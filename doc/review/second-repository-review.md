# Second review of the repository, at commit aa8a512

Reviewed on 2026-10-19: everything that changed since commit 88276db, the commit of [repository-review.md](repository-review.md), 131 commits, and the state of the repository as a whole at commit aa8a512 ("nicewasm: README.md wraps six paragraphs at the usual width"). The changes are the pipelined core of MICROARCH.md with its five entities, the formal proofs of FETCH, PREPARE, and DBUS, the 64-bit instruction bus of both cores, the data bus decoder, the timer (ISA.md §8.6), the fetch statistics (MICROARCH.md §8.1), the faster math unit, the console input, the device routines (ISA.md §9.3), `scanf`, the monitor start-up files, the translator's register allocator and its optimizations, the benchmark with its hazard profile, cycle model, and profiler, and the out-of-context timing of the pipelined core ([pipeline-timing.md](pipeline-timing.md)).

The question asked was not whether each part works, but whether the parts still fit: what the pipelined core, the translator work, and the formal checks left behind in the documents and the tests, and where two parts of the repository now say different things.

**How it was checked.** I read ISA.md §3 to §8 against `hdl/src/pipe_write.vhd`, `pipe_prepare.vhd`, `pipe_decode.vhd`, `pipe_fetch.vhd`, `pipe_dbus.vhd`, `pipeline.vhd`, `pipe_pkg.vhd`, and `nice_pkg.vhd`, and MICROARCH.md §3 to §7 and `hdl/ASSUMPTIONS.md` against the same files, rule by rule: the condition tested once per instruction, the four rules for a data read, the interrupt boundary, the flush ranges for a store into fetched code, the early redirect, R15 and R14 as operands, `regval`, the flags, and the reports to the trace writer. I read `timer.vhd` against §8.6, `wb_mem.vhd` against §8.3, and the formal wrappers against the README. I read every README, MICROARCH.md, ASSUMPTIONS.md, TODO.md, CLAUDE.md, the CI workflow, and the slides against the code and against each other. I ran `make test`, `make typecheck`, and `make -C hdl lint`; all pass, and CI passes on `main`. Then I ran what the repository does not:

- **`make -C hdl programs CORE=pipeline`**, the runtime's and the translator's 350 test programs on the pipelined core. CI and TODO.md run them on the multi-cycle core only. All 350 pass.
- **`make -C bench core CORE=pipeline`**, the benchmark on the pipelined core with the translator's output of 2026-10-19. The checked-in numbers are from 2026-10-16, before the translator's optimizations.
- **The cycle model against the core**, phase by phase, from those two runs.
- **A store into the pair of words being fetched.** A sweep of 40 programs that store a NOP over a `HALT` 1 to 40 words ahead, each with no stalls and with eight stall seeds, 360 runs on the pipelined core, all compared with the emulator. It targets the one window that `hazard.nasm` does not reach: a store that lands in the pair whose fetch the bus accepts in the same cycle.
- **The translator against its own previous version**, the one of 88276db, on 1300 random modules, 880 of them with accesses, divisions, and indirect calls that may trap, with every option; and the emulator's and the runtime's new code against ISA.md by hand, with the expected files of the new probes checked by hand. The results are in §5 and §6.

## Summary

**No bug was found in the pipelined core, the timer, the emulator, or the runtime.** The pipelined core runs all 350 programs and the benchmark correctly, and the one window I thought the self-modifying-code check left open is closed by the way FETCH reports its range (§1.2). The findings are about the repository drifting apart while three lines of work went on at once:

- The cycle model `bench/pipecycles.py` looks for the instruction counter at its old address, so `make cycles` and `make profile` print no phase rows, and it models the math unit as it was before the two-cycle multiplier. Its per-phase estimate is within 12% of the core on the translated benchmark, but its math-unit figures are wrong by up to a factor of 3.4, and TODO.md draws a conclusion from them (§3).
- The top-level README, the slides, and `bench/README.md` say the pipelined core is not written yet. MICROARCH.md §8 describes a memory system that does not exist, and §9 and ASSUMPTIONS.md item 14 do not know of the PREPARE and DBUS proofs. ISA.md §8.3 says the simulation memory has no console input. TODO.md says the test order's steps 4 to 7 pass on the multi-cycle core, when `make test` runs them on both (§2).
- `hdl/README.md` lost the heading of its trace-writer section (§2.4).
- CI never runs `make programs` on the pipelined core, and nothing in `make test` would notice the missing phase rows of §3.1 (§4).
- Small emulator items: `--input` with a directory runs as an ended input, one README sentence predates the timer, and the timer's "keeps its vector" rule has no test of its own (§6).

## 1. The pipelined core

### 1.1 What was checked

The core follows ISA.md where MICROARCH.md and ASSUMPTIONS.md say it does, and I found no rule it breaks. In WRITE: the condition is read from `cond_known` or from SR as the first micro-operation finds it; `bound_v` takes an interrupt only before an instruction that has not begun, with `commits`, `mid`, `busy`, and `after_rti` all clear; entry saves `regs(15)` for IRQ and NMI and `next_pc` for `INT`, sets I, and reads the vector at VBASE × 256 + v; a reserved control word is any with bits 20..8 set, or bits 7..0 set outside `INT`; `RTI` outside a routine and `INT` inside one halt; the flag update skips R14 in modes 000, 001, and 010; `R14--` goes through `regval` twice; R15 as a base is `next_pc` unless an earlier micro-operation of the instruction wrote it. In PREPARE: the condition is known for a first micro-operation only when WRITE's cannot change SR; a read waits for the register WRITE will write, for an older micro-operation that may jump, halt, store, or is not yet counted, and for a pending request that could be taken first, with the three exemptions of ASSUMPTIONS.md item 9; the read is counted in the cycle the bus accepts the last one. In DECODE: the early redirect is exactly `MOVE R15, c` and the two forms of `ADD R15, R15, c` with condition "always" and the C bit clear, with or without M, and WRITE computes the same target from `next_pc`. In FETCH: a redirect drops the requests in flight and an odd address's low word. The assertions of `p_check` and the formal properties say what the headers claim.

The shifter in `nice_pkg.vhd` still reduces the count inside WRITE. MICROARCH.md §7.3 says PREPARE "can" compute it, which it does not yet; that is step 3 of the lean plan in TODO.md, so this is a note, not a finding.

### 1.2 A store into the pair being fetched

WRITE flushes when a store lands in FETCH's range, `addr_o` to `end_o`, or in the instruction in DECODE or PREPARE. `end_r` is set when FETCH decides on a request, one cycle before the request is on the bus. So the pair whose fetch the bus accepts in the same cycle as the store is already inside the range, and the memory model's rule that the instruction port reads the old value in that cycle does no harm: the flush drops the stale pair and refetches. My sweep confirmed this. With no stalls, the store of the program with 9 and 10 NOPs lands in the pair accepted in the same cycle, and the waveform shows the flush and the refetch. All 360 runs match the emulator.

**Suggestion.** `hazard.nasm` stores up to six words ahead, all inside FETCH's buffer. A section that stores 1 to 40 words ahead would cover the boundary of the range, on every stall seed `make test` uses. It is a short loop of `MOVE @n, 0` over a `HALT`, as section 5 does now.

**Resolved**: `hdl/test/smc_prog.py` writes that program, 40 stores of a NOP over a `HALT` 1 to 40 words ahead, which checks itself, and `make test` runs it on every core with and without stalls. A waveform of the pipelined core shows three of its stores landing in the pair whose fetch the bus accepts in the same cycle with no stalls, and two with 30%, so the test reaches the far end of FETCH's range. The sweep's 360 runs from reset are not kept; the program covers the same distances in the pipeline's steady state.

## 2. The documents that fell behind

### 2.1 The pipelined core "is not written yet"

- `README.md` line 20: "The pipelined core is not written yet." Line 32 calls MICROARCH.md "a draft design note", line 40 says `hdl/` holds "So far a simple multi-cycle core", and line 61 says `make -C hdl test` tests "the multi-cycle core".
- `doc/intro/nice_intro.tex` lines 816 and 913: "So far a simple multi-cycle core", and "Next comes the pipelined FPGA core". `make pdfcheck` means the PDF must be rebuilt with the text.
- `bench/README.md` line 187 and the docstring of `bench/pipecycles.py`: the pipelined core "is not built yet".

**Fix.** Say that `hdl/` holds both cores, that the pipelined one is the core of MICROARCH.md, and that `make -C hdl test` runs both against the emulator. In the slides, move the pipelined core from "next" to "exists", with a sentence on the proofs.

**Resolved**: README.md, the slides, with `nice_intro.pdf` rebuilt, `bench/README.md`, and the docstring of `pipecycles.py` say that both cores exist, and what comes next.

### 2.2 MICROARCH.md

- **§8** opens with "The repository provides a system around the core: the core, dual-port RAM, the bus decoders, a default slave, and the console UART", and the Console bullet describes a UART at `0xFFFFFF00`. Only the data bus decoder exists, as TODO.md says. **Fix:** "will provide", and mark the UART, the RAM, the default slave, and the instruction bus decoder as open, with a pointer to TODO.md.
- **§9** says "FETCH is proven for every cycle" and that the whole core is checked for 8 cycles. PREPARE and DBUS are proven too (`hdl/Makefile`, `FORMAL`), and hdl/README.md describes both proofs. **Fix:** name all three, and say which assumptions of each are checked by `p_check` in the whole core.
- **§7.3** says the mod 33 reduction "does not depend on s0, so PREPARE can compute it". The core computes it in WRITE, which is the second carry chain of pipeline-timing.md. **Fix:** say where it is now, and that moving it is step 3 of the lean plan.
- **§5.6** is the table of 2026-10-15, which TODO.md already notes as stale. `make -C bench hazards` gives the new shares.

**Resolved**: §8 says what exists and what the memory model stands in for, §9 names the three proofs and what `p_check` checks of their assumptions, and §7.3 says where the reduction is and that moving it is step 3 of the plan. §5.6 stays as TODO.md has it.

### 2.3 ASSUMPTIONS.md

Item 14, "FETCH is proven, the rest of the core is checked for 8 cycles", predates the proofs of PREPARE and DBUS. The header says MICROARCH.md "has since taken up items 1, 8, and 9"; after 2.2 it should also take up 14. **Fix:** update the item, or drop it in favour of hdl/README.md, The formal checks.

**Resolved**: item 14 names the three proofs and what checks their assumptions, and the header says MICROARCH.md has taken it up.

### 2.4 hdl/README.md lost a heading

Commit ef385fa ("nicehdl: the timer of ISA.md §8.6") replaced the heading `## The trace writer` with `## The timer` instead of inserting one. The paragraphs that begin "The core reports each step in a `t_retire`" now sit under "The fetch statistics", after two blank lines (line 676). **Fix:** put `## The trace writer` back before them.

**Resolved**: the heading is back.

### 2.5 TODO.md names the multi-cycle core where both pass

Under "Test order steps not done", steps 4, 5, 6, and 7 each say "which the multi-cycle core passes". `make test` runs steps 4, 5, and 7 on both cores, and the pipelined core passes them; step 6 passes on it too, as this review ran it (How it was checked). **Fix:** say "both cores", and add `make programs CORE=pipeline` to what step 6 has run.

**Resolved**: the four steps say both cores pass, and step 6 names the run of 2026-10-19. Seeds 31 to 90 pass on the pipelined core too, checked with `make random` for this fix.

### 2.6 ISA.md §8.3 on the simulation memory's input

"The simulation memory of the FPGA core has no input either: a read returns `0x200`." Since commit 7f445c5, `hdl/sim/wb_mem.vhd` reads the file of its generic `G_INPUT_FILE` and returns `0x100` plus each byte, and `0x200` only after the end or without a file, as hdl/README.md says and the emulator's `input` probe checks on the core. **Fix:** "The simulation memory of the FPGA core reads a file too, as the emulator's `--input` does, and returns `0x200` without one."

**Resolved**: the sentence says so.

### 2.7 Smaller ones

- `CLAUDE.md`: `make -C hdl formal` is "ports of both cores, a proof of FETCH". It also proves PREPARE, DBUS, the timer, and the data bus decoder.
- `doc/REFERENCES.md` lists the review notes, but not [pipeline-timing.md](pipeline-timing.md), which is one.
- `emulator/src/main.zig` usage says the timer is at `0xFFFFFF10`–`0xFFFFFF12`; the README's memory map and ISA.md give `0xFFFFFF10`–`0xFFFFFF1F`, and words 13 to 1F are device words that read 0 and drop writes, not memory.

**Resolved**: CLAUDE.md names every proof, REFERENCES.md has listed pipeline-timing.md since the review's own commit, and the usage text gives the timer's and the counters' ranges in full.

## 3. The cycle model, bench/pipecycles.py

### 3.1 It looks for INSTR_LO at the old address

`INSTR_LO = 0xFFFFFF12` (line 96, and the docstring). Commit 50995c8 of 2026-10-17 moved the performance counters to `0xFFFFFF40`, so `INSTR_LO` is `0xFFFFFF42`, and `0xFFFFFF12` is `TIMER_VECTOR`. The model was added on 2026-10-19, from a branch that predated the swap. `bench.c` and `hand.nasm` read `0xFFFFFF42` around each phase, so `make cycles` prints the totals and the causes but no phase rows, and `make profile` has no phases to charge to. The phase table in `bench/README.md` and the per-phase figures in TODO.md cannot be reproduced at this commit. `make -C bench test` does not notice, because `pipecycles.py --test` runs on snippets that read no counter.

**Fix.** `INSTR_LO = 0xFFFFFF42`, and a test that runs the model on `build/bench.bin` and expects six phase rows, or a check of the constant against `runtime/lib.nasm`.

**Resolved**: `INSTR_LO` is `0xFFFFFF42`, and `make test` runs the model on both programs with `--phases 6`, which fails unless each reads the counter around six phases. The fixes of 3.1 to 3.3 are one commit, since the comparison needs the phases and the phases need the address.

### 3.2 It models the math unit of 2026-10-15

The model holds a read of a result for `--mpu32` = 35 cycles after the write of an operand, "as in hdl/src/mpu.vhd: 33 (65) steps, plus a cycle to start and one to acknowledge". Since commits b018cbd and dd81315 of 2026-10-16, the multiplier takes two cycles, and the dividers skip runs of eight zero quotient bits, so a small dividend or a large divisor takes a few cycles. `bench/README.md` repeats the 35. The model therefore overcharges every multiplication by about 30 cycles.

**Resolved**: the model has the multiplier's two cycles and the dividers' skips, worked out from the operands in the trace as `mpu.vhd` does them, with `--mul` and `--div-skip` as its knobs in place of `--mpu32` and `--mpu64`. `--test` has four math unit cases, a product, two divisions that skip, and one that does not, with the cycles counted by hand from the rules of `tb_mpu`.

### 3.3 The model against the core

With the address of 3.1 corrected, the model's phase rows against the pipelined core's `make core CORE=pipeline`, both on the programs of 2026-10-19:

| Phase | Instructions | Model, cycles | Core, cycles | Model against core |
|---|---|---|---|---|
| `rng64` | 89632 | 101952 | 95358 | +7% |
| `crc32` | 65816 | 76595 | 87154 | −12% |
| `bst` | 315589 | 434878 | 409866 | +6% |
| `heapsort` | 312536 | 375132 | 386801 | −3% |
| `vm` | 840049 | 1122089 | 1184155 | −5% |
| `strings` | 105901 | 162844 | 167285 | −3% |
| total | 1729523 | 2273490 | 2330619 | −2% |

And for `hand.nasm`:

| Phase | Instructions | Model, cycles | Core, cycles | Model against core |
|---|---|---|---|---|
| `rng64` | 39949 | 205836 | 59679 | 3.4 times |
| `crc32` | 27658 | 35337 | 41756 | −15% |
| `bst` | 115203 | 281279 | 260388 | +8% |
| `heapsort` | 175654 | 304491 | 290524 | +5% |
| `vm` | 112013 | 452032 | 500056 | −10% |
| `strings` | 21140 | 82699 | 61791 | +34% |
| total | 491617 | 1361674 | 1214194 | +12% |

The totals of the translated benchmark agree to 2%, which is better than the model promises. But the agreement comes from errors that cancel: the phases that wait on the math unit (`rng64`, `bst`, `strings`) are overcharged, and the phases of byte loads and table jumps (`crc32`, `vm`) are undercharged. In `hand.nasm`, where the math unit is used directly and often, the model is 3.4 times too high on `rng64` and a third too high on `strings`.

TODO.md, under "Faster and smaller translated code", says that "waits on the math unit" are "about a quarter" of the cycles above one per instruction, and that hiding "the 35 cycles" needs independent work. That quarter is the model's figure with the old multiplier. On the core, `rng64`, whose inner loop is `i64.mul`, runs at 1.06 cycles per instruction. The conclusion should be drawn again from the core, or from the model once 3.2 is fixed.

**Fix.** Give the model the multiplier's 2 cycles and the dividers' variable time (a divider that skips zero runs is simple to copy from `mpu.vhd`), and then compare it with the core again. The comparison is worth keeping: `make core CORE=pipeline` already prints the phase rows, and a target that diffs them against the model's would show when the model drifts next.

**Resolved**: `make compare` prints the model's phases beside the core's, from the output of `make core CORE=pipeline`. With the math unit of 3.2, the model is below the core in every phase, by 2% to 22%, least on `rng64` and most on the jump-heavy `vm`, `crc32`, and `bst`; `bench/README.md` has the table. `--flush 7` halves the error, so the core's bubble after a jump taken in WRITE is longer than the five cycles the model assumes, which is a new item in TODO.md.

### 3.4 The tables of 2026-10-16

`bench/README.md` ("On 2026-10-16") and `hdl/README.md` ("The pipelined core") give the pipelined core 6003616 cycles for 3359061 instructions on the translated benchmark, from before the translator's optimizations, next to the multi-cycle core's numbers of 2026-10-19 for 1729523 instructions. The two columns are not of the same program. Today's numbers from this review:

| Program | Instructions | Cycles | Cycles per instruction | Faster than the multi-cycle core |
|---|---|---|---|---|
| `bench.c` through nicewasm | 1729523 | 2330619 | 1.35 | 8.5 times |
| `hand.nasm` | 491617 | 1214194 | 2.47 | 4.8 times |

The pipelined core also ran `hand.nasm` 21% faster than on 2026-10-16, which is the faster math unit of 3.2 at work.

**Fix.** Replace both tables with these, with the date, and keep the two READMEs' tables the same.

**Resolved**: both READMEs have the tables of 2026-10-19, and hdl/README.md's reading of `hand.nasm`'s phases follows the new cycles.

## 4. The tests and CI

### 4.1 CI runs `make programs` on the multi-cycle core only

The `hdl` job runs `make test`, which covers both cores, and `make programs`, which runs `CORE`'s default, the multi-cycle core. So the pipelined core's run of the 350 programs happens only when someone runs it by hand, as this review did. **Fix:** `make programs CORE=pipeline` in the job too, about as long again, or `programs` over `CORES` as `test` is.

**Resolved**: the job runs `make programs CORE=pipeline` after `make programs`.

### 4.2 Nothing checks the model's phase rows

See 3.1. The bench `make test` runs `pipecycles.py --test` on snippets. A run of the model on `bench.bin` that asserts six phase rows, with the sum of the rows no more than the total, would have caught the stale address.

**Resolved**: with 3.1.

### 4.3 The hazard program and the fetch range

See 1.2.

## 5. The translator

### 5.1 The optimizations are correct

The translator at this commit and the translator at 88276db were run on the same random modules, and their programs compared on the console output, the halt reason, the exit status, R1, R7 to R13 after a normal halt, and every word of the linear memory; R2 was left out, since a trap's R2 may differ between versions. The modules were those of `fuzz.py`'s generator, in bounds, with R1 also checked against its model, and the same modules with injected statements that may trap: loads and stores out of bounds, at constant addresses, through locals, and as `(i << s) + c` with masked and with huge indices, offsets up to `0xFFFFFFF0`, groups of word accesses from one local near the end of the memory, `div` and `rem` by zero and by masked divisors, the most negative value divided by −1, `call_indirect` with a bad index and with a bad type, `memory.fill` and `memory.copy` past the end and wrapping, a conditional `unreachable`, and, with `--memory-pages 2`, `memory.grow` and accesses to the new page. 1300 modules ran: 420 in bounds, with the default options, `--no-mpu`, `--no-bounds-checks`, `--memory-pages 2`, and `--library`; and 880 that may trap, of which 514 did, with every trap code but 5, which needs floats. Both versions agreed on every module, every trap code, and every memory word. A module built by hand, a shared-compare group in a loop with a `nice.poke` between its accesses, took the slow path through the copy on an unaligned first round, printed the same on both, and ran the `poke` once per round.

By reading, each rule of the README's "How functions are translated" holds in the code: a hoisted instruction is register-only, flag-free, and unconditional, commutes with what it passes, goes after a jump so that it never runs on the taken path, and may not touch the register that the write before a read writes; an early exit never touches a saved register or SP; a tail call restores R7 to R12 and drops the frame first, and a call with stack arguments is never one; a known bound is forgotten at every label a jump can reach and at every write of its register; a shared compare's slow path is a copy whose traps keep the original's R2; `if_convert` converts only bodies with no condition, flag write, R14 operand, or label, so a `peek` or `poke` under a condition is performed exactly when wasm would; `mul64_const` forms the low 64 bits from the three partial products; the trap helpers take four words and set R1 and R2 as §9.4 says. 164 cases of `run.py` in both modes, 151 error cases, and 880 seeds of `fuzz.py` pass, and `mypy --strict` is clean.

### 5.2 Three rules have no test

CLAUDE.md asks for a test with every new rule. Commits fa3a8a7 (the instruction moved after the write of an address register may not use what it writes), 2e77769 (a tail call has only labels and comments before the return), and 3e0a2c1 (no tail copies in the stubs after the epilogue) change `nicewasm.py` and the README only. The first two commit messages say that no module reaches the shape today, which is why no `run.py` case could be written; the third could be pinned by a `SHAPES` entry. **Fix.** A test of the passes on hand-built instruction lists, which `test/` has no form for yet: `hoist_into_slots` and the tail-call pass take a function's items, so a few lists with the shapes in question, and the expected output, would do.

**Resolved**: `test/passes.py` runs `hoist_into_slots`, `tail_calls`, and `duplicate_tails` on code built by hand, five cases with the three rules among them, and `make test` runs it.

### 5.3 What `fuzz.py` does not check

`fuzz.py` runs the default options only, and its model checks R1 and a normal halt: not the trap codes and R2, which TODO.md records, and also not R7 to R13 across the call, not the console, and only 18 words of the memory. The differential check above covered those, and found nothing; a version of it in the repository would keep it so. The script is `diff_fuzz.py` in the scratch directory of this review, with the old translator beside it, and TODO.md already asks for such a mode.

### 5.4 README nits

- Line 92: "`test/safe.zig` is about 7100 words built with ReleaseSafe". It is 5182, as the README's own measurements of 2026-10-19 and `make -C bench words` say. The Debug figure on the same line was not checked.
- Lines 410 to 416 list `i32.mul` among the operations whose result goes straight to the local. With the math unit, `mpu_op("umul_lo", ...)` at line 4745 does not forward the result; only the constant multiplications and the `--no-mpu` path do. The coalescing then removes the copy, so the code is the same; the sentence or the call could change.
- Lines 715 to 720 describe `invert_back_edges` without its second form, where an unconditional jump after the `br_if` swaps targets with it instead of getting a label.
- The example at lines 479 to 481, `SUB[M] R0, R1, 65532`, is for an access at offset 1, which the text does not say.

## 6. The emulator and the runtime

### 6.1 `--input` with a directory runs as an ended input

`niceemu --input /tmp prog.bin` opens the directory (main.zig line 261), and every console read then returns `0x200`, because `cpu.zig` line 427 turns every read error into the end marker. The run exits 0 with no message. `test/errors.py` has cases for a missing value and a missing file, not for this. **Fix:** reject anything but a regular file or `-` after opening, with exit 1, or let `cpu.zig` fail on any error but end of stream; and add an `errors.py` case.

### 6.2 The README's Interrupts section predates the timer

`emulator/README.md` line 178: "No device raises IRQ or NMI yet." The timer has raised IRQ since commit 3125ba1, and the same README's memory map says so. **Fix:** "The timer (Memory map) is the only device that raises IRQ, and no device raises NMI."

### 6.3 The timer's "keeps its vector" rule has no test of its own

ISA.md §8.6: "A request keeps the vector it was raised with." The unit test at `cpu.zig` line 1487 rewrites `TIMER_VECTOR` only after an `--irq` request has replaced the timer's, so it checks the merge, and `test/timer.nasm` never changes the vector after setting it. A scratch probe that raises the timer's request with E = 0, rewrites the vector, stops the timer, and sets E showed the right vector taken, so the emulator is correct. **Fix:** add those steps to `timer.nasm`, with the expected file checked by hand.

### 6.4 Nits

- `main.zig` line 261 accepts `--input -` for stdin, which neither the usage text nor the README says.
- `cpu.zig` line 326's comment says a console read returns 0 when the input is unset; the code falls through to memory.
- The emulator's console read blocks, so it never returns 0 for "no byte waiting". `nice_getc`'s retry loop and `nice_pollc`'s −2 can be exercised only on hardware; `device.nasm` and `libc/test/nice.c` test the byte and end paths.

## 7. What is correct

- **The pipelined core** against the emulator on everything `make test` runs, on the 350 programs of `make programs` (first run on it here), on the benchmark with the translator's output of 2026-10-19, and on 360 runs of stores at every distance up to 40 words. Its code keeps the rules of ISA.md and MICROARCH.md as §1.1 lists them.
- **The timer** in `timer.vhd` against §8.6: the write's own cycle counts, P = 0 stops the count and leaves a request pending, a new request keeps a pending one's vector.
- **The emulator** against §7, §8.3, §8.5, and §8.6: the timer's count and merge rules, `--no-timer-irq`, `--no-cycle-counter`, the console's bits 8 and 9, no side effect of `peek` or `--dump` on any device, fetches from the I/O range. The expected files of the `timer`, `input`, `perf`, and `console` probes were checked by hand against ISA.md. The README's options and memory map match `main.zig`. 37 unit tests, 28 program runs, and 42 `errors.py` cases pass.
- **The runtime**: the eight device routines against the §9.3 table, `nice.zig`, `nice.rs`, `nice.h`, and the C library's `getchar` and `scanf` against it and the README, with 18 edge cases of `scanf` compared with glibc; `start_mon.nasm` and `start_wasm_mon.nasm` against "Programs under a monitor", with their expected files checked by hand. 17 runtime programs and 5 C library tests pass, and `fuzz_printf.py` passes 1100 more random calls with seeds 2 and 7.
- **The translator** against its previous version on 1300 random modules in every mode, with 514 traps, all agreeing, and against its README rule by rule (§5.1). 164 cases of `run.py` in both modes, 151 error cases, and 880 seeds of `fuzz.py` pass.
- **The documents** agree with the code everywhere else I compared them: ISA.md §8.4 to §8.6 and §9.3 with `mpu.vhd`, `perf.vhd`, `timer.vhd`, `cpu.zig`, and `lib.nasm`; hdl/README.md with the Makefile, the testbenches, and the formal jobs; `emulator/README.md`'s memory map with `cpu.zig`; and MICROARCH.md §3 to §6 with the five entities.
