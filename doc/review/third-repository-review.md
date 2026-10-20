# Third review of the repository, at commit 69405dd

Reviewed on 2026-10-20: everything that changed since commit aa8a512, the commit of [second-repository-review.md](second-repository-review.md), 34 commits, and the state of the repository as a whole at commit 69405dd ("nicehdl: CYC held in the cycle after an accept, and no request after a halt"). The changes are the pipelined core re-timed for 100 MHz ([pipeline-timing.md](pipeline-timing.md), The second measurement): PREPARE forms every operand value, address, and shift count, WRITE keeps the value it wrote last as its one bypass, the shifter works from a prepared count, the store compare is on aligned blocks, and three rare cases take WRITE a second cycle; `make timing`; the translator's byte accesses that rotate by a register count computed before the bounds check; the cycle model with the rules of the re-timed core and `make compare`; `hazards.py` with the counts of those rules; the fixes of the second review, with `smc_prog.py`, `passes.py`, and `diff_fuzz.py`; and the moves of the devices to SYSTEM.md, of the C ABI and the WebAssembly mapping to ABI.md and WASM.md, and of the history to HISTORY.md, with tables of contents for ISA.md and MICROARCH.md.

The question asked was the same as last time: not whether each part works, but whether the parts still fit, after a re-timing that changed how WRITE gets every operand, and after four documents were cut out of two.

**How it was checked.** I read ISA.md §3 to §8 against `hdl/src/pipe_write.vhd`, `pipe_prepare.vhd`, `pipe_decode.vhd`, `pipe_fetch.vhd`, `pipeline.vhd`, `pipe_pkg.vhd`, and `nice_pkg.vhd` as they are now, rule by rule: where each field's value comes from (`SRC_VAL`, `SRC_LAST`, `SRC_SR`) and when PREPARE waits instead; R15 as a base before and after a side effect on it in the same instruction; the two-cycle cases and the interrupt boundary between them; the late shift count and its count mod 33; the flags after a destination in R14; the block compares of a store against FETCH's range, with the block number a cycle late, and against the instructions in DECODE and PREPARE; the early redirect and what WRITE computes for it. I read MICROARCH.md §3 to §9, ASSUMPTIONS.md, SYSTEM.md, ABI.md, WASM.md, HISTORY.md, every README, TODO.md, CLAUDE.md, the slides, and the CI workflow against the code and against each other, and the diffs of `nicewasm.py`, `pipecycles.py`, `hazards.py`, `cpu.zig`, `main.zig`, the runtime, and the new tests. I ran `make test`, `make typecheck`, `make -C hdl lint`, `make pdfcheck`, and `make -C hdl formal`; all pass, and CI passes on `main`. Then I ran what the repository does not run by itself, or does not run at all:

- **`make -C hdl programs CORE=pipeline`**: all 350 programs pass on the re-timed core.
- **`make -C bench core CORE=pipeline`** at this commit, against the tables in `bench/README.md` and `hdl/README.md` (§1.3).
- **`make -C translator diff OLD=aa8a512`**: the translator against its version at the last review, on 360 random modules in six modes, with traps, growth, `--no-mpu`, `--library`, and `--unchecked`. No difference.
- **Every `FILE.md §n.m` reference in the repository** against the headings of ISA.md, SYSTEM.md, MICROARCH.md, and the others, with a script (§5.1), since two sections of ISA.md moved out and its numbering changed.
- **The bubble after a jump** on the pipelined core, measured with the cycle counter on nine four-instruction programs, for a fall-through, a skipped jump, a jump taken in WRITE, a target that spans two pairs, an early redirect, `MOVE R15, R3`, and `ADD R15, R3, 0` (§1.2), beside the cycle model's figures for the same programs (§3.1).
- **Programs written to break the operand rules of the re-timed core**, run on both cores and the emulator (§1.5), which found the bug of §1.4. The counts of §3.2 and §3.3 are rows of `hazards.py` now.
- **The multi-cycle core**, run to the same depth: the 350 programs, random seeds 31 to 90, the sweep of `latecount.nasm`, and the benchmark (§1.6).
- **The benchmark with smaller budgets for a multiplication by a constant**, by the cycle model (§4.1).
- **The three diagrams of MICROARCH.md §3 and §6**: the block diagram and its text twin against the entities and their registers, and the interrupt timing diagram against a scratch copy of the re-timed core instrumented to print its sixteen signals once per cycle for `irqwave.nasm` (§2.8).

## Summary

**One bug was found, in the pipelined core: a `0<0` shift with R15 as its destination in mode 000 jumps to the unshifted source** (§1.4). WRITE decides whether a jump's target is ready from the opcode alone, and the shift `0<0` shares the opcode 0000 with `MOVE`, so `0<0 R15, R1, 1` redirects FETCH to R1 while R15 gets R1 << 1, and the trace reports the right R15 as the core runs from the wrong address. The multi-cycle core and the emulator are right. No test has such an instruction: the random programs never write R15 with an ordinary instruction, and the hazard programs jump with `MOVE` and `ADD`. The fix is one condition in `pipe_write.vhd`. It was found by programs written against the operand rules of the re-timed core, which found nothing else in 240 runs with interrupt requests and some 7000 instructions of the cases in §1.4.

Nothing else is wrong in the core, the translator, the emulator, or the runtime where I read them. The re-timed core follows ISA.md elsewhere, passes everything, and the one place where I thought a comment's argument did not hold (§2.3, the block number a cycle late after DECODE's redirect) is safe for another reason. The other findings are where the documents and the models lag the core and the moves:

- **The cycle model's bubble after a jump taken in WRITE is explained with a registered flush that the core does not have.** The flush is combinational, and the measured bubble is 6 cycles, not the 7 of `bench/README.md` and the model (§3.1). The 7 fits the benchmark better, so it may stay, but as a fit, not as the core's timing. Two more of the model's rules, shared with `hazards.py`, are not the core's: a jump through a register counts as one DECODE resolves, and `MOVE R15, Rx` as a two-cycle jump (§3.2); and a shift count through an adder, which every signed byte load of the translator uses, is not charged the cycle WRITE spends on it (§3.3). The four new options are documented as off by default, and are on (§3.4).
- **The moves left text behind.** ABI.md and WASM.md say "SYSTEM.md ISA §2" six times, the memory map of SYSTEM.md is broken into two tables, the slides still send a C compiler to ISA.md for its calling convention, HISTORY.md calls the translated code "the code of the translator" and cites an ISA section that moved, and the review notes cite ISA.md sections by their old numbers (§2, §5.1).
- **MICROARCH.md and ASSUMPTIONS.md lag the re-timing in small ways**: figures of the old hazard table, "two cycles" where a rotation through C takes three, a signal that does not exist, and the argument of §5.5 that no store retires in the cycle after a redirect (§2.3, §2.4).
- **The translator's budgets for a multiplication by a constant are tuned to the 35-cycle multiplier** that the math unit had until 2026-10-16, and the README and the code still say so. The model says the difference is small today (§4.1).
- **Two bench tools count the same trace differently** (§3.5), and the hand-written program's rows of the benchmark tables are 0.1% off what the core gives at this commit (§1.3).

Every finding has a fix. None changes what a program computes.

## 1. The pipelined core

### 1.1 What was checked

The re-timed core follows ISA.md. In PREPARE: a field in mode 000, 010, 100, or 110 whose register the micro-operation in WRITE writes takes `SRC_LAST`, unless it is a read address, which waits; a field in mode 001, 011, 101, or 111 on such a register waits; R14 in a plain mode takes `SRC_SR`, so the flags of the older instruction are seen; R15 is the instruction's next address unless `w_r.jump` says an earlier micro-operation of the same instruction wrote it, and an older instruction's write of R15 is never a dependency, since it flushes this one or leaves R15 the next address. `wr_v` covers every write the micro-operation in WRITE can make, `uop_wreg` for the registers and `may_sr` for SR, and a control instruction's writes of R14 and R15 end in a flush. The shift count is late exactly when §7.3 says, and `cnt_late` with `cnt_step` takes one cycle, or two for a rotation through C. In WRITE: `n_v.last` is the register written, through `regval`, so `R14--` leaves `0x01FFFFFF`; the second cycle of an adjusted destination or a computed jump finds the result in `w_r.last` and `w_r.regs(15)`; `MOVE R15, x` takes its target from the source and needs no second cycle; the flags update after the destination and skip R14 in modes 000, 001, and 010; a store waits for room, and its register writes are undone until the bus accepts it; `bound_v` keeps an interrupt out of the two-cycle cases with `cnt_step` and `exec_done`. The early redirect of DECODE is still exactly `MOVE R15, c` and the two forms of `ADD R15, R15, c` with condition "always" and the C bit clear, and WRITE computes the same target from `next_pc`. The block compare of §5.5 covers FETCH's range: the range is at most 16 words from the oldest word, which lies in the block of that word or the next, and WRITE tests the block of the oldest word, the block after the one it was in a cycle ago, and the one after that (§2.3 on the cycle after a redirect).

### 1.2 The bubble after a jump, measured

Nine programs read `CYCLE_LO` into R1, run one instruction, and read it into R2. On the pipelined core in `tb_core` with no stalls:

| Between the reads | R2 − R1 | Cost |
|---|---|---|
| `MOVE R0, 0` (fall-through) | 3 | |
| `?Z MOVE R15, L` with Z = 0 (skipped) | 3 | 0 |
| `?!Z MOVE R15, L` (taken, resolved in WRITE) | 9 | 6 |
| The same, with `L` odd, so the target spans two pairs | 10, against 4 for the skipped jump in the same layout | 6 |
| `MOVE R15, L` (resolved in DECODE) | 5 | 2 |
| `MOVE R3, L` first, then `MOVE R15, R3` | 9 | 6 |
| `MOVE R3, L` first, then `ADD R15, R3, 0` | 10 | 7 |

So a jump that WRITE resolves costs 6 cycles over a fall-through, whatever the target's alignment, a `MOVE` through a register the same, and an `ADD` to R15 one more, as MICROARCH.md §5.4 and §7.4 say. `hdl/test/bubble.nasm` measures the seven cases and checks these values; `make test` runs it on the pipelined core. The chain is: the jump retires in cycle c − 1 and flushes in the same cycle, since `flush_o` is combinational; FETCH issues the request in c, it is on the bus in c + 1, the memory acknowledges in c + 2, DECODE takes the instruction in c + 3 and emits its micro-operation in c + 4, PREPARE passes it on in c + 5, and WRITE runs it in c + 6, where the fall-through would have run in c. §3.1 is about the model's account of this.

### 1.3 The benchmark on the core

`make -C bench core CORE=pipeline` at this commit gives the translated program's figures of `bench/README.md` and `hdl/README.md` exactly: 2275410 cycles, and every phase of the `make compare` table. The hand-written program's do not reproduce:

| `hand.nasm` | `bench/README.md`, from commit dcc491a | At 69405dd |
|---|---|---|
| `rng64` | 60191 | 59679 |
| `bst` | 262436 | 261412 |
| total | 1216653 | 1215117 |

The other four phases agree. No logic of the core, the memory model, the testbench, or the program changed between dcc491a and 69405dd, only comments and formal properties, so the rows were measured on some earlier state of the core; the differences are exactly 512 and 1024 cycles, a cycle for each round of a loop. The derived figures hold, 2.47 cycles per instruction and 4.6 times faster than the multi-cycle core, and the model's distance in the `make compare` table moves from −1.3% to −0.5% on `rng64`, from −8.1% to −7.8% on `bst`, and from −7.7% to −7.6% in all. **Fix:** the three rows in `bench/README.md`, and `hdl/README.md`'s 1216653; and name the commit beside each measured table, since the code, not the date, decides whether a run reproduces.

### 1.4 A `0<0` shift into R15 jumps to its source

`pipe_write.vhd`, in the destination case for mode 000:

    if x_v = 15 then
       target_v := v0_v;
       two_v    := u_v.inst.op /= "0000";
    end if;

`u_v.inst.op` is bits 24..21 of the instruction word for ALU and SHIFT instructions alike, so a shift with opcode 0000, which is `0<0` (`SHL`), takes the `MOVE` path: FETCH is redirected to s0 in the same cycle, and the shifted result goes to `regs(15)` and to the trace. The program

    MOVE    R1, 0x80
    0<0     R15, R1, 1          ; R15 = 0x100
    HALT
    .ORG    0x80
    MOVE    R2, 0x80
    HALT
    .ORG    0x100
    MOVE    R2, 0x100
    HALT

runs on the emulator and on the multi-cycle core as `R15=00000100`, then `MOVE R2, 0x100` at `0x100`. On the pipelined core the trace reports `R15=00000100` and then continues at `0x80`: `R2=00000080`, and the halt at `0x82`, with and without stalls. The same with a count in a register written by the instruction before (`0<0 R15, R1, R2`, which continues at R1), and with a constant source (`0<0 R15, 1[R0], R2`, which continues at 1). `0<0 R15, R1, R0`, a count of 0, is right by luck, and every other shift opcode into R15 is right, since it takes the second cycle whose redirect reads `regs(15)`. `0<0 R15++, R2, 1` is right too, through the adjusted-destination path.

The ISA says any write to R15 is a jump (§4.3), and the shift's result is the value written. **Fix:** `two_v := u_v.inst.op /= "0000" or u_v.inst.shift = '1'`, and a comment that `MOVE` is opcode 0000 of the ALU class only. Then tests, since none reached this: a `0<0 R15, R1, 1` and a `0<0 R15, R1, R2` in `emulator/test/r15.nasm` or in `hdl/test/hazard.nasm`, which both cores run in `make test`; and a jump template with a shift in `hdl/test/random_prog.py`, whose "ordinary instructions never write R15" is why thirty seeds of random programs did not find it. `bench/hazards.py` has the same blind spot in its decode, where a `MOVE` is "not a shift and opcode 0" (`move = not (iw >> 27) & 1 and ...`), which is right; the core's test is the one to change.

**Resolved**: `two_v` is set for a shift too, with a comment that `MOVE` is opcode 0000 of the ALU class only. `emulator/test/r15.nasm` has a `0<0` into R15 by a constant count and by a count written just before, with its expected file worked out by hand, and both cores run it in `make test`; `hdl/test/shiftjump.nasm` has every shift into R15; and a fifth of the jump templates of `random_prog.py` are now `0<0 R15, c, 1`.

### 1.5 The programs written against the operand rules

The bug came from a second reader's programs, in the scratchpad of the review, run on both cores, with a stalling memory, and against the emulator, in the way `check_core` of `hdl/Makefile` runs them: every late shift count of MICROARCH.md §7.3 and every reader of a late shift's result; every reader of an adjusted destination, and chains of them; R14 and R15 in every mode as count, source, and destination, after flag writes and after jumps; one register in all three fields with every pair of source modes; stores into fetched code from late and two-cycle instructions; the read counter and `INSTR_LO` around them; and two programs swept with an NMI or an IRQ before each step, 356 runs, judged by `irq_compare.py --read-delay`. All but the `0<0` cases agree. The programs are worth keeping as a hazard program, next to `hazard.nasm`, once the fix is in.

**Resolved**: the programs are in `hdl/test/`, `latecount.nasm` to `shiftjump.nasm`, with `samereg_prog.py` writing the generated one, and `make test` runs each on both cores, plain and on a stalling memory, and `irqhazard.nasm` with a request before each step.

### 1.6 The multi-cycle core, to the same depth

The multi-cycle core is the reference, and `make test` runs everything on both cores, so it had the probes, the hazard programs, the random seeds 1 to 30, the sweeps, and, once they were in, the review's programs. The checks that the pipelined core got beyond that were run on it as well, after the commits of the tests:

- `make -C hdl programs CORE=multicycle`: all 350 programs pass.
- The random seeds 31 to 90, with the generator that now makes shift jumps: all 60 pass on the multi-cycle core, and all 60 on the pipelined core. Seed 89 writes a byte above 0x7F to the console, which crashed `core_runs.py`, since it read the emulator's output as strict UTF-8; it reads with replacement now, and the seed passes on both cores.
- `latecount.nasm` with a request before each of its 155 steps, through `irq_sweep.py` on a stalling memory: 932 runs on the multi-cycle core, with the requests 0, 3, and 7 cycles late, and 1242 on the pipelined core, with 0 to 3 cycles and `--read-delay`, all pass. The program had to keep E = 1 past its R14 section first, since a sweep demands that every request is taken; the review's own sweep had not noticed, as it checked the taken requests only.
- `make -C bench core CORE=multicycle` gives the figures of `bench/README.md` exactly, 19486758 and 5598318 cycles, so the multi-cycle core's rows are current, as the translated program's rows of the pipelined core are (§1.3).

So the multi-cycle core stands where the pipelined core does, and has no finding.

## 2. The documents

### 2.1 ABI.md and WASM.md: "SYSTEM.md ISA §2"

The move of the devices out of ISA.md turned each "ISA §8.4" into a link to SYSTEM.md whose text is "SYSTEM.md ISA §2", with "ISA" left in: ABI.md lines 115, 126 (three times), and 140, and WASM.md line 110. **Fix:** "SYSTEM.md §2", and so on.

**Resolved**: "SYSTEM.md §2", "§1", and "§3" in both files.

### 2.2 SYSTEM.md: the memory map is two tables

In SYSTEM.md, Memory map, a blank line follows the row of the character screen, so the table ends there. The rows from `0xFFFFFF00` on have no header row, and a Markdown renderer shows them as a paragraph of text with bars. Three blank lines also precede the table. **Fix:** one table, or two with a header each, if the screen is to stand apart.

**Resolved**: one table, with one blank line before it.

### 2.3 MICROARCH.md

- **§3** says an instruction is "2.1 words on average in translated code and 1.6 in hand-written code (§5.6)", and **§4** "1.02 micro-ops". The table of §5.6, regenerated on 2026-10-19 by commit 6bab46b, says 1.84, 1.62, and 1.00. **Fix:** the table's figures, or "about two words".
- **§7.4** says three rare cases take WRITE two cycles, "a shift whose count PREPARE could not reduce (§7.3)" among them, and "An interrupt is not taken between the two (§6)". §7.3 says a rotation through C by such a count takes three, and §6 says nothing of it. **Fix:** "two cycles, or three for a rotation through C by a count WRITE must reduce", and say in §7.4 itself that `bound_v` waits, or point at ASSUMPTIONS.md item 6.
- **§5.5** says "in the cycle after a redirect, when the number is stale, no store can retire", and the comment in `pipe_fetch.vhd` line 206 says the same. After a flush by WRITE that is true, since WRITE holds nothing in the next cycle. After a redirect by DECODE it is not: WRITE may hold an older store, stalled by the bus, that the bus accepts in the next cycle. The compare is still right, for another reason: in that cycle FETCH holds no word and has no request on the bus, since `load` was held off by `redirect_i`, so the pair it requests in that cycle is accepted a cycle after the store at the earliest, and sees it (ASSUMPTIONS.md item 8), and the pair's block is the block of `head_r`, which WRITE tests directly. **Fix:** say that, in §5.5 and in the comment. A line in `p_check` could assert it: a store accepted in the cycle after a redirect finds `count_r` = 0 and no live request in FETCH.

**Resolved**: §3 says about 1.8 words, and §4 1.00 micro-ops. §7.4 says a rotation through C takes three cycles, and points at ASSUMPTIONS.md item 6 for the interrupt. §5.5 and the comment in `pipe_fetch.vhd` give the argument above. In place of the line in `p_check`, FETCH proves it for every redirect, with `f_redirect` under `make formal`: in the cycle after a redirect `count_r` = 0 and `drop_r` = `pending_r`, so every request in flight is dropped.

### 2.4 ASSUMPTIONS.md

- **Item 6** says "`w_r.exec_done` and `w_r.cnt_done` mark the second cycle". There is no `cnt_done`; the count's progress is `w_r.cnt_step`, 0 to 2, and a rotation through C takes a third cycle. The line ends in a trailing space.
- **Item 1** has a paragraph indented by six spaces, "Reading the registers and forming the sums in PREPARE ...", followed by three blank lines, which Markdown renders as a code block.

**Fix:** `cnt_step`, "two cycles, or three", and the indentation.

**Resolved**: item 6 names `exec_done` for the first two cases, `cnt_step` for the count, the third cycle of a rotation through C, and `bound_v`, which keeps an interrupt out; item 1's paragraph is indented as the others.

### 2.5 HISTORY.md

- "The code of the translator is about half the size it was" means the translated code; the translator did not shrink.
- "§5 and §9.4 were made to name the two kinds of access": ISA.md §9.4 is now WASM.md, so the sentence should say so, as this file is where old numbers are allowed.
- The Benchmark section says `bench/` went "from about 5.55 to about 2.27 million cycles by `bench/pipecycles.py`". The model says 2.20 million (`bench/README.md`); 2.28 is the core's figure.

**Fix:** the three sentences.

**Resolved**: "the code that the translator writes", a sentence that §9.4 is WASM.md now, and 2.20 million cycles by the model, with the core's 2.28 beside it.

### 2.6 The slides

`doc/intro/nice_intro.tex` line 917: "A C compiler that targets NICE directly would be great, too. The calling convention for one is already in `doc/ISA.md`." It is in `runtime/ABI.md` since commit d07a0a0. **Fix:** the file name, and `make pdf`, since `make pdfcheck` compares the PDF with the text.

**Resolved**: `runtime/ABI.md`, and the PDF rebuilt.

### 2.7 Smaller ones

- `translator/README.md` lines 632, 654, and 658 say a taken conditional jump "costs some five cycles more" than a skipped one on the FPGA core. It costs six (§1.2), and the model charges seven.
- `hdl/README.md`, The pipelined core, names the third two-cycle case "a shift by a count from memory". MICROARCH.md §7.3 lists five more kinds of count that WRITE must reduce.
- TODO.md, under "Faster and smaller translated code", asks that "MICROARCH.md §5 could state this stall in so many words" for the address register written by the instruction before. §5.1 has stated it since the re-timing.
- `hdl/test/tb_shift.vhd` says it checks "counts near the multiples of 33 up to 2^32"; its loop runs to m = 41, so to 1353, and the top of the range is covered by the loops over `0xFFFFFFFF − i` and `0x80000000 + i` instead. The loop `for m in 1 to 130150523 ... exit when m > 40` could be `for m in 1 to 41`.
- The nine stale references of §5.1 in `doc/review/`, which cite ISA.md §8.4, §8.6, and §9.4 as they were on their dates. The notes are history, so a sentence in REFERENCES.md that they cite sections as numbered then is enough.

**Resolved**: `translator/README.md` and the two docstrings of `nicewasm.py` that said the same say six cycles, and a loop's round saves three; `hdl/README.md` names the counts that PREPARE cannot reduce and the third cycle of a rotation through C; `tb_shift.vhd` loops to 41 and its header says what it covers. The sub-item of TODO.md went with the review's commit, and the sentence in REFERENCES.md with `check_refs.py`.

### 2.8 The diagrams of §3 and §6

The block diagram `pipeline.png` and its text twin in §3 show the stages, the three paths through DBUS, the registers PREPARE reads from WRITE, the early redirect, and the flush as the code has them, and the registers the header of `pipeline.tex` names, `req_r`, `stb_r`, `ring_r`, `dec_r`, `prep_r`, `rd_stb_r`, `rd_addr_r`, and `w_r.uop`, all exist and sit where the bars are. Two small things: DECODE has held a second instruction, `dec_q`, since the re-timing, which the header's list does not name, and the flush arrow ends at FETCH while the header says the flush reaches every stage.

The timing diagram `interrupt.png` was read off the core before the re-timing. On the re-timed core, with the instrumentation of a scratch copy printing its sixteen signals once per cycle for `irqwave.nasm`, every signal in both panels still matches, cycle for cycle, from the panels' start cycles 9 and 32 on, but one: `target_o` in the cycle of the take. WRITE now puts the next instruction's address there, `u_v.inst.next_pc`, where the old core put the dropped instruction's: 0014 in place of 0012 at t = 2 of panel (a), and 0020 in place of 001E at t = 4 of panel (b). FETCH never fetches from it, since it stops during the vector read and is redirected to the routine with the entry, so the core is right and the two values are stale. **Fix:** the two values in `interrupt.tex`, a sentence in its header that the target of the take is the next instruction's address, which FETCH never fetches, and `make diagrams`.

**Resolved**: `interrupt.tex` shows 0014 and 0020, and its header says that the target of the take is the next instruction's address, which FETCH never fetches. `pipeline.tex` names `dec_q` and draws the flush into DECODE and PREPARE as well, below the jump and above the register path, so that no lines cross. Both are rendered again.

## 3. The cycle model, bench/pipecycles.py, and bench/hazards.py

### 3.1 The bubble after a jump taken in WRITE

`bench/README.md`, The cycle estimate, and the docstring of `pipecycles.py` explain the model's `--flush 7` as the core's timing: "A jump leaves WRITE in cycle c − 1, and WRITE's registered flush redirects FETCH in cycle c", and then one cycle each for the request, the bus, the memory, DECODE, its micro-operation, and PREPARE, "7 cycles after a fall-through would have run". The flush is not registered: `flush_o` of `pipe_write` is combinational, `pipeline.vhd` feeds it straight into FETCH's `redirect_i`, and ASSUMPTIONS.md item 2 says a flush "reaches every stage at once". The measurement of §1.2 gives 6, for an aligned target and for one that spans two pairs alike. The model gives the same programs 16 and 9 cycles for the taken jump and the fall-through, 7 apart.

The second review found that 7 "halves the error" of the model against the core on the benchmark, so the extra cycle stands in for something the model lacks, not for the flush. One candidate is §3.3; another is the instruction after the target, which must wait for its own pair while FETCH refills. **Fix:** say in the README and the docstring that the core's bubble is 6 and that 7 is the value that fits the benchmark, or find the missing cycle and model it. The hand-counted cases of `pipecycles.py --test` and `cycprof.py --test` encode the 7, so they change with the choice.

### 3.2 Jumps that DECODE resolves, and computed jumps

`hazards.py` calls a jump early, that is, resolved in DECODE, when it is unconditional, writes R15 in mode 000, and reads no memory (`early_jump`). The core resolves only `MOVE R15, c` and `ADD R15, R15, c` in DECODE (MICROARCH.md §5.4, `pipe_decode.vhd`); `MOVE R15, R3`, `ADD R15, R3, 0`, and every other register jump cost the full bubble of §1.2. The model takes `early` from the same decode, so it charges such a jump 2 cycles and not 6, and the row "jump that DECODE resolves" of `make hazards` counts it. In the same decode, `jump_kind` is "computed" for every jump that WRITE resolves but a `MOVE` of a constant or of a memory word, so `MOVE R15, R3` is charged the second cycle of `--dest-adjust`, which the core does not take (§1.2, MICROARCH.md §5.4: "The target of `MOVE R15, x` is the source itself"). The model gives `MOVE R15, R3` and `ADD R15, R3, 0` 12 cycles each, where the core takes 9 and 10 between the counter reads.

In the benchmark this changes little: the translated program has no such jump, and `hand.nasm` has six. **Fix:** in `hazards.py`, early only for the two forms DECODE takes, and "computed" only for an operation other than `MOVE` or for `MOVE` with a side effect on R15; the model follows.

### 3.3 A shift count through an adder

MICROARCH.md §7.3 lists the counts that WRITE reduces in a cycle of its own: from memory, through an adder (`R − 1` or `c[R]`), from the register the micro-operation before writes or from R14, with a side effect, and a rotation through C by a register. The model charges the first (`--shift-mem`) and waits for the third (`--shift-reg`), and nothing for a count through an adder. `hazards.py` counts a count in mode 011 with a register as "a register". The translator's signed byte loads rotate by exactly such a count, `ROR d, @___wasm_memory[w], 8[c]` (`translator/README.md`, "A signed load rotates the bytes up to bit 31 instead, by `8[c]` or `16[c]`"), five times in `bench.nasm`, and the trace runs them 4175 times. So the core spends 4175 cycles that the model does not charge, 5% of the 76396 by which it is below the core, and the sentence of HISTORY.md that "the byte loads no longer wait" holds for the unsigned ones only.

**Fix:** a rule for a count in mode 001 or 011 with a register, charged like `--shift-mem`, and a row for it in `hazards.py`. The translator could also avoid it: `ROR d, word, c` and then a shift by the constant, one instruction more, or a second count register formed before the compare, which costs a register. The model, with the rule, would say which is cheaper.

### 3.4 The defaults of the four rules

The docstring of `pipecycles.py` says the four rules of the re-timed core are "each off (0) by default", and the help of `--shift-mem`, `--shift-reg`, `--sum-wait`, and `--dest-adjust` ends in "(0)". Their default is 1, in `Model.__init__` and in `argparse`, as `bench/README.md` says: "Four options, each 1 by default". **Fix:** the docstring and the four help strings.

**Resolved**: the docstring says each is 1 by default, and 0 turns one off, and the four help strings end in "(1)".

### 3.5 Two counts of one trace

`make hazards` says `bench.bin` runs 1775455 instructions and `make cycles` 1775661, from the same trace. `profile()` in `hazards.py` takes a trace line only when its first two words are the address and the instruction word, and `run_model()` in `pipecycles.py` also searches for them later in the line, where the console's output of the program precedes them, since the emulator writes both to stdout. The benchmark prints 206 characters that are not followed by a newline, and `hazards.py` drops the instruction after each. The shares of MICROARCH.md §5.6 are not affected at this size, but the two tools should read a trace the same way. **Fix:** one parser in `hazards.py`, used by both.

**Resolved**: `hazards.steps()` reads a trace for both tools, and finds a step or an interrupt entry after console output on its line. Both now count 1775661 instructions for `bench.bin`, the emulator's count, and 494272 for `hand.bin`, not 494070; the table of MICROARCH.md §5.6 has the new counts, and one share moved, a store in `hand.nasm`, 15.5%.

## 4. The translator

### 4.1 Multiplication by a constant, tuned to a multiplier that is gone

`nicewasm.py` turns an `i32.mul` by a constant into up to `MUL_STEPS` = 8 shifts, additions, and subtractions, and the word products of an `i64.mul` by a constant into up to `MUL64_STEPS` = 16 each, "while the math unit computes" the first. The comments at both constants, and `translator/README.md` lines 202 and 211, justify the budgets with a product that "comes some 35 cycles after the operands on the FPGA core". Since commits b018cbd and dd81315 of 2026-10-16 the multiplier takes two cycles, and a product can be read three cycles after the operand write (`bench/README.md`, The cycle estimate). So eight instructions now cost more than the three of the math unit and its wait, and the sixteen steps of each cross product of an `i64.mul` no longer hide behind anything.

By the cycle model, on the benchmark:

| `MUL_STEPS` | Instructions in the phases | Cycles, model |
|---|---|---|
| 8 (today) | 1730635 | 2199014 |
| 4 | 1717945 | 2195129 |
| 2 or 0 | 1717944 | 2194173 |

The difference is 0.2% of the cycles and 0.7% of the instructions, in `bst`, `heapsort`, and `strings`. `rng64`, whose loop is an `i64.mul` by `0x2545F4914F6CDD1D`, runs 28 shift and add steps beside one product of the math unit; with `MUL64_STEPS` = 0 it calls `__mul64` instead and takes 6% more cycles, so the inline code is still the better of the two that exist, but three products of the math unit, about 18 cycles, would beat its 28 steps. **Fix:** say in the comments and the README what the math unit costs now, set `MUL_STEPS` to 2 or 3, and let `mul64_const` use the math unit for the cross products too, measured with `make cycles` and then `make core CORE=pipeline`.

## 5. Tests and CI

### 5.1 A check of the section references

The script that found the nine stale references in `doc/review/` reads every `FILE.md §n.m` in the repository and checks the section against the headings of that file. It found none outside `doc/review/`, which shows the moves were done with care, but ABI.md's six "SYSTEM.md ISA §2" are the kind of slip it does not see, and the next move will make more of both. **Fix:** a small script under `doc/`, run by the top-level `make test`, that checks the section references, the relative links, and the anchors of every Markdown file in the repository, and that accepts the old numbers in `doc/review/` or a list of exceptions. The review's script is a start.

**Resolved**: `doc/check_refs.py`, run by `make -C doc test` and so by the top-level `make test`, checks the section references in every tracked file but the review notes, and the file and the heading of every link in every Markdown file. It found nothing more at this commit.

## What is correct

- `make test`, `make typecheck`, `make -C hdl lint`, `make pdfcheck`, and `make -C hdl formal` pass at 69405dd, and CI passes on `main`.
- The re-timed pipelined core passes the 350 programs of `make -C hdl programs CORE=pipeline`, and every rule of ISA.md §3 to §8 that I read against it holds (§1.1), but for the `0<0` of §1.4. The flush, the store compare, the two-cycle cases, and the early redirect behave as MICROARCH.md §5.4, §5.5, and §7.4 describe, and the measured bubbles are those of §1.2.
- The translator at 69405dd agrees with its version at aa8a512 on 360 random modules in six modes, traps included.
- Every section reference outside `doc/review/` points at a section that exists, and every `ISA.md §8.4` to `§8.6` and `§9.4` in code and documents was renamed.
- The new tests do what their headers say: `tb_shift` checks `shift_fast` against `shift` for every operation and the counts that matter, `smc_prog.py` stores 1 to 40 words ahead and checks itself, `passes.py` reaches the three rules no module reaches, and `diff_fuzz.py` compares the console, the halt, the registers, and the memory.
- The emulator's new `--input` checks, the timer test with the vector kept, and the README's memory map agree with SYSTEM.md.
