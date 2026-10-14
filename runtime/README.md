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
| `__mul` | R1 × R2, the low 32 bits. Serves signed and unsigned operands. | R2, R3 |
| `__div`, `__mod` | Signed R1 / R2 and R1 % R2, rounding toward zero. | R2–R6 |
| `__udiv`, `__umod` | Unsigned R1 / R2 and R1 % R2. | R3–R6 |
| `__clz`, `__ctz` | The number of leading or trailing 0 bits in R1, 32 for 0. | R2 |
| `__popcnt` | The number of 1 bits in R1. | R2 |

The `long long` routines take their operands in R1:R2 and R3:R4, and
return the result in R1:R2, each pair low word first (§9.3):

| Label | Result in R1:R2 | Changes |
|---|---|---|
| `__mul64` | R1:R2 × R3:R4, the low 64 bits. Serves signed and unsigned operands. | R3–R6 |
| `__div64`, `__mod64` | Signed R1:R2 / R3:R4 and R1:R2 % R3:R4, rounding toward zero. | R3–R6 |
| `__udiv64`, `__umod64` | Unsigned R1:R2 / R3:R4 and R1:R2 % R3:R4. | R3–R6 |
| `__clz64`, `__ctz64` | The number of leading or trailing 0 bits in R1:R2, 64 for 0. | none |
| `__popcnt64` | The number of 1 bits in R1:R2. | R3, R4 |

Every routine changes the flags. A routine may change R1–R6 and the
flags, as §9.3 allows. The tables list what each one actually changes.

Division by zero is undefined in C, so the division routines return some
value for it and do not trap. The wasm translator checks for 0 before it
calls them. The most negative number divided by −1 gives the most
negative number.

The comments in `lib.asm` give the number of steps each routine takes.
The division routines take the same number for all operands of one sign,
for example 292 steps for `__udiv` and 839 for `__udiv64`. `__mul64` and
the counting routines take longer the more bits their operand has.

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
