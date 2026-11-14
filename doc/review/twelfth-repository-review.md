# Twelfth review of the repository, at commit 7593bbc

Reviewed on 2026-11-14: the 41 commits between `V2.1` and the head of `dev-V2.2`, commit 7593bbc ("doc: the rules only in CONTRIBUTING.md"), before the release `V2.2`. They add the floating-point unit, the FPU (#161): DEVICES.md §11, a reference model in exact arithmetic with its vectors, the unit in the emulator, the float library on it, `runtime/float_fpu.nasm`, nicewasm's `--inline-fpu`, and `hdl/src/fpu.vhd` on its arithmetic unit, with proofs of its bus and its stack, and with both cores run against the emulator. They also let a program reserve only the start of its memory, with `--memory-bytes` (#165), rename `doc/SYSTEM.md` to `doc/DEVICES.md` (#166), shorten `make programs` (#169), and give the emulator `TIME_SKIP` (#170). This review looks at two things: what the documents say, and what the tests cover.

**How it was checked.** I read the diff of every document since `V2.1`, and DEVICES.md §11 and §3 whole. For each change I looked for the other places that state the same fact: the READMEs, the documents of `doc/`, the usage texts, the headers of the VHDL units, CLAUDE.md, and CONTRIBUTING.md. One script compared the files that the release adds with the README beside each. I checked the statements about NiceMonMEGA65 against its checkout, 13 commits after its `V2.0.1`, and against its issues. On the unchanged tree I ran `make all`, which passes: 1603 lines of `PASS` in 526 seconds. I ran what no gate runs: `float.c` and its inline build on both cores, the same program with the float library in software on the pipelined core, the program built for the FPU on an emulator without one, and Vivado on the FPU alone, out of context, three times. I worked out the examples of DEVICES.md §11.3 by hand, and counted the words that the documents quote. CI passed every job on 073e57c, six commits before the head, which change the emulator, the runtime's float library, and documents. It passed every job on 7593bbc too, while this was being written.

Three agents, each in a copy of the repository, looked at what the tests cover: the emulator, `hdl/`, and the runtime with the translator and the benchmarks. Each mapped the rules of DEVICES.md §11 and §3 to the tests that check them, and then broke the code on purpose, one rule at a time, to see which test fails: 38 changes in the emulator, 33 in the runtime, the translator, and the benchmarks, and 33 in `hdl/`. I ran again by hand what this review states as a bug or shows with its output: the two bugs of §2, on an emulator that I built as `make dist` does, the root cause in Zig, the vectors on the baseline CPU, and the model against Python; three of the changes that every test passes (§3.5, §3.10, and §3.11); the cycles of the commands (§3.12); and the checks that the code is right where no test looks (§3.5, §3.8, and §3.9). The other changes that pass are the agents' runs, which I read against the tests they name.

## Summary

**Two bugs pass every test** (§2), and both are best fixed before the tag.

- The emulators that `make dist` builds for a release give `ISQRT` of an exact square m², with m of 2^26 or more, as m − 1 (§2.1). They are built for a CPU without the FMA instruction, where the `fma` of Zig 0.17.0 is wrong, and `make test` and CI replay the FPU's vectors on the host's CPU only. On the baseline CPU 24 of the 48068 lines fail. The release would ship it in both of its emulators.
- The rule of `DIGITS` in DEVICES.md §11.3 takes an exponent that is one too large wherever the digits round up to a power of ten at it (§2.2): `DIGITS 1` of 8 gives 1 · 10^1, `DIGITS 2` of 9.6 gives 1.0 · 10^1, and the 15 digits 999999999999995 and above do not come back. The model, the emulator, and `fpu.vhd` all follow the rule, and the vectors expect it. It is a rule of the specification, so it costs least to change before a release has it.

**The release steps are open, and one thing beside them needs care** (§1). RELEASE_NOTES.md has no section for `V2.2` (§1.1), and `emulator/build.zig.zon` says `2.1.0` (§1.3). `nicebuild.py` now builds a program with floats for the FPU, and on a system without one, as NiceMonMEGA65 is, that program computes wrong results and reports nothing (§1.2). DEVICES.md §8 has no bullet for it, the board has no issue for it, and the notes must say it.

**The FPU misses 100 MHz, and nothing measures it** (§3.1). `make timing` synthesizes the core alone. Out of context, in three runs of Vivado, `fpu.vhd` with its arithmetic unit misses 10 ns by 1.1 ns to 4.4 ns, and takes 8244 LUTs, more than the pipelined core. No rule is broken, since the FPU is off the core's paths, but DEVICES.md gives its times "at 100 MHz", and a board that takes it as it is fails its timing.

**The tests of the new code are strong where the vectors reach, and thin beside them** (§3). Of 104 changes made to the code on purpose, 63 fail a test. Those that pass show what no test looks at:

- the figures of `float.c` on the cores, and the cycle model's FPU (§3.2 and §3.4), and `NO_FPU=1` in `bench/`, which runs the other build's programs (§3.3);
- the float library's rule for the FPU's stack, when the caller keeps values there (§3.5);
- whether nicebuild's new options do anything, and a program built with `--no-fpu` on a system without the FPU (§3.6);
- the edges of `--memory-bytes` (§3.7), of `FPU_X_W` at 2^31, and of a skip that an NMI or the console ends (§3.8);
- a core that waits for the FPU when an interrupt, a pause, or a single step comes (§3.9);
- a request that waits for a command, on any register but `FPU_STATUS` (§3.10), and a reset during a command (§3.11);
- the cycles of the commands (§3.12).

Where this review ran the case that is missing, the code is right: the figures of §3.2, the stack with values kept (§3.5), the NMI and the console (§3.8), and the interrupts, pauses, and steps of §3.9. It did not run a reset during a command (§3.11), nor the edges of §3.7. `make -C emulator fpu-long` and the fuzz of the C library are in no gate (§3.13), and a program that runs away hangs the translator's tests (§3.14).

**The documents of the FPU agree with each other and with the code** (§6): DEVICES.md §11, the READMEs, ABI.md, WASM.md, TOOLCHAIN.md, the usage texts, and every figure that they quote but three. What is stale is small (§4): the board's clock, which it sets from its real-time clock since its `V2.0.1`, the times and the counts of `make formal` and `make programs`, the math unit as the slave that waits longest, the size of `float.nasm`, one cycle count, and the time of `ISQRT`, which is some 90 cycles and not 70. What is missing is in `hdl/` (§5): its README has no section for the FPU, as it has for every other device, and MICROARCH.md §8 names neither the FPU nor the clock.

**Nothing is fixed, and no issue is filed.** `make all` passes on the unchanged tree, and CI passed every job on 7593bbc. Before the tag: §2.1, §2.2, and §1.1 to §1.3. The findings of §3 are tests to add, and those of §3.1, §3.9, and §3.13 may be issues for `V2.3` beside #164.

## 1. The release

### 1.1 RELEASE_NOTES.md has no section for `V2.2`

The newest section is `V2.1`. The 92 lines that the file changed since then are the rename of SYSTEM.md. RELEASE.md step 2.8 asks for the section, and for a row `V2.2`, "none yet", in the table of board tags. `release.py notes` drafts it. This release changes more for a user than any since `V2.0`, so the upgrade notes matter. They must say at least:

- **`nicebuild.py` joins `runtime/float_fpu.nasm`**, where it joined `float.nasm`. A program that uses floats now needs the FPU, and on a system without one it computes wrong results and reports nothing (§1.2). `--no-fpu` joins the float library in software, as before. The tests of the runtime and the benchmarks take `NO_FPU=1` for the same.
- **`0xFFFFFF88`–`0xFFFFFF8F` are the FPU**, where they were words reserved for I/O that the emulator kept as memory. `niceemu --no-fpu` makes them memory again. With `--step-time`, a write to `0xFFFFFF5F`, `TIME_SKIP`, skips time, where it was ignored.
- **nicewasm's `--library-memory` and `--ram-bytes` are gone**, and so is nicebuild's `--ram-bytes`: `--memory-bytes` replaces all three (b2c25fb). `nicebuild.py --ram` now takes a program that uses floats, unless with `--no-fpu`.
- **`doc/SYSTEM.md` is `doc/DEVICES.md`** (#166). A link to the old name on `main` breaks at the release. NiceMonMEGA65 has 51 such links, and follows in MJoergen/NiceMonMEGA65#130.
- A start over the debug link resets the FPU. The link stays version 8.
- `hdl/src` has three new files, `fpu.vhd`, `fpu_unit.vhd`, and `fpu_pkg.vhd`, a device beside the cores, which do not change. `tb_core` has the generic `G_FPU`, and its watchdog waits 10000 cycles for a step.
- TODO.md is gone, and the rules for a change are in CONTRIBUTING.md only.
- Zig 0.17.0, as in `V2.1`.

**Fix:** write the section, with the line "The version is 2.2.0." under the emulator's heading, and the row of the table.

### 1.2 A program built for the FPU runs without it, and is wrong

`bench/build/float.bin`, as `nicebuild.py` and the Makefiles now build a program with floats, on an emulator without the FPU:

    $ niceemu --step-time --no-fpu bench/build/float.bin
    phase      instructions       cycles  result
    convert          38441        38469  b45705c5  FAIL
    dot32             4946         4974  00000000  FAIL
    dot64             6569         6597  00000000  FAIL
    mandel          214346       214374  0f875145  FAIL
    norm             11679        11707  39ab7825  FAIL

It halts with `HALT` and exit status 0. This program checks itself; another prints wrong numbers. Nothing in the start-up code or in `float_fpu.nasm` looks for the unit. A program translated with `--byte-windows` has the same need of its system, and there `___wasm_start` traps with code 8 when the windows cannot reach its memory (WASM.md).

NiceMonMEGA65 is such a system today. Its words `0xFFFFFF87`–`0xFFFFFF8F` read 0 and take no write (its `doc/SYSTEM.md`, The screen), and its `doc/PROGRAMMING.md` builds a program with `nicebuild.py -o prog.bin prog.c`, or with `--monitor`. When it moves its submodule to `V2.2`, a program with floats built that way reads zeros from the FPU.

Three things are missing:

- DEVICES.md §8 has no bullet for the FPU. It has one for each other device that a system may leave out: the receive interrupt, the SD card, the station, the frames, the clock, and the byte windows. Its **Reserved words** bullet says only that NiceMonMEGA65 "is to give up `0xFFFFFF88`–`0xFFFFFF8F` to the FPU", with no issue.
- NiceMonMEGA65 has no issue for the FPU. Its open issues that follow this release are #130, the rename, and #133, `TIME_SKIP`. The last comment of #161 says that the board's side "belongs to NiceMonMEGA65".
- The notes (§1.1).

**Fix:** a bullet **FPU** in DEVICES.md §8: a system may leave out the FPU, then has nothing at `0xFFFFFF88`–`0xFFFFFF8F`, and a program for it is built with `--no-fpu`; NiceMonMEGA65 does not have it yet, with the number of a new issue there, which also names `--no-fpu` for its users until then. A check at the start, as for the byte windows, is a question for an issue here: a push and a read of the depth in `FPU_STATUS` take a few words.

### 1.3 `emulator/build.zig.zon` still says `2.1.0`

RELEASE.md step 2.9 asks for the new tag's version there before `release.py check`. **Fix:** `2.2.0`.

### 1.4 The rest of the checklist

- The milestone `V2.2` has 5 closed issues and none open: #161, #165, #166, #169, and #170.
- The debug link stays version 8, and DEBUG.md §9 needs no row. The start that resets the FPU is the rule of §6 for a device, and the pause and the step of a skip are the emulator's.
- No `make -C hdl sweep` and no `make -C hdl timing` before and after is owed. The diff of `hdl/src/pipe_write.vhd`, `pipeline.vhd`, `multicycle.vhd`, and `nice_pkg.vhd` is the name of DEVICES.md in comments.
- `make all` passes here, and `make -C doc test` and `pdfcheck` with it.
- CI passed every job on 7593bbc.

## 2. Two bugs that every test passes

### 2.1 `ISQRT` is wrong in the emulators of a release

`make -C emulator dist` builds the emulators of a release for the baseline x86_64 CPU: `-Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl`, and `x86_64-linux-gnu.2.31` with the window. Such a build gives `ISQRT` of 78480680² as 78480679:

    $ niceemu -d 0x200:2 isqrt.bin              # the build of make test
    00000200: 04ad8528 00000004
    $ dist/bin/niceemu -d 0x200:2 isqrt.bin     # ReleaseSafe, x86_64-linux-musl
    00000200: 04ad8527 00000004

- **The cause.** `isqrt` in `emulator/src/fpu.zig:193` asks whether the root, rounded to nearest, is one too high with `@mulAdd(f64, s, s, -f(a)) > 0`. On a CPU with the FMA instruction, as this machine has, that is one instruction, and exact. The baseline CPU has none, so Zig calls its own `fma`, and that of Zig 0.17.0 returns 2^−1022 where the result is exactly 0 and the product is 2^52 or more: its `std.math.ldexp(0.0, n)` is 2^(n − 1076) for n of 54 or more, and not 0. So `ISQRT` of an exact square m², with m of 2^26 or more, gives m − 1: all 200000 of them from 2^26 up, and none of the 200000 below it.
- **How far it goes.** `zig build test -Dcpu=baseline` with the vectors of `make test` fails 24 of 48068 lines, all of them `ISQRT`. `mulPair`, for `SCALE10` and `DIGITS`, uses the same `@mulAdd` (line 438), and its pair gets a low part of 2^−1022 where it is to be 0. No vector differs there, and I found no value for which it shows, but did not prove that there is none. The cores are right, and so is every build for a CPU with FMA.
- **Why no test sees it.** `make test` replays the vectors in a Debug build for the host's CPU (`emulator/Makefile:117`), and CI's runners pass it. `make dist` runs the probe programs on its two builds, with `errors.py` on the one and `window.py` on the other, and not the unit tests, so not the vectors: its 73 programs pass on the wrong build. `release.py check` does not build `dist`. The release workflow does, after the tag.

**Fix:** compare s · s with X without `fma`, in integers or in `f128`, and do the same for the error of `mulPair`'s product, so that no result depends on which `fma` the build has. Replay the vectors on the baseline CPU too, in `make test` and in `make dist`. Tell Zig of `ldexp`.

### 2.2 `DIGITS` gives the next power of ten for a value just below it

DEVICES.md §11.3, line 822: "D, the digits as a whole number, is `NEAREST` of `SCALE10` of |X| by n − 1 − e, and e is the largest whole number for which D ≥ 10^(n−1)." With an e that is one too large, the scaled |X| lies just below 10^(n−1), `NEAREST` rounds it up to 10^(n−1), and the test passes. So the rule takes that e whenever the first n digits of |X| round up to 10^(n−1) one place higher:

| Command | Gives | The n digits of X |
|---|---|---|
| `DIGITS 1` of 8 | 1 · 10^1 | 8 · 10^0 |
| `DIGITS 2` of 95.1 | 1.0 · 10^2 | 9.5 · 10^1 |
| `DIGITS 15` of 99.9999999999999 | 1.00000000000000 · 10^2 | 9.99999999999999 · 10^1 |

- For n = 1 that is every value above 5 · 10^k and below 10^(k+1), so 6, 7, 8, and 9 all give 1 · 10^1: of 4000 random values, 1947 differ from Python's `'%.0e'`. For n = 2 it is 195 of 4000, for n = 3 it is 28, and for n = 15 only the values whose 15 digits are 999999999999995 or more.
- So line 825, "15 digits come back", does not hold for those: the constant 99.9999999999999, read through `FROMBCD` and `SCALE10` and printed through `DIGITS 15`, comes back as 100.000000000000.
- The model (`fpu_model.py:428`), the emulator, and `fpu.vhd` all follow the rule. Of the 310 vectors of `DIGITS` on a finite value, 6 are such a case, `DIGITS 2` of 9.6 among them, which gives 1.0 · 10^1, and they pass on all three. I ran the three lines of the table on niceemu and on the model.
- No test compares `DIGITS` with digits found another way. The model's `fifteen_digits()` draws 1500 random constants of 15 digits, of which some 5 in 9 · 10^14 are such a case, and the hand cases have none. One of the six values that the directed vectors name is 9.6 (`fpu_vectors.py:656`), so the wrong digits of `DIGITS 1` and `DIGITS 2` of it are in the vectors as the results to expect.

**Fix:** DEVICES.md first: e is the smallest whole number for which D < 10^n. D then has n digits always. On the model that rule agrees with Python's `'%.*e'` on 4000 random values for each of n = 1, 2, 3, and 6, and for n = 15 it differs only by one in the last digit, 163 times, as the old rule does, which is `SCALE10`'s rounding before `NEAREST`. Then the model, with a test against `'%.*e'` and the cases of the table among the directed vectors, the emulator, and `fpu.vhd`: its loop may stop where it does now, and try the e below only when D is exactly 10^(n−1). Nothing prints through `DIGITS` yet but `fpudec.nasm`, and BASIC on the board is to, so the change costs least before `V2.2`.

## 3. Test coverage

### 3.1 Nothing measures the FPU's timing, and it misses 100 MHz

`make timing` synthesizes the pipelined core alone. The FPU is checked by `ghdl --synth`, which says that it can be synthesized, and by nothing that places it. #164 says so: "`make timing` does not cover it yet". So I ran Vivado 2025.1 on `fpu.vhd` with `fpu_unit.vhd`, out of context, as `hdl/timing.tcl` runs the core: a 10 ns clock, input and output delays of 0, one run of each.

| Part | Flow | Worst slack | Failing endpoints | LUTs | Registers | DSPs |
|---|---|---|---|---|---|---|
| MEGA65, `xc7a200tfbg484-2` | default | −2.424 ns | 503 | 8244 | 2383 | 6 |
| MEGA65 | timing, the directives NiceMonMEGA65 builds with | −1.070 ns | 548 | 8340 | 2402 | 6 |
| Nexys4DDR, `xc7a100tcsg324-1` | default | −4.367 ns | 1388 | 8334 | 2383 | 6 |

- The worst path of the default flow takes 12.2 ns through 23 levels of logic, 11 of them carry chains, from `n_r`, the operand n of the command, to the clock enables of `u_a` and `u_b`, the operands that `fpu.vhd` gives its unit.
- With the timing flow the paths that fail are in 21 groups, in both files. In `fpu.vhd`: from `n_r` to `u_a`, `u_b`, `dexp_r`, `state_r`, and `ret_r`, and from `x_r` to `res_r`. In `fpu_unit.vhd`: from the multiplier's count to its product `pp_r`, and from the accumulator `acc_r` to itself, to `res_r`, and to `e_r`, which is the normalization and the rounding.
- The placement moves a slack of the core by up to 1.4 ns from run to run (`timing_budget.py`, `SPREAD`). So the timing flow's miss might close in another run, and the other two will not. In a system the paths get longer, not shorter.
- The FPU is larger than the pipelined core, which takes 7642 LUTs and 3292 registers with 4 breakpoints and 4 watchpoints. Its arithmetic unit is 7297 of the 8244 LUTs. No document gives its size, and #164 calls it small.
- The runs report hold violations too, of 0.4 ns from the data inputs, which the input delay of 0 makes out of context. I did not look further into hold.

No rule is broken: CONTRIBUTING.md keeps 100 MHz for the pipelined core, the FPU is off its paths, and no release waits for the board. But the documents read as if the FPU ran at the board's clock. DEVICES.md §11.5 gives its times "at 100 MHz", and §8 says that NiceMonMEGA65 "is to give up" the FPU's words to it. A board that takes `fpu.vhd` as it is fails its timing.

**Fix:** an issue, with #164 or beside it, for the paths and for a target that measures the FPU: the two scripts of this review are `fpu_timing.tcl` and `fpu_timing2.tcl`, to become `make timing UNIT=fpu` or a file beside `timing.tcl`. Until the paths are fixed, a sentence in the `V2.2` notes, in hdl/README.md (§5.1), and in the board's issue (§1.2) that says the FPU does not meet 10 ns yet, with the figures above.

### 3.2 `float.c` on the cores is in no gate

`make slow` runs `bench`, `hand`, Dhrystone, CoreMark, and the strides on each core (`Makefile:74`). `make -C bench core CORE_PROGRAMS=float`, and `float_inline`, are run by hand, as CoreMark was before #160. Four documents quote their cycles on the pipelined core, 581542 and 343753, and the 41% between them: bench/README.md, DEVICES.md §11.5, translator/README.md, and #164. `release.py figures` cannot check a figure of a core that no gate measures.

The figures hold at this commit. Both programs pass on both cores, in nvc, in under two minutes together:

| | Pipelined | Multi-cycle |
|---|---|---|
| `float` | 581542 | 2264883 |
| `float_inline` | 343753 | 1261837 |
| `float` with `float.nasm` | 1917617 | |

The FPU is not untested on the cores: `make -C hdl test` runs `fpu`, `fpustack`, and `fpudec` on both, and CI's `programs` jobs run every program with floats on the FPU. What is missing is the one program whose figures the documents quote.

**Fix:** `slow/%/float` beside `slow/%/coremark`, with `CORE_PROGRAMS="float float_inline"`, a line in RELEASE.md §5, and the two cycle counts among the figures that `release.py figures` checks.

### 3.3 `NO_FPU=1` in `bench/` runs the other build's programs

bench/README.md line 39 says that the float programs are joined "with `NO_FPU=1` with the one in software". The Makefile's `NO_FPU` changes `FLOAT_LIB` only, a prerequisite, and not `BUILD`. So in a build directory that has the programs, as after any `make test`, make finds them up to date:

    $ make -C bench core CORE_PROGRAMS=float NO_FPU=1 SIM=nvc
    float on the pipeline core:
    ...
    total           180304       581542

That is the program with the FPU, and nothing says so. The other way round is worse: `make test NO_FPU=1` in a clean tree leaves `float.bin`, `dhry.bin`, and `coremark.bin` with the float library in software, and a later `make test` or `make cycles` without the option measures those. `make test` itself is right, since it builds its second `float.bin` with `BUILD=build/nofpu` in a make of its own. With that `BUILD` the option does what the README says: `make core CORE_PROGRAMS=float NO_FPU=1 BUILD=build/nofpu` gave the 1917617 of §3.2.

**Fix:** let `NO_FPU=1` choose the build directory, `BUILD = build$(if $(NO_FPU),/nofpu)`, so that the two never share files, and say in the README where the programs go.

### 3.4 The cycle model's FPU, and `float_inline`, are checked by their results only

- `pipecycles.py --test` has two snippets for the FPU, run with `fpu_op=4` and `fpu_long=60`, not the defaults. These changes pass `make -C bench test`: the default `--fpu-op` 30 where it is 18, `SQRT` taken out of the long commands, and a stack command of 3 cycles where it is 1.
- `make test` checks `float_inline.bin` by its five results. With `--inline-fpu` left out of its rule it passes too, as the results are the same.
- "The averages give `float.c` and `float_inline` on the pipelined core within 1%" (bench/README.md) is from a run by hand. `make compare` covers `bench` and `hand`. The claim holds: the model gives 576315 and 341012, 0.9% and 0.8% below the core.

**Fix:** with §3.2, `make compare` on the two float programs after `make slow`, and in `make test` a check that `float_inline.bin` has fewer instructions than `float.bin`.

### 3.5 The float library's stack rule is tested from an empty stack only

DEVICES.md §11.5 and ABI.md say that a routine leaves the FPU's depth as it found it, so that a caller may keep 8 values across a call. `runtime/test/float_fpu.py` starts each of its three runs with an empty stack, reads `FPU_STATUS` once at the end (line 213), and looks at the depth alone (line 344). A routine that pops one value too many on an empty stack leaves the depth 0, and sets only the stack fault, which the test does not read.

So these pass every test of `make -C runtime test`: `DROP 2` in place of `DROP` in the part that every f64 routine ends with (`float_fpu.nasm:57`, which I ran again), `DROP 3` in place of `DROP 2` after a comparison (line 143), and the same two in the code that `--inline-fpu` writes (`nicewasm.py:4496` and `4515`), which pass `translator/test/run.py` too. The code is right today: with 14 values pushed first, the same 41080 calls leave a depth of 14, no fault, and the values as they were, for the routines and for the inline code, and each of the four changes then fails.

**Fix:** push some values before the calls in `float_fpu.py`, and compare them, the depth, and the stack fault after.

### 3.6 nicebuild's new options are not checked to do anything

`translator/test/build.py:171` builds one C program with each option and compares its output, `42 6 hi 4`, which is the same with every option. So these pass: `--inline-fpu` not passed on to nicewasm, `float_fpu.nasm` joined in spite of `--no-fpu`, and `--memory-bytes` not passed on. No test runs a program built with `--no-fpu` on `niceemu --no-fpu`, so that such a program runs on a system without the FPU is tested nowhere from end to end, which is the case of §1.2. The three options are tried for C only.

**Fix:** a program with floats in each language, built with `--no-fpu` and run with `niceemu --no-fpu`; a look for an access to `0xFFFFFF8C` in the `.nasm` of `--inline-fpu`; and the words reserved with `--memory-bytes`.

### 3.7 `--memory-bytes` at its edges

- No case gives a number of bytes that is not a multiple of 4: without the rounding up to a word, `run.py` and `errors.py` pass.
- No case gives exactly the memory's size: with `>=` for `>` in the check against it, they pass. 70000 is the only size tried there.
- The `RESERVED` cases of `run.py` compare the comment "; Linear memory: the first N bytes of", and not the words reserved.

**Fix:** three cases: 62 bytes, 65536 bytes, and a count of the `.BLK` words.

### 3.8 The emulator: the edges at 2^31, and the ends of a skip

38 changes to `fpu.zig` and `cpu.zig` were tried, and 26 fail a test. Two of the rest change nothing that can be seen. These pass every test:

- **The limits of `FPU_X_W`.** The saturation at 2^31 and at −2^31 − 1, and the class bit "fits" for those two values (`fpu.zig:285` and `294`). The vectors' special values have 2^31 − 0.5 and −2^31, and not the first values that do not fit. The model's test has them among its 300 hand cases, but those never reach the emulator or the cores: only the vectors do.
- **A skip ended by an NMI, or dropped for the console.** DEVICES.md §3 names the timer, `--irq`, `--nmi`, and the console. `skip.nasm` uses the timer and `--irq`. Without the NMI in `skipStepDue` (`cpu.zig:1335` and `1479`), or without the console's request, every test passes.
- **A pause during a skip**, and the go on that counts the rest (DEBUG.md §6). `link.py` checks the single step and the breakpoint. Without the window the emulator counts a skip at once, so a pause can come during one only under `--window`, and `window.py` has no `TIME_SKIP`.
- **Small ones.** No test reads `TIME_SKIP`, which is to read 0, or writes `0xFFFFFF8F` through the processor. No vector tells k = 22 from k = 23 in `SCALE10`, and the last bit of the low parts of its table is pinned by no vector, though the tables equal the model's.

The emulator does these right today. A skip of 1000 steps with `--nmi 50:0x80` ends at step 50, and with `--nmi 700:0x80` at step 700. With the console's request enabled and a byte waiting, a skip counts nothing, and without the enable it counts its 1000 steps.

**Fix:** write the model's hand cases into the vectors; the two values in the vectors' specials; and runs of `skip.nasm`, or a second probe, with `--nmi` and with input.

### 3.9 No run interrupts, pauses, or steps a core that waits for the FPU

DEVICES.md §11.5: "An interrupt, and the pause and the step of the debug link, wait for it." The FPU holds a core for up to some 3300 cycles, 50 times the longest wait of the math unit. The runs of `make -C hdl test` with the FPU are `fpu`, `fpustack`, and `fpudec` on each core, and `fpu` again on a stalling memory (`hdl/Makefile:171` and `532`). None has a request, a pause, a held pause, or single steps. The random programs run with `G_FPU=false` (line 459), and the programs of the sweeps do not use the FPU.

The cores do it right today. In a copy, `fpu`, `fpustack`, and `fpudec` pass on both cores with `G_PAUSE`, with `G_PAUSE_HOLD` of 40 and of 3000, and with `G_SINGLE_STEP`, in the 12 runs that I ran again. A probe made of `fpudec.nasm`, with `FMOD` of 1e308 by 3 before it and routines for the NMI and the IRQ, passes `irq_sweep.py --stride 16 --delays 0,40,400,1500` on each core: 128 runs, with a request before 879 of its 1028 steps.

**Fix:** those runs in `make test`: `fpudec` with a pause, with a held pause of 3000 cycles, and one step at a time, and the probe as a sweep. Together they took about a minute here in nvc.

### 3.10 `tb_fpu` has few requests that wait for a command

`tb_fpu` does the access of each vector and then reads `FPU_STATUS`, so the request that waits for a running command is nearly always that read. After the vectors it checks one read of `FPU_CMD` and one of `FPU_X_HI` while `DIV` runs (`tb_fpu.vhd:183`–`235`). The other registers wait for a command only in the programs on the cores. With the waiting request of one register broken in `fpu.vhd`:

| The request that waits | What fails |
|---|---|
| a read of `FPU_X_LO`, `FPU_X_S`, or `FPU_X_W` returns 0 | `fpu` on the cores, and for `FPU_X_W` `fpudec` too |
| a write of `FPU_X_S` is dropped | `fpustack` on the pipelined core only |
| a read of `FPU_REL` returns 0 | nothing in `make test`, and no proof; `float32` and `float32_inline` of `make programs`, on the pipelined core only |
| a write of `FPU_X_LO`, `FPU_X_HI`, or `FPU_STATUS` is dropped | no simulation of `make test`, and for the first and the last no program of `make programs` on either core; the stack model of `formal_fpu` only |

The last row I ran again for `FPU_X_HI`: bounded to 8 cycles, the stack model fails in 23 seconds. As a release runs it, that model is `prove_stack`, of 23 minutes, in `make formal`.

**Fix:** let `tb_fpu` do the next access without the read of `FPU_STATUS` between, for a share of its vectors, so that each register in turn waits for a command.

### 3.11 A reset during a command

- With the reset of the arithmetic unit removed (`fpu_unit.vhd:1131`–`1134`, "Reset ends an operation"), every simulation of the FPU passes, the two testbenches and the eight runs on the cores, which I ran again. Both testbenches reset once, before the first access, and the proofs use a stand-in for the unit.
- The FPU's own reset of the depth, the flags, and the state is checked by the proofs only. No simulation resets after its start.
- "A start resets the FPU" (DEBUG.md §6) is tested on the emulator, by `link.py`, and not in `hdl/`: `tb_link` has no FPU.
- This review did not run a reset during a command either. By reading, the unit goes to its idle state and drops its result, and the FPU empties its stack.

**Fix:** a reset in `tb_fpu` while `DIV` runs, then an access, and a second reset between two sequences of the vectors.

### 3.12 Nothing checks the cycles of the commands

`tb_fpu` and `tb_fpu_unit` report the most cycles from a request to its ACK, 2153 in `make test`, and compare it with nothing. The only bound is the watchdog of `tb_core`, 10000 cycles for a step. DEVICES.md §11.5 gives the cycles of eight commands, and the cycle model of `bench/` takes two averages from them. With a `tb_fpu` that reports the cycles of each write of a command and of the read of `FPU_STATUS` after it, the vectors of `make test` give:

| Command | Median | Most |
|---|---|---|
| `ADD`, `SUB`, `MUL` | 18 to 21 | 37 |
| `DIV`, `SQRT`, of finite operands | 70 to 72 | 83 |
| `ISQRT`, of finite operands | 92 | 98 |
| `SCALE10` | | 1073 |
| `FMOD` | | 2114 |
| `DIGITS` | | 2154 |

- `ISQRT` takes some 90 cycles, and §11.5 says some 70 (§4.6).
- No vector comes near the "up to some 3300" of `DIGITS`. An agent's scan of `DIGITS` around every power of ten, of `SCALE10` by every count from −660 to 660, and of `FMOD` reached 3145, 1233, and 2124 cycles, and `fpu.vhd` gave the model's result on each of its 19258 lines.
- The directed vectors of `DIGITS` take 16 values (`fpu_vectors.py:656`). With the constant `C_LOG10_2` of `fpu.vhd` lower by 87, every test passes; the loop makes up for an estimate that is one too low, so the results stay right, and only the time grows.

**Fix:** a bound for each command in `tb_fpu`, the figures of §11.5 with a margin, and vectors of `DIGITS` that take its longest path.

### 3.13 What runs in no gate

- `make -C emulator fpu-long`, the vectors with a million random accesses, is in neither `make slow`, nor `release.py check`, nor CI. It passes at this commit with `SEED=1`, in 77 seconds.
- `make -C runtime/libc fuzz` is in none either, as before. It now joins `float_fpu.nasm`, so the float library in software, which it fuzzed until `V2.1`, is fuzzed only with `--no-fpu` by hand, and `fuzz_printf.py` has no such option. All three pass with the FPU, and the two that take `--no-fpu` pass with it.
- `translator/test/fuzz.py` and `diff_fuzz.py` make no float instruction, and have no mode for `--inline-fpu`. So the inline code under pressure for registers is tried only by `floats.c`, the float benchmark, and constant operands.

**Fix:** `fpu-long` and the fuzz of the C library, both ways, in `make slow`. Float instructions in `fuzz.py` are an issue of their own.

### 3.14 `run.py` runs niceemu with no step limit

`translator/test/run.py:3585` runs each program with `subprocess.run` and neither `-n` nor a timeout. A program that runs away hangs `make test`, with no line that says which. `kept_program`, new in this release, adds such runs under `--keep`, which `make programs` gives: it keeps a program translated again with `--memory-bytes` where its run gives the same outcome. It has no test of its own. One of the changes of §3.7 ran away so, and had to be stopped by hand. **Fix:** `-n` with a limit far above the longest case.

## 4. Stale statements

### 4.1 DEVICES.md §8: the board sets its clock from the real-time clock

The **Clock** bullet, line 535, says of the MEGA65's real-time clock: "NiceMonMEGA65 is to set the clock from it in its ROM at a cold start, in that local time, and never writes it (MJoergen/NiceMonMEGA65#105); it does not yet", and then: "So on both, "set" stays 0 until a program sets the clock." That issue closed on 2026-11-11, hours after `V2.1`, and the board's `V2.0.1` has it:

- The monitor in the ROM sets the clock from the real-time clock at its start, when the clock is not set yet, and leaves it when the chip says that it lost its time (the board's `doc/SYSTEM.md`, and its 5f5cfb5).
- The monitor's `time` writes the real-time clock (its b41271f), so "never writes it" no longer holds.
- So on the MEGA65 "set" is 1 after the ROM's start. On the Nexys4DDR, which has no such chip, it stays 0.

**Fix:** say what the board does, as the other bullets do. The table of board tags in RELEASE_NOTES.md also lacks `V2.0.1` in the row of `V2.0`, which it pins (RELEASE.md step 8.5).

### 4.2 hdl/README.md: the times of `make formal` and `make programs`

- Line 71 says that `make formal` takes "20 minutes on 20 CPUs, most of it the debug link's covers". Line 1463 of the same file gives the FPU's `prove_stack` "about half an hour", alone. The release check of `V2.1` took 1699 seconds for `make formal`, 28 minutes, before the FPU's tasks.
- Line 74 says that `make programs` takes "25 minutes on the pipelined core and 51 on the multi-cycle one in GHDL; 5 and 3 in nvc". #169 measured 423 seconds on the pipelined core in nvc, 7 minutes, after its two commits, and 517 before. CI's two jobs took 11 and 10 minutes at this commit.
- Lines 1260 to 1264 say the same times, "its four modes" of `fuzz.py`, and "some 2 million steps in 490 programs". The Makefile's loop has five modes, `--windows` among them. CI's job at this commit makes 867 programs and runs 610, the others being the same as one of those, and the 610 take nearly 9 million steps on the emulator.

**Fix:** measure both at the release check, and write the figures with their date.

### 4.3 MICROARCH.md §8: the math unit is no longer the slave that waits longest

- Line 904, **Bus decoder**: "since the math unit holds an ACK for up to 65 cycles". The FPU holds one for up to some 3300 (DEVICES.md §11.5).
- Line 1027, the cause STALL of the fetch statistics: "a slow memory, or the math unit with a result not ready". A read of the FPU while a command runs is such a read too, and in a program with floats it is the common one.

**Fix:** name the FPU in both, with its figure.

### 4.4 runtime/README.md: the size of `float.nasm`

Line 267: "Assembled, `float.nasm` is about 6900 words, 7150 with its stack." As a program joins it, it is 6844 words, 264 of them its memory, the stack and 8 words of data: the float benchmark shrinks by 6555 words, 6844 less the 289 of `float_fpu.nasm`. The sentence dates from 2026-10-27. The 6578 words that the other documents quote are `make -C bench words`, the module without `--no-mpu` and without its memory. **Fix:** 6580 and 6844.

### 4.5 bench/README.md: "the 1916828 without the FPU"

Line 618: "That is 3.3 times fewer cycles than the 1916828 without the FPU". 1916828 is the estimate of `make cycles` in the table above it. The pipelined core takes 1917617, as line 584 says, and as it does at this commit. The factor is 3.3 either way. **Fix:** 1917617.

### 4.6 DEVICES.md §11: the time of `ISQRT`

- §11.5, line 895: "`DIV`, `SQRT`, and `ISQRT` some 70" cycles. In `fpu.vhd`, `ISQRT` is `SQRT` toward zero and then the rounding to a whole number, two operations of the arithmetic unit. Of finite operands it takes 78 to 98 cycles, with a median of 92, where `SQRT` takes 70 to 75 (§3.12).
- §11.3, line 727: "`ISQRT` takes the time of `SQRT` and saves the `FLOOR`." It saves the command, and takes some 20 cycles more than `SQRT`.

**Fix:** "`DIV` and `SQRT` some 70, and `ISQRT` some 90" in §11.5, and "`ISQRT` is one command" in §11.3. The cycle model's `--fpu-long`, 75, counts `ISQRT` with `DIV`; no benchmark uses `ISQRT`, so no figure changes.

### 4.7 `math.h` and `libm.h`: "NICE has no floating-point exceptions", optional

`runtime/libc/include/math.h:6` and `src/math/libm.h:6` say that NICE has no floating-point exceptions, "as the float library raises none". The FPU has the flags invalid, division by zero, and overflow (DEVICES.md §11.2). What holds is ABI.md's sentence: compiled and translated code never reads them. **Fix, if wanted:** "the C library reads no flag of the FPU" in both.

## 5. Gaps

### 5.1 hdl/README.md has no section for the FPU

The README has a section for each device of `hdl/src`: the timer, the console's receive interrupt, the math unit, the performance counters, the clock, the fetch statistics, the SD card controller, the network station, and the Ethernet frames. The FPU is in "What the tests check" and "The formal checks" only. An integrator does not find there what the header of `src/fpu.vhd` says, nor what it does not say:

- the port, a pipelined Wishbone slave with a 3-bit address, selected for `0xFFFFFF88`–`0xFFFFFF8F`;
- which reset it takes: that of a start of the processor, as `tb_core` gives it, so that DEBUG.md §6 holds;
- that it holds STALL for up to some 3300 cycles, so a pause and an interrupt wait that long, and a watchdog of a system must allow for it, as `tb_core`'s now does;
- the cycles of each command, which are in DEVICES.md §11.5, bench/README.md, and #164 in three forms;
- its size and its timing (§3.1).

**Fix:** a section "The floating-point unit" after "The math unit".

### 5.2 MICROARCH.md §8 names neither the FPU nor the clock

§8 lists the devices of `hdl/src` with the rule that a system follows for each, from the console to the Ethernet frames. `fpu.vhd` is not there, and neither is `tod.vhd`, the clock of `V2.0`, whose words lie inside the range of `perf.vhd`. **Fix:** a bullet for each: the address bits the decoder compares, the reset, and for the FPU the wait.

### 5.3 The lists of the synthesis check, and two comments

`hdl/README.md:96` lists what `ghdl --synth` checks, and leaves out the FPU and its arithmetic unit, which `SYNTH` in `hdl/Makefile:685` has. The comment above `SYNTH` names the arithmetic unit and not the FPU. The eleventh review found the same of the two units of `V2.1` (its §3.2). **Fix:** both names in both.

- `hdl/Makefile:706`: the comment "The debug link is proven twice, with and without a ROM" now stands above `FORMAL_TASKS_fpu`, and the line of the debug link below that. **Fix:** the comment back above its line, and one for the FPU's three tasks.
- `hdl/test/tb_fpu.vhd:12` names §11.2 for the waits that it checks. The rule of a read of `FPU_CMD` is in §11.1, **Waiting**. **Fix:** §11.1.

### 5.4 Two lists of the devices

- `doc/README.md:9` lists the devices of DEVICES.md down to "and clock". **Fix:** "clock, and floating-point unit".
- The usage text of niceemu, `emulator/src/main.zig:23`, gives the range of each device, and not the FPU's, which only the line of `--no-fpu` has. **Fix, if wanted:** "the floating-point unit at 0xFFFFFF88-0xFFFFFF8F".

### 5.5 DEVICES.md §11.3 holds an open item

Line 811, of `SCALE10` beyond k = 22: "the error has a bound that this section will state once it is proven". CONTRIBUTING.md puts open items in issues. #167, phase 2, asks for the bounds of the functions and does not name this one. The sentence after it says what was measured, which is what is true now. **Fix:** add the proof to #167, or give it an issue, and let §11.3 say that no bound is proven yet.

### 5.6 HISTORY.md, optional

HISTORY.md has the rename and TODO.md, and nothing else of this release. Two things used to be true and are in no document now: until `V2.2` the float library in software was the only one, and nicewasm had `--library-memory` and `--ram-bytes`, which `translator/test/diff_fuzz.py` still knows. The notes will say both (§1.1). **Fix, if wanted:** a paragraph in "The size and speed of translated code".

### 5.7 emulator/README.md: the other runs of `skip.nasm`, optional

The README says that `fpu_mem` runs `fpu.nasm` again with `--no-fpu`. It does not say that `skip.nasm` runs three more times, as `skip_off`, `skip_limit`, and `skip_mem`: without `--step-time`, cut short by the step limit, and with `--no-cycle-counter`. **Fix, if wanted:** one sentence after "The probe `test/skip.nasm` shows these rules."

## 6. What was checked, and found right

These are recorded so that the next review need not repeat them.

- **The FPU's documents agree.** DEVICES.md §11, the READMEs of the emulator, the runtime, the translator, and the benchmarks, ABI.md, WASM.md, TOOLCHAIN.md, and the usage texts of niceemu, nicewasm, and nicebuild say the same of the registers, the options, and which float library a program joins. The link stays version 8, and the start that resets the FPU is in DEBUG.md §6, in the emulator, and in `link.py`.
- **The examples of §11.3 hold**, worked out by hand: the S form on 1 + 2^−24 and 2^−54, `ISQRT` of 2^106 + 2^55, `ROUND` of the largest value below 0.5, 3 · 0.1, `IDIV` of −1 by 2, and D · 5^(16−n) < 2^53 for n up to 15. The 16 values of `CONST`, in `fpu.vhd` and in `fpu.zig`, are each the binary64 value nearest its number, by `decimal`.
- **The figures.** `float_fpu.nasm` is 289 words. `float.c` is 16825 words with `float.nasm`, 10270 with the FPU, and 10533 with `--inline-fpu`. The three tables of the emulator in bench/README.md are what the programs print, and with them the 5.9 times, the 53%, and the 2.6%. The pipelined core takes 581542, 343753, and 1917617 cycles, which give the 3.3 times, the 41%, and the 3.23 and 4.04 per instruction. `make cycles` gives 576315 and 341012, and `make words` 11523, 5903, 30073, 6578, and 23392. `release.py figures` passes.
- **The emulator's tests.** The eight new `.expected` files, of `fpu`, `fpu_mem`, `fpustack`, `fpudec`, `skip`, `skip_off`, `skip_limit`, and `skip_mem`, were worked out again by hand and are right. A change to any of these fails a test: the reset and the link's start that empty the FPU; `--no-fpu` in a run, under the link, and in the decode; a read that changes nothing; a skip without `--step-time`, at the step limit, and with `--no-cycle-counter`; the timer and `--irq` that end a skip, and a pending request that drops one; the clock and the microseconds of a skip; the link's single step and its breakpoint after a skip; and in the arithmetic, `FPU_X_HI` on an empty stack, the class bit "whole", the S form's one rounding, an infinite X of `SCALE10`, `ISQRT`'s correction, `SCALE2`'s limit, `FROMBCD`'s digits, and bit 9 of `SCALE10`'s k. `--no-fpu` has its case in `errors.py`, and `main.zig` has no new message.
- **The float libraries.** `float_fpu.nasm` and `float.nasm` define the same 52 labels, which are those that nicewasm calls and those that `float_fpu.py` compares, on 30 special values of f32 and 34 of f64, each with each, and 300 random ones a routine. A change to the sticky bit of `___floatdisf`, to the NaN of a comparison, to the saturation of a conversion, or of `NEAREST` to `ROUND` fails it. Without the S bit it passes, rightly: for binary32 operands the two roundings are the same (§11.3). All 60 float instructions of wasm run with `--inline-fpu` in a test. Each C library test that calls the float library, `zigfloat`, `rustfloat`, and `float.c` run with both libraries, in `make test` and so in CI.
- **The messages.** Each of the 7 messages that `nicewasm.py` gained or changed, and of the 4 of `nicebuild.py`, has its case in `errors.py` or `build.py`.
- **The FPU in `hdl/`.** No change to `fpu.vhd` or `fpu_unit.vhd` found a bug in them. Of 33 changes, 23 fail a simulation of `make test`, 15 of them `tb_fpu`: the stack faults, the sticky flags, the write of `FPU_STATUS`, bits 31 to 17 of a command, S where it does not apply and S of `SQRT`, bit 9 and the cross term of `SCALE10`, the compare of `DIGITS`, the overflow of an infinite X, the flags of `ISQRT`, `IDIV` by 0, and the last step of `FMOD`, which `tb_fpu_unit` fails too. Of the other 10, the proofs fail 7, among them a view without STALL and a reset that keeps the state, which `prove` finds in a second. §3.10, §3.11, and §3.12 have the rest. `SYNTH` has both units, and the lint and the type check have the new files.
- **`make programs` after #169.** Every one of the 603 programs that `V2.1` made is still made, with 264 new ones, 252 of them with `--inline-fpu`. Each of the 257 that are not run has the `.bin` and the `.input` of one that is, by a hash of each. The shares `SHARD=1/N`, for N from 1 to 6, hold each program that is run exactly once, and `programs.py --test` checks the split in `make test`. 41 of the programs use the FPU, and all pass on both cores.
- **The files.** Every file that the release adds is named in the README beside it, but for the three of §5.7. No file names `SYSTEM.md` or `TODO.md` but HISTORY.md, the older notes and reviews, and one comment that means the board's own.
- **The board, where §8 is current.** MJoergen/NiceMonMEGA65#104 and #106 are open, as the bullets of the receive interrupt and the NMI say, and the board uses no option that this release removes.
- **The references.** `make -C doc test` and `make -C doc/intro pdfcheck` pass, in `make all`.
- **CI** passed every job on 7593bbc after this was written, `hdl` in 35 minutes and `formal` in 34.
