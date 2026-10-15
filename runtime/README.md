# NICE runtime library

The start-up code and the runtime routines that compiled C code and
translated wasm code call. They follow the C ABI of
[doc/ISA.md §9.3](../doc/ISA.md#93-c-abi).

## Files

| File | What it is |
|---|---|
| `start.asm` | Start-up code for a program without a wasm module. |
| `start_wasm.asm` | Start-up code for a program with a wasm module. It calls `___wasm_start` before `main`. |
| `lib.asm` | The runtime routines in assembly, except those below. |
| `muldiv_mpu.asm` | The multiply and divide routines: `__mul`, `__div`, `__mod`, `__udiv`, `__umod`, and their `64` versions, with the math unit of ISA.md §8.4. |
| `muldiv_soft.asm` | The same routines in software, for a system without the math unit. |
| `float.zig` | The source of the float routines (see below). |
| `float.wasm` | `float.zig` and parts of Zig's compiler_rt, compiled to wasm. |
| `float.asm` | `float.wasm` translated as a library module. It is not checked in: `make float.asm` makes it, with Python only. |

There is no linker. A program is one assembly file, joined in this order:
one of the start-up files, the program's own files, `lib.asm`, one of the
two muldiv files, and `float.asm` if the program uses floats. For example:

    cat runtime/start.asm prog.asm runtime/lib.asm runtime/muldiv_mpu.asm > full.asm
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
| `__udiv64`, `__umod64` | Unsigned R1:R2 / R3:R4 and R1:R2 % R3:R4. | R5, R6 |
| `__clz64`, `__ctz64` | The number of leading or trailing 0 bits in R1:R2, 64 for 0. | none |
| `__popcnt64` | The number of 1 bits in R1:R2. | R3, R4 |

A routine may change R1–R6 and the flags, as §9.3 allows. The tables list
what each one actually changes in `lib.asm` and `muldiv_soft.asm`. The
versions in `muldiv_mpu.asm` change less: R5 for `__mul64`, nothing
besides the result for the others, and not the flags. They change the
operands of the math unit.

A program contains exactly one of the muldiv files. `muldiv_mpu.asm` needs
the math unit, which the emulator and the FPGA core have. It also defines
the labels `__mpu.a`, `__mpu.b`, and so on, for the words of the math
unit, and translated code that uses the math unit needs them (see
[translator/README.md](../translator/README.md), `--no-mpu`). A program
translated with `--no-mpu` must use `muldiv_soft.asm`.

Some labels are not C routines: the `__mpu.` names above, and
`__udivmod` and `__udivmod64` in `muldiv_soft.asm`, the unsigned divisions
that the division routines share. Every label is global in the joined
program (§9.3), so no other file may define these names either.

Division by zero is undefined in C, so the division routines return some
value for it and do not trap. The wasm translator checks for 0 before it
calls them. The most negative number divided by −1 gives the most
negative number.

The comments in the files give the number of steps each routine takes.
The division routines take the same number for all operands of one sign,
for example 292 steps for `__udiv` in `muldiv_soft.asm` and 839 for
`__udiv64`. `__mul64` in `muldiv_soft.asm` and the counting routines take
longer the more bits their operand has. In `muldiv_mpu.asm`, the one-word
routines take 4 steps each, `__mul64` 10, and the other `long long` ones 7.

`lib.asm` also holds the wasm trap vector of ISA.md §9.4:

| Label | What it is |
|---|---|
| `___wasm_trap_vector` | The word that wasm traps jump through. It starts as `___wasm_trap`. |
| `___wasm_trap` | The default handler: the reserved control word `0x0FE00000`. It halts with the trap's code in R1 and address in R2. The emulator exits with status 2, not 0 as after `HALT`. |

## Floating point

NICE has no float instructions, so `float.asm` does float arithmetic in
software. It is the library module `float` of ISA.md §9.4: wasm code,
translated by `nicewasm --library float`. Its routines take and return the
bits of the numbers, an `f32` in one word and an `f64` in two, low word
first, by the rules of §9.3. Most come unchanged from Zig's compiler_rt.
`float.zig` adds those whose meaning differs from C's, or that compiler_rt
has only with float instructions inside. It also has its own division,
because compiler_rt's gives 0 when the quotient is subnormal.

| Labels | Result |
|---|---|
| `___addsf3`, `___subsf3`, `___mulsf3`, `___divsf3` | f32 +, −, ×, and ÷, rounded to nearest. |
| `___adddf3`, `___subdf3`, `___muldf3`, `___divdf3` | The same for f64. |
| `___eqsf2`, `___nesf2`, `___ltsf2`, `___lesf2`, `___gtsf2`, `___gesf2` | Compare two f32: below 0, 0, or above 0, as libgcc does. For a NaN, the result makes the test fail, except for `ne`. |
| `___eqdf2` and the others with `df` | The same for f64. |
| `___floatsisf`, `___floatunsisf`, `___floatdisf`, `___floatundisf` | f32 from an `int`, `unsigned int`, `long long`, or `unsigned long long`. |
| `___floatsidf`, `___floatunsidf`, `___floatdidf`, `___floatundidf` | The same to f64. |
| `___fixsfsi`, `___fixunssfsi`, `___fixsfdi`, `___fixunssfdi` | f32 to those integers, toward 0. Out of range they saturate, and a NaN gives 0, as wasm's `trunc_sat` does. |
| `___fixdfsi`, `___fixunsdfsi`, `___fixdfdi`, `___fixunsdfdi` | The same from f64. |
| `___extendsfdf2`, `___truncdfsf2` | f32 to f64, and f64 to f32 rounded to nearest. |
| `___sqrtsf`, `___ceilsf`, `___floorsf`, `___truncsf`, `___nearestsf` | The square root, rounded to nearest, and rounding to an integral value: up, down, toward 0, and to nearest with ties to even. |
| `___minsf`, `___maxsf` | As wasm defines them: a NaN gives a NaN, and −0 is less than +0. |
| The same with `df` | For f64. |

The routines use the words `WL.float.memory` as their own stack, 256
words that are part of the program image. Assembled, `float.asm` is about
14600 words.

`make float` rebuilds `float.wasm` from `float.zig`. It needs Zig 0.15,
whose compiler_rt sources it copies next to `float.zig`. The routines must
not use the wasm float instructions, as `nicewasm` translates those into
calls to this library. `nicewasm` rejects a library module that uses them.

## Test

    make test

This builds the emulator, then joins each `test/X.asm` with a start-up file,
`lib.asm`, and `muldiv_mpu.asm`. It assembles and runs the result and
compares the output and exit status with `test/X.expected`. The tests of
the muldiv routines run a second time with `muldiv_soft.asm`, and compare
with `test/X_soft.expected`. The expected values were checked by
hand. The comments in each test show how.
