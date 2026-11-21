# Fourteenth review of the repository, at commit 6234019

Reviewed on 2026-11-21: the ten commits between `V2.4` and the head of `dev-V2.5`, commit 6234019 ("demo: the rows that a board with 25 hides"), before the release `V2.5`. They grow the emulator's screen from 25 rows to 28, and its chunky mode from 160×100 pixels to 160×112, in a window of 1280×896 (#203), in the emulator, the runtime, the demo, and the documents, and keep the 25 rows with `-2004`. And they split `nicedbg.main()` into `add_options()` and `run()`, for a front end that runs nicedbg as one of its subcommands (#202). `hdl/`, the assembler, the translator, and the benchmarks do not change. This review looks at the documents.

**How it was checked.** I read the whole diff since `V2.4`, the documents and the code, and each changed statement against the code: the addresses and counts of DEVICES.md §1.1, §1.3, §1.4, and §1.10, the emulator's option table, its usage text, and its memory map, ABI.md, the READMEs of the runtime, the demo, and the debugger, the slides, and HISTORY.md. I recomputed the figures by hand: the last words of the screen, the 47360 words after it, the 6722 steps of `nice_screen_clear`, the steps and registers of `runtime/test/device.nasm`, and the 1440 steps that the demo's counters grow by. For each fact that changed I searched the tree for the other places that state it: the old sizes, the old last words, the rows 0 to 24, and the window of 1280×800, in the documents, the comments, the usage texts, and the tests. I read DEVICES.md §8 whole, and checked what it and the demo's README say about NiceMonMEGA65 against its checkout, its tags, and the state of the 14 issues of the board that this repository cites. I looked at `doc/window.png`.

On the unchanged tree I ran the tests of the emulator, the runtime, the demo, and the debugger, their type checks, `make -C doc test`, `make -C doc/intro test` and `pdfcheck`, `make wasmcheck`, and `release.py figures`. All pass. CI passed every job on 42a3fae, the first of the two commits of the branch that it ran. On the head one job fails (§1.1), which I reproduced here, with its cause and a fix, in a scratch worktree. When this was written, `hdl`, `formal`, and the two `programs` jobs of the head were still running, and the other ten had passed.

## Summary

**One thing blocks the tag: CI fails on the head** (§1.1). The unit test that 379455f adds to `window.zig` opens two windows and asks for SDL's dummy video driver once. `SDL_Quit` forgets the hint when the first window closes, so the second, that of `-2004`, opens on a real display where there is one, and fails in CI, where there is none. It is a fault of the test, not of the window. The fix is to move one line.

**The release steps are open**, as expected before the tag (§1): RELEASE_NOTES.md has no section for `V2.5` (§1.2), its table of board tags still says "none yet" for `V2.4` and lacks the board's `V2.3.2` (§1.3), and `emulator/build.zig.zon` says `2.4.0` (§1.4).

**The documents of the release agree with the code.** Every address, count, and size that the ten commits state is right, and no document, comment, usage text, or test still has an old one. The four commits that came after the first, each for a place that it had missed, left none that I could find. Three statements are stale or unclear (§2):

- DEVICES.md §8 says that NiceMonMEGA65 does not have the chunky mode yet. The MEGA65 has had it since the board's `V2.3`, and the issue that the sentence cites is closed (§2.1). The sentence was stale in `V2.4` already; this release rewrote the paragraph around it.
- The same paragraph says that a program knows the rows of its system from `NICE_SCREEN_ROWS` "and its kind". The constant is 28 on every system, and no document here says what a program's kind is (§2.2).
- Four places call the 100 rows of pixels of `-2004` those "of 2004". The emulator of 2004 has no pixels (§2.3).

**Three small gaps** (§3): doc/review/decisions.md has nothing of the three ideas that #203 weighed and dropped, the debugger's README does not name `nicedbg.DESCRIPTION`, which no test reads either, and nothing checks a "not yet" of the documents against the board's issue, which is how §2.1 went stale.

Nothing here is fixed, and no issue is filed.

## 1. The release

### 1.1 CI fails on the head: the window's test needs a display for its second window

Job `emulator-window` of the CI run on 6234019:

    zig build test -Doptimize=ReleaseSafe -Dwindow --summary all
    +- run test 118 pass, 1 skip, 1 fail (120 total)
    error: 'window.test.the window is as high as its rows, and shows no word after them (DEVICES §1.1, §1.3)' failed:
           niceemu: SDL_Init: No available video device

The test came with 379455f. CI ran on two commits of the branch, 42a3fae and the head, so this is its first run of the test.

The test sets the hint `SDL_HINT_VIDEO_DRIVER` to `dummy` once, before its loop over the two sizes. Each turn opens a window and closes it, and `Window.close` calls `SDL_Quit`, which forgets the hints. So the first window, with all the rows, is on the dummy driver, and the second, that of `-2004`, is on whatever driver SDL finds. On a machine with a display that is X11: the test passes, and a real window of 1280×800 opens for a moment. In CI there is none.

I ran the test here three ways, in a scratch worktree of the head:

| Run | Result |
|---|---|
| With `DISPLAY` and `WAYLAND_DISPLAY` unset | Fails as in CI: `SDL_Init: No available video device` |
| Under `xvfb-run` | Passes, 119 and 1 skipped |
| With `DISPLAY` and `WAYLAND_DISPLAY` unset, and the hint set in the loop | Passes, 119 and 1 skipped |

`make test` and `release.py check` do not run the test: its gate is the green CI run of RELEASE.md §6, so the tag waits for it. `make -C emulator dist` does not run it either, as its unit tests are those of the build without the window, so the release workflow is not affected.

Three texts say what the fix makes true. emulator/README.md, Window: "Another there opens a window on the dummy driver with all the rows, and one with those of `-2004`". The comment in `main.zig`'s test block: "Its tests need no display". And the message of 379455f.

**Fix:** set the hint for each window:

         for (cases) |case| {
    +        // SDL's dummy video driver needs no display. SDL_Quit, in close,
    +        // forgets the hint, so each window sets it.
    +        _ = c.SDL_SetHintWithPriority(c.SDL_HINT_VIDEO_DRIVER, "dummy", c.SDL_HINT_OVERRIDE);
             var cpu = Cpu.init(testing.allocator);

with the two lines before the loop removed. `make -C emulator window-test` with `DISPLAY` unset then shows the failure before a push does.

**Resolved.** The test sets the hint for each window, and passes with no display: 119 and 1 skipped. `make -C emulator window-test` now runs the unit tests with `DISPLAY` and `WAYLAND_DISPLAY` unset, so that a test that needs a display fails on a desk machine as it does in CI: with the test as it was, the target fails there with the message of CI, and with the fix it passes, `test/window.py` and its 13 tests included. emulator/README.md says so.

### 1.2 RELEASE_NOTES.md has no section for `V2.5`

The newest section is `V2.4`. RELEASE.md step 2.8 asks for the section, and for a row `V2.5`, "none yet", in the table of board tags. `release.py notes` drafts it. The upgrade notes must say at least:

- **The screen has 28 rows** (#203): 2240 words, `0xFFFF0000`–`0xFFFF08BF`, and the chunky mode 160×112 pixels, 17920 words to `0xFFFF45FF`, in a window of 1280×896. It is the interface change of this release, in the address map of DEVICES.md (RELEASE.md §7): the words `0xFFFF3E80`–`0xFFFF45FF` were ordinary memory after the screen, and now show. A program written for 25 rows runs unchanged and leaves the last 3 blank, and a picture of 100 rows of pixels leaves the last 12 as they are.
- **`nice_screen_clear` writes 2240 words in 6722 steps**, where it wrote 2000 in 6002, so an expected step count of a program that calls it grows by 720. `NICE_SCREEN_ROWS`, `screen_rows`, and `SCREEN_ROWS` are 28, and the three names of the pixel rows 112.
- **`--screen` prints up to 28 rows.** A screen that uses rows 0 to 24 prints as before, as the blank rows at the bottom are dropped. In the chunky mode the line is `Screen: 160x112 pixels`, which changes every expected output of the mode, and `--color` prints up to 56 lines of pixels.
- **`-2004` keeps the 25 rows**, the 160×100 pixels, and the window of 1280×800.
- **The demo's typewriter and key codes reach row 27**, and its image changes, so a board that keeps the demo in its ROM builds the ROM again. A board that shows 25 rows hides the last 3 until it follows (MJoergen/NiceMonMEGA65#157).
- **nicedbg has `add_options()`, `run()`, and `DESCRIPTION`** (#202). `main()` takes what it took. `nicedbg.py --help` says "An interactive debugger on the debug link of doc/DEBUG.md.", where it said "nicedbg: an interactive debugger on the debug link of doc/DEBUG.md."
- `hdl/` does not change: the same files, the same ports, and the timing of `V2.4`. The debug link stays version 8, and Zig stays 0.17.0. The figures of the benchmarks are those of `V2.4`: `release.py figures` passes on the head.

**Fix:** write the section, with the line "The version is 2.5.0." under the emulator's heading, and the row of the table.

### 1.3 The table of board tags says "none yet" for `V2.4`, and lacks `V2.3.2`

RELEASE_NOTES.md, the table at its top. NiceMonMEGA65 has a tag `V2.4`, of 2026-11-20, which pins 292fb41, `V2.4` here. It also has `V2.3.2`, of 2026-11-19, which pins 9b5d948, `V2.3` here, as its `V2.3` and `V2.3.1` do. RELEASE.md step 2.8 keeps a row at "none yet" only until the board follows.

**Fix:** `V2.4` in the row of `V2.4`, and `V2.3.2` added to the row of `V2.3`, with the row of §1.2.

**Resolved.** The row of `V2.4` names the board's `V2.4`, and the row of `V2.3` its `V2.3.2` too. The row of `V2.5` comes with the notes (§1.2).

### 1.4 `emulator/build.zig.zon` still says `2.4.0`

RELEASE.md step 2.9 asks for the new tag's version there before `release.py check`, as a change after the stamp makes the stamp stale. **Fix:** `2.5.0`.

### 1.5 The rest of the checklist

- The milestone `V2.5` has two closed issues, #202 and #203, and none open.
- The board's side of #203 is MJoergen/NiceMonMEGA65#157, which is open, and whose review lists what the board changes. Nothing is left to file there.
- The debug link stays version 8, and DEBUG.md §9 needs no row.
- No `make -C hdl timing` and no `make -C hdl sweep` is owed: `hdl/` is not in the diff.
- `release.py figures` passes: `bench.bin` takes 1697007 instructions and 2435862 estimated cycles, as bench/README.md says. `make wasmcheck` passes with 57 files, so the three `.wasm` files of the diff are those that their sources build.
- `make -C doc/intro pdfcheck` passes, so the slides' PDF is that of the `.tex`. No diagram changes.
- CI on the head was not complete when this was written (How it was checked). Cut no tag before every job passes on the release's commit (RELEASE.md §6), §1.1 included.

## 2. Stale and unclear statements

### 2.1 DEVICES.md §8 says that NiceMonMEGA65 has no chunky mode

The **Screen** point of §8 ends: "NiceMonMEGA65 does not have the mode yet (MJoergen/NiceMonMEGA65#144), and its `0xFFFFFF87` reads 0 and takes no write, so a program finds no mode there."

MJoergen/NiceMonMEGA65#144 was closed on 2026-11-17, done in the board's 63f5ef7. The board's `V2.3` has the mode on the MEGA65, where a write of 1 to `0xFFFFFF87` keeps 1, as its release notes and its SYSTEM.md say. Only the Nexys4DDR, whose screen has 8192 words, has no mode, and there the word stays 0. The first point of §8 already says that the board has the mode word at `0xFFFFFF87`.

The sentence was stale in `V2.4`. It matters more now: 42a3fae rewrote the start of the same point to say that the board shows 25 rows until MJoergen/NiceMonMEGA65#157, and left out that its pixels are 160×100 until then, which is the other half of the same difference.

**Fix:** "NiceMonMEGA65 has the mode on the MEGA65 from its `V2.3` (MJoergen/NiceMonMEGA65#144), with 160×100 pixels, which cover its 25 rows, until MJoergen/NiceMonMEGA65#157. The Nexys4DDR, whose screen has 8192 words, has no mode: its `0xFFFFFF87` reads 0 and takes no write."

### 2.2 DEVICES.md §8: a program's "kind"

The same point says: "A program knows the rows of its system when it is built, from `NICE_SCREEN_ROWS` and its kind, so no register tells them."

Two things are wrong with it.

- `NICE_SCREEN_ROWS` is 28 on every system, and so are `screen_rows` and `SCREEN_ROWS`. A program that is built with it does not know that a board shows 25. The sentence before it says so: "a program written for 28 rows loses its last 3 there."
- No document of this repository says what the kind of a program is. The word is from #203. NiceMonMEGA65's PROGRAMMING.md has two kinds of program, one under the monitor and one on its own, and neither tells the rows.

What the sentence is there to record is the decision of #203: no register for the size.

**Fix:** say what holds, such as: "No register tells the rows. The runtime's `NICE_SCREEN_ROWS` is the 28 of §1.1, and a program for a system that shows another number takes it from that system's documents."

### 2.3 Two phrases about `-2004`

**The pixels "of 2004".** The emulator of 2004 has a screen of 80×25 characters and no pixels: the chunky mode is of `V2.3`. Four places say otherwise:

| Place | Text |
|---|---|
| emulator/README.md, Window | "for the 25 rows of text or the 100 rows of pixels of 2004" |
| `emulator/src/frame.zig`, `Size` | "the 25 rows of text and 100 of pixels of the 2004 emulator" |
| `emulator/test/chunky.nasm` | "`--screen` prints only the size, and with `-2004` that of the 2004 emulator" |
| `emulator/Makefile`, `OPTS_chunky_screen2004` | "whose screen keeps the 100 rows of pixels of 2004" |

DEVICES.md §1.10 has it right: the 160×100 "cover the 1280×800 of its 25 rows". **Fix:** "the 100 rows of pixels that cover them", or the like, in the four places.

**"A longer program".** DEVICES.md §1.1: "With `-2004` the screen keeps its 25 rows, which end at `0xBCF`, as 28 would reach into the code of a longer program". The sentence before it says that a screen at `0x400` overlaps the code of every program longer than 1024 words, and that holds with 25 rows as with 28. What 28 rows would add is the words `0xBD0`–`0xCBF`, which come after the screen of 2004 and are the program's. `frame.zig` says it that way: the screen "cannot grow into the code after it". **Fix:** "as 28 would reach into the words after it, `0xBD0`–`0xCBF`, which are the program's".

## 3. Gaps

### 3.1 doc/review/decisions.md has nothing of #203

#203 weighed three ideas and dropped them: a register that tells the size of the screen, a chunky mode that stays 160×100 with 96 black lines below it, and 28 rows with `-2004`. DEVICES.md states how the first and the third came out, in §8 and §1.1, and the second nowhere. decisions.md is where the dropped ideas are kept "so that they are not proposed again", and the closed issues before this one have their paragraphs there, #198 the last.

**Fix:** a paragraph, "A register that tells the size of the screen (#203)", with the reason: a program is built for its system, and the reserved screen words have room if one is wanted later. The other two fit in it, or beside it.

### 3.2 `nicedbg.DESCRIPTION` is in no document and no test

#202 adds three names, and debugger/README.md, On a board, names two: `add_options()` and `run()`. The third, `DESCRIPTION`, is nicedbg's sentence without the program's name in front, for a front end that gives each subcommand the description of its tool, as NiceMonMEGA65's `nicemon.py` does with `module.DESCRIPTION`. The README says only that the front end's parser has "its own program name and description".

No test reads it: `test/link.py` gives its parser a description of its own, and no test looks at `nicedbg.py --help`. A change of the name would pass here and break the board's front end.

**Fix:** name `nicedbg.DESCRIPTION` in the README's point, and have `test/link.py` check that `main()`'s help has it.

### 3.3 Nothing checks a "not yet" against the board's issue

§2.1 went stale when the board closed its issue, and no check here could see it. The documents cite 14 issues of the board. Four of the sentences say "not yet" or "until":

| Sentence | Issue | State |
|---|---|---|
| DEVICES.md §8, the NMI request of the link, twice | MJoergen/NiceMonMEGA65#106 | open |
| DEVICES.md §8, the receive interrupt | MJoergen/NiceMonMEGA65#104 | open |
| DEVICES.md §8 and demo/README.md, the 25 rows | MJoergen/NiceMonMEGA65#157 | open |
| DEVICES.md §8, the chunky mode | MJoergen/NiceMonMEGA65#144 | closed (§2.1) |

The other ten are cited for what the board has, and are closed, as they should be. The two sentences of #157 are new in this release, and go stale the same way when the board follows.

**Fix, optional:** have `release.py preflight`, which already asks `gh` whether it is logged in, list the issues of the board that the documents cite beside a "yet" or an "until", and warn on a closed one. It would be a warning and no gate, as a release here never waits for the board.

## 4. What was checked, and found right

These are recorded so that the next review need not repeat them.

- **The addresses and counts.** 80 × 28 = 2240 = `0x8C0` words, so the last is `0xFFFF08BF`. 160 × 112 = 17920 = `0x4600` words, to `0xFFFF45FF`, and the ordinary memory after it, `0xFFFF4600`–`0xFFFFFEFF`, is 47360 words. With `-2004`, the 2000 words end at `0xBCF` and the 16000 at `0x427F`. 28 rows of 32 lines are 896, and 112 pixel rows of 8.
- **The emulator.** `frame.zig` keeps the full size, and `Size` gives the rows that a run shows. `printScreen`, `printPixels`, and the window's `drawn` read only the words of the size, so with `-2004` the words after `0xBCF`, or after `0x427F`, are never shown. The usage text and the README's option table say the same of `-s`, `--color`, and `-2004`.
- **The cursor.** DEVICES.md §1.4 gives the row as 0 to 27, or 0 to 24 with `-2004`. `Cursor.at` takes a row up to 27 in both cases, and with `-2004` a cursor in rows 25 to 27 is drawn below the lines that the window shows, so it is not seen.
- **The runtime.** `nice_screen_clear` is 1 + 3 × 2240 + 1 = 6722 steps. `device.nasm`'s 6870 steps are its 6150 and 720 more, and R2 = 80 × 27 + 79 = `0x8BF` and R4 = 64 × 27 = `0x6C0` at its end. `nice.h`, `nice.zig`, and `nice.rs` have 28 and 112, their comments say rows 0 to 27, and `test/colors.py` holds the three to the same pixel rows. ABI.md and the README's two tables agree with them.
- **The demo.** `TOP` is 10 and `LAST` 27, so the typewriter has the 18 rows that the README says, its scroll copies 17 rows and its clear fills 18, and the key codes, from row 8, scroll 19. The 23 keys of the fourth input scroll four times in 20 rows, as the 20 did in 17. The counters of F7 grow by 2 × 240 × 3 = 1440 steps. The pages of F5 to F11 keep their layout, so "row 22" and "row 24" of the README's station keys still hold.
- **The documents.** README.md, the emulator's README, with its Window section and its memory map, DEVICES.md's address map and §1.1, §1.3, §1.4, and §1.10, the runtime's README, ABI.md, the demo's README, and the slides, with their PDF, all have the new sizes. HISTORY.md has the old ones, with the date and the reason. No other document states a size of the screen: TOOLCHAIN.md, DEBUG.md, MICROARCH.md, ISA.md, WASM.md, and the READMEs of `hdl/`, `bench/`, and the assembler name the screen without one, or not at all.
- **The screenshot.** `doc/window.png` is 1280×896 and shows `keys.nasm` as the README describes it: the title in yellow on blue, `Hello, NICE!` on row 2, and the cursor after it.
- **The board.** DEVICES.md §8 is right that NiceMonMEGA65's screen has up to 32K words, 32768 on the MEGA65 and 8192 on the Nexys4DDR, that it shows 25 rows, that it serves the link in version 8, and that it does not have the receive interrupt or the link's NMI request. With 28 rows and the debugger's strip of 4, its display of 1280×1024 is full, as HISTORY.md says: 32 × 32 = 1024.
- **nicedbg.** `main()` is `add_options()` and `run()` on a parser of its own, with the same parameters and defaults as before, and the README's sentence on which hook each takes is right. `test/link.py` runs the two on a parser with another program name.
- **`test/window.py`** runs 13 tests and prints 13.
