# NICE runtime library

The start-up code and the runtime routines that compiled C code and
translated wasm code call. They follow the C ABI of
[ABI.md](ABI.md).

Which section to read: for a C program, [C library](#c-library); for a
Zig or Rust program, [Zig and Rust](#zig-and-rust); and for a program in
assembly, [Files](#files), [Joining a program](#joining-a-program), and
the routines it can call under [Routines](#routines) and [Device
routines](#device-routines). `nicebuild.py` of the translator joins a C,
Zig, or Rust program by itself ([translator README](../translator/README.md)).

## Files

| File | What it is |
|---|---|
| `start.nasm` | Start-up code for a program without a wasm module. |
| `start_wasm.nasm` | Start-up code for a program with a wasm module. It calls `___wasm_start` before `main`. |
| `start_wasm_trap.nasm` | `start_wasm.nasm` with its trap vector holding the trap report below. |
| `start_mon.nasm`, `start_wasm_mon.nasm`, `start_wasm_trap_mon.nasm` | The same three for a program that a monitor in ROM runs (ABI.md, "Programs under a monitor"): at `0x8000`, above the ROM, on the monitor's stack, with the monitor's putc routine in `___putc_vector`, and returning to the monitor instead of halting. |
| `lib.nasm` | The runtime routines in assembly, except those below. It holds no word that is written: the vectors it jumps through are in the start-up files. |
| `trapmsg.nasm` | The trap report below. It goes after `lib.nasm`, and only with `start_wasm_trap.nasm` or `start_wasm_trap_mon.nasm`. |
| `muldiv_mpu.nasm` | The routines that the math unit of SYSTEM.md §2 does: `__mul`, `__div`, `__mod`, `__udiv`, `__umod`, and their `64` versions, the bit counts `__clz`, `__ctz`, and `__popcnt`, and `_nice_isqrt64`, with the math unit. |
| `muldiv_soft.nasm` | The same routines in software, for a system without the math unit. |
| `float.zig` | The source of the float routines (see below). |
| `float.wasm` | `float.zig` and parts of Zig's compiler_rt, compiled to wasm. |
| `float.nasm` | `float.wasm` translated as a library module. It is not checked in: `make float.nasm` makes it, with Python only. |
| `libc/` | A small C library (see below). |
| `nice.zig`, `nice.rs` | The device routines, console output, and a heap for Zig and Rust (see below). |

## Joining a program

There is no linker. A program is one assembly file, made by joining these
files with `cat`, in this order:

1. One start-up file: `start.nasm`, `start_wasm.nasm`, or
   `start_wasm_trap.nasm`, or its `_mon` version for a program under a
   monitor.
2. The program's own files, in any order: hand-written assembly files,
   compiled units (ABI.md), and the translated wasm module, if there is
   one.
3. `lib.nasm`.
4. `muldiv_mpu.nasm`, or `muldiv_soft.nasm` for a system without the math
   unit and for a program translated with `--no-mpu`.
5. `float.nasm`, if the program uses floats.
6. `trapmsg.nasm`, with `start_wasm_trap.nasm` or
   `start_wasm_trap_mon.nasm`.

For example:

    cat runtime/start.nasm prog.nasm runtime/lib.nasm runtime/muldiv_mpu.nasm > full.nasm
    assembler/niceasm.py full.nasm
    emulator/zig-out/bin/niceemu full.bin

The start-up code sets SP to `0xFFFFFF00`, calls `_main` with R1 = 0 and
R2 = 0 (no `argc` or `argv`), and halts with `main`'s result in R1. Each
start-up file also defines `_exit`, the C library's `exit`: in these
three, the `HALT` after `main`. The `_mon` versions are for a program that
a monitor in ROM, such as the one that
[NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65) will have, loads at
`0x8000` and calls with R1 = its putc routine or 0, R2 = `argc`, and
R3 = `argv`: they leave SP as the monitor set it, store a nonzero R1 in
`___putc_vector`, pass `argc` and `argv` to `main`, and return to the
monitor with `main`'s result in R1 instead of halting, and their `_exit`
restores SP and returns the same way. The start-up files are the only ones
that use `.ORG`. Each also defines the two vectors that `lib.nasm` jumps
through, `___wasm_trap_vector` and `___putc_vector` (below), so that a
system whose code runs from a ROM, with start-up code of its own, can put
them in its RAM (ABI.md, Start-up).

## Routines

| Label | Result in R1 | Changes |
|---|---|---|
| `__mul` | R1 × R2, the low 32 bits. Serves signed and unsigned operands. | R2, R3 |
| `__div`, `__mod` | Signed R1 / R2 and R1 % R2, rounding toward zero. | R2–R6 |
| `__udiv`, `__umod` | Unsigned R1 / R2 and R1 % R2. | R3–R6 |
| `__clz`, `__ctz` | The number of leading or trailing 0 bits in R1, 32 for 0. | R2 |
| `__popcnt` | The number of 1 bits in R1. | R2 |
| `_nice_isqrt64` | floor(√(R1:R2)), unsigned, as `ISQRT64_Q` of SYSTEM.md §2. | R2–R6 |

`_nice_isqrt64` has a C name, `nice_isqrt64`, so that the float library,
a wasm module, can import it from `env` (WASM.md): its f32 square root
calls it. The other routines of the first table are in the muldiv files,
since the math unit computes them too.

The `long long` routines take their operands in R1:R2 and R3:R4, and
return the result in R1:R2, each pair low word first (ABI.md):

| Label | Result in R1:R2 | Changes |
|---|---|---|
| `__mul64` | R1:R2 × R3:R4, the low 64 bits. Serves signed and unsigned operands. | R3–R6 |
| `__div64`, `__mod64` | Signed R1:R2 / R3:R4 and R1:R2 % R3:R4, rounding toward zero. | R3–R6 |
| `__udiv64`, `__umod64` | Unsigned R1:R2 / R3:R4 and R1:R2 % R3:R4. | R5, R6 |
| `__clz64`, `__ctz64` | The number of leading or trailing 0 bits in R1:R2, 64 for 0. | none |
| `__popcnt64` | The number of 1 bits in R1:R2. | R3, R4 |

A routine may change R1–R6 and the flags, as ABI.md allows. The tables list
what each one actually changes in `lib.nasm` and `muldiv_soft.nasm`.
`__clz64`, `__ctz64`, and `__popcnt64` are in `lib.nasm`, and call
`__clz`, `__ctz`, and `__popcnt`, so `lib.nasm` needs one of the muldiv
files. The
versions in `muldiv_mpu.nasm` change less: R5 for `__mul64`, nothing
besides the result for the others, and not the flags. They change the
operands of the math unit.

A program contains exactly one of the muldiv files. `muldiv_mpu.nasm` needs
the math unit, which the emulator and the FPGA core have. It also defines
the labels `__mpu.a`, `__mpu.b`, and so on, for the words of the math
unit, and translated code that uses the math unit needs them (see
[translator/README.md](../translator/README.md), `--no-mpu`). A program
translated with `--no-mpu` must use `muldiv_soft.nasm`.

Some labels are not C routines: the `__mpu.` names above, the `__nice.`
names in `lib.nasm` that give the devices' addresses (`__nice.console`,
`__nice.cycle_lo`, `__nice.cycle_hi`, `__nice.instr_lo`, `__nice.instr_hi`,
and `__nice.screen`), `__udivmod` and `__udivmod64` in
`muldiv_soft.nasm`, the unsigned divisions that the division routines
share, `___console_putc` in `lib.nasm`, `_exit`, `___putc_vector`, and
`___wasm_trap_vector` in the start-up files and `___exit.sp` in the `_mon`
ones, and
`___trap_report` and the `___trap.` names in `trapmsg.nasm`. Every label is global in the joined
program (ABI.md), so no other file may define these names either.

Division by zero is undefined in C, so the division routines return some
value for it and do not trap. The wasm translator checks for 0 before it
calls them. In `muldiv_mpu.nasm` the quotient is all ones and the
remainder the dividend (SYSTEM.md §2). `muldiv_soft.nasm` gives the same,
except that `__div` and `__div64` give 1 for a negative dividend. The most
negative number divided by −1 gives the most negative number.

The comments in the files give the number of steps each routine takes.
The division routines take the same number for all operands of one sign,
for example 292 steps for `__udiv` in `muldiv_soft.nasm` and 839 for
`__udiv64`. `__mul64` in `muldiv_soft.nasm` and the counting routines take
longer the more bits their operand has. In `muldiv_mpu.nasm`, the one-word
routines take 4 steps each, `__mul64` 10, and the other `long long` ones 7.

The wasm traps of WASM.md jump through the start-up code's vector to
`lib.nasm`'s default handler:

| Label | What it is |
|---|---|
| `___wasm_trap_vector` | The word of the start-up code that wasm traps jump through. It starts as `___wasm_trap`, or as `___trap_report` in `start_wasm_trap.nasm` and `start_wasm_trap_mon.nasm`. |
| `___wasm_trap` | The default handler: the reserved control word `0x0FE00000`. It halts with the trap's code in R1 and address in R2. The emulator exits with status 2, not 0 as after `HALT`. |

**The trap report.** The default handler halts without a word.
`trapmsg.nasm` has `___trap_report`, a handler that first writes a line
to the console and then jumps to `___wasm_trap`:

- `nicebuild.py` installs it unless given `--no-trap-report`. By hand, a
  program joins `trapmsg.nasm` after the other files and starts with
  `start_wasm_trap.nasm`, which is `start_wasm.nasm` with
  `___wasm_trap_vector` starting as `___trap_report`, or with
  `start_wasm_trap_mon.nasm` under a monitor.
- The line is such as `trap 2: memory access out of bounds at 00003dc9`,
  with the code of R1 and the address of R2, a NICE address, naming the
  trap as `niceemu --symbols` does (a code above 7 is `trap ?: unknown
  trap`). It prints with `nice_print` and `nice_putc`, so through
  `___putc_vector` (below), and under a monitor on the monitor's output.
  With `niceasm.py --symbols` or `nicebuild.py --symbols`, and `niceemu
  --symbols`, the emulator also names the function.
- The processor still halts at `___wasm_trap`, with R1 and R2 as the trap
  left them, and the emulator still exits with status 2. The report uses
  R9, R10, and R11, the routine behind the vector may change R3–R6 and the
  flags, and it uses the stack at SP, so after a stack overflow it may
  fail itself.

## Device routines

`lib.nasm` also has the device routines of ABI.md, for the console,
the performance counters, and the emulator's character screen. Programs
call them instead of using the devices' addresses. They are C functions,
so their labels are their C names with `_` in front.

| Label | C declaration | What it does | Changes |
|---|---|---|---|
| `_nice_putc` | `void nice_putc(int c)` | Writes bits 7..0 of R1 through `___putc_vector` (below). | none, or what the routine behind the vector changes |
| `_nice_getc` | `int nice_getc(void)` | Waits for the next input byte and returns it, 0 to 255, or −1 once the line's input has ended (SYSTEM.md §1). | flags |
| `_nice_pollc` | `int nice_pollc(void)` | Like `nice_getc`, but returns −2 at once if no byte is waiting. | flags |
| `_nice_print` | `void nice_print(const char *s)` | Writes the string at R1, one character per word, up to its first 0 word, with no newline, through `___putc_vector`. | R1, flags, and what the routine changes |
| `_nice_cycles` | `unsigned long long nice_cycles(void)` | R1:R2 = the cycle counter. | none |
| `_nice_instructions` | `unsigned long long nice_instructions(void)` | R1:R2 = the instruction counter. | none |
| `_nice_screen_put` | `void nice_screen_put(int col, int row, int c)` | Writes R3 to column R1, 0 to 79, of row R2, 0 to 24. | R2, R4 |
| `_nice_screen_clear` | `void nice_screen_clear(void)` | Writes `0x20` to each of the screen's 2000 words. | R1, flags |

From assembly, for example:

                    MOVE    R1, text
                    CALL    _nice_print
                    ...
text    .ASCII_L 'Hello'

`___putc_vector` is the word of the start-up code that `_nice_putc` jumps
through, and that `_nice_print` calls through for each character, with its pointer in R7
across the calls. It starts as `___console_putc`, which writes bits 7..0
of R1 to the console and changes nothing. The start-up code of a program
under a monitor stores the monitor's putc routine in it (ABI.md), and an
assembly program may store a routine of its own, which follows the C ABI,
takes the character in bits 7..0 of R1, and may change R1–R6 and the
flags, as `_nice_putc` and `_nice_print` then may. The vector costs a step
per character; a UART's rate is the limit on a board anyway. The input
has no vector, as the console's input is the line and the keyboard both.

The counter routines read the low word first, as SYSTEM.md §3 describes.
So an interrupt service routine that reads a counter can spoil the reading
of the code it interrupted. The screen routines write `0xFFFF0000` to
`0xFFFF07CF`, so with the emulator's `-2004` they miss the screen. On a
system without a screen, those words are RAM or nothing.

The C library below has the same routines, in `nice.h`.

## Floating point

NICE has no float instructions, so `float.nasm` does float arithmetic in
software. It is the library module `float` of WASM.md: wasm code,
translated by `nicewasm --library float --no-mpu`. With `--no-mpu` its
one u64 divide calls `__udiv64`, so the library joins with either
`muldiv_mpu.nasm` or `muldiv_soft.nasm`. Its routines take and return the
bits of the numbers, an `f32` in one word and an `f64` in two, low word
first, by the rules of ABI.md. Most come unchanged from Zig's compiler_rt.
`float.zig` adds those whose meaning differs from C's, or that compiler_rt
has only with float instructions inside. It also has its own division,
because compiler_rt's gives 0 when the quotient is subnormal. The f32
quotient is one u64 divide, and the f64 one is found bit by bit. The f32
square root takes its root with `_nice_isqrt64`, and the f64 one bit by
bit, as its radicand needs 128 bits.

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
6900 words, 7150 with its stack.

`make float` rebuilds `float.wasm` from `float.zig`. It needs Zig 0.17,
whose compiler_rt sources it copies next to `float.zig`. The routines must
not use the wasm float instructions, as `nicewasm` translates those into
calls to this library. `nicewasm` rejects a library module that uses them.

## C library

`libc/` is a small C standard library for C code that reaches NICE
through wasm. It is written in C and compiled to wasm, to the archive
`libc/libc.a`, which `make -C runtime/libc` builds with clang. wasm-ld
links it into the program's module and, as it collects unused sections by
default, keeps only the functions the program uses. So it adds
nothing to the joined assembly files. The Zig recipe below does the same:
Zig keeps only the objects of `libc.a` that the program references.

| Header | Functions |
|---|---|
| `stdio.h` | `FILE`, `stdin`, `stdout`, `stderr`, `putchar`, `puts`, `getchar`, `fputc`, `putc`, `fputs`, `fgetc`, `getc`, `ungetc`, `fgets`, `fflush`, `printf`, `fprintf`, `sprintf`, `snprintf`, `vprintf`, `vfprintf`, `vsprintf`, `vsnprintf`, `scanf`, `fscanf`, `sscanf`, `vscanf`, `vfscanf`, `vsscanf` |
| `string.h` | `memcpy`, `memmove`, `memset`, `memcmp`, `memchr`, `strlen`, `strnlen`, `strcmp`, `strncmp`, `strcpy`, `strncpy`, `strcat`, `strncat`, `strchr`, `strrchr`, `strstr`, `strcspn` |
| `stdlib.h` | `malloc`, `calloc`, `realloc`, `free`, `abs`, `labs`, `llabs`, `atoi`, `atol`, `strtol`, `strtoul`, `atof`, `strtod`, `strtof`, `rand`, `srand`, `abort`, `exit` |
| `math.h` | In double, and in float with an `f`, such as `sinf`: `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log`, `log10`, `log2`, `pow`, `sqrt`, `fmod`, `frexp`, `ldexp`, `scalbn`, `modf`, `floor`, `ceil`, `trunc`, `round`, `rint`, `nearbyint`, `fabs`, `copysign`, `fmin`, and `fmax`. The macros `fpclassify`, `isfinite`, `isinf`, `isnan`, `isnormal`, `signbit`, `HUGE_VAL`, `HUGE_VALF`, `INFINITY`, `NAN`, and `math_errhandling`, the types `float_t` and `double_t`, and POSIX's constants, such as `M_PI`. See Math functions below. |
| `assert.h` | `assert` and `static_assert`. A failed `assert` prints `file:line: function: Assertion `expr' failed.` and calls `abort`. `-DNDEBUG` removes the checks. |
| `time.h` | `clock`, with `CLOCKS_PER_SEC` 1000000 and `clock_t` unsigned, from the microsecond counter of SYSTEM.md §3, which counts the host's time in the emulator, and wraps after 71.6 minutes on a board; `time`, which returns −1 because no device has the date; and the types `clock_t` and `time_t`. |
| `errno.h` | `errno`, one for the whole program, 0 at start, and the codes `EINVAL`, `EDOM`, `ERANGE`, and `EILSEQ`. Only the conversions from text set it: `strtol` and `strtoul`, and so `atoi` and `atol`, to `ERANGE` on an overflow and to `EINVAL` for a base other than 0 and 2 to 36, and `strtod` and `strtof`, and so `atof` and `scanf`, to `ERANGE` when a float overflows or underflows, and to `EINVAL` when there is none. |
| `ctype.h` | `isalnum`, `isalpha`, `iscntrl`, `isdigit`, `isgraph`, `islower`, `isprint`, `ispunct`, `isspace`, `isupper`, `isxdigit`, `tolower`, `toupper` |
| `nice.h` | The device routines (see above): `nice_putc`, `nice_getc`, `nice_pollc`, `nice_print`, `nice_cycles`, `nice_instructions`, `nice_micros` (C only, with no assembly routine), `nice_screen_put`, and `nice_screen_clear`. Also `nice_peek` and `nice_poke`, the `nice` imports of WASM.md, and the devices' addresses, for devices that have no routine. |

The device routines, in `src/nice.c`, are the only functions that touch
hardware. They use `nice_peek` and `nice_poke`. `nice_putc` is not among
them: `nice.h` declares it as an import from `env`, as `stdlib.h` declares
`exit`, so it is `_nice_putc` of `lib.nasm` (WASM.md), and every byte of
the library's output goes through `___putc_vector`, at the cost of a call
per byte. `nice_print` writes the
bytes of a C string in linear memory, where `_nice_print` in `lib.nasm`
writes one character per word. `fputc`, `fputs`, and `puts` write with `nice_putc` and
`nice_print`, and `fgetc` reads with `nice_getc` (SYSTEM.md §1).
`getchar` waits until a byte is there. It
returns `EOF` once the line's input has ended, that of the emulator's
stdin or of the debug link's host; a keyboard's bytes may still come
after that (SYSTEM.md §1). The emulator reads the input from stdin, or from the file
that `--input` names. Clang's own `stddef.h`,
`stdint.h`, `stdarg.h`, `stdbool.h`, and `limits.h` complete the headers.

The library is small on purpose:

- The only streams are `stdin`, `stdout`, and `stderr`, all on the
  console. `stdout` and `stderr` are two `FILE` objects that write to the
  same console, and the output functions ignore which stream they get.
  `ungetc` holds one byte per stream. These functions are missing:
  - in `stdio.h`, `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `feof`,
    `ferror`, `perror`, `setvbuf`, `rewind`, and `clearerr`;
  - in `stdlib.h`, `strtoll`, `strtoull`, `strtold`, `atoll`, `qsort`, `bsearch`, `div`, `ldiv`, `getenv`, and `system`;
  - in `string.h`, `strcoll`, `strspn`, `strpbrk`, `strtok`, `strdup`, and
    `strerror`;
  - in `ctype.h`, `isblank`;
  - in `time.h`, `difftime`, `mktime`, and `strftime`;
  - in `math.h`, the hyperbolic functions, `hypot`, `cbrt`, `exp2`,
    `expm1`, `log1p`, `fma`, `remainder`, `lround` and the other
    conversions to integers, `nextafter`, the comparison macros such as
    `isgreater`, and every `long double` function.
- `scanf` and `sscanf` support white space and ordinary characters in the
  format, `*` to read without storing, a width, the length modifiers
  `hh h l ll z t j`, and the conversions `d i u o x X p c s [ n %`, and
  `e E f F g G a A`, which read a float as `strtod` does, into a `float`,
  or into a `double` with `l`. A set in `[` may hold ranges such as
  `a-z`, and `^` first negates it. `scanf` gives back the one byte it read
  too far, for the next `getchar` or `scanf`, with `ungetc`. A float cut
  off, such as `1e+` before a letter, is a matching failure, as C says,
  and stays read.
- `strtod`, `strtof`, `atof`, and the float conversions of `scanf` are
  musl's `floatscan`, in `src/floatscan.c`, in `double` where musl has
  `long double`, under musl's license. They read decimal and hex floats,
  infinities, and NaNs, and round correctly, ties to even, subnormals
  included. In `double`, as musl builds it where `long double` is
  `double`, musl's code has five faults, which the file lists and fixes: three
  roundings of hex floats and of the smallest subnormals, a lost sign, and
  a missing `ERANGE`. `fuzz_strtod.py` (below) checks the result against
  exact arithmetic. The float arithmetic is the float library's, so a
  program that calls `scanf`, even only for integers, is joined with
  `float.nasm`. `sscanf` with `%d` alone was 4166 words; it is now 9082,
  and the float library's 6578 come with it.
- `printf` supports the flags `- + space # 0`, with `+` and space for the
  signed and float conversions, as C defines them, a width and a
  precision (either may be `*`), the length modifiers `hh h l ll z t j`,
  and the conversions `d i u o x X c s p %`, and `e E f F g G a A` for a
  `double`. Any other conversion, such as `%Lf` for a `long double`, is
  printed as it stands. `%p` prints `0x` and the address in hex, `0x0` for
  a null pointer.
- The float conversions of `printf` are musl's `fmt_fp`, taken apart from
  the bits of the `double` and rounded with integers, so that `printf`
  needs no float library. They print the exact decimal value, rounded to
  nearest, ties to even, as glibc does. `%a` prints a 1 before the point,
  also for a subnormal, as musl does, or a 2 when the rounding carries
  into it, such as `0x2p+0` for `%.0a` of 1.5. They cost every program
  that calls `printf` 3085 words: `printf` with `%d` alone was 4124 words
  and is now 7209. `%f` of 1e300 takes about 48000 steps.
- `strtol` and `strtoul` saturate on overflow and set `errno` to `ERANGE`. A base other than 0 and 2 to 36 converts nothing, as no digits, and sets `errno` to `EINVAL`. `strtod` and `strtof`, and so `atof` and `scanf`, set it for a float, as the `errno.h` row above says. No other function sets `errno`: the math functions report no error (Math functions below), `malloc` returns `NULL` with no code, and `scanf` keeps the low bits of a number too large for its type, as C leaves it undefined.
- `exit` is the assembly routine `_exit` of the start-up code: with `start_wasm.nasm`, the `HALT` after `main`, with the status in R1, so the emulator exits with status 0, and under a monitor a return to it (ABI.md). `EXIT_SUCCESS` is 0 and `EXIT_FAILURE` 1. There is no `atexit`. `abort` and a failed `assert` trap (WASM.md), so the emulator exits with status 2.
- `rand` is the linear congruential generator of the C standard's example, `srand(1)` at start.
- `malloc` is first fit, with an 8-byte header on each block, and merges
  neighboring free blocks. `realloc` to a smaller size, 0 included,
  keeps the block. The heap starts at wasm-ld's `__heap_base`
  and grows with `memory.grow`, so only up to nicewasm's
  `--memory-pages`. Code that runs from a ROM, translated with `--ram`,
  may use neither `memory.size` nor `memory.grow`, so it has no `malloc`
  (translator README, Code in a ROM).

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

### Math functions

The functions of `math.h` are musl's, from musl 1.2.5, unchanged, in
`libc/src/math/`. They are under musl's MIT license and the notices in
their files, which `libc/src/math/COPYRIGHT` collects. Three files there
are this library's own: `libm.h` and `features.h` stand in for musl's
internal headers, and `builtin.c` holds the functions that `math.h` maps
to clang's built-ins. Their float arithmetic is wasm float instructions,
which nicewasm turns into calls of the float library above, so a program
that uses them is joined with `float.nasm`, as `nicebuild.py` does when
the program needs it. The float library could not hold them: a library
module may not use float instructions. The library compiles them with
`-Os`, which keeps clang from unrolling the loops of `__rem_pio2_large`,
the reduction of a huge argument of `sin`, `cos`, and `tan`. That saves
2200 words and costs no step on other arguments.

- **Accuracy.** Each result is within 1 ulp of the true value, but that
  of `atan2f`, within 1.5: its error reaches 1.23 ulp, where glibc's
  `atan2f` gives the same result. `sqrt`, `fmod`, `frexp`, `ldexp`,
  `scalbn`, `modf`, `fmin`, `fmax`, the roundings, `fabs`, and `copysign`
  are exact. The float library rounds each operation correctly and has
  no fused multiply-add, so the results are bit for bit those of musl on
  a host with IEEE 754 doubles. `acosf(-1)`, `acosf(0)`, and `atanf` of
  an infinity give the float below π or π/2, 0.63 ulp from the true
  value, as musl does.
- **No error reports.** No function sets `errno`, and NICE has no
  floating-point exceptions, so `math_errhandling` is 0. A domain error
  gives a NaN, a pole or an overflow an infinity, and an underflow 0 or a
  subnormal. C17 7.12 asks for `MATH_ERRNO` or `MATH_ERREXCEPT`, so this
  departs from it. Clang assumes the same for wasm32: unless told
  otherwise, it takes math functions to leave `errno` alone.
- **Round to nearest only.** The float library has no other rounding
  mode, and there is no `fenv.h`, so `nearbyint` is `rint`.
- **Built-ins.** `math.h` defines `sqrt`, `fabs`, `copysign`, `floor`,
  `ceil`, `trunc`, `rint`, `nearbyint`, and their float versions as
  macros for clang's built-ins. Each is one wasm instruction: a call of
  the float library, or a bit operation for `fabs` and `copysign`. The
  functions exist too, for a pointer to one. The classification macros
  test the bits, with no call.
- **No `long double`.** wasm32's `long double` is a binary128, which the
  float library does not support.

A call costs, on the emulator with the math unit, the steps below,
averaged over 32 arguments in the range each function is most used in,
such as −10 to 10 for `sin`. Each also brings the words below into the
program: its own and those of the routines it calls, the float library
not counted. A program that uses all of them gets 23392 words, as
`make words` in `bench/` prints. The reduction of a huge argument, past
2²⁰·π/2, costs `sin` up to 43000 steps and `sinf` up to 26000. `frexp`,
`ldexp`, and `modf` are 199, 82, and 261 words, and their float versions
189, 77, and 187.

| Function | Steps, double | Steps, float | Words, double | Words, float |
|---|---|---|---|---|
| `sin`, `cos` | 6700 | 3900, 3700 | 5630 | 4190 |
| `tan` | 10600 | 6500 | 5670 | 4050 |
| `asin` | 12700 | 5300 | 668 | 264 |
| `acos` | 10200 | 1500 | 799 | 372 |
| `atan` | 8100 | 1600 | 621 | 400 |
| `atan2` | 9700 | 1900 | 893 | 594 |
| `exp` | 4700 | 2900 | 1340 | 475 |
| `log` | 5400 | 3000 | 2011 | 524 |
| `log10` | 10400 | 2800 | 548 | 311 |
| `log2` | 6400 | 3000 | 1506 | 530 |
| `pow` | 15500 | 6500 | 3485 | 1039 |
| `sqrt` | 6200 | 130 | 2 | 2 |
| `fmod` | 320 | 180 | 361 | 196 |
| `round` | 1000 | 540 | 163 | 125 |
| `fmin`, `fmax` | 110 | 80 | 72 | 46 |
| `floor` | 70 | 30 | 2 | 2 |
| `fabs` | 5 | 4 | 2 | 2 |

`libc/test/math.c` checks each function and macro on the cases whose
results C17 Annex F gives, on exact results, and on a few known values,
256 checks in all. `libc/test/fuzz_math.py` (Test, below) checks them on
random arguments.

## Zig and Rust

`nice.zig` and `nice.rs` give Zig and Rust code the device routines that
`nice.h` gives C code, with names and types that suit each language, and
console output through the language's own formatting. They declare the
routines as imports from `env`, which the translator calls at their labels
(WASM.md), so the calls go to the assembly routines in `lib.nasm`.
`nice_print` is left out, since it takes one character per word; `write`
prints a byte slice instead.

| | Zig, `nice.zig` | Rust, `nice.rs` |
|---|---|---|
| The `nice` imports | `peek`, `poke` | `peek`, `poke`, safe wrappers |
| Output | `putc(c)`, `write(bytes)`, `print(fmt, args)` with `std.fmt`, and `writer`, a `std.Io.Writer` | `putc(c)`, `write(bytes)`, `print!` and `println!` with `core::fmt`, and `Console`, a `core::fmt::Write` |
| Input | `getc()`, a `?u8`, `pollc()`, a `Poll`: `.byte`, `.empty`, or `.end`, and `readLine(buf)`, a `?[]u8` | `getc()`, an `Option<u8>`, `pollc()`, a `Poll`: `Byte`, `Empty`, or `End`, and `read_line(buf)`, an `Option<&str>` |
| Counters | `cycles()`, `instructions()` | `cycles()`, `instructions()` |
| Screen | `screenPut(col, row, c)`, `screenClear()`, `screen_cols`, `screen_rows` | `screen_put(col, row, c)`, `screen_clear()`, `SCREEN_COLS`, `SCREEN_ROWS` |
| Heap | `heap`, a `std.mem.Allocator` | `Heap`, a `GlobalAlloc` for the `alloc` crate |
| Math | none needed: `@sqrt`, `@sin`, and `std.math` | `Float`, std's math methods for `f64` and `f32` |

`getc` waits until a byte is there, and returns null or `None` once the
line's input has ended, as `nice_getc` returns −1.

`readLine` and `read_line` read a line into a buffer and return it,
without the `\n`, and without a `\r` just before it. A line longer than
the buffer is cut off: the bytes that fit are returned, and the rest of
the line is read and dropped. A last line with no `\n` before the end of
the input is returned too, and after it null or `None`. In Rust, bytes
that are not UTF-8, such as a character cut in two by the buffer's end,
end the string at the last whole character. There is no `scanf`; a
program parses the line with the language's own functions:

    // Zig
    var it = std.mem.tokenizeAny(u8, line, " ");
    while (it.next()) |w| sum += try std.fmt.parseInt(i32, w, 10);

    // Rust
    let sum: i32 = line.split_whitespace().filter_map(|w| w.parse::<i32>().ok()).sum();

`test/zigline.zig` and `test/rustline.rs` are examples.

**Floats.** Both languages compile `f32` and `f64` arithmetic into wasm
float instructions, which nicewasm turns into calls of the float
library, as for C, so a program that uses floats is joined with
`float.nasm` (Joining a program). Both print floats with their own
formatting code, `std.fmt` and `core::fmt`, which is part of the program,
so `{d}`, `{e}`, `{}`, and `{:e}` work.
The math functions come with the compiler, ported from musl, and are
compiled into the program as well:

- Zig's math builtins, such as `@sqrt`, `@sin`, `@exp`, and `@log`, and
  `std.math`, such as `std.math.pow` and `std.math.atan2`, need nothing
  from `nice.zig`. Zig's compiler_rt, which Zig puts in the module, does
  `f128` too.
- In a `#![no_std]` Rust program, `f64` and `f32` lack std's math
  methods, such as `sqrt`, `sin`, and `ln`. The trait `nice::Float`
  supplies them, with std's names: `abs`, `floor`, `ceil`, `trunc`,
  `round`, `round_ties_even`, `sqrt`, `cbrt`, `sin`, `cos`, `tan`, `asin`,
  `acos`, `atan`, `sinh`, `cosh`, `tanh`, `exp`, `exp2`, `ln`, `log10`,
  `log2`, `atan2`, `powf`, `hypot`, and `copysign`. Each calls the C
  function of compiler_builtins, which rustc links into the module:
  `use nice::Float;` and then `x.sqrt()`. `sqrt`, `abs`, the roundings
  but `round`, and `copysign` are wasm instructions there.

Both compilers' `exp` is the older fdlibm one, whose `exp(1)` is the
double above e, 0.67 ulp off, where the C library's gives the nearest.
`test/zigfloat.zig` and `test/rustfloat.rs` print the results of each
kind of operation.

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

### The heap

Zig code passes `nice.heap` where the standard library asks for an
`Allocator`, as in `list.append(nice.heap, x)`. Rust code names
`nice::Heap` as the allocator, for `Vec`, `String`, `Box`, and the rest
of the `alloc` crate:

    extern crate alloc;

    #[global_allocator]
    static HEAP: nice::Heap = nice::Heap;

Both work as the C library's `malloc`, above: first fit, with an 8-byte
header on each block, and neighboring free blocks merged. A smaller
size, or a larger one that still fits the block, keeps the block, as
Zig's `resize` and Rust's `realloc` ask. Blocks are 8-aligned; a larger
alignment costs that many bytes more. The heap starts at the linker's
`__heap_base`, using the rest of the initial memory first, and grows
with `memory.grow` by the pages a block needs, so a heap larger than the
initial memory needs `--memory-pages` (translator README). When the memory cannot grow, an allocation fails: Zig returns
`error.OutOfMemory`, and Rust's `alloc` crate panics, except in calls
such as `Vec::try_reserve`, which return an error. An interrupt routine
must not use the heap. `test/zigheap.zig` and `test/rustheap.rs` are
examples.

Zig's own `std.heap.wasm_allocator`, which `std.heap.page_allocator` is
on wasm, also works, but costs much more memory. It leaves the free part
of the initial memory unused, and takes a whole page, 16384 words, for
each size class of small blocks. An `ArrayList` of 1000 `u32` needs
`--memory-pages 8` with it, 131072 words. `std.heap.FixedBufferAllocator`
over a static buffer needs no `memory.grow`, but frees only the last
block.

## Test

    make test

This builds the emulator, then joins each `test/X.nasm` with a start-up file,
`lib.nasm`, and `muldiv_mpu.nasm`. It assembles and runs the result and
compares the output and exit status with `test/X.expected`. The tests of
the muldiv routines run a second time with `muldiv_soft.nasm`, and compare
with `test/X_soft.expected`. `test/device.nasm` reads `test/device.input`
as its console input. The tests of the `_mon` start-up files, and
`test/exit_mon.nasm`, are joined after `test/monitor.nasm`, a stand-in for
a monitor at address 0, which calls the program at `0x8000` with a putc
routine of its own, `argc` = 1, and an `argv`, and halts when the program
returns, with the number of bytes its routine wrote in R2. `test/exit.nasm`
and `test/exit_mon.nasm` call `exit` from inside a nested call.
`test/console_mon.nasm` runs after `test/monitor_console.nasm`, the
stand-in with R1 = 0, so its output stays on the console. The expected
values were checked by hand. The comments in each test show how.

With `make test KEEP=DIR`, where DIR is an absolute path, each test also
leaves its program in `DIR/X.bin`, and its console input, if any, in
`DIR/X.input`. The C library's tests leave `DIR/libc_X.bin`. `make
programs` in `hdl/` uses them to run the same programs on the FPGA core.

Then it runs the C library's tests, `libc/test/X.c`, with
`libc/test/X.input` as the console input if there is one. Their `.wasm` files
are checked in, so no C compiler is needed; `make -C libc wasm` rebuilds
them and `libc.a`. Each is translated, joined with `start_wasm.nasm`,
`lib.nasm`, and `muldiv_mpu.nasm`, and `float.nasm` for `math.c`, and run. Its console output, `main`'s result in R1, and the
exit status are compared with `libc/test/X.expected`, which was written
by hand from the source. `exit.c` also runs as `libc/exit_mon`, joined
after `test/monitor.nasm` with `start_wasm_mon.nasm`, and its
`exit_mon.expected` shows R2 too, the bytes that went through the
stand-in's putc routine. The exception is `mchess.expected`, 600 lines of
board output. It was checked against a native build of `mchess.c` on the
same input, and the perft counts 20, 400, and 8902 are the known ones for
the start position. The test runs perft only, so the search of `mchess`,
which needs the 128 KB stack, is not exercised. The core's runs (`make test KEEP=DIR`, for `hdl/`) leave `mchess.core.input` instead of
`mchess.input`: the same without `perft 3`, which takes 11 million steps, and in
GHDL hours.

Then it runs the tests of `nice.zig` and `nice.rs`, `test/nicezig.zig`,
`test/zigpoll.zig`, `test/zigheap.zig`, `test/zigline.zig`,
`test/zigfloat.zig`, `test/nicers.rs`, `test/rustpoll.rs`,
`test/rustheap.rs`, `test/rustline.rs`, and `test/rustfloat.rs`, the same
way, with `test/X.input`, if there is one, as the console input and
`test/X.expected`, written by hand from the source. `zigfloat` and
`rustfloat` are joined with `float.nasm`, and their expected values were
checked with Python's `math` and `fractions` modules. `test/zigheap.zig` and `test/rustheap.rs` are
translated with `--memory-pages 2`, so that their heap can grow by one
page, and no more. Their `.wasm`
files are checked in; `make wasm` rebuilds them, with Zig 0.17 and rustc
with the `wasm32-unknown-unknown` target.

`make -C libc fuzz` needs clang. It runs `libc/test/fuzz_printf.py`,
which writes a C program with 300 random `printf` and `snprintf` calls,
with every flag, width, precision, length modifier, and conversion, of
integers and of doubles, and compares the output with a model of C's
`printf` in Python. `fuzz_printf.py SEED COUNT` runs other seeds and
sizes. Then it runs `libc/test/fuzz_strtod.py`, which calls `strtod` and
`strtof` on 1000 random strings: long decimals, hex floats, exact
halfway cases between two doubles, subnormals, overflows, and the forms
that end a float early, such as `1e+`. It compares the bits, the bytes
taken, and `errno` with the exact value rounded in Python.
`fuzz_strtod.py SEED COUNT` runs other seeds and sizes.
Then it runs `libc/test/fuzz_math.py`, which calls each of the 56
functions of `math.h` on 1000 arguments: special values, random bits,
and random numbers in the function's usual range. It compares the
results with those of the same sources compiled for the host, which
must match bit for bit, and with the true values, which it takes from
Python's `decimal` module or the host's libm. `fuzz_math.py SEED COUNT
[NAME...]` runs other seeds, sizes, and functions, and `--errors` prints
the largest error of each function.
