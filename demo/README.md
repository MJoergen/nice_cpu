# demo

The demo is a program in NICE assembly that shows what the processor,
the keyboard, and the screen do: a typewriter, the bytes of each key, the
font and the colors, the performance counters, a small game, and a
self-test with the network station's addresses. It runs in
`niceemu --window`, with the keys typed into the window, and a board can
keep it in its ROM: [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
joins it behind its monitor, whose command `x` runs it, so that a board
with no computer on its debug UART shows that it works.

    make -C emulator window       # niceemu with its window
    make -C demo window           # the demo in it

## What it shows

The top two rows are blue bars that every demo has: the name and the
version, and a menu of the demos, which lists the function key of each and
shows the running one in black on white. A function key starts its demo
afresh, and one without a demo does nothing. The keys are F1, F3, F5, and
so on, which the MEGA65 has without SHIFT. F12, SHIFT and F11 on the
MEGA65, clears the screen and returns, to a board's monitor or, in
`niceemu`, to the stand-in that halts.

| Key | Demo |
|---|---|
| F1 | The typewriter, which runs when the demo starts |
| F3 | The key codes |
| F5 | The characters and the colors |
| F7 | The counters |
| F9 | The comet, a game |
| F11 | The board: a self-test, and the network station's addresses |
| F12 | Returns |

The typewriter's top ten rows are the welcome: the two bars, what the
demo is, where to go further, and a third blue bar with the keys and F12.
The 15 rows below it are a typewriter. What you type on the keyboard, or
send to the console, appears at the blinking cursor:

| Key | What it does |
|---|---|
| A character | Shown at the cursor, which moves on, to the next row after the last column |
| RETURN | The next row. A CR, an LF, and a CR LF are each one new row. |
| DEL, backspace | Deletes the character before the cursor, in its row |
| TAB | The next column that is a multiple of 8 |
| Cursor keys | Move the cursor within the typewriter's rows |
| CTRL-L | Clears the typewriter's rows |

Past the last row, the typewriter's rows scroll up by one, and the welcome
stays. Other control codes and other escape sequences do nothing, and so do
the bytes `0x80` to `0x9F`. The bytes from `0xA0` on are the characters of
ISO 8859-1.

The key codes show the bytes that each key sends, as
[DEVICES.md §1.5](../doc/DEVICES.md#15-keyboard) lists them, which helps when
writing programs that read the keyboard. Each key gets a row, with its
bytes in hex from column 2, and from column 42 as characters, a control
code as `^` and a character: `^[` is ESC, `^C` is CTRL-C, and `^?` is
DEL. The bytes `0x80` to `0x9F` have no character, and a key shows at
most 12 bytes. A sequence from the line shows as one key, and so
does an ESC with the bytes that come within 10 ms after it. So the ESC
key shows alone, and in a test of `niceemu`, where the next byte of the
input file is always there, an ESC shows with the key after it. A function
key with a demo starts that demo, so its bytes show only for a moment, or
not at all. Past the last row, the rows scroll up by one.

The characters and the colors check the font and the video output at a
glance. On the left are the 256 characters of the font, ISO 8859-1, in 16
rows of 16. A row's label is the code of its first character, and the
digits above the columns add to it. On the right are ramps of seven
colors, red, green, blue, yellow, cyan, magenta, and gray, each with the
16 intensities `0` to `F` of 4-bit color: first as backgrounds, and then as
foregrounds, the digits of the intensities on black. Intensity 0 is black,
so its cell shows nothing. The keys do nothing here, except the function
keys.

The counters show the performance counters
([DEVICES.md §3](../doc/DEVICES.md#3-performance-counters)). The top part
has those since reset: the time as `h:mm:ss.hh`, the microseconds, the
cycles, and the instructions, all 64 bits in decimal, and the clock in
MHz, the cycles divided by the microseconds: 100 on the MEGA65. The bottom
part has a sieve of Eratosthenes on the numbers below 2048, which runs
again before each update of the screen: the runs, the primes it finds,
which are 309, and the instructions, cycles, and microseconds of the last
run, with the cycles per instruction and the instructions per
microsecond. On the MEGA65, the sieve's 30058 instructions take about
79000 cycles, 2.6 per instruction, and about 38 instructions a
microsecond. That is usual for the pipelined core on code written by hand
([bench/README.md](../bench/README.md)): each turn of its loops ends with a
taken jump, which costs cycles, the count reads the sieve from memory, and
each prime's square is read from the math unit. In `niceemu`, each step is
a cycle, and the microseconds are the host's time, so the clock is the
emulator's rate of steps ([DEVICES.md §1.6](../doc/DEVICES.md#16-pacing)).
With `--step-time`, as in the test, each step is also a microsecond, so
the clock is 1 MHz, and the sieve has one cycle per instruction. The keys
do nothing here, except the function keys.

The comet is a small game. The cursor keys steer the comet, `@`, through
a field in a blue frame, and its green tail follows it. Each star, `*`,
scores a point, makes the tail longer by 4, and makes the comet faster, from
a step every 150 ms to one every 50 ms. A new star then comes at a random
free cell. The game ends when the comet hits the frame or its tail, and
then any key starts a new one. The comet waits for the first cursor key,
and a key that would turn it back is ignored. The best score stays until
another demo starts. The game keeps time by the microsecond counter, so
it keeps its pace in the window. It takes one key at each step, so in the
test, where a microsecond is a step, each key of the input file is one
step.

The board runs a self-test of four tests each time that F11 starts it,
and shows PASS or FAIL for each:

| Test | What it checks |
|---|---|
| RAM | The 12288 words from `0x0000B000` to `0x0000DFFF`, above the demo's variables and below a monitor's stack, RAM on every board: each is written with its address, and then with its address inverted, and read back |
| Math unit | Signed and unsigned products and quotients of 32 bits, a division by zero, the most negative number divided by −1, and quotients of 64 bits, against known results |
| Timer | 10 interrupts, one every 1000 cycles, which must come within 9500 to 10500 cycles of the start |
| Performance counters | The instructions of a known sequence, and over a loop, at least as many cycles as instructions, some microseconds, and 1 to 255 cycles per microsecond |

A failure shows two words in hex: the address that failed and the word
read there, or for the timer, the interrupts that came and the cycles
that they took. The last line says whether all tests passed.

Below the self-test is the network station
([DEVICES.md §6](../doc/DEVICES.md#6-network-station)), shown again and
again while the demo runs: its IP address in decimal with dots, its MAC
address in hex with colons, its counts of the good frames received, the
bad or dropped ones, and the frames sent, and the TCP port of the debug
link, with whether a host is connected to it. After reset the IP address
is `0.0.0.0`, which answers nothing, and the MAC address is
`02:4E:49:43:45:00`. So a board with the demo in its ROM can get its
address from its own keyboard, or from a terminal on the debug UART, and
then answers pings and serves the debug link. These keys change the
addresses:

| Key | What it does |
|---|---|
| I | Starts typing a new IP address, such as `192.168.1.65` |
| M | Starts typing a new MAC address, such as `02:4E:49:43:45:01` |
| Digits and dots, or hex digits and colons | Typed at the cursor in row 22. Other characters are dropped, and so are those past the 15 or 17 of a full address. |
| DEL, backspace | Deletes the last character |
| RETURN | Writes the address to the station, if it is one, and ends the typing. Otherwise a red message in row 24 says what is wrong, and the typing goes on. |
| ESC, CTRL-C, RUN/STOP | Cancels the typing |

An IP address is four numbers from 0 to 255 with dots between them. A MAC
address is six bytes of one or two hex digits with colons between them,
and the first byte must be even, because an odd one is a group address,
which no station has. A function key still starts its demo, which also
cancels the typing. On a board, writing an address while a host is
connected on the TCP port, or while a reply goes out, breaks that
connection or reply. In `niceemu` the station keeps the addresses
written, and its counts stay 0; the port is that of `--link`, and 0
without it.

## How it works

Every demo reads the keys through `POLL`. It turns the escape sequences of
the cursor keys and the function keys into codes of their own: those of
xterm, which the window and the MEGA65's keyboard send, and also
`ESC O A` to `ESC O D` and the VT220's `ESC [ 11 ~` to `ESC [ 14 ~`. It
waits for each byte of a sequence after its ESC, at most `T_ESC`, 10 ms,
as a keyboard or a terminal sends a sequence at once. An ESC with no byte
after it in time is the key ESC, `0x1B`. An ESC and a byte that starts no
sequence give that byte. On a function key with a demo, `POLL` jumps to
the demo, which starts with an empty stack. A new demo is a routine that
sets SP, calls `FRAME` for the two bars, and polls the keys; its address
goes in the tables `FKEYS` and `MENU`. A demo that wants the bytes
themselves puts a routine in `ECHO`, R12, which `POLL` calls with each
byte, as the key codes do. `FRAME` sets `ECHO` to 0.

The demo is a program under a monitor
([ABI.md](../runtime/ABI.md), "Programs under a monitor"). It is
assembled at `0x8000`, with its own entry there, which keeps the SP that
the monitor called it with in `D_SP`. Each demo starts with SP at
`D_SP`, and F12 returns from there with the status 0 in R1, after it has
cleared the screen and put the cursor at the top left. A monitor that
keeps a cursor of its own sets it again. The monitor then clears E, stops
the timer, and sets VBASE to 0, as ABI.md says. In `niceemu`, the
runtime's stand-in for a monitor, `runtime/test/monitor_console.nasm`,
sits at 0: it sets SP to `0xFFFFFF00`, calls the demo, and halts when it
returns.

The demo keeps most of its state in registers, and its variables at
`VARS`, `0xA000`, past its image: the counters keep the sieve at
`0xA000`–`0xA7FF` and their numbers from `0xA800`, and the comet keeps the
addresses of its cells and its state at the same addresses, as only one
demo runs at a time. The comet tells what is in a cell from the screen
itself. F11 tests the RAM from `0xB000` to `0xDFFF`. These are RAM words
on every board, below a monitor's stack and variables: on NiceMonMEGA65
those start at `0xFFFFF000`, and the RAM repeats through the address
space, so `0xFFFFEFFF` is RAM word `0xEFFF` with 64K words and `0x1EFFF`
with 128K ([DEVICES.md §8](../doc/DEVICES.md#8-systems-built-on-the-fpga-core)).
The assembler checks that the image stays below `VARS`, as the variables
and the tested RAM are `.RES` blocks. The demo writes only these words,
the screen, the cursor's registers, the math unit, the timer, the
station's addresses, and its stack.

The self-test's timer interrupt goes through vector `0x41` and a vector
table at `0x8000`, VBASE `0x80`, the first page of the image. Its only
entry, the word at `0x8041`, holds the address of the routine, which
counts the interrupts in RAM. The self-test sets VBASE, and leaves the
timer stopped and E clear when it is done, so no other demo has
interrupts.

The demo scrolls by copying the rows, not with the display offset, so
that the welcome stays, and so that it runs the same in `niceemu`, where
the screen's registers are memory.

The demo halts at the end of the input: in `niceemu` without the window,
after its input file, and on a board, after a break on the line, as when
an Ethernet host half-closes its connection. That is on purpose: no key
could come, and the tools and the tests end on the halt. In the window, a
read never returns the end ([DEVICES.md §1.5](../doc/DEVICES.md#15-keyboard)),
so the demo runs until F12 or until the window is closed.

## Building and testing

    make -C demo                  # build/demo.bin and build/emu.bin
    make -C demo window           # build/emu.bin in niceemu --window
    make -C demo test             # runs in niceemu, compared with test.expected

The version in the title bar is `git describe --tags --always --dirty`, or
`VERSION=` on the command line, which a board's release sets to its tag.
The assembler has no include, so the Makefile joins `demo.nasm`, the text
of `TEXT`, and a line that defines `VERSION` into `build/demo.bin`, from
`0x8000`. `TEXT` is `text.nasm` by default: the name in the title bar,
the welcome, the keys of the third bar, and a note under the counters. A
board gives a file of its own with `TEXT=`, with the same labels, and so
changes the text without touching `demo.nasm`. `build/emu.bin` is the
stand-in, assembled at 0, with `build/demo.bin` after it, as a monitor's
image and a program's concatenate.

The test assembles the demo with the version `V9.9` and `text.nasm` into
`build/demo_test.bin`, puts it behind the stand-in in
`build/emu_test.bin`, and runs that in `niceemu` with `--step-time`, so
that its counters are the same in every run. The Makefile writes its
inputs, `build/test1.txt` to `build/test16.txt`, with `printf`: the first
edits a few lines, the second clears them and scrolls, the third has the
function keys, the fourth shows key codes and scrolls them, the fifth goes
from the key codes back to the typewriter, the sixth shows the characters
and the colors, the seventh the counters, with two runs of the sieve, the
eighth plays two games of the comet, the ninth runs the board twice, the
tenth types an IP address that is rejected, the eleventh writes an IP
address and a MAC address and cancels a second one, the twelfth and the
thirteenth type MAC addresses that are rejected, the fourteenth runs the
board in `build/emu_fail.bin`, with a copy of the test's demo with a wrong
word in the math unit's test, which shows how a failure looks, the
fifteenth types with a backspace and the other cursor keys, `ESC O A` to
`ESC O D`, and the sixteenth leaves with F12, which leaves a blank screen
and R1 = 0 at the stand-in's halt. `niceemu` shows no colors, so for the
sixth the test also has the words of two rows of ramps, for the ninth
those of the menu, with F11 in black on white, and of PASS in green, and
for the fourteenth those of FAIL in red. The screens that `niceemu`
prints, those words, and R1 of the sixteenth are in `test.expected`,
which was checked by hand.

After `make -C demo test`, the first input shows the first screen of
`test.expected`:

    emulator/zig-out/bin/niceemu --screen --step-time -i demo/build/test1.txt demo/build/emu_test.bin
