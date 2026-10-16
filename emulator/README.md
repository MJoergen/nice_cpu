# niceemu

An emulator for the NICE processor, written in [Zig](https://ziglang.org). It implements
[doc/ISA.md](../doc/ISA.md) and runs the `.bin` files that
[niceasm](../assembler/README.md) writes.

It needs Zig 0.15 (tested with 0.15.2), and Python 3 for `make test`.

## Build and test

    make          # unit tests, example and probe programs, test/errors.py
    make build    # just build zig-out/bin/niceemu

`make test` runs the unit tests in `src/cpu.zig`, then the example programs
in `../assembler/test/` (the three 2004 programs and `wrap`) and the probe
programs `test/*.nasm`, comparing the output and exit status of each with
`test/X.expected`.
Finally `test/errors.py` checks the error messages and exit statuses of the
command line and the loader. The probes are assembled with niceasm, and
`make bins` reassembles them after a change.

`test/reserved.nasm` runs a reserved control word, which halts the
processor with exit status 2.

`test/cputest.nasm` is a self-checking test of the whole instruction set:
every opcode, shift, addressing mode, and condition, the flags, R0, R14, and
R15, skipped instructions, `INT`, and `RTI`. It halts at the first check
that fails, with the check's number in R12 and R11 = 0. If every check
passes, it halts with R11 = `0x600D`. It needs no emulator options or I/O, so
the FPGA core can run it too. No IRQ may be raised while it runs, because
some checks set E with no vector table in place.

## Usage

    niceemu [options] program.bin

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
| `-2004` | Put the screen at `0x400`, as the 2004 emulator does. |
| `-d`, `--dump ADDR:N` | After halting, print N memory words from ADDR. May be repeated. |
| `-n`, `--max-steps N` | Stop after N steps. The default is 100000000. |
| `-i`, `--input FILE` | Read the console's input from FILE instead of stdin. |
| `--irq STEP:VEC` | Raise IRQ with vector VEC just before step STEP. May be repeated. |
| `--nmi STEP:VEC` | Raise NMI with vector VEC just before step STEP. May be repeated. |
| `--no-cycle-counter` | Make `0xFFFFFF10` and `0xFFFFFF11`, the cycle counter, ordinary memory (see Memory map). |
| `--no-timer-irq` | The timer counts, but raises no requests, so that `--irq` can raise them instead (see Memory map). |
| `-h`, `--help` | Print the usage on stdout. |

Numbers in options are decimal, or hex after `0x` or `0X`, with no sign or
`_`.

`--dump` prints eight words per line, each line starting with the address of
its first word. `--screen` prints `Screen:` and then one line per row,
starting with `|`, with trailing blanks dropped from each row and blank rows
dropped from the bottom. Characters outside printable ASCII show as blanks.
Both come after the registers, the dumps first.

The exit status is 0 after `HALT`, 2 after any other halt (a reserved control
word, a nested `INT`, or `RTI` outside an interrupt routine), 3 at the step
limit, and 1 for a usage, file, or memory error. If stdout is a pipe that
closes early, as in `niceemu -t x.bin | head`, niceemu stops quietly with
status 141, as a filter killed by SIGPIPE would.

## Program files

A `.bin` file has one line per word, as niceasm writes it (ISA.md §10.4):
an address and a word, both in hex, separated by blanks. niceasm writes 8
digits; the loader accepts 1 to 8, in upper or lower case, and nothing else:
no `0x` prefix, sign, or `_`. Blank lines are ignored. Loading the same
address twice and a file with no words are errors.

## Memory map

| Address | Words | Contents |
|---|---|---|
| `0x00000000`–`0xFFFEFFFF` | 4294901760 | Ordinary memory. Programs load at 0. |
| `0xFFFF0000`–`0xFFFF07CF` | 2000 | Character screen, 80×25. Ordinary memory. With `-2004` it is at `0x00000400`–`0x00000BCF` instead. |
| `0xFFFF07D0`–`0xFFFFFEFF` | 63280 | Ordinary memory. The runtime's stack starts at `0xFFFFFF00` and grows down. |
| `0xFFFFFF00` | 1 | Console. A write prints bits 7..0 on stdout. A read returns the next input byte plus `0x100`, or `0x200` after the end of the input. |
| `0xFFFFFF01` | 1 | Read counter. A data read returns the number of data reads of it since the last write, and a write sets that number. |
| `0xFFFFFF02`–`0xFFFFFF0F` | 14 | Reserved for I/O (ISA.md §8.3). Ordinary memory for data accesses. Instruction fetches read 0. |
| `0xFFFFFF10`–`0xFFFFFF1F` | 16 | Performance counters (ISA.md §8.5). Cycles and instructions, 64 bits each. |
| `0xFFFFFF20`–`0xFFFFFF3F` | 32 | Math unit (ISA.md §8.4). Multiplies and divides A and B, and divides C and D. |
| `0xFFFFFF40`–`0xFFFFFF4F` | 16 | Timer (ISA.md §8.6). Raises IRQ once every P steps. |
| `0xFFFFFF50`–`0xFFFFFFFF` | 176 | Reserved for I/O, like `0xFFFFFF02`–`0xFFFFFF0F`. |

The screen has one word per character, with the character in bits 7..0 and
its colour above. It is ordinary memory, and `--screen` prints the
characters when the program has halted. `test/screen.nasm` writes to it. The
2004 emulator has the screen at `0x400`, where it overlaps the code of any
program longer than 1024 words. `-2004` puts it there for the 2004
programs, such as `print.nasm`.

The console stores nothing. Its output comes before the `Halted` line, and
with `--trace` it is mixed in with the trace lines. `test/console.nasm`
writes to it. The FPGA core will have a UART at the same address.

Each data read of the console takes the next byte of the input, which is
stdin unless `--input` names a file. It returns the byte in bits 7..0 with
bit 8 set, so a 0 byte reads as `0x100`. Once the input has ended, every
read returns `0x200`. For no input at all, give stdin from `/dev/null`, or
`--input /dev/null`. On a terminal, a read waits until a whole line has
been typed, and Ctrl-D ends the input. Before it reads, the emulator
flushes its output, so that a prompt shows before the program waits for
the answer. `test/input.nasm` reads `test/input.txt`. Reads by `--dump`
take no input. `make test` runs every program with stdin from `/dev/null`.

The read counter makes the data reads of ISA.md §8.2 visible: how many
there are, and in which order. It stores nothing else, and `--dump` shows
its count without counting. `test/reads.nasm` uses it.

The math unit holds only its operands, A, B, C, and D. It computes each
result when it is read, so a read never waits, and `--dump` shows the
results for the current operands. Its words store nothing else.
`test/mpu.nasm` and `test/mpu64.nasm` check every result, with division by
zero and the signed overflow.

The performance counters count the instructions and the steps since reset.
The emulator has no clock, so its cycle counter counts one cycle per step,
that is, per instruction and per interrupt entry. It differs from the FPGA
core's, which counts clock cycles. A read of a low word takes a snapshot of
its counter, and a read of the high word returns the snapshot's high word.
`--dump` shows the low words and the snapshots without taking a snapshot.
Writes are ignored. `test/perf.nasm` checks the instruction counter.

`--no-cycle-counter` makes the two words of the cycle counter ordinary
memory, like the rest of the I/O range. A program that reads them then
runs the same on the emulator and on an FPGA core whose cycle count
cannot be predicted, so their traces can be compared. The random programs
of the HDL tests run this way ([hdl/README.md](../hdl/README.md)). The
instruction counter stays.

The timer counts steps as well, so its requests come every P steps. A
request raised by the last step of a run is not listed as pending at the
end, as on the FPGA core, where it only reaches the core after that step.
The timer's requests are IRQs, like those of `--irq`. A request merges
with one that is pending, and an `--irq` request replaces the vector of a
pending one. `test/timer.nasm` checks the counting, the stop, and the
merging.

With `--no-timer-irq`, the timer counts, reloads, and answers reads as
before, but raises no requests. A test of an FPGA core that may take a
timer request later than the emulator does (doc/MICROARCH.md §6) then
raises each one with `--irq` at the step where the core took it, as it
does for its own requests ([hdl/README.md](../hdl/README.md)). `make test`
runs `timer.nasm` so, with its eight requests given by `--irq`, and the
output must equal that of the plain run.

Instruction fetches from `0xFFFFFF00`–`0xFFFFFFFF` read 0, as ISA.md §8.3
requires, whatever the memory there holds. So a program that runs into the
I/O range runs through it as NOPs. `test/iofetch.nasm` shows this.

All 2³² words of memory exist, and addresses wrap from `0xFFFFFFFF` to 0
(ISA.md §1.1). Memory is allocated in pages of 4096 words when a nonzero
word is first written to them, so a program only costs the memory it
touches.

## Interrupts

The core (`src/cpu.zig`) implements IRQ, NMI, `INT`, and `RTI` (ISA.md §7).
No device raises IRQ or NMI yet. Instead, `--irq` and `--nmi` raise a request
at a chosen step. A request for step N is raised after N steps have run, so
with `--trace` it comes before line N + 1, and `--nmi 0:5` raises an NMI
before the first instruction. A request is raised whether or not it can be
taken. If it cannot, it stays pending, as ISA.md §7.1 says, and a request
still pending at a halt is never taken. A request of a kind that is already
pending replaces it, so the vector given last wins, whether the two were
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
