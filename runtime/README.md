# NICE runtime library

The start-up code and the runtime routines that compiled C code and
translated wasm code call. They follow the C ABI of
[doc/ISA.md §9.3](../doc/ISA.md#93-c-abi).

## Files

| File | What it is |
|---|---|
| `start.asm` | Start-up code for a program without a wasm module. |
| `start_wasm.asm` | Start-up code for a program with a wasm module. It calls `___wasm_start` before `main`. |
| `lib.asm` | The runtime routines. |

There is no linker. A program is one assembly file, joined in this order:
one of the start-up files, the program's own files, and `lib.asm`. For
example:

    cat runtime/start.asm prog.asm runtime/lib.asm > full.asm
    assembler/niceasm.py full.asm
    emulator/zig-out/bin/niceemu full.bin

The start-up code sets SP to `0xFFFFFF00`, calls `_main` with R1 = 0 and
R2 = 0 (no `argc` or `argv`), and halts with `main`'s result in R1. It is
the only file that uses `.ORG`.

## Routines

| Label | Result in R1 | Changes |
|---|---|---|
| `__mul` | R1 × R2, the low 32 bits. Serves signed and unsigned operands. | R2, R3, and the flags |

A routine may change R1–R6 and the flags, as §9.3 allows. The table lists
what each one actually changes. ISA.md §9.3 and §9.4 name more routines,
such as `__div` and `__udiv`, that are not written yet.

`lib.asm` also holds the wasm trap vector of ISA.md §9.4:

| Label | What it is |
|---|---|
| `___wasm_trap_vector` | The word that wasm traps jump through. It starts as `___wasm_trap`. |
| `___wasm_trap` | The default handler: the reserved control word `0x0FE00000`. It halts with the trap's code in R1 and address in R2. The emulator exits with status 2, not 0 as after `HALT`. |

## Test

    make test

This builds the emulator, then joins each `test/X.asm` with a start-up file
and `lib.asm`. It assembles and runs the result and compares the output and
exit status with `test/X.expected`. The expected values were checked by
hand. The comments in each test show how.
