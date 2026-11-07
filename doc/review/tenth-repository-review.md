# Tenth review of the repository, at commit 351a0cf

Reviewed on 2026-11-07: the eleven commits between `V1.8` and the head of `dev-V1.9`, commit 351a0cf ("nicehdl: WRITE's cause without the ACK"), before the release `V1.9`. They give the math unit the bit counts of A and the square root of C (#129), in the emulator, in `mpu.vhd`, and in the runtime, whose `__clz` searches by halves and whose float library takes its f32 square root and quotient from the runtime; add `math.h` from musl (#130), the float conversions of `printf`, `scanf`, and `strtod` (#68), and floats in Zig and Rust (#142); add a float benchmark; and move WRITE's report of its cause off the paths from `dbus_ack_i` (#141). The ninth review looked at the SD card controller before `V1.5`. This one asks whether the code does what SYSTEM.md §2 and the READMEs say, whether the emulator and the core agree, whether the tests would catch a departure, and whether the documents and the release steps are ready for the tag.

**How it was checked.** I read the whole diff since `V1.8` but for the 75 files of `runtime/libc/src/math/` that are musl's, which I compared byte for byte with the musl 1.2.5 tarball instead: every one of them is identical, and so is `COPYRIGHT`. I checked each new rule of SYSTEM.md §2 against the emulator's `Mpu` and against `mpu.vhd`, and the two against each other, and re-derived by hand every value of `emulator/test/mpubits.expected`, the changed words of `mpu.expected` and `mpu64.expected`, the roots of `runtime/test/isqrt.nasm`, the counts of `clz.nasm` and `bits.nasm`, every line of `runtime/libc/test/floatio.expected`, and the lines of `zigfloat.expected` and `rustfloat.expected` whose values I could compute. I checked the bound that keeps the square root's remainder in 34 bits, the software `_nice_isqrt64` and `__clz` step by step, the f32 square root and quotient of `float.zig` for the widths they assume, `fmt_fp` of `printf.c` line by line against musl's, the five changes of `floatscan.c` against musl 1.2.5's file, and that the pipeline's new derivation of W_RETIRE, W_EMPTY, and W_LATE is the same function of the same signals as WRITE's old one. On the unchanged tree I ran `make test` (1172 lines of `PASS`), `make typecheck`, `make lint`, `make -C doc/intro pdfcheck`, `make -C runtime/libc fuzz` (the printf, strtod, and math fuzzers, all `PASS`), and `make -C bench words`, whose four figures are those the READMEs quote. CI was green for every job on 31c11ac; on 351a0cf the `formal`, `hdl`, and `programs (pipeline)` jobs were still running when this was written, and the rest had passed.

## Summary

**Nothing in the code blocks the tag.** The emulator and `mpu.vhd` implement every rule of SYSTEM.md §2 that I could check, and they agree with each other: the counts for 0, the 33-bit remainder, which words wait and on which unit, and the words that read 0. The probes' expected values are right. The tests are good: `mpubits` runs on both cores, also on a stalling memory; `tb_mpu` checks the new words against a model written another way; the formal job proves the bit counts for every A and the square root for every C, with the shift-and-add lemma proven by hand in hdl/README.md; the runtime tests run on both muldiv files; and the three fuzzers check the C library's floats against exact arithmetic, against the same sources on the host, and against a model of C's `printf`. The timing work of #141 is sound: WRITE still computes W_READ, and the pipeline classifies a cycle as W_RETIRE, W_EMPTY, or W_LATE from registered `done`, `empty`, `flush`, `ack`, and `late`, in the same order of precedence as WRITE did, so every cause is as it was.

**Two release steps are still to do** (§1): the version in `emulator/build.zig.zon`, and the `V1.9` section of RELEASE_NOTES.md, whose upgrade notes have four things to say. **Four statements in the documents are stale or contradict another** (§3): the runtime README still says that only `strtol` and `strtoul` set `errno`; the bench README says `printf` has no `%f` and quotes the float benchmark's cycles on the core from before the changes; and the HDL README's two lists of the probes leave out `mpubits`. Each is a sentence.

## 1. The release

### 1.1 `emulator/build.zig.zon` still says `1.8.0`

RELEASE.md step 2.9 asks for the new tag's version there before `release.py check`, as a change after the stamp makes the stamp stale. **Fix:** `1.9.0`, in a commit before `release.py check`.

**Resolved**: `emulator/build.zig.zon` says `1.9.0`.

### 1.2 The `V1.9` section of RELEASE_NOTES.md

It does not exist yet, as expected before the tag. Besides the five issues, its upgrade notes should say:

- The math unit's words `0xFFFFFF2A`–`0xFFFFFF2C` and `0xFFFFFF3C`–`0xFFFFFF3E`, which read 0, now hold `CLZ`, `CTZ`, `POPCNT`, and the square root of C with its remainder. The ports of both cores, `wb_dmux`, the devices, and the debug link are as in `V1.8`; a system that instantiates `mpu.vhd` gets the words by rebuilding.
- `lib.nasm` now needs `muldiv_mpu.nasm` or `muldiv_soft.nasm` after it: `__clz`, `__ctz`, and `__popcnt` moved there, and `__clz64`, `__ctz64`, and `__popcnt64` call them. A program joined with `lib.nasm` alone no longer assembles. The board side is MJoergen/NiceMonMEGA65#89.
- Every program that calls `printf` grows by 3085 words, and every program that calls `scanf`, even for integers alone, is joined with `float.nasm`, as `nicebuild.py` and the test Makefiles now do.
- In the `timing` flow on the MEGA65, `dbus_ack_i` is back within the budget of 1.5 ns (#141), so the "misses the input budget" of the `V1.8` notes no longer holds.

**Resolved**: RELEASE_NOTES.md has a `V1.9` section, with the four upgrade notes, and a row in the table of board tags, none yet. Its date is set at the tag.

### 1.3 The rest of the checklist

- CI on 351a0cf was not complete when this was written: `formal`, `hdl`, and `programs (pipeline)` were running. Cut no tag before they pass (RELEASE.md §6).
- No row of DEBUG.md §9 is needed: the link does not change.
- No `make -C hdl sweep` is needed: WRITE's interrupt entry, `RTI`, and the request ports are untouched. The `make timing` before and after that CLAUDE.md asks for is in the message of 351a0cf.
- The GitHub API reports milestone `V1.9` with one open item while every issue of it (#68, #129, #130, #141, #142) is closed and no pull request is open. The count is likely stale; look at the milestone page before the tag (RELEASE.md step 1.2).

## 2. What was checked in the code, and found right

These are recorded so that the next review need not repeat them.

### 2.1 The math unit

- **The emulator.** `read(10..12)` are Zig's `@clz`, `@ctz`, and `@popCount`, which give 32, 32, and 0 for 0 as SYSTEM.md §2 says. `read64(6)` packs Q in the low word and the remainder's low word in the high word, and `read64(7)` the remainder's high word and 0, so words 28 to 31 are `ISQRT64_Q`, `ISQRT64_R_LO`, `ISQRT64_R_HI`, and 0. `std.math.sqrt` of a `u64` returns the floor in a `u32`, and the remainder is computed in `u64`, where Q² ≤ C.
- **`mpu.vhd`.** A step forms `rem & bits` in 36 bits and compares it with `4Q + 1`. If `rem` ≤ 2Q, the shifted value is at most 8Q + 3; after a subtraction it is at most 4Q + 2 = 2(2Q + 1), and without one it is below 4Q + 1 ≤ 2(2Q), so the new remainder is at most twice the new root, which has at most 32 bits, and fits the 34 bits kept. The write handler's `sqcount_r <= 0` comes after the step in the process, so a write during a root restarts it through `start64_r`, as the dividers restart. A read of word 28 to 30 waits on `sqrt_busy`, which includes `start64_r`; word 31 never waits and reads 0. A bit count waits on `mul_busy`, and `clz_r` is registered from `a_r`, so it is current once the multiplier's count has run out, which `tb_mpu` checks at 2 cycles. The formal fast list in `formal_mpu.vhd` matches: words 0, 1, 13 to 19, and 31.
- **The probes.** All 32 words of `mpubits.expected`, the 129 and 139 steps of `mpu` and `mpu64`, and the root of 2⁶³ − 1 in `mpu64.expected` (Q = 0xB504F333, R = 0x1_615E23D6) are right.
- **`tb_mpu`.** Its model counts the bits one at a time and finds the root by a search that squares with `numeric_std`, so a shared mistake with `mpu.vhd` is unlikely. The 23 and 20 corner cases that hdl/README.md quotes are those in the file.

### 2.2 The runtime

- `__clz` in `muldiv_soft.nasm` starts the count at 1, adds 16, 8, 4, and 2 for each half it shifts past, and subtracts bit 31 at the end: 31 for 1 and 0 for 2³¹, in 19 steps as the comment counts them, with 3 for 0. `clz.nasm` reaches every count down both paths.
- `_nice_isqrt64` in `muldiv_soft.nasm` is `mpu.vhd`'s loop in registers: two shifts of the radicand into the remainder, 2Q by `DBL`, 4Q + 1 by `0<1` and `SHR`, the trial subtraction into R6 and the stack word, and the conditional take. 18 steps a pass, 584 in all, and the stack is left as found. `isqrt.nasm` tests the roots on both sides of each step it exercises, and `isqrt.expected` and `isqrt_soft.expected` agree on every root.
- `bits.nasm`'s recount, 1684 steps in software and 479 with the math unit, follows from the new costs.

### 2.3 The float library

- `sqrt(f32)`: m has at most 25 bits after the odd-exponent doubling, so `m << 38` is below 2⁶³ and fits the `u64` that `nice_isqrt64` takes; its root is below 2³², so the rounding that follows sees 31 or 32 bits, as before.
- `div(f32)`: `ma << 25` is below 2⁵⁰, and the quotient below 2²⁷, so both fit; the remainder is nonzero exactly when the old loop's was. The `float32div` case of `translator/test/run.py` fails if the remainder is dropped.
- The library is translated with `--no-mpu`, so its one `u64` divide calls `__udiv64` and it joins with either muldiv file. The Makefiles and `nicebuild.py` join `float.nasm` when a program uses one of its labels.

### 2.4 WRITE's cause without the ACK

The old WRITE said W_LATE in its read-wait branch when `rq_cnt_i + ack >= nr`, else W_READ, and then overrode that with W_RETIRE when it retired, or W_EMPTY when it ran with no micro-operation and no flush. In that branch `bavail_v < nr`, where `bavail_v` is `rq_cnt_i + ack` when the micro-operation may take its data from the bus and `rq_cnt_i` otherwise, so W_LATE needed `byp_v` false, `ack` 1, and `rq_cnt_i + 1 >= nr`. That is exactly `late_o` and the ACK, and the pipeline applies the same precedence a cycle later from `done`, `empty`, and `flush` registered in the same cycle. The formal wrapper of WRITE leaves `late_o` open, as it did `why_o` and `fwhy_o`. The commit's retire logs, identical cycle for cycle on `bench.bin` and `hand.bin`, agree.

### 2.5 The C library

- **`fmt_fp`** follows musl's: the same big array of base 10⁹ words, the same rounding position, carry, `%g` trimming, and padding. `-` clears `0` before `fmt_fp` is called, so the three `fill` calls pad as C says. `BIG` is 124 words: the fraction grows one word per shift of 9 bits from 2⁻¹⁰⁷⁴, 120 shifts, and the integer part of a double is at most 35 words. Every line of `floatio.expected` is what glibc prints, including `0x2p+0` for `%.0a` of 1.5, `1.00e+03` for `%#.3g` of 999.5, and the matching failure of `%lf` on `1e+z`, which leaves `z` in the input.
- **`floatscan.c`** is musl 1.2.5's in `double`, with the five changes its header lists. The first, 15 hex digits rather than `LDBL_MANT_DIG/4+1` = 14, is the change musl itself made later: the copy in Zig 0.17's tree has `(LDBL_MANT_DIG+3)/4+1`. The second makes a sticky bit at the half position round an odd x up rather than make a tie. The others keep the sign of a zero, set `ERANGE` after `scalbn`, and give the decimal sticky bit the float's sign. `scanf` calls it after its own white space skip and EOF check, within the width, and gives back at most one byte to a stream.
- **`math.h`** declares the 56 functions and defines the 16 built-in ones as function-like macros, which C allows; `builtin.c` has the functions for a pointer or `(sqrt)(x)`, and `math.c` calls them through pointers. `libm.h` keeps `WANT_ROUNDING` as musl has it and makes `FORCE_EVAL` a no-op, which is right where no exception can be raised. `fuzz_math.py` requires the bits of the host build of the same sources, so a translation fault cannot hide behind the 1 ulp bound.

### 2.6 The benchmark and the language tests

`floatexpected.py` rounds after every f32 operation, in the order the C evaluates them, and wasm has no fused multiply-add, so the two agree by construction; `make test` runs both. The expected lines of `zigfloat` and `rustfloat` that I recomputed are right: 0.1f · 3 is the float nearest 0.3, `exp(1)` of fdlibm is the double above e, and 2 · 10¹⁰ saturates to 2147483647 in Rust.

## 3. The documents

### 3.1 runtime/README.md says no other function than `strtol` and `strtoul` sets `errno`

Line 345: "No other function sets `errno`: `malloc` returns `NULL` with no code, and `scanf` keeps the low bits of a number too large for its type". Line 272, the `errno.h` row, now says that `strtod`, `strtof`, `atof`, and `scanf` set it too. **Fix:** "No other function sets `errno`: the math functions report no error (Math functions below), `malloc` returns `NULL` with no code, and `scanf` keeps the low bits ...", with the float conversions named before it, as the row does.

**Resolved**: The sentence names the float conversions first, as the `errno.h` row does, and the math functions among those that set no `errno`.

### 3.2 bench/README.md says `printf` has no `%f`

Line 511: "printf has no `%f` (issue #68), so a result is the bits of a float, or an FNV-1a hash of them". #68 is closed by 31c11ac, and `printf` has it. The reason to print bits stands. **Fix:** "A result is the bits of a float, or an FNV-1a hash of them, or of the iteration counts in `mandel`, so that the check is exact and the program needs no float conversions."

**Resolved**: The paragraph gives the reason that stands, and no longer names #68.

### 3.3 bench/README.md quotes the float benchmark's cycles on the core from `V1.8`

Line 533: "`make core CORE_PROGRAMS=float` measures 2301987 there, 1.84 per instruction". That is the figure before the changes of #129; the message of 8dd4513 measured 1917617 cycles for 1058329 instructions on the pipelined core after them. RELEASE.md step 2.4 asks for the figures of the release. **Fix:** add the measured figure to the last row of the table of changes, or a sentence after it: "On the pipelined core the program then takes 1917617 cycles, 1.81 per instruction." The run table above it is labeled as `V1.8`'s, which is clear enough.

### 3.4 hdl/README.md's lists of the probes leave out `mpubits`

Line 912: "`mpu` and `mpu64` read every word of the math unit." Line 1002: "`cputest`, `reads`, `mpu`, `mpu64`, `perf`, `events`, `timer`, and `sd` again, on a memory that stalls in 30% of the cycles". `hdl/Makefile` runs `mpubits` in both lists, and its own comment says so. **Fix:** add `mpubits` to both.

### 3.5 A sentence for WASM.md, optional

The float library is the first library module with an import, `nice_isqrt64` from `env`. WASM.md's list of how a library module differs from a program's module does not mention imports, so by its wording they are the same, and the translator's README says imports from `env` are supported. The runtime README and ABI.md say what the import is. A clause in WASM.md's list, "it may import from `env` as a program's module does", would make it explicit. Not needed for the tag.
