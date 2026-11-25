# Fifteenth review of the repository, at commit 2f6eca7

Reviewed on 2026-11-25: the 47 commits between `V2.6` and the head of `dev-V3.0`, commit 2f6eca7 ("nicewasm: long calls across a large memory"), before the release `V3.0`. They remove the interrupts (#162): IRQ, NMI, `INT`, `RTI`, `WAIT`, the vector table, the timer, and the console's receive interrupt, in the specification, the tools, both cores, and the documents, with the debug link at version `0x10`. And they add `JMP`, `JMPR`, and `CALL` as control instructions of one word (#192), which makes every translated program 17% to 20% shorter and moves most of the figures that the documents quote. This review looks at the documents: what they say that is not so, and what they leave out.

**How it was checked.** Each document that says what is true now was read whole, not only its diff, and its statements checked against the code, a test, or a run. I read ISA.md, the assembler's README, the top-level README, CONTRIBUTING.md, CLAUDE.md, TOOLCHAIN.md, the two new sections of HISTORY.md, decisions.md, and the release documents, with probes of niceasm, nicedis, and niceemu for the rules of ISA.md §5.3 and §10.1, and the issues #162, #192, and #196 beside HISTORY.md. Three fork agents read the rest, each in a scratch copy of the tree: the documents of `hdl/` with MICROARCH.md; the READMEs of the emulator and the debugger with DEBUG.md and DEVICES.md; and the documents of the runtime, the translator, the benchmarks, and the demo with the slides, where the work was to measure each figure again. I checked each of their findings against the tree, or by a run of my own, before it went in here.

On the unchanged tree, in the scratch copies, these ran and pass: `make test` in `hdl/` (408 lines of `PASS` in 4 minutes 18 seconds), the emulator, the debugger, the runtime, the translator, `bench/`, the demo, `doc/`, and `doc/intro`, `make pdfcheck`, `make wasmcheck`, `make diagrams`, which renders both PNGs byte for byte as committed, `release.py figures`, 39 of the 41 tasks of `make formal`, and `make -C bench core`, `core-dhry`, and `core-coremark` on the pipelined core in nvc. CI passed all 15 jobs on the head. I asked GitHub for the state of each issue of NiceMonMEGA65 that the documents cite, compared the board's tags with the table of RELEASE_NOTES.md, and ran `release.py preflight`. Not run: Vivado, so the timing is compared with the commit messages only (§1.5), the benchmarks on the multi-cycle core, and the window on a display.

## Summary

**The release steps are open**, as expected before the tag (§1). `dev-V3.0` is one commit behind `origin/main` (§1.1), RELEASE_NOTES.md has no section for `V3.0` (§1.2), its table of board tags lacks four tags (§1.3), `emulator/build.zig.zon` says `2.6.0` (§1.4), the timing figures of hdl/README.md are from before both changes to the core (§1.5), and #208, a stale sentence of DEVICES.md §8, is open with no milestone (§1.6).

**The interrupts are gone from the documents.** ISA.md, DEVICES.md, DEBUG.md, MICROARCH.md, and the READMEs describe a processor without them, the section numbers that other places cite still hold, and no reference points at a section that went. A dozen words are left over (§2.9), among them "the halt reasons 2 to 4" of hdl/README.md and "or waiting" of DEVICES.md §10.

**The one-word jump and call are not yet everywhere.** ISA.md, the assembler, MICROARCH.md §5.4, and the tables of bench/README.md are right. These are not:

- **README.md's worked example** shows the output of `V2.6`: the string moved from `0x12` to `0x11`, so one register, two trace lines, and the memory dump are wrong (§2.1).
- **The slides** teach a control class with `HALT` alone, a control word with a `vector` field, and an R13 that the hardware treats like any other register (§2.2).
- **DEVICES.md §3** defines the jump counter and the store counter without the one-word forms, which the emulator and both cores count (§2.3).
- **hdl/README.md** describes DECODE's early redirect without them, in two places, and so do three comments of `pipe_decode.vhd` (§2.4).
- **Sixteen figures** are stale, most of them from before #192, in translator/README.md, DESIGN.md, bench/README.md, MICROARCH.md, hdl/README.md, decisions.md, and runtime/README.md (§2.5).

**Five things are in no document** (§4): what NiceMonMEGA65 up to its `V2.6` does with a program or a debugger of `V3.0`, why the commands 1 to 3 stay reserved, what #162, #192, and #196 decided against, that a hand-written file joined after a large memory must jump with the long form, and that `nicedis` does not name a jump's target below address 16.

**Older errors were found in passing** (§3), none of them of this release: a port and a generic of the debug link that do not exist, a sentence of DEBUG.md §1 that says the opposite of DEVICES.md §1.5, an issue that MICROARCH.md calls open and that was closed on 2026-11-05, and some counts.

No finding is in the behavior of a tool or a core. Two are at the edge: `nicedis` and the target below 16 (§4.5), and `tb_perf`, which has no one-word jump (§2.3). Nothing here is fixed, and no issue is filed.

## 1. The release

### 1.1 `dev-V3.0` is one commit behind `origin/main`

`origin/main` is at 6b5e2a8, "Update RELEASE_NOTES.md", of 2026-11-25, which puts the board's `V2.6` into the table of board tags. `dev-V3.0` forks from 72fbc75, the tag `V2.6`, and the local `main` is there too. A release starts by moving `main` forward to the release's branch, and `release.py preflight` needs `HEAD` to be `origin/main`:

      FAIL HEAD is origin/main (2f6eca7 against 6b5e2a8)

`dev-V3.0` does not touch RELEASE_NOTES.md, so a rebase onto `origin/main` has no conflict. It rewrites the 47 commits, which are pushed, and CI must pass again on the new head (RELEASE.md §6).

**Fix:** rebase `dev-V3.0` onto `origin/main` before the fixes of this review, and push it.

### 1.2 RELEASE_NOTES.md has no section for `V3.0`

The newest section is `V2.6`. RELEASE.md step 2.8 asks for the section, and for a row `V3.0`, "none yet", in the table of board tags. `release.py notes` drafts it under the heading `V2.7`, the next minor version, so the name is given by hand, and to `release.py tag V3.0` too. The upgrade notes must say at least:

- **NICE has no interrupts** (#162): no IRQ, no NMI, no `INT`, `RTI`, or `WAIT`, no vector table, and no hidden state but `halted`. ISA.md §7 says why, and what polling costs. A program that used them polls. `RTI`, `INT`, and `WAIT` are errors in niceasm, and stay reserved words.
- **SR bits 31, 30, and 23..0 are F1, F0, and U**, storage for software. The conditions are `?F1` and `?F0`, niceasm still takes `?I`, `?E`, and `?M`, and nicedis prints the new names. The hardware no longer writes bit 31.
- **`JMP`, `JMPR`, and `CALL` with an address are one word** (#192), the control commands 4, 5, and 6, with a signed distance of 21 bits from the next instruction. A target out of reach is an error in niceasm, and the source then writes the long form. So every label after a jump or a call moves down, and a program that counts on the size of a jump must change: a table of `JMP label` entries has one word an entry, where it had two, and code that reads or patches the constant word of a jump writes `MOVE PC, label`. `JMPR label` is no longer `ADD PC, PC, offset`.
- **`CALL` pushes through R13**, which the hardware gave no meaning before. A call of a label is one step, where it was two, so the expected step count of a program falls by one for each such call.
- **Old and new binaries.** A `.bin` file of `V2.6` that has no `RTI`, `INT`, or `WAIT` runs unchanged, as the long forms are ordinary instructions. One that has them halts there, with "reserved control instruction", as the commands 1 to 3 stay reserved for that (§4.2). A `.bin` file of `V3.0` halts on an emulator or a core of `V2.6` at its first `JMP`, `JMPR`, or `CALL`. So NiceMonMEGA65 up to its `V2.6` runs no program that `V3.0` assembles (§4.1). The board's side is MJoergen/NiceMonMEGA65#169 and MJoergen/NiceMonMEGA65#172.
- **The devices.** The timer at `0xFFFFFF10`–`0xFFFFFF1F` and the console's receive interrupt at `0xFFFFFF02` are gone, and their words are reserved: ordinary memory in the emulator. The interrupt counter is gone, and `0xFFFFFF52` and `0xFFFFFF53` read 0. DEVICES.md keeps §1.9 and §4 as short sections, so that the other numbers hold.
- **niceemu.** `--irq`, `--nmi`, and `--no-timer-irq` are unknown options. The trace has no interrupt entries, and the report no pending requests. A halt is `HALT`, a reserved control word, or the step limit. `TIME_SKIP` has no early end. The version is 3.0.0.
- **The debug link is version `0x10`**, a new major. The registers `0xFFFFFFD0`, `0xFFFFFFD1`, and `0xFFFFFFD7` read 0 and take no write, bits 6 to 10 of the control register read 0, and the halt reasons 3 and 4 do not occur. A host of version 8, such as nicedbg of `V2.6` or a board's tools, stops on it, and the tools of `V3.0` stop on a system of major 0, such as the board up to its `V2.6`. nicedbg has no `nmi`.
- **nicewasm.** The output's jumps and calls are one word. From a memory of 2¹⁹ reserved words on, 32 pages, a jump or a call to a label outside the module keeps the long form (§4.4).
- **The figures.** Words: `bench.c` 11878 to 9869, Dhrystone 20886 to 16797, CoreMark 30648 to 25235, and `float.c` 10550 to 8632. Cycles on the pipelined core: `bench.c` 2351494 to 2341190, `hand.nasm` 1252613 to 1247655, Dhrystone 2278 to 2253 a run, and CoreMark 1078661 to 1068822 an iteration.
- **`hdl/`.** Both cores lose the NMI and IRQ ports, `waiting_o`, `wstep_o`, and the hidden state. `timer.vhd`, `console_irq.vhd`, and `irq_merge.vhd` are gone, and so are the ports of `debug_link.vhd` for the wait, the hidden state, the pending requests, and the NMI request. The performance counters have no interrupt counter, the fetch statistics four flush causes, and the retire log the cycle causes a to n. `make sweep` and `make strides` are gone, and `make -C hdl test` takes 5 minutes, where it took 13. The timing, with the figures of §1.5.
- **The demo's self-test has no timer test**, and its image changes, so a board that keeps the demo in its ROM builds the ROM again.
- **The slides** have `poll.nasm` in place of `irq.nasm`.
- Zig stays 0.17.0.

**Fix:** write the section, with the line "The version is 3.0.0." under the emulator's heading, and the row of the table.

### 1.3 The table of board tags lacks four tags

The table at the top of RELEASE_NOTES.md gives the tags of NiceMonMEGA65 that pin each tag here. The board's tags, each with the tag that `git ls-tree <tag> nice_cpu` gives:

| nice_cpu | NiceMonMEGA65's tags | The table on `dev-V3.0` |
|---|---|---|
| `V2.6` | `V2.6` | none yet (6b5e2a8 on `origin/main` has it, §1.1) |
| `V2.5` | `V2.5`, `V2.5.1` | `V2.5` |
| `V2.4` | `V2.4`, `V2.4.1` | `V2.4` |
| `V2.2` | `V2.2`, `V2.2.1` | `V2.2` |

The other rows are right.

**Fix:** add `V2.5.1`, `V2.4.1`, and `V2.2.1`, with the row of `V3.0`.

### 1.4 `emulator/build.zig.zon` says `2.6.0`

RELEASE.md step 2.9: the version is the new tag's, `3.0.0`, and `release.py tag` and the release workflow refuse a tag that it does not match. Set it before `release.py check`.

### 1.5 The timing figures are from before both changes to the core

RELEASE.md step 2.4 asks that the timing quoted in hdl/README.md is what the release measures. Its table of `make timing-spread` is "at 565b976 (#151)", of `V2.1`, and `SPREAD` of `hdl/test/timing_budget.py` is from the same run. Both changes to the core of this release measured it again, and the figures are only in the two commit messages, 833f2cd and aefdaf3:

| MEGA65, `default` flow | Core | Inputs | Outputs | Budget met |
|---|---|---|---|---|
| hdl/README.md, at 565b976 | 0.111, 0.396, 0.708 ns | 1.869, 2.251, 2.559 ns | 1.554, 2.357, 2.963 ns | 4 of 7 |
| After #162 (833f2cd) | 0.013, 0.350, 0.568 ns | 2.208, 2.929, 3.439 ns | 1.299, 2.092, 2.681 ns | 2 of 7 |
| After #192 (aefdaf3) | −0.005, 0.255, 0.434 ns | 1.741, 2.379, 2.996 ns | 0.709, 2.246, 2.597 ns | 4 of 7 |

The medians move by less than the ranges of `SPREAD`, so by CONTRIBUTING.md neither change counts. But the median of the core's slack is 0.141 ns lower than the table says, and one variant, 2 breakpoints and 4 watchpoints, misses 10 ns by 5 ps. The row of the `timing` flow was not measured again. Vivado was not run for this review.

**Fix:** run `make -C hdl timing-spread` on the release's commit, with `FLOW=timing` too, and replace the table and `SPREAD` together. The release notes say that one variant of seven missed by 5 ps, if it still does.

**Resolved.** `make -C hdl timing-spread` ran in both flows on 2026-11-25, on the tree with the fixes of this review, which change only comments in `hdl/src`. The `default` flow gives the figures of aefdaf3 again, to the picosecond, and the `timing` flow gives the core 0.079, 0.165, and 0.551 ns, the inputs 1.463, 2.143, and 2.735 ns, and the outputs 1.290, 2.251, and 2.770 ns, with the budget met in 4 of 7. hdl/README.md has both rows, and `SPREAD` their ranges. The variant of the boards, 4 breakpoints and 4 watchpoints, which `make timing` and `release.py check` run, meets the budget in the `default` flow, with 0.291 ns for the core, and misses it at the outputs in the `timing` flow, by less than one run varies. The table of what a system may add to `dbus_ack_i` and `instret_o` is measured again too, on both boards: the ACK has 3.0 ns or more on the MEGA65, where it had 1.7. The FPU is unchanged: 0.424 ns, as hdl/README.md says. The notes of `V3.0` say what missed (§1.2).

### 1.6 #208 is open, with no milestone

DEVICES.md §8, **Font**: "Its ROM does not have the blocks and arrows of §1.8 at `0x80`–`0x99` yet, so `0xFFFE3000` reads 0 there (MJoergen/NiceMonMEGA65#171)." The board's issue was closed on 2026-11-23, and its `V2.6`, tagged on 2026-11-24, has the glyphs. #208 says so and gives the new sentence. It was filed after `V2.6` and has no milestone, so the milestone `V3.0`, which is empty, does not show it.

`release.py preflight` does not warn of the sentence (§4.8).

**Fix:** change the sentence as #208 says, in this release, and close the issue with it.

## 2. What the documents say that is not so, since `V3.0`

### 2.1 README.md: the worked example shows the output of `V2.6`

`doc/intro/examples/hello.nasm` ends its loop with `JMP PUTS`, since 648aaee. Then a `JMP` was `MOVE PC, label` in two words, so the README's copy, which says `MOVE PC, PUTS`, assembled to the same words. Now the `JMP` is one word, and `TEXT` is at `0x11`, not `0x12`. Run as the README says:

| README.md | Shows | The tools give |
|---|---|---|
| The listing, last line of `PUTS` | `MOVE    PC, PUTS        ; and loop` | `JMP     PUTS            ; and loop` |
| The report | `R1  0000001f` | `R1  0000001e` |
| The trace, second line | `00000002 00005800 R1=00000012` | `R1=00000011` |
| The trace, fifth line | `0000000c 0200b080 R1=00000013 R2=00000048` | `R1=00000012 R2=00000048` |
| `--dump 0x12:16`, "the string at `TEXT`" | `00000012: 00000048 00000065 …` | `00000012: 00000065 0000006c …`: the dump starts at the `e` |

The 56 steps, the PC of `0xc`, and the return address 8 still hold. 90ef260 moved the same addresses in the slides and their expected files.

The second example quotes `keys.nasm` the same way: `?Z MOVE PC, KEY`, `SUB[M] R0, R2, 13`, and `?Z MOVE PC, DONE`, where the file has `?Z JMP KEY`, `CMP R2, 13`, and `?Z JMP DONE`.

**Fix:** copy the two listings from the files, the three outputs from the tools, and dump `0x11:16`. A check would keep them (§4.8).

**Resolved.** The README's listing is `hello.nasm` as it is now, with `CALL PUTS` and `?Z RET` (§4.6), and its report, its trace, of four steps, and its dump of `0xe:16` are what the tools print. The snippet of `keys.nasm` is as in the file. `doc/check_readme.py` now compares both worked examples with the files and the tools, in `make -C doc/intro test` (§4.8): it fails on the README of 2f6eca7 in five places.

### 2.2 The slides: the control class of #162, not of #192

ea1e2e1 took the interrupts out of the slides, and 8e02935 changed the slides on jumps and calls for #192. Four other slides still describe the control class as #162 left it, and the slides contradict themselves: "`JMP LOOP` … in one word" and "`CALL ROUTINE` is one word" are further on.

| `nice_intro.tex` | The slide says | ISA.md |
|---|---|---|
| Lines 59–60 | "16 ALU operations, 16 shifts, and 3 control instructions" | Four: `HALT`, `JMP`, `JMPR`, and `CALL` (§5.3). Three was `HALT`, `RTI`, and `INT`. |
| Lines 80–81 | "`R13`: The stack pointer (`SP`), by convention only. The hardware treats it like any other register." | "The one-word `CALL` pushes the return address through it" (§1.2). |
| Lines 190–194 | The control format has bits 20..8 `0` and bits 7..0 `vector`. | Bits 20..0 are d, or 0 (§2.1). There is no vector. |
| Lines 353–366 | "The control class has one command", a table with `HALT` alone, and "All other commands are reserved. They halt the processor." | Commands 4, 5, and 6 are `JMP`, `JMPR`, and `CALL` (§5.3). |

**Fix:** four control instructions, R13 as ISA.md §1.2 has it, one field `d` in bits 20..0, and a table of the four commands with their words. Then `make -C doc/intro pdf`.

**Resolved.** The slides say 4 control instructions, give R13 as ISA.md §1.2 has it, show the control word with the one field `d` in bits 20..0, and list the four commands with their words and the reach of `d`. The PDF is rebuilt.

### 2.3 DEVICES.md §3: the jump counter and the store counter

"The **jump counter** counts the instructions that are not skipped and write R15: as their register destination, in mode 000, 001, or 010, or by the side effect of a field, in mode 001, 010, 101, or 110 (ISA §4)." A one-word `JMP`, `JMPR`, or `CALL` has no operand field, and is counted: `writesR15` of `cpu.zig` returns `isShort(iw)` for a control word, and `writes_r15` of `nice_pkg.vhd` does the same for both cores. On the emulator, a `JMP`, a `CALL`, a `RET`, and a `JMPR` leave `JUMP_LO` at 4. `events.nasm` relies on it.

"The **store counter** counts the destination writes of ISA §8.2." ISA.md §8.2 lists the push of `CALL` apart from the destination writes, and the push is counted: `STORE_LO` reads 1 after a `CALL` and no other store.

hdl/README.md says of `tb_perf` that it checks "a jump but not one that halts or a control word". The control word of `tb_perf` is `0C400040`, a reserved one, and it has no one-word jump. `formal_perf` covers the commands 4 to 6.

**Fix:** "or as a one-word `JMP`, `JMPR`, or `CALL` (ISA §5.3)" for the jump counter, "the destination writes, and the push of `CALL`" for the store counter, and "a reserved control word" in hdl/README.md, with a `JMP` in `tb_perf`.

**Resolved.** DEVICES.md §3 says that the jump counter counts a one-word `JMP`, `JMPR`, or `CALL` too, and that the store counter counts the data writes of ISA §8.2, the destination writes and the push of `CALL`. `tb_perf` steps the three one-word forms, and a skipped `JMP`, and checks 4 jumps and 3 skips. hdl/README.md says so, with "a reserved control word".

### 2.4 hdl/README.md: DECODE's early redirect

The table of the stages says of DECODE: "Redirects FETCH at once for `MOVE R15, c` and `ADD R15, R15, c` with condition "always", and for a conditional `ADD R15, R15, c` with a negative `c`." The formal checks say that DECODE "redirects FETCH only as it takes `MOVE R15, c` or `ADD R15, R15, c`". Since aefdaf3 it also redirects for the `JMP` and the `CALL` of one word with the condition "always", and predicts a `JMPR` of one word with a condition that goes back: `early_form(...) or short_early(iw_v)` in `pipe_decode.vhd`. MICROARCH.md §5.4 and the header of `pipeline.vhd` have it. Three comments of `pipe_decode.vhd` do not, at lines 8, 345, and 404, and the comment of `uop_wreg` in `pipe_pkg.vhd` says that control instructions "write R14 and R15 in other ways", where the function now returns 13 for a call and 15 for a jump.

**Fix:** name the jump and the call of one word, and the predicted `JMPR`, in the two places of the README and the three comments, and correct the comment of `uop_wreg`.

**Resolved.** The table of the stages and the account of DECODE's proof in hdl/README.md name the jump and the call of one word, and the `JMPR` that DECODE predicts. So do the three comments of `pipe_decode.vhd`. The comment of `uop_wreg` says that it gives R15 for a jump of one word and R13 for a call. Only comments change in `hdl/src`.

### 2.5 Sixteen stale figures, most from before #192

The commits 946ea08 to a9df48d changed the figures by hand, place by place. These were left, and each was measured again on the head:

| Place | Says | The tree gives |
|---|---|---|
| translator/README.md, `--inline-fpu` | "2.5% more words, and runs 53% fewer instructions, and 42% fewer cycles" | 9060 words against 8632, 5.0% more; 84393 instructions against 169542, 50% fewer; 354930 cycles against 600538, 41% fewer. bench/README.md and DEVICES.md §11.5 have these. |
| translator/README.md, the speed flags | "23% fewer words … by `pipecycles.py` at 889c202 … 48% fewer words" | 9625 words, 7589 with `--trust-alignment --byte-windows`, 21% fewer, and 5445 with `--no-bounds-checks` too, 43% fewer. The cycles, 13% and 22%, hold. No target builds these, so the method is in no file. |
| translator/README.md, `safe.zig` | "about 11900 built with Debug" | 8990 |
| translator/README.md, the traps | "So a trap takes four words, not six." | Three: `MOVE R2, label` and a `JMP` |
| translator/DESIGN.md, the cold stubs | "Such a stub takes some 10 words" | 5 or 6 |
| bench/README.md, the words | "3052 of the benchmark's words are the float conversions of `printf`" | 2578, as runtime/README.md and translator/README.md say |
| doc/review/decisions.md, the split of `printf` | "saves 3052 words with `iprintf`" | 2578 |
| bench/README.md, the sample of `make hazards` | "for `hand.nasm` at commit 98d2bed": 493964 instructions, words "1: 35.6%  2: 63.1% … mean 1.66" | 491363 instructions, "1: 50.7%  2: 47.9%  3: 1.3% … mean 1.51", and each line after it |
| bench/README.md, the ratio of `strings` | 5.0 | 100207 / 20321 = 4.9. The other six ratios hold. |
| MICROARCH.md §3 | "about 1.86 words on average in translated code and 1.66 in hand-written code (§5.6)" | 1.68 and 1.51, as the table of §5.6 itself says. "About one instruction per two cycles" no longer follows. |
| MICROARCH.md §5.3 | "at ffd0a16 … waited 146 cycles … 0.006% … 269 cycles for their condition and 2002 for an older micro-operation, 0.18% … at most 0.18%" | 80 cycles, 0.003%, and 269 and 0, 0.02%, as bench/README.md says, which cites this section for them. HISTORY.md says that the 2002 went to 0. The 52002 dropped reads, 4.1%, hold. |
| hdl/README.md, the pipelined core | "`hazard.nasm`, which is all hazards, 1.9" and "`strings` (2.4)" | 634 cycles for 307 steps, 2.1, and 47406 for 20321, 2.3 |
| hdl/README.md, `make programs` | "it makes 911 programs and runs 643 of them … with some 9 million steps" | 920, 649, and 8.4 million. CI on the head: "649 of 649 …, and 271 the same as one of them". |
| hdl/README.md, twice | CI runs `make programs` in "13 minutes on 2026-11-14" on each core | 14.5 minutes on the pipelined core and 23.6 on the multi-cycle one, in the run on the head |
| runtime/README.md, Math functions | `fmin` and `fmax` "take 75 and 73 steps, and 52 and 51 in float" | 2 fewer each. The table of steps above it moves too, which #205 has, with the sizes: 1 fewer in most rows, 2 for `sin`, `cos`, and `tan`, and 4 for their float forms. |
| translator/README.md, Tests | "built with rustc 1.99.0" | 1.99.1, since 33f688f rebuilt them. Older than `V3.0`. |

`release.py figures` checks two figures of bench/README.md, and with `make slow` two more. It sees none of these (§4.8).

**Fix:** the figures of the third column. For the speed flags, give the commands or a target, and drop the commit.

**Resolved.** Each place has the figure of the third column. For the speed flags, `words.py` takes nicewasm's options with `--options`, `make -C bench words` prints the two sizes, 7589 and 5445 words, and bench/README.md gives the command for the cycles, 2047068 and 1833670 in the six phases, so translator/README.md names no commit. The sample of `make hazards` is today's, and names no commit either. MICROARCH.md §3 says one instruction in 1.5 to 1.7 cycles. The steps of the math functions stay those of 2026-11-16, and the text now says that a call took two steps then, so that each figure is 1 to 4 steps high: #205 measures the table again. Found on the way, and corrected too: decisions.md gave `lib.nasm` 131 words and `float_fpu.nasm` 483, which are 107 and 400.

### 2.6 bench/README.md: `JMPR`, and what DECODE resolves

"A conditional jump back that is mostly taken, such as a loop's back edge, is `JMPR label`, which assembles as `ADD PC, PC, label-next` (ISA.md §10.1)". It assembles to the one-word instruction of ISA.md §5.3.

Of `make hazards`: "A jump that DECODE resolves is `MOVE R15, c` or `ADD R15, R15, c` with the condition "always", or the `ADD` with another condition and `c` negative … A trace shows no constant words, so this last one counts only when FILE is a `.bin`." `hazards.py` also counts the one-word `JMP`, `JMPR`, and `CALL` without a condition, and a `JMPR` with one that goes back. That one has its distance in the instruction word, so it counts from a trace too.

**Fix:** "the one-word `JMPR` of ISA.md §5.3", and the one-word forms in the rule.

**Resolved.** bench/README.md calls `JMPR label` the one-word jump of ISA.md §5.3, and its rule of the jumps that DECODE resolves names the one-word forms, the predicted `JMPR` among them, which counts from a trace too.

### 2.7 ABI.md: "E = 0", and `MOVE PC, _main`

Programs under a monitor: "it pushes a return address and jumps to `0x8000`, with E = 0 and these registers". There is no E. The same file names F1, F0, and U at its line 42.

"jumps to `main` with `MOVE PC, _main`, a tail call". The three start-up files for a monitor have `JMP _main`, the one-word jump.

**Fix:** drop "with E = 0 and", and write `JMP _main`.

**Resolved.** ABI.md no longer names an E, and gives the jump to `main` as `JMP _main`, as the three start-up files have it.

### 2.8 HISTORY.md: a date, and "the commands were free"

"On 2026-11-15 the interrupts were removed (#162)." That is the day the issue was accepted. The commits are of 2026-11-22, and the release is `V3.0`.

"So `V3.0` added `JMP`, `JMPR`, and `CALL` as control commands 4, 5, and 6 … The commands were free after the interrupts went." The commands 4 to 31 were reserved before #162 too. What the interrupts freed is 1, 2, and 3, and #192 decided to leave them reserved, "so that an old binary with `RTI`, `INT`, or `WAIT` halts". So the sentence gives a reason that does not hold, and the real one is in no document (§4.2).

**Fix:** "On 2026-11-15 it was decided to remove them (#162), and the removal landed on 2026-11-22", and for the commands the reason of §4.2.

**Resolved.** HISTORY.md says that the removal was decided on 2026-11-15 and landed on 2026-11-22, and that the commands 4 to 6 were always reserved, with the reason of §4.2 for 1 to 3.

### 2.9 Words left from the interrupts

| Place | Text | What holds |
|---|---|---|
| hdl/README.md, `tb_link` | "a hold while it runs, the halt reasons 2 to 4, and the single step" | `trace_pkg.vhd` has the reasons 1 and 2 only, and `tb_link` checks 2. The same list names reason 2 again further on. |
| hdl/README.md, `tb_link`, and two comments of `tb_link.vhd` | "the halt reason 2 for `INT`, `RTI`, `WAIT`, and the other reserved control words" | The commands 1 to 3 have no names now. |
| DEVICES.md §10 | "The clock counts on while the processor is held, paused, halted, or waiting" | The emulator's README has "held, paused, or halted". |
| DEBUG.md §6, the version | "A host checks it before it uses the pause, the step, a breakpoint, or a write of a register." | Every system of major 1 has all four. A host checks the major, and the counts of breakpoints and watchpoints. |
| MICROARCH.md §9, step 5 | "the reserved control words, which halt with reason 2 (`cputest`, `reserved`, `tb_trace`, and `tb_link`)" | `cputest` has its reserved words only under `?!1`, and ends with status 0. It checks that a skipped one does nothing. New text of 014ff74. |
| emulator/README.md, Trace format | "for the other halts, such as `reserved control instruction`" | There is one other halt. |
| emulator/README.md, Tests | "that the options of the old interrupts are unknown" | It says what used to be. Name `--irq`, `--nmi`, and `--no-timer-irq`. |
| hdl/CODING_STYLE.md, the names | The example signal `take_nmi` | No file has it. |
| `hdl/src/trace_pkg.vhd`, line 92 | The codes 3 and 4 "no longer occur" | History, in a comment. |
| `bench/pipecycles.py`, twice | The bus slaves include "the timer", and `slave()` returns `"timer"` for `0xFFFFFF10`–`0xFFFFFF1F`, "as in hdl/test/tb_core.vhd" | `tb_core.vhd` has no such slave. |
| `doc/timing.sty`, and the Makefile's comment on the diagrams | "Used by doc/interrupt.tex and doc/flow.tex", and "the timing diagrams" | `interrupt.tex` is gone, and one timing diagram is left. |
| `emulator/test/errors.py`, lines 304–310 | "A wait is named at the WAIT", and "FAIL --symbols in a wait" | The word is a reserved control word now. |
| `emulator/test/perf.nasm` and `events.nasm` | `INTR_LO .EQU 0xFFFFFF52` | DEVICES.md no longer names the word. |

**Fix:** each in place.

**Resolved.** Each place is corrected. hdl/README.md and `tb_link.vhd` speak of the reserved control commands 1, 2, 3, and 31. DEBUG.md §6 says that a host checks the version before anything else, and stops on another major. `slave()` of `pipecycles.py` has no timer, which no benchmark reached. The probes call `0xFFFFFF52` `SPARE`, and the three comments of `cputest.nasm` that named `RTI`, `INT`, and `WAIT` "before #162" say "reserved command", which this table did not list. The `.bin` files are the same.

### 2.10 ISA.md: six small points

- **§7** says of a loop that polls: "The emulator does not spin the host's CPU for such a loop (DEVICES.md §1.6)". DEVICES.md §1.6 and `main.zig` have the rule for a run with `--window` and without `--speed` only. A plain run of a program that polls a counter keeps a host core busy. **Fix:** "The emulator's window does not …".
- **§5.3**, the table: "`0x0C800000` + d". With a negative d the sum borrows from the command: d = −1 gives `0x0C7FFFFF`, a reserved word, where the instruction is `0x0C9FFFFF`. **Fix:** "+ the low 21 bits of d", or a note under the table.
- **§5.3**: "The write may change the words of the `CALL` itself". A `CALL` is one word. The rule holds: on the emulator, a `CALL` whose push lands on itself still jumps by its own d.
- **§9.1**: "Call `sub` | `CALL sub`". `sub` cannot be a label, as `SUB` is a mnemonic and mnemonics ignore case (§10.1): niceasm answers "SUB takes 3 operands, got 1". The name is older than `V3.0`, but the line is new. **Fix:** another name.
- **§10.1**, Operand counts: "`HALT` takes none." Before, the point named every control instruction. `JMP`, `JMPR`, and `CALL` take one, and are not there.
- **§9.2**: the example of a signed comparison ends in `?N MOVE PC, less`, the long form, under a table that gives `?Z JMP label` for a conditional jump.

**Resolved.** All six are changed in ISA.md: §7 speaks of the emulator with its window; §5.3 says that the "+ d" of the table puts the low 21 bits of d into the word, with `0x0C9FFFFF` for a `JMP` with d = −1, and speaks of the word of the `CALL`; §9.1 calls `routine`; §9.2's signed comparison ends in `?N JMP less`; and §10.1 gives the one operand of `JMP`, `JMPR`, and `CALL`.

### 2.11 emulator/README.md: a step is not a cycle

Window, new text: "at `--speed 1000000`, one step per microsecond, a loop of P steps lasts P microseconds, where on a board of 100 MHz it lasts some P/100". A step is an instruction, and the pipelined core takes 1.4 to 2.6 cycles for one (bench/README.md). `V2.6` spoke of a timer's period of P cycles, which was exact. DEVICES.md §1.6 compares the cycle counter, which is right. **Fix:** the wording of DEVICES.md §1.6.

Debug link: a step "runs one step of `--max-steps` and `--trace`, an instruction". After a write of `TIME_SKIP` it runs the rest of the skip and the instruction, as DEBUG.md §6 and the README's own "Skipping time" say.

**Resolved.** The emulator's README compares the cycle counter, as DEVICES.md §1.6 does, and says that a step over the link after a write of `TIME_SKIP` runs the rest of the skip and the instruction after it.

## 3. What the documents say that is not so, older than `V3.0`

These were found by reading the documents whole. None is of this release.

- **DEBUG.md §7.3, Flow control**: "The board drives `rx_hold_i` high … for up to `G_HOLD` cycles". `debug_link.vhd` has `rx_flow_i` and `G_WAIT`, and no file has the other two names. Since 8462504.
- **DEBUG.md §1**, and again in §7.1: "While the processor is held or halted (§6), and after the end of the line's input (§7.1), they are dropped; a keyboard's bytes are not (DEVICES.md §1, §7)." A keyboard's bytes are dropped while the processor is held or halted: DEVICES.md §1.5 says so, and `takeKeys` of `link.zig` does it. Only the end of the line's input spares them. And DEVICES.md §7 is the Ethernet frames: the keyboard is in §1.5 and §8.
- **MICROARCH.md §9**: "A proof of the whole core for every cycle is still open (#59)". #59 was closed on 2026-11-05, with a last comment that the proof is still not planned. decisions.md has no entry for it.
- **hdl/README.md, What the tests check**: the cores run the emulator's probes "but `scrbound`, `screencolor`, and `screeninvert`". `PROBES` of `hdl/Makefile` has 38 of the emulator's 49. The other eight that it leaves out are `chunky`, `clock`, `clockhost`, `font`, `skip`, `stack`, `time`, and `trapsym`.
- **hdl/README.md, Integrating the core**: "the same two generics", over a table of three, which both entities have.
- **hdl/README.md**: the contents list lacks four sections, the floating-point unit, the SD card controller, the network station, and Ethernet frames. `tb_core`'s list of slaves lacks the FPU. The same `bmc` takes "4 minutes" in one place and "3 minutes" in another, and took 284 seconds here. The example of `trace_reads.py` reads `build/run/multicycle/random_65/` under a `make random` line that writes `build/run/pipeline/random_65/`.
- **hdl/README.md, the proof of WRITE**: it "pauses without `pause_i` only on the breakpoint flag", where `formal_pipe_write.vhd` allows a watchpoint hit too, and the row of hdl/formal/README.md leaves out the watchpoints and the register write. The cover list of the multi-cycle core lacks `c_brk_go` and `c_wch`.
- **hdl/ASSUMPTIONS.md**: "Items that need a change outside `hdl/` are marked **Outside hdl/**". No item is.
- **MICROARCH.md §8, Console**: the console's file is in "hdl/README.md, The memory model". The section is "The console".
- **`hdl/test/tb_core.vhd`**, line 70: "`--against` sums the causes". The option is `--causes`.
- **runtime/README.md, the C library's tests**: "`mchess.expected`, 600 lines of board output". The file has 142 lines, as at its first commit. "`perft 3`, which takes 11 million steps": 11.3 million is the whole run, and `perft 3` is 9.7 million of it. The Makefile of `runtime/libc` says the same.
- **runtime/README.md**: "In `muldiv_mpu.nasm`, the one-word routines take 4 steps each". `__clz`, `__ctz`, and `__popcnt` take 3, as their comment says.
- **nicedbg, `help load`**: it "disables the breakpoints, and loads the file". It disables the watchpoints too, as the README says.
- **emulator/README.md, Tests**: the order is given as the probes, `errors.py`, `link.py`, `udp.py`, and `tap.py`. The Makefile runs the last three before `errors.py`. The usage text says that `--stack` and `--symbols` act after the halt, and both act at the step limit too.
- **`bench/words.py`**, twice: "A constant takes a whole word whatever its value (ISA.md §3)". The constant words are §2.3.
- **translator/DESIGN.md**: the introduction and the contents leave out the section "The output", which translator/README.md cites.
- **The slides**: "October 2026" on the title, and "As of now (OCT-2026)".

**Fix:** each in place, and an entry in decisions.md for the proof of #59.

**Resolved.** Each is corrected in place. DEBUG.md has `rx_flow_i` and `G_WAIT`, and says that a keyboard's bytes are dropped while the processor is held or halted, and kept after the end of the line's input (DEVICES.md §1.5, §8). decisions.md has an entry for the proof of #59, and MICROARCH.md §9 points to it. hdl/README.md names all eleven probes that the cores do not run, with what each checks, has three generics, the four sections in its contents, the clock and the FPU among `tb_core`'s slaves, the watchpoint in WRITE's proof, and both covers. The whole-core `bmc` took 195 seconds alone on 2026-11-25, so both places say 3 minutes, and 5 beside the other jobs of `make formal`. The steps of `perft 3` are "some 10 million" in both places, and `_nice_isqrt64` is among the routines of 4 steps. The emulator's usage text names the step limit for `--symbols` and `--stack`, and its README gives the tests in the Makefile's order. The slides' two dates were changed with §2.2.

## 4. Gaps

### 4.1 Nothing says what the board does until its `V3.0`

`V3.0` breaks the board in two ways at once, and both are silent until someone meets them:

- **A program.** NiceMonMEGA65's `V2.6` pins `V2.6` here, where the commands 4 to 6 are reserved. A program that niceasm of `V3.0` assembles halts there at its first `JMP`, `JMPR`, or `CALL`.
- **The debugger.** The board serves the link in version 8, major 0. `check_version` of `nicelink.py` stops on it: "this tool knows major 1".

The documents say the opposite, or nothing. DEBUG.md's introduction: "Both follow this file, so one host tool works with either." DEVICES.md §8 says that the board serves the link "in version 8", beside a DEBUG.md that describes `0x10`, and its point **Debug link** has no word on versions. The debugger's README, "On a board", has none either. MJoergen/NiceMonMEGA65#169 and MJoergen/NiceMonMEGA65#172 are open, with the board's milestone `V3.0`.

**Fix:** a point in DEVICES.md §8, as the FPU's and the screen's have: NiceMonMEGA65 runs the programs of `V3.0`, and serves the link in version `0x10`, from its `V3.0` (the two issues), and its releases before that halt on a one-word jump and serve version 8, which the tools of `V2.6` speak. The same in one sentence at DEBUG.md's introduction and in the debugger's README.

**Resolved.** DEVICES.md §8 has a point **Core**: NiceMonMEGA65 has the core of `V3.0` from its `V3.0` on (MJoergen/NiceMonMEGA65#169 and MJoergen/NiceMonMEGA65#172), and before that a program of `V3.0` halts at the first one-word jump or call that it runs. Its point **Debug link** gives the versions, `0x10` from the board's `V3.0` on and 8 before, and which tools work with which, and the point of the reserved words no longer says "version 8". DEBUG.md's introduction and the debugger's README say the same in a sentence each.

### 4.2 Why the commands 1 to 3 stay reserved

ISA.md §5.3 has `JMP`, `JMPR`, and `CALL` at 4, 5, and 6, and 1 to 3 reserved. A reader who knows that 1 to 3 were `RTI`, `INT`, and `WAIT` asks why the new instructions did not take them. #192 decided it: they stay reserved "so that an old binary with `RTI`, `INT`, or `WAIT` halts", where it would otherwise jump. The message of 398314b says it. No document does, and HISTORY.md gives another reason (§2.8).

The other half of that decision is in no document either: a binary of `V2.6` without those three runs unchanged, and a binary of `V3.0` halts on an older emulator or core.

**Fix:** HISTORY.md, in "Jumps and calls in one word", and the upgrade notes (§1.2).

**Resolved.** HISTORY.md, "Jumps and calls in one word", says why the commands 1 to 3 stay reserved, that a binary from before `V3.0` without `RTI`, `INT`, or `WAIT` runs unchanged, and that a binary of `V3.0` halts on an older emulator or core. The notes of `V3.0` say it too (§1.2), and decisions.md has the idea of taking 1 to 3 (§4.3).

### 4.3 doc/review/decisions.md has nothing of #162, #192, and #196

decisions.md keeps the ideas that were weighed and dropped, "so that they are not proposed again". The diff changes two of its entries, PR #36 and the watchdog, and adds none. The three issues of the milestone dropped these:

| Idea | Issue | Why it was dropped | In HISTORY.md |
|---|---|---|---|
| SR bits 31, 30, and 23..0 that read 0 | #162, question 1 | Two conditions would be a second "never" and a second "always", R14 would get a second mask on every write, and the cost is the same. | In part |
| The timer kept as a counter to poll | #162, question 2 | The performance counters count cycles and microseconds. | No |
| IRQ or NMI alone removed | #162 | A copy without IRQ, NMI, and `WAIT` saved nothing: the cost is the saved PC and SR, the vector read, and `RTI`. | No |
| The commands 1 to 3 for the new instructions | #192 | §4.2 | No |
| One relative jump, in place of `JMP` and `JMPR` | #192, Prediction | `hand.nasm` takes 10.0% more cycles, and heapsort 45.7%. | Yes |
| An assembler that picks the form by the distance | #192 | The size of a statement depends only on its operand modes, which keeps the passes in agreement. | Yes |
| A distance of 16 bits, or an absolute target | #192 | The farthest call measured is 41611 words. | In part |
| No early redirect for the long forms | #192 | It saves 81 LUTs and gains no slack. | No |
| The interrupt sweeps in shares, and CI's `hdl` job as a matrix over the cores | #196 | The sweeps went with the interrupts. | No |

The fourteenth review found the same for #203 (its §3.1).

**Fix:** a paragraph for each, or one for each issue.

**Resolved.** decisions.md has a paragraph for each of the nine, with the figure that decided it where the issue has one.

### 4.4 A hand-written file joined after a large memory

2f6eca7 makes nicewasm keep the long form for a jump or a call out of the module when the memory has 2¹⁹ words or more, and translator/README.md and DESIGN.md describe it. A file that `nicebuild.py --asm` joins lies after the memory too, and its own jumps back are the writer's:

    $ cat cb.nasm
    _bye            JMP     _exit
    $ translator/nicebuild.py --memory 4194304 --asm cb.nasm -o cb.bin cb.c
    /tmp/tmp5nt1431d/full.nasm:86: error: JMP: '_exit' is out of reach, -1048613 words from the next instruction, where the reach is -1048576 to 1048575

With `--memory 65536` it builds. The message names a file that is gone unless `--keep` is given. Nothing under `--asm`, under the memory limit of translator/README.md, or in "Joining a program" of runtime/README.md says that such a file reaches the start-up code and the module with `MOVE PC, label` and the long call of ABI.md.

The limit itself is worded two ways. translator/README.md: "so from 32 pages on, nicewasm writes the long form". DESIGN.md: "when the memory in the output has 2¹⁹ words or more, which is 32 pages". The code counts the words that the output reserves, so `--memory 4194304 --memory-bytes auto` gives the one-word form, and DESIGN.md is the right one.

**Fix:** a sentence under `--asm` and under the memory limit, and "from 2¹⁹ reserved words on, 32 pages" in the README.

### 4.5 `nicedis` does not name a jump's target below address 16

assembler/README.md: "A constant of 16 or more that is the address of a label is shown as the label … So is the target of a one-word jump or call. Smaller constants, such as the 2 of a call, stay numbers". The limit is there so that a small immediate is not taken for a label. It holds for a target too, which the README does not say:

    $ assembler/nicedis.py --symbols k.sym k.bin
                    CALL    0x3
                    HALT
    fn              MOVE    R15, @R13++
    far             JMP     0x3
                    JMP     far             ; far = 0x00000010

`fn` is at 3, and both jumps to it show `0x3`. A target is always an address, never a count, so the limit has no reason there, and the first routine of a program, a loop at its start, and the entries of a dispatch table at 0 lose their names. nicedbg's `d` shows the same, as it uses `disassemble()`.

**Fix:** name every target of a one-word jump or call that has a label, in `name()` of `nicedis.py`, with a case in `test/dis.py`. Or say in the README that the limit of 16 holds for a target too.

### 4.6 The slides teach no `JMPR`, and no program of theirs calls with `CALL`

- `JMPR` is on no slide. The slide on jumps shows `JMP` and `ADD PC, PC, 10`.
- `hello.nasm` calls with `ADD @--SP, 2, PC` and `MOVE PC, PUTS`, and no other example calls. So no program of the slides, and no case of `make -C doc/intro test`, uses `CALL` or `RET`, which the slide on calls teaches.
- The table of the flags has a row for `HALT` alone, where no control instruction writes a flag.
- The lists of the repository's parts leave out `debugger/`, though a slide relies on the debugger.

**Fix:** a line for `JMPR` on the slide on jumps, `CALL PUTS` and `RET` in `hello.nasm`, or a sixth example, and "The control instructions" in the row of the flags.

**Resolved.** The slide on jumps has a point for `JMPR`, and the table of the control instructions a row. `hello.nasm` calls with `CALL PUTS` and returns with `?Z RET`, so `make -C doc/intro test` runs both: the program takes 55 steps, where it took 56, and `TEXT` is at `0xE`. It no longer names `PC`, which it does not use. The row of the flags is "The control instructions", and both lists of parts name the debugger. The examples keep `JMP` for their loops.

### 4.7 hdl/README.md: what the tests check

"What the tests check" does not name the probes `short` and `shortfar`, which `hdl/Makefile` runs on both cores for the one-word forms, and which MICROARCH.md §9 names. It says that the random programs use "R15 with every side effect, `HALT`, the reserved control words, and the read counter": since 3f9a6be `random_prog.py` writes the one-word `JMP`, `JMPR`, and `CALL` too. And these runs of `make test` are in the Makefile's comment only, which is older than `V3.0`: `cputest_pause`, `cputest_hold`, `cputest_step`, `reads_step`, `bytewin_stall`, `eth_stall`, `eth_hold`, `breaks_hold`, and `random_pause_N` and `random_hold_N` for eight seeds.

The flush causes of the README, new text, leave out a predicted jump that is skipped, which MICROARCH.md §5.4 has.

**Fix:** the two probes, the three forms, and a sentence for the runs with a pause, a hold, and a step.

### 4.8 What no check looks at

Four findings of this review are of a kind that a check could see.

- **README.md's worked example** (§2.1). `make -C doc/intro test` runs `hello.nasm`, but nothing compares the README's listing and its three outputs with the file and the tools. It went stale twice: its listings at 648aaee, and its outputs at 90ef260. A test that takes the indented blocks after each `$` line of the README, runs the line, and compares would have failed both times.
- **A sentence that waits for a closed issue** (§1.6). `release.py preflight` has warned of one since `V2.5`. Its pattern wants the issue right after the "yet" or the "until", and the sentence of #208 has a clause between: "yet, so `0xFFFE3000` reads 0 there (MJoergen/NiceMonMEGA65#171)". So the check that was written for this case does not see it. On every run it prints two warnings that are not findings, for the example in RELEASE.md step 2.2 and for the `OWNER/NAME#12` of release/README.md, which teaches the reader to pass over its warnings.
- **The table of board tags** (§1.3). It was short at the eleventh and the fourteenth review too, and is short by three tags now. `release.py preflight` could list the board's tags with `git ls-remote --tags` and warn of one that the table lacks.
- **The figures** (§2.5). `release.py figures` checks the summary line and the total of `bench.bin`, and the two cycles of the float benchmark. The words of the modules, the percentages of the flags, and the figures that MICROARCH.md and hdl/README.md take from `make hazards` and `make cycles` are copied by hand, and 16 were missed. `make -C bench words`, `hazards`, and `cycles` print most of them, so `figures` could look for more of their output in the documents.

**Fix, optional:** the test of the README's example is the one that would pay first.

### 4.9 Small gaps

- **ISA.md §10.1** does not give the operand count of `JMP`, `JMPR`, and `CALL` (§2.10).
- **translator/README.md, Tests**: the list of what `test/passes.py` checks names five of its 11 cases. Missing are the anonymous labels, `pseudo()` near and far, the last new with 2f6eca7, the predicted back edge, and two more of the hoist and the tail call.
- **bench/README.md**: "`make profile` writes `build/bench.cyc.txt` and `build/hand.cyc.txt`". It writes `build/float.cyc.txt` too.
- **translator/README.md**: "The emulator runs about 70 million steps per second", with no host and no program. Here a loop of two instructions ran at 74 million, and CoreMark at 41 million.
- **emulator/README.md** names neither `make bincheck` nor `make typecheck`, where CONTRIBUTING.md says that each README lists its other targets, and its account of `link.py` leaves out the host that knows only the minimum of major 1, `test_old_host`.
- **debugger/README.md**: the alias `exit` of `quit` is in neither the table nor `help`.
- **Generics**: `G_HAS_ROM` and `G_BOOT_HELD` of `debug_link`, `G_MAC` of `net_regs`, and `G_STACK` of `fpu` are in no document.
- **RELEASE.md §5** no longer says how long `make slow` takes in nvc. Its "about half an hour" for `SIM=ghdl` is from before the sweeps went, and was not measured again.

## 5. What was checked, and found right

These are recorded so that the next review need not repeat them.

- **ISA.md and niceasm.** The words of the table of §5.3: `JMP`, `JMPR`, and `CALL` assemble to `0x0C800000`, `0x0CA00000`, and `0x0CC00000` plus the low 21 bits of the distance from the next word. The reach is −1048576 to 1048575, computed modulo 2³², and one word farther either way is the error that §10.1 promises. `JMP` and `CALL` with a register, `c[Rx]`, or memory give the long forms with the right constant, 1 or 2, and `JMP c[R0]` is an address. `JMPR` with a register or memory is an error. `?F0`, `?F1`, `?E`, `?M`, and `?I`, with their `!` forms, give SEL 110 and 111. `RTI`, `INT`, and `WAIT` are errors where a mnemonic stands, and cannot be a label or an `.EQU` name. None of the five takes a modifier.
- **ISA.md and niceemu.** A `JMP` with d = −1 jumps to itself. A `CALL` whose push lands on its own word still jumps by its d. A reserved control word with a false condition is skipped, and one that runs halts, as does a `HALT` with a bit of 20..0 set, with status 2.
- **nicedis.** It writes the one-word forms with their target, and every control word but the four as a `.DAT` with "reserved control word", the old `RTI`, `INT`, and `WAIT` among them. `test/dis.py` takes every `.bin` file of the tree there and back.
- **The sections.** ISA.md §7 is one section, DEVICES.md keeps §1.9 and §4, and MICROARCH.md §6 is "Stops" with §6.1 alone. Every reference to a section in the tree still points at a section that says what the reference is there for, and `make -C doc test` passes. The contents list of ISA.md matches its headings.
- **HISTORY.md.** The census of #192: 23570 words, 36.1% of the code, and 1698 of 4217 constant words. The 17% to 20% and the 19.7%, the 41611 words of the farthest call, and the cycles before and after on the pipelined core, which are those of bench/README.md at `V2.6` and now. `WAIT` came with `V2.0` (#133), the console's interrupt with `V2.1` (#153), and the link's NMI with version 8. The "about 400 LUTs, 5%" is the estimate of #162, on cut copies after synthesis. The medians of `make timing-spread` before and after the removal are 7642 and 6967 LUTs, and 3225 and 3146 registers, but the routed counts range over some hundreds.
- **DEBUG.md §9.** The row of version `0x10` names `V3.0`, as RELEASE.md step 2.8 asks.
- **The emulator and the link.** The 25 rows of niceemu's option table against the parser and the usage text, the six exit statuses, the 21 rows of both memory maps with their word counts, the link's version, halt reasons, control bits, and reserved words in `link.zig`, `debug_link.vhd`, and `nicelink.py`, nicedbg's 5 options and 23 commands, and the six checksums of DEBUG.md §8. `0xFFFFFF02` and `0xFFFFFF10` are plain memory for data accesses, and `0xFFFFFF52` reads 0.
- **`hdl/`.** Every file of `hdl/src` (23), `test` (61), `formal` (39), and `sim` (4) is in its README, and every target named exists. The table of ports and generics, the 13 states of the multi-cycle core, the four flush causes and 14 cycle causes, the offsets of the counters and the fetch statistics, and items 1 to 19 of ASSUMPTIONS.md. The 16 rows of MICROARCH.md §5.6 equal `make -C bench hazards` in both columns. The bus rows of `flow.tex` match a waveform of `addwave`.
- **The benchmarks.** Every figure of bench/README.md on the emulator, in the model, and on the pipelined core, but those of §2.5: the four tables of the emulator, the table of `simple.nasm`, the phases and totals of 2341190 and 1247655 cycles, the read waits, the tables of `make compare`, the float benchmark, Dhrystone at 2253 cycles a run, and CoreMark at 1068822 an iteration. The words: 9625, 4909, 24591, and 5723.
- **The runtime and the translator.** The 400 and 245 words of the float library, its 52 and 33 routines, the 10 options of nicewasm and the 19 of nicebuild against their parsers, the quick start in C, Zig, and Rust, both listings of ABI.md, which assemble and run, and WASM.md, read whole.
- **The slides.** Every listing equals its file in `examples/`, the shown outputs are what the tools print, and the PDF matches the `.tex`.
- **The board.** The 11 issues of NiceMonMEGA65 that DEVICES.md cites are closed, and each statement that leans on one holds, but that of #171 (§1.6). MJoergen/NiceMonMEGA65#104, the monitor's wait for a key with `WAIT`, is still open there, and no document here cites it.
- **The targets.** Every `make` target that CLAUDE.md and CONTRIBUTING.md name exists, and the 15 jobs of `ci.yml` are those that CONTRIBUTING.md lists.

**Not checked.** The slacks and the durations of the Timing sections, which need Vivado. The figures of the multi-cycle core in bench/README.md, whose derived figures are consistent. The durations in GHDL. The figures of the demo on the MEGA65. The absolute steps of the table of math functions, the 7.7% and 4.4% of MICROARCH.md §5.4 for `JMPR`, and the internal rows of `flow.png`.
