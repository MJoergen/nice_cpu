# niceemu

An emulator for the NICE processor, written in Zig. It implements
[doc/ISA.md](../doc/ISA.md) and runs the `.bin` files that
[niceasm](../assembler/README.md) writes.

It needs Zig 0.15 (tested with 0.15.2), and Python 3 for `make test`.

## Build and test

    make          # unit tests, example and probe programs, test/errors.py
    make build    # just build zig-out/bin/niceemu

`make test` runs the unit tests in `src/cpu.zig`, then the 2004 example
programs in `../assembler/test/` and the probe programs `test/*.asm`,
comparing the output and exit status of each with `test/X.expected`.
Finally `test/errors.py` checks the error messages and exit statuses of the
command line and the loader. The probes are assembled with niceasm, and
`make bins` reassembles them after a change.

## Usage

    niceemu [options] program.bin

The program is loaded, the processor is reset (PC = 0) and it runs until it
halts. Then the emulator prints why it stopped, the number of steps and the
registers. A step is one instruction, or the entry into an interrupt, so an
NMI followed by `RTI` and `HALT` is 3 steps. The PC printed after a halt is
the address after the halting instruction.

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
| `-h`, `--help` | Print the usage on stdout. |

The exit status is 0 after `HALT`, 2 after any other halt (a reserved control
word, a nested `INT`, or `RTI` outside an interrupt routine), 3 at the step
limit, and 1 for a usage, file or memory error. If stdout is a pipe that
closes early, as in `niceemu -t x.bin | head`, niceemu stops quietly with
status 141, as a filter killed by SIGPIPE would.

## Program files

A `.bin` file has one line per word, as niceasm writes it (ISA.md §10.4):
an address and a word, both in hex, separated by blanks. niceasm writes 8
digits; the loader accepts 1 to 8, in upper or lower case, and nothing else:
no `0x` prefix, sign or `_`. Blank lines are ignored. Loading the same
address twice and a file with no words are errors.

## Devices

The 2004 emulator has one device, a character screen mapped into memory at
`0x400`: 80 columns by 25 rows, one word per character, with the character
in bits 7..0 and its colour above. Here the screen is ordinary memory, and
`--screen` prints the characters when the program has halted. `print.asm`
writes to it.

All 2³² words of memory exist, and addresses wrap from `0xFFFFFFFF` to 0
(ISA.md §1.1). Memory is allocated in pages of 4096 words when a nonzero
word is first written to them, so a program only costs the memory it
touches. Nothing is mapped at the I/O addresses `0xFFFFFF00`–`0xFFFFFFFF`
yet: they are ordinary memory.

The core (`src/cpu.zig`) implements IRQ, NMI, `INT` and `RTI` (ISA.md §7).
No device raises IRQ or NMI yet; the unit tests call `requestIrq` and
`requestNmi` directly.

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
- An interrupt taken between instructions prints `IRQ vv` or `NMI vv` and the
  registers it changed, lined up with the instruction lines:

      NMI 06            R14=81000000 R15=00000040

The format is meant for comparing the FPGA core with the emulator line by
line.
