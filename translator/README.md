# nicewasm

Translates a WebAssembly module into NICE assembly, following the
WebAssembly mapping in [doc/ISA.md §9.4](../doc/ISA.md#94-webassembly-mapping).
It is one Python 3 script with no dependencies beyond the standard library.

This is a first version. It supports only the features listed below. It
rejects anything else with an error, rather than translating it wrongly.

## Usage

    ./nicewasm.py [-o output.asm] [--no-bounds-checks] input.wasm

Without `-o`, the output goes to `input.asm`. `--no-bounds-checks` leaves
out the bounds checks on memory accesses, as ISA.md §9.4 allows. The code
is then smaller and faster, but an access out of bounds reads or writes
whatever NICE memory the address reaches. Errors are printed as
`file:0xOFFSET: error: message`, where OFFSET is the byte offset in the
module, or as `file: error: message` when there is no offset. The exit
status is 1 after an error, and no output is written. nicewasm stops at the
first error.

The output is one assembly file. A program is made by joining it with the
start-up code, the program's other files, and the runtime library, in the
order of ISA.md §9.3. For example, for C code compiled with clang:

    clang --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export=main \
        -Wl,--allow-undefined -Wl,-z,stack-size=4096 -Wl,--initial-memory=65536 \
        -o prog.wasm prog.c
    translator/nicewasm.py prog.wasm
    cat runtime/start_wasm.asm prog.asm runtime/lib.asm > full.asm
    assembler/niceasm.py full.asm
    emulator/zig-out/bin/niceemu full.bin

And for Zig:

    zig build-exe -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall \
        -fstrip --stack 4096 --initial-memory=65536 prog.zig

ReleaseSafe and Debug work too. They need `--stack 16384`, or at least
more than 4096, if the program can panic: Zig's panic handler puts a
4 KB buffer on the stack, and with too small a stack it traps with code
2, out of bounds, before it reaches its own trap. A ReleaseSafe program
is about 12000 words, and a Debug one about 44000.

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

## Target

nicewasm aims at the default wasm32 feature set of Zig 0.15:
`bulk-memory-opt`, `call-indirect-overlong`, `extended-const`,
`multivalue`, `mutable-globals`, `nontrapping-fptoint`, and `sign-ext`.
Clang's default set is a subset of it. A module built with
`-mcpu=mvp` needs none of them. Of `bulk-memory-opt`, nicewasm supports
`memory.copy` and `memory.fill`. It decodes the other `0xFC`
instructions, those of `nontrapping-fptoint` and the table instructions,
only to name them in an error. It accepts only an `i32.const` or `i64.const` as a
global's initial value, not the expressions of `extended-const`.

Every Zig program built with ReleaseSafe or Debug uses a table,
`call_indirect`, `br_table`, `select`, `memory.copy`, and `memory.fill`,
and it traps with `unreachable`, even if its source has no function
pointers. nicewasm supports all of them. The next features are `f32` and
`f64`.

## Supported features

- **Types:** `i32` and `i64`, in function types, locals, and globals. A
  function has at most one result. An `i64` takes two words, low word
  first, and is passed in registers or on the stack by the rules of ISA.md
  §9.3.
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
  `extend16_s`, and `i64.extend32_s`. `mul`, the divisions, and the bit
  counts call the runtime library, for example `__mul`, `__div64`, and
  `__popcnt` (see [runtime/README.md](../runtime/README.md)). Division by 0
  traps with code 3, and `div_s` of the most negative number by −1 with
  code 4. `rem_s` by −1 is 0 without a call, because C leaves the most
  negative number % −1 undefined.
- **Comparisons:** `eqz`, `eq`, `ne`, `lt`, `gt`, `le`, and `ge`, signed
  and unsigned, for `i32` and `i64`.
- **Shifts:** `shl`, `shr_s`, `shr_u`, `rotl`, and `rotr`, for `i32` and
  `i64`.
- **Memory instructions:** every `i32` and `i64` load and store, at any
  byte address, and `memory.size`. An access out of bounds traps with
  code 2. The memory cannot grow yet, so `memory.grow` returns the size for
  0 pages and -1 otherwise.
- **Bulk memory:** `memory.fill` and `memory.copy`, whose ranges may
  overlap. Both check their ranges before they write a byte, and trap with
  code 2 if a range passes the end of the memory. Each calls a function
  that nicewasm emits once, `W.fill` or `W.copy`, which works a word at a
  time where it can.
- **Imports:** functions from `env`, whose names must be C identifiers. Each
  becomes a call to the label `_name`.
- **Hardware access:** `nice.peek`, of type `(i32) -> i32`, and `nice.poke`,
  of type `(i32, i32) -> ()`, as ISA.md §9.4 says. Each call becomes one
  `MOVE` that reads or writes the NICE word at the given word address, even
  if a `peek`'s result is not used. So `poke(0xFFFFFF00, c)` prints `c` on
  the console (ISA.md §8.3). They have no address, so they cannot be in a
  table.
- **Exports:** functions and globals get the label `_name`, as §9.4 says.
  Exporting an imported function is not supported.
- **Globals:** mutable or not, with an `i32.const` or `i64.const` initial
  value. `global.set` on an immutable global is an error.
- **Memory:** one memory at `___wasm_memory`, at its initial size.
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

Not supported yet: the other `0xFC` instructions, `f32` and `f64` loads
and stores, the conversion trap (code 5), passive data and element segments, `memory.init`, the table instructions
such as `table.get`, `ref.func` outside element segments, the tail calls
`return_call` and `return_call_indirect`, library modules (ISA.md §9.4),
`f32`, and `f64`.

nicewasm checks the types on the operand stack as wasm validation does,
so an invalid module is an error, not wrong code. Code that cannot be
reached, such as the code after a `br` up to the end of its block, is
decoded but not checked, and nicewasm emits nothing for it. Two exports with the
same name are an error too, and so is a `__wasm_call_ctors` with
parameters or results.

## How functions are translated

Each wasm function becomes a §9.3 function at the label `W.fN`, where N is
its function index. It builds a §9.3 frame with FP (R12). The parameters
that arrive in R1–R4 and the declared locals are copied into words below FP.
The declared locals are set to 0, as wasm requires. Parameters on the stack
stay where the caller put them. nicewasm tracks the type of each value on
the wasm operand stack, so each value has fixed frame words: one for an
`i32`, two for an `i64`. Every wasm instruction becomes NICE instructions on
frame words. For example, `i32.add` is one `ADD` with three memory
operands, and `i64.add` is `ADD[M]` on the low words and `ADD[C]` on the
high words. The output has a comment for each wasm instruction.

A block's values stay in the frame words where they already are. A
branch moves the values it carries down to the words that the target
block expects, and then jumps. A branch out of the function moves them
to R1 and up, as `return` does. `br_table` checks the index against the
number of labels, then jumps through a table of `.DAT` addresses.
A comparison sets the flags, usually with `SUB[M]`, then sets the result from
them. A signed comparison is N XOR V (ISA.md §9.2).

An `i32` shift masks its count to 5 bits first, because NICE uses the
full count (ISA.md §9.4). `shr_s` copies the sign bit into C and shifts it
in with `C>0` (§5.2). A rotate needs no mask, since only the count modulo
32 matters to `ROL` and `ROR`. An `i64` shift combines the two words with
32-bit shifts. A NICE shift by 32 or more gives 0, and so does a shift by
a "negative" count such as 32 − n for n > 32. So `shl` and `shr_u` need
no branch: each part that does not apply comes out as 0. An `i64`
rotate by 32 or more swaps the words first.

A load or store first puts the byte address in R1 and checks that all its
bytes are in the memory. A failed check jumps to a trap stub after the
function's epilogue, which sets R2 to the start of the access code. Then
R2 gets the word index and R3 the byte within the word. An access that
fits in one word reads or writes only that word. Otherwise the value is
shifted together from, or split across, two words, or three for an
unaligned `i64`. A store that changes only part of a word reads the word,
changes its bytes, and writes it back once.

`call_indirect` puts the table index in R5 and checks it against the
table's size. It checks the entry's address for 0 and its type number,
then calls the address in R5 with `ADD @--SP, 1, PC` and `MOVE PC, R5`,
the "through a register" sequence of ISA.md §9.3. The arguments are in
R1–R4 and on the stack, as for `call`.

The translated code itself uses only R1–R5, R12, R13, and R15, so R7–R11
keep their values across a call, as §9.3 requires. `W.fill` and `W.copy`
also use R6, which a §9.3 function may change.

## Test

    make test        # translate, assemble, and run the test modules, then test/errors.py
    make typecheck   # mypy --strict
    make wasm        # rebuild test/*.wasm from test/*.c and test/*.zig

`test/run.py` translates each test module and joins it with the runtime. It
then assembles and runs the program. It checks main's result in R1, that
R7–R13 are unchanged, what it printed on the console, and that the memory
is not in the `.bin` file. A case that traps must instead halt at
`___wasm_trap` with the trap code in R1, and R2 at the start of the code
that trapped. Most modules are built byte by byte with `test/wasm.py`.
The others are compiled from `test/*.c` and `test/*.zig`. Their `.wasm` files
are checked in, so `make test` needs no compiler. `make wasm` needs clang
with the wasm32 target, `wasm-ld`, and Zig 0.15. `test/errors.py` checks
every error message.
