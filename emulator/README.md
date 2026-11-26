# niceemu

An emulator for the NICE processor, written in [Zig](https://ziglang.org). It implements
[doc/ISA.md](../doc/ISA.md) and the devices of [doc/DEVICES.md](../doc/DEVICES.md), and runs the `.bin` files that
[niceasm](../assembler/README.md) writes.

It needs Zig 0.17 (tested with 0.17.0), and Python 3 for `make test`.
The window of `--window` needs a build with `-Dwindow`, below.

## Download

Each [release](https://github.com/MJoergen/nice_cpu/releases) from V1.2
on has niceemu built for x86_64 Linux, so it can run without Zig. The
files of V3.1 are:

| File | What it is |
|---|---|
| `niceemu-V3.1-x86_64-linux.tar.gz` | Without the window. Static, so it runs on any distribution. |
| `niceemu-window-V3.1-x86_64-linux.tar.gz` | With the window of `--window`, which plays the sound. Needs glibc 2.31 or later, and X11 or Wayland for the window. Has the licenses of SDL in `licenses/`. |
| `SHA256SUMS` | The SHA-256 of both. |

Each archive holds one directory, with `niceemu`, this README, and the
license:

    $ sha256sum -c --ignore-missing SHA256SUMS
    $ tar xzf niceemu-V3.1-x86_64-linux.tar.gz
    $ niceemu-V3.1-x86_64-linux/niceemu --help

Both are built for the baseline x86_64 CPU, with ReleaseSafe, as
`make build` builds. `make dist` builds them, below.

## Build and test

    make          # unit tests, example and probe programs, test/errors.py, the FPU's model and vectors, the sound's model and vectors
    make build    # just build zig-out/bin/niceemu
    make window   # build it with the window of --window
    make window-test  # build it so, and run test/window.py
    make dist     # the files of Download, in dist/
    make fpu-long # the FPU's vectors with a random sequence of a million accesses
    make ymfmcheck  # the model of the sound against ymfm (git, a C++ compiler)
    make bincheck # fail if a probe's .bin is not what its .nasm assembles to
    make bins     # reassemble the probes' .bin files, after a change to a .nasm
    make typecheck  # mypy --strict on the Python of test/, tools/, and font/

`make window` builds niceemu with `zig build -Dwindow`. The window uses
[SDL 3](https://libsdl.org), which the build fetches from
[castholm/SDL](https://github.com/castholm/SDL), pinned by its hash in
`build.zig.zon`, and compiles from source, with no system packages. The
first build takes a few minutes of CPU time; later ones take SDL from the Zig
cache. Zig unpacks the source into `zig-pkg/`, which `make clean`
removes. Without `-Dwindow`, the build fetches nothing and needs only Zig.
`make test` and `make build` build without the window.
`make window-test` runs `test/window.py` on that build, with SDL's dummy
video driver, so it needs no display (see Window below). What `make test`
runs is under [Tests](#tests), at the end.

`make dist` builds the two files of Download in `dist/`, and the
release workflow, `.github/workflows/release.yml`, runs it on each tag.
It builds niceemu for `x86_64-linux-musl` without the window, and for
`x86_64-linux-gnu.2.31` with it, as SDL loads the libraries of X11 or
Wayland at run time, which a static build cannot. It first replays the
FPU's vectors and the sound's in a unit test built for
`x86_64-linux-musl` with ReleaseSafe. It runs the programs of
`make test` and `test/link.py` on both, `test/errors.py` on the first, and
`test/window.py` on the second. Their names take the tag from the version
in `build.zig.zon`, or from `TAG`. `make programs EMU=PATH` runs the
programs and `test/link.py` on any build, and the test scripts run the
niceemu that `NICEEMU` in the environment names, if set.

## Usage

    niceemu [options] program.bin
    niceemu --link [ADDR:]PORT [options] [program.bin]

The program is loaded, the processor is reset (PC = 0) and it runs until it
halts. A program that loads no word at 0 is refused with status 1, unless
`--link` is given: a program of `nicebuild.py --monitor`, at `0x8000`,
runs behind a monitor, such as the stand-in `runtime/test/monitor.nasm`
(runtime/ABI.md, "Programs under a monitor"). Then the emulator prints why it stopped, the number of steps, and the
registers. A step is one instruction, or a wait step of a skip of
`TIME_SKIP` with `--step-time` (Skipping time below). The PC printed after
a halt is the address after the halting instruction. If the step limit
stops the program first, the first line is `Stopped at the step limit
after N steps, PC=...` instead.

    $ zig-out/bin/niceemu ../assembler/test/count.bin
    Halted (HALT) after 12292 steps, PC=00000009
    R0  00000000 R1  00800800 R2  00000000 R3  00000000
    ...

To assemble a program and run it, with its console input from a file,
with a trace of every instruction, or with the screen in a window:

    ../assembler/niceasm.py hello.nasm            # writes hello.bin
    zig-out/bin/niceemu hello.bin
    zig-out/bin/niceemu --input keys.txt hello.bin
    zig-out/bin/niceemu --trace hello.bin
    zig-out/bin/niceemu --window hello.bin

The [worked example](../README.md#worked-example) of the top-level README
goes through these steps on a small program, and a
[second one](../README.md#worked-example-with-the-window) opens the window.

| Option | Effect |
|---|---|
| `-t`, `--trace` | Print one line per instruction (see below). |
| `-s`, `--screen` | After halting, print the 80×28 character screen, or 80×25 with `-2004`, or only the size of the chunky mode (DEVICES.md §1.10). |
| `--color` | Like `--screen`, with the colors of each word as 24-bit ANSI escapes (see below). |
| `--invert-fg` | Like `--color`, with the foreground inverted, as in the 2004 IDE. |
| `-2004` | Put the screen at `0x400`, as the 2004 emulator does, with 25 rows, and 100 rows of pixels. The window of `--window` is then 1280×800. |
| `-d`, `--dump ADDR:N` | After halting, print N memory words from ADDR. May be repeated. |
| `-n`, `--max-steps N` | Stop after N steps. There is no limit by default, so a program that never halts runs until it is killed. |
| `-i`, `--input FILE` | Read the console's input from FILE instead of stdin; `-` is stdin. A directory is an error. |
| `--sd0 FILE` | Put a card into SD card slot 0, with FILE as its image: the card's 512-byte sectors in order. A FILE that cannot be written gives a write-protected card. An empty FILE, or one whose size is not a multiple of 512 bytes, is an error (see SD card below). |
| `--sd1 FILE` | The same for slot 1. |
| `--eth-in FILE` | Receive the Ethernet frames of FILE, one per line in hex, at the write that enables the port and at each frame sent (see Ethernet frames below). A line that is not hex, or whose frame is not 14 to 1514 bytes, is an error. |
| `--eth-out FILE` | Write the frames sent, the program's and the station's, to FILE, one per line in hex, without the padding to 60 bytes. A line of it is a valid line of `--eth-in`. |
| `--eth-udp [ADDR:]PORT` | Receive frames as UDP datagrams on PORT of ADDR, `127.0.0.1` if no ADDR is given, written as for `--link`. It needs `--eth-peer`. |
| `--eth-peer [ADDR:]PORT` | Send the frames sent to this address, one UDP datagram each, padded to 60 bytes. It needs `--eth-udp`. |
| `--symbols FILE` | Read the labels of `niceasm.py --symbols` from FILE, and name the location of a halt other than `HALT`, of the step limit, and of a wasm trap (see Symbols file below). |
| `--stack` | After the halt or the step limit, print the first value of R13, the lowest since, and the words between them (see Stack below). |
| `--no-cycle-counter` | Make the cycle counter, the microsecond counter, and the clock of the time of day, `0xFFFFFF40`, `0xFFFFFF41`, and `0xFFFFFF44`–`0xFFFFFF49`, ordinary memory (see Performance counters below). |
| `--no-fpu` | Make the floating-point unit, `0xFFFFFF88`–`0xFFFFFF8F`, ordinary memory, as on a system without one (see Floating-point unit below). |
| `--no-sound` | Make the sound, `0xFFFFFF08`–`0xFFFFFF0F`, ordinary memory, as on a system without one (see Sound below). |
| `--wav FILE` | Write the samples of the sound to FILE, a WAV file of 16-bit stereo at 55930 Hz, from the start to the halt, the step limit, or a signal that ends the run (see Sound below). An error with `--link`, `--window`, or `--no-sound`. |
| `--pcm-wav FILE` | Write the samples of the sample player to FILE, as `--wav`, at the rate of its first sample (see Sound below). An error with `--link`, `--window`, or `--no-sound`. |
| `--no-font` | Make the font RAM and the character ROM, `0xFFFE0000`–`0xFFFE3FFF`, ordinary memory, so that a program that reaches them runs as on an FPGA core with none (see Window below). |
| `--no-screen-mode` | Make the screen's mode word, `0xFFFFFF87`, ordinary memory, so that a program that reaches it runs as on an FPGA core with none (DEVICES.md §1.10). The window shows the chunky mode while the word is 1. |
| `--step-time` | Count one microsecond per step in the microsecond counter, and in the clock of the time of day from 0 with "set" 0, rather than the host's time, so that a run counts the same each time, and make a write of N to `TIME_SKIP`, `0xFFFFFF5F`, skip N wait steps (see Performance counters and Skipping time below). |
| `--window` | Show the screen in a window while the program runs, and keep it after the halt until it is closed (see Window below). Needs a build with `-Dwindow`. |
| `--speed N` | With `--window`, run N steps a second, for a program that keeps time by counting steps; 1000000 is one step per microsecond. 0, the default, runs as fast as the host can, and sleeps while the program waits for a key or a time (see Window below). |
| `--link [ADDR:]PORT` | Serve the debug link on PORT of ADDR, `127.0.0.1` if no ADDR is given, instead of running the program once (see Debug link below). ADDR is an IPv4 address, or an IPv6 one in brackets, such as `[::1]`. With PORT 0, pick a free port and print `link: port N` on stderr. The program file is optional. `--input` is an error with it. |
| `-h`, `--help` | Print the usage on stdout. |

**Symbols file.** `niceasm.py --symbols` and `nicebuild.py --symbols` write one: one line per label, with an 8-digit hex address, a space, and the label. Only the labels of instructions and data are in it, not `.EQU` names. With `--symbols FILE`, niceemu prints `At label+0x1f`, the location of the halt, after a halt other than `HALT`, or at the step limit. The label is the nearest one at or before the address, the first in the file if several are at one address, so a second label at the same address is never named. After a halt at the default wasm trap handler, `___wasm_trap`, it also prints `Trap CODE (cause) at label+0x1f`, from R1 and R2 ([WASM.md](../translator/WASM.md)). `nicedis` reads the same file.

**Stack.** niceemu tracks R13, the stack pointer of software (ISA.md §9.1), on every run: its value after the first step that changes it, as it is 0 after reset, and the lowest since. A push, a `SUB`, and the push of a `CALL` count alike. With `--stack`, niceemu prints them after the registers, as `Stack: first SP=ffffff00, lowest SP=fffffef9, 7 words below`, or `Stack: R13 never changed`. The words below are how much stack the run needed. Only the printing is an option, as R13 is SP only by convention. niceemu stops on no overflow: its memory has all 2³² words, so a stack from `0xFFFFFF00` runs into the screen, and then into the character ROM, which drops its writes, long before it could reach a program at 0. On a board whose RAM repeats through the address space, it reaches the program much sooner, and a watchpoint of the debugger can guard it ([debugger/README.md](../debugger/README.md)). `test/stack.nasm` is the probe.

Numbers in options are decimal, or hex after `0x` or `0X`, with no sign or
`_`.

`--dump` prints eight words per line. Each line starts with the address of
its first word and a colon, and each word is 8 hex digits after a blank. `--screen` prints `Screen:` and then one line per row,
starting with `|`, with trailing blanks dropped from each row and blank rows
dropped from the bottom. Characters outside printable ASCII show as blanks.
Both come after the registers, the dumps first.

With `--color`, each row also has the colors of its words (DEVICES.md §1). The
background is bits 31..20 and the foreground bits 19..8, as 4-bit red, green,
and blue. The row has one escape, `ESC[48;2;R;G;B;38;2;R;G;Bm`, at its start
and wherever the colors change, and `ESC[0m` at its end. The foreground is
not inverted, as it is in the 2004 IDE, unless `--invert-fg` asks for it. Then
each foreground component `n` becomes `0xF − n`, and the background stays.

In the chunky mode of DEVICES.md §1.10, `--screen` prints only `Screen:
160x112 pixels`, or `Screen: 160x100 pixels` with `-2004`. `--color` prints that line and then the pixels, two rows
to a line, starting with `|`: each pair is an upper half block, `▀`, with
the color of the top pixel, bits 31..20 of its word, in the foreground and
that of the bottom one in the background, with the escape
`ESC[38;2;R;G;B;48;2;R;G;Bm` at the start of the line and wherever the
colors change, and `ESC[0m` at its end. Black pairs are dropped from the end
of each line, and lines with no pixel that is not black from the bottom.
`--invert-fg` does not change the pixels.

The exit status says how the run ended:

| Status | When |
|---|---|
| 0 | `HALT`; or, with `--link`, a signal (see Debug link below). |
| 1 | A usage, file, or memory error, an out-of-memory condition, or an output that cannot be written. |
| 2 | The other halt: a reserved control word (ISA.md §5.3). |
| 3 | The step limit. |
| 4 | The window of `--window` was closed before the halt or the step limit. |
| 141 | stdout is a pipe that closed early, as in `niceemu -t x.bin \| head`. niceemu stops quietly, as a filter killed by SIGPIPE would. |

Diagnostics go to stderr, and only `-h` prints on stdout. `--` is not an
option, so a program path that starts with `-` cannot be given, and an
empty argument counts as no program.

## Window

With `--window`, niceemu shows the 80×28 screen in a window of 1280×896
pixels while the program runs, as DEVICES.md §1 specifies, or the 160×112
pixels of the chunky mode, when the mode word at `0xFFFFFF87` selects it
(DEVICES.md §1.10). With `-2004`, the window is 1280×800, for the 25 rows
of text of 2004, or the 100 rows of pixels that cover them. A resized window
scales the screen and keeps its aspect. The characters are from the font
that the font base at `0xFFFFFF86` selects (DEVICES.md §1.8): the
character ROM, Spleen 16×32 as on NiceMonMEGA65, with blocks and arrows
at `0x80`–`0x99`, or the font RAM at
`0xFFFE0000`, which a program writes. Spleen is in `src/font.zig`, which
`font/gen_font.py` generates (`font/LICENSE.spleen` has its license).
`--no-font` makes the words of both fonts ordinary memory, as on an FPGA
core with no font, so that the traces of the random programs of the HDL
tests can be compared ([hdl/README.md](../hdl/README.md)). The window
still draws Spleen, and bits 15..0 of the font RAM's words. The
window draws a cursor from `0xFFFFFF80`–`0xFFFFFF82`, and redraws about 60
times a second. A cell is redrawn when its word, the cursor on it, or its
glyph changes, and a pixel of the chunky mode when its color changes.
`-2004` and `--invert-fg` work with it as with `--screen`.

The console writes to stdout, as without the window. It reads the file of
`--input`, if given, and then the keys typed into the window, with the
bytes of DEVICES.md §1, and not stdin. A read with no byte waiting returns
0, and a read never returns `0x200`. The keys wait in a buffer of 2048
bytes, and a key whose bytes do not all fit is dropped.

The emulator runs as fast as the host can, as without the window, and the
microsecond counter keeps the host's time (DEVICES.md §1.6). While the
program waits for a key or for a time, niceemu sleeps: a console read that
finds no byte and a read of `TIME_LO` are idle reads, two of them within
1000 steps of each other mean a wait loop, and at each step of one the
window waits for an event, up to 1 ms when the loop has read `TIME_LO`
within the last 1000 steps and up to 10 ms when it waits for a key alone.
A key still reaches the program at once, a wait on `TIME_LO` may end up to
1 ms late, and a program that polls less often than once in 1000 steps
never sleeps. `--speed N` runs N steps a second instead, for a program
that keeps time by counting steps: at `--speed 1000000`, one step per
microsecond, a loop of P steps lasts P microseconds, and the cycle
counter counts at 1 MHz, where on a board of 100 MHz it counts at
100 MHz. A run that falls more than 100 ms behind its
rate goes on from there, rather than catch up in a burst. A skip of
`TIME_SKIP` with `--step-time` takes no host time, as niceemu counts its
wait steps at once, but `--speed` runs them at its rate as any steps, a
chunk at a time.

At the halt, or at the step limit, niceemu prints the report as without
the window, and the window stays, with the last screen, until it is
closed. Then niceemu exits with the status of the halt. Closing the window
before ends the run: the first line of the report is `Stopped when the
window was closed after N steps, PC=...`, and the exit status is 4. SIGINT,
SIGTERM, and SIGHUP end niceemu as without the window, also while the
window stays after the halt. Ctrl-C in the window is a key, `0x03`. If no
window can be opened, as without a display, niceemu prints SDL's error
and exits with status 1 before the run.

The window plays the samples of the sound (DEVICES.md §12) on the
default audio device, which SDL converts from the sound's rate, 55930 Hz,
to the device's. It computes the samples up to now and gives them to SDL
at least every 10 ms, also while it waits for an event and after the
halt, as the sound plays on. Ahead of them goes 50 ms of silence, the
latency, so that the next ones come in time. When the device has played
every sample given, the next ones get the 50 ms again, and when more
than 250 ms wait, as the samples come faster than the device plays them,
those that wait are dropped, and the next ones get the 50 ms. The
samples keep the host's time, so they come at the device's rate. With
`--step-time` they keep the time of the steps, so they sound right only
at `--speed 1000000`. If no audio device can be opened, niceemu prints
`niceemu: no sound:` and SDL's error, and runs without the sound.
`--no-sound` opens none.

The samples of the sample player (DEVICES.md §12.7) go to a second
stream on the same device, which SDL converts from the player's rate and
mixes with the sound's. They get the same 50 ms ahead of them and the
same limit of 250 ms, at their own rate. When the rate changes, the
samples before go to the stream at the old rate, and the stream takes
the new one from there.

With `--link`, the window opens when niceemu starts and stays open over
every run, and shows the screen also while the processor is held, halted,
or paused. The console reads the link's input buffer, into which the keys
go too, as DEVICES.md §1 says, and a read does not wait. So a pause or a
step at a console read is never undone (DEBUG.md §7). The runs sleep in a
wait loop, or keep the pace of `--speed`, as without the link. Closing the
window ends niceemu with status 0, as a signal does.

`test/window.py` runs niceemu with SDL's dummy video driver
(`SDL_VIDEODRIVER=dummy`), which needs no display, but can type no key and
close no window. It checks the report at the halt with `--color`, and
with `-2004` and its 25 rows, the
reads of `--input` and then 0, that stdin is not read, that the default is
faster than `--speed 1000000`, that a program that polls the console
sleeps, that a long skip with `--speed` goes a chunk at a time, that
each of the three signals ends a run with no report, and what happens
without a display. The close of the window, before the halt, after it, and
with `--link`, it checks through a hook of niceemu for the test, as the
dummy driver cannot close one. With `--link`, as a host, it checks that a
read returns 0 until a byte comes, the sleep in the wait loop, and the end
of the input, and that the link is served in a long skip. It plays the
note of DEVICES.md §12.5 on SDL's disk audio driver, which writes the
samples to a file at the sound's rate, and checks them against the
model's: silence, then the model's samples from the first that is not
silence, for at least 0.2 s, and after each silence that the window put
in, a later part of them. It plays 4096 samples of one value on the
sample player at 8000 Hz on the same driver, and checks that the file
holds the value for nearly their 0.512 s, and not much longer. It checks
that `--no-sound` plays nothing, and the warning without an audio
device. The others run on SDL's dummy audio
driver. The key table and the drawing of the screen are unit tests
in `src/keys.zig` and `src/frame.zig`, the keys' way into the link's
buffer one in `src/link.zig`, and the mapping of SDL's key events to the
keys one in `src/window.zig`, which `make window-test` runs. Another
there opens a window on the dummy driver with all the rows, and one with
those of `-2004`, and checks the size of each, 1280×896 and 1280×800,
that the words after its rows do not show, in the text and in the chunky
mode, and that its last row is at the bottom edge. One more gives the
samples of the sound to a stream on the dummy audio driver, paused, and
checks the 50 ms ahead of them, and the drop of too many, and one more
gives the sample player's to their own stream, and checks its rate and
a change of it.
`make window-test` runs these unit tests with `DISPLAY` and
`WAYLAND_DISPLAY` unset, so that a test that needs a display fails there
as it does in CI.

## Program files

A `.bin` file has one line per word, as niceasm writes it (ISA.md §10.4):
an address and a word, both in hex, separated by blanks. niceasm writes 8
digits; the loader accepts 1 to 8, in upper or lower case, and nothing else:
no `0x` prefix, sign, or `_`. Blank lines are ignored, and so are tabs,
trailing blanks, CRLF line ends, and a missing final newline. A UTF-8 byte
order mark is an error. This is more lenient than ISA.md §10.4. Loading the same
address twice and a file with no words are errors.

## Memory map

| Address | Words | Contents |
|---|---|---|
| `0x00000000`–`0x0FFFFFFF` | 268435456 | Ordinary memory. Programs load at 0, or at `0x8000` under a monitor in ROM, as a stand-in for one at 0 shows (runtime/ABI.md, "Programs under a monitor"). |
| `0x10000000`–`0x5FFFFFFF` | 1342177280 | Byte windows (DEVICES.md §9). A data access reaches a word, a byte, or a halfword of words `0x00000000`–`0x03FFFFFF`. Instruction fetches read 0. |
| `0x60000000`–`0xFFFDFFFF` | 2684223488 | Ordinary memory. |
| `0xFFFE0000`–`0xFFFE1FFF` | 8192 | Font RAM (DEVICES.md §1.8). Ordinary memory, but a write keeps only bits 15..0. With `--no-font`, ordinary memory. |
| `0xFFFE2000`–`0xFFFE3FFF` | 8192 | Character ROM (DEVICES.md §1.8): Spleen 16×32, with blocks and arrows at `0x80`–`0x99`, 32 words per glyph. A write is dropped. With `--no-font`, ordinary memory. |
| `0xFFFE4000`–`0xFFFEFFFF` | 49152 | Ordinary memory. |
| `0xFFFF0000`–`0xFFFF45FF` | 17920 | Screen: the characters of 80×28 in its first 2240 words, or 160×112 pixels in the chunky mode (DEVICES.md §1.10). Ordinary memory. With `-2004` it is at `0x00000400`–`0x0000427F` instead, 80×25 or 160×100. |
| `0xFFFF4600`–`0xFFFFFEFF` | 47360 | Ordinary memory. The runtime's stack starts at `0xFFFFFF00` and grows down. |
| `0xFFFFFF00` | 1 | Console. A write prints bits 7..0 on stdout. A read returns the next input byte plus `0x100`, or `0x200` after the end of the input. |
| `0xFFFFFF01` | 1 | Read counter. A data read returns the number of data reads of it since the last write, and a write sets that number. |
| `0xFFFFFF02`–`0xFFFFFF07` | 6 | Reserved for I/O (ISA.md §8.3, DEVICES.md §1.9 and §4). Ordinary memory for data accesses. Instruction fetches read 0. |
| `0xFFFFFF08`–`0xFFFFFF0F` | 8 | Sound (DEVICES.md §12): the FM synthesizer, its write word and its status, and the sample player's three words. With `--no-sound`, ordinary memory. |
| `0xFFFFFF10`–`0xFFFFFF1F` | 16 | Reserved for I/O, like `0xFFFFFF02`–`0xFFFFFF07`. |
| `0xFFFFFF20`–`0xFFFFFF3F` | 32 | Math unit (DEVICES.md §2). Multiplies and divides A and B and counts the bits of A, and divides C and D and takes the square root of C. |
| `0xFFFFFF40`–`0xFFFFFF7F` | 64 | Performance counters (DEVICES.md §3). Cycles, instructions, microseconds, data reads, stores, skips, and jumps, 64 bits each, and `0xFFFFFF52`–`0xFFFFFF5E`, which read 0. The clock of the time of day, at `0xFFFFFF46`–`0xFFFFFF49` (DEVICES.md §10). `TIME_SKIP` at `0xFFFFFF5F`, for `--step-time`. The fetch statistics of the FPGA core, at `0xFFFFFF60`–`0xFFFFFF7F`, read 0. |
| `0xFFFFFF80`–`0xFFFFFF86` | 7 | Reserved for I/O, like `0xFFFFFF02`–`0xFFFFFF07`. `--window` draws its cursor from `0xFFFFFF80`–`0xFFFFFF82` (DEVICES.md §1.4), and takes its font base from `0xFFFFFF86` (DEVICES.md §1.8). |
| `0xFFFFFF87` | 1 | The screen's mode word (DEVICES.md §1.10): 0 for the text, 1 for the chunky mode. A write of another value writes 0. With `--no-screen-mode`, ordinary memory. |
| `0xFFFFFF88`–`0xFFFFFF8F` | 8 | Floating-point unit (DEVICES.md §11): a stack of 16 doubles, the views of X, and the commands. With `--no-fpu`, ordinary memory. |
| `0xFFFFFF90`–`0xFFFFFF9F` | 16 | Reserved for I/O, like `0xFFFFFF02`–`0xFFFFFF07`. |
| `0xFFFFFFA0`–`0xFFFFFFAF` | 16 | SD card controller (DEVICES.md §5). Two slots, with the images of `--sd0` and `--sd1`. |
| `0xFFFFFFB0`–`0xFFFFFFBF` | 16 | Network station (DEVICES.md §6). The IP and MAC addresses, counts of frames that read 0, and the state of `--link`. |
| `0xFFFFFFC0`–`0xFFFFFFCF` | 16 | Ethernet frames (DEVICES.md §7). A queue of 4 frames and a send buffer, with the frames of `--eth-in` and `--eth-udp`. |
| `0xFFFFFFD0`–`0xFFFFFFFF` | 48 | Reserved for I/O, like `0xFFFFFF02`–`0xFFFFFF07`. |

### Screen

The screen has one word per character, with the character in bits 7..0 and
its colors above. It is ordinary memory, and `--screen` prints the
characters when the program has halted. `test/screen.nasm` writes to it. The
2004 emulator has the screen at `0x400`, where it overlaps the code of any
program longer than 1024 words. `-2004` puts it there for the 2004
programs, such as `print.nasm`.

### Console

The console stores nothing. Its output comes before the `Halted` line, and
with `--trace` it is mixed in with the trace lines. `test/console.nasm`
writes to it. This repository has no UART. A system built on the FPGA core maps one at the same address (DEVICES.md §1).

Without `--window` (see Window above), each data read of the console takes
the next byte of the input, which is
stdin unless `--input` names a file. It returns the byte in bits 7..0 with
bit 8 set, so a 0 byte reads as `0x100`. Once the input has ended, every
read returns `0x200`. A read error on the input counts as its end. For no input at all, give stdin from `/dev/null`, or
`--input /dev/null`. On a terminal, a read waits until a whole line has
been typed, and Ctrl-D ends the input. Before it reads, the emulator
flushes its output, so that a prompt shows before the program waits for
the answer. When stdout is a terminal, it also flushes after each console
write, so that Ctrl-C loses nothing. Otherwise the output is buffered, and
is written when the buffer fills, before a read, and at the end of the run,
and on SIGINT, SIGTERM, and SIGHUP, which the emulator then dies of. Only
SIGKILL loses what is still in the buffer. The signals are noticed every
65,536 steps, and at once while the program waits for console input, which
the signal ends. `test/input.nasm` reads `test/input.txt`. Reads by `--dump`
take no input. `make test` runs every program with stdin from `/dev/null`.

### Read counter

The read counter makes the data reads of ISA.md §8.2 visible: how many
there are, and in which order. It stores nothing else, and `--dump` shows
its count without counting. `test/reads.nasm` uses it.

### Math unit

The math unit holds only its operands, A, B, C, and D. It computes each
result when it is read, so a read never waits, and `--dump` shows the
results for the current operands. Its words store nothing else.
`test/mpu.nasm` and `test/mpu64.nasm` check every result, with division by
zero and the signed overflow, and `test/mpubits.nasm` the bit counts and
the square root.

### Performance counters

The performance counters count the instructions, the steps, and the
microseconds since reset. The emulator has no clock, so its cycle counter
counts one cycle per step, that is, per instruction and per wait step of a
skip, and differs from the FPGA core's, which counts clock cycles.

The microsecond counter counts the host's monotonic time, without the time
the host sleeps, less the time the processor was held, paused, or halted
(DEVICES.md §3). Each read of `TIME_LO` reads the host's clock. A console
read that waits for input counts as running. After `-n` stops a run, the
counter runs on until the report, so only after a halt does `--dump` show
the same count each time. The cycle counter and the microsecond counter
have no fixed ratio: a program that divides one by the other gets the
host's rate of steps, which varies. `--step-time` makes the counter count
one microsecond per step instead, for tests whose output is worked out by
hand. Both counters then also count the microseconds that a write to a
full FIFO of the sound or of its sample player waits (Sound below),
which are no steps.

A read of a low word takes a snapshot of
its counter, and a read of the high word returns the snapshot's high word.
`--dump` shows the low words and the snapshots without taking a snapshot.
Writes are ignored, but for `TIME_SKIP` with `--step-time` (below). `test/perf.nasm` checks the instruction counter, and
`test/time.nasm` the microsecond counter, both with `--step-time`.

The event counters, at `0xFFFFFF4A`–`0xFFFFFF51`, count the data reads,
the stores, the skipped instructions, and the jumps, as every FPGA core
counts them. The words `0xFFFFFF52`–`0xFFFFFF5E` read 0 and ignore
writes. `test/events.nasm` checks each, and that `0xFFFFFF52` reads 0,
and the FPGA cores run it too.
The emulator has none of the FPGA core's fetch statistics, at
`0xFFFFFF60`–`0xFFFFFF7F`: their words read 0 and ignore writes.

`--no-cycle-counter` makes the words of the cycle counter, the
microsecond counter, and the clock of the time of day, `0xFFFFFF40`,
`0xFFFFFF41`, and `0xFFFFFF44`–`0xFFFFFF49`, ordinary memory, like the rest of the I/O range. A program that reads them then
runs the same on the emulator and on an FPGA core whose cycle count
cannot be predicted, so their traces can be compared. The random programs
of the HDL tests run this way ([hdl/README.md](../hdl/README.md)). The
instruction counter stays.

### Floating-point unit

The floating-point unit of DEVICES.md §11, in `src/fpu.zig`, holds the
stack of 16 doubles, its depth, and the four flags. It computes with the
host's doubles, which round to nearest, even on a tie, as §11.1 asks,
and computes the flags itself, so the host's own flags do not matter.
With the S bit it rounds the exact result once, to binary32: where the
host's double is not exact, it first moves it to the neighbor with an
odd last bit on the side of the exact result, which rounds to binary32
as the exact result does. It
writes the canonical NaN for every NaN that it computes. A command runs
when `CMD` is written, at once, so a read never waits. A read of a word
changes nothing, so `--dump` and the debug link show the unit as it is,
and a fetch from its words reads 0, a `NOP`. `--no-fpu` makes its eight
words ordinary memory, as on a system without the unit.

A function of DEVICES.md §11.3, `SIN` to `HYPOT`, runs as a sequence of
steps on the unit's own stack: commands of the unit, and the six steps
that only a sequence has, which push a constant, push an entry of a
table of constants, write a value of the stack, jump, and mark a pole. It runs when `CMD` is written, at once,
as a command does. The steps and the constants are the tables of
`src/fpu_seq.zig`.
`test/fpu_seq.py` writes that file from its programs, one for each
function, and from the same programs the ROM of the cores,
`../hdl/src/fpu_seq_pkg.vhd`:

    python3 test/fpu_seq.py --zig > src/fpu_seq.zig
    python3 test/fpu_seq.py --vhdl > ../hdl/src/fpu_seq_pkg.vhd

Both files are checked in, so a change of a program writes both again.
`make seqcheck`, which `make test` runs, fails if `src/fpu_seq.zig` is
not what the generator writes, and `make -C ../hdl seqcheck` does the
same for the ROM. Without an option, `test/fpu_seq.py` lists the steps
of each function and the constants.

The unit test of `src/fpu.zig` replays the vectors of
`test/fpu_vectors.py` (Tests below): it sets each line's state, makes the access, and compares the
state after it and the value read. `test/fpu.nasm` uses the views and a
few commands of each group, and the two examples of DEVICES.md §11.5, and
`fpu_mem` runs it again with `--no-fpu`. `test/fpustack.nasm` checks the
depth, the stack faults, the sticky flags, a save and a restore of
`STATUS`, an instruction that reads and writes one register of the unit,
and a read of the eight words through `@R9++`. `test/fpudec.nasm` prints
numbers through `DIGITS 15`, and reads one back through `FROMBCD` and
`SCALE10`. `test/fpufunc.nasm` runs `SIN`, `COS`, `TAN`, `ATAN2`,
`EXP`, `LN`, `POW`, `HYPOT`, and `POW2`, `ASIN` of 2, beyond its bound,
and one whose frame does not fit above the stack.

### Clock

The clock of the time of day, at `0xFFFFFF46`–`0xFFFFFF49`, reads the
host's clock of the time of day plus an offset, which a write of
`CLOCK_USEC` sets so that the clock reads the time written (DEVICES.md
§10). "Set" is 1 from the start. The clock runs on while the processor
is held, paused, or halted, and a start over the link leaves it. With
`--step-time` it counts one microsecond per step instead, a wait step
included, from 0 with "set" 0. `test/clock.nasm` checks its reads, its
writes, and its wrap with `--step-time`, and again with
`--no-cycle-counter`, where its words are memory. `test/clockhost.nasm`
checks it on the host's clock.

### Sound

The sound at `0xFFFFFF08`–`0xFFFFFF0F` is the FM synthesizer of
DEVICES.md §12, in `src/opm.zig`, which computes what the model,
`test/opm_model.py`, computes, and its FIFO of 64 writes. It computes
its samples when the program reads or writes its words, and at the end
of the run, for the time since it last did: the microseconds of the
steps with `--step-time`, a skip's included, or else the host's time,
which runs on while the processor is held, paused, or halted. So with
`--step-time` the samples of a run are the same each time, and they end
at the halt. Without `--wav` and a window that plays them, nobody takes
the samples, and the status shows the FIFO alone, so the emulator
computes none: one write of the FIFO takes effect in each sample's
time, as with them, and a long run or a long skip costs the host no
time for the sound. A write to a full FIFO waits for the next sample: with
`--step-time`, the step of the write counts the microseconds of the
wait in the cycle counter, the microsecond counter, and the clock, as
the wait steps of a skip, but not as steps of the run; without it, the
emulator waits the host's time. A read changes nothing, and `--dump` and
the debug link bring the sound no further: they show the status as of
the program's last read or write of its words, or of the end of the
run. A start over the link resets the sound. `--no-sound` makes the
eight words ordinary memory.

`--wav FILE` writes the samples to FILE as a WAV file: 16-bit stereo
PCM, left first, at 55930 Hz, the sound's rate of 55930.4 rounded down.
Its header states the sizes once the run ends: at the halt, at the step
limit, or on SIGINT, SIGTERM, or SIGHUP, which niceemu then dies of, so
a run stopped with Ctrl-C leaves a whole file, with the samples up to
the signal. The sizes of a header end at 4 GiB, some 5.3 hours of the
sound: a longer run writes on, and its header states 4 GiB. A run with `--step-time`
gives the same file each time. To hear a program to its last note, let
it wait before its `HALT`: with `--step-time` by a write of `TIME_SKIP`,
which is ignored without it, and else by reading `TIME_LO` in a loop.
The window of `--window`
plays the samples (Window above).

`src/opm_tables.zig` holds the tables of the synthesizer. `test/opm_tables.py`
writes it:

    python3 test/opm_tables.py --zig > src/opm_tables.zig

`make opmcheck`, which `make test` runs, fails if the file is not what
it writes. The unit test of `src/opm.zig` replays the vectors of
`test/opm_vectors.py` (Tests below). `test/sound.nasm` checks the words,
the status, a skip, and the waits of a full FIFO with `--step-time`, and
`sound_mem` runs it again with `--no-sound`. `test/wav.py` plays the
example of DEVICES.md §12.5 with `--wav`, and compares every sample with
the model's, for the writes at the samples that their steps give. It
ends a run that loops with SIGINT, SIGTERM, and SIGHUP, and both files
must be whole. Then
it plays the note without `--wav` and skips 9.5 hours, which must take
no time, as no sample is computed.

The sample player of DEVICES.md §12.7, in `src/pcm.zig`, is at
`0xFFFFFF0A`–`0xFFFFFF0C`, among the sound's words, with its FIFO of
4096 samples. It counts the time as the synthesizer does, and a write
to its full FIFO while it plays waits for its next sample in the same
way. Without
`--pcm-wav` and a window, nobody hears its samples, so the time takes
them from the FIFO all at once. `--pcm-wav FILE` writes them as
`--wav` does, at the rate of the first sample, an underrun's 0s
included. The header has one rate: if a later sample comes at another
rate, niceemu says so at the end. `test/pcm.nasm` checks the words, the
status, the rate, an underrun, and a full FIFO, stopped and playing,
with `--step-time`, and `pcm_mem` runs it again with `--no-sound`.
`test/wav.py` checks every sample of `--pcm-wav`, the underrun's
included, and the warning of a change of rate.

### SD card

The controller has 2 slots, with or without images. A command ends in the
write that starts it, so busy never reads 1, and a Read or Write goes to
the image file at once, at byte 512 · `SD_LBA`. A card's type is 2, SDHC,
and Init always succeeds. A failure of the host to read or write the file
gives error 5. "Changed" is set at the start, and a card cannot be taken
out. `SD_LAST` is the image's size in sectors minus 1. Reset, at a start of
the debug link, keeps the buffer.

`test/sd.nasm` checks the registers, the commands and their errors, a
Write read back from the file, and the slots, on a fresh image of 2
sectors that `make test` makes for each run. The unit tests in
`src/cpu.zig` check write protection, the order of the checks, a failure
of the host, and reset.

### Network station

The emulator has no Ethernet. `NET_IP`, `NET_MAC_HI`, and `NET_MAC_LO`
are registers that keep what a program or the link writes, from their
reset values 0 and 02:4E:49:43:45:00. They are set only when niceemu
starts: a start of the debug link and a clear keep them. The emulator
serves the link where `--link` says, whatever `NET_IP` holds, and a write
closes no connection. The counts of frames read 0. `NET_STATUS` gives the
port of `--link`, and bit 31 while a host is connected. Without `--link`
it reads 0. Writes to all but the addresses are ignored.

`test/net.nasm` checks the reset values, the ignored writes, and
`NET_MAC_HI`'s 16 bits. A unit test in `src/cpu.zig` checks that a start
keeps the station.

### Ethernet frames

The emulator has no Ethernet: the frames come from `--eth-in` and
`--eth-udp`, and go to `--eth-out` and `--eth-peer`. A frame is sent in
the write of `ETH_TX_LEN`, so busy never reads 1. The lines of `--eth-in`
arrive in order, at the write of `ETH_CSR` that enables the port and at
each frame sent, a line `N:` once the program has sent N frames since
niceemu started, so a run is the same each time. A datagram arrives when
niceemu next looks, every 1024 steps, and between the chunks of steps of
`--window` and `--link`. Before the queue, the station answers an ARP
request for `NET_IP` and a ping to it, while `NET_IP` is not 0, and keeps
TCP to the port of `--link`. It drops frames to other MAC addresses
without counting them. Its counts in `0xFFFFFFB3`–`B5` stay 0. Reset, at
a start of the debug link, keeps the send buffer and the lines that have
not arrived.

`test/eth.nasm` checks the registers, the queue filled and emptied, the
window and its chunks, a frame sent, an ARP reply, and a line that waits
for a frame sent, with `test/eth.in`; the frames sent must be those of
`test/eth.frames.expected`. The unit tests in `src/eth.zig` check the
layout of a frame in the buffer, the lengths, the ping reply and its
checksums, TCP to the link's port, an IP address of 0, and the lines of
`--eth-in`. `test/udp.py` checks the socket, with a peer that sends an ARP
request and a frame that the program sends back.

### A real network

`tools/nicetap.py` joins the socket of `--eth-udp` to a TAP device on
Linux, so that a program in the emulator is a host on a real network and
can get DHCP, DNS, NTP, and TFTP from it. Each frame read from the device
goes to niceemu as one datagram, and each datagram from niceemu of 14 to
1514 bytes goes to the device. It is Python 3 with the standard library
only, and its options mirror niceemu's:

    nicetap.py --tap NAME --udp [ADDR:]PORT --peer [ADDR:]PORT

`--udp` is where it receives niceemu's frames, and `--peer` is niceemu's
`--eth-udp`, written as for niceemu, with `127.0.0.1` if no ADDR is
given. It opens the device NAME, and makes it if the process may. It
prints one line on stderr once it is ready, and runs until it is killed.
A bad option, or a device or a port it cannot open, is an error, with the
exit status 1, or 2 for a missing option.

The device needs root or `CAP_NET_ADMIN`. Without them, make one
beforehand that you may open, and bring it up:

    sudo ip tuntap add mode tap user $USER name nice0
    sudo ip link set nice0 up
    emulator/tools/nicetap.py --tap nice0 --udp 5556 --peer 5555 &
    emulator/zig-out/bin/niceemu --eth-udp 5555 --eth-peer 5556 program.bin

The host then joins `nice0` to the network as for QEMU: it puts it in a
bridge with its Ethernet port, or gives it an address and routes and NATs
it. A bridge to a wired port lets the network's DHCP server answer the
program. A Wi-Fi port cannot be bridged, so route there, and run a DHCP
server such as dnsmasq on `nice0`. niceemu itself needs no root and has
no code for one operating system.

`test/tap.py` checks the errors of nicetap's options. Then, in a user and
network namespace of `unshare -rn`, which needs no root, it runs nicetap
on a device of its own, niceemu with `ECHO` of `test/udp.py`, and a host
on the device with a packet socket, which sees the program's hello, gets
an ARP reply from the station, and sends a frame that the program sends
back. A host that refuses the namespace, or has no `/dev/net/tun` or
`ip`, skips that part with a message.

### Instruction fetches and the memory

Instruction fetches from `0xFFFFFF00`–`0xFFFFFFFF` read 0, as ISA.md §8.3
requires, whatever the memory there holds. So a program that runs into the
I/O range runs through it as NOPs. `test/iofetch.nasm` shows this.

All 2³² words of memory exist, and addresses wrap from `0xFFFFFFFF` to 0
(ISA.md §1.1). Memory is allocated in pages of 4096 words when a nonzero
word is first written to them, so a program only costs the memory it
touches. There is no bound: a program that writes one word to each of many
pages can use up to 16 GiB before the emulator runs out of memory.

## Debug link

With `--link PORT`, niceemu serves the debug link of
[DEBUG.md](../doc/DEBUG.md) on a TCP port of `127.0.0.1`, as DEBUG.md §7
says. With `--link 0.0.0.0:PORT`, a host on another computer can connect.
The link has no authentication, so anyone who can reach the port can read
and write the memory and run programs. On a network you do not trust,
keep the default and forward the port over SSH instead:

    ssh -L 4510:127.0.0.1:4510 emuhost 'niceemu --link 4510 prog.bin'

The host tool is [`debugger/nicedbg.py`](../debugger/README.md), an
interactive debugger on the link. It loads a program, runs, pauses,
steps, and goes on, sets the breakpoints and the watchpoints, reads and
writes the registers and the memory, and disassembles with `nicedis.py`, with labels from
`niceasm.py --symbols`. It connects to niceemu with `--tcp PORT`:

    niceemu --link 4510 &
    debugger/nicedbg.py --tcp 4510 --symbols prog.sym prog.bin

niceemu starts held, with the program file in memory if one was given,
and runs a program each time the host starts one. The console's input and output go over the
link, and what a run prints after it halts, and the trace, go to stderr.
stdout stays empty. It runs until a signal, and then exits with status 0.
With `--window`, closing the window ends it too (see Window above).

It serves the link every 4096 steps while a program runs, and at least
every 100 ms while the processor is held, halted, or paused, or a console
read waits. With `--window`, it serves the link and the window after each
65536 steps, or each millisecond of steps at the pace of `--speed`, and
at each step of a wait loop (see Window above), and about every 10 ms
while the processor is held, halted, or paused.
A console byte that finds the input buffer full waits up to 50 ms
for room, measured at these services, and niceemu reads nothing more
from the connection meanwhile, so that TCP holds the host back
(DEBUG.md §1).
A pause takes effect between two steps. A pause while a
console read waits undoes the step of the read, and pauses before it
(DEBUG.md §7). The bytes that the step took go back to the input buffer. A step of a paused processor (bit 5, DEBUG.md §6) runs one
step of `--max-steps` and `--trace`, an instruction, or the rest of a
skip of `TIME_SKIP` and the instruction after it (Skipping time), and
then pauses again. A step at a console read that would wait does not
run, and pauses again at once.
It has four breakpoints (DEBUG.md §6). Before each step, it stops at a
breakpoint at R15, unless the step is a wait step of a skip or the first
after a go on or a step. A stop does not count as a step, so
`--max-steps` counts as without breakpoints. A write to their registers
takes effect before the next step, and a host's connection clears them.
It has four watchpoints too. It checks each data access of a step against
them, and after a step that hit one, it stops before anything else,
unless the step halted or reached `--max-steps`. A step that a pause
undoes, at a console read, hit nothing. A write to their registers takes
effect at the next step, and a host's connection clears them.
While the processor is paused, a write of R1 to R15 sets the register as
a register-direct write of an instruction does (ISA.md §4.3). A write of
R0 to R15 while it is not paused gets `e04` (DEBUG.md §6). The reserved
registers `0xFFFFFFD0`–`0xFFFFFFD3` and `0xFFFFFFD7`, and bits 6 to 10 of
the control register, read 0 and take no write.
A `W` writes its words when its checksum has been checked, so a `W`
with a bad checksum writes nothing. One with a bad payload writes the whole
words before the bad byte, at most N.

## Skipping time

With `--step-time`, a write of N to `TIME_SKIP`, `0xFFFFFF5F`, skips N
wait steps after the step of the write (DEVICES.md §3). Each is a step:
the cycle counter counts it, and so do the microsecond counter and the
clock, but the instruction counter and the event counters do not, and
`-n` counts it as a step. niceemu counts the wait steps at once, up to
the step limit, with the same result as one by one, so a skip takes no
host time. `--trace` prints no line for a wait step. A write of 0 skips
nothing, and `-n` cuts a skip short. Without `--step-time` the write is
ignored, as on an FPGA core. Under the link, a single step runs the rest
of a skip with the next step (DEBUG.md §6). The probe `test/skip.nasm`
shows these rules, and `make test` runs it three more times: `skip_off`
without `--step-time`, `skip_limit` with a step limit that cuts its first
skip short, and `skip_mem` with `--no-cycle-counter`.

## Trace format

With `--trace`, each instruction prints one line: its address, its instruction
word, and then what it changed. These are the last lines for `count.bin`:

    00000005 02a08100 R2=00000001
    00000006 b003d800 R15=00000004
    00000004 00604082 R1=00800800
    00000005 02a08100 R2=00000000 R14=09000000
    00000006 b003d800 skipped
    00000008 0c000000 HALT

- `Rn=value` for each register that changed. R15 is listed only when it is not
  the address after the instruction's constant words, that is, after a jump.
- `[addr]=value` for a memory write.
- `skipped` when the condition was false.
- The reason for a halt, at the end of the halting instruction's line: `HALT`,
  or `reserved control instruction`, the text of the `Halted (...)` line.
The format is meant for comparing the FPGA core with the emulator line by
line.

## Tests

`make test` first checks with `zig fmt --check` that the Zig sources are
laid out as `zig fmt` lays them out, with `make seqcheck` that
`src/fpu_seq.zig` is what `test/fpu_seq.py` writes (Floating-point unit
above), and with `make opmcheck` the same of `src/opm_tables.zig` and
`test/opm_tables.py` (Sound above). It then writes the FPU's vectors
with `test/fpu_vectors.py` and the sound's with `test/opm_vectors.py`,
runs the unit tests in `src/cpu.zig` and the
other sources, which replay the vectors, for this machine's CPU and again
for the baseline x86_64 CPU of the release files (Download), which has
no FMA instruction. Zig keeps the result of a run of the unit tests, and
runs them again only when an input changed, so `build.zig` names the
file of the vectors as an input; `make test` then adds a wrong line to
the file, and the unit test must fail. Then come the example programs
in `../assembler/test/` (the three 2004 programs and `wrap`) and the
probes: the programs `test/*.nasm`, each of which exercises one feature
and has a hand-checked `test/X.expected`. The output and exit status of
each run must be those of its `.expected` file.
The probes are
assembled with niceasm, and `make bins` reassembles them after a change.
Then `test/link.py` runs niceemu with `--link 0` and checks the debug link
over TCP (Debug link above). It checks the packets of DEBUG.md §8 byte for
byte, the errors and drops, a program loaded, run, halted, and restarted,
the overflow notice, floods of console bytes: to a program that reads,
with none lost, to one that never reads, with one `o` and a request
behind them answered after 50 ms, and to a paused one, the step limit, halt reason 2 for reserved control
words, and a clear of a running program. It checks that the microsecond counter counts the
time while the processor runs, stops while it is paused or held, starts
from 0 at a start, and counts the steps with `--step-time`. It checks the single step: its example of DEBUG.md
§8, the cases where bit 5 does nothing, a step into `HALT` and to the step
limit, and a step at a console read. And it checks the breakpoints:
their example of DEBUG.md §8, the stop register, a step and a start that
end at one, two at one address, a skipped instruction and a `HALT` at one,
and what keeps and clears them. It
checks the watchpoints: their example of DEBUG.md §8, a write, a read,
two reads in one step, a skipped read, two at one address, a stop before a breakpoint, a step and
the step limit, what keeps and clears them, and their registers. It
checks the writes of R0 to R15: their example of DEBUG.md §8, R0, R14,
a step and a go on from a written R15, also at a breakpoint, and `e04`
while halted, held, and running. And it checks the network station's
`NET_STATUS`, with the port and a host connected, and that a start, a
clear, and a new connection keep `NET_IP`. And it checks a skip of
`TIME_SKIP`: a single step through it, and a breakpoint at R15 that
fires only at its end. And it checks that a host that knows only the
minimum of major 1 works: one that checks the major, knows bits 0 to 3
of the control register, writes 0 to its other bits, and gets no notice
but `h` (DEBUG.md §9). And it checks that the reserved registers
`0xFFFFFFD0`–`0xFFFFFFD3` and `0xFFFFFFD7`, and bits 6 to 10 of the
control register, read 0 and take no write, and that the range answers
while the program runs. And it checks the screen's mode word over
the link, and that `--no-screen-mode` holds after a clear.
Then `test/wav.py` checks the files of `--wav` and `--pcm-wav` (Sound
above), and `test/udp.py` checks the frames over the socket of `--eth-udp`
(Ethernet frames above), and `test/tap.py` the same through
`tools/nicetap.py` and a TAP device (A real network above).
Then `test/errors.py` checks the error messages and exit statuses of the
command line and the loader, and the exit status and some output lines of
runs that stop in each way: `HALT`, a reserved control word, and the
step limit, `-n 0` included, and that `--irq`, `--nmi`, and
`--no-timer-irq` are unknown options. It checks the name
of each trap code with a symbol file, input files with CR LF lines, the
screen's mode word with and without `--no-screen-mode`, and the pixels
with `-2004`. Last come the tests of the two models,
`test/fpu_model_test.py` and `test/opm_model_test.py`, below.

`test/fpu_model.py` is a reference model of the floating-point unit of
DEVICES.md §11. It computes every result exactly, with Python's
fractions, and rounds it itself, so it shares nothing with the host's
doubles, which the emulator uses. It runs a function as the steps of
`test/fpu_seq.py`, which the emulator's table repeats. Its widths
are parameters. `make test` runs `test/fpu_model_test.py`, which checks
the model four ways: a table of hand-checked accesses, each with its
reason; the model at binary64 against the host's doubles, on special
and random operands; every pair of values of a format of 8 bits against
a rounding by brute force, and the S forms, which round once, on every
pair of such values against a format of 6 bits; and in exact
arithmetic, the constants against `decimal`, `ISQRT` against
`math.isqrt`, `SCALE10`, correctly rounded for k up to 22 and within its
bound beyond, `DIGITS` against Python's `%e` digit for digit, constants
of 15 digits through `FROMBCD`, `SCALE10`, and `DIGITS 15`, which must
come back, and the functions within the bounds of DEVICES.md §11.3,
against series in `decimal` to 90 digits. Each function is checked on
400 random operands, some of them from where its error is the largest,
and `ATAN2` and `HYPOT` on the operands of their worst errors that are
known.

`test/fpu_vectors.py` writes the FPU's test vectors from the model, one
line for each access: the state before it, the access, and the state
after it, with the value a read returns. The state is the flags and the
whole stack, so each line stands alone. Its docstring gives the format.
Some 35800 lines are directed, by group: the registers, every command
number and the words that are not valid, every command at the depths
0, 1, 2, 15, and 16, the special values each with each, for `XMUL`,
`CHOP`, and the functions as for the other commands, the rounding, the
S forms where rounding once and rounding twice differ, the conversions,
the decimal commands, the operands of the functions that run the steps
of their sequences which the other groups leave out, and the
hand-checked accesses of `fpu_model_test.py`, so that the emulator and
the cores replay those too. A random sequence from a seed
adds 20000 more, in which the depth and the faults take part. The
coverage counts bins: the class of each operand of each command, the
rounding case, exact, down, up, or a tie, the class of the result, the
flags each command sets, and for each S form the results that the
command and then `ROUND32` would not give. Each step of the sequence of
each function is a bin too, and a `JZ` is two, one for each way it goes:
these count the directed lines only, so that every step runs whatever
the seed is, and the emulator and the cores are checked on it.
`make test` runs it, and it fails if a bin that can occur is empty, if
a command sets a flag that its row of `FLAGS` does not allow, if a step
of `DEAD_STEPS` runs, the 11 steps that no operand reaches, or if a
line does not parse back and replay on the model. With `-o FILE` it
writes the vectors. `make test` writes them to `test/fpu.vectors.out`,
and the unit test of `src/fpu.zig` replays them on the emulator's unit
(Floating-point unit above); `tb_fpu` in `hdl/` replays them on the FPU
of the cores. `make fpu-long` writes and replays a random sequence of a
million accesses, from `SEED`, 1 by default.

`test/opm_model.py` is a reference model of the sound of DEVICES.md
§12, the FM synthesizer whose registers are the YM2151's. It defines
the samples that a log of writes gives, and follows ymfm step by step.
`test/opm_tables.py` holds its tables: the sine and the exponential
computed from their formulas, each value checked to round the same on
every host, and the pitch, the detune, and the envelope's increments as
ymfm has them, under ymfm's notice. `make test` runs
`test/opm_model_test.py`, which checks the model against the formulas
of DEVICES.md §12.4 for the pitch, the rates, the levels, and the LFO's
period, its rules of writes, and its DAC on hand-checked
values. The other formulas rest on `make ymfmcheck`. `test/opm_vectors.py` writes random logs of writes from a seed,
and with the model's samples, the vectors. `make test` writes 20000
samples of them to `test/opm.vectors.out`, and the unit test of
`src/opm.zig` replays them. `make test` then changes one sample in the
file, and the unit test must fail. `make ymfmcheck` clones ymfm
at `YMFM_COMMIT` into `build/ymfm`, or takes a checkout in `YMFM`,
builds `test/opm_ymfm.cpp` against it, and compares every sample of
`SEEDS` random logs, 20 by default, of 30000 samples each, through
`test/opm_ymfm.py`. `tb_opm` in `hdl/` replays the vectors on the
sound of the cores' system, `hdl/src/opm.vhd`.

`test/cputest.nasm` is a self-checking test of the whole instruction set:
every opcode, shift, addressing mode, and condition, the flags, F0, F1,
and the U bits of R14, R0, R14, and R15, skipped instructions, and
skipped reserved control words. It halts at the first check that fails,
with the check's number in R12 and R11 = 0. If every check passes, it
halts with R11 = `0x600D`. It needs no emulator options or I/O, so the
FPGA core can run it too.

Some probes check corners that cputest leaves out: `r0dest` and
`r15modes` the remaining addressing modes of R0 and R15, `r14mem` R14 as
an address, `skipconst` the constant words of skipped and control
instructions, `carryin` and `shiftc` the carry input and the shift counts
at their edges, `wrapmem` the wrap of addresses at `0xFFFFFFFF`, and
`smcown` an instruction that overwrites its own constant word. `short`
runs the one-word `JMP`, `JMPR`, and `CALL` of ISA.md §5.3, skipped and
taken, forward and back, and `shortfar` the two ends of their reach.
`bytewin` reads and writes through the byte windows of DEVICES.md §9.
`scrbound` runs twice, with `-s` and with `-2004 -s`, to check the bounds
of the screen.

`test/reserved.nasm` runs a reserved control word, which halts the
processor with exit status 2.
