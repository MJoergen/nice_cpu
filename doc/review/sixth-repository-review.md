# Sixth review of the repository, at commit b2ac5a5

Reviewed on 2026-10-26: the state of the repository at commit b2ac5a5 ("ISA: RELEASE_NOTES.md for RC01 to RC05"), one commit after the tag `RC05`, as a release candidate. The fifth review looked at `RW01` of 2026-10-22. This one asked what the 139 commits since then introduced: the debug link and its three versions, the pause and the single step, the predictor, the microsecond counter, the handshakes, the simplifications of issues #51 and #54, the C library additions, and Dhrystone. It also asked whether the seventeen issues closed since then were closed in substance, whether the diagrams and the figures of MICROARCH.md still describe the core, and whether the branch `origin/release-script` should be rebased and merged.

**How it was checked.** Ten readers worked in parallel, each in its own clone, and changed nothing: one each for the closed issues and pull requests, the release-script branch, the documents as a set, the debug link in its three forms (DEBUG.md, `link.zig`, and `debug_link.vhd`), the emulator and the assembler, the runtime and the C library, the translator and `nicebuild.py`, the cores, the benchmarks, and a fresh machine. Unlike the fifth review, this one ran the tests: `make test` at the top level (5 min 31 s, passes), `make -C hdl test` (808 pass), `make -C hdl formal`, the differential test of the translator against the fifth review's commit, a trace comparison of the pipelined core across the 35 commits since then that touched `hdl/`, and `make hazards`, `make cycles`, `make core`, `make core-dhry`, and `make compare`. I checked the tags and their CI runs myself, re-rendered the three diagrams, compared the retire rows of `flow.tex` and `interrupt.tex` with a simulation, re-measured every figure of §8, reproduced the three behavior findings (§3.1, §4.1, §4.2), and re-read the code or the text behind every finding of §1, §2.1, §7.2 to §7.5, §9.2, §9.3, and §9.5. The rest is the readers' word, with file and line. Nothing is fixed; each finding says what the fix is.

## Summary

**No behavior bug in the cores, in the emulator's execution, in the assembler's output, in the runtime, or in translated code.** The pipelined core gives the same trace and the same retire cycles at every one of the 35 core commits since the fifth review, but for the predictor, which changes only the cycles of programs with predicted jumps (§7.1). So the handshake commit's "the cycle counts do not change" holds, and the simplifications of #51 and #54 changed nothing. The predictor survived six adversarial programs and 360 random programs with backward conditional jumps on both cores, with pauses, stalls, and interrupts. The translator gives the same results as the fifth review's on 1040 modules and the right ones on 96 hand-built loops. Three edges remain. `debug_link.vhd` lets the second checksum byte of a dropped packet through to the program as a console byte, where DEBUG.md and the emulator keep it (§3.1). `niceasm.py --symbols` can overwrite its input (§4.1). `niceemu` cannot be stopped with Ctrl-C while it waits for console input (§4.2).

**The releases were tagged before CI had judged them.** All five `RC` tags and `RW01` are lightweight, cut seconds after the push, so no tag has a message or a date of its own. RC04's two runs failed in the formal job, and main stayed red for a day. RC05's two runs were still in the programs jobs when this review was written, 80 minutes after the push; those jobs take two and four and a half hours (§1.1). The release-script branch is the answer to this, and its `tag` makes an annotated tag from the release notes, but as written its `check` can never pass and its `figures` fails (§10). The board repository pins a commit from before the debug link's third version and has no RC05 (§1.2).

**The predictor and the pause left stale text behind.** The translated column of the §5.6 table (§8.2), two percentages of §5.3 (§8.3), the quoted estimate and the Dhrystone table of bench/README.md (§8.4, §8.5), HISTORY.md's entry of the predictor (§9.2), three file headers that still say DECODE redirects only for condition "always" (§7.5), and the step numbers of §9 in five places (§9.3). Each is a line or a re-measurement, and `make hazards`, `make cycles`, and `make dhry` give the lines.

**What the tests do not reach.** The random programs never make a backward conditional jump, so the predictor meets random code nowhere in `make test`, `make random-sweep`, or `make sweep` (§7.2). The microsecond counter is proven and tested at 1.5 MHz only (§7.3). No test joins a core with the counters it is meant to stop (§7.4). The translator's fuzzer makes loops of one shape (§6.2). The seven simplifications of issue #53 were neither done nor declared (§2.1).

## 1. Release hygiene

### 1.1 The tags and their CI runs

| Tag | Commit | Pushed | The CI runs of the commit and of the tag |
|---|---|---|---|
| `RC01` | 8cda29c | 2026-10-22 | green about an hour later |
| `RC02` | 6e2ed8f | 2026-10-23 | green |
| `RC03` | 22eacce | 2026-10-24 | the push's run was canceled when `hdl` reached the 6-hour limit; the tag's run was green 5.5 hours later |
| `RC04` | decab5f | 2026-10-24 | both failed: `formal debug_link prove` crashed in CI's GHDL (`psl-errors.adb:37`), and the push's `hdl` job was canceled at 6 hours; main was red until fd3767a on 2026-10-25 |
| `RC05` | ac01285 | 2026-10-26 04:27Z | at 05:47Z nine jobs green, `programs (pipeline)` and `programs (multicycle)` running; on the last green commit those took 2 h 14 min and 4 h 33 min |

Every tag is lightweight (`git cat-file -t` says `commit`), so `git tag -n` shows the commit's subject, and no tag says what it is. `RW01`, on 9d8f13d, is explained in the fifth review and nowhere else. RELEASE_NOTES.md was written after RC05 was tagged, so RC05 has none of it. CI fails since the fifth review were of two kinds, and both were avoidable locally: `make lint` (vsg's `concurrent_006` in `pipe_prepare.vhd:136-140`, fixed by 1208d47; an indent in `debug_link.vhd:1089`) and `formal debug_link prove` (an induction counterexample at a3d5011, and the GHDL crash, which does not show with the local GHDL 6). **Fix:** tag after the push's run is green, with an annotated tag whose message is the tag's section of RELEASE_NOTES.md; `release.py tag` of §10 does the second. The programs jobs could run `--stall` and the plain mode in two jobs each, so that a run finishes in two hours.

### 1.2 NiceMonMEGA65 pins a commit before RC05

NiceMonMEGA65's submodule points at 62f2da2 (2026-10-25), 32 commits behind main, before the debug link's version 3 (696a372) and before RC05; its tags are `RC02` and `RC04`. A reader who follows README.md to the board gets a core and a link that do not serve the single step DEBUG.md describes. **Fix:** move the pin and tag the board repository `RC05`, and say in RELEASE_NOTES.md which board tag goes with each RC.

### 1.3 Branches and pull requests

- **PR #35** (`claude/pause-port`, 2026-10-20) was superseded by 3209fbb (#48): the same test names exist on main, and the board repository's matching PR #8 was closed unmerged. Close and delete.
- **PR #36** (`claude/project-thread-k4m3qt`): `RDSPC`, `RDSSR`, `WRSPC`, and `WRSSR`, the "writable registers and a port" of stage 6 in TODO.md's debug item. No file on main mentions it, and it conflicts in seven files. Keep until decided, with a pointer in TODO.md.
- **`origin/claude/project-thread-cmdpdw`**: a seven-line experimental predictor of 2026-10-17, 339 commits behind. Delete, with a line in "Decided against" if the `MOVE` form was rejected for timing.
- **`origin/read-waits`** (6af54d5): the measurement behind the decision against speculative reads (§2.3). Keep until its figures are in MICROARCH.md.
- **`origin/release-script`**: §10.

### 1.4 A hidden requirement: `llvm-ar`

README.md:174-176 says `make test` needs no C or Rust compiler. When clang and `wasm-ld` are found, `translator/test/build.py` builds C, and that runs `make -C runtime/libc libc.a`, whose Makefile line 3 has `AR = llvm-ar`, not `?=`. A machine with clang and `wasm-ld` but no `llvm-ar` fails `make -C translator test` with two failures; the reader reproduced it. `llvm-ar` is named only in a comment of ci.yml. **Fix:** check for `llvm-ar` in `clang_for_wasm32()` as for `wasm-ld`, and name it in README.md:177.

**Resolved**: `clang_for_wasm32()` also requires `llvm-ar` on `PATH`, or the program named by `AR`, and the skip note names all three tools. `AR` in `runtime/libc/Makefile` is now `?=`, so it can be set. README.md names `llvm-ar` and `AR`.

### 1.5 Smaller

- 19 of the 41 `.wasm` files have the executable bit again (bench.wasm, dhry.wasm, the C library's tests), though 82c72f1 cleared it after the fifth review: the `wasm` recipes restore it on every rebuild. A `chmod` in the recipes.
- `.mypy_cache/` is not in `.gitignore`, and `make clean` leaves it and `__pycache__`.
- A machine with Python, make, Zig, and git but no GHDL passes every test but `make -C hdl test`, which fails with `ghdl: not found` seven minutes in. README.md:63 says the cores need GHDL; the top-level `make test` could say so first.
- `nicebuild.py` without clang prints make's own `clang: No such file or directory`; without rustc it prints a clear message.
- The hdl scripts still need Python 3.10 (`str | None` in `irq_sweep.py:153`, `core_runs.py:46`, `programs.py:31`, `pcfx_prog.py:214`), as the fifth review said; README.md's 3.10 is right, and sixteen scripts lack the `__future__` import that would make 3.7 enough.
- Dhrystone 2.1 (`bench/dhrystone/`) has no stated terms, and `mchess.c` has no author, origin, or license line; README.md's License section covers "the code and the documents", which over-reaches for both.
- `timer.vhd:15` is 113 characters (390cfc6 joined the header's sentences) and `tb_core.vhd:805` is 104; vsg warns.

**Resolved**: Six of the seven.
- The `wasm` recipes of runtime/libc, bench, and translator end with `chmod -x`, the 19 files are back to mode 644, and `make -C doc test` fails if a checked-in `.wasm` file is executable.
- `.mypy_cache/` is in `.gitignore`, and the top-level `make clean` also removes the `.mypy_cache` and `__pycache__` directories.
- The top-level `make test` stops at once, with a message that names `TEST_DIRS`, when `hdl` is among them and GHDL is not found. `GHDL` names the program, as in hdl/Makefile.
- `nicebuild.py` checks for the compiler of the language (`CLANG`, `ZIG`, or `RUSTC`) before it runs anything, and `test/build.py` has a case for each.
- `timer.vhd:15` and `tb_core.vhd:824` are wrapped; vsg no longer warns about either.
- The Python 3.10 of the hdl scripts is won't fix, as TODO.md's "Decided against" now says.
- Dhrystone's terms are left. `mchess.c` is by the repository's author: its header has a copyright and license line, and README.md's License section says that the license covers it and does not cover Dhrystone.

## 2. The closed issues and pull requests

Seventeen issues closed since the fifth review, #34 and #38 to #54. The reader checked each against the commits that closed it and found all done in substance. Two were done differently from what they asked, and the difference is recorded: the three won't-fix items of #34 in HISTORY.md and pipeline-timing.md, and #46, where nicewasm closes its loops with the predicted jump instead of leaving them as they were.

### 2.1 Issue #53's simplifications were neither done nor declared

Issue #53 ends with seven checkboxes for `debug_link.vhd`: the memory condition written four times, two `err02_r` tests (now lines 468 and 471), `f_digit` beside `hex_of`, the register window test written three times, the tag literals `X"52"`, `X"57"`, and `X"23"` (fourteen times), one block per notice in `TX_IDLE_ST`, and `to_sl`. Only `to_sl` was done, with #54. The issue is closed, the boxes are unchecked, and neither TODO.md nor HISTORY.md says they are left or dropped. **Fix:** do them, or a TODO.md item.

### 2.2 Decisions recorded only in issue comments

Items 9 and 10 of #51 (won't do) and the items #54 left alone (the math unit's divider, `_o` against `_r`) are only in the issues. TODO.md's "Decided against" also lacks the won't-fix items of 2026-10-23: speculative reads, the math unit's store retiring early, and the timing fixes of #34; HISTORY.md:44-66 and MICROARCH.md §5.3 have them. **Fix:** a line each in "Decided against".

### 2.3 The evidence against speculative reads is on a branch

Commit e92703a says speculative reads were investigated and will not be done; MICROARCH.md §5.3 says so without figures, and HISTORY.md:59-66 gives the §5.6 percentages only. The measurement, 166 cycles (0.007%) of the translated benchmark, 18822 (1.5%) of the hand-written one, and 52002 waits on a path that was flushed, is only on `origin/read-waits`, with `readwait.nasm`. That commit's message also says the model charges a read after a skipped jump a wait that the core does not take, "a new TODO item"; the commit does not touch TODO.md, main has no such item, and on main the model charges nothing (`pipecycles.py`, "costs nothing") and is within 0.1% of the core (§8.1), so it was fixed without a record. **Fix:** the figures in §5.3 and HISTORY.md; then the branch can go.

### 2.4 The timing since the in-system figures

The in-system results, the MEGA65 R6 at 100 MHz and the Nexys4DDR at 90 MHz, were measured at 4cd869e. Since then the predictor, the pause, the handshakes, and #51 and #54 each reported `make timing` out of context in their commit messages, and pipeline-timing.md does not record them; RELEASE_NOTES.md says nothing about timing. **Fix:** a row per commit in pipeline-timing.md, and an in-system build at RC05.

### 2.5 Smaller

- Nothing checks that `bench.wasm` and `dhry.wasm` are current. They are: `make wasm` in a clone gives both byte for byte.
- DEBUG.md §8's example of a step assumes the processor is held before the write of `0x18`; the text does not say so.

## 3. The debug link

The reader checked DEBUG.md rule by rule against `link.zig` and `debug_link.vhd`, recomputed 26 checksums, ran `tb_link` on both cores, and ran the proof (`prove` and `prove_held` pass locally; the `cover` task takes about 20 minutes, and CI's formal job 27 minutes for it).

### 3.1 `debug_link.vhd` lets a checksum byte through to the program

DEBUG.md §5: "Every byte up to the `#` and the two bytes of cc after it belongs to the packet, so none of them reaches the program, even when the packet is dropped." `link.zig:259-272` does that: in `cc_high` any byte but ESC is taken as the high digit, and the state goes to `cc_low`. `debug_link.vhd:496-506` (`RX_CC1_ST`) goes to `RX_IDLE_ST` on a byte that is neither a hex digit nor ESC, so the second cc byte reaches the program as a console byte. Reproduced: `ESC R000001000001#Z94` gives the program two console bytes in a copy of `tb_debug_link.vhd`, where the emulator gives one. The proof does not say what reaches the program, so it cannot see it. **Fix:** stay in the packet with an invalid high digit, so that the checksum fails at `RX_CC2_ST`; a case in `tb_debug_link.vhd` and in `emulator/test/link.py`.

### 3.2 What a board must do is not in DEBUG.md

The six contracts a system keeps for `debug_link.vhd`, (a) to (f), are in its header and in hdl/README.md:1077-1095. DEBUG.md §7 gives the differences of the emulator and of a board, but not these, and neither says that the input FIFO must not let a `p` or `h` overtake a program byte. **Fix:** a list in DEBUG.md §7, or in SYSTEM.md §5.

### 3.3 A `W` with a bad checksum

DEBUG.md §3 says a `W` with a bad checksum "may leave some words written", and `debug_link.vhd` writes the words as they arrive. emulator/README.md:235-237 says the emulator writes nothing. DEBUG.md §7 lists the emulator's differences; this one is not among them. **Fix:** a line in §7.

### 3.4 The counters while paused

perf.vhd:37 and fetch_stats.vhd:39, contract (c): "`run_i` is low while the core is held or halted". DEBUG.md:122 says the counters stop while the processor is paused, and TODO.md says a board must stop them. Nothing tests a core and its counters together (§7.4).

### 3.5 The versions

DEBUG.md says the version register reads 3 (line 208) and never says what versions 1 and 2 were. RC04 shipped version 1 without saying so, version 2 was never tagged, and RELEASE_NOTES.md gives the two steps under RC05. **Fix:** a table of the versions beside the register.

### 3.6 What the proof covers is overstated

hdl/README.md and TODO.md say the proof covers that bytes after a halt are dropped; `f_strobe` does not check `halted_r`, and that rule is proven nowhere. No cover reaches `p`, `s`, or an `r` of memory, which the header admits, and contract (e) is asserted nowhere formally for the pipelined core. **Fix:** say what the testbench alone checks.

### 3.7 Tests

- Halt reasons 2 to 4 through the link are tested in the emulator only; `tb_link` halts with `HALT`.
- `link.py` does not test a half-closed reconnect, a clear while running, a lowercase tag, a pause during a console wait, or the timeout.
- With `-n N`, the Nth step ends in `h05`, never in `p`; a host should know. `send` blocks, and the timeout is measured at service time, not at arrival.

## 4. The emulator and the assembler

### 4.1 `niceasm.py --symbols` can overwrite its input

`niceasm.py:649` checks that the `.bin` output is not the input and exits with "the output file would overwrite the input". Line 670 opens the `--symbols` file with no such check, after the `.bin` is written. `niceasm.py --symbols prog.nasm prog.nasm` replaces the source with its label list, and `-o f --symbols f` leaves `f` as the label list. An unwritable `--symbols` path exits 1 after the `.bin` was written, where the README says a failed run writes no output. **Fix:** the same check for `--symbols`, against the input and against `-o`, before anything is written; an `errors.py` case.

### 4.2 `niceemu` cannot be interrupted while it waits for input

Commit 4c42461 installed handlers for SIGINT, SIGTERM, and SIGHUP that set `stop_signal` (`main.zig:183-203`), checked every 65536 steps (`main.zig:451-452`), so that the output is flushed; emulator/README.md:157-161 says the emulator then dies of the signal. While the program waits in a console read (`cpu.zig:449`), no step runs, the check is never reached, and the read restarts after EINTR, so Ctrl-C does nothing. Before 4c42461 the default action killed the process. Reproduced. **Fix:** after a read returns EINTR, treat a set `stop_signal` as the end of the input, so the run ends through the normal path.

### 4.3 Smaller

- `--irq` at step N and the timer's request at the same step: `--irq` wins (`main.zig:454-460` runs before `cpu.zig:525-528`), against the first-vector rule of RC02. No document says it, and no probe pins it.
- Two labels at one address: niceasm sorts by address and then name, so `--symbols` names the alphabetically first, and `main.zig:175` tests only that one for `___wasm_trap`, so an alias that sorts before `_` hides the `Trap` line. No real program has one.
- emulator/README.md:135's memory map omits the microsecond counter; the synopsis at line 53 lacks the `--link` form; line 79 does not describe the `.sym` format, nor that `.EQU` names are left out where assembler/README.md says "every label"; nothing warns that no step limit means a program may run forever; `hdl/test/tb_trace.vhd:29` and `hdl/sim/trace.vhd` still call 100000000 "the emulator's default for `-n`".
- `--no-cycle-counter` makes `TIME_LO` and `TIME_HI` plain memory too, and an empty `.sym` file is accepted silently. Both untested, both fine.

## 5. The runtime and the C library

### 5.1 The 81 KB claim is wrong the other way

runtime/README.md:178: a Zig program linked with `libc.a` "holds the whole library, about 81 KB of wasm". The fifth review (§5.2) made the claim; the reader rebuilt the example, and Zig keeps only the objects the program references: 3590 bytes of wasm, 4180 words, against 13155 bytes for the whole library. 81 KB is the size of the `.bin` file. **Fix:** drop the sentence, or say that both compilers keep only what is used.

### 5.2 mchess

- `mchess.c` has no author, origin, or license line, and the author's own repository has no license file. A header line, for a release.
- runtime/README.md:307 says the expected values of the C library tests "were checked by hand". `mchess.expected` is 600 lines of ANSI output and was not. The reader checked it instead against a native clang build on the same input, identical, and the perft counts 20, 400, and 8902. Say so.
- The search that needs the 128 KB stack is not exercised: the test runs perft only, 11.35 million steps in 2.5 s.

### 5.3 `--stack` needs `--memory`

`nicebuild.py --stack 131072 mchess.c` fails with wasm-ld's "initial memory too small"; it works with `--memory 262144`. Only a comment in runtime/libc/Makefile (`BIGSTACK`) says so. **Fix:** a sentence in translator/README.md, or raise `--memory` to cover the stack.

### 5.4 Smaller

- `trapmsg.nasm:24` names a code outside 1 to 7 by `code & 7`, and line 19 prints `code + 0x30`: code 12 prints "trap <: integer overflow". The emulator says "unknown code", trapmsg "unknown trap". A compare against 8.
- `time.h:11` defines `CLOCKS_PER_SEC` as an int, not `clock_t`. Neither the README nor the header says a microsecond is a step in the emulator, and only the header says `clock` wraps after 71.6 minutes on a board.
- runtime/README.md:70-73's list of reserved labels omits `_exit` (`lib.nasm:108`, new) and `___trap.*`; a program that defines its own `_exit` no longer assembles, and RELEASE_NOTES.md does not say so.
- "stdout and stderr are the same stream", but they are distinct `FILE` objects. `exit(EXIT_FAILURE)` is `HALT`, so `niceemu` exits 0, as documented, where `abort` and `assert` give 2.
- The "No ..." list of the C library misses `atoll`, `strdup`, `isblank`, `perror`, `setvbuf`, `rewind`, `clearerr`, `div`, `ldiv`, `difftime`, `mktime`, and `strftime`.
- ABI.md:100 gives the join order as the start-up code, the units, the wasm module, and the runtime library; `nicebuild.py` joins the start-up code, the program, `lib.nasm`, a muldiv file, `float.nasm` if any of its labels is used, and `trapmsg.nasm`.
- WASM.md's "From C" recipe for a trap handler cannot be built, since `nicebuild.py` cannot add an assembly file; TODO.md:189-194 has it.

## 6. The translator and `nicebuild.py`

### 6.1 Loop closing holds

The differential test of nicewasm at b2ac5a5 against 9d8f13d: 1040 modules (300 plain, 300 with traps, and the grow, no-mpu, library, and unchecked modes), identical console output, halt reason, registers, and memory. By hand: eight loop shapes (a middle back edge, `br_table` into the loop, an unconditional `br 0`, nested loops with adjacent back edges, an inner `br_if 1` to the outer loop), 60 generated loops over the ten comparisons in i32 and i64 at edge values, values on the stack at the branch, an f64 condition, and a trap inside a shared bounds check, each in four configurations: all right. `predict_back_edges` (`nicewasm.py:2256`) sets `.back` only when the `br_if` moves no values, targets a loop, and is followed by `end`s alone; the offset is a whole constant word and always negative. The change swaps the encoding of the same jump, so it cannot alter what a program computes.

### 6.2 The fuzzer makes loops of one shape

`gen_loop` (`test/fuzz.py:947-971`) always ends a loop with `local.get; i32.const 1; add; local.tee; i32.const k; i32.lt_u; br_if 0; end`, and asserts that no branch in the body targets the loop. So neither the fuzzer nor the differential test sees a middle back edge, a `br_table` to a loop, a `br 0`, a signed, 64-bit, or float condition, values on the stack at the branch, or adjacent nested back edges. The hand tests cover them, outside the repository. **Fix:** a second loop shape in `gen_loop`, and the hand harness as a test.

### 6.3 A test that fails under load

`test/errors.py:402` fails the "8000 nested blocks" case when the translation takes more than 4 s of wall-clock time. Under a load of 134 it took 4.0 s of wall time for 0.25 s of CPU time and failed; alone it passes. `make -C translator test` stops at the first failure, so `build.py` did not run in that pass. **Fix:** measure CPU time, or allow 30 s; a quadratic regression would still show as minutes.

### 6.4 `nicebuild.py`

- The README says the defaults are those of its recipes. The C recipe has `-Wl,--allow-undefined`, which `nicebuild.py` omits, and there is no way to join a `.nasm` file, so a C program that calls hand-written assembly cannot be built with it (`undefined symbol`).
- `-o /nonexistent/x.bin` prints "python3 failed with status 1" after the whole compile.
- `--stack 0` is silently the default (`args.stack or 4096` at lines 100, 104, and 117); `--stack -5` reaches wasm-ld.
- translator/README.md lists `--no-bounds-checks` and `--memory-pages` in the synopsis without describing them.
- `test/build.py` does not cover `-D`, `-I`, `--stack`, `--memory`, `--no-mpu`, floats, several C files, a failing compiler, or an unwritable output.
- Static prediction costs six cycles at each exit of a loop that runs once; translator/README.md:690-700 says only that the predicted form "still gains" from three rounds on.

### 6.5 Stale figures

- translator/README.md:187-188 and bench/README.md:403: `safe.zig` 5170 words and the float library 7083; `make words` gives 5156 and 7079 (bench 8537 holds).
- TODO.md:156 "Loop back edges cost the three cycles of an early redirect each round": two since the predictor.
- translator/README.md:829 "CI has Zig only": ci.yml has installed clang and lld since 0ba0ec7.

## 7. The cores

### 7.1 No behavior change but the predictor

The reader extracted the sources at each of the 35 commits since 9d8f13d that touched `hdl/`, ran the pipelined core on 26 programs (the hazard programs, `cputest` plain and stalled, three random programs with interrupts and 30% stalls, and six new predictor programs), and compared the full trace and the cycle of every retire. All 34 consecutive pairs are identical but 82bfeeb to c96cdb0, the predictor, which changes only the cycles of programs with predicted jumps and the trace of `bubble.nasm`, which reads the cycle counter. So the handshakes (aebd390) kept every cycle, and the simplifications of #51 and #54 changed nothing. The predictor programs: skipped and taken back edges, flags from the instruction before, two predicted jumps back to back, a jump to itself, stores into the target's constant, into the jump's own offset, and into the word after it, skipped jumps into the I/O range and the screen, a taken jump into the I/O range, and the offset `0x80000000`, with single step, pause and hold, stalls, and eight interrupts: all match the emulator on both cores. The pause: both cores separate the pause from the step boundary and the interrupts, clear `after_go` on the report of a step, put the pause ahead of NMI and IRQ, hold no bus cycle open while `paused_o` or `halted_o` is 1, and give the halt codes of DEBUG.md §6. `make -C hdl test`: 808 pass. Lint and typecheck clean. Formal: 27 of 28 tasks passed, and the 28th, `debug_link` cover, takes about 20 minutes.

### 7.2 The random programs never make a predicted jump

`random_prog.py`'s R15 template (line 141) makes forward jumps only, and the one backward jump of a program is the unconditional one at its end. So `make random-sweep`, `make sweep`, and the interrupt sweeps never exercise the predictor; `jumpwords.nasm`, `bubble.nasm`, and the benchmarks do. The reader added a template, `[cond] ADD R15, R15, c` in either source order with a negative offset to one of the last twelve instructions, and ran seeds 1 to 120 on the pipelined core, the multi-cycle core, and the pipelined core with a pause every five steps: 360 runs, 0 failures, about 26000 taken and 700 skipped predicted jumps in the first 40 seeds. Interrupt sweeps of two predictor programs, 1036 runs, pass. **Fix:** the template in `random_prog.py`, and a predictor program in `HAZARD_PROGS`.

### 7.3 The microsecond counter is proven at one frequency

`formal_perf.vhd:52` sets `C_CLK_HZ` to 1500000 and proves `perf` equal to a model that counts two microseconds per three cycles; `tb_perf.vhd:66` uses 1500000 too. No other frequency is proven or tested, nor the range of `frac_r`. The reader simulated 33333333, 83333333, and 100000000 Hz: the count is the integer part of N·10⁶/`G_CLK_HZ`, exact, and `run_i` low freezes it. SYSTEM.md:109 says "exact for any frequency", without the rounding and without the lower bound of 1 MHz, which only perf.vhd:17-21 and the generic's range (1000000 to 500000000) state. **Fix:** "the integer part of N·10⁶/`G_CLK_HZ`, for 1 MHz and up" in SYSTEM.md §3; a `tb_perf` run at a frequency that 10⁶ does not divide, such as 33333333.

### 7.4 `run_i` is not a rule of the system

MICROARCH.md §8's rules for a system do not say that it drives `run_i` of the counters and the fetch statistics, nor with what; the fetch statistics bullet says only that they stop "while the core is held or has halted". perf.vhd:37 and fetch_stats.vhd:39 say "held or halted", DEBUG.md:122 says the counters stop while paused, and SYSTEM.md:108-109 says "held or has halted". No test joins a core with the counters: `tb_core` leaves `run_i` at its default `'1'`, and `tb_link` wires no counters or timer. **Fix:** a bullet in §8, "`run_i` is 0 while the core is held, paused, or halted, from `paused_o` and `halted_o`", the same words in the two headers, and the counters in `tb_core`.

### 7.5 Stale text

- `pipe_decode.vhd:8-9`, `pipeline.vhd:80-82`, and hdl/README.md:945 say DECODE redirects FETCH for `MOVE R15, c` and `ADD R15, R15, c` "with condition always"; since c96cdb0 it also redirects a conditional `ADD R15, R15, c` with a negative offset, and pipeline.vhd's "WRITE then does not flush" is false for a skipped predicted jump (`pipe_write.vhd:592-593`).
- hdl/README.md:1180 "The cycle counter counts every clock cycle after reset"; line 217 and perf.vhd say "with `run_i` high" since 8463689.
- hdl/README.md:849 "one cycle of `pause_i` = 0 runs exactly one step" lacks "while the core is paused", which MICROARCH.md §6.1 has; a pulse before the core reaches the boundary only cancels the pause.
- The step numbers of MICROARCH.md §9 (§9.3).

**Resolved**: Three of the four; the step numbers are §9.3's.
- `pipe_decode.vhd`, `pipeline.vhd`, and hdl/README.md say that DECODE also redirects FETCH for a conditional `ADD R15, R15, c` with a negative `c`, and `pipeline.vhd` says that WRITE then flushes only when the condition is false.
- hdl/README.md says that the cycle counter counts the cycles after reset in which `run_i` is high.
- hdl/README.md says that one cycle of `pause_i` = 0 runs one step "while the core is paused".

## 8. The benchmarks and the figures of MICROARCH.md

### 8.1 What agrees

- `make diagrams` renders `pipeline.png`, `flow.png`, and `interrupt.png` byte for byte as committed, though `pipeline.tex` and `flow.tex` were edited after their PNGs (comments only). The retire row of `flow.tex` matches a run of `addwave.bin` with `G_RETIRE_LOG`, and the two panels of `interrupt.tex` match `irqwave.bin` with `--irq 2:9 --irq 10:9`; the cores reader checked the other rows with a report process. The handshakes and the pause changed none of the cycles.
- `make core` gives the cycles of bench/README.md to the cycle, 2357155 and 1252613, and `make compare` puts the model within 0.1% of the core on every phase of both programs.
- The hand-written column of §5.6 matches `make hazards` in all sixteen rows. §5.4's figures hold: the redirect cycle costs 1.5% and 2.8% (267540/7 and 238917/7 of the cycles), the predictor saves 9.6% and 1.2%, R14 is 7% of the hand-written instructions (6.6%). The instruction counts 1652811 and 491309, the module of 8537 words, the 28001 dispatches of TODO.md:49, and the figures that the rule options of `pipecycles.py` give are right everywhere they appear.
- Dhrystone's port changes only lines under `#ifdef NICE` and one `#ifndef` in `dhry.h`; `dhrycheck.py` checks 22 values and the program's own "should be" lines against a table written by hand; runs below 1 are refused.

### 8.2 The translated column of §5.6 is stale

The table at MICROARCH.md:486-503 was measured at d5e3cd0, before f678c7b closed nicewasm's loops with the predicted jump; that commit updated §5.4's text only. `make hazards` now gives:

| Row | §5.6 | Now |
|---|---|---|
| Instructions | 1726040 | 1697422 |
| Skipped | 20.3% | 19.1% |
| Conditional | 22.3% | 22.7% |
| Data read | 11.9% | 12.1% |
| Store | 5.8% | 5.9% |
| Jump: writes R15, or a control instruction | 20.1% | 18.7% |
| Reads a register the previous instruction writes | 29.9% | 30.4% |
| Reads a register written two back, not one | 7.3% | 8.3% |
| Conditional, SR written by the previous instruction | 20.1% | 20.4% |
| Data read after a store | 0.7% | 0.8% |
| Data read after a conditional jump | 5.6% | 5.8% |

Words per instruction, micro-ops, the two 0.0% rows, and R14 hold. **Fix:** paste the column from `make hazards`, with the commit named.

### 8.3 Two percentages of §5.3

| MICROARCH.md | Says | The model's charge now, of all cycles | Written at |
|---|---|---|---|
| :335-336, a read that WRITE takes a cycle after its ACK | 4% translated, 6% hand-written | 7.4% and 11.9% ("read data used by more than a register write") | 1b18fd6, 2026-10-20, when the estimate was 2247688 cycles |
| :343-344, a read directly after a store | at most 0.5% translated, 3.1% hand-written | 0.86% and 3.15% ("read after store, two reads in a micro-op") | f1e737e, 2026-10-21 |

The other figures of §5.3 hold: 0.8% and 8% of instructions (line 338), "0 to 4% and 5 to 8%" (line 347), and the 0.4% and 0.1% of line 322 come from an experiment that `make compare` cannot repeat. **Fix:** the two sentences, from `make cycles`.

### 8.4 bench/README.md's quoted outputs

- The `pipecycles.py` excerpt at lines 281-293 mixes two measurements: the summary line (1726040 instructions, 2466576 cycles, CPI 1.429), the "cycles above" line (740536), the flush row (0.155 per instruction), the early-redirect row (79046, 10.7%), and the `rng64` row (52768, 83026, 1.573) are d5e3cd0's, while cfdebb5 updated the total row alone (1652811, 2356816, 1.426). Now: 1697422, 2438761, 1.437; 741339; 0.158; 60047 and 8.1%; 51746, 82515, 1.595.
- The `--retires` paragraph at lines 375-378 gives 1a41b0c's figures (295 cycles below over 1613484 steps; 63 below over 494212). Now: 289 below over 1588218 steps, and 21 above over 493904 of `hand.nasm`. The `cycprof` example after it shows a `fetch` term the line no longer has.
- The table at lines 192-199: `strings` through nicewasm is 101281 instructions and 163528 cycles, not 104562 and 166871 (pre-f678c7b), so line 200's "1.50 times fewer" is 1.47.
- The ratio table at lines 123-129: `crc32` 2.4, `bst` 2.7, and `strings` 5.1 are 2.30, 2.61, and 4.98 now; `rng64`, `heapsort`, `vm`, and the total hold.

### 8.5 The Dhrystone table

bench/README.md:461 says "100 runs, measured at commit 4a3c917"; no such commit exists. The table's figures are from before d197992 rebuilt `dhry.wasm` with the current C library, in the commit that added them:

| Where | README | Now |
|---|---|---|
| emulator | 1559 cycles per run, 0.365 DMIPS/MHz | 1508, 0.377 (`make dhry`) |
| multi-cycle core | 17948, 0.031 | 17479, 0.032 |
| pipelined core | 2353, 0.241 | 2302, 0.247 (`make core-dhry`) |

RELEASE_NOTES.md:136 has 0.241 under RC03, and c-compiler-plan.md:91 has 2348 and 0.242: four values of one figure in four places. The port prints the figure truncated to three decimals, which line 442 could say. **Fix:** the table from the three commands, with a commit that exists, and the same figure in the notes.

### 8.6 Smaller

- MICROARCH.md:124 "1.62 in hand-written code"; the table at line 490 and `make hazards` say 1.66, since a517599.
- bench/Makefile:72-73 "Each takes about 20 minutes"; bench/README.md:16-17 says about 40, and lines 139-140 give 38 and 8. `make core` took 46 minutes under load; `make core-dhry`, "4 minutes" at line 18, took 14.
- TODO.md:150-152 "speculative reads (above)" refers to nothing above.
- The cost of a jump DECODE resolves: translator/README.md:693 says two cycles, bench/README.md:265 and TODO.md:156 three. `bubble.nasm` measures three in a stream and two behind a counter read, and §5.4 says "two" for the predicted form. One sentence that says both.
- `make compare` prints percentages only, so the README's per-phase differences (−56 and so on) cannot be read off its output. Neither pipecycles.py nor the README says the model ignores the pause.
- The new tables of bench/README.md (the `simple.nasm` table, the compare table, the 1252613 paragraph, the hazards sample, the `--retires` paragraph) name no commit, where the older ones do.

## 9. The documents as a set

### 9.1 RELEASE_NOTES.md

- RC05's upgrade notes name `pause_i` on the cores, but not `debug_link.vhd`'s new ports `pause_o`, `paused_i`, and `halt_reason_i`, which have no defaults, nor that `halted_o` of both cores now waits for the buses to be quiet.
- RC03 omits `G_CLK_HZ` on `perf.vhd` (default 100000000); RC02 and RC04 omit `run_i` on `perf.vhd` and `fetch_stats.vhd` (default `'1'`).
- New global labels: `_exit`, `___trap_report`, `___trap.*`, and `start_wasm_trap.nasm`. A program that defines `_exit` fails to assemble.
- RC02 omits the rules of 8cd38a6 (numbers below 2³², symbol syntax, `*` comments, control words take no constants, the read counter's reset).
- RC03's 0.241 DMIPS/MHz was RC05's figure, and is stale now (§8.5).
- Line 118's list lacks the Oxford comma.

### 9.2 HISTORY.md

- Lines 106-108: "1384879 to 1287563 cycles, 7.0% fewer ... `bench.c` took the same". a517599 took `hand.nasm` to 1252613, 9.6%, and f678c7b and cfdebb5 took 1.2% off `bench.c`; MICROARCH.md:410-412 and bench/README.md:159-162 have the current figures, and no entry gets to them.
- No entry for the merge rule (2b7a24e), the counters stopping at a halt (8463689), the fetch statistics stopping (40e709f), the handshakes (aebd390), `hand.nasm`'s layout (a517599), or nicewasm's loop closing (f678c7b).
- The entry for the start-up code of a monitor is undated (68f9b0b, 2026-10-20); "The assembler's checks" appears twice, once with "misspelt" (line 113); several entries are in the present tense.

### 9.3 TODO.md and the step numbers

- "Decided against" lacks the items of §2.2.
- 3209fbb inserted "6. Pauses" into MICROARCH.md §9, and TODO.md:14 ("Step 7"), hdl/README.md:417 and :426, hdl/Makefile:412, and hdl/test/programs.py:6 still use the old numbers.
- TODO.md:150-152 and :156 (§8.6, §6.5). The Vivado item of "Left from the fifth review": the root CLAUDE.md:87 has the path too, since ac01285.
- PR #36 is in no item; `origin/read-waits` promises an item that was never written.

### 9.4 README.md and CLAUDE.md

- README.md:22 says formal checks cover "four stages of the pipeline"; with WRITE's halt and pause it is five.
- README.md:80 "There are four tools. Three run on the host"; the table at lines 85-89 has five rows, `nicebuild` the fifth.
- The table says the emulator follows ISA.md and SYSTEM.md; DEBUG.md too, with `--link`.
- CLAUDE.md's Layout lacks doc/DEBUG.md and what wins over it, translator/nicebuild.py, runtime/libc, and hdl/CLAUDE.md; its command comments omit `link.py` and `bincheck` (emulator), `build.py` (translator), the C library tests (runtime), and Dhrystone (bench).
- No sentence anywhere says that ISA.md and SYSTEM.md win over DEBUG.md.
- REFERENCES.md's review list omits c-compiler-plan.md, whose "1.72 ceiling" (line 22) is 22eacce's figure, dated; it is about 1.88 now.

### 9.5 `check_refs.py` does not know DEBUG.md

`doc/check_refs.py:30`'s `DOCUMENTS` lacks DEBUG.md, so the sixty-odd citations of "DEBUG.md §n" in SYSTEM.md, the READMEs, TODO.md, and RELEASE_NOTES.md are not checked. The reader read them all: every section exists. **Fix:** one line.

**Resolved**: `DOCUMENTS` has DEBUG.md. A citation of a section that does not exist, tried once by hand in SYSTEM.md, fails `make -C doc test`, and every real citation passes.

### 9.6 Nits

HISTORY.md:113 "misspelt"; emulator/test/link.py:397 "cancelled"; an en dash in `link.zig:375`; `mchess.c` "colour" (third party); hdl/README.md:972 quotes `strings` at 3.1 and `bst` at 2.5 cycles per instruction at 1a41b0c, dated, where they are 2.40 and 1.98 now.

## 10. The release-script branch

`origin/release-script` is one commit, ba6a473 of 2026-10-23 on a2c82f1, 96 commits behind main. It adds `release/RELEASE.md`, a checklist of eight steps from the clean tree to the board; `release/release.py` (408 lines: `preflight`, `check`, `figures`, `ci`, `notes`, `tag`); `test.py`, a README, and a Makefile; a `release` job in ci.yml; and `make release-check` at the top. It rebases onto b2ac5a5 without a conflict, and its own `make test` and `make typecheck` pass after the rebase. Its `tag` makes an annotated tag with the draft notes as the message (`git tag -a`), refuses without a stamp of `check` and a green `ci`, and pushes only on request.

**Should it be merged?** Yes, rebased, after the changes below. §1.1 shows the gate is needed, the checklist is the right home for the figure refresh of §8 and the board step of §1.2, and the annotated tag answers the lightweight tags. As it stands it would block the wrong things:

- **A.** `check` (release.py:227-230) runs `make -C doc/intro pdf` and then requires a clean tree. The PDF holds its build date (doc/intro/Makefile:13-14), so the tree is never clean, and `check` can never pass. Drop the step; `make all` runs `pdfcheck`.
- **B.** `figures` (release.py:139) expects exactly four lines from `make cycles`; since d59bb12 it prints six, with `simple.bin`, so `figures` fails, and `check` calls it last, after the hours of `make core`. test.py:12 and :30 pin 1726106 instructions, three programs ago. Select the lines by program name.
- **C.** `CI_JOBS` (release.py:36) lacks `programs (pipeline)` and `programs (multicycle)`, the two slowest jobs and the ones still running on RC05, and lists `release`; `ci_status` takes `runs[0]` only (line 262) and needs the repository name when `origin` is not GitHub. Require every job of the run to have succeeded, with none pending.
- **D.** RELEASE.md:14 links `NiceMonMEGA65/blob/main/RELEASE.md`, which does not exist; the board's checklist is on its own unmerged `release-script` branch, at `release/RELEASE.md`.
- **E.** Neither RELEASE.md nor release.py knows RELEASE_NOTES.md, which CLAUDE.md now requires a section of for every tag: a step before `tag`, and `tag`'s message from that section. Step 8.3's text is garbled.
- **F.** The stamp is per commit, so a docs-only commit after `check` needs it again; `--cores pipeline` alone marks the slow checks done; `make slow` lacks `core-dhry`; the `vsg` version is not compared with ci.yml's pin; RELEASE.md step 6's job list and CLAUDE.md's Layout need the new files.

If a smaller change is wanted: merge RELEASE.md alone, with D, E, and the job list fixed, and a `ci` command that requires all jobs green. The checklist's steps 1 to 5 are what §8 and §9 of this review did by hand.

## What is correct

- `make test` passes at b2ac5a5 (5 min 31 s), `make -C hdl test` (808 pass), lint, every typecheck, `make -C doc test`, and 27 of 28 formal tasks locally, with the 28th green in CI. Nine of the eleven CI jobs are green on both RC05 runs; the two programs jobs were running.
- Every closed issue is done in substance, and every commit claim the readers tested holds: the handshakes kept every cycle, #51 and #54 changed no behavior, the pause and the step work as DEBUG.md says on both cores, and the ports of the two cores are identical but for `stats_o`.
- The emulator: `time.expected`, `perf.expected`, `trapsym`, and `merge` recomputed by hand; the first-vector rule; the reserved words as memory; every option, exit status, and message of its README; the trace format against `trace_pkg.vhd`.
- The debug link: every other rule of DEBUG.md in `link.zig` and `debug_link.vhd`; 26 checksums by hand; `tb_link` on both cores; the halt codes; the proofs that neither core holds a bus cycle open while paused or halted and that each pause is followed by one step.
- The runtime: headers against sources against the README's lists; the float library at 7079 words; the format of `assert`, `exit`, `rand`'s sequence, the `FILE` functions, `strcspn`; the trap names 1 to 7 the same in three places; every test file run; every other `.expected` checked by hand; the C library's `.wasm` files, `bench.wasm`, and `dhry.wasm` byte for byte on rebuild.
- The translator: an opcode scan of `0x00` to `0xFF` and `0xFC` 0 to 19 rejects exactly the README's unsupported list; the errors, exit statuses, and the memory, table, and import checks of af1e2fd as documented; WASM.md:50 and README.md:314 agree in effect; the trap tables of WASM.md, `main.zig`, and `trapmsg.nasm` agree for 1 to 7.
- The cores: the §3 interface table, §6.1, the depth claims of §9, ASSUMPTIONS.md items 15 and 17 to 19, and the proofs of FETCH, DECODE, PREPARE, DBUS, and WRITE as described; the multi-cycle core's 15 states; the retire rows of both diagrams.
- The figures of §8.1. The ranges and dates of RELEASE_NOTES.md, the RC01 inventory, the slides and their example programs, the 23 checksums of DEBUG.md's examples, every `make` line of CLAUDE.md, the CI sentence of README.md, no TODO or FIXME in the code, and the fifth review's fixes but for the `.wasm` bits. The quick start works on a fresh clone, 503 files are tracked, and none is stray.

The readers' programs are worth keeping as tests: the random-program template with backward conditional jumps and the six predictor programs (§7.2), the loop-shape harness and the opcode scan of the translator (§6.2), the second testbench case of `debug_link` (§3.1), the microsecond testbench at three frequencies (§7.3), and the per-commit trace comparison of the pipelined core (§7.1).
