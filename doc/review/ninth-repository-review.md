# Ninth review of the repository, at commit daf0054

Reviewed on 2026-11-04: the five commits between `V1.4` and the head of `dev-V1.5`, commit daf0054 ("release: V1.5 notes"), before the release `V1.5`. They add the SD card controller of #107 to SYSTEM.md, the emulator, and the FPGA sources, and assign the reserved I/O words of #123. The eighth review looked at the user documentation before `V1.2`. This one asks whether the code does what SYSTEM.md §5 says, whether the emulator and the core agree, whether the tests would catch a departure, and whether the documents and the release steps are ready for the tag.

**How it was checked.** I read the whole diff since `V1.4`: SYSTEM.md §5 and §6, DEBUG.md, MICROARCH.md §8, decisions.md, `emulator/src/cpu.zig` and `main.zig`, `emulator/test/sd.nasm`, `hdl/src/sd_regs.vhd`, `hdl/sim/sd_sim.vhd`, `hdl/test/tb_sd_regs.vhd` and `tb_core.vhd`, `hdl/formal/formal_sd_regs.vhd`, the Makefiles, the READMEs, and the `V1.5` section of RELEASE_NOTES.md. I checked each rule of SYSTEM.md §5 against the emulator's `Sd` and against `sd_regs`, and the two against each other. I re-derived every value of `emulator/test/sd.expected` by hand from the image's bytes, o mod 251, and the program. On the unchanged tree I ran `make all` (every quick test, the type checks, the VHDL style check, and the slides), which passes, and the three formal tasks of `sd_regs`, which pass in 11 s. By hand I ran the probe on a read-only image, which no test does, and with one image in both slots. I checked the board facts of SYSTEM.md §6 against NiceMonMEGA65's design note `doc/SDCARD.md` on its branch `sdcard-design`, and the link's hold against `tb_link.vhd`. CI on `dev-V1.5` was green for ab4f456, and for c8b0ab4 and daf0054 every job but `hdl` and `formal` had passed when this was written; those two were still running.

## Summary

**Nothing blocks the tag.** The emulator and `sd_regs` implement every rule of SYSTEM.md §5 that I could check, and they agree with each other where both apply: the order of the checks, the status bits, what a change of slot and a reset clear, and the words that read 0. The probe's expected values are right. The tests are good: the probe runs on both cores against the emulator, also on a stalling memory and with pauses, `tb_sd_regs` reaches what no program can (busy, a card taken out, an engine error, a reset during a Read and during a Write), and the formal job proves the two ports. The release notes say what changed and who must act.

**Two statements in SYSTEM.md are wrong or will be read as wrong**, and should change before the tag: §5 says a system has one or more slots while §6 allows `SD_SLOTS` 0, which `sd_regs` cannot provide (§2.1); and §6 says NiceMonMEGA65 has two SD card slots, where the board has no controller yet (§2.2). **Four lists of the devices are stale**: README.md's, hdl/README.md's, CLAUDE.md's, and the header of the probe names an image file that does not exist (§3). Each is a sentence. **Two release steps are still to do** (§1): the version in `emulator/build.zig.zon`, and the date of the section at the tag.

## 1. The release

### 1.1 `emulator/build.zig.zon` still says `1.4.0`

RELEASE.md step 2.9 asks for the new tag's version there before `release.py check`, as a change after the stamp makes the stamp stale, and `release.py tag` refuses a tag it does not match. **Fix:** `1.5.0`, in a commit before `release.py check`.

**Resolved**: `emulator/build.zig.zon` says `1.5.0`.

### 1.2 The rest of the checklist

- The date of the `V1.5` section is set at the tag, as the commit says.
- No row of DEBUG.md §9 is needed: the link's bytes, registers, and rules do not change. The new sentences of §6 and §7.3 describe the system around it.
- `release.py check` runs the formal checks, `make slow`, and the timing; CI must be green on the commit to tag. The `hdl` and `formal` jobs of the last two commits were still running when this was written.
- Milestone `V1.5` has no open issue: #107 and #123 are closed by the commits.

## 2. SYSTEM.md

### 2.1 §5 says one or more slots, §6 allows `SD_SLOTS` 0, and `sd_regs` allows neither

Line 219: "A system has one or more slots for cards." Line 319: "A system without an SD card controller has nothing at `0xFFFFFFA0`–`0xFFFFFFAF`, or one with `SD_SLOTS` 0." `hdl/src/sd_regs.vhd` line 61 has `G_SLOTS : positive range 1 to 16`, so a board cannot build the second kind from the repository's sources. A program that reads `SD_SLOTS` to decide is fine either way, but the two sentences contradict each other. **Fix:** one rule. The simplest is to drop "or one with `SD_SLOTS` 0" from §6, so that a system either has the controller with at least one slot or has nothing there. If the 0 case is wanted, say in §5 that a system has zero or more slots, and in hdl/README.md that `sd_regs` needs at least one.

**Resolved**: §6 no longer allows a controller with `SD_SLOTS` 0: a system has the controller, with at least one slot, or nothing at its addresses.

### 2.2 §6 says NiceMonMEGA65 has two slots

Line 319: "NiceMonMEGA65 has 2 slots on the MEGA65: slot 0 is the microSD slot at the back, and slot 1 the full-size slot underneath, the only one with write protect. On the R3, slot 1 has no working card detect (§5). The Nexys4DDR has 1, its microSD slot." The facts match the board's design note (`doc/SDCARD.md` on its branch `sdcard-design`), but the board has no SD card controller yet: its engine is MJoergen/NiceMonMEGA65#55 and MJoergen/NiceMonMEGA65#63, and the table at the top of RELEASE_NOTES.md says `none yet` for `V1.5`. The documents say only what is true now (CLAUDE.md), and the eighth review's §6.5 removed a sentence of the same shape about the board's monitor. **Fix:** state the hardware, and the numbering as a plan: "The MEGA65 has 2 slots: the microSD slot at the back, and the full-size slot underneath, the only one with write protect, whose card detect does not work on the R3. NiceMonMEGA65 plans to number them 0 and 1 (MJoergen/NiceMonMEGA65#55). The Nexys4DDR has 1, its microSD slot."

**Resolved**: §6 says what the MEGA65 and the Nexys4DDR have, and that NiceMonMEGA65 plans to number the MEGA65's slots 0 and 1, with its issue.

### 2.3 Two sentences of §5 that read oddly

- Line 296, Reset: "Then the controller is idle, with slot 0 selected, ..." and three sentences later "Busy may read 1 after reset for as long as the Write takes". Both are true, but the first reads as if the second could not happen. **Fix:** "Then, or when that Write ends, the controller is idle, ..."
- Line 285: "If it succeeds, it sets "ready" to 1, the type, and `SD_LAST`; if it fails, "ready" stays 0." For an Init of a card that was ready, `sd_regs` clears "ready" when the command starts (line 276 of `sd_regs.vhd`), so a failed Init leaves it 0 whatever it was. "Stays" hides that. **Fix:** "if it fails, "ready" is 0."

**Resolved**: The reset paragraph says the controller is idle then, or when that Write ends, and a failed Init leaves "ready" 0.

## 3. The other documents

### 3.1 README.md's list of the emulator's devices ends at the timer

Lines 45–49: "the devices of doc/SYSTEM.md: the console, the 80×25 character screen, the math unit, the performance counters, and the timer." **Fix:** ", the timer, and the SD card controller".

**Resolved**: The list ends with the SD card controller.

### 3.2 hdl/README.md's list of `tb_core`'s slaves ends at the timer

Line 439: "In `tb_core`, slave 0 is the memory model, the default slave, then come the math unit, the performance counters, and the timer." The fetch statistics have been slave 4 since they were split out, and the SD card controller is slave 5 (`C_SD` in `tb_core.vhd`). **Fix:** ", the timer, the fetch statistics, and the SD card controller".

### 3.3 CLAUDE.md names the devices of SYSTEM.md without the SD card

Line 21: "the devices that the emulator maps into the I/O range (console, math unit, counters, timer)". **Fix:** add "SD card".

**Resolved**: CLAUDE.md names the SD card among the devices.

### 3.4 Two headers name what the code does not do

- `emulator/test/sd.nasm` line 1: "Slot 0 holds test/sd.img, a copy that the Makefile makes for each run". The Makefile (line 65 and 85) makes `test/sd.img.out`, which `.gitignore` covers as `test/*.out`. **Fix:** name `test/sd.img.out`.
- `hdl/sim/sd_sim.vhd` line 23, contract b): "An image file is empty or a multiple of 512 bytes long. Otherwise the simulation fails at time 0." The assertion at line 87 refuses an empty file, as the emulator does. **Fix:** "An image file is a multiple of 512 bytes long, and not empty."

Not worth changing: the `V1.2` and `V1.3` sections of RELEASE_NOTES.md cite "SYSTEM.md §5" for the systems built on the FPGA core, which is §6 now. They are the messages of those tags.

## 4. What is correct

The rules of SYSTEM.md §5, in the emulator (`Sd` in `cpu.zig`) and in `sd_regs`:

- The checks of a command and their order: no card (1), then not ready (2) and out of range (7) for Read and Write, then write-protected (6) for Write. A refused command changes nothing else, and commands 3 to 15 do nothing, `SD_ERROR` included. `tb_sd_regs` and the unit tests check the order, and the probe the rest.
- The status: present, ready, changed, write-protected only with a card, the type only while ready, and `SD_LAST` 0 while not ready. A slot at or above `SD_SLOTS` shows no card and fails every command with error 1, in both, with no index out of range in either (`card()` returns null first; `slot_bit` returns '0').
- A change of `SD_SELECT` to another slot clears "ready"; to the same slot it does not. Init clears "changed" of its slot and, in `sd_regs`, "ready" until it ends well. A card taken out clears "ready", and one put in sets "changed" (`seen_r`).
- Reset: slot 0, `SD_CHUNK`, `SD_LBA`, `SD_ERROR`, and "ready" 0, "changed" where a card is present, the buffer kept. In `sd_regs` a running Write goes on with `quiet_r`, keeps its own slot and sector while `SD_SELECT` and `SD_LBA` read 0, ignores the writes that busy ignores, and reports nothing at its end; any other command gets `abort_o`. `tb_sd_regs` runs both.
- The buffer: 128 words, little-endian, 8 at a time through `SD_CHUNK`, which takes a write at any time. The probe reads chunks 0, 2, 3, and 15 of a sector whose bytes are known, writes a word of chunk 3 to the other sector, and reads it back; the emulator's values are the ones I computed from o mod 251. In `sd_regs` the four byte lanes, the registered read, and the engine's byte port a cycle behind its address give the same words, and the Write-then-Read in the probe shows it on both cores.
- Busy: with `G_HOLD_ACK` the ACK of the write that starts a command waits for `done_i`, so the core never sees busy 1 and the trace is the emulator's; without it, a read in the next cycle sees busy 1, and `tb_sd_regs` checks what busy ignores. The formal job proves that at most one ACK is owed, that STALL is high exactly while one waits, that every other request is answered in the next cycle, that no command starts while one runs, and that its command, slot, and sector hold until it ends.
- `SD_LBA` is compared unsigned with `SD_LAST` (`numeric_std_unsigned`), so a card of 2³² sectors works, and `openImage` refuses a file of more than 2³² sectors.

The emulator around it:

- `--sd0` and `--sd1` parse as the other options with a value do, and `errors.py` covers a missing value, a missing file, a directory, an empty file, and 700 bytes.
- A file that cannot be opened for writing is a write-protected card. No test takes this path, so I ran the probe on a read-only image: "changed" and write-protected after reset (`0x34`), ready with the type (`0x22C`), the Write refused with error 6, the sector unchanged, and the error bit beside write-protected (`0x26`).
- The same image in both slots works, each slot with its own handle.
- The debug link reads with `peek` and writes with `Cpu.write`, so a host reads and writes the registers as the processor does, with no rule of its own. `stopped`, which `Cpu.write` honors, is set only when a hold, a start, or a pause request ends a console read that waits, and the rest of that step writes nothing, as before. A link start calls `Cpu.reset`, which resets the controller with the other devices and keeps the images.
- No program of the repository used `0xFFFFFFA0`–`0xFFFFFFAF`, as the upgrade note says: no `.nasm`, `.c`, `.zig`, `.rs`, or `.py` file names the addresses.

The simulation and the board:

- `tb_link.vhd` gives the devices a reset of one cycle when the hold falls (`dev_rst`), not throughout the hold, so the promise of §5 that a host can use the card while the processor is held holds for a board that follows DEBUG.md §7.3.
- `sd_sim` samples `start_i` and `abort_i` a cycle after `sd_regs` raises them, as registered outputs are sampled; `done_o` is high for one cycle, and `buf_we_o` is low by the cycle after an abort, within what `formal_sd_regs` assumes of an engine.
- `tb_core`'s decoder sends `0xFFFFFFA0`–`0xFFFFFFAF` to slave 5 and nothing else changes; the `programs` jobs of CI, which elaborate `tb_core` with `sd_sim` in nvc, pass for both cores.
- The cores, `wb_dmux`, and the debug link do not change, so no timing run was needed, and the benchmark's cycle counts cannot have changed.
- SYSTEM.md's memory map, §3's split row, §6, and emulator/README.md's map agree on every range and count: 29 words at `0xFFFFFF83`–`0xFFFFFF9F`, 16 for each block, 80 at `0xFFFFFFB0`–`0xFFFFFFFF`.
- DEBUG.md's "Start", "Pause", and §7.3 "Counters" bullets say what the controller does at a reset and during a pause, and agree with §5. decisions.md records the designs left out, with the reasons.
- The section references moved from §5 to §6 in DEBUG.md, ABI.md, `debug_link.vhd`, and `tb_link.vhd`, and `make -C doc test` passes.
