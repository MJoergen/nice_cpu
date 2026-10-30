# niceemu

An emulator for the NICE processor, written in [Zig](https://ziglang.org). It implements
[doc/ISA.md](../doc/ISA.md) and the devices of [doc/SYSTEM.md](../doc/SYSTEM.md), and runs the `.bin` files that
[niceasm](../assembler/README.md) writes.

It needs Zig 0.17 (tested with 0.17.0), and Python 3 for `make test`.
The window of `--window` needs a build with `-Dwindow`, below.

## Build and test

    make          # unit tests, example and probe programs, test/errors.py
    make build    # just build zig-out/bin/niceemu
    make window   # build it with the window of --window
    make window-test  # build it so, and run test/window.py

`make window` builds niceemu with `zig build -Dwindow`. The window uses
[SDL 3](https://libsdl.org), which the build fetches from
[castholm/SDL](https://github.com/castholm/SDL), pinned by its hash in
`build.zig.zon`, and compiles from source, with no system packages. The
first build takes a few minutes of CPU time; later ones take SDL from the Zig
cache. Zig unpacks the source into `zig-pkg/`, which `make clean`
removes. Without `-Dwindow`, the build fetches nothing and needs only Zig.
`make test` and `make build` build without the window.
`make window-test` runs `test/window.py` on that build, with SDL's dummy
video driver, so it needs no display (see Window below).

`make test` runs the unit tests in `src/cpu.zig`, then the example programs
in `../assembler/test/` (the three 2004 programs and `wrap`) and the probe
programs `test/*.nasm`, comparing the output and exit status of each with
`test/X.expected`.
Finally `test/errors.py` checks the error messages and exit statuses of the
command line and the loader, and the exit status and some output lines of
runs that stop in each way: `HALT`, the other halts, and the step limit,
`-n 0` included. The probes are assembled with niceasm, and
`make bins` reassembles them after a change.
Then `test/link.py` runs niceemu with `--link 0` and checks the debug link
over TCP (see Debug link below): the packets of DEBUG.md §8 byte for byte,
the errors and drops, a program loaded, run, halted, and restarted, the
overflow notice, the step limit, the halt reasons 2 to 4, a clear of a running
program, the single step: its example of DEBUG.md §8,
the cases where bit 5 does nothing, a step into `HALT` and to the step limit,
a step at a console read, and R13–R15 after each step across interrupt entries,
compared with `--trace`, and the breakpoints: their example of DEBUG.md §8,
the stop register, a step and a start that end at one, two at one address,
a skipped instruction and a `HALT` at one, what keeps and clears them, and
an interrupt entry that goes first.

`test/reserved.nasm` runs a reserved control word, which halts the
processor with exit status 2.

Some probes check corners that cputest leaves out: `r0dest` and
`r15modes` the remaining addressing modes of R0 and R15, `r14mem` R14 as
an address, `skipconst` the constant words of skipped and control
instructions, `carryin` and `shiftc` the carry input and the shift counts
at their edges, `wrapmem` the wrap of addresses at `0xFFFFFFFF`, and
`smcown` an instruction that overwrites its own constant word.
`scrbound` runs twice, with `-s` and with `-2004 -s`, to check the bounds
of the screen.

`test/cputest.nasm` is a self-checking test of the whole instruction set:
every opcode, shift, addressing mode, and condition, the flags, R0, R14, and
R15, skipped instructions, `INT`, and `RTI`. It halts at the first check
that fails, with the check's number in R12 and R11 = 0. If every check
passes, it halts with R11 = `0x600D`. It needs no emulator options or I/O, so
the FPGA core can run it too. No IRQ may be raised while it runs, because
some checks set E with no vector table in place.

## Usage

    niceemu [options] program.bin
    niceemu --link [ADDR:]PORT [options] [program.bin]

The program is loaded, the processor is reset (PC = 0) and it runs until it
halts. Then the emulator prints why it stopped, the number of steps, and the
registers. A step is one instruction, or the entry into an interrupt, so an
NMI followed by `RTI` and `HALT` is 3 steps. The PC printed after a halt is
the address after the halting instruction. If the step limit stops the
program first, the first line is `Stopped at the step limit after N steps,
PC=...` instead. If an interrupt request is still pending at the end, a
line such as `Pending: IRQ 05` follows the first line.

    $ zig-out/bin/niceemu ../assembler/test/count.bin
    Halted (HALT) after 12292 steps, PC=00000009
    R0  00000000 R1  00800800 R2  00000000 R3  00000000
    ...

| Option | Effect |
|---|---|
| `-t`, `--trace` | Print one line per instruction (see below). |
| `-s`, `--screen` | After halting, print the 80×25 character screen. |
| `--color` | Like `--screen`, with the colors of each word as 24-bit ANSI escapes (see below). |
| `--invert-fg` | Like `--color`, with the foreground inverted, as in the 2004 IDE. |
| `-2004` | Put the screen at `0x400`, as the 2004 emulator does. |
| `-d`, `--dump ADDR:N` | After halting, print N memory words from ADDR. May be repeated. |
| `-n`, `--max-steps N` | Stop after N steps. There is no limit by default, so a program that never halts runs until it is killed. |
| `-i`, `--input FILE` | Read the console's input from FILE instead of stdin; `-` is stdin. A directory is an error. |
| `--symbols FILE` | Read the labels of `niceasm.py --symbols` from FILE. After a halt other than `HALT`, or at the step limit, print `At label+0x1f`, the location of the halt. After a halt at the default wasm trap handler, `___wasm_trap`, also print `Trap CODE (cause) at label+0x1f`, from R1 and R2 ([WASM.md](../translator/WASM.md)). Each line of the file is an 8-digit hex address, a space, and a label; `.EQU` names are not in it, only the labels of instructions and data. Each label is the nearest one at or before the address, the first in the file if several are at one address, so a second label at the same address is never named. |
| `--irq STEP:VEC` | Raise IRQ with vector VEC just before step STEP. May be repeated. |
| `--nmi STEP:VEC` | Raise NMI with vector VEC just before step STEP. May be repeated. |
| `--no-cycle-counter` | Make the cycle counter and the microsecond counter, `0xFFFFFF40`, `0xFFFFFF41`, `0xFFFFFF44`, and `0xFFFFFF45`, ordinary memory (see Memory map). |
| `--no-timer-irq` | The timer counts, but raises no requests, so that `--irq` can raise them instead (see Memory map). |
| `--window` | Show the screen in a window while the program runs, and keep it after the halt until it is closed (see Window below). Needs a build with `-Dwindow`. |
| `--speed N` | With `--window`, run N steps a second, 1000000 by default, or as fast as the host can for 0. |
| `--link [ADDR:]PORT` | Serve the debug link on PORT of ADDR, `127.0.0.1` if no ADDR is given, instead of running the program once (see Debug link below). ADDR is an IPv4 address, or an IPv6 one in brackets, such as `[::1]`. With PORT 0, pick a free port and print `link: port N` on stderr. The program file is optional. `--input` is an error with it. |
| `-h`, `--help` | Print the usage on stdout. |

Numbers in options are decimal, or hex after `0x` or `0X`, with no sign or
`_`.

`--dump` prints eight words per line. Each line starts with the address of
its first word and a colon, and each word is 8 hex digits after a blank. `--screen` prints `Screen:` and then one line per row,
starting with `|`, with trailing blanks dropped from each row and blank rows
dropped from the bottom. Characters outside printable ASCII show as blanks.
Both come after the registers, the dumps first.

With `--color`, each row also has the colors of its words (SYSTEM.md §1). The
background is bits 31..20 and the foreground bits 19..8, as 4-bit red, green,
and blue. The row has one escape, `ESC[48;2;R;G;B;38;2;R;G;Bm`, at its start
and wherever the colors change, and `ESC[0m` at its end. The foreground is
not inverted, as it is in the 2004 IDE, unless `--invert-fg` asks for it. Then
each foreground component `n` becomes `0xF − n`, and the background stays.

The exit status is 0 after `HALT`, 2 after any other halt (a reserved control
word, a nested `INT`, or `RTI` outside an interrupt routine), 3 at the step
limit, 4 when the window of `--window` was closed before either, and 1 for a usage, file, or memory error, an out-of-memory
condition, or an output that cannot be written. Diagnostics go to stderr,
and only `-h` prints on stdout. `--` is not an option, so a program path
that starts with `-` cannot be given, and an empty argument counts as no
program. If stdout is a pipe that
closes early, as in `niceemu -t x.bin | head`, niceemu stops quietly with
status 141, as a filter killed by SIGPIPE would.

## Window

With `--window`, niceemu shows the 80×25 screen in a window of 1280×800
pixels while the program runs, as SYSTEM.md §1 specifies. A resized window
scales the screen and keeps its aspect. The characters are from the font
Spleen 16×32, as on NiceMonMEGA65, in `src/font.zig`, which
`font/gen_font.py` generates (`font/LICENSE.spleen` has its license). The
window draws a cursor from `0xFFFFFF80`–`0xFFFFFF82`, and redraws about 60
times a second. `-2004` and `--invert-fg` work with it as with `--screen`.

The console writes to stdout, as without the window. It reads the file of
`--input`, if given, and then the keys typed into the window, with the
bytes of SYSTEM.md §1, and not stdin. A read with no byte waiting returns
0, and a read never returns `0x200`. The keys wait in a buffer of 2048
bytes, and a key whose bytes do not all fit is dropped.

The emulator runs one step per microsecond, so that the microsecond counter
keeps the time of the host's clock. The cycle counter and the timer still
count one cycle per step, so a timer period of P lasts P microseconds,
where on a board of 100 MHz it lasts P/100 (SYSTEM.md §1). `--speed` sets another
rate, and `--speed 0` runs as fast as the host can. A run that falls more
than 100 ms behind the rate starts the pace again from there, rather than
catch up in a burst.

At the halt, or at the step limit, niceemu prints the report as without
the window, and the window stays, with the last screen, until it is
closed. Then niceemu exits with the status of the halt. Closing the window
before ends the run: the first line of the report is `Stopped when the
window was closed after N steps, PC=...`, and the exit status is 4. SIGINT,
SIGTERM, and SIGHUP end niceemu as without the window, also while the
window stays after the halt. Ctrl-C in the window is a key, `0x03`.

With `--link`, the window opens when niceemu starts and stays open over
every run, and shows the screen also while the processor is held, halted,
or paused. The console reads the link's input buffer, into which the keys
go too, as SYSTEM.md §1 says, and a read does not wait. So a pause or a
step at a console read is never undone (DEBUG.md §7). The runs are paced
as without the link. Closing the window ends niceemu with status 0, as a
signal does.

`test/window.py` runs niceemu with SDL's dummy video driver
(`SDL_VIDEODRIVER=dummy`), which needs no display, but can type no key and
close no window. It checks the report at the halt with `--color`, the
reads of `--input` and then 0, that stdin is not read, the pace of the
default speed and of `--speed 0`, and that a signal ends a run with no
report. With `--link`, as a host, it checks that a read returns 0 until a
byte comes, the pace, and the end of the input. The key table and the
drawing of the screen are unit tests in `src/keys.zig` and `src/frame.zig`,
and the keys' way into the link's buffer one in `src/link.zig`.

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
| `0x00000000`–`0xFFFEFFFF` | 4294901760 | Ordinary memory. Programs load at 0, or at `0x8000` under a monitor in ROM, as a stand-in for one at 0 shows (runtime/ABI.md, "Programs under a monitor"). |
| `0xFFFF0000`–`0xFFFF07CF` | 2000 | Character screen, 80×25. Ordinary memory. With `-2004` it is at `0x00000400`–`0x00000BCF` instead. |
| `0xFFFF07D0`–`0xFFFFFEFF` | 63280 | Ordinary memory. The runtime's stack starts at `0xFFFFFF00` and grows down. |
| `0xFFFFFF00` | 1 | Console. A write prints bits 7..0 on stdout. A read returns the next input byte plus `0x100`, or `0x200` after the end of the input. |
| `0xFFFFFF01` | 1 | Read counter. A data read returns the number of data reads of it since the last write, and a write sets that number. |
| `0xFFFFFF02`–`0xFFFFFF0F` | 14 | Reserved for I/O (ISA.md §8.3). Ordinary memory for data accesses. Instruction fetches read 0. |
| `0xFFFFFF10`–`0xFFFFFF1F` | 16 | Timer (SYSTEM.md §4). Raises IRQ once every P steps. |
| `0xFFFFFF20`–`0xFFFFFF3F` | 32 | Math unit (SYSTEM.md §2). Multiplies and divides A and B, and divides C and D. |
| `0xFFFFFF40`–`0xFFFFFF7F` | 64 | Performance counters (SYSTEM.md §3). Cycles, instructions, and microseconds, 64 bits each. The fetch statistics of the FPGA core, at `0xFFFFFF50`–`0xFFFFFF7F`, read 0. |
| `0xFFFFFF80`–`0xFFFFFFFF` | 128 | Reserved for I/O, like `0xFFFFFF02`–`0xFFFFFF0F`. `--window` draws its cursor from `0xFFFFFF80`–`0xFFFFFF82` (SYSTEM.md §1). |

The screen has one word per character, with the character in bits 7..0 and
its colors above. It is ordinary memory, and `--screen` prints the
characters when the program has halted. `test/screen.nasm` writes to it. The
2004 emulator has the screen at `0x400`, where it overlaps the code of any
program longer than 1024 words. `-2004` puts it there for the 2004
programs, such as `print.nasm`.

The console stores nothing. Its output comes before the `Halted` line, and
with `--trace` it is mixed in with the trace lines. `test/console.nasm`
writes to it. This repository has no UART. A system built on the FPGA core maps one at the same address (SYSTEM.md §1).

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

The read counter makes the data reads of ISA.md §8.2 visible: how many
there are, and in which order. It stores nothing else, and `--dump` shows
its count without counting. `test/reads.nasm` uses it.

The math unit holds only its operands, A, B, C, and D. It computes each
result when it is read, so a read never waits, and `--dump` shows the
results for the current operands. Its words store nothing else.
`test/mpu.nasm` and `test/mpu64.nasm` check every result, with division by
zero and the signed overflow.

The performance counters count the instructions, the steps, and the
microseconds since reset. The emulator has no clock, so its cycle counter
counts one cycle per step, that is, per instruction and per interrupt entry,
and its microsecond counter counts one microsecond per step. They differ
from the FPGA core's, which counts clock cycles and real microseconds. A read of a low word takes a snapshot of
its counter, and a read of the high word returns the snapshot's high word.
`--dump` shows the low words and the snapshots without taking a snapshot.
Writes are ignored. `test/perf.nasm` checks the instruction counter, and
`test/time.nasm` the microsecond counter.
The emulator has none of the FPGA core's fetch statistics, at
`0xFFFFFF50`–`0xFFFFFF7F`: their words read 0 and ignore writes.

`--no-cycle-counter` makes the words of the cycle counter and the
microsecond counter, `0xFFFFFF40`, `0xFFFFFF41`, `0xFFFFFF44`, and
`0xFFFFFF45`, ordinary memory, like the rest of the I/O range. A program that reads them then
runs the same on the emulator and on an FPGA core whose cycle count
cannot be predicted, so their traces can be compared. The random programs
of the HDL tests run this way ([hdl/README.md](../hdl/README.md)). The
instruction counter stays.

The timer counts steps as well, so its requests come every P steps. A
request raised by the last step of a run is not listed as pending at the
end, as on the FPGA core, where it only reaches the core after that step.
The timer's requests are IRQs, like those of `--irq`. A request merges
with one that is pending, and the pending one keeps its vector. So when `--irq` and the timer raise a request before the same step, the vector
of `--irq` is kept: it is pending before the step begins, and the timer's
request merges with it (`test/irqtimer.nasm`). `test/timer.nasm` checks the counting, the stop, the
merging, and that a request keeps the vector it was raised with when
the vector is written while it is pending.

With `--no-timer-irq`, the timer counts, reloads, and answers reads as
before, but raises no requests. A test of an FPGA core that may take a
timer request later than the emulator does (doc/MICROARCH.md §6) then
raises each one with `--irq` at the step where the core took it, as it
does for its own requests ([hdl/README.md](../hdl/README.md)). `make test`
runs `timer.nasm` so, with its ten requests given by `--irq`, and the
output must equal that of the plain run.

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

niceemu starts held, with the program file in memory if one was given,
and runs a program each time the host starts one. The console's input and output go over the
link, and what a run prints after it halts, and the trace, go to stderr.
stdout stays empty. It runs until a signal, and then exits with status 0.
With `--window`, closing the window ends it too (see Window above).

It serves the link every 4096 steps while a program runs, and at least
every 100 ms while the processor is held, halted, or paused, or a console
read waits. With `--window`, it serves the link and the window after each
millisecond of steps at the pace of `--speed` (65536 steps for `--speed 0`),
and about every 10 ms while the processor is held, halted, or paused. A pause takes effect between two steps. A pause while a
console read waits undoes the step of the read, and pauses before it
(DEBUG.md §7). The bytes that the step took go back to the input buffer. A step of a paused processor (bit 5, DEBUG.md §6) runs one
step of `--max-steps` and `--trace`, an instruction or an interrupt entry,
and then pauses again. A step at a console read that would wait does not
run, and pauses again at once.
It has four breakpoints (DEBUG.md §6). Before each step, after the
`--irq` and `--nmi` requests of that step are raised, it stops at a
breakpoint at R15, unless the step is an interrupt entry or the first after
a go on or a step. A stop does not count as a step, so the requests and
`--max-steps` count as without breakpoints. A write to their registers
takes effect before the next step, and a host's connection clears them.
A `W` writes its words when its checksum has been checked, so a `W`
with a bad checksum writes nothing. One with a bad payload writes the whole
words before the bad byte, at most N.

## Interrupts

The core (`src/cpu.zig`) implements IRQ, NMI, `INT`, and `RTI` (ISA.md §7).
The timer (Memory map) is the only device that raises IRQ, and no device
raises NMI. `--irq` and `--nmi` raise a request at a chosen step. A request for step N is raised after N steps have run, so
with `--trace` it comes before line N + 1, and `--nmi 0:5` raises an NMI
before the first instruction. A request is raised whether or not it can be
taken. If it cannot, it stays pending, as ISA.md §7.1 says, and a request
still pending at a halt is never taken. A request of a kind that is already
pending merges with it, so the vector given first wins, whether the two were
given for the same step or for different steps. Requests for steps that are
never reached, because the processor halts or `-n` stops it, are never
raised. The probes `test/irq.nasm`, `test/merge.nasm`, `test/after.nasm`, and
`test/start.nasm` show these rules.

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
  or the same text as the `Halted (...)` line for the other halts, such as
  `reserved control instruction`.
- An interrupt taken between instructions prints `IRQ vv` or `NMI vv` and the
  registers it changed, lined up with the instruction lines:

      NMI 06            R14=81000000 R15=00000040

The format is meant for comparing the FPGA core with the emulator line by
line.
