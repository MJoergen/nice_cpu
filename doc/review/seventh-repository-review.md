# Seventh review of the repository, at commit bebbdc0

Reviewed on 2026-10-28: the 18 commits since the tag `V1.0` (2026-10-27), at commit bebbdc0 ("release: CI on Node 24 actions and Ubuntu 24.04"), before the release `V1.1`. The sixth review looked at `RC05`. This one asked what the commits since `V1.0` introduced and whether anything in them blocks the tag: debug link version 5 (#79, #81), the pause at a waiting console read in the emulator (#56), `nicedis` (#80), `errno` in the C library, nvc as the simulator of the long runs (#77) and the new shape of `make slow`, the proofs of PREPARE's assumptions about WRITE and DBUS (#59), the CI toolchain, and the move of TODO.md's items to the issues.

**How it was checked.** Four readers worked in parallel and changed nothing: one each for the cores and the formal proofs, the emulator and the debug link, the disassembler, and the runtime and the translator. I read the release checklist, `release.py`, the CI workflow, the Makefiles, and the documents myself, and reproduced every finding below that names a file and a line. The gates ran on the unchanged tree, which was clean afterwards: `make test` (973 PASS lines), `make slow` on both cores in nvc (5 min 29 s, beside the proofs), the proofs of `pipe_write`, `pipe_dbus`, `pipe_prepare`, and `debug_link` (prove, prove_held, and cover) and the 12-cycle bounded check of the whole pipelined core (160 s), `make -C hdl lint`, every `make typecheck`, and `make wasmcheck` (41 files). The readers also ran `make -C assembler test`, `make -C emulator test`, and the typechecks of their directories. The versions that `ci.yml` pins were checked against GitHub: `actions/checkout`, `actions/setup-python`, and `actions/upload-artifact` at `v7`, the OSS CAD Suite build of 2026-09-30, and nvc 1.23.0 with the digest the workflow checks.

## Summary

**One behavior defect, in the emulator's debug link, and none in the cores, the proofs, the disassembler, or the C library.** A pause request that undoes the step of a console read that waits does not put back the input buffer, so an instruction that reads the console twice loses its first byte (§2.1). The common case, one read per instruction, is right. The change to `pipe_prepare.vhd` and `pipeline.vhd` is formal code and comments only, so the rule of CLAUDE.md about timing figures was rightly not triggered (§3.3). `debug_link.vhd`, `link.zig`, DEBUG.md, and the tests agree on version 5 (§2.3). `nicedis` reassembles every `.bin` file in the tree to the same words, with and without symbols, and does not crash on random words (§4). `strtol` and `strtoul` follow the C standard, and every new line of `stdlib.expected` was derived by hand (§5).

**Two lines stand between the tree and the tag.** DEBUG.md's table of versions says version 5 is "Not yet tagged.", no step of RELEASE.md changes it, and `release.py tag` accepts only RELEASE_NOTES.md and TODO.md after the stamp (§1.1). RELEASE_NOTES.md has no section for `V1.1` yet, which is expected at this point; §1.2 lists what the section must say beyond the draft of `release.py notes`.

**The rest is small**: a version in hdl/README.md (§6.1), a download that CI does not check (§6.2), a reset guard that an assumption lacks (§3.1), three mismatches between `nicedis` and its README or `niceemu` (§4.1, §4.2), a scan that is quadratic in the symbols (§4.3), and an invalid base that runs past a string in the C library (§5.1).

## 1. The release

### 1.1 DEBUG.md's version table is not on the checklist

[DEBUG.md](../DEBUG.md) §9's table says of version 5: "Not yet tagged." At `V1.0` the same cell for version 4 was filled in by hand. Nothing in [RELEASE.md](../../release/RELEASE.md) says to do it, and step 8.3 lets `tag` accept only commits that change RELEASE_NOTES.md and TODO.md after the stamp, so a change to DEBUG.md after `release.py check` makes the stamp stale. **Fix:** write `V1.1` in the cell before `release.py check`, and add the cell to step 2 of RELEASE.md, next to the sentence about a new debug link version.

**Resolved** in part: 4d7607a writes `V1.1` in the cell. RELEASE.md does not yet name the cell.

### 1.2 What the `V1.1` section must say

`release.py notes` drafts the Zig version, the benchmark estimate (2356816 cycles, unchanged), the `hdl/src` files that changed, and the commit subjects. By hand it needs:

- Debug link version 5 is a new minor (RELEASE.md step 2): a clear ends the halt and the stop, so bit 1 of the control register, the halt reason, and the stop register read 0 after it. A host of version 4 keeps working by the rules of DEBUG.md §9. NiceMonMEGA65's host sees the new `b05` notice.
- No port of either core, of `wb_dmux`, or of a device changed, and the address map of SYSTEM.md is as at `V1.0`. The changes to `pipe_prepare.vhd` and `pipeline.vhd` are inside `G_FORMAL` and in comments. A system built for `V1.0` needs no change in its VHDL.
- `niceemu --link`: a pause request now ends a console read that waits, and a step at such a read pauses again (#56), with the limit of §2.1 if it is not fixed first.
- `nicedis`, the disassembler, under Assembler.
- `errno`, set by `strtol` and `strtoul`, under Runtime and C library; the three test `.wasm` files that link them changed with it.
- For a user of the repository: nvc runs the long simulations (`SIM=nvc`), `make slow` runs the benchmark, Dhrystone, and the stride sweeps on both cores at once and leaves the programs to CI, `make strides` is new, and `make sweep` is run only after a change to the interrupt path.

Issue #79, the version 5 change, is closed without the `V1.1` milestone, which has 8 closed issues and no open one. RELEASE.md's list under "Interface changes" (step 7) names the ports, the address map, the output ports, and the clock assumptions, but not the debug link's version, which an integrator's host sees. **Fix:** add the milestone to #79; add "the version and the rules of the debug link (DEBUG.md §9)" to the list.

**Resolved** in part: dff63e9 adds the `V1.1` section, and it says each of the above: the new minor, no interface change, the pause at a waiting read, `nicedis`, `errno`, nvc, `make slow`, `make strides`, and `make sweep`. It says the pause takes nothing, which §2.1 qualifies until that is fixed. The milestone of #79 and the list of step 7 are as before.

## 2. The emulator and the debug link

### 2.1 Undoing a step at a waiting read loses a byte that the same instruction took

DEBUG.md §7 says a pause request undoes the step of a console read that waits: "The processor pauses before it, with R15 the address of the read, and no byte taken", and "a go on runs the read again". `emulator/src/cpu.zig`'s `Saved` (line 562) keeps the registers, the interrupt state, the read counter, the counters, and the timer, and its comment says "A step writes no memory and no device before its reads". A read of the console is a read of a device, and the link's input buffer (`input_head`, `input_len`, `overflow_sent` in `link.zig`) is not in `Saved`. `source()` evaluates s0 and then s1, so `ADD R3, @CONSOLE, @CONSOLE` reads the console twice in one step. With one byte in the buffer the first read takes it, the second waits, and the pause request in `streamInput` (link.zig:497) sets `undo`. `putBack` (main.zig:603) restores the registers, and the byte is gone.

Reproduced over the link with that instruction followed by `HALT`: after `a` and a pause, `p` came, R15 read the address of the `ADD`, and the free space (`0xFFFFFFF3`) read 2048, not 2047. After a go on, the program waited for two new bytes. The bytes are still in the ring buffer, because `input_head` only advances. **Fix:** save the three fields of the link with the `Saved` snapshot, and put them back on undo; or make the undo apply only when the wait is the first console read of the step; or state the limit in DEBUG.md §7 and emulator/README.md. Any of the three gets a test in `emulator/test/link.py`.

**Resolved**: the link counts the bytes that a step takes, and an undo puts them back in the ring before `input_head`. The buffer is empty at an undo, as the step waited, so the bytes are still there. Saving the three fields would not do: a byte that arrives during the step and is taken by its first read would be lost. `link.py`'s `test_step` steps `ADD R3, @CONSOLE, @CONSOLE` with one byte waiting, and then with a second; DEBUG.md §7 and emulator/README.md say that no earlier read of the instruction keeps its byte.

### 2.2 Tests

The tests of a pause during a waiting read in `link.py` sleep 0.2 s so that the read waits before the pause is sent. A pause that arrived first would take effect between steps and give the same `p`, R15, and counters, so the undo path is covered only while the timing holds; the step at a waiting read is deterministic and does cover it. `test_old_host` checks the version rules through the `b` payload, the version register, and the major and minor, but nothing reads `0xFFFFFFF7` or the high bits of `0xFFFFFFF2`, which DEBUG.md §9 says read 0; the code does so. No test covers §2.1. **Fix:** a test for §2.1 with the fix, and one line each for the two registers.

**Resolved**: the test of §2.1 steps at the second read, which is deterministic, and `test_old_host` reads `0xFFFFFFF2` as 5 and `0xFFFFFFF7` as 0. The tests that sleep stay; the step test covers the undo without them.

### 2.3 What agrees

`link.zig` has `version = 5`, sends `b05#C7`, and reads 5 at `0xFFFFFFF2`; `debug_link.vhd` has `C_VERSION` 5 and the same notice; the checksum is right. On a write with bit 2, the emulator sets `cleared`, clears the stop register, masks bit 1 and the reason at a read, keeps `haltReason()` for the `h` that has not gone out, and resets `cleared` at a start. The VHDL does the same with `cleared_r`, `stop_r`, `halted_r`, and `reason_r`, and the same-cycle order is right: the clear's `stop_r` assignment comes after the pause's in the same process, so it wins. The two differ where DEBUG.md allows it: the VHDL's clear takes time and ignores control writes while it runs, the emulator's is instant, and the emulator leaves R0 to R15 alone where the spec says undefined. The pause at a waiting read is single-threaded, polls with a 100 ms timeout, increments no step counter when it undoes, writes no trace line, and neither loses nor duplicates an `--irq` request. The README's sentences on how often the link is served and on the undo match `main.zig`. The hand-derived numbers of `link.py` (6 steps per echo pass, 18 after three, 2045 free with three bytes waiting, control `0x9` after a clear, `[0xA, reason]` after a halt) are right.

## 3. The cores and the formal proofs

### 3.1 WRITE assumes what PREPARE asserts, without the reset guard

`hdl/formal/formal_pipe_write.vhd:143` assumes `always valid_i -> decoded_ok(uop)`, and the comment names PREPARE's `f_out_decoded`. `hdl/src/pipe_prepare.vhd:574` asserts it under `rst_i = '0'`. So in a reset cycle WRITE's proof assumes more than PREPARE proves. WRITE ignores its input in reset, so nothing follows from it, but the commit's claim that every assumption of a stage proof is proven of the stage it names has this one-cycle gap. **Fix:** guard the assumption with `rst_i = '0'` too.

### 3.2 No property states the behavior of #79

`formal_debug_link.vhd` gained only the invariant `i_cleared` (`cleared_r = '1' -> hold_r = '1'`). Nothing in the proof says that bit 1, the reason, and the stop register read 0 after a clear; `tb_debug_link` covers it, with a clear after a halt, a clear before a late `h`, the stop register after a clear at a breakpoint, and a version-1 host that loads, starts, halts, and restarts. The "clear before the h" case uses `expect_either`, so the order of `k` and `h` is not pinned, as DEBUG.md allows. Not covered: a clear while paused, not at a breakpoint, and a clear in the cycle of a halt; by the code, `halted_r` is masked by `cleared_r` in both. **Fix:** an assertion or a cover for the three registers after a clear, and the two testbench cases, if cheap.

### 3.3 What agrees

Every hunk of `pipe_prepare.vhd` is a comment or inside `gen_formal : if G_FORMAL generate`, and the `pipeline.vhd` hunk is a comment, so no path of `timing_groups.rpt` changes and the commit body rightly has no timing figures. The weakened assumptions (`f_takes` only in `RUN_ST` on a valid micro-operation, `f_sr_stable` and `f_cond_stable` while WRITE holds one that may change them, `f_tags`, and the `f_inv_*` on `f_uop`) match ASSUMPTIONS.md item 15, MICROARCH.md, and hdl/README.md. The proofs of WRITE and DBUS use the same model registers as PREPARE's, compared line by line: `f_uop`, `f_sr_free`, `f_cond_free`, `f_cond_set`, `f_cond_val`, `f_mode_free`, and the `f_tag` formula. Their new properties are assertions; the only new assumption is `f_decoded` of §3.1. The covers of `pipe_write` reach `c_int_keep`. The `.sby` changes (`techmap; setundef -anyseq`, depth 12) match the text. `pipe_write`'s `f_exec` lists the two-cycle modes by constant, so a new two-cycle micro-operation would fail the proof rather than be caught by construction; that is acceptable. The 22 lint warnings are the same lines as at `V1.0`, shifted.

## 4. The disassembler

### 4.1 A blank line in a symbols file is an error here and not in `niceemu`

`nicedis.py`'s `read_symbols` matches every line against `SYM_LINE`, so a file with a blank line ends with "expected an 8-digit hex address, a space, and a name". `niceemu --symbols` (`main.zig:104`, `loadSymbols`) trims each line, skips blank ones, and takes short hex. The README says it reads "the symbols files of `niceasm --symbols` and `nicebuild.py --symbols`", which have no blank lines, but a hand-edited file that `niceemu` takes is refused. The reverse holds for a name with a space, which `nicedis` takes and `niceemu` refuses; that is harmless. **Fix:** skip blank lines, and either accept what `niceemu` accepts or say in the README that the address is 8 digits and a line is never blank.

### 4.2 `--start` and `--end` are not "decimal, or hex with `0x`"

assembler/README.md:67 says so; `address()` calls `int(text, 0)`, so `--start 010` is refused ("bad address '010'") where `niceasm` reads `010` as 10, and `--start 0b1` is accepted. A start beyond the file, or beyond `--end`, prints nothing and exits 0. **Fix:** parse `0x` and plain decimal explicitly, refuse a start above `0xFFFFFFFF`, and either refuse an empty range or say that it prints nothing.

### 4.3 The listing is quadratic in the symbols

`listing()` finds the next label with `next((s for s in starts if s > addr), end)` for every instruction, a scan of the sorted list. 60000 words with 8000 symbols took 6.0 s. **Fix:** `bisect.bisect_right(starts, addr)`.

### 4.4 Smaller

- `assembler/test/dis.py` finds the binaries with `git ls-files "*.bin"`, so it raises `CalledProcessError` outside a checkout and covers the 47 tracked files, not the build outputs. The reader ran the 112 on disk too; see below.
- The symbols file is read as Latin-1 and names are printed through the locale, so a non-ASCII name comes out re-encoded. It can only reach a comment, as such a name is never a valid label.
- The README does not list the exact error texts; it gives the `file:line: error:` form and the exit statuses 0, 1, and 2, which match.

## 5. The runtime and the C library

### 5.1 A base above 36 runs past the string

`runtime/libc/src/stdlib.c`'s `digit()` returns 36 for a character that is not a digit or a letter, and `parse()` loops while `digit(*p) < (unsigned)base`. For a base above 36, or a negative one cast to unsigned, the terminating NUL counts as a digit, and the loop reads on past the string. C leaves an invalid base undefined, and the README promises only `ERANGE`, so this is older than the diff and breaks no promise; but it is a crash for one comparison. Base 1 is harmless and takes only zeros. **Fix:** in `parse`, treat `base < 0`, `base == 1`, or `base > 36` as no conversion, with `*end = s`; file it as an issue if not done now, as `errno` makes `EINVAL` the natural next step.

### 5.2 What agrees

`strtol` returns `LONG_MAX` or `LONG_MIN` with `ERANGE` on overflow and takes -2147483648 without one; `strtoul` saturates at `ULONG_MAX` with `ERANGE`, including "-4294967296", and negates a value that fits, so "-4294967295" gives 1; the overflow bound `v > (ULONG_MAX - d) / base` is exact, and digits are consumed after it so `endptr` is right; `0x` is taken only with a hex digit after it; `errno` is never set to zero, is one `int` in `stdlib.c`, and is written by nothing else in the library. All 11 new lines of `stdlib.expected` were derived from `stdlib.c` by hand and match. `limits.wasm`, `mchess.wasm`, and `numbers.wasm` changed because they link `strtol` or `strtoul`; `make wasmcheck` rebuilds all 41 files to the same bytes, with the usual note on the four Rust files that follow the rustc version. The `chmod -x` of the Zig and Rust `.wasm` files in `runtime/Makefile` and `translator/Makefile` is right, `doc/Makefile` rejects an executable `.wasm`, and every tracked `.wasm` is mode 100644; `runtime/float.wasm` is rebuilt only by `make -C runtime float`, so no check compares it, which is as before. WASM.md's listing of a trap handler is in the column layout and matches `runtime/test/trapvec.nasm` and what `nicewasm.py` emits for a trap.

## 6. CI, the Makefiles, and the documents

### 6.1 hdl/README.md names an nvc version CI does not use

hdl/README.md:144 says nvc is "tested with nvc 1.20"; `ci.yml`'s programs jobs install 1.23.0 from its release package. **Fix:** "tested with nvc 1.20 locally and 1.23.0 in CI", or move the local install to 1.23.0.

### 6.2 The OSS CAD Suite download is not checked

`ci.yml`'s formal job pipes `curl` of the 2026-09-30 tarball into `tar` with no digest, where the programs jobs check the nvc package with `sha256sum -c`. The suite puts a whole toolchain on `PATH`. **Fix:** the same check, with the digest of the release asset.

### 6.3 What agrees

The top-level `make slow` builds the emulator, analyzes the VHDL for `SIM`, assembles the five programs, and then runs the eight jobs with `PREBUILT=1`; every target and variable it names exists (`emulator build`, `hdl analyze`, `strides`, `SWEEP_JOBS`, `bench core CORE_PROGRAMS`, `core-dhry`). `SWEEP_JOBS` is (JOBS - 3 per core) / cores, at least 1. `hdl/sim.mk`'s nvc line has the options in the right order, both simulators use femtoseconds, and `core_runs.py` takes the same exit codes from both. `bench/Makefile` runs each program in a directory of its own under `hdl/build/bench_run/`, so the runs do not race on GHDL's executables. `release.py check` runs `make timing` on a thread beside `make formal` and shows the result after; a failure of `make formal` waits for Vivado to finish before it is raised, which is slow but right. `release.py ci` matches a `programs (core)` job by prefix, so the end of the shards changes nothing there, and `release/test.py` already used the unsharded names. The `--shard I/N` arithmetic and the strides of `irq_sweep.py` are right. The sentences of CLAUDE.md, README.md, hdl/README.md, bench/README.md, and RELEASE.md about nvc, `make slow`, `make strides`, and `make sweep` agree with the Makefiles. The commit subjects and bodies meet 50/72. TODO.md's claim that no code has a TODO or FIXME holds. The `V1.1` milestone has no open issue. REFERENCES.md lists decisions.md.

### 6.4 Nits

- README.md's table says RELEASE_NOTES.md lists "the changes in each release candidate"; since `V1.0` they are releases.
- bench/README.md says `make core CORE=multicycle` takes about 57 minutes, and the comment in bench/Makefile says about 38; neither changed in this diff.
- hdl/README.md:148 says `make test` took 15 minutes in nvc and 5 in GHDL; the sentence is right, and worth keeping, as the number surprises.
- HISTORY.md has entries for the proofs, CI's formal tools, TODO.md, the clear, and the pause, but none for what `make slow` used to be (the programs and `make sweep` in GHDL, one core at a time) or for GHDL as the only simulator. **Fix:** one entry.

## What is correct

- `make test`, `make slow` on both cores, the nine formal tasks, lint, every typecheck, `make wasmcheck`, and `make -C doc test` pass at bebbdc0, and the tree is clean after them. The CI pins exist.
- The cores: `pipe_prepare.vhd` and `pipeline.vhd` changed only in formal code and comments; the proofs of PREPARE, WRITE, and DBUS share their model registers; the assumptions match ASSUMPTIONS.md item 15; the debug link's VHDL does what DEBUG.md says for a clear in every state the testbench reaches.
- The debug link in three forms: version 5, `b05#C7`, the clear-ends-halt rule, the stop register, and the version rules of §9 agree in DEBUG.md, `link.zig`, `debug_link.vhd`, `tb_debug_link`, `tb_link`, and `link.py`.
- The emulator's pause at a waiting read: no race, no hang, no lost interrupt request, no trace line, no step counted, and nothing changed without `--link`.
- `nicedis`: every opcode, condition, register, mode, constant order, and reserved encoding of ISA.md §4 and §10 decodes as `niceasm` encodes it; all 112 `.bin` files on disk, 47 tracked, round-trip with and without symbols; 55 random streams, 15 of 3000 words with wraps and gaps and 40 with hostile names and random ranges, gave no exception and reassembled to the same words; the `disedge` words at 0x0 to 0x1c and the `.EQU` lines, and `count.lst`, were decoded by hand.
- The C library: `strtol`, `strtoul`, and `errno` as the standard says, and `stdlib.expected` by hand.
- The release script and the Makefiles: every target, variable, and job name that the new `make slow`, `release.py check`, `release.py ci`, and `ci.yml` depend on exists and agrees with its README.
