# Fifth review of the repository, at commit 9d8f13d

Reviewed on 2026-10-22: the state of the repository at commit 9d8f13d ("ISA: state the memory model"), tagged `RW01`, as a release candidate. The four earlier reviews asked whether the parts fit and what the tests do not reach. This one asked what a release is missing: what a reader on a fresh machine hits first, what an integrator of the core has to know and is not told, what the documents say that is no longer true, and what the tools do that no document states.

**How it was checked.** Seven readers worked in parallel: one each for ISA.md and SYSTEM.md against the emulator, the assembler, the emulator's interface, the runtime and the C library, the translator, the cores, and the documents as a set. Each read its code against its documents rule by rule, and ran the tools on small inputs where it suspected a gap, but ran no test suite: the tests pass at this commit and the benchmark figures are current, which this review takes as given. The readers reported findings with file and line and changed nothing. I checked the release hygiene of the repository myself, reproduced every behavior finding below (§3.2, §4.1, §6.1, §6.2), and re-read the text of every document finding of §1, §2, §5.1, §7.1, §7.4, and §8. Nothing is fixed; each finding says what the fix is.

## Summary

**No behavior bug in the cores, in the emulator's execution, in the assembler's output, in the runtime, or in translated code.** The readers traced every rule of ISA.md §1 to §8 and of SYSTEM.md through `cpu.zig`, recomputed encodings by hand, ran hand-built f32 modules through the whole pipeline against a Python reference, and synthesized both cores with GHDL, and found nothing wrong. Three edges remain. The emulator loses its console output on Ctrl-C (§4.1). The translator prints a Python traceback for a name section that overruns the file, and for an output file it cannot write (§6.1, §6.2); the assembler had the second and was fixed after the fourth review.

**What a release is missing is around the code, not in it.** There is no license (§1.1). CI does not run the document checks, though README.md says it runs every test (§1.2). No document names the Python, make, or platform the tests need, and the hdl scripts need Python 3.10 where the tools need 3.7 (§1.3, §1.4). The quick start runs a binary that a fresh clone does not have (§1.5). The rules a system must follow to drive the pipelined core's buses are stated in the formal checker and in a file header, not in MICROARCH.md §8 or hdl/README.md, where an integrator looks (§7.1).

**The documents drifted in small ways while the pipeline changed.** The slides still promise a UART and a first core (§8.1). MICROARCH.md keeps a hazard figure from before the store register (§8.2). HISTORY.md has no entry for the default core changing (§8.3). The runtime README doubles the size of the float library (§5.1). SYSTEM.md cites an ISA.md section for a rule it does not contain (§2.1). Each is a line to fix.

## 1. Release hygiene

### 1.1 No license

No file in the repository, and no sentence in any README, says under what terms the code and the documents may be used. The 2004 `.bin` files are `NICE.pm` output, and REFERENCES.md names their source but not their terms. **Fix:** a `LICENSE` file, a line in README.md, and a sentence in REFERENCES.md on the 2004 files.

### 1.2 CI does not run the document checks

README.md:169 says "GitHub Actions runs every `make test` and `make typecheck` on each push." `.github/workflows/ci.yml` has no job that runs `make -C doc test` or `make -C doc typecheck`, so `check_refs.py` runs only by hand. The sentence also understates CI, which runs `make programs` on both cores, `make lint`, `make formal`, and `make pdfcheck` too. **Fix:** a `doc` job, and the sentence.

### 1.3 No minimum Python version

README.md:44 says "You need Python 3." `niceasm.py`, `nicewasm.py`, and their test scripts need 3.7 (`from __future__ import annotations`, dataclasses, `subprocess.run(capture_output=)`). The hdl test scripts need 3.10: `hdl/test/core_runs.py:91`, `programs.py:30`, and `pcfx_prog.py:214` write `str | None` in function signatures without the `__future__` import, so Python 3.9 raises `TypeError` at import, and `make -C hdl test` fails. CI runs "3.x" and cannot see it. **Fix:** say 3.10 in README.md, or add the import to the hdl scripts and say 3.7.

### 1.4 The top-level `make test` needs GNU make 4 and coreutils

Makefile:38 passes `-O`, which GNU make has had since 4.0, and Makefile:34 and hdl/Makefile:19 run `nproc`. macOS ships make 3.81 and no `nproc`. README.md:168 lists the tools the tests use as `make`, `cat`, `cmp`, `diff`, `sed`, `grep`, and `cut`. **Fix:** say "GNU make 4 and coreutils, as on Linux", or drop `-O` and `nproc`.

### 1.5 The quick start runs a binary that does not exist

README.md:70–71 run `assembler/niceasm.py` and then `emulator/zig-out/bin/niceemu`. On a fresh clone nothing has built the emulator; the text above says only that the tests build it. **Fix:** `make -C emulator build` before the two lines.

### 1.6 Smaller

- `make typecheck` covers `niceasm.py`, `nicewasm.py`, the bench and doc scripts, and the assembler's and translator's test scripts. It does not cover the eleven `hdl/test/*.py`, `emulator/test/errors.py`, or `runtime/libc/test/fuzz_printf.py`. All thirteen pass `mypy --strict` today; a `typecheck` target in `hdl/` and `emulator/` would keep it so.
- hdl/README.md says `pip install vsg`; ci.yml pins `vsg==3.35.0`.
- Every checked-in `.wasm` file has the executable bit set. Nothing runs them.
- hdl/CLAUDE.md gives one machine's Vivado path, and hdl/Makefile:415 has the same path as the default of `VIVADO`.

## 2. The specification

### 2.1 SYSTEM.md cites a rule that ISA.md does not contain

SYSTEM.md:67: "Each 64-bit value takes two words, low word first, as in ISA §9.3." ISA.md §9.3 is two links, to ABI.md and WASM.md, and says nothing about word order. `check_refs.py` passes it because the section exists. The emulator does put the low word first (`Mpu.write` in `cpu.zig`). **Fix:** state the order in SYSTEM.md §2, and cite ABI.md if it states it.

### 2.2 Rules the tools decide and ISA.md does not state

- **Control words take no constant words.** ISA.md §2.3 says every instruction is followed by zero to three constant words. Only §5 step 2 says control instructions take none, and §3 says a skipped instruction "still consumes its constant words" without excepting them. The emulator and the probe `skipconst` have it right. A sentence in §2.3.
- **A single number of 2³² or more is an error.** ISA.md §10.2 says the value of a constant wraps modulo 2³². `niceasm.py:130` rejects `4294967296` and `0x100000000` with "number too large", and accepts `0xFFFFFFFF+1`. Either wrap, or say in §10.2 that each number must be below 2³².
- **Symbol syntax.** `IDENT` at `niceasm.py:53` is an ASCII letter or `_`, then ASCII letters, digits, `_`, and `.`. Neither ISA.md §10.1 nor the README says so: `a.b` is a label, and `é` is "bad symbol name".
- **Which vector a merge keeps.** ISA.md §7.1 says requests of the same kind "may merge". The emulator keeps the older vector when the timer's request meets a pending one (`cpu.zig:501`) and the newer one for `--irq` and `--nmi` (`requestIrq`, `requestNmi`). Say "unspecified", or pick one.
- **The read counter has no reset value** in SYSTEM.md §1, and `Cpu.reset()` does not clear it. It matters only if reset were called on a running processor, which it is not.
- ISA.md §10.1 says a label cannot be "a register name"; assembler/README.md:55 says it cannot look like one, so `R16` is rejected too. Put the stricter rule in ISA.md.
- ISA.md §10.1 says a comment starts with `;` or `*`; the assembler takes `*` as a comment only at the start of a word, as the README says. A clause in §10.1.

### 2.3 Nits

ISA.md:364 lacks the Oxford comma before "and a software interrupt". The console paragraph of SYSTEM.md §1 says a read with no byte waiting returns 0, and then that the emulator never returns 0; "a UART returns 0 when no byte waits; the emulator and the simulation wait for one" says it once.

## 3. The assembler

No bug. Probes of `.ORG` backwards and overlapping, a duplicate label, wrap in `.DAT` and `.ORG -1`, words wrapping past `0xFFFFFFFF`, `.BLK 0`, a BOM, CRLF, a lone `\r`, an empty file, and a file of comments all matched the code, the README, and ISA.md. Twelve words of `encoding.nasm`, the hardest ones, were recomputed by hand from ISA.md §2 and §4 and match.

### 3.1 Behavior no document states

- `.BLK n` writes n lines with no limit: `.BLK 0xFFFFFFFF` writes about 38 GB. The README should send large reservations to `.RES`.
- `check_blocks` (`niceasm.py:342`) rejects any overlap of a `.BLK` or `.RES` with anything, `.RES` against `.RES` included. The README says only "Writing two words to the same address is an error."
- The `.bin` is sorted by address, so with a wrap the words at 0 come before those at `0xFFFFFFFE`. `wrap.bin` pins it; the README does not say it.
- `.ASCII_B ''` emits nothing and `.ASCII_L ''` one 0 word. A failed run leaves an existing output file untouched. Warnings print before errors. `-o -` writes a file named `-`. `str.isspace()` at line 481 makes form feed and Latin-1 `\xa0` separators.

### 3.2 Nits

`niceasm.py:421` says "expected [M], [C] or [CM]" and line 561 "condition, mnemonic or directive", both without the Oxford comma; `errors.py:86` pins the first. assembler/README.md:49 has "misspelt". A 50 KB line of `[` takes 17 s in the regex at line 313. `open(out, "w")` at line 666 has no `newline=""`, so on Windows the `.bin` would get CRLF line ends.

## 4. The emulator

### 4.1 Console output is lost on Ctrl-C

`main.zig:93–95` buffers stdout in 64 KiB and flushes it when the buffer fills, before a console read (`cpu.zig:428`), and at exit. There is no signal handler. A program that writes `A` to the console and then loops forever, run under `timeout -s INT 1`, writes 0 bytes. Under the default step limit the `A` appears after about 3.5 s, with the "Stopped" line. **Fix:** flush after each console write when stdout is a terminal, or flush from a SIGINT and SIGTERM handler. The README's "Before it reads, the emulator flushes its output" is true; it should say that it is the only flush.

### 4.2 The README against the code

- `--` is not supported (`main.zig:196`, "unknown option '--'"), so a program path that starts with `-` cannot be given. An empty argument is taken as no program.
- Exit status 1 is also used for "cannot write the output" (`main.zig:121`) and for running out of memory; the README names only "a usage, file, or memory error". It does not say that diagnostics go to stderr and `-h` to stdout.
- The loader accepts CRLF, tabs, trailing blanks, a missing final newline, upper-case hex, and fewer than 8 digits, and rejects a BOM. The README says only that it is more lenient than ISA.md §10.4.
- The dump format is `ADDR:` and then eight ` %08x` words (`main.zig:339`); the README says each line starts with the address.
- A read error on the input is reported as end of input (`cpu.zig:429` catches every error). Memory is 4096-word pages with no bound, so a program that touches one word per page can take 16 GiB before `OutOfMemory`.
- Nothing but CI's `make bins && git diff` checks that `test/*.bin` match their `.nasm`. The reader reassembled all 35 and found none stale.

## 5. The runtime library and the C library

### 5.1 The size of the float library

runtime/README.md:156: "Assembled, `float.nasm` is about 14600 words." It is 7083 words of code, as bench/README.md:346, translator/README.md:157, and HISTORY.md say, and 7339 with its 256-word `WL.float.memory`; the reader translated and assembled it. **Fix:** "about 7100 words, 7340 with its stack."

### 5.2 Names and claims

- runtime/README.md:73–76 lists the labels no other file may define: the `__mpu.` names, `__udivmod`, and `__udivmod64`. `lib.nasm:100–105` also defines the `.EQU`s `__nice.console`, `__nice.cycle_lo`, `__nice.cycle_hi`, `__nice.instr_lo`, `__nice.instr_hi`, and `__nice.screen`, which share the one namespace.
- `runtime/libc/include/nice.h:6–7` says the routines have "the same names and meanings as in the runtime library". `nice_print` writes the bytes of a C string, where `_nice_print` writes one character per word; README.md:180–181 says so, ABI.md:133 and the header do not.
- The README's "No ..." list for the C library names `FILE`, `errno`, and `exit`. It also has no `strtoll`, `strtoull`, `atoll`, `rand`, `qsort`, `strspn`, `strcspn`, `strdup`, or `isblank`, though `printf` and `scanf` take `%lld`.
- The recipe at runtime/README.md:78–83 for a Zig program with `libc.a` says the link "keeps only the functions the program uses". The reader built one: the image held the whole library, 81 KB. The claim holds for clang with `wasm-ld`.
- Untested edges, all conforming: `%n` and `%Lf` print as they stand and consume no argument (`printf.c:229–235`); `%.3s` of NULL prints `(nul`; `strtol` does not reject a base of 1 or above 36 (`stdlib.c:157–186`); `scanf` of `"0x"` with no digit after it consumes the `x`.

## 6. The translator

### 6.1 A name section that overruns the file gives a traceback

`parse_custom` (`nicewasm.py:758–773`) builds a `Reader` for each subsection with `s.pos + size` as its end, and never clamps it to the section or the file. A subsection whose declared size runs past the end makes `Reader.byte` (line 415) raise `IndexError`: a traceback and exit 1, where the README says a cut-short name section is ignored and the comment at line 760 says "errors are ignored". Reproduced with a name section whose subsection 1 declares a size of 2³² − 1. `test/run.py:3180` cuts inside a name, within the subsection's bounds. **Fix:** `min(s.pos + size, s.end)`, or catch `IndexError` with `WasmError`, and an `errors.py` case.

### 6.2 An output file that cannot be written gives a traceback

`nicewasm.py:5119` opens the output outside any `try`: `-o /nonexistent/x.nasm` gives `FileNotFoundError` with a traceback and exit 1. The assembler had the same and was fixed after the fourth review ([fourth-repository-review.md](fourth-repository-review.md) §1.2). **Fix:** the same `except OSError`, and an `errors.py` case.

### 6.3 Invalid modules accepted

- `--library-memory -4` is accepted (`nicewasm.py:2719–2728`), and the output says "the first -4 bytes".
- The memory section checks neither min ≤ max nor min ≤ 65536: `memory(65537)` gives `.RES 1073758208`, and a load at `0xFFFFFFF0` has no bounds check. The table section does not check min ≤ max.
- `env.foo` imported twice with different types is accepted; both become `_foo`.

Compilers emit none of these. Each is a few lines and an `errors.py` case. Of 37 hand-made malformed modules, every other one gave a clean `file:0xOFF: error:` message.

### 6.4 The README

- "Exports" says a name that is not a C identifier gets no label. It omits that in a program a name starting with `_` gets none, which the code (line 2786) and WASM.md say.
- `ref.null` and `ref.is_null` in a body give "not supported yet", but are in neither the README's list nor TODO.md's.
- Line 35 gives exit status 1 after an error; argparse errors exit 2.
- Line 172 says a program with floats is joined with `runtime/float.nasm`, which is generated and gitignored. Say `make -C runtime float.nasm`.
- Nits: the "Instructions" bullet carries three sentences about traps; `test/errors.py:379` has `p =subprocess.run`; translation time is quadratic in block depth (3000 nested blocks take 7 s).

## 7. The cores

No bug. GHDL synthesis of both cores and the devices shows no latch. Every stage process is clocked or `(all)`, reset is the last `if` of every clocked process, no signal has two drivers, every ASSUMPTIONS.md item names a MICROARCH.md section that says what it claims, and eight of them were checked in the code. The diagrams match the current structure: the skid register, the store register, the vector read through DBUS, the read data into a register, and the redirect from a register. No `assume` in the formal sources constrains the environment beyond the rules of §7.1.

### 7.1 The rules an integrator needs are not where an integrator looks

MICROARCH.md §8 says "A system built from them must follow these rules" and lists the visibility of stores, a default slave, the bus decoder, the math unit's latency, and the stack. hdl/README.md says "pipelined Wishbone". The cores also rely on these, which only the formal sources, the header of `pipeline.vhd`, and the formal section of the README state:

- **A slave may not ACK in the cycle it accepts.** `wb_master_check.vhd` counts a request from the cycle after it is accepted and assumes that an ACK finds one counted; FETCH and DBUS count the same way, and the header of `wb_dmux.vhd` says so. A same-cycle ACK is never counted.
- **ACK only while CYC is high, and only for a request the core made.** An ACK with nothing pending decrements a `natural` at `pipe_fetch.vhd:174` and `pipe_dbus.vhd:150`: a range error in simulation, a wrapped counter in hardware. `wb_mem.vhd` suppresses its ACKs during reset. A block RAM that is not reset with the core, or that does not gate ACK with CYC, would do it. The core drops CYC in the reset cycle, so "reset the slaves with the core" is the rule.
- **A store accepted in cycle c is seen by a fetch accepted in c + 1.** This is ASSUMPTIONS.md item 8 and contract (a) of the header, not a rule of §8. A write buffer breaks self-modifying code and the argument of §5.5.
- **Up to 8 instruction requests and 4 data requests in flight**, and `irq_ready_o` and `nmi_ready_o` combinational from `valid` (contract (c) of the header; the README says it for the multi-cycle core only).

**Fix:** a list in MICROARCH.md §8, and the same in the integrator text of hdl/README.md.

### 7.2 What `p_check` checks is overstated

hdl/README.md:551 and MICROARCH.md §9 say that the assumptions of each stage's proof that name another stage are checked in the whole core by `p_check`. PREPARE's assumptions about WRITE, `f_takes`, `f_sr_stable`, `f_cond_stable`, `f_run`, `f_tag_grow`, and `f_st_queue` (`pipe_prepare.vhd:515–531`), are not: `p_check` asserts the DECODE, DBUS, and committed-read invariants, and PREPARE's `G_FORMAL` is off in the whole core. TODO.md:48 says WRITE is covered by the bounded check only, which is the truth. **Fix:** name them as unchecked in the README, or assert them in `p_check`.

### 7.3 Unreset registers

WRITE's `saved_pc`, `saved_sr`, `s0val`, `s1val`, `last`, `m33sum`, `cnt`, `vec`, `vec_intr`, and `vec_nmi`, PREPARE's `rd_addr_r`, DBUS's `tags_r`, `rq_r`, `st_we_r`, `st_addr_r`, and `st_data_r`, and FETCH's `ring_r` have no reset. Every use is gated by a valid or a count, so there is no bug, but `dbus_addr_o` is 'U' until the first request, where the multi-cycle core's outputs start at '0', and no document or style rule says the choice is deliberate. One line in ASSUMPTIONS.md or CODING_STYLE.md.

### 7.4 The README against the code

- `multicycle.vhd:519` and hdl/README.md:445 say the state is "one of its 12 values"; `t_state` has 14, and the README's state table lists 9, without the four wait states and `HALTED_ST`.
- hdl/README.md:226 says the probe list leaves out only `scrbound`; `PROBES` in hdl/Makefile also lacks `screencolor` and `screeninvert`, which need `--color` and `--invert-fg`.
- hdl/ASSUMPTIONS.md:127 says "`make test CORE=pipeline` (the default)"; `make test` runs both cores, and `CORE` selects the core of `random`, `programs`, and `sweep` only.
- hdl/README.md:496 says the assertions of `formal_pipe_fetch` are "inductive in one step"; `pipe_fetch.sby` proves with depth 2. `hdl/test/random_prog.py:2` says "for the multicycle core's tests"; both cores run them. `programs.py --stall` is in no README.
- The header of `doc/pipeline.tex` names `dec_r`, `dec_q`, `prep_r`, and `st_r`, but not `skid_r` or WRITE's redirect registers, which MICROARCH.md §3 describes.
- `FS_JUMPS` and `FS_WORDS` count `d_redirect` and `f_consume` also in cycles where a flush drops DECODE's input, slightly more than "the jumps DECODE resolved".
- `wb_mem.vhd` always acknowledges in the next cycle, so a delayed ACK on the instruction bus is exercised only by the formal jobs.

## 8. The documents as a set

### 8.1 Stale statements

- `doc/intro/nice_intro.tex:128` "The FPGA implementation will have a UART at the same address", and emulator/README.md:132 "The FPGA core will have a UART at the same address." SYSTEM.md §1 and MICROARCH.md §8: this repository has no UART, and NiceMonMEGA65 maps one.
- The slides, line 40: "a first FPGA core -- and next, a faster one"; line 872: "The FPGA implementation will write the same trace"; line 914: "Next comes a faster clock for the pipelined core". Two cores exist, both write the trace, and the core meets 10 ns out of context. The PDF is checked against the `.tex`, so both change.
- README.md never says the pipelined core is the default. Its introduction and its table give the two cores with no order, where CLAUDE.md:34, hdl/README.md:10, and bench/README.md:136 say it.
- CLAUDE.md:51 says `make -C translator test` is "test/run.py, then test/errors.py"; translator/Makefile:24–31 also run `fuzz.py` in four modes and `passes.py`.
- REFERENCES.md:41 says pipeline-timing.md records "the clock of the pipelined core, measured out of context, and the plan for a faster one"; it now records the met timing too.
- MICROARCH.md:811 "Synthesisable".

### 8.2 Figures that disagree

| Figure | One place | Another |
|---|---|---|
| Data read after a store, translated | MICROARCH.md:305, 0.3% | MICROARCH.md:437, 0.8%, the current table; 0.3% is the 2026-10-19 figure of HISTORY.md:57 |
| Words per instruction | MICROARCH.md:122, about 1.8 and 1.6 | MICROARCH.md:427 and bench/README.md:171, 1.86 and 1.62 |
| `make core CORE=multicycle` | bench/README.md:14, about 20 minutes | bench/README.md:128–129, 38 and 8 minutes |
| `rng64`'s store wait | TODO.md:93–95, 10% and 7% | pipeline-timing.md, +10.2% and +7.5% |
| The Nexys4DDR | TODO.md:70, 83.33 MHz | no document records the measurement; pipeline-timing.md:288 has 75 MHz on 2026-10-21 |
| The MEGA65 R6 | TODO.md:68, "meets 100 MHz in NiceMonMEGA65" | pipeline-timing.md's last R6 build missed it by 0.257 ns, before the redirect change; the later results are out of context |

### 8.3 HISTORY.md

No entry for: the pipelined core becoming the default (753100a: `CORE`, `G_CORE`, the CI job, and the words "default" and "variant"); `regs_o` replacing NiceMonMEGA65's read of `retire_o.regs` (77d6ac6), which only TODO.md records; the assembler's warning for a lone word, its check of every `.EQU`'s symbols, and `INT`, `.BLK`, and `.RES` taking the value before it wraps (af454a6). The skid register, the vector read through DBUS, and the redirect from a register appear at HISTORY.md:231–232 under "The benchmark" only.

### 8.4 TODO.md

The first item asks for "the cost of the waits ... to decide on speculative reads"; MICROARCH.md §5.3 and bench/README.md have the figures now, and what is left is the decision. hdl/ASSUMPTIONS.md:13 narrates history ("once had DECODE read three registers"), which CLAUDE.md sends to HISTORY.md.

## What is correct

- The tests pass at 9d8f13d, as given. This review ran none of them.
- The emulator agrees with every rule of ISA.md §1 to §8 and of SYSTEM.md that the reader traced: reset values, R0, R14, and R15 in every mode, the order of constants and of side effects, the carry input, the shifts, the control words, interrupt entry and `RTI`, the halts, the I/O range, and every device's addresses, results, and reset values. The worked examples of ISA.md and the five encodings of the slides recompute by hand.
- The assembler's `encoding.bin` matches twelve hand-computed words, and every option, message, exit status, and finer point of its README matches the code.
- The emulator's trace writer and `hdl/src/trace_pkg.vhd` agree field by field, including `INT`, `RTI`, skipped instructions, the halts, and the first line after reset. Every option and message of its README matches the code, and every test file is used.
- ABI.md matches the code in the register roles, the call sequence, the stack, two-word values, the start-up code, the trap vector, and the join order. The two muldiv files have the same 14 labels and the same results, but for the documented division of a negative dividend by zero. Every runtime and C library test file is run, and every header declares what its source defines.
- The translator agrees with WASM.md and with wasm semantics in every rule the reader checked, and with a Python reference for 14 f32 operations and 6 compares on 30 edge values and 150 random pairs. Every supported opcode is listed, and every rejected one is in the unsupported list of the README and TODO.md, which are the same.
- Both cores have the same ports but for `stats_o`. Every Makefile target, variable, file, formal job, tool version, and probe that hdl/README.md names exists as described, but for §7.4. The timing figures, the hazard percentages, the instruction and cycle counts, the bubble costs, and the formal depth agree across TODO.md, MICROARCH.md, pipeline-timing.md, and the bench and hdl READMEs, but for §8.2.
- Every `make` line of CLAUDE.md is a real target with that meaning, but for §8.1. No TODO.md item is done. No source file has a TODO or FIXME. American spelling and the Oxford comma hold everywhere but the four places named above.
