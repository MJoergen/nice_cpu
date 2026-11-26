# Sixteenth review of the repository, at commit d2b0143

Reviewed on 2026-11-26: the 30 commits between `V3.0` and the head of `dev-V3.1`, commit d2b0143 ("niceemu: the window plays the sample player"), before the release `V3.1`. They add the sound of DEVICES.md §12 (#209), an FM synthesizer whose registers are the YM2151's: its model, the device in the emulator with `--wav`, `hdl/src/opm.vhd`, and the sound of the emulator's window. They add its sample player (#216), §12.7, in the same four places. And they change the FPU: `SIN`, `COS`, and `TAN` reduce any finite argument (#185), so the C library's `sin`, `cos`, and `tan` are routines of the float library, its steps and commands take fewer cycles (#164), and the start of a function and X and Y are in registers, with a `make timing-spread` of its own (#194, #211). This review looks at the documents: what they say that is not so, and what they leave out.

**How it was checked.** Each document that says what is true now was read whole, not only its diff, and its statements checked against the code, a test, or a run. I read README.md, CONTRIBUTING.md, CLAUDE.md, TOOLCHAIN.md, REFERENCES.md, doc/README.md, RELEASE.md, release/README.md, the new entries of HISTORY.md and decisions.md, and DEVICES.md §8 and §12 with DEBUG.md §6, and the issues #164, #171, #185, #194, #209 to #216 beside HISTORY.md and decisions.md. Three fork agents read the rest, each in a scratch copy of the tree: the READMEs of the emulator and the debugger with DEVICES.md and DEBUG.md; the documents of `hdl/` with MICROARCH.md; and the documents of the runtime, the translator, the benchmarks, the demo, and the slides, where the work was to measure each figure again. I checked each of their findings against the tree, or by a run of my own, before it went in here.

On the unchanged tree, in the scratch copies, these ran and pass: `make test` in the emulator (80 lines of `PASS`), the runtime (70), `bench/` (78), the demo, `doc/`, `doc/intro`, and `release/`, `make typecheck` in `bench/` and the runtime, `make wasmcheck` (57 files, no note), `make -C runtime/libc fuzz`, `make ymfmcheck` (20 logs of 30000 samples), `make -C bench hazards`, `words`, `mathsteps`, and `cycles`, and on the pipelined core in nvc `make -C bench core`, `core-dhry`, `core-coremark`, and the float benchmark. `tb_opm` ran in nvc with a counter of the engine's cycles, and the FPU's two proofs ran alone. `make timing UNIT=opm` ran once in Vivado (§2.3). CI passed all 15 jobs on the head. I asked GitHub for the state of the issues that the documents cite, compared the board's tags with the table of RELEASE_NOTES.md, and ran `release.py preflight`, `notes`, and `figures`. A chess engine match ran on the machine all the while, so the runs were kept small, and CI stands for the rest: `make test` of `hdl/` and of the translator, `make formal`, `make programs`, and the window's tests were not run here. The cycles of the FPU's commands are read from the logs of `make -C hdl test` of the same day, and the timing of the FPU and the sample player from the day's reports on disk.

## Summary

**The release steps are open**, as expected before the tag (§1). RELEASE_NOTES.md has no section for `V3.1` (§1.1), its table of board tags says "none yet" for `V3.0`, which the board tagged today (§1.2), `emulator/build.zig.zon` says `3.0.0` (§1.3), and #164 is open in the milestone (§1.4). CI is green on the head. The four commits of the sample player came after the code review of the branch (§1.5).

**The sound is described well where it was written**, and is missing where a list was not touched. DEVICES.md §12 agrees with the model, the emulator, and both units of `hdl/` in every rule that was probed: the words, the status, the FIFOs, the rates, the reset, and the two examples, which run as written. These places did not follow:

- **Six lists of devices** lack the sound: two of README.md, one of doc/README.md, and three of DEBUG.md, among them the devices that a start resets (§2.1).
- **README.md's License section** has no entry for the files that follow ymfm, under BSD 3-Clause (§2.2), and the archives of a release would carry no notice of it (§4.1).
- **hdl/README.md says that the sound takes "no DSP or block RAM"**. It takes three block RAMs of 18 Kb and a DSP, by a run of `make timing UNIT=opm`, which had no report on disk (§2.3).
- **The sound's place on the bus** is said two ways since the sample player took six of its eight words (§2.4).
- **The units of `make timing`** are two or three in three places, and four in fact (§2.9).

**The FPU's changes left some figures behind.** The float library has 409 words, where four places say 400, and the float benchmark 8641 and 9069 words (§2.7). Two rows of the FPU's cycle table are below what its test measures (§2.5). The table of 2/π has 1176 bits, not 1584 (§2.6). runtime/README.md counts 33 routines of `math.h` where the test runs 36 (§2.12). Every other figure of bench/README.md and runtime/README.md was measured again, and holds.

**Seven things are in no document** (§4): the notices in a release's archives, what #209 and #216 decided against, the rule for the I/O page that #209 decided, that no gate runs `make ymfmcheck`, what a signal leaves of a WAV file, that the sound and the sample player have no formal check, and that a pause and a watchdog wait for a write to a full FIFO. Some smaller ones follow them (§4.8).

**Older errors were found in passing** (§3), none of them of this release: a hazard that ASSUMPTIONS.md says neither benchmark has, and which both have in stores, a closed issue that bench/README.md cites as open, and some comments.

No finding is in the behavior of a core. Three are at the edge of a tool's: the WAV file that a signal leaves empty (§4.5), the archives' notices (§4.1), and `window.py`, which prints 13 tests and runs 14 (§2.10).

Nothing is fixed, committed, or filed: this file and its line in REFERENCES.md are the only changes to the tree.

## 1. The release

### 1.1 RELEASE_NOTES.md has no section for `V3.1`

The newest section is `V3.0`. RELEASE.md step 2.8 asks for the section, and for a row `V3.1`, "none yet", in the table of board tags. `release.py notes` drafts it. The upgrade notes must say at least:

- **The sound** (#209): an FM synthesizer whose registers are the YM2151's, at `0xFFFFFF08` and `0xFFFFFF09`, `OPM_WRITE` and `OPM_STATUS`, with a FIFO of 64 writes, of which one takes effect in each sample, 55930 times a second. `emulator/test/opm_model.py` defines the samples, and follows ymfm, under its BSD 3-Clause license (§2.2, §4.1).
- **The sample player** (#216): `PCM_DATA`, `PCM_RATE`, and `PCM_STATUS` at `0xFFFFFF0A`–`0xFFFFFF0C`, a FIFO of 4096 stereo samples, played at 1000 to 48000 Hz.
- **`0xFFFFFF08`–`0xFFFFFF0F` are no longer memory.** They were reserved, and ordinary memory in the emulator. A program that kept data there runs with `--no-sound`. The random runs of `hdl/` use it so, as `tb_core` has no sound.
- **niceemu.** `--wav FILE` and `--pcm-wav FILE` write the samples, `--no-sound` makes the eight words memory, and the window plays both on the host's audio device, or says `niceemu: no sound:` and runs without. The version is 3.1.0.
- **`SIN`, `COS`, and `TAN` of any finite X** (#185). They gave a NaN from 2²⁰·π/2 on. The C library's `sin`, `cos`, and `tan` and their float versions are routines of the float library, as the others: 19 and 20 steps a call on the emulator where 43 and 45, 880 words of C math where 5723, and musl's `__rem_pio2`, its kernels, and the `-Os` of the math files are gone. A result for a huge argument may differ from musl's by 1 ulp.
- **Programs must be built again.** The labels `_nice_sin`, `_nice_cos`, and `_nice_tan` are gone, so a `.wasm` file of `V3.0` that calls `sin`, `cos`, or `tan` does not join: "undefined symbol '_nice_cos'". And `_sin`, `_cos`, `_tan`, `_sinf`, `_cosf`, and `_tanf` are labels of the float library now, so a module that exports a function of one of these names and uses a float no longer builds (runtime/README.md). On a system with the FPU of `V3.0`, such as NiceMonMEGA65 until it follows, the new `sin` gives a NaN for a huge argument.
- **The FPU is faster** (#164): the steps `PUT`, `POLE`, and a `JZ` that does not jump take one cycle where two, and a command of the unit two or three fewer. `float.c` takes 577066 cycles on the pipelined core, where 600538, and 331137 with `--inline-fpu`, where 354930, which now saves 43%. The model's averages are `--fpu-op 16` and `--fpu-long 72`, where 18 and 75. The longest command is `TAN` of a huge argument, 6108 cycles, where `DIGITS` was the longest with some 3400: a system's watchdog must allow for it.
- **The figures.** The float library 409 words, where 400. `float.c` 8641 words, Dhrystone 16806, and CoreMark 25244: 9 more each. The cycles of `bench.c`, `hand.nasm`, Dhrystone, and CoreMark on the cores are those of `V3.0`. The model's `hand.nasm` is 1247576 cycles, where 1247321, as a read after a store into the I/O range loads a cycle later (#206).
- **`hdl/`.** `src/opm.vhd`, `opm_engine.vhd`, `opm_tables_pkg.vhd`, and `src/pcm.vhd` are new, each a slave of the data bus with a strobe for its samples, which a system mixes. The sound's clock is 24 to 268 MHz. `make timing` takes `UNIT=opm` and `UNIT=pcm`, and `make timing-spread` `UNIT=fpu`. The FPU keeps X and Y, and the start of a function, in registers (#194, #211); its ports are unchanged. The timing: the figures of the release check, with the FPU's +0.460 ns of the default flow under its budget of 1.0 ns by less than the range of its spread, the sound's +2.271 ns, and the player's +3.701 ns. The resources of the sound (§2.3).
- **For the board.** The interface changes of RELEASE.md are the two new units and the eight words of the I/O map. MJoergen/NiceMonMEGA65#176 builds them in.
- **`bench/`.** `make mathsteps`, and the sizes of the C library's parts in `make words` (#205).
- **Decided against:** one math unit (#171), `K` and `PICK` in one cycle (#164), and a read that loads in the cycle after an I/O store (#210).
- The debug link stays version `0x10`. A start resets the sound and the sample player too (§2.1). Zig stays 0.17.0.

**Fix:** write the section, with the line "The version is 3.1.0." under the emulator's heading, and the row of the table.

### 1.2 The table of board tags says "none yet" for `V3.0`

NiceMonMEGA65 has a tag `V3.0`, of 2026-11-26, which pins ea1f485, `V3.0` here. The table at the top of RELEASE_NOTES.md says `V3.0`, "none yet". `release.py preflight` warns of it:

      warn RELEASE_NOTES.md: the table of board tags lacks V3.0 of MJoergen/NiceMonMEGA65

The other rows are right: the board's `V2.3.1` to `V2.6` are in the table.

**Fix:** `V3.0` in the row of `V3.0`.

**Resolved.** The row of `V3.0` says `V3.0`, which `git ls-tree V3.0 nice_cpu` in the board's repository shows at ea1f485, and the table has the row of `V3.1`, "none yet", as RELEASE.md step 2.8 asks. `release.py preflight` names no missing tag now.

### 1.3 `emulator/build.zig.zon` says `3.0.0`

RELEASE.md step 2.9: the version is the new tag's, `3.1.0`, set before `release.py check`, as a change to it after the stamp makes the stamp stale. `release.py tag` and the release workflow refuse the tag otherwise.

**Fix:** `3.1.0`.

**Resolved.** `emulator/build.zig.zon` says `3.1.0`, which `version_is_tags()` of `release.py` takes for the tag `V3.1`.

### 1.4 #164 is open in the milestone `V3.1`

RELEASE.md step 1.2: the milestone of the release has no open issue left. #164, "nicehdl: a faster arithmetic unit for the FPU", is open there. Two of its parts are done (5436324, dbfa2bf), one is decided against (1a2a381), and its last comment says that it "stays open for the barrel shifter and two quotient bits a cycle for `DIV`". The other 13 issues of the milestone are closed. #210 is closed with no milestone, and decisions.md has its entry.

**Fix:** move #164 to the next milestone, or take the milestone off it, and close the milestone at the tag.

### 1.5 CI, and the code review

CI passed all 15 jobs on the head, `formal` among them, and on a592877 before it.

The code review of the branch against `main` was made at bc4b116, and its eight fixes end at a592877. The four commits of the sample player came after it: e0223a2, c16d0ce, 1be8e50, and d2b0143, with `emulator/src/pcm.zig` and `hdl/src/pcm.vhd`. This review reads documents, and is no review of that code. What it did look at there: the rules of §12.7 on the emulator, by probes of the reader (§5), and the speed of the emulator, as the review of the sound had found a run with `--step-time` twice as slow. A loop of 500 million steps takes 7.1 s on the head, on a592877, and on `main`, and 7.3 to 7.5 s with `--step-time` on all three, so the player costs a run nothing.

**Fix:** none for CI. A code review of the four commits is the user's call.

## 2. What the documents say that is not so, since `V3.0`

### 2.1 The lists of devices that lack the sound

CLAUDE.md, DEVICES.md, and the memory map of emulator/README.md name the sound. These lists do not:

| Where | The list | What it lacks |
|---|---|---|
| README.md, "The emulator" | "the console, the 80×28 character screen, the math unit, the performance counters, the SD card controller, the network station's registers, the port for Ethernet frames, the clock of the time of day, and the floating-point unit" | the sound and its sample player |
| README.md, "It can:" | "show the screen in a window while the program runs, with the keys typed into it going to the console" | that the window plays the sound, and that `--wav` and `--pcm-wav` write it to a file |
| doc/README.md, the row of DEVICES.md | "console, math unit, performance counters, SD card, network station, Ethernet frames, clock, and floating-point unit" | the sound |
| DEBUG.md §6, **Start** | "The math unit, the performance counters, the SD card controller, the port for Ethernet frames, and the FPU start from their reset values" | the sound and the sample player |
| DEBUG.md §6, **While paused** | "the program cannot tell that it was paused, but by the wall clock, by the clock of the time of day, which runs on (DEVICES.md §10), and by a snapshot" | the sound's FIFO, which empties, and the player's FIFO and underrun flag |
| DEBUG.md §7.3, **Counters** | "The SD card controller and the clock of the time of day do not stop" | the sound and the sample player |

DEVICES.md §12.3 and §12.7 cite DEBUG.md §6 for the start: "A reset of the system, and a start over the debug link (DEBUG.md §6), empty the FIFO and reset the sound". `reset()` of `emulator/src/cpu.zig` resets both, and both units of `hdl/` take the reset of a start. DEBUG.md has no change since `V3.0`. The link's version stays `0x10`: the registers of the link do not change.

**Fix:** the sound in the six places. In DEBUG.md §6, "and the sound with its sample player (DEVICES.md §12)" among the devices that start from their reset values, and a sentence that both run on while the processor is paused, so that a program can tell a pause by them.

**Resolved.** The six places name the sound. README.md has it among the emulator's devices, with the window that plays it and the WAV files among what the emulator can do, and doc/README.md in the row of DEVICES.md. DEBUG.md §6 has the sound and its sample player among the devices that a start resets, and among what tells a program that it was paused, and §7.3 among what does not stop.

### 2.2 README.md's License section has no entry for the sound

"The code and the documents are under the MIT license, `mchess.c` included, but for these:", and then Dhrystone, CoreMark, the 2004 examples, the font, SDL, the math functions, and the sequences of the FPU. The sound is not there. `emulator/test/opm_model.py` "follows ymfm by Aaron Giles, src/ymfm_opm.cpp and src/ymfm_fm.ipp, of https://github.com/aaronsgiles/ymfm at commit 81aec25, step by step, under the notice in opm_tables.py", and `opm_tables.py` gives ymfm's BSD 3-Clause notice in full. `emulator/src/opm.zig` and `hdl/src/opm_engine.vhd` follow the model, and `emulator/src/opm_tables.zig` and `hdl/src/opm_tables_pkg.vhd` are written from the tables and point at the notice. The review of #209 decided it so: "MIT, with ymfm's notice on the files that follow it". The thirteenth review, §5.3, added the same bullet for the FPU's sequences.

**Fix:** a bullet for the six files, as the bullet of the FPU's sequences: the model and the tables follow ymfm, under its BSD 3-Clause license, which the header of `opm_tables.py` gives. The archives of a release are §4.1.

**Resolved.** The License section of README.md has a bullet for the model of the sound, the tables, and the four files that follow them or are written from them: what they have of ymfm is under its BSD 3-Clause license, which the header of `opm_tables.py` gives.

### 2.3 hdl/README.md: the sound has block RAM and a DSP

hdl/README.md, "The sound": "It takes 1432 LUTs, 172 of them distributed RAM, 769 registers, and no DSP or block RAM." There was no report of `make timing UNIT=opm` on disk, and the figures are those of the message of 6433a20, which has no word of RAMs or DSPs. I ran it once on the head. The slacks are the README's to the picosecond, +2.271, +6.599, and +7.958 ns, so 9f18717 changed no logic, as it says. `timing_util.rpt` of that run:

      | Slice LUTs                 | 1453 |
      |     LUT as Distributed RAM |  172 |
      | Slice Registers            |  773 |
      |   RAMB18                   |    3 |
      | DSPs                       |    1 |

The three block RAMs are the tables of the sine, the exponential, and the phase steps (`sin_r_reg` 256×12, `pow_r_reg` 256×10, `ps_r_reg` 1024×12 in Vivado's log), and the DSP is the product `prod_r` of the engine. A board with few of either needs to know.

**Fix:** "1453 LUTs, 172 of them distributed RAM, 773 registers, 3 block RAMs of 18 Kb, and 1 DSP", from the report.

**Resolved.** hdl/README.md has the figures of the report: 1453 LUTs, 172 of them distributed RAM, 773 registers, 3 block RAMs of 18 Kb, and 1 DSP, and what they hold. The slacks stand.

### 2.4 The sound's place on the bus, said two ways

Since the sample player (1be8e50), the decoder gives the sound offsets 0 and 1 of the eight words, and the player offsets 2 to 7. hdl/README.md, "The sample player", MICROARCH.md §8, **Sample player**, and the header of `pcm.vhd` say so. Three places still have the sound alone on the eight words:

- hdl/README.md, "The sound": "The bus decoder selects it for `0xFFFFFF08`–`0xFFFFFF0F` and passes address bits 2..0 as the offset", after "offsets 2 to 7 read 0".
- MICROARCH.md §8, **Sound**: "8 aligned words, so the decoder compares address bits 31..3, and gives the sound bits 2..0".
- `hdl/src/opm.vhd`, contract b: "The sound is at 0xFFFFFF08-0xFFFFFF0F, so the offset is address bits 2..0".

Each is true of a system with the sound and no player (DEVICES.md §8), but a reader of MICROARCH.md §8 finds two bullets that claim the same words. No test bench has the decoder of the two: `tb_core` has neither device.

**Fix:** in the three places, that the decoder gives the sound all eight words on a system without the player, and offsets 0 and 1 beside the player.

**Resolved.** The three places say it one way: the decoder gives the sound address bits 2..0 of the eight words, selects it for offsets 0 and 1 alone beside the sample player, and for all eight on a system without the player.

### 2.5 hdl/README.md: two rows of the FPU's cycles

The table "The most cycles of each command in `tb_fpu` on 2026-11-26", against the logs of the eight shares of `make -C hdl test` of that day, after the last change of the FPU (804dd41):

| Row | The table | The logs |
|---|---|---|
| `XMUL` | 62 | 68: "command 1E took at most 68 cycles, line 6391, bound 120", a random pair with a subnormal product. The shares give 60, 62, 62, 60, 62, 60, 60, and 68. |
| `AND`, `OR`, `XOR`, `NOT`, `SHL`, and `SHR` | 58 to 60 | 56 to 60: `NOT` takes 56 at most |

The other 18 rows equal the logs, `SIN` and `COS` at 5721 and 5798 and `TAN` at 6108 among them.

**Fix:** 68, and 56 to 60. DEVICES.md §11.5 says "`XMUL` … takes some 60 cycles", which still holds for most operands.

**Resolved.** The table says 56 to 60 for the bit commands and 68 for `XMUL`, as the logs of the eight shares do.

### 2.6 DEVICES.md §11.3: the table of 2/π has 1176 bits, not 1584

"they reduce any finite X as musl's `__rem_pio2_large` does, by the 1584 bits of 2/π in its table, which `KX` reads 24 at a time". musl's table has 66 entries of 24 bits, 1584 bits. The FPU's table, which `KX` reads, has the first 49 of them, 1176 bits, behind two zeros: `emulator/test/fpu_seq.py` says "the first 49 entries of musl's ipio2 … the bits of 2/pi that the reduction of the largest binary64 value needs", and `TABLES['ipio2']` has 51 entries, 49 of them not 0. A comment of `emulator/test/fpu_model_test.py` says the same: "The largest double, whose n takes all 1584 bits of the table".

**Fix:** "by the first 1176 bits of 2/π of its table, all that a binary64 value needs, which `KX` reads 24 at a time", and the comment.

**Resolved.** DEVICES.md §11.3 says "the first 1176 bits of 2/π in its table, all that a binary64 value needs", and the comment of `fpu_model_test.py` has 1176 too.

### 2.7 The float library has 409 words, not 400

804dd41 added `_sinf`, `_cosf`, and `_tanf` to `runtime/float_fpu.nasm`, 9 words. The file assembles to 409 words on the head, and to 400 on `main`. `_sin`, the first routine of `math.h`, is at word 245, so the float operations are still 245 words, and the functions 164, where they were 155. Four places say 400, and one 155:

- DEVICES.md §11.5, **C.**: "in 155 words more. A program that uses floats is joined with the whole library, 400 words."
- runtime/README.md, "The float library": "the library is 400 words, 245 of them for the float operations".
- runtime/README.md, C library: "the float library comes with it, 400 words more".
- translator/README.md: "all of it, 400 words".

bench/README.md has the sizes of the float benchmark from before, by the same 9 words: "The program is 8632 words" is 8641, and "The program takes 9060 words, 428 more" is 9069. The 428 and the 5.0% hold. No target prints the size of the float library, which is how it went stale.

**Fix:** 409 and 164, and 8641 and 9069. `make -C bench words` could print the library's size beside those of the C library's parts.

**Resolved.** The four places say 409, DEVICES.md §11.5 164 words for the functions, and bench/README.md 8641 and 9069 words for the float benchmark. `words.py` now counts a `.nasm` file as it is, and `make -C bench words` prints `float_fpu 409`, so the figure has a target that gives it.

### 2.8 DEVICES.md §12.4: the model's test checks half of the formulas

"The model gives these, and `emulator/test/opm_model_test.py` checks them." emulator/README.md says the same: it "checks the model against the formulas of DEVICES.md §12.4". The script has eight tests: the pitch, with KF, DT2, and MUL, a tone, the times of the rates, the effective rate, the levels of TL and D1L, the LFO's step and its reset, the rules of the writes, and the DAC. It has no test of DT1, of an attack at r = 62 or 63, of the silence from 0x380 on, of the scale of a modulation and of the feedback, of a channel's clip, of AMD, PMD, AMS, and PMS, of the LFO's waves, or of the noise. No word of `dt1`, `noise`, `feedback`, `AMS`, `PMS`, or `clip` is in the file. What checks those is ymfm, through `make ymfmcheck`, which no gate runs (§4.4), and the reader's comparison of §12.4 with `opm.zig` found them right.

**Fix:** "and `opm_model_test.py` checks the pitch, the rates, the levels, the LFO's period, and the DAC; the others rest on the comparison with ymfm (§12.6)". Or the missing tests, by hand-checked values as the others.

**Resolved.** DEVICES.md §12.4 and emulator/README.md say what the script checks, the pitch, the rates, the levels, the LFO's period, the writes, and the DAC, and that the other formulas rest on the comparison with ymfm (§4.4).

### 2.9 The units of `make timing`: four, not two or three

- RELEASE.md §4: "`release.py check` runs only `make timing` beside them, a Vivado run of three minutes for the core and one for the FPU." It runs four, one after the other: the core, the FPU, the sound, and the sample player (`TIMING_UNITS` of `release.py`). The section "Timing" of the same file has all four.
- hdl/README.md, the table of files: "`timing.tcl` | The Vivado script of `make timing`: the pipelined core, the FPU, or the sound alone". It takes `pcm` too.
- hdl/README.md, the table of targets: "`make timing` | Vivado on the pipelined core alone, out of context, with `UNIT=fpu` on the FPU, or with `UNIT=opm` on the sound", and "3 minutes, 2 for the sound". `UNIT=pcm` is in the section "Timing" and in CLAUDE.md.
- `release.py check --help`: "skip make timing, which is no gate (10 minutes)". The time of the four runs is not measured.

**Fix:** the four units in the three sentences, and the time of the four in the help text, measured at the release check.

### 2.10 emulator/README.md: six small points

- **`fpufunc.nasm`.** "`test/fpufunc.nasm` runs `SIN`, `COS`, `TAN`, `ATAN2`, `EXP`, `LN`, `POW`, `HYPOT`, and `POW2`, one beyond its bound". The one beyond its bound was `SIN` of 2²¹, which now has a result, and is `ASIN` of 2 since 804dd41. `ASIN` is not in the list.
- **`TIME_SKIP` before the `HALT`.** "To hear a program to its last note, let it wait with `TIME_SKIP` before its `HALT`." Without `--step-time` a write of `TIME_SKIP` is ignored, as the same README says of the counters, and the samples end at the halt: the note of DEVICES.md §12.5 with a skip and a `HALT` gives a file of 44 bytes, the header alone. The sentence needs "with `--step-time`", and what a program does without it: it reads `TIME_LO` in a loop.
- **"(Window below)"** in the section "Sound". The section "Window" is above it, and the same file says "see Window above" three times after it.
- **`make dist`.** "It first replays the FPU's vectors in a unit test built for `x86_64-linux-musl`". It replays the sound's too, with `-Dopm-vectors`.
- **Tests.** The account of `make test` has no `test/wav.py`, which runs between `link.py` and `udp.py`, and no `make opmcheck`. "Last, `test/errors.py`" is followed by two more scripts, the models' tests.
- **The archives.** "The files of V1.2 are:", and then "`niceemu-window-V1.2-x86_64-linux.tar.gz` | With the window of `--window`, which plays the sound". The window of `V1.2` plays none. The table wants a tag that has what it says, or no tag.

`emulator/test/window.py` prints "PASS window (13 tests)", and runs 14 since d2b0143, which added `test_player`.

**Fix:** as said at each.

### 2.11 hdl/README.md: what used to be true, and 430 cycles

- **History.** After the FPU's table of `make timing-spread`: "Before #185 the medians were 1.018 and 0.913 ns. The FPU of `V3.0`, which took the start from a decode of the function's number, had 0.424, 0.839, and 1.342 ns in the `default` flow … Before #211, the reads of `FPU_STATUS`, `FPU_REL`, and `FPU_X_S` addressed the stack's distributed RAM with its top, and their paths were the worst, with 0.579 and 0.739 ns at the least." The figures are those of the commits. They say what used to be true, which belongs to HISTORY.md (CONTRIBUTING.md, Documents), and HISTORY.md has nothing of #194, #164, or #211.
- **430 or 422.** "What the tests check": "the sum may be off by the 430 cycles of one sample in the engine". "The sound" and `opm_engine.vhd`: "It takes at most 422 cycles for a sample". An instrumented `tb_opm` in nvc measures 422, from the start to the sample, for each of 20000 samples. The 430 is `C_ENGINE` of `tb_opm.vhd`, the bound of the test: the engine's 422 and a few cycles of the sample clock.

**Fix:** move the three sentences to a section of HISTORY.md on the FPU's timing, and "by 430 cycles, a little more than the 422 of one sample in the engine".

### 2.12 runtime/README.md: 36 routines, and two lists that run together

- **Tests:** "A second program calls the 33 routines of `math.h` the same way". `make -C runtime test` prints "PASS float_fpu (41080 calls of 52 routines, and inline, and 14128 of the 36 routines of math.h)": `sin`, `cos`, and `tan` have float versions in the library since 804dd41.
- **Math functions:** "The others are C, in `libc/src/math/`:" has two items, and after a blank line comes the list from "**Accuracy.**" to "**No `long double`.**", which is about all the functions. The paragraph that stood between the two lists went with musl's files, so Markdown renders one list, and the eight properties read as items of "the others are C".

**Fix:** 36, and a sentence between the lists, such as "These hold for all of them:".

### 2.13 bench/README.md: the model's rules lack the read after an I/O store

4cefe99 gave the model a rule: PREPARE loads no read in the cycle a store into the I/O range leaves WRITE, so a read after one loads a cycle later, counted as the data bus's (#206). The header of `pipecycles.py`, MICROARCH.md §5.3, and HISTORY.md have it. The list of what the model has, in bench/README.md, has "a store that is on the bus from DBUS's store register a cycle after WRITE, and that FETCH waits for", and not this rule. The README's figures are those of the new model.

**Fix:** the rule in the list, after the store's.

### 2.14 Small points

- **DEVICES.md §11.3, the bounds:** "against the exact value to 90 digits". `SIN`, `COS`, and `TAN` are checked at 420 digits, which a huge argument needs (`fpu_model_test.py`, "reduce by pi/2 to 420 digits").
- **DEVICES.md §11.5, Calls:** "up to 15 values in all for `POW`". `TAN` takes 15 too, its operand and a k of 14.
- **DEVICES.md §3 and emulator/README.md, the counters:** with `--step-time`, the cycle counter and the microsecond counter count one "for each step". A write to a full FIFO of the sound or the player counts the microseconds of its wait too, which are no steps: `test/sound.nasm` runs 331 steps and reads 684 in `CYCLE_LO`. §12.3 says so, and §3 does not point there.
- **emulator/README.md, the sound's vectors:** the unit test "must fail on a copy with one wrong sample". The Makefile changes `test/opm.vectors.out` in place, with `sed -i`.
- **TOOLCHAIN.md, the table of tools:** niceemu writes "Console output, the registers, memory dumps, and a trace". It writes WAV files too, and the frames of `--eth-out`, which the row lacked before.
- **Comments.** `hdl/test/tb_opm.vhd`: "a sample is due once in some 700 cycles" and "the next is then some 250 cycles away", but the Makefile runs it at 32 MHz, 572 cycles, as hdl/README.md says. `hdl/Makefile`: the comment of the synthesis check names the sound and not the sample player, which `SYNTH` has, and the comment of `UNITS` has no `tb_pcm`.

**Fix:** as said at each.

## 3. What the documents say that is not so, older than `V3.1`

- **ASSUMPTIONS.md, item 1:** the wait in PREPARE costs a cycle "for a sum on a register just written, which neither benchmark has (MICROARCH.md §5.6)". `make -C bench hazards` counts the sums that PREPARE forms on a register from the previous instruction: no source in mode 001 or 011, but a store in mode 011, 101, or 111 2458 times in `bench.c`, 0.1%, and 5549 times in `hand.nasm`, 1.1%. The cycle model waits for both (`--sum-wait`, bench/README.md). So the benchmarks have such sums, in stores. And the table of §5.6 has no row for either.
- **MICROARCH.md cites §5.6 for three counts that its table does not have:** "Neither benchmark has such a destination (§5.6)", of a register destination in mode 001 or 010, "Neither benchmark has one (§5.6)", of an operation on R15 other than a move, and "a constant count, which is most shifts (§5.6)". All three are true by `make hazards`. The table of §5.6 wants their rows, or the citations want "`make hazards`".
- **hdl/test/README.md:** "`fpu_slow_vectors.py` | The vectors of the slowest `DIGITS`, `SCALE10`, and `FMOD` that a scan found". It has the slowest functions too, and since 804dd41 `SIN`, `COS`, and `TAN` of huge arguments, as hdl/README.md says.
- **RELEASE.md, "Timing":** "The FPU, the sound, and the sample player must keep 1.0 ns on their own paths, and the same at their ports." It reads as 1.0 ns at the ports. `timing_budget.py` gives them the core's 1.5 and 2.2 ns there. The sentence was so of the FPU alone before.
- **Comments.** `hdl/Makefile`, of `timing-spread`: "About 11 minutes for the core with the default flow and 40 with the timing flow", where hdl/README.md and CLAUDE.md have 4 and 9. `hdl/timing.tcl`: "by up to 1.4 ns on the MEGA65", where `SPREAD` has 1.89 ns for the outputs. `hdl/test/programs.py`: "libc_mchess, has most of them", which has 1561079 of the 8353882 steps.
- **bench/README.md:** "What remains is in issue #73." #73 was closed on 2026-11-01, and its last comment says that each of its ideas is done, decided against, or out of scope.
- **bench/README.md, the table of groups of `make compare`:** "read | readbus, readlate, mpu". `pipecycles.py` has `fpu` in the group too, at `V3.0` as now, and the 154501 cycles of the FPU in `float.c` are counted there.
- **release/README.md, `figures`:** "The other programs are not checked." It checks `float` and `float_inline` on the pipelined core too, from the logs of `make slow`, as RELEASE.md §5 and bench/README.md say. So `release.py figures` fails on the tree today: the logs in `hdl/build/` are those of the release check of `V3.0`, with 600538 and 354930 cycles, and the README has the new 577066 and 331137. `make slow` writes new ones, and `release.py check` runs it first.
- **`bench/Makefile`:** "the pipelined core takes about 22 minutes and the multi-cycle core about 38", where bench/README.md has 21 and 57.

**Fix:** as said at each.

## 4. Gaps

### 4.1 The archives of a release carry no notice of ymfm

`make -C emulator dist` packs `niceemu`, the emulator's README, and `LICENSE`, the MIT license of this repository, and with the window the licenses of SDL. From `V3.1` on, both builds have the synthesizer, which follows ymfm, and its three tables. ymfm's license, as `opm_tables.py` gives it: "Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution." Neither archive has it, and the README in the archive names ymfm without the notice.

Older, and the same way: both builds have the character ROM, Spleen 16×32, whose BSD 2-Clause license asks the same, and `emulator/font/LICENSE.spleen` is not in the archives. Both have the FPU's sequences, which follow fdlibm, FreeBSD, and musl under Sun's notices and musl's MIT license (thirteenth review, §5.3).

This is a reading of the licenses, as the review of #209 said of its own, and no legal advice. The notices cost nothing.

**Fix:** `make dist` copies the notices into `licenses/` of both archives: ymfm's, Spleen's, and those of the header of `fpu_seq.py`. A file with ymfm's notice beside the model, as `LICENSE.spleen` is beside the font, gives it something to copy. The emulator's README, under Download, says what `licenses/` holds.

### 4.2 doc/review/decisions.md has nothing of #209 and #216

The branch added entries for #171, #164's `K` and `PICK`, and #210. The two issues of the sound weighed and dropped more, and each choice is in a closed issue alone:

- **A busy flag that a program polls** before each write, as on the chip and the Commander X16 (#209). The FIFO spaces the writes as the chip's busy time does, and no program has to poll.
- **The chip's two ports**, one for the register's number and one for its data (#209). One word has no latch between two writes, so a pause or a memory dump cannot split a write.
- **Timers A and B, and the key on of CSM** (#209). They would be polled timers again, which #162 dropped, and a program that waits reads `TIME_LO`.
- **A model written from Yamaha's datasheet alone**, with all code under MIT (#209). The datasheet does not hold the chip's bits: the LFO's waves, the detune, and the noise are known from ymfm, Nuked-OPM, and measurements. Nuked-OPM is LGPL and jt51 GPL 3, so the model follows ymfm, under BSD 3-Clause.
- **The RTL in the board's repository**, with only the registers here (#209). The rule of bit for bit would make a release here wait for the board.
- **A mixer, or a conversion of the rate, in the device** (#209, #216). The bit-exact output is each device's own samples, and the mixer is the system's.
- **A second clock of 4 MHz**, as some machines with the chip have (#209).
- **An MP3 decoder in RTL, a soft coprocessor with a decoder, and DMA from a ring buffer in RAM** (#216). The first two need a bit-exact model in the emulator and leave NICE out of the work. The third needs a port into the core's RAM, which costs timing.
- **A FIFO of 2048 samples, a highest rate of 96000 Hz, and rates below 1000 Hz** (#216). 2048 is less than two frames of an MP3 file. Nothing needs 96000. At 1 Hz a write to a full FIFO would hold the bus for a second.
- **An underrun that plays the last sample again** (#216). It clicks as well, and leaves an offset.
- **One WAV file with both streams**, mixed at 55930 Hz (#216). It needs a conversion of the rate, and would not be exact.

Two things of #216 are neither done nor dropped, and CONTRIBUTING.md wants an open item in an issue: the measurement of an MP3 decoder through nicewasm, which "decides whether MP3 is a goal at all", and an accelerator for its filterbank. They are in the closed issue's text and comment alone.

**Fix:** the entries above in decisions.md, and an issue, labeled `idea`, for the measurement.

### 4.3 The rule for the I/O page is in no document

The review of #209 decided, in its table of decisions: "The I/O page | It holds control and status words. Tables go in blocks of their own outside it." Its reasons: only 30 of the 256 words were free, an absolute address is a constant word wherever it points, and the page's one property is that an instruction fetch reads 0 there, which matters for a word whose read has a side effect. It gave a budget too: `0xFFFFFF08`–`0F` for sound, `0xFFFFFF10`–`1F` for video, and `0xFFFFFF02`–`07` spare. DEVICES.md §4 says only that the words "are reserved for I/O (§8). No system of this file maps a device there." The next device will be designed without the rule, unless its author reads a closed issue.

**Fix:** the rule, and the budget as far as it is meant, in DEVICES.md §4 or under its memory map.

### 4.4 What no gate runs

DEVICES.md §12 and §12.6 lean on it: "The model follows ymfm … and `make ymfmcheck` compares the two". No job of `ci.yml` runs it, `make slow` does not, and RELEASE.md and `release.py check` do not name it. `make wasmcheck`, the other target that `make test` leaves out for its tools, is in the same place. So a change of the model that departs from ymfm passes every gate, as the emulator and the RTL follow the model, and the vectors are the model's.

I ran it on the head: 20 logs of 30000 samples, `PASS`, in 70 seconds on one CPU. It needs git, the network, and a C++ compiler, which CI's runners have.

`make -C bench mathsteps` and the sizes of the C library's parts in `make -C bench words` are the same: the steps and the sizes of runtime/README.md come from them, they need clang, which bench/README.md does not say of them, and neither `make test`, CI, nor `release.py figures` runs them. They are right today (§5).

**Fix:** a job in `ci.yml` for `make ymfmcheck`, or a step of RELEASE.md §5 by hand, as it needs the network. For the two of `bench/`, a line of RELEASE.md step 2.4, and "needs clang" in bench/README.md.

### 4.5 A WAV file after a signal

emulator/README.md: `--wav FILE` writes the samples "from the start to the halt or the step limit", and "Its header states the sizes once the run ends." A run that a signal ends is not said. `main.zig` dies of the signal before it finishes the files. With `--step-time`, a loop ended by SIGINT after a second leaves a file of 0 bytes. Without it, the reader got 196614 bytes whose header states no samples. A user who stops a long tune with Ctrl-C has no file that a player opens. The console's output is kept in that case: "on SIGINT, SIGTERM, and SIGHUP, which the emulator then dies of", the same README says. The sizes in the header also stop at 4 GiB, some 5.3 hours of the sound, which no document says.

**Fix:** finish the two files before niceemu dies of a signal, with a case in `test/wav.py`. Or say that a signal leaves a file without its sizes.

### 4.6 The sound and the sample player have no formal check, and nothing says so

README.md: "Formal checks cover their ports, five stages of the pipeline, the devices, and the shifter and the ALU for every input." CLAUDE.md, of `make formal`: "the devices". hdl/README.md and hdl/formal/README.md: "a wrapper and a SymbiYosys job for each unit". `FORMAL` of `hdl/Makefile` has neither `opm` nor `pcm`, and the table of the formal checks has no row and no remark for them. Each is a Wishbone slave that holds a request, the sound for up to 1788 cycles and the player for up to 100000. Every other device of `hdl/src` has a job: the SD card controller, the clock, the counters, the fetch statistics, the network station, and the port for Ethernet frames with `formal/wb_slave_check.vhd` on the port, and the math unit and the FPU with assertions of their own for it.

**Fix:** a job for the port of each, with the checker. Or a sentence under "The formal checks" that the two have test benches alone, and "the devices but the sound" in README.md and CLAUDE.md.

### 4.7 A pause, a step, and a watchdog while a write waits

- **DEVICES.md §12** does not say that a pause and a step of the debug link wait for a write to a full FIFO. hdl/README.md says it of both units: "A pause and a step of the debug link wait that long", up to 100000 cycles, 1 ms, for the player at 1000 Hz. §11.5 says it of the FPU's commands.
- **A watchdog.** hdl/README.md and MICROARCH.md §8, of the FPU: up to some 6100 cycles, "and so must a watchdog of the system", and "a watchdog of the system must allow for it". The bullets of the sound and of the player give their 1788 and 100000 cycles, and say nothing of a watchdog, which must allow for 16 times the FPU's longest command. The **Bus decoder** bullet of §8 gives the FPU and the math unit as the reasons to keep the ACKs in order, and not the two new units, which hold theirs longer.
- **What the link shows.** Only emulator/README.md says that `--dump` and the link show the sound's status "as of the program's last read or write of its words". DEVICES.md §12.3 says that the sound always runs, and a host that reads `OPM_STATUS` over the link of the emulator sees a FIFO that does not empty.

**Fix:** a sentence in §12.3 and §12.7, and the watchdog's bound in the two bullets of MICROARCH.md §8.

### 4.8 Small gaps

- **DEVICES.md §8, Sound:** "NiceMonMEGA65 has no sound." The other bullets cite the board's issue, and this one has MJoergen/NiceMonMEGA65#176, open, filed on 2026-11-26.
- **DEVICES.md §1.3, Window:** it says what the window shows, and not that it plays the sound, though §12.3 points there: "The emulator's window (§1.3) plays them".
- **hdl/README.md, Timing:** `make timing` writes `timing_util.rpt`, from which the README's LUTs, registers, and RAMs come. The README lists the other five reports, and no document names this one (§2.3 came of it).
- **hdl/README.md, `formal_fpu`:** `prove` now also proves that X and Y are the slots at the top of the stack, or the canonical NaN, and that a request's flag matches its data (`f_xs`, `f_ys`, and `f_sd` of `fpu.vhd`, from 87e4ef7). The account of the job does not have them.
- **hdl/README.md, The sound:** the engine clears its RAMs for 256 cycles after a reset, with `ready_o` low (`opm_engine.vhd`), which the section does not say.
- **runtime/README.md:** `nice.h`, `nice.zig`, `nice.rs`, and `lib.nasm` have no name and no routine for the sound's words, and the documents of the runtime and the translator do not mention it. A C program plays with `nice_poke(0xFFFFFF08, …)`. The SD card and the network are the same, so a sentence at the row of `nice.h` is all it needs.

**Fix:** as said at each.

## 5. What was checked, and found right

These are recorded so that the next review need not repeat them.

- **DEVICES.md §12 on the emulator.** The example of §12.5, run as written with `--step-time --wav`: 439.94 Hz, a peak of 8160, the status `0x21510980` after its 9 writes, and silence 310 samples after the key off. The example of §12.7: the status `0x10000005`, 8 samples in 1000 µs at 8000 Hz, the underrun flag, the rates 999, 48001, and 0, which set 1000, 48000, and 0, and the words `0x0D` to `0x0F`, which read 0. §12.1 to §12.4 and §12.6 against `opm.zig`, `pcm.zig`, and `cpu.zig`: the words, the status bits, the FIFO of 64, one write a sample, the connections, the reset values, the 1787.94 cycles and 17.879 steps of a sample, the rates and the levels, the DAC, the LFO's range, and the noise. The arithmetic of §12: 4.6 ms for 256 writes, 93 ms and three frames for 4096 samples, 84 and 93 dB, and 0.0008 to 53 Hz.
- **niceemu.** The 28 options of `--help` are the 28 of the README's table. The four usage errors of `--wav` and `--pcm-wav`, and "cannot write", are as documented. `--no-sound` makes `0xFFFFFF08`–`0xFFFFFF0F` memory, and the reserved words beside them are memory. Both memory maps, and the README's make targets against the Makefile. The window's paragraphs against `window.zig`: the 50 ms ahead, the limit of 250 ms, the 10 ms, the second stream, and the change of its rate, read and not run.
- **The emulator's speed.** A loop of 500 million steps, with and without `--step-time` and `--no-sound`, on the head, on a592877, and on `main` (§1.5).
- **`make ymfmcheck`** passes on the head, 20 logs of 30000 samples, at ymfm's commit 81aec25.
- **DEVICES.md §11.** The k of the 14 functions, the six steps of a sequence, `KX`, the 35842 directed and 20002 random vectors, and the bounds: 1.6 ulp for `ATAN2`, 1.1 for `HYPOT`, and 1 for the rest, with 1.523 and 1.028 the worst measured. "A few results by 1 ulp" of `SIN`, `COS`, and `TAN` of a huge argument: of 12000 results on 4000 random arguments, 3 differ from musl's, each by 1 ulp. 14 of the 15 cycle figures of §11.5 are those of hdl/README.md.
- **`hdl/`, the FPU.** 18 of the 20 rows of the cycle table (§2.5), the 15 bounds of `tb_fpu`, each 20% above the slowest, and the cycles of the steps in `fpu.vhd`. The timing of 2026-11-26 against the reports on disk: +0.460, +8.300, +7.958, and +0.811 ns, the medians 1.026 and 0.879, 10090 LUTs, 2919 registers, 5 DSPs, and 5.5 block RAMs, both tables of `make timing-spread`, and the eight ranges of `SPREAD`. `prove` of the FPU takes 2 seconds and `prove_stack` 12 minutes 30 seconds. Each commit under `hdl/src` gives its timing before and after, as CONTRIBUTING.md asks.
- **`hdl/`, the sound and the sample player.** The slacks of both (§2.3), and the player's 183 LUTs, 137 registers, and 4 block RAMs of 36 Kb. Both sections against `opm.vhd` and `pcm.vhd`. Of `tb_opm`: 228 writes, 164 waits, 20000 samples, 2000 at 268 MHz, 572 and 4792 cycles a sample, the 422 cycles of the engine, and "10923 samples differ" for the wrong vector. The paragraph of `tb_pcm` against the test bench.
- **`hdl/`, the rest.** The 16 rows of MICROARCH.md §5.6 for both programs equal `make -C bench hazards`, with "R13 alone is under 1%", and `random_stats.py --test` passes. The new sentences of MICROARCH.md §5.3 agree with `pipe_prepare.vhd`. §8: 6100, 1788, and 100000 cycles. `make programs`: 920 programs, 649 of them distinct, 8353882 steps. `make test` took 4 minutes 39 seconds by its files' times. `src/README.md` lists 27 of 27 files, and the READMEs of `test/` and `formal/` every file. The cores' sources and ASSUMPTIONS.md have no change since `V3.0`.
- **The benchmarks.** Every other figure of bench/README.md. On the emulator: the tables of `bench`, `hand`, `float`, and `float_inline`, Dhrystone, and CoreMark. In the model: the summary and the phases, 16 and 72, 2339144 and 1246552 with the four rules off, 2250869 and 1168357 without `--read-late`, and the 28 figures of `make compare` with its groups and retires. On the pipelined core in nvc: `bench.c` 2341190, `hand.nasm` 1247655, Dhrystone 2253, CoreMark 1068822, `float.c` 577066 with each phase, and `float_inline` 331137. The figures of the multi-cycle core are from the logs of `V3.0`, and stand, as `bench.bin` is the same file and no core changed.
- **The runtime and the translator.** The table of steps against `make mathsteps`, all of it. The words against `make words`: 6059, 3481, 7000, 3516, 2578, and 880, and the nine small ones. The 36 labels are the same in `float_fpu.nasm`, in `math.h`'s imports, and in nicewasm's `MATH_IMPORTS`. `COPYRIGHT` is musl's, and no `__rem_pio2`, `features.h`, `NICE_TRIG_LIMIT`, or `-Os` of the math files is left outside HISTORY.md, the reviews, and the FPU's sources. ABI.md, WASM.md, and DESIGN.md, read whole: no list of imports is stale. The figures of translator/README.md.
- **The demo and the slides** list no devices that the sound belongs in, and `demo/` has no change since `V3.0`.
- **HISTORY.md and decisions.md.** The new sentences of #185, #205, and #206 against the issues and the figures: 23413, 7268, 5723, and 880 words, 3481, 6059, 7000, and 3516, and the 255 and 268 cycles of the model. The entries of #171, #164, and #210 against their issues, with the 6100 cycles of `TAN`.
- **The issues and the board.** The 13 closed issues of the milestone. No document waits for a closed issue of NiceMonMEGA65: `release.py preflight` warns of the board's tag alone (§1.2). MJoergen/NiceMonMEGA65#176 is open.
- **The targets.** Every `make` target that CLAUDE.md and CONTRIBUTING.md name exists, `make ymfmcheck` and `make mathsteps` among them, and the top-level help has them. `make -C doc test` passes: every section that a document cites exists, §12.1 to §12.7 among them. No British spelling, and no "yet" or "until" that waits for something done, in the lines that this release added.

**Not checked.** The core's table of `make timing-spread` and the table of what a system may add to its ports, which need Vivado; the core's RTL has no change, and its one report on disk matches. The durations of the tables of targets. The window on a display, and its sound on a device. The figures of the multi-cycle core. The "3 of 6039" of DEVICES.md §11.3, which no script gives. The sentence of bench/README.md on the cycles of the FPU's unit, "13 cycles for an `ADD` and 15 for a `MUL` of normal operands, and the FPU about 2 more for the command": a `MUL` takes the unit 15, an `ADD` 11 to 15 by its operands, and the model counts 3 more, so it may want "about 3". The code of the sample player beyond what §12.7 says of it (§1.5).
