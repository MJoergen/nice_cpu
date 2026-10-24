# A C compiler for NICE: expectations and decisions

C reaches NICE today through wasm: clang compiles it to wasm32, and
nicewasm translates that ([translator/README.md](../../translator/README.md)).
TODO.md lists a C compiler that targets NICE directly. This file records
what such a compiler can be expected to gain, measured on commit 22eacce,
and the decisions taken before any code is written. The open items are in
TODO.md, under Toolchain.

## Where the translated code loses

[bench/README.md](../../bench/README.md) compares `bench.c` through nicewasm
with `hand.nasm`, the same benchmark written by hand. On the pipelined
core:

| Program | Instructions | Cycles | Cycles per instruction |
|---|---|---|---|
| `bench.c` through nicewasm | 1681080 | 2384635 | 1.42 |
| `hand.nasm` | 491617 | 1384879 | 2.82 |

The hand-written program has 3.4 times fewer instructions but takes only
1.72 times fewer cycles. Its dense instructions, with operands in memory,
side effects, and table jumps, meet more of the pipeline's hazards
([MICROARCH.md §5](../MICROARCH.md)). So 1.72 is the ceiling for any
compiler on this core. More needs changes to the core as well.

The bounds checks are not where the time goes. With
`nicewasm --no-bounds-checks`, the phases take 1641660 instructions, 2%
fewer, and about 2412000 cycles by `pipecycles.py`, slightly more. One
compare checks both the bounds and the alignment, so without it the
accesses take the general path more often.

The time goes into the memory model of wasm. Linear memory is
byte-addressed and packed four bytes to a word
([WASM.md](../../translator/WASM.md)). So a byte load takes seven
instructions, and every access adds `MEMBASE` to a byte address divided by 4.
ABI.md has `CHAR_BIT` = 32 and word addresses as pointers. A compiler that
follows it pays none of this, even a simple one.

## The calibration spike

To check this, the `vm` and `strings` phases were written by hand the way
a simple compiler would emit them from `bench.c` with `CHAR_BIT` = 32,
in place of those of `hand.nasm`. The program is `bench/simple.nasm`, and
`make cycles` in `bench/` gives its cycles. The rules:

- Locals in registers. Local arrays in the frame.
- A load is folded into the one instruction that uses it, and a store is a
  memory destination.
- The math unit is used inline.
- The C library routines are separate functions, called by the ABI. They
  are written from `runtime/libc/src/string.c` with the same rules.
- No `@R++` or `--R`, no conditional instruction except a jump, and no
  flags reused from an earlier operation.
- Signed compares of `int` take the V trick of ISA.md §9.2.
- Loops are tested at the top. The `switch` checks its range and jumps
  through a table, and each case jumps back to the top of the loop.

The byte buffer is unpacked to one byte per word before the strings phase,
outside its timing, as `unsigned char buf[]` is with `CHAR_BIT` = 32. Both
results are correct. Instructions on the emulator, and cycles by
`pipecycles.py`:

| Phase | nicewasm | Simple | Hand | nicewasm / simple, cycles | Share of the gap closed |
|---|---|---|---|---|---|
| `vm`, instructions | 840049 | 314016 | 112013 | | |
| `vm`, cycles | 1248112 | 768069 | 602050 | 1.62 | 74% |
| `strings`, instructions | 104562 | 47293 | 21140 | | |
| `strings`, cycles | 166871 | 112468 | 66032 | 1.48 | 54% |

The share of the gap closed is the cycles saved against nicewasm, as a
share of what `hand.nasm` saves. The spike is hand-written, so a real
simple compiler may do worse, through spills and poorer instruction
selection.

## What to expect

For the whole benchmark, these are estimates. Only `vm` and `strings`
were measured.

- **A simple compiler**, as in the spike, closes about half of the gap in
  cycles: about 1.75 to 1.9 million cycles, against 2.38 million. That is
  1.25 to 1.35 times faster, and about two times fewer instructions. The
  gain is largest in byte and string code. `rng64` and `heapsort` gain 25%
  at most, since `hand.nasm` itself is only that much faster there.
- **A good compiler** adds `@R++` pointer walks, conditional instructions
  in place of short jumps, flags from the operation, tail calls, the
  `switch` dispatch copied into each case, and math unit scheduling. It
  comes within 10 to 20% of `hand.nasm`: 1.4 to 1.6 times faster than
  nicewasm.
- **Dhrystone**, at 2348 cycles per run on the pipelined core and 0.242
  DMIPS/MHz, would move to about 1500 to 1800 cycles and 0.32 to 0.38
  DMIPS/MHz. The Cortex-M0 has 0.87. Most of the remaining gap is the
  core's cycles per instruction, not the compiler.
- `char` data takes four times the memory. Code gets smaller.

## Decisions

Taken on 2026-10-24:

1. **The goal is cycles on the pipelined core**, measured by `bench/` and
   Dhrystone. The C the compiler accepts grows as far as those need first.
2. **`CHAR_BIT` is 32**, as ABI.md defines it. A `char` is a word, and a
   pointer is a word address. There is no `uint8_t`, and code that
   assumes 8-bit bytes must change. This is where most of the gain is.
3. **The front end is our own**, in Python with the standard library only
   and `mypy --strict` clean, as niceasm and nicewasm are. Clang and LLVM
   need 8-bit bytes. GCC's word-addressed ports are mostly abandoned. Our
   own front end gives full control over `CHAR_BIT` = 32.
4. **The intermediate form is SSA from the start.** A direct code
   generator would reach the level of `simple.nasm` sooner, but most of
   what is left after that needs SSA: `@R++` pointer walks need loop
   analysis, conditional instructions in place of short jumps need the
   merges that φ functions describe, and flags from the operation need to
   know where a compared value comes from.
5. **The C accepted at first is C89**, with K&R definitions and
   structure assignment, which Dhrystone needs, and `long long`, which
   `rng64` in `bench.c` needs. Variadic functions are in, both calls and
   definitions (see 6). Floating-point arithmetic and bit-fields come
   later. Dhrystone declares two
   `float` variables but uses them only outside the `NICE` port, so the
   first version must accept `float` declarations. The front end includes
   its own preprocessor, for `#include`, `#define`, and `#ifdef`.
6. **The C library is compiled natively**, from the sources in
   `runtime/libc/src` that the wasm build uses. Calling the wasm library
   instead would copy every string into linear memory, packed four bytes
   to a word, and lose the gain of `CHAR_BIT` = 32 in string code. The
   few places tied to wasm go under `#ifdef`: the heap of `malloc.c`,
   which uses the wasm memory builtins, the builtins behind `memcpy`,
   `memmove`, and `memset`, and the device routines of `nice.c`, which
   `runtime/lib.nasm` already has. New headers give `limits.h`,
   `stdint.h`, `stddef.h`, and `stdarg.h` for `CHAR_BIT` = 32. Variadic
   definitions come with the first version, because the ABI puts every
   argument of a variadic call on the stack: `stdarg.h` is macros, with
   `va_start(ap, last)` as `&last + 1`, as long as the compiler leaves a
   stack parameter whose address is taken in the slot it arrived in. The
   wasm build stays for the wasm path. The float library stays wasm until
   the compiler has floating-point arithmetic.

## Still open

These are in TODO.md:

- The float library, once the compiler has floating-point arithmetic:
  called in wasm across the pointer boundary of WASM.md, or compiled
  natively.
- Safety: wasm traps on an access out of bounds, and C does not. Is an
  optional check mode wanted?
- The linker: keep joining files, as ABI.md does now, or write one.
- Tests: compare with the same C run on the host, as `make native` does,
  plus the benchmark and Dhrystone checks, and a fuzzer like
  `translator/test/fuzz.py`.
