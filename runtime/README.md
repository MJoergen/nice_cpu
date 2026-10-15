# NICE runtime library

The start-up code and the runtime routines that compiled C code and
translated wasm code call. They follow the C ABI of
[doc/ISA.md §9.3](../doc/ISA.md#93-c-abi).

## Files

| File | What it is |
|---|---|
| `start.nasm` | Start-up code for a program without a wasm module. |
| `start_wasm.nasm` | Start-up code for a program with a wasm module. It calls `___wasm_start` before `main`. |
| `lib.nasm` | The runtime routines in assembly, except those below. |
| `muldiv_mpu.nasm` | The multiply and divide routines: `__mul`, `__div`, `__mod`, `__udiv`, `__umod`, and their `64` versions, with the math unit of ISA.md §8.4. |
| `muldiv_soft.nasm` | The same routines in software, for a system without the math unit. |
| `float.zig` | The source of the float routines (see below). |
| `float.wasm` | `float.zig` and parts of Zig's compiler_rt, compiled to wasm. |
| `float.nasm` | `float.wasm` translated as a library module. It is not checked in: `make float.nasm` makes it, with Python only. |

There is no linker. A program is one assembly file, joined in this order:
one of the start-up files, the program's own files, `lib.nasm`, one of the
two muldiv files, and `float.nasm` if the program uses floats. For example:

    cat runtime/start.nasm prog.nasm runtime/lib.nasm runtime/muldiv_mpu.nasm > full.nasm
    assembler/niceasm.py full.nasm
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
what each one actually changes in `lib.nasm` and `muldiv_soft.nasm`. The
versions in `muldiv_mpu.nasm` change less: R5 for `__mul64`, nothing
besides the result for the others, and not the flags. They change the
operands of the math unit.

A program contains exactly one of the muldiv files. `muldiv_mpu.nasm` needs
the math unit, which the emulator and the FPGA core have. It also defines
the labels `__mpu.a`, `__mpu.b`, and so on, for the words of the math
unit, and translated code that uses the math unit needs them (see
[translator/README.md](../translator/README.md), `--no-mpu`). A program
translated with `--no-mpu` must use `muldiv_soft.nasm`.

Some labels are not C routines: the `__mpu.` names above, and
`__udivmod` and `__udivmod64` in `muldiv_soft.nasm`, the unsigned divisions
that the division routines share. Every label is global in the joined
program (§9.3), so no other file may define these names either.

Division by zero is undefined in C, so the division routines return some
value for it and do not trap. The wasm translator checks for 0 before it
calls them. The most negative number divided by −1 gives the most
negative number.

The comments in the files give the number of steps each routine takes.
The division routines take the same number for all operands of one sign,
for example 292 steps for `__udiv` in `muldiv_soft.nasm` and 839 for
`__udiv64`. `__mul64` in `muldiv_soft.nasm` and the counting routines take
longer the more bits their operand has. In `muldiv_mpu.nasm`, the one-word
routines take 4 steps each, `__mul64` 10, and the other `long long` ones 7.

`lib.nasm` also holds the wasm trap vector of ISA.md §9.4:

| Label | What it is |
|---|---|
| `___wasm_trap_vector` | The word that wasm traps jump through. It starts as `___wasm_trap`. |
| `___wasm_trap` | The default handler: the reserved control word `0x0FE00000`. It halts with the trap's code in R1 and address in R2. The emulator exits with status 2, not 0 as after `HALT`. |

## Floating point

NICE has no float instructions, so `float.nasm` does float arithmetic in
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
words that are part of the program image. Assembled, `float.nasm` is about
14600 words.

`make float` rebuilds `float.wasm` from `float.zig`. It needs Zig 0.15,
whose compiler_rt sources it copies next to `float.zig`. The routines must
not use the wasm float instructions, as `nicewasm` translates those into
calls to this library. `nicewasm` rejects a library module that uses them.

## C library

`libc/` is a small C standard library for C code that reaches NICE
through wasm. It is written in C and compiled to wasm, to the archive
`libc/libc.a`, which `make -C runtime/libc` builds with clang. wasm-ld
links it into the program's module and keeps only the functions the
program uses. So it adds nothing to the joined assembly files.

| Header | Functions |
|---|---|
| `stdio.h` | `putchar`, `puts`, `printf`, `sprintf`, `snprintf`, `vprintf`, `vsprintf`, `vsnprintf` |
| `string.h` | `memcpy`, `memmove`, `memset`, `memcmp`, `memchr`, `strlen`, `strnlen`, `strcmp`, `strncmp`, `strcpy`, `strncpy`, `strcat`, `strncat`, `strchr`, `strrchr`, `strstr` |
| `stdlib.h` | `malloc`, `calloc`, `realloc`, `free`, `abs`, `labs`, `llabs`, `atoi`, `atol`, `strtol`, `strtoul`, `abort` |
| `ctype.h` | `isalnum`, `isalpha`, `iscntrl`, `isdigit`, `isgraph`, `islower`, `isprint`, `ispunct`, `isspace`, `isupper`, `isxdigit`, `tolower`, `toupper` |
| `nice.h` | `nice_peek` and `nice_poke`, the `nice` imports of ISA.md §9.4, and `NICE_CONSOLE` |

`putchar` writes to the console at `0xFFFFFF00` with `nice_poke`. It is
the only function that touches hardware. Clang's own `stddef.h`,
`stdint.h`, `stdarg.h`, `stdbool.h`, and `limits.h` complete the headers.

The library is small on purpose:

- Output only. There is no `getchar`, because the console has no input
  yet.
- No `FILE`, `stdout`, or `fprintf`.
- `printf` supports the flags `- + space # 0`, a width and a precision
  (either may be `*`), the length modifiers `hh h l ll z t j`, and the
  conversions `d i u o x X c s p %`. The float conversions, such as `%f`,
  take their argument and are printed as they stand, as is any other
  unknown conversion. `%p` prints `0x` and the address in hex.
- No `errno`. `strtol` and `strtoul` saturate on overflow.
- No `exit`. `abort` traps (ISA.md §9.4).
- `malloc` is first fit, with an 8-byte header on each block, and merges
  neighbouring free blocks. The heap starts at wasm-ld's `__heap_base`
  and grows with `memory.grow`, so only up to nicewasm's
  `--memory-pages`.

Compile with the library's headers and link with `libc.a`, for example:

    make -C runtime/libc
    clang --target=wasm32 -mbulk-memory -O2 -ffreestanding -nostdlibinc \
        -isystem runtime/libc/include -nostdlib -Wl,--no-entry -Wl,--export=main \
        -Wl,-z,stack-size=4096 -Wl,--initial-memory=65536 \
        -o prog.wasm prog.c runtime/libc/libc.a

Then translate, join, and assemble as for any wasm module
([translator README](../translator/README.md)). `-ffreestanding` keeps
clang from treating the library's functions as built-ins, for example from
turning `printf("x\n")` into `puts("x")`. `-mbulk-memory` matters
here too: the library's `memcpy`, `memmove`, and `memset` are
`memory.copy` and `memory.fill`.

**From Zig and Rust.** The library is plain wasm code with C names, so
Zig and Rust code can call it too, but this is not the preferred way. It
ties a Zig or Rust program to a C library and to clang, and `printf`
loses the type checks of the languages' own formatting. To try it, declare
the functions and link `libc.a`:

    // Zig
    extern fn printf(fmt: [*:0]const u8, ...) c_int;
    zig build-exe ... prog.zig runtime/libc/libc.a

    // Rust
    extern "C" { fn printf(fmt: *const u8, ...) -> i32; }
    rustc ... -C link-arg=runtime/libc/libc.a prog.rs

The preferred way is a small support module in each language, written in
that language, with the same split as the C library. Only its console
code calls `nice.poke`. For Zig, that is a writer for the console, so
that `std.fmt` can print through it. For Rust, it is a type that
implements `core::fmt::Write`, `print!` and `println!` macros on top of
it, and a `#[global_allocator]` for `alloc`. Neither exists yet
([TODO.md](../TODO.md)).

## Test

    make test

This builds the emulator, then joins each `test/X.nasm` with a start-up file,
`lib.nasm`, and `muldiv_mpu.nasm`. It assembles and runs the result and
compares the output and exit status with `test/X.expected`. The tests of
the muldiv routines run a second time with `muldiv_soft.nasm`, and compare
with `test/X_soft.expected`. The expected values were checked by
hand. The comments in each test show how.

Then it runs the C library's tests, `libc/test/X.c`. Their `.wasm` files
are checked in, so no C compiler is needed; `make -C libc wasm` rebuilds
them and `libc.a`. Each is translated, joined with `start_wasm.nasm`,
`lib.nasm`, and `muldiv_mpu.nasm`, and run. Its console output, `main`'s result in R1, and the
exit status are compared with `libc/test/X.expected`, which was written
by hand from the source.
