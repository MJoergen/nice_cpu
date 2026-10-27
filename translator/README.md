# nicewasm

Translates a WebAssembly module into NICE assembly, following the
WebAssembly mapping in [WASM.md](WASM.md).
It is one Python 3 script with no dependencies beyond the standard library.
The [WebAssembly specification](https://webassembly.github.io/spec/core/)
defines the module format and what each instruction does.

It supports the features listed below, which cover what clang, Zig, and
Rust emit for their default wasm32 targets (see Target). It rejects
anything else with an error, rather than translating it wrongly.

## Usage

    ./nicewasm.py [-o output.nasm] [--no-bounds-checks] [--memory-pages N]
                  [--library NAME [--library-memory BYTES]] [--no-mpu] input.wasm

Without `-o`, the output goes to `input.nasm`. `--no-bounds-checks` leaves
out the bounds checks on memory accesses, as WASM.md allows. The code
is then smaller and faster, but an access out of bounds reads or writes
whatever NICE memory the address reaches. `--memory-pages N` lets
`memory.grow` grow the memory up to N pages, the cap of WASM.md. N
may not be below the memory's initial size or above its maximum, if it
declares one, and it must be below 65536. Without the option, the cap is
the initial size. `--library` translates a library module instead, as
described below. `--no-mpu` is for a system without the math unit of
SYSTEM.md §2: `i32.mul`, and `div` and `rem` of both widths, then call
the runtime library instead of using the math unit, and the program must be joined with
`runtime/muldiv_soft.nasm`, not `muldiv_mpu.nasm`. Errors are printed as
`file:0xOFFSET: error: message`, where OFFSET is the byte offset in the
module, or as `file: error: message` when there is no offset. An input
that cannot be read prints `file: message`, such as `file: No such file
or directory`, and an output that would overwrite the input prints
`file: the output file would overwrite the input; use -o`, and an output file that cannot be written prints `file: message` too, all without
`error:`. The exit status is 1 after an error, and no output is written; a
mistake in the options exits with 2, as argparse does.
nicewasm stops at the first error.

`nicebuild.py` does all of the steps below: it compiles the sources, translates,
joins, and assembles. The extension of the inputs picks the language: `.c`,
`.zig`, or `.rs`.

    ./nicebuild.py [-o output.bin] [-O LEVEL] [-I DIR] [-D MACRO[=VALUE]]
                   [--stack BYTES] [--memory BYTES] [--no-mpu] [--no-bounds-checks]
                   [--memory-pages N] [--asm FILE]... [--no-trap-report] [--symbols]
                   [--keep] input.c... | input.zig | input.rs

Without `-o`, the output is the first input with the extension `.bin`.
The defaults are the options of the recipes below, but for `-Wl,--allow-undefined`,
which only `--asm` adds. `-O` is a clang level
for C, a mode for Zig such as `ReleaseSafe`, and an `opt-level` for
Rust. `--stack` and `--memory` set the stack size and the initial memory;
the default stack is 4096 bytes, or 16384 for Zig in Debug or ReleaseSafe.
The stack is in the memory, whose default is 65536 bytes, so a larger
`--stack` needs a larger `--memory` too: `--stack 131072` alone fails with
wasm-ld's "initial memory too small", and `--memory 262144` fixes it.
`--stack` and `--memory` must be positive.
`--asm FILE` joins a NICE assembly file after the program, so that a C, Zig, or
Rust program can call a function that the file defines, as the label
`_name` of ABI.md; for C it also lets the link leave the function undefined.
With it the program can call hand-written assembly. The option can repeat.
`-I` and `-D` are for C. C files are linked with the C library, and Zig
gets `runtime/nice.zig` as the module `nice`. Zig and Rust take one source file,
the root of the program, and a Rust program that wants `nice.rs` mounts it
itself (runtime README). The float library
is joined if the program calls it. A wasm trap writes a line with its code and
address to the console before the processor halts, as `trapmsg.nasm` of the
runtime README does; `--no-trap-report` leaves it out, so that a trap halts
silently. `--symbols` also writes the labels to `output.sym`, with the
functions of the program by their names, for `niceemu --symbols`, which then
names the function of a trap. A Zig program is then built with `-fno-strip`,
because ReleaseSmall leaves the names out of the wasm; the `.bin` is the
same. `--keep` leaves the `.wasm`, `.nasm`,
and joined `.full.nasm` files next to the output. The script builds
`runtime/libc/libc.a` and `runtime/float.nasm` first if needed. `CLANG`,
`ZIG`, and `RUSTC` in the environment name the compilers. If the compiler of
the language is not installed, the script says so and exits with status 1.
It also checks the output directory and the `--asm` files before it compiles.
A step that fails ends the script with "nicebuild: NAME failed with status N",
where NAME is the compiler or the Python script.

The output is one assembly file. A program is made by joining it with the
start-up code, the program's other files, and the runtime library, in the
order of ABI.md. For example, for C code compiled with clang:

    clang --target=wasm32 -mbulk-memory -O2 -nostdlib -Wl,--no-entry -Wl,--export=main \
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

    zig build-exe -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall \
        -fstrip --stack 4096 --initial-memory=65536 prog.zig

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
        -C panic=abort -C strip=debuginfo -C link-arg=-zstack-size=4096 \
        -C link-arg=--initial-memory=65536 prog.rs

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
`-mcpu=mvp` needs none of them. Of the `0xFC` instructions, nicewasm
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
is measured in words (`make words` in `bench/`): `test/safe.zig` is 5932
words and the float library 6895. The benchmark of [bench/](../bench/)
runs 1652811 instructions in its phases, from a module of 8537 words.
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
  the sign bit inline. Everything else calls the float library,
  `runtime/float.nasm`, so a program that uses floats must be joined with
  it, after `runtime/lib.nasm` and the muldiv file. `float.nasm` is generated; `make -C runtime float.nasm` builds it. `trunc` traps with code 5 for a NaN or a
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
  most three shifts, additions, and subtractions, if that many will do.
  So x × 31 is `SHL t, x, 5` and `SUB d, t, x`. The math unit takes
  three instructions, and on the FPGA core its product can be read three
  cycles after the operand is written, so a read right after the write
  waits about two; each of these instructions takes one. By the cycle
  estimate of `bench/`, more steps gain nothing. A multiplication by any
  other constant uses the math unit, or with `--no-mpu` calls `__mul`.
- **i64 multiplication by a constant:** with x = 2^32 · xh + xl and the
  constant c = 2^32 · ch + cl, the product is xl · cl + 2^32 · (xl · ch +
  xh · cl), modulo 2^64. Of the last two products only the low words
  count. The math unit computes xl · cl, and then each of the two others
  in turn, but one that takes at most four shifts, additions, and
  subtractions is computed so, while the math unit computes xl · cl.
  xorshift64*'s constant 0x2545F4914F6CDD1D takes three products of the
  math unit, nine instructions. With `--no-mpu` the multiplication calls
  `__mul64`.
- **Comparisons:** `eqz`, `eq`, `ne`, `lt`, `gt`, `le`, and `ge`, signed
  and unsigned, for `i32` and `i64`.
- **Shifts:** `shl`, `shr_s`, `shr_u`, `rotl`, and `rotr`, for `i32` and
  `i64`.
- **Memory instructions:** every `i32` and `i64` load and store, at any
  byte address, and `memory.size`. An access out of bounds traps with
  code 2. `memory.grow` returns the old size, or -1 if the memory would
  pass its cap (`--memory-pages`), and sets the new pages to 0. Below the
  cap, the size is a word, `W.pages`, and the bounds checks compare with
  words that `memory.grow` keeps up to date, `W.limit0` to `W.limit8`,
  `W.wlimit4`, and `W.wlimit8`. At
  the cap, they are constants, and only growing by 0 pages succeeds.
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
- **Ignored:** custom sections. The
  name section only supplies function names for comments. A name that is
  not printable ASCII is left out, and so is any such character in the
  input file's name, so that a comment cannot become code.

Not supported yet: function types with more than one result (a block
type may have several), passive data and element segments, `memory.init`,
`data.drop`, the table instructions such as `table.get` and `table.grow`,
`ref.func` outside element segments, `ref.null` and `ref.is_null`, the tail calls `return_call` and
`return_call_indirect`, SIMD, and exceptions.

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

## How functions are translated

Each wasm function becomes a function of the ABI (ABI.md) at the label `W.fN`, where N is
its function index. nicewasm translates it in two steps. The front end
turns each wasm instruction into NICE instructions on virtual registers.
The back end gives the virtual registers physical registers, or frame
words if there are too few, and adds the prologue and the epilogue.

Each local has a virtual register, or two for an `i64` or `f64`, low word
first. So does each value that an instruction pushes on the wasm operand
stack, whose type nicewasm tracks. The values that a block, loop, or `if`
takes and gives have fixed registers, which every branch to it writes.
Every wasm instruction becomes NICE instructions on these registers. For
example, `i32.add` is one `ADD` with three operands, and `i64.add` is
`ADD[M]` on the low words and `ADD[C]` on the high words. The output has
a comment for each wasm instruction. Physical registers appear only
where ABI.md or a helper demands them: the arguments and results of
calls, the function's parameters and result, and the code and address
of a trap.

A constant, and a `local.get`, emit no code. nicewasm records the value
on the operand stack as deferred, and the instruction that uses it takes
the constant or the local's register as its operand. A
result that the next instruction stores with `local.set` or `local.tee`
goes straight to the local, for an `i32` operation of two values, an
`i32` shift, a call, a multiplication by a constant, and the operations
that call the runtime library, such as `i32.mul` with `--no-mpu`. An
`i32.mul` through the math unit reads the product into a register of its
own, and the coalescing below folds that into the local. So `local.get
a; local.get b; i32.add; local.set c` is one `ADD c, a, b`. Before such an operation, the copies of the local's old
value below its operands are copied to registers of their own. A
deferred value is copied to registers of its own only when it must be:

- before a `local.set` or `local.tee` changes the local it is the value of;
- at the start of a block, for the values the block takes and for every
  value of a local below it, so these are the same on every path through
  the block. A constant below a block stays deferred, because nothing can
  change it;
- at an `else` or `end`, for the block's results.

`select`, `abs`, `neg`, and `copysign` change only a part of their first
operand, so they copy a deferred one to the result's registers first.

A branch moves deferred values to the registers of its target, as it
does any other value. A call takes deferred arguments directly, and
deferred values below the arguments stay deferred, since a call cannot
change this function's locals. `local.tee` leaves the local itself on
the stack, and `i32.wrap_i64` of a deferred value is the low word of it.

A branch moves the values it carries to the registers that the target
block expects, and then jumps. A branch out of the function moves them
to R1 and up, as `return` does. `br_table` checks the index against the
number of labels, then jumps through a table of `.DAT` addresses.
A comparison sets the flags, usually with `SUB[M]`, then sets the result from
them. A signed comparison is N XOR V (ISA.md §9.2), so `?V XOR R14, R14,
0x10000000` first flips N when V is set, and N alone holds the answer,
as ISA.md §9.2 describes. When the next instruction is `br_if` or `if`,
or `i32.eqz` and then one of them, the comparison sets only the flags,
and the branch jumps on them. `i32.eqz` and `i64.eqz` before `br_if` or
`if` do the same with Z. A comparison of an `i32` with the constant 0 is
`MOVE[M] R0, x`, whose flags are those of `SUB[M] R0, x, 0`, so that the
back end may give the M bit to the instruction that computed x (see
Register allocation). An `i64` `eq` or `ne` takes the words of x as they
are when the other operand's word is 0.

The front end also keeps track of what the flags say, until an
instruction changes them or a label comes. After a comparison or an
`eqz` sets its result, they say whether the result is 0. After an
`i32.load` whose offset is a multiple of 4, they can say whether the
value is 0: its `MOVE` gets the M bit, and so does the `MOVE` of the
helper's result in the stub, if a branch uses the flags. A `select`,
`br_if`, `if`, or `eqz` on such a value, or on a copy of it in a local,
then uses the flags, with no test of its own. So `select(a, b, x < y)`,
signed, is `SUB[M] R0, x, y`, the `?V XOR`, `MOVE d, a`, and `?!N MOVE
d, b`. If the comparison's result is not used otherwise, no code sets
it.

An `i32` shift masks its count to 5 bits first, because NICE uses the
full count (WASM.md). A constant count is masked by nicewasm, so a
shift by a constant is one instruction, such as `SHL d, x, 3`. `shr_s`
copies the sign bit into C and shifts it in with `C>0` (§5.2). A rotate
needs no mask, since only the count modulo 32 matters to `ROL` and
`ROR`. An `i64` shift by a constant combines the two words with three or
four 32-bit shifts inline, or with moves for a count of 32. Any other `i64` shift
or rotate calls a helper, such as `W.shl64`, with the value in R1 and R2
and the count in R3. A NICE shift by 32 or more gives 0, and so does a
shift by a "negative" count such as 32 − n for n > 32. So `W.shl64` and
`W.shr_u64` need no branch: each part that does not apply comes out as
0. An `i64` rotate by 32 or more swaps the words first.

A load or store first checks that all its bytes are in the memory. One
compare of the base with the first base at which the access does not
fit does it, as in `SUB[M] R0, R1, 65532` for a word access at offset 1, whose last
byte is at base + 4, since below that base the base plus the offset
cannot pass 2^32 either. A failed check jumps to a
trap stub after the function's epilogue, which sets R2 to the start of
the access code. Then the code adds the offset to the base. If the
memory can grow, the code adds the offset first, traps if the sum passes
2^32, and compares the sum with a word that `memory.grow` keeps up to
date. An
access of 4 or 8 bytes then tests whether the address is at a multiple
of 4. If it is, one `MOVE` for each word does the access, with the word
index in a register. If it is not, the code jumps to a stub after the
epilogue, which calls a helper, `W.load4`, `W.load8`, `W.store4`, or
`W.store8`, and jumps back. So the common, aligned path changes no
registers but its own. A helper takes the byte address in R1. It returns
a loaded value in R1, or R1 and R2, and takes a value to store in R2, or
R2 and R3. nicewasm emits each helper once, if a function uses it.

With bounds checks, an access of 4 or 8 bytes whose offset is a
multiple of 4 takes a shorter path. `ROR t, base, 2` gives base / 4 if
base is a multiple of 4, and 2^30 or more if it is not, which is past
the last word of any memory. So one unsigned compare of t checks the
bounds and the alignment at once, and the offset goes into the word
operand. An `i32.load` at offset 4 in a memory of one page is:

                    ROR     R2, R1, 2
                    SUB[M]  R0, R2, 16383
            ?!C     MOVE    R15, W.f0.L1
                    MOVE    R1, @___wasm_memory+1[R2]

If the compare fails, a stub after the epilogue gets the base back with
`ROL` and calls a helper such as `W.cload4`, which is followed by two
words: the start of the access code and the offset. The helper adds the
offset, traps if the access is out of bounds, with R2 the first word,
else does the access as `W.load4` does, and returns past the two words.
Then the stub jumps back. Such a stub takes some 10 words, and with the
check in each stub it took some 20. If the memory can grow, t is
compared with a word that `memory.grow` keeps up to date, `W.wlimit4` or
`W.wlimit8`. An offset is then added to t first, and the code jumps to
the stub if the sum passes 2^32.

Clang computes the address of an array element as `(i << 2) + c`, with
`i32.shl` and `i32.add`. When c is a multiple of 4, that address is a
multiple of 4 too, and t = i + c / 4 is its word index, modulo 2^30,
since the address wraps modulo 2^32. So the `i32.add` also computes t,
and an access at the address uses it in place of `ROR`. A t of 2^30 or
more fails the compare, and the stub gets the address back with `SHL`.
The same holds for `i << s` with s above 2, with t = (i << (s - 2)) +
c / 4, and for a constant added to such a sum. If no other code uses the
address itself, the allocator removes the shift and the add, and the
access is three instructions after the `ADD` that computes t. Without
bounds checks, t is taken modulo 2^30 with an `AND`, and there is no
compare. A later access at the same base in the same straight-line code
uses the same t. What nicewasm knows of t is dropped when a register it
involves is written, and at a label that a jump may reach.

Often the `ADD` that computes t can go too. Then t is i + d, with i
the index, or the index shifted by s - 2, and the constant d = c / 4.
If d is below the limit L of the compare, the compare is of i with L -
d, and d goes into the word operand. So for `(i << 2) + 8480`, an
`i32.load` is:

                    SUB[M]  R0, R7, 14264
            ?!C     MOVE    R15, W.f6.L8
                    MOVE    R5, @___wasm_memory+2120[R7]

If i passes the compare, i + d is below L, so the access is in bounds,
and its word index does not wrap. If not, the stub computes t with an
`ADD` and goes on as before. So an address that wraps modulo 2^32 to
one in the memory still works, through the checked helper. A d at or
past L keeps the `ADD`, and so does a negative c, since d is taken
modulo 2^32. So does every access if the memory can grow. Without
bounds checks, d and the access's offset go into one `ADD` before the
`AND`. For a library module, L comes from the library's memory. If
the `i32.add` writes the local that holds i, as a `local.tee` of the
index does, a copy of i comes first, for the accesses. The allocator
gives the copy the register of i if it can, and then removes it.

nicewasm also keeps an upper bound on the unsigned value of some
registers. A constant gives itself, and a value without a bound counts
as 2^32 - 1. `i32.and` gives the smaller bound of its operands, so a
constant mask m gives m. `i32.load8_u` and `i32.load16_u` give 255 and
65535. `i32.shr_u` by a constant k, and `i32.div_u` by 2^k, give the
bound of the value shifted right by k, so 2^(32 - k) - 1 at most.
`i32.rem_u` by a constant c gives c - 1, or the bound of the value if c
is a power of two and that is smaller. A copy keeps the bound of what it
copies, and `i32.add`, `i32.or`, `i32.xor`, and `i32.shl` by a constant
combine the bounds of their operands. Signed operations give no bound. A
bound is dropped, as what nicewasm knows of t is, when its register is
written, and at a label that a jump may reach. A call changes no virtual
register, so a bound lasts across it. If the bound of the register that
a word access compares is below the limit of the compare, every value
passes it, so there is no compare and no stub. For an access at word d
of the memory plus i, that is B + d + w ≤ L, with B the bound of i, w
the words of the access, 1 or 2, and d including a quarter of the
access's offset. So in crc32, `table[(crc ^ b) & 255]` with the table at
word 3144 is:

                    AND     R1, R1, 255
                    MOVE    R5, @___wasm_memory+3144[R1]

With a memory that can grow, the access keeps its compare. Without
bounds checks, if B + d is below 2^30, i + d is the word index, so d
goes into the word operand, and there is no `ADD` and no `AND`.

Such a group of word accesses with the same t, or the same i, shares
one compare: that of the first access, with the least limit of the
group, L - d for i. If the compare passes,
every access of the group is in bounds and at a multiple of 4, so the
others need no compare. A struct's fields, or a load and a store of the
same array element, are such groups. If the compare fails, the first
access's stub does that access, as before, and then goes on in a copy
of the code up to the end of the last access, after the epilogue. In
the copy, each word access calls its checked helper, such as
`W.cload4`, and the copy then jumps back to the code after the last
access. So an access out of bounds still traps where it would have:
the code before it has run, and its stores are done. R2 points at the
access in the original code, which has no compare of its own, as for
the copies of duplicate tails below. The stubs of the other accesses
go, and that pays for most of the copy. The code from the first compare
to the end of the last access may hold up to 16 other instructions. It
may not change t, and no jump may come into it. In a loop, the group
may make the code larger by up to 20 words for each compare that it
saves, twice that in two loops, and so on. Outside loops, it may not
make the code larger. With a memory that can grow, each access keeps
its own compare.

In a helper, the value is shifted together from, or split across, two
words, or three for an unaligned `i64`. A store that changes only part
of a word reads the word, changes its bytes, and writes it back once.

An access of 1 or 2 bytes is inline. A shift gives the word index w of
the address a, and `SHL c, a, 3` gives c, which is 8p modulo 32 for the
byte p of a in its word. Neither instruction can trap, and each writes
only its own register, so both come before the bounds check, after the
start of the code, where a trap's R2 points (WASM.md). So the read
waits for neither register, only for the skipped jump just before it,
unless an instruction moves to between them (below). Only a rotation
takes its count modulo 32 (ISA.md §5.2), so the code rotates by c. The
vm's fetch of an opcode, an `i32.load8_u`, is:

                    SHR     R2, R3, 2
                    SHL     R1, R3, 3
                    SUB[M]  R0, R3, 65536
            ?!C     MOVE    R15, W.f7.L20
                    ROR     R1, @___wasm_memory[R2], R1
                    AND     R1, R1, 0xFF

A signed load gets c from `SHL c, 1[a], 3` or `SHL c, 2[a], 3`
instead, which is 8p + 8 or 8p + 16 modulo 32, rotates the bytes up to
bit 31 by it, and then shifts them down with the
sign, by `C<0[M]` and `C>0`. A store rotates the mask of the bits to
keep, such as `ROL R4, -256, R3`, ANDs the word with it, rotates the new
bytes into place, and writes the word back with `OR`. A store of a
constant 0 needs no `OR`: `AND @___wasm_memory[R3], R2,
@___wasm_memory[R3]` writes the word back. With bounds checks and a
memory that cannot grow, an offset that is a multiple of 4 goes into
the word operand, as for the words above, and any other offset is added
before the check too. If the memory can grow, w and c come after the
add of the offset, which can trap, and before the compare. If the
bound of the base, as for the words above, shows that all the bytes
are in the memory, there is no bounds check. Two bytes at p = 3
straddle two words. The code checks for that, with `AND[M] R0, 1[a],
3`, which is 0 for p = 3, and jumps to a stub after the epilogue, which
does the access with the two words and jumps back.

If the address is a constant, nicewasm adds the offset itself. If all
the bytes are in the initial memory, or there are no bounds checks,
there is no check, and an aligned access of 4 or 8 bytes is a `MOVE`
for each word, such as `MOVE R3, @___wasm_memory+256`. If no access of
its size fits in the memory at all, the access traps at once.

`call_indirect` checks the table index against the table's size. It
checks the entry's address for 0 and its type number, then calls the
address with `ADD @--SP, 1, PC` and `MOVE PC, Rn`, the "through a
register" sequence of ABI.md. The arguments are in R1–R4 and on the
stack, as for `call`. If the address is in a frame word, the jump takes
a constant word, and the `ADD` adds 2.

### Register allocation

The back end works on a list of instructions and labels. It finds the
jumps between them, and which flags (ISA.md §6) each instruction may
leave for a later one to read. A test `MOVE[M] R0, x` of a value that
the same straight-line code computed, with no instruction between that
reads or writes the flags, goes away: the instruction that computed x
gets the M bit instead, as in `ADD[M] x, a, b`. A logic operation or a
shift whose bit shifted out is discarded sets the flags just as the
`MOVE[M]` would. An arithmetic operation also sets C and V from the
operation, so it takes the test's place only if neither is read before
the flags are written again. For a copy `MOVE x, y`, the instruction
that computed y gets the M bit, if it can.

Then the back end finds which registers are live at each instruction. It
removes the instructions whose only effect is to write a register that
is not read afterwards. So of the declared locals, which wasm sets to 0,
only those that may be read before they are set get a `MOVE x, 0`. An
instruction with the M bit stays for its flags, but if its result is not
read, it writes R0 instead, as in `AND[M] R0, x, 1`. Then it splits
each virtual register into webs: each web is the definitions that reach
a common use, with those uses. A local that the wasm code
reuses for unrelated values thus gets a register for each of them.

The registers are colored by iterated register coalescing (George and
Appel, 1996), with R1–R12. A move between two registers that do not
interfere is removed if, by the tests of Briggs and George, that cannot
make the coloring fail. This includes moves to and from the physical
registers of calls, so an argument is often computed straight into R1.
A call may change R1–R6 and the flags, as ABI.md allows, so a value that
is live across a call gets one of R7–R12, which ABI.md preserves. A call
of a helper changes only the registers that the helper uses, all among
R1–R6. A value that is not live across a call gets one of R1–R6 if it
can, since the function must save each of R7–R12 that it uses.

If there are too few registers, the values with the lowest cost for
their number of neighbors go to frame words. The cost of a value counts
its uses and definitions, each weighted by 10 for each loop around it,
so values in inner loops keep their registers. NICE takes a memory
operand almost anywhere, so a value in a frame word is used in place, as
in `ADD R1, @2[R13], R3`. Only where it is an address, as in `@x[Rn]`,
or is changed by a side effect, does it go to a temporary register for
that one instruction, and the coloring runs again. Values in frame
words that are never live at the same time share a word.

Then nicewasm removes each `MOVE` of a register to itself and each jump
to the label that follows it.

Next, a conditional jump over up to four instructions goes away, and
they get the opposite condition instead. On the FPGA core, a taken
conditional jump costs six cycles more than a skipped instruction
(doc/MICROARCH.md §5.4). The instructions must not write the flags or be
conditional already, and no label may come between them. A skipped
instruction makes no memory access (ISA.md §3), so they may access
memory. So `if (x) y = 9;` is `MOVE[M] R0, x` and `?!Z MOVE y, 9`. The
code of an if before its else, up to two instructions and the jump to
the end, becomes conditional the same way, jump and all.

An unconditional jump to code of up to three instructions that ends in a
jump or a return gives way to a copy of that code. That saves the jump,
which costs at least two cycles on the FPGA core. So a `return` in a
function that saves at most two registers and has no frame words becomes
the epilogue itself. Code that ends in the jump of a `br_table` may have
up to twelve instructions, so that each case of an interpreter's loop
ends with its own copy of the dispatch. The copy has no labels. A jump
in it to one of the original's labels, such as from a stub back to the
code, goes on in the original, which does the same, and so a trap's R2
points at the original. The jumps of the stubs after the epilogue stay,
since the stubs run rarely: copies there cost words and save little.
Code that no jump reaches any more goes.

A `br_if` back to the start of a loop, at the end of the loop, is
usually taken. On the FPGA core DECODE predicts a conditional `ADD PC,
PC, offset` taken when the offset is negative, and a predicted jump costs
what an unconditional jump to a label does when taken, a bubble of 3
cycles in a stream without reads and 2 behind a read, which holds the
stream up a cycle (`hdl/test/bubble.nasm`, MICROARCH.md §5.4). So the `br_if` becomes `?cc ADD R15,
R15, top-next`, where `next` is a new label right after it. Each round of
the loop then costs two cycles and one instruction less than a skipped
conditional jump out and an unconditional one back, and leaving it, a
mispredict, costs six cycles more, as a taken conditional jump did. If an
unconditional jump follows the `br_if`, leaving the loop takes two more
cycles than if the two swapped targets, but a loop that runs three rounds
or more still gains. A loop that runs once pays the six cycles at its
exit and gains nothing.

A `br_if` out of a block whose other arm ends in a `br` forward, as in
`block; block; c; br_if 0; A; br 1; end; B; end`, jumps over arm A to
arm B. Without a profile, nicewasm guesses that the shorter arm is the
rarer one, as an edge case tends to be. So if A has fewer instructions
than B, the jump goes to A on the opposite condition instead, and A
moves to the end of the function, after the return, so that B falls
through. A may have no other unconditional jump, and no jump back,
which would be the next round of a loop. In the benchmark, this made
heapsort's sift take some 51000 cycles fewer.

Last, on the FPGA core, a data read waits a cycle for a conditional
jump just before it that is not taken (doc/MICROARCH.md §5.3). So an
earlier instruction of the same straight-line code moves to between the
two, if one can: it must compute a register from registers only, with
no flags, the code it passes must not use the register or change its
sources, and the register must not be live where the jumps it passes
go. Nor may it be the read's address register, or its count if the
read is a shift, as the `SHL` of a byte access is, since the read would
wait for it instead on a core that forms the count in PREPARE. In a
copy of an interpreter's dispatch, for example, the `ADD` that
computes the next pc moves to just before the jump through the table.

Often no earlier instruction can, as when the read is the first
instruction after the label of a word access. Then one of the next four
instructions after the read, in the same straight-line code, may move
to between the jump and the read instead. This holds for any
conditional jump just before a read: the jump to the stub of a word
access, the check of a 2-byte access for p = 3, or a `br_if` just
before a load from a constant address. This is done on the virtual
registers, before the allocation, so that the moved instruction gets a
register of its own. It must compute a virtual register from virtual
registers and constants, with no flags, be unconditional, and not be a
copy, which the allocator may remove. Neither it nor an instruction
that it passes, the read included, may write a register that the other
reads or writes. It may pass a label that no jump goes to, such as the
start of the code of a wasm instruction, where a trap's R2 points, only
if it is the first instruction after it. The label then moves with it,
so R2 still points at the first instruction of that code, as in the
vm's `ROR` of the address of a store just after a load.
It may pass the label where the stub of a word access comes back, or
another label that only unconditional jumps go to, if it is in a loop:
then a copy of it goes just before each of those jumps. So every path
past the label runs it once, as before, and an access that traps in its
stub has not run it. If the stub goes on in a copy of the code, as for
a group of accesses that share a compare, the copy runs its own. It may
not be the value that a later `MOVE[M] R0`
tests, since it then could no longer take the M bit.

A data access also waits a cycle when the instruction just before it
writes its address register, since the core forms the address in
PREPARE, before that instruction's WRITE (doc/MICROARCH.md §3). So one
of the next four instructions may move to between them in the same
way. Labels that no jump goes to, such as the start of the access's
code, may be between them, and the moved instruction goes before those.
In crc32, the `SHR` of the CRC moves to between the `AND` of the table
index and the load from the table.

### The frame

There is no frame pointer. The prologue pushes the registers of R7–R12
that the function uses, then reserves its frame words with `SUB R13,
R13, n`. The epilogue drops them with `ADD R13, R13, n`, pops the
registers, and returns with `MOVE R15, @R13++`. A function that needs
neither has no prologue. Frame words are addressed from SP, as `@k[R13]`.
SP moves only in a call sequence: each stack argument and the return
address are pushed, the return pops the return address, and `ADD R13,
R13, n` drops the stack arguments. nicewasm counts the words pushed at
each instruction, so that it can address the same frame word from
anywhere. All sources of an instruction are read before its destination
is written (ISA.md §5), so `MOVE @--R13, @3[R13]` pushes the frame word at
3 above the old SP. A parameter that arrives on the stack is read at
entry from above the return address.

A function that starts with a test and an early return often needs no
saved register on that path, as in a recursive walk of a tree that
returns at once for a null node. If the first jump of the function is a
conditional one, and the code it goes to returns without a saved
register, SP, or a call, within ten instructions before the return,
the test and the jump come before the prologue. The jump then goes to a copy of that code, which returns with
`MOVE R15, @R13++` alone. The instructions before the jump may not need
a saved register or SP either, except those that only write a saved
register from other registers and constants, such as the copy of a
parameter. These come after the prologue instead. If one of them sets
the flags for the jump, a copy of it that writes R0 sets them before
the prologue. Where it reads a saved register that an earlier one
of them copied from another register or a constant, the copy reads
that instead, and if it cannot, the jump stays after the prologue.

A call of a function or a helper by its label, just before the return,
is a tail call: the epilogue drops the frame and restores the saved
registers, and then jumps to the label with `MOVE R15, label`, without
pushing a return address. The callee then returns to this function's
caller, with its results in R1 and up, which are this function's. A
call with stack arguments drops them after it, so it is never a tail
call.

The translated functions may use every register. The helpers and
`___wasm_start` use only R1–R6, R13, R14, and R15, so a value in R7–R12
survives a call of a helper, as it does any ABI.md call.

## Test

    make test        # run the test modules, then test/fuzz.py, test/passes.py, test/errors.py, and test/build.py
    make typecheck   # mypy --strict
    make wasm        # rebuild test/*.wasm from test/*.c, test/*.zig, and test/*.rs
    make diff        # compare with an older translator, OLD=main, on random modules (minutes)

`test/run.py` translates each test module and joins it with the runtime.
It then assembles and runs the program. It checks main's result in R1,
that R7–R13 are unchanged unless it trapped, what it printed on the
console, and that the memory is not in the `.bin` file. A case that
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
must halt without the report. `hello.zig` is built with and without
`--symbols`, which must give the same `.bin`, and `hellors.rs` with it.
Every `.sym` file must name every function. A language whose compiler is
missing is skipped, and the PASS line says which; CI has Zig and clang, not Rust.
`test/run.py --keep DIR` also leaves each
program in `DIR/X.bin`, or `DIR/X_soft.bin` for the run with `--no-mpu`,
for `make programs` in `hdl/`, which runs them on the FPGA core.
`test/run.py`, `test/fuzz.py`, and `test/errors.py` run their cases in
parallel, one per CPU, each with files of its own, and report them
in order.

`test/fuzz.py FIRST COUNT` builds random modules from a syntax tree
whose nodes also evaluate themselves in Python, so each module comes
with the result that wasm defines for it, and `main`'s result in R1 must
match, or if the module traps, the program must halt at `___wasm_trap`
with the trap code in R1. The modules have four functions with `i32` and
`i64` parameters, 8 to 13 locals, loops, blocks, and ifs whose block
types may have parameters and several results, branches that carry no
value, one, or several, `br_table` among them, `return`, `nop`, both
forms of `select`, calls through the table, every integer
operation and comparison, the results of comparisons kept in locals for
later conditions, mutable and immutable globals, loads and stores of
every width at constant and dynamic addresses, the addresses of array
elements as `(i << s) + c`, groups of word accesses at offsets from one
address, and `memory.fill` and `memory.copy`. That covers the rules for
deferred values, fused comparisons, the flags, forwarded results, and
register allocation above. In 40% of the modules, statements may trap:
`unreachable`, divisions by 0 and of the most negative value by −1,
`call_indirect` past the table or of the wrong type, and accesses,
`memory.fill`, and `memory.copy` past the end of the memory. About a
fifth of the modules trap. The modes of nicewasm are `--no-mpu`,
`--unchecked` for `--no-bounds-checks`, whose modules make no access out
of bounds, and `--grow` for `--memory-pages 2`. `make test` runs 40
seeds with the math unit, 40 with `--no-mpu`, and 20 each with
`--unchecked` and `--grow`, and says how many of them trap;
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
of the linear memory. The modules are `fuzz.py`'s, and, with `--trap`,
the same with statements that may trap: accesses out of bounds,
divisions by zero and of the most negative value by −1, bad
`call_indirect`s, `memory.fill` and `memory.copy` past the end,
`unreachable`, and `memory.grow`. So it checks a trap's R2, and
`memory.grow`, which `fuzz.py`'s model does not know, and each mode of
the translator. It is not part of `make test`, since it takes minutes and needs git.
