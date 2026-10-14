# nicewasm

Translates a WebAssembly module into NICE assembly, following the
WebAssembly mapping in [doc/ISA.md §9.4](../doc/ISA.md#94-webassembly-mapping).
It is one Python 3 script with no dependencies beyond the standard library.

This is a first version. It supports only the features listed below. It
rejects anything else with an error, rather than translating it wrongly.

## Usage

    ./nicewasm.py [-o output.asm] input.wasm

Without `-o`, the output goes to `input.asm`. Errors are printed as
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
        --stack 4096 --initial-memory=65536 prog.zig

The memory options matter. nicewasm reserves the module's initial memory as
`.BLK` words, and the assembler writes every one of them to the `.bin` file.
Without the options, clang asks for 2 pages and Zig for 16, which is 32768
or 262144 words.

## Supported features

- **Types:** `i32` only, in function types, locals, and globals. A function
  has at most one result.
- **Instructions:** `nop`, `drop`, `return`, `call`, `local.get`,
  `local.set`, `local.tee`, `global.get`, `global.set`, `i32.const`,
  `i32.add`, `i32.sub`, `i32.mul`, `i32.and`, `i32.or`, and `i32.xor`.
  `i32.mul` calls `__mul` in the runtime library.
- **Imports:** functions from `env`, whose names must be C identifiers. Each
  becomes a call to the label `_name`.
- **Exports:** functions and globals get the label `_name`, as §9.4 says.
  Exporting an imported function is not supported.
- **Globals:** mutable or not, with an `i32.const` initial value.
- **Memory:** one memory, reserved at its initial size at `___wasm_memory`.
  No instruction reads or writes it yet.
- **Start-up:** `___wasm_start` calls the start function, if there is one,
  and then `__wasm_call_ctors`, if it is exported.
- **Ignored:** tables (without element segments) and custom sections. The
  name section only supplies function names for comments.

Not supported yet: blocks, loops, branches, comparisons, the other `i32`
operations, memory instructions, `unreachable` and the other traps,
`call_indirect`, `nice.peek` and `nice.poke`, data and element segments,
`i64`, `f32`, and `f64`.

## How functions are translated

Each wasm function becomes a §9.3 function at the label `W.fN`, where N is
its function index. It builds a §9.3 frame with FP (R12). The parameters
that arrive in R1–R4 and the declared locals are copied into words below FP.
The declared locals are set to 0, as wasm requires. Parameters on the stack
stay where the caller put them. Each depth of the wasm operand stack has its
own frame word, so every wasm instruction becomes NICE instructions on frame
words. For example, `i32.add` is one `ADD` with three memory operands. The
output has a comment for each wasm instruction.

The translated code itself uses only R1–R4, R12, R13, and R15, so R7–R11 keep their
values across a call, as §9.3 requires.

## Test

    make test        # translate, assemble, and run the test modules, then test/errors.py
    make typecheck   # mypy --strict
    make wasm        # rebuild test/*.wasm from test/*.c and test/*.zig

`test/run.py` translates each test module and joins it with the runtime. It
then assembles and runs the program. It checks main's result in R1, and that
R7–R13 are unchanged. Most modules are built byte by byte with `test/wasm.py`.
The others are compiled from `test/*.c` and `test/*.zig`. Their `.wasm` files
are checked in, so `make test` needs no compiler. `make wasm` needs clang
with the wasm32 target, `wasm-ld`, and Zig 0.15. `test/errors.py` checks
every error message.
