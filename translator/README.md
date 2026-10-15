# nicewasm

Translates a WebAssembly module into NICE assembly, following the
WebAssembly mapping in [doc/ISA.md §9.4](../doc/ISA.md#94-webassembly-mapping).
It is one Python 3 script with no dependencies beyond the standard library.
The [WebAssembly specification](https://webassembly.github.io/spec/core/)
defines the module format and what each instruction does.

It supports the features listed below, which cover what clang, Zig, and
Rust emit for their default wasm32 targets (see Target). It rejects
anything else with an error, rather than translating it wrongly.

## Usage

    ./nicewasm.py [-o output.asm] [--no-bounds-checks] [--memory-pages N]
                  [--library NAME [--library-memory BYTES]] [--no-mpu] input.wasm

Without `-o`, the output goes to `input.asm`. `--no-bounds-checks` leaves
out the bounds checks on memory accesses, as ISA.md §9.4 allows. The code
is then smaller and faster, but an access out of bounds reads or writes
whatever NICE memory the address reaches. `--memory-pages N` lets
`memory.grow` grow the memory up to N pages, the cap of ISA.md §9.4. N
may not be below the memory's initial size or above its maximum, if it
declares one, and it must be below 65536. Without the option, the cap is
the initial size. `--library` translates a library module instead, as
described below. `--no-mpu` is for a system without the math unit of
ISA.md §8.4: `i32.mul`, `div`, and `rem` then call the runtime library
instead of using the math unit, and the program must be joined with
`runtime/muldiv_soft.asm`, not `muldiv_mpu.asm`. Errors are printed as
`file:0xOFFSET: error: message`, where OFFSET is the byte offset in the
module, or as `file: error: message` when there is no offset. The exit
status is 1 after an error, and no output is written. nicewasm stops at the
first error.

The output is one assembly file. A program is made by joining it with the
start-up code, the program's other files, and the runtime library, in the
order of ISA.md §9.3. For example, for C code compiled with clang:

    clang --target=wasm32 -mbulk-memory -O2 -nostdlib -Wl,--no-entry -Wl,--export=main \
        -Wl,--allow-undefined -Wl,-z,stack-size=4096 -Wl,--initial-memory=65536 \
        -o prog.wasm prog.c
    translator/nicewasm.py prog.wasm
    cat runtime/start_wasm.asm prog.asm runtime/lib.asm runtime/muldiv_mpu.asm > full.asm
    assembler/niceasm.py full.asm
    emulator/zig-out/bin/niceemu full.bin

`-mbulk-memory` matters. Without it, clang turns every copy or fill that
it does not inline, such as the assignment of a large structure, into a
call to `memcpy`, `memset`, or `memmove`. With `-nostdlib`, these become
imports from `env`, and the assembler stops with `undefined symbol
'_memcpy'`. A C routine could not serve them anyway, since they take byte
addresses in linear memory. With `-mbulk-memory`, clang emits
`memory.copy` and `memory.fill` instead.

C's `long double` and `__int128` are not supported. Clang implements them
with calls to routines such as `__addtf3` and `__multi3`, which the
runtime library does not have, and nicewasm rejects the imports. Zig's
`f128` and `u128` work, because Zig puts its compiler_rt in the module.

If the program has constructors, also link with
`-Wl,--export=__wasm_call_ctors`, so that `___wasm_start` runs them once
(ISA.md §9.4). Without it, wasm-ld runs them again before each call of an
exported function.

And for Zig:

    zig build-exe -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall \
        -fstrip --stack 4096 --initial-memory=65536 prog.zig

ReleaseSafe and Debug work too. They need `--stack 16384`, or at least
more than 4096, if the program can panic: Zig's panic handler puts a
4 KB buffer on the stack, and with too small a stack it traps with code
2, out of bounds, before it reaches its own trap. `test/safe.zig` is
about 7100 words built with ReleaseSafe, and about 239000 built with
Debug.

`-fstrip` drops the DWARF sections, which make up almost all of a
ReleaseSafe or Debug module. nicewasm ignores them, but they make the
file large. Do not use `-fno-llvm`: Zig 0.15's own wasm backend encodes
the initial value of `__stack_pointer` wrongly, so every stack access is
out of bounds.

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

nicewasm aims at the default wasm32 feature set of Zig 0.15:
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

The code is about a third smaller than it was, after three steps with
no change to ISA.md §9.4. Using locals and constants directly as
operands made `test/safe.zig` 19% smaller (12353 to 9941 words) and the
float library 31% smaller (29569 to 20317). A short inline path for
memory accesses made them 12% (to 8730) and 2.5% (to 19808) smaller
again. Helpers for `i64` shifts, and short inline code for a shift by a
constant, took them to 8670 and 18723. Locals in registers, jumps on the
flags after a comparison, and results written straight to a local took
them to 7139 (18% less) and 14565 (22% less). In all, `test/safe.zig` is
42% smaller and the float library 51%.
[doc/review/code-size-plan.md](../doc/review/code-size-plan.md) has the
measurements.

## Supported features

- **Types:** `i32`, `i64`, `f32`, and `f64`, in function types, locals,
  and globals. An `i64` or `f64` takes
  two words, low word first, and is passed in registers or on the stack by
  the rules of ISA.md §9.3. A float value is its bits, as in memory.
- **Floats:** every `f32` and `f64` instruction. `const`, `load`, `store`,
  and `reinterpret` move the bits, and `abs`, `neg`, and `copysign` change
  the sign bit inline. Everything else calls the float library,
  `runtime/float.asm`, so a program that uses floats must be joined with
  it, after `runtime/lib.asm` and the muldiv file. `trunc` traps with code 5 for a NaN or a
  value whose integer part does not fit, and `trunc_sat` saturates
  instead.
- **Control:** `block`, `loop`, `if`, `else`, `end`, `br`, `br_if`,
  `br_table`, `return`, `call`, `unreachable`, and `nop`. A block type may
  be a function type, with parameters and several results.
- **Instructions:** `drop`, `select` (both forms), `local.get`,
  `local.set`, `local.tee`, `global.get`, `global.set`, `i32.const`,
  `i64.const`, `i32.wrap_i64`, `i64.extend_i32_s`, and `i64.extend_i32_u`.
  `unreachable` traps with code 1 through `___wasm_trap_vector`, as ISA.md
  §9.4 says.
- **Integer operations,** for `i32` and `i64`: `add`, `sub`,
  `mul`, `div_s`, `div_u`, `rem_s`, `rem_u`, `and`, `or`, `xor`, `clz`,
  `ctz`, `popcnt`, and the `sign-ext` instructions `extend8_s`,
  `extend16_s`, and `i64.extend32_s`. `i32.mul`, `div`, and `rem` write
  their operands to the math unit of ISA.md §8.4 and read the result, in
  three instructions, through the labels `__mpu.a` and the like that
  `runtime/muldiv_mpu.asm` defines. With `--no-mpu` they call `__mul`,
  `__div`, and the like instead. The `i64` ones and the bit counts always
  call the runtime library, for example `__mul64`, `__div64`, and
  `__popcnt` (see [runtime/README.md](../runtime/README.md)). Division by 0
  traps with code 3, and `div_s` of the most negative number by −1 with
  code 4. `rem_s` by −1 is 0 without a division, because C leaves the most
  negative number % −1 undefined.
- **Comparisons:** `eqz`, `eq`, `ne`, `lt`, `gt`, `le`, and `ge`, signed
  and unsigned, for `i32` and `i64`.
- **Shifts:** `shl`, `shr_s`, `shr_u`, `rotl`, and `rotr`, for `i32` and
  `i64`.
- **Memory instructions:** every `i32` and `i64` load and store, at any
  byte address, and `memory.size`. An access out of bounds traps with
  code 2. `memory.grow` returns the old size, or -1 if the memory would
  pass its cap (`--memory-pages`), and sets the new pages to 0. Below the
  cap, the size is a word, `W.pages`, and the bounds checks compare with
  words that `memory.grow` keeps up to date, `W.limit0` to `W.limit8`. At
  the cap, they are constants, and only growing by 0 pages succeeds.
- **Bulk memory:** `memory.fill` and `memory.copy`, whose ranges may
  overlap. Both check their ranges before they write a byte, and trap with
  code 2 if a range passes the end of the memory. Each calls a function
  that nicewasm emits once, `W.fill` or `W.copy`, which works a word at a
  time where it can.
- **Imports:** functions from `env`, whose names must be C identifiers
  that do not start with `_` (ISA.md §9.4). Each becomes a call to the
  label `_name`.
- **Hardware access:** `nice.peek`, of type `(i32) -> i32`, and `nice.poke`,
  of type `(i32, i32) -> ()`, as ISA.md §9.4 says. Each call makes exactly
  one data access, a `MOVE` that reads or writes the NICE word at the given
  word address, after the code that puts the address in a register. A
  `peek` whose result is not used still makes its access. So `poke(0xFFFFFF00, c)` prints `c` on
  the console (ISA.md §8.3). They have no address, so they cannot be in a
  table.
- **Exports:** functions and globals get the label `_name`, as §9.4 says.
  A name that is not a C identifier gets no label, in a library module
  too. Exports of the memory and of the table are ignored: the memory is at
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
  the cap.
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
  `W.table`, two words to an entry as ISA.md §9.4 says: the function's
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
`ref.func` outside element segments, the tail calls `return_call` and
`return_call_indirect`, SIMD, and exceptions.

nicewasm checks the types on the operand stack as wasm validation does,
so an invalid module is an error, not wrong code. Code that cannot be
reached, such as the code after a `br` up to the end of its block, is
decoded but not checked, and nicewasm emits nothing for it. Two exports with the
same name are an error too, and so is a `__wasm_call_ctors` with
parameters or results.

## Library modules

`--library NAME` translates a library module of the runtime library, as
ISA.md §9.4 describes. The float library is one: see
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
  `--library-memory BYTES`, it is BYTES, rounded up to a word. An access
  past it traps with code 2.

## How functions are translated

Each wasm function becomes a §9.3 function at the label `W.fN`, where N is
its function index. It builds a §9.3 frame with FP (R12).

The most used locals live in R7–R11. nicewasm translates each function
twice. The first pass counts the uses of each local, and a use inside a
loop counts 8 times, or 64 or 512 inside two or three loops. The second
pass gives the registers to the locals with the highest counts, as long
as they fit: an `i32` takes one register, and an `i64` two. A local whose
count is below 3 stays in the frame. The function pushes the registers it
uses just below the saved FP, and pops them before it returns. So R7–R11
keep their values across a call, as §9.3 requires.

The parameters that arrive in R1–R4 and the declared locals are copied into
their registers, or into words below the saved registers. The declared
locals are set to 0, as wasm requires. A parameter on the stack is copied
into its registers, or stays where the caller put it. nicewasm tracks the
type of each value on the wasm operand stack, so each value has fixed frame
words: one for an `i32`, two for an `i64`. Every wasm instruction becomes
NICE instructions on registers and frame words. For example, `i32.add` is
one `ADD` with three operands, and `i64.add` is `ADD[M]` on the low words
and `ADD[C]` on the high words. The output has a comment for each wasm
instruction.

A constant, and a `local.get`, emit no code. nicewasm records the value
on the operand stack as deferred, and the instruction that uses it takes
the constant or the local's register or frame word as its operand. A
result that the next instruction stores with `local.set` or `local.tee`
goes straight to the local, for an `i32` operation of two values, an
`i32` shift, a call, and the operations that call the runtime library,
such as `i32.mul`. So `local.get a; local.get b; i32.add; local.set c` is
one `ADD c, a, b`. Before such an operation, the copies of the local's old
value below its operands are written to their frame words. A deferred
value is written to its frame words only when it must be:

- before a `local.set` or `local.tee` changes the local it is the value of;
- at the start of a block, for the values the block takes and for every
  value of a local below it, so these are the same on every path through
  the block. A constant below a block stays deferred, because nothing can
  change it;
- at an `else` or `end`, for the block's results.

`select`, `abs`, `neg`, and `copysign` change only a part of their first
operand, so they copy a deferred one to the result's frame words first.

A branch moves deferred values to the frame words of its target, as it
does any other value. A call takes deferred arguments directly, and
deferred values below the arguments stay deferred, since a call cannot
change this function's locals. `local.tee` leaves the local itself on
the stack, and `i32.wrap_i64` of a deferred value is the low word of it.

A block's values stay in the frame words where they already are. A
branch moves the values it carries down to the words that the target
block expects, and then jumps. A branch out of the function moves them
to R1 and up, as `return` does. `br_table` checks the index against the
number of labels, then jumps through a table of `.DAT` addresses.
A comparison sets the flags, usually with `SUB[M]`, then sets the result from
them. A signed comparison is N XOR V (ISA.md §9.2). When the next
instruction is `br_if` or `if`, or `i32.eqz` and then one of them, the
comparison sets only the flags, and the branch jumps on them. For a
signed comparison, `?V XOR R14, R14, 0x10000000` first flips N when V is
set, so N alone holds the answer, as ISA.md §9.2 describes. `i32.eqz` and `i64.eqz` before `br_if` or
`if` do the same with Z.

An `i32` shift masks its count to 5 bits first, because NICE uses the
full count (ISA.md §9.4). `shr_s` copies the sign bit into C and shifts it
in with `C>0` (§5.2). A rotate needs no mask, since only the count modulo
32 matters to `ROL` and `ROR`. An `i64` shift by a constant combines the
two words with three or four 32-bit shifts inline. Any other `i64` shift
or rotate calls a helper, such as `W.shl64`, with the value in R1 and R2
and the count in R3. A NICE shift by 32 or more gives 0, and so does a
shift by a "negative" count such as 32 − n for n > 32. So `W.shl64` and
`W.shr_u64` need no branch: each part that does not apply comes out as
0. An `i64` rotate by 32 or more swaps the words first.

A load or store first puts the byte address in R1 and checks that all its
bytes are in the memory. A failed check jumps to a trap stub after the
function's epilogue, which sets R2 to the start of the access code. An
access of 4 or 8 bytes then tests whether R1 is at a multiple of 4. If
it is, R2 gets the word index, and one `MOVE` for each word does the
access. If it is not, the code calls a helper, `W.load4`, `W.load8`,
`W.store4`, or `W.store8`, which returns past the aligned `MOVE`s. An
access of 1 or 2 bytes always calls a helper, such as `W.load1u` or
`W.store2`. A helper returns a loaded value in R1, or R1 and R2, and
takes a value to store in R2, or R2 and R3. nicewasm emits each helper
once, if a function uses it.

In a helper, the value is shifted together from, or split across, two
words, or three for an unaligned `i64`. A store that changes only part
of a word reads the word, changes its bytes, and writes it back once.

If the address is a constant, nicewasm adds the offset itself. If all
the bytes are in the initial memory, or there are no bounds checks,
there is no check, and an aligned access of 4 or 8 bytes is a `MOVE`
for each word, such as `MOVE @x, @___wasm_memory+256`.

`call_indirect` puts the table index in R5 and checks it against the
table's size. It checks the entry's address for 0 and its type number,
then calls the address in R5 with `ADD @--SP, 1, PC` and `MOVE PC, R5`,
the "through a register" sequence of ISA.md §9.3. The arguments are in
R1–R4 and on the stack, as for `call`.

Apart from the locals in R7–R11, the translated functions use only R1–R5,
R12, R13, R14 for the trick above, and R15. The helpers and
`___wasm_start` also use R6, which a §9.3 function may change.

## Test

    make test        # translate, assemble, and run the test modules, then test/errors.py
    make typecheck   # mypy --strict
    make wasm        # rebuild test/*.wasm from test/*.c, test/*.zig, and test/*.rs

`test/run.py` translates each test module and joins it with the runtime.
It then assembles and runs the program. It checks main's result in R1,
that R7–R13 are unchanged unless it trapped, what it printed on the console, and that the
memory is not in the `.bin` file. A case that traps must instead halt at
`___wasm_trap` with the trap code in R1, and R2 at the start of the code
that trapped. Most modules are built byte by byte with `test/wasm.py`.
The others are compiled from `test/*.c`, `test/*.zig`, and `test/*.rs`.
Their `.wasm` files are checked in, so `make test` needs no compiler.
`make wasm` needs clang with the wasm32 target, `wasm-ld`, Zig 0.15, and
rustc with the `wasm32-unknown-unknown` target. The Rust modules were
built with rustc 1.99.0. `test/errors.py` checks every error message.