# niceemu

An emulator for the NICE processor, written in Zig. It implements
[doc/ISA.md](../doc/ISA.md) and runs the `.bin` files that
[niceasm](../assembler/README.md) writes.

It needs Zig 0.15 (tested with 0.15.2), and Python 3 for `make test`.

## Build and test

    make          # unit tests, example and probe programs, test/errors.py
    make build    # just build zig-out/bin/niceemu

`make test` runs the unit tests in `src/cpu.zig`, then the example programs
in `../assembler/test/` (the three 2004 programs and `wrap`) and the probe
programs `test/*.asm`, comparing the output and exit status of each with
`test/X.expected`.
Finally `test/errors.py` checks the error messages and exit statuses of the
command line and the loader. The probes are assembled with niceasm, and
`make bins` reassembles them after a change.

`test/cputest.asm` is a self-checking test of the whole instruction set:
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
| `-s`, `--screen` | After halting, print the 80×25 character screen at `0x400`. |
| `-d`, `--dump ADDR:N` | After halting, print N memory words from ADDR. May be repeated. |
| `-n`, `--max-steps N` | Stop after N steps. The default is 100000000. |
| `--irq STEP:VEC` | Raise IRQ with vector VEC just before step STEP. May be repeated. |
| `--nmi STEP:VEC` | Raise NMI with vector VEC just before step STEP. May be repeated. |
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

## Devices

The 2004 emulator has one device, a character screen mapped into memory at
`0x400`: 80 columns by 25 rows, one word per character, with the character
in bits 7..0 and its colour above. Here the screen is ordinary memory, and
`--screen` prints the characters when the program has halted. `print.asm`
writes to it. The screen is kept for the 2004 programs. It overlaps the code
of any program longer than 1024 words.

niceemu adds a console at `0xFFFFFF00`, the first I/O address. A write
there prints bits 7..0 of the word on stdout at once, and ignores the rest.
The console stores nothing, so a read from it returns 0. Its output comes
before the `Halted` line, and with `--trace` it is mixed in with the trace
lines. `test/console.asm` writes to it. The FPGA core will have a UART at
the same address.

All 2³² words of memory exist, and addresses wrap from `0xFFFFFFFF` to 0
(ISA.md §1.1). Memory is allocated in pages of 4096 words when a nonzero
word is first written to them, so a program only costs the memory it
touches. The other I/O addresses, `0xFFFFFF01`–`0xFFFFFFFF`, are ordinary
memory.

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
raised. The probes `test/irq.asm`, `test/merge.asm`, `test/after.asm`, and
`test/start.asm` show these rules.

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
