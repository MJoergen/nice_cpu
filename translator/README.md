# nicewasm

Translates a WebAssembly module into NICE assembly, following the
WebAssembly mapping in [WASM.md](WASM.md).
It is one Python 3 script with no dependencies beyond the standard library.
The [WebAssembly specification](https://webassembly.github.io/spec/core/)
defines the module format and what each instruction does.

It supports the features listed below, which cover what clang, Zig, and
Rust emit for their default wasm32 targets (see Target). It rejects
anything else with an error, rather than translating it wrongly.
[DESIGN.md](DESIGN.md) says how it translates a function and allocates
the registers, for whoever changes `nicewasm.py`.

- [Quick start](#quick-start)
- [Usage](#usage): [nicewasm](#nicewasm), [nicebuild](#nicebuild), and
  [what nicebuild runs](#what-nicebuild-runs)
- [Target](#target)
- [Supported features](#supported-features)
- [Library modules](#library-modules)
- [Test](#test)

## Quick start

`nicebuild.py` builds a C, Zig, or Rust source file into a `.bin` file,
and the emulator runs it. Build the emulator once with `make -C emulator
build`. Then, from the top of the repository:

    translator/nicebuild.py -o hello.bin hello.c
    emulator/zig-out/bin/niceemu hello.bin

`hello.c` is any C program with a `main`, such as:

    #include <stdio.h>

    int main(void)
    {
        printf("Hello, NICE\n");
        return 0;
    }

A Zig program prints through the module `nice`, `runtime/nice.zig`, which
`nicebuild.py` gives it, and a Rust program through `runtime/nice.rs`,
which it mounts itself ([runtime README](../runtime/README.md#zig-and-rust)):

    // hello.zig
    const nice = @import("nice");

    export fn main() i32 {
        nice.print("Hello, NICE\n", .{});
        return 0;
    }

    // hello.rs
    #![no_std]
    #[path = "runtime/nice.rs"]
    mod nice;

    #[no_mangle]
    pub extern "C" fn main() -> i32 {
        println!("Hello, NICE");
        0
    }

    #[panic_handler]
    fn panic(_: &core::panic::PanicInfo) -> ! {
        core::arch::wasm32::unreachable()
    }

What you get:

- The console of SYSTEM.md §1: `printf` and `putchar` write to it, and
  `getchar` and `scanf` read from it. On the emulator, that is stdout and
  stdin, or the file of `--input`.
- The program ends when `main` returns or calls `exit`. The processor
  halts with the result in R1, and the emulator exits with status 0.
- A wasm trap, such as an access out of bounds or a failed `assert`,
  prints a line such as `trap 2: memory access out of bounds at 00000048`
  and halts the processor. The emulator exits with status 2. Built with
  `--symbols`, `niceemu --symbols hello.sym hello.bin` also names the
  function.
- C has an 8-bit `char`, and its memory is wasm's byte-addressed linear
  memory, as the compiler's wasm32 target gives. The one-word `char` of
  ABI.md is for hand-written assembly and a compiler that targets NICE
  directly.

## Usage

### nicewasm

    ./nicewasm.py [-o output.nasm] [--no-bounds-checks] [--trust-alignment] [--byte-windows]
                  [--memory-pages N] [--ram ADDR [--ram-bytes BYTES]]
                  [--library NAME [--library-memory BYTES]] [--no-mpu] [--inline-fpu]
                  input.wasm

| Option | Effect |
|---|---|
| `-o FILE` | Write the assembly to FILE. Without it, the output goes to `input.nasm`. |
| `--no-bounds-checks` | Leave out the bounds checks on memory accesses, as WASM.md allows. The code is then smaller and faster, but an access out of bounds reads or writes whatever NICE memory the address reaches. |
| `--trust-alignment` | Take an access of 4 or 8 bytes whose alignment hint is 4 bytes or more to be at a multiple of 4, without the test of DESIGN.md, as WASM.md allows. The code is then smaller and faster, mostly without bounds checks, but a misaligned access reads or writes the word that holds its first byte. With `--byte-windows`, it also takes an access of 2 bytes whose hint is 2 to be at a multiple of 2. The hint is exact in the code of clang, Zig, and rustc. |
| `--byte-windows` | Access the memory through the byte windows of [SYSTEM.md §9](../doc/SYSTEM.md#9-byte-windows), so that a byte load or store is one `MOVE` (see DESIGN.md). Halfwords take a window with `--trust-alignment` and the hint 2, and words with the hint 4 or when the address is known to be at a multiple of 4. The program then runs only on a system that has the windows, such as the emulator, and the memory must lie in words below `0x04000000`: nicewasm refuses a memory of more than 4096 pages, checks where the memory lies with `--ram`, and otherwise has `___wasm_start` check it and trap with code 8 if it lies beyond. |
| `--memory-pages N` | Let `memory.grow` grow the memory up to N pages, the cap of WASM.md. N may not be below the memory's initial size or above its maximum, if it declares one, and it must be below 65536. Without the option, the cap is the initial size. |
| `--ram ADDR` | For code that runs from a ROM: put the words that the module writes in RAM from ADDR, a NICE address in decimal or with `0x` (see [Code in a ROM](#code-in-a-rom)). Not with `--library` or `--memory-pages`. |
| `--ram-bytes BYTES` | With `--ram`, the size of the memory in RAM (see Code in a ROM). |
| `--library NAME` | Translate a library module instead (see [Library modules](#library-modules)). |
| `--library-memory BYTES` | With `--library`, the size of the library's memory (see Library modules). |
| `--no-mpu` | For a system without the math unit of SYSTEM.md §2: `i32.mul`, and `div` and `rem` of both widths, then call the runtime library instead of using the math unit, and the program must be joined with `runtime/muldiv_soft.nasm`, not `muldiv_mpu.nasm`. |
| `--inline-fpu` | For speed on a system with the FPU of SYSTEM.md §11: write the FPU's accesses inline for the float operations, as `runtime/float_fpu.nasm` makes them, instead of calling it (WASM.md, Runtime routines). The conversions of an `i64` to `f32` still call it, and the program must be joined with it, which also names the FPU's words. On `bench/float.c`, the program takes 2.6% more words, and runs 53% fewer instructions and an estimated 54% fewer cycles (bench README, The float benchmark). |

Errors are printed as `file:0xOFFSET: error: message`, where OFFSET is the
byte offset in the module, or as `file: error: message` when there is no
offset. nicewasm stops at the first error. An input that cannot be read
prints `file: message`, such as `file: No such file or directory`, an
output that would overwrite the input prints `file: the output file would
overwrite the input; use -o`, and an output file that cannot be written
prints `file: message` too, all without `error:`. The exit status is 1
after an error, and no output is written; a mistake in the options exits
with 2, as argparse does.

### nicebuild

`nicebuild.py` does all of the steps of [What nicebuild runs](#what-nicebuild-runs):
it compiles the sources, translates, joins, and assembles. The extension
of the inputs picks the language: `.c`, `.zig`, or `.rs`.

    ./nicebuild.py [-o output.bin] [-O LEVEL] [-I DIR] [-D MACRO[=VALUE]]
                   [--stack BYTES] [--memory BYTES] [--no-mpu] [--no-fpu] [--inline-fpu]
                   [--no-bounds-checks]
                   [--trust-alignment] [--byte-windows] [--memory-pages N] [--asm FILE]...
                   [--no-trap-report] [--monitor] [--ram ADDR [--ram-bytes BYTES]]
                   [--symbols] [--keep]
                   input.c... | input.zig | input.rs

| Option | Effect |
|---|---|
| `-o FILE` | Write the program to FILE. Without it, the output is the first input with the extension `.bin`. |
| `-O LEVEL` | A clang level for C, a mode for Zig such as `ReleaseSafe`, and an `opt-level` for Rust. |
| `-I DIR`, `-D MACRO[=VALUE]` | For C: an include directory, and a macro. |
| `--stack BYTES` | The stack size, 4096 by default, or 16384 for Zig in Debug or ReleaseSafe. It must be positive. |
| `--memory BYTES` | The initial memory, 65536 by default. It must be positive. The stack is in the memory, so a larger `--stack` needs a larger `--memory` too: `--stack 131072` alone fails with wasm-ld's "initial memory too small", and `--memory 262144` fixes it. |
| `--no-mpu`, `--inline-fpu`, `--no-bounds-checks`, `--trust-alignment`, `--byte-windows`, `--memory-pages N` | Passed on to `nicewasm.py` (above). With `--no-mpu`, the program is joined with `muldiv_soft.nasm`. |
| `--no-fpu` | For a system without the FPU of SYSTEM.md §11: join the float library in software, `runtime/float.nasm`, instead of `runtime/float_fpu.nasm`. Not with `--inline-fpu`. |
| `--asm FILE` | Join a NICE assembly file after the program, so that the program can call a function that the file defines, as the label `_name` of ABI.md; for C it also lets the link leave the function undefined. The option can repeat. |
| `--no-trap-report` | Leave out the trap report, so that a trap halts silently (see below). |
| `--monitor` | Build a program for a monitor in ROM, which loads it at `0x8000` and calls it, and to which it returns (ABI.md, "Programs under a monitor"): the start-up code is `runtime/start_wasm_trap_mon.nasm`, or `start_wasm_mon.nasm` with `--no-trap-report`, and the `.bin` file starts at `0x8000`. The monitor's own routines, if the program calls them, come as stubs in a file of the monitor's, joined with `--asm`. |
| `--ram ADDR` | Build a program whose code runs from a ROM, as nicewasm's `--ram ADDR` does (see [Code in a ROM](#code-in-a-rom)): the words that it writes are in RAM from ADDR, and `___wasm_start` gives them their initial values. The module is linked with `--export=__heap_base`, so that nicewasm reserves the memory up to the end of the static data. The start-up code is the same as without the option, and the `.bin` file starts at 0, for a ROM there. With `--no-fpu`, a program that uses floats is an error, since the float library in software keeps its words in the image. Not with `--monitor` or `--memory-pages`. |
| `--ram-bytes BYTES` | With `--ram`, passed on to `nicewasm.py`. |
| `--symbols` | Also write the labels to `output.sym`, with the functions of the program by their names, for `niceemu --symbols`, which then names the function of a trap. A Zig program is then built with `-fno-strip`, because ReleaseSmall leaves the names out of the wasm; the `.bin` is the same. |
| `--keep` | Leave the `.wasm`, `.nasm`, and joined `.full.nasm` files next to the output. |

C files are linked with the C library, and Zig gets `runtime/nice.zig` as
the module `nice`. Zig and Rust take one source file, the root of the
program, and a Rust program that wants `nice.rs` mounts it itself (runtime
README). The float library is joined if the program calls it:
`runtime/float_fpu.nasm`, which uses the FPU of SYSTEM.md §11, or with
`--no-fpu` `runtime/float.nasm`, in software. A wasm trap
writes a line with its code and address to the console before the
processor halts, as `trapmsg.nasm` of the runtime README does, unless
`--no-trap-report` leaves the report out. The defaults are the options of
the recipes below, but for `-Wl,--allow-undefined`, which only `--asm`
adds. The script builds `runtime/libc/libc.a`, and `runtime/float.nasm`
with `--no-fpu`, first if needed. `CLANG`, `ZIG`, and `RUSTC` in the environment name the
compilers. If the compiler of the language is not installed, the script
says so and exits with status 1. It also checks the output directory and
the `--asm` files before it compiles. A step that fails ends the script
with "nicebuild: NAME failed with status N", where NAME is the compiler or
the Python script.

### What nicebuild runs

The output of nicewasm is one assembly file. A program is made by joining
it with the start-up code, the program's other files, and the runtime
library, in the order of the [runtime README](../runtime/README.md#joining-a-program).
These are the steps, and the compiler options that `nicebuild.py` uses.
For C code compiled with clang:

    clang --target=wasm32 -mbulk-memory -mtail-call -O2 -nostdlib -Wl,--no-entry -Wl,--export=main \
        -Wl,--allow-undefined -Wl,--stack-first -Wl,-z,stack-size=4096 \
        -Wl,--initial-memory=65536 -o prog.wasm prog.c
    translator/nicewasm.py prog.wasm
    cat runtime/start_wasm.nasm prog.nasm runtime/lib.nasm runtime/muldiv_mpu.nasm > full.nasm
    assembler/niceasm.py full.nasm
    emulator/zig-out/bin/niceemu full.bin

`-mbulk-memory` matters. Without it, clang turns every copy or fill that
it does not inline, such as the assignment of a large structure, into a
call to `memcpy`, `memset`, or `memmove`. With `-nostdlib`, these become
imports from `env`, and the assembler stops with `undefined symbol
'_memcpy'`. A C routine could not serve them anyway, since they take byte
addresses in linear memory. With `-mbulk-memory`, clang emits
`memory.copy` and `memory.fill` instead.

`-mtail-call` lets clang emit `return_call`. Without it, clang rejects
a `[[clang::musttail]]` call that it cannot turn into a loop, and Zig
rejects `@call(.always_tail, ...)`, so nicebuild turns the feature on
for all three compilers. They then also emit `return_call` for an
ordinary call just before a return, which nicewasm would turn into a
tail call anyway ([DESIGN.md](DESIGN.md)).

`-Wl,--stack-first` matters too. The program's own stack, which clang
keeps in linear memory for the variables whose address is taken and for
the arguments of variadic calls, is not checked for overflow, as WASM.md says. By default wasm-ld puts it above the data, so a function whose
frame does not fit in `-z stack-size` overwrites the data, and the
program misbehaves somewhere else later. With `--stack-first`, the stack
is at the bottom of the memory, so an overflow wraps the address below 0
and the bounds check traps with code 2 at once. Zig and rustc put the
stack first by default. A `main` with hundreds of `printf` calls needs
more than 4 KB, since clang gives each call its own argument area.

C's `long double` and `__int128` are not supported. Clang implements them
with calls to routines such as `__addtf3` and `__multi3`, which the
runtime library does not have, and nicewasm rejects the imports. Zig's
`f128` and `u128` work, because Zig puts its compiler_rt in the module.

For `printf`, `strlen`, `malloc`, and the like, compile and link with the
small C library in `runtime/libc/`. Its section in the
[runtime README](../runtime/README.md#c-library) gives the command line.
Zig and Rust code prints, reads the console, and uses the other device
routines with `runtime/nice.zig` and `runtime/nice.rs`
([runtime README](../runtime/README.md#zig-and-rust)).

If the program has constructors, also link with
`-Wl,--export=__wasm_call_ctors`, so that `___wasm_start` runs them once
(WASM.md). Without it, wasm-ld runs them again before each call of an
exported function.

And for Zig:

    zig build-exe -target wasm32-freestanding -mcpu=generic+tail_call -fno-entry -rdynamic \
        -O ReleaseSmall -fstrip --stack 4096 --initial-memory=65536 prog.zig

ReleaseSafe and Debug work too. They need `--stack 16384`, or at least
more than 4096, if the program can panic: Zig's panic handler puts a
4 KB buffer on the stack, and with too small a stack it traps with code
2, out of bounds, before it reaches its own trap. `test/safe.zig` is
about 5900 words built with ReleaseSafe, and about 11900 built with
Debug.

`-fstrip` drops the DWARF sections, which make up almost all of a
ReleaseSafe or Debug module. nicewasm ignores them, but they make the
file large. Use the LLVM backend, the default: no test here covers
Zig's own wasm backend (`-fno-llvm`).

The memory options keep the memory small. nicewasm reserves the module's
initial memory with `.RES`, so the memory is not in the `.bin` file, and
`___wasm_start` sets it to 0. Only the words that data segments set are in
the `.bin` file. That takes 18 steps for every 16 words, or
18434 steps for one page. The emulator runs about 70 million steps per
second, so even Zig's default of 16 pages, or 17 with data, is cleared
in a few milliseconds. The real cost is space: each page is 16384 words, which an
FPGA system with little RAM may not have. Without the options, clang asks
for 2 pages and Zig for 16 or more.

And for Rust, with the wasm32 target installed (`rustup target add
wasm32-unknown-unknown`):

    rustc --target wasm32-unknown-unknown --crate-type cdylib -C opt-level=s \
        -C panic=abort -C target-feature=+tail-call -C strip=debuginfo \
        -C link-arg=-zstack-size=4096 -C link-arg=--initial-memory=65536 prog.rs

Use `#![no_std]`, which keeps the module small. It needs a panic
handler, such as one that calls `core::arch::wasm32::unreachable()`.
That traps with code 1. `main` is `#[no_mangle] pub extern "C" fn main()
-> i32`. rustc does not wrap it, so `_main` is that function. An `extern
"C"` block needs `#[link(wasm_import_module = "env")]`, or rustc fails
to link its functions; with the attribute, they are imports from `env`.
With Cargo, the crate type is `cdylib`, the profile sets `panic =
"abort"`, and the `-C link-arg` options go in `rustflags` in
`.cargo/config.toml`. Other opt-levels work too, and so do `-C
overflow-checks` and `-C debug-assertions`.

## Target

nicewasm aims at the default wasm32 feature set of Zig 0.17:
`bulk-memory-opt`, `call-indirect-overlong`, `extended-const`,
`multivalue`, `mutable-globals`, `nontrapping-fptoint`, and `sign-ext`.
Clang's default set, `mutable-globals` and `sign-ext`, is a subset of it,
and so is the set with `-mbulk-memory`. Rust's default set adds all of
`bulk-memory` and `reference-types`. Of those, rustc emits only
`memory.copy`, `memory.fill`, and the `call_indirect` encoding, unless
the program uses threads or `externref`. nicewasm rejects the rest, such
as `memory.init` and `table.get`, with an error. A module built with
`-mcpu=mvp` needs none of them. nicewasm also supports `tail-call`,
which no default set has, and which nicebuild turns on. Of the `0xFC` instructions, nicewasm
supports `memory.copy` and `memory.fill` of `bulk-memory-opt`, and the
`trunc_sat` conversions of `nontrapping-fptoint`. It decodes the others,
such as the table instructions, only to name them in an error. It accepts
only a constant instruction as a global's initial value, not the
expressions of `extended-const`.

Every Zig program built with ReleaseSafe or Debug uses a table,
`call_indirect`, `br_table`, `select`, `memory.copy`, and `memory.fill`,
and it traps with `unreachable`, even if its source has no function
pointers. nicewasm supports all of them. A Rust program uses a table and
`call_indirect` for `dyn` trait calls.

The optimizations change nothing in WASM.md. The size of translated code
is measured in words (`make words` in `bench/`): `test/safe.zig` is 5903
words and the float library in software 6578; with the FPU it is 289. The benchmark of [bench/](../bench/)
runs 1652811 instructions in its phases, from a module of 11523 words,
3085 of them the float conversions of the C library's `printf`.
[doc/review/code-size-plan.md](../doc/review/code-size-plan.md) has the
measurements of the plan, and [doc/HISTORY.md](../doc/HISTORY.md) lists
the steps that got the code here.

## Supported features

- **Types:** `i32`, `i64`, `f32`, and `f64`, in function types, locals,
  and globals. An `i64` or `f64` takes
  two words, low word first, and is passed in registers or on the stack by
  the rules of ABI.md. A float value is its bits, as in memory.
- **Floats:** every `f32` and `f64` instruction. `const`, `load`, `store`,
  and `reinterpret` move the bits, and `abs`, `neg`, and `copysign` change
  the sign bit inline. Everything else calls the float library, or with
  `--inline-fpu` most of it writes the FPU's accesses inline,
  `runtime/float_fpu.nasm` or, on a system without the FPU,
  `runtime/float.nasm`, so a program that uses floats must be joined with
  one (runtime README, Joining a program). `float.nasm` is generated; `make -C runtime float.nasm` builds it. `trunc` traps with code 5 for a NaN or a
  value whose integer part does not fit, and `trunc_sat` saturates
  instead.
- **Control:** `block`, `loop`, `if`, `else`, `end`, `br`, `br_if`,
  `br_table`, `return`, `call`, `unreachable`, and `nop`. A block type may
  be a function type, with parameters and several results.
- **Instructions:** `drop`, `select` (both forms), `local.get`,
  `local.set`, `local.tee`, `global.get`, `global.set`, `i32.const`,
  `i64.const`, `i32.wrap_i64`, `i64.extend_i32_s`, and `i64.extend_i32_u`.
- **Traps:** `unreachable` traps with code 1 through
  `___wasm_trap_vector`, as WASM.md says. Each trap sets R2 and jumps to a
  helper for its code, such as `W.trap1`, which sets R1 and jumps through
  the vector. So a trap takes four words, not six.
- **Integer operations,** for `i32` and `i64`: `add`, `sub`,
  `mul`, `div_s`, `div_u`, `rem_s`, `rem_u`, `and`, `or`, `xor`, `clz`,
  `ctz`, `popcnt`, and the `sign-ext` instructions `extend8_s`,
  `extend16_s`, and `i64.extend32_s`. `i32.mul`, and `div` and `rem` of
  both widths, write their operands to the math unit of SYSTEM.md §2 and
  read the result, in three instructions for `i32` and six for `i64`,
  through the labels `__mpu.a` and the like that `runtime/muldiv_mpu.nasm`
  defines. With `--no-mpu` they call `__mul`, `__div64`, and the like
  instead. `i64.mul`, except by a constant (below), and the bit counts
  always call the runtime library, for example `__mul64` and `__popcnt` (see
  [runtime/README.md](../runtime/README.md)). Division by 0
  traps with code 3, and `div_s` of the most negative number by −1 with
  code 4. `rem_s` by −1 is 0 without a division, because C leaves the most
  negative number % −1 undefined. A divisor that is a constant other
  than 0 and −1 needs none of these checks, and an unsigned `i32`
  division or remainder by a power of 2 is a `SHR` or an `AND`.
- **Multiplication by a constant:** an `i32.mul` by a constant is at
  most three shifts, additions, and subtractions, if that many will do,
  so x × 31 is `SHL t, x, 5` and `SUB d, t, x`; by any other constant it
  uses the math unit, or with `--no-mpu` calls `__mul`. An `i64.mul` by a
  constant takes at most three products of the math unit, or with
  `--no-mpu` calls `__mul64` ([DESIGN.md](DESIGN.md), Multiplication by a
  constant).
- **Comparisons:** `eqz`, `eq`, `ne`, `lt`, `gt`, `le`, and `ge`, signed
  and unsigned, for `i32` and `i64`.
- **Shifts:** `shl`, `shr_s`, `shr_u`, `rotl`, and `rotr`, for `i32` and
  `i64`.
- **Memory instructions:** every `i32` and `i64` load and store, at any
  byte address, and `memory.size`. An access out of bounds traps with
  code 2. `memory.grow` returns the old size, or -1 if the memory would
  pass its cap (`--memory-pages`), and sets the new pages to 0. At the
  cap, only growing by 0 pages succeeds, and the bounds checks compare
  with constants; below it, with words that `memory.grow` keeps up to
  date (DESIGN.md).
- **Bulk memory:** `memory.fill` and `memory.copy`, whose ranges may
  overlap. Both check their ranges before they write a byte, and trap with
  code 2 if a range passes the end of the memory. Each calls a function
  that nicewasm emits once, `W.fill` or `W.copy`, which works a word at a
  time where it can.
- **Imports:** functions from `env`, whose names must be C identifiers
  that do not start with `_` (WASM.md). Each becomes a call to the
  label `_name`.
- **Hardware access:** `nice.peek`, of type `(i32) -> i32`, and `nice.poke`,
  of type `(i32, i32) -> ()`, as WASM.md says. Each call makes exactly
  one data access, a `MOVE` that reads or writes the NICE word at the given
  word address, after the code that puts the address in a register. A
  `peek` whose result is not used still makes its access. So `poke(0xFFFFFF00, c)` prints `c` on
  the console (SYSTEM.md §1). They have no address, so they cannot be in a
  table.
- **Exports:** functions and globals get the label `_name`, as WASM.md says.
  A name that is not a C identifier gets no label, in a library module
  too, and in a program a name that starts with `_` gets none either. Exports of the memory and of the table are ignored: the memory is at
  `___wasm_memory`, and a function pointer is a table index. So the
  `memory` export that Zig always emits does no harm. An export of a memory
  or table that the module does not have is an error. Exporting an imported
  function is not supported, and an export may not have the name of an
  `env` import, because the call to the import goes to the same label
  `_name`.
- **Globals:** mutable or not, with an `i32.const`, `i64.const`,
  `f32.const`, or `f64.const` initial value. `global.set` on an immutable
  global is an error, and so is a mutability byte other than 0 or 1.
- **Memory:** one memory at `___wasm_memory`, with words reserved up to
  the cap. A memory's or a table's minimum size above its maximum is an error, and so
  is a memory of more than 65536 pages. A function imported twice with different
  types is an error.
- **Data segments:** active ones, whose offset is an `i32.const`. The words
  they set are `.DAT` words in the program image, and a word that a
  segment sets only part of has its other bytes 0. A later segment
  overwrites an earlier one, as in wasm. The rest of the memory is
  reserved with `.RES`. A segment that does not fit in the memory is an
  error.
- **Start-up:** `___wasm_start` sets the memory to 0, except the words
  that data segments set. Then it calls the start function, if there is
  one, and `__wasm_call_ctors`, if it is exported.
- **Tables:** table 0 of `funcref`, filled by active element segments
  whose offset is an `i32.const`. Their elements may be function indices
  or `ref.func` and `ref.null` expressions. nicewasm emits the table at
  `W.table`, two words to an entry as WASM.md says: the function's
  address and its type number, the index of the first type with the same
  parameters and results. Declarative segments are ignored.
- **Indirect calls:** `call_indirect`. An index past the end of the table
  and an empty entry trap with code 6, and an entry of another type with
  code 7.
- **Tail calls:** `return_call` and `return_call_indirect`, with the
  checks of `call_indirect`. The stack arguments go into the function's
  own, the frame goes, and the saved registers are restored, and then a
  jump goes to the callee, as WASM.md says. A callee with more words of
  stack arguments than the function is called instead, and its results
  returned, so the stack then grows by a frame. A callee whose results
  differ from the function's is an error.
- **Ignored:** custom sections. The
  name section only supplies function names for comments. A name that is
  not printable ASCII is left out, and so is any such character in the
  input file's name, so that a comment cannot become code.

Not supported, and not planned
([decisions](../doc/review/decisions.md)): function types with more
than one result (a block type may have several), passive data and
element segments, `memory.init`, `data.drop`, the table instructions
such as `table.get` and `table.grow`, `ref.func` outside element
segments, `ref.null`, `ref.is_null`, SIMD, and exceptions.

nicewasm checks the types on the operand stack as wasm validation does,
so an invalid module is an error, not wrong code. Code that cannot be
reached, such as the code after a `br` up to the end of its block, is
decoded but not checked, and nicewasm emits nothing for it. Two exports with the
same name are an error too, and so is a `__wasm_call_ctors` with
parameters or results.

## Library modules

`--library NAME` translates a library module of the runtime library, as
WASM.md describes. The float library is one: see
[runtime/README.md](../runtime/README.md). It differs from a program's
module in these ways:

- The labels nicewasm makes start with `WL.NAME.`, and its memory is at
  `WL.NAME.memory`. Every exported function gets the label `_name`, also
  when the name starts with `_`, so `__addsf3` becomes `___addsf3`.
- There is no `___wasm_start`, and a start function, an export
  `__wasm_call_ctors`, `memory.size`, and `memory.grow` are errors. So is any float instruction that would call the
  float library, which a library module could be part of.
- Only the start of the memory is reserved, and it is part of the program
  image, with the data segments in it. By default, that is up to the end of
  the last data segment or the highest initial value of a mutable `i32`
  global, which for compiler output is the stack pointer. With
  `--library-memory BYTES`, it is BYTES, which may not be negative, rounded up to a word. An access
  past it traps with code 2.

## Code in a ROM

`--ram ADDR` translates a program's module whose code runs from a ROM,
as WASM.md describes under Code in a ROM. The words that the module
writes go in RAM, and the rest stays in the image:

- The mutable globals are at ADDR and up, and the memory follows them.
  `W.gN`, the labels of exported globals, and `___wasm_memory` are `.EQU`
  names of their addresses, and `___wasm_ram_end` is the word after the
  last. The immutable globals stay in the image.
- `W.init` in the image holds the initial values: those of the mutable
  globals, and the words that data segments set. `___wasm_start` copies
  them to RAM and sets the rest of the memory to 0, in one pass from
  ADDR up, before it calls the start function and `__wasm_call_ctors`.
  The system calls it at every start.
- Only the start of the memory is reserved. By default, that is up to
  the end of the last data segment, the highest initial value of a
  mutable `i32` global, or the value of the global `__heap_base`,
  whichever is highest. wasm-ld puts the static data that is 0 at the
  start, such as C's `.bss`, in no data segment, and ends it at
  `__heap_base`, so the module must export that global: link with
  `--export=__heap_base`, as `nicebuild.py --ram` does. Without it, give
  `--ram-bytes BYTES`, which may not be negative, rounded up to a word.
  An access past the reserved part traps with code 2, unless the bounds
  checks are left out.
- `memory.size` and `memory.grow` are errors, so the C library's
  `malloc` is not available.
- The words must fit below 2³²: ADDR plus their number may not pass it.
  Whether they fit in the system's RAM is for the system to check, with
  `___wasm_ram_end`.

The runtime library's start-up files hold the vectors that it jumps
through (ABI.md, Start-up), so a system that runs the code from a ROM
has start-up code of its own, which puts them in its RAM.

## Test

    make test        # run the test modules, then test/fuzz.py, test/passes.py, test/errors.py, and test/build.py
    make typecheck   # mypy --strict
    make wasm        # rebuild test/*.wasm from test/*.c, test/*.zig, and test/*.rs
    make diff        # compare with an older translator, OLD=main, on random modules (minutes)

`test/run.py` translates each test module and joins it with the runtime.
It then assembles and runs the program. Each case runs three times:
with the math unit and the float library of the FPU, `float_fpu.nasm`,
with `--no-mpu`, `muldiv_soft.nasm`, and `float.nasm`, for a system with
neither, and with `--inline-fpu`. It checks main's result in R1,
that R7–R13 are unchanged unless it trapped, what it printed on the
console, and that the memory is not in the `.bin` file. A case for
code in a ROM, translated with `--ram`, must also leave every word of
the image as it was, and its `___wasm_ram_end` must be as worked out by
hand. A case that
traps must instead halt at `___wasm_trap` with the trap code in R1, and
R2 at the start of the code that trapped. Most modules are built byte by
byte with `test/wasm.py`. The others are compiled from `test/*.c`,
`test/*.zig`, and `test/*.rs`. Their `.wasm` files are checked in, so
`make test` needs no compiler. `make wasm` needs clang with the wasm32
target, `wasm-ld`, Zig 0.17, and rustc with the `wasm32-unknown-unknown`
target. The Rust modules were built with rustc 1.99.0. `test/errors.py`
checks every error message. `test/build.py` runs `nicebuild.py`: the
mistakes in its options, and then a program in each language whose
compiler is installed. `abort.c` of the C library's tests is built with
`--symbols` and `--keep`, and its run must print the trap report and the
emulator's name of the trap, `abort`; built with `--no-trap-report`, it
must halt without the report. `exit.c` is built with `--monitor`, with
and without the trap report, and run after the runtime's stand-in for a
monitor, `runtime/test/monitor.nasm`, assembled on its own and put before
it in one `.bin` file: its output must come through the stand-in's putc
routine, and `exit` must return to the stand-in, which halts with the
status in R1. `hello.zig` is built with and without
`--symbols`, which must give the same `.bin`, and `hellors.rs` with it.
A Zig program that prints through `nice.zig` is built with `--monitor`
too, and its output must come through the stand-in's putc routine.
Every `.sym` file must name every function. A language whose compiler is
missing is skipped, and the PASS line says which; CI has Zig and clang, not Rust.
`test/run.py --keep DIR` also leaves each
program in `DIR/X.bin`, `DIR/X_soft.bin` for the run with `--no-mpu`, or
`DIR/X_inline.bin` for the run with `--inline-fpu`, for `make programs`
in `hdl/`, which runs them on the FPGA core, with the FPU.
`test/run.py`, `test/fuzz.py`, and `test/errors.py` run their cases in
parallel, one per CPU, each with files of its own, and report them
in order.

`test/fuzz.py FIRST COUNT` builds random modules from a syntax tree
whose nodes also evaluate themselves in Python, so each module comes
with the result that wasm defines for it, and `main`'s result in R1 must
match, or if the module traps, the program must halt at `___wasm_trap`
with the trap code in R1. The linear memory at the halt must match the
model's too, word for word. It starts with a pattern in which no two
words are alike, so an access at the wrong word gets a value of its own.
The modules have four functions with `i32` and
`i64` parameters, 8 to 13 locals, loops, blocks, and ifs whose block
types may have parameters and several results, branches that carry no
value, one, or several, `br_table` among them, `return`, `nop`, both
forms of `select`, calls through the table, tail calls, every integer
operation and comparison, the results of comparisons kept in locals for
later conditions, mutable and immutable globals, loads and stores of
every width at constant and dynamic addresses, the addresses of array
elements as `(i << s) + c`, among them, at the start of `main`, loads
and stores whose index has high bits that the shift drops, so that the
address wraps modulo 2^32, groups of word accesses at offsets from one
address, and `memory.fill` and `memory.copy`. That covers the rules for
deferred values, fused comparisons, the flags, forwarded results, and
register allocation of DESIGN.md. In 40% of the modules, statements may trap:
`unreachable`, divisions by 0 and of the most negative value by −1,
`call_indirect` past the table or of the wrong type, and accesses,
`memory.fill`, and `memory.copy` past the end of the memory. About a
fifth of the modules trap. The modes of nicewasm are `--no-mpu`,
`--unchecked` for `--no-bounds-checks`, whose modules make no access out
of bounds, `--grow` for `--memory-pages 2`, and `--trust` for
`--trust-alignment` with `--no-bounds-checks`, whose modules give the
alignment hint 4 to each access of 4 or 8 bytes at an address known to
be a multiple of 4, and `--windows` for `--byte-windows` with
`--trust-alignment` and the bounds checks, with the hints of `--trust`.
`make test` runs 40 seeds with the math unit, 40
with `--no-mpu`, and 20 each with `--unchecked`, `--grow`, `--trust`,
and `--windows`, and says how many of them trap;
`test/fuzz.py 1 1000` runs more, and `test/fuzz.py --reduce SEED 1`
shrinks a failing module and writes it with its translation. With `--keep DIR`, `fuzz.py` copies each program to
`DIR/fuzzSEED.bin`, with the mode added to the name, for `make programs` in `hdl/`.

`test/passes.py` runs some of the passes over a function's code on code
built by hand: `hoist_into_slots` after the write of an address
register, `tail_calls` with data between the call and the return,
`duplicate_tails` in the stubs, and `early_exit` with a test that writes
a saved register and with a call in the code that the jump goes to.
These are rules that no module reaches today, so `run.py` and `fuzz.py`
cannot test them.

`make diff` compares the translator with an older version of itself,
`OLD`, a git revision, `main` by default: `test/diff_fuzz.py` translates
random modules with both, runs both programs, and compares the console
output, the halt reason, the exit status, R1, R7 to R13, and every word
of the linear memory. The modules are `fuzz.py`'s, without the tail calls,
which a version before them rejects, and, with `--trap`,
the same with statements that may trap: accesses out of bounds,
divisions by zero and of the most negative value by −1, bad
`call_indirect`s, `memory.fill` and `memory.copy` past the end,
`unreachable`, and `memory.grow`. So it checks a trap's R2, and
`memory.grow`, which `fuzz.py`'s model does not know, and each mode of
the translator. It is not part of `make test`, since it takes minutes and needs git.
