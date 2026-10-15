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
| `libc/` | A small C library (see below). |
| `nice.zig`, `nice.rs` | The device routines and console output for Zig and Rust (see below). |

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

## Device routines

`lib.nasm` also has the device routines of ISA.md §9.3, for the console,
the performance counters, and the emulator's character screen. Programs
call them instead of using the devices' addresses. They are C functions,
so their labels are their C names with `_` in front.

| Label | C declaration | What it does | Changes |
|---|---|---|---|
| `_nice_putc` | `void nice_putc(int c)` | Writes bits 7..0 of R1 to the console. | none |
| `_nice_getc` | `int nice_getc(void)` | Waits for the next input byte and returns it, 0 to 255, or −1 once the input has ended. | flags |
| `_nice_pollc` | `int nice_pollc(void)` | Like `nice_getc`, but returns −2 at once if no byte is waiting. | flags |
| `_nice_print` | `void nice_print(const char *s)` | Writes the string at R1, one character per word, up to its first 0 word, with no newline. | R1, R2, flags |
| `_nice_cycles` | `unsigned long long nice_cycles(void)` | R1:R2 = the cycle counter. | none |
| `_nice_instructions` | `unsigned long long nice_instructions(void)` | R1:R2 = the instruction counter. | none |
| `_nice_screen_put` | `void nice_screen_put(int col, int row, int c)` | Writes R3 to column R1, 0 to 79, of row R2, 0 to 24. | R2, R4 |
| `_nice_screen_clear` | `void nice_screen_clear(void)` | Writes `0x20` to each of the screen's 2000 words. | R1, flags |

From assembly, for example:

        MOVE    R1, text
        ADD     @--R13, 2, R15
        MOVE    R15, _nice_print
        ...
text    .ASCII_L 'Hello'

The counter routines read the low word first, as ISA.md §8.5 describes.
So an interrupt service routine that reads a counter can spoil the reading
of the code it interrupted. The screen routines write `0xFFFF0000` to
`0xFFFF07CF`, so with the emulator's `-2004` they miss the screen. On a
system without a screen, those words are RAM or nothing.

The C library below has the same routines, in `nice.h`.

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
| `stdio.h` | `putchar`, `puts`, `getchar`, `printf`, `sprintf`, `snprintf`, `vprintf`, `vsprintf`, `vsnprintf`, `scanf`, `sscanf`, `vscanf`, `vsscanf` |
| `string.h` | `memcpy`, `memmove`, `memset`, `memcmp`, `memchr`, `strlen`, `strnlen`, `strcmp`, `strncmp`, `strcpy`, `strncpy`, `strcat`, `strncat`, `strchr`, `strrchr`, `strstr` |
| `stdlib.h` | `malloc`, `calloc`, `realloc`, `free`, `abs`, `labs`, `llabs`, `atoi`, `atol`, `strtol`, `strtoul`, `abort` |
| `ctype.h` | `isalnum`, `isalpha`, `iscntrl`, `isdigit`, `isgraph`, `islower`, `isprint`, `ispunct`, `isspace`, `isupper`, `isxdigit`, `tolower`, `toupper` |
| `nice.h` | The device routines (see above): `nice_putc`, `nice_getc`, `nice_pollc`, `nice_print`, `nice_cycles`, `nice_instructions`, `nice_screen_put`, and `nice_screen_clear`. Also `nice_peek` and `nice_poke`, the `nice` imports of ISA.md §9.4, and the devices' addresses, for devices that have no routine. |

The device routines, in `src/nice.c`, are the only functions that touch
hardware. They use `nice_peek` and `nice_poke`. `nice_print` writes the
bytes of a C string in linear memory, where `_nice_print` in `lib.nasm`
writes one character per word. `putchar` and `puts` write with `nice_putc` and
`nice_print`, and `getchar` reads with `nice_getc` (ISA.md §8.3).
`getchar` waits until a byte is there. It
returns `EOF` once the emulator's input has ended, which a UART's input
never does. The emulator reads the input from stdin, or from the file
that `--input` names. Clang's own `stddef.h`,
`stdint.h`, `stdarg.h`, `stdbool.h`, and `limits.h` complete the headers.

The library is small on purpose:

- No `FILE`, `stdin`, `stdout`, `fprintf`, `ungetc`, or `fgets`.
- `scanf` and `sscanf` support white space and ordinary characters in the
  format, `*` to read without storing, a width, the length modifiers
  `hh h l ll z t j`, and the conversions `d i u o x X p c s [ n %`. A set
  in `[` may hold ranges such as `a-z`, and `^` first negates it. There
  are no float conversions. `scanf` gives back the one byte it read too
  far, for the next `getchar` or `scanf`.
- `printf` supports the flags `- + space # 0`, with `+` and space for the
  signed conversions only, as C defines them, a width and a precision
  (either may be `*`), the length modifiers `hh h l ll z t j`, and the
  conversions `d i u o x X c s p %`. The float conversions, such as `%f`,
  take their argument and are printed as they stand, as is any other
  unknown conversion. `%p` prints `0x` and the address in hex, `0x0` for a
  null pointer.
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
        -Wl,--stack-first -Wl,-z,stack-size=4096 -Wl,--initial-memory=65536 \
        -o prog.wasm prog.c runtime/libc/libc.a

Then translate, join, and assemble as for any wasm module
([translator README](../translator/README.md)). `-ffreestanding` keeps
clang from treating the library's functions as built-ins, for example from
turning `printf("x\n")` into `puts("x")`. `-mbulk-memory` matters
here too: the library's `memcpy`, `memmove`, and `memset` are
`memory.copy` and `memory.fill`. `--stack-first` makes an overflow of the
program's stack in linear memory trap instead of overwriting the data
(translator README); each `printf` call takes some of that stack for its
arguments.

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

The preferred way is `nice.zig` or `nice.rs`, below.

## Zig and Rust

`nice.zig` and `nice.rs` give Zig and Rust code the device routines that
`nice.h` gives C code, with names and types that suit each language, and
console output through the language's own formatting. They declare the
routines as imports from `env`, which the translator calls at their labels
(ISA.md §9.4), so the calls go to the assembly routines in `lib.nasm`.
`nice_print` is left out, since it takes one character per word; `write`
prints a byte slice instead.

| | Zig, `nice.zig` | Rust, `nice.rs` |
|---|---|---|
| The `nice` imports | `peek`, `poke` | `peek`, `poke`, safe wrappers |
| Output | `putc(c)`, `write(bytes)`, `print(fmt, args)` with `std.fmt`, and `writer`, a `std.Io.Writer` | `putc(c)`, `write(bytes)`, `print!` and `println!` with `core::fmt`, and `Console`, a `core::fmt::Write` |
| Input | `getc()`, a `?u8`, and `pollc()`, a `Poll`: `.byte`, `.empty`, or `.end` | `getc()`, an `Option<u8>`, and `pollc()`, a `Poll`: `Byte`, `Empty`, or `End` |
| Counters | `cycles()`, `instructions()` | `cycles()`, `instructions()` |
| Screen | `screenPut(col, row, c)`, `screenClear()`, `screen_cols`, `screen_rows` | `screen_put(col, row, c)`, `screen_clear()`, `SCREEN_COLS`, `SCREEN_ROWS` |

`getc` waits until a byte is there, and returns null or `None` once the
emulator's input has ended, as `nice_getc` returns −1. There is no
formatted input, as `scanf` gives C.

For Zig, add the file as the module `nice`, and import it with
`const nice = @import("nice");`:

    zig build-exe -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall \
        -fstrip --stack 4096 --initial-memory=65536 \
        --dep nice -Mroot=prog.zig -Mnice=runtime/nice.zig

For Rust, mount the file at the crate root as the module `nice`, so that
`print!` and `println!` find it, in a `#![no_std]` program:

    #[path = "runtime/nice.rs"]
    mod nice;

and compile as the [translator README](../translator/README.md) shows.
`test/nicezig.zig` and `test/nicers.rs` are examples.

## Test

    make test

This builds the emulator, then joins each `test/X.nasm` with a start-up file,
`lib.nasm`, and `muldiv_mpu.nasm`. It assembles and runs the result and
compares the output and exit status with `test/X.expected`. The tests of
the muldiv routines run a second time with `muldiv_soft.nasm`, and compare
with `test/X_soft.expected`. `test/device.nasm` reads `test/device.input`
as its console input. The expected values were checked by
hand. The comments in each test show how.

Then it runs the C library's tests, `libc/test/X.c`, with
`libc/test/X.input` as the console input if there is one. Their `.wasm` files
are checked in, so no C compiler is needed; `make -C libc wasm` rebuilds
them and `libc.a`. Each is translated, joined with `start_wasm.nasm`,
`lib.nasm`, and `muldiv_mpu.nasm`, and run. Its console output, `main`'s result in R1, and the
exit status are compared with `libc/test/X.expected`, which was written
by hand from the source.

Then it runs the tests of `nice.zig` and `nice.rs`, `test/nicezig.zig` and
`test/nicers.rs`, the same way, with `test/X.input` as the console input
and `test/X.expected`, written by hand from the source. Their `.wasm`
files are checked in; `make wasm` rebuilds them, with Zig 0.15 and rustc
with the `wasm32-unknown-unknown` target.

`make -C libc fuzz` needs clang. It runs `libc/test/fuzz_printf.py`,
which writes a C program with 300 random `printf` and `snprintf` calls,
with every flag, width, precision, length modifier, and integer
conversion, and compares the output with a model of C's `printf` in
Python. `fuzz_printf.py SEED COUNT` runs other seeds and sizes.
