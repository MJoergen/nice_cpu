# niceemu

An emulator for the NICE processor, written in Zig. It implements
[doc/ISA.md](../doc/ISA.md) and runs the `.bin` files that
[niceasm](../assembler/README.md) writes.

It needs Zig 0.15 (tested with 0.15.2).

## Build and test

    make          # unit tests, then the example programs
    make build    # just build zig-out/bin/niceemu

`make test` runs the unit tests in `src/cpu.zig` and then the 2004 example
programs in `../assembler/test/`, comparing each output with
`test/X.expected`.

## Usage

    niceemu [options] program.bin

The program is loaded, the processor is reset (PC = 0) and it runs until it
halts. Then the emulator prints why it stopped, the number of steps and the
registers:

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
| `-m`, `--mem-size N` | Words of memory from address 0. The default is `0x100000`. |

The exit status is 0 after `HALT`, 2 after any other halt (a reserved control
word, a nested `INT`, or `RTI` outside an interrupt routine), 3 at the step
limit, and 1 for a usage or file error.

## Devices

The 2004 emulator has one device, a character screen mapped into memory at
`0x400`: 80 columns by 25 rows, one word per character, with the character
in bits 7..0 and its colour above. Here the screen is ordinary memory, and
`--screen` prints the characters when the program has halted. `print.asm`
writes to it.

Memory runs from address 0 up to `--mem-size`. Above that, reads return 0 and
writes are ignored (ISA.md §8.2). Nothing is mapped at the I/O addresses
`0xFFFFFF00`–`0xFFFFFFFF` yet.

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
  registers it changed.

The format is meant for comparing the FPGA core with the emulator line by
line.
