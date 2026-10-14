# nice_cpu

[![CI](https://github.com/MJoergen/nice_cpu/actions/workflows/ci.yml/badge.svg)](https://github.com/MJoergen/nice_cpu/actions/workflows/ci.yml)

An implementation of the NICE processor on an FPGA.

NICE ("NICE Is Charmingly Elegant") is a 32-bit processor designed by
B. Ulmann and described in two articles (1997, 1999) and a 2004 web page with
a Perl emulator. It has sixteen 32-bit registers, word-addressed memory, a
single instruction word format with conditional execution on every
instruction, and memory-to-memory operands with pre-decrement, post-increment,
and indexed addressing.

The sources disagree in places and leave gaps, so the first step was to write
a complete specification. The FPGA implementation will follow it. So far the
repository holds the specification, an assembler, an emulator, and the
start of a runtime library.

## Contents

| Path | What it is |
|---|---|
| [doc/ISA.md](doc/ISA.md) | The instruction set: the specification for everything else here. |
| [doc/REFERENCES.md](doc/REFERENCES.md) | The NICE and QNICE sources the specification is based on. |
| [doc/review/](doc/review/) | Notes on how each ISA decision was reached, and the reviews of the tools. ISA.md supersedes them. |
| [assembler/](assembler/README.md) | `niceasm`, the assembler: one Python 3 script with no dependencies. |
| [emulator/](emulator/README.md) | `niceemu`, the emulator, written in Zig. |
| [runtime/](runtime/README.md) | The start-up code and runtime library for C and wasm programs. |

## Quick start

You need Python 3 and Zig 0.15 ([download](https://ziglang.org/download/),
or see [installing Zig](https://ziglang.org/learn/getting-started/)).

**Use Zig 0.15 exactly (tested with 0.15.2).** It is the only supported
version. Zig changes its language and standard library between releases, so
the emulator is unlikely to build with a newer or older version. On the
download page, pick 0.15.2 rather than the latest release or master.

    cd assembler && make test         # test the assembler
    cd emulator && make test          # build and test the emulator
    cd runtime && make test           # test the start-up code and runtime library

To assemble and run a program:

    assembler/niceasm.py -o count.bin assembler/test/count.asm
    emulator/zig-out/bin/niceemu count.bin

The emulator's `--trace` option prints one line per instruction, in a format
meant for comparing the FPGA core with the emulator.

## The specification

[doc/ISA.md](doc/ISA.md) covers the programmer's model, the instruction
format, conditional execution, addressing modes, execution, flags,
interrupts, reset, memory, I/O, software conventions, the C ABI, the
WebAssembly mapping, the assembler syntax, and the `.bin` object format. Where the sources disagree, it follows this
order:

1. The intended behaviour of the 2004 emulator `NICE.pm` and web page (not
   its bugs).
2. The 1999 and 1997 articles.
3. QNICE, the 16-bit descendant of NICE, as implemented in
   [MJoergen/qnice_cpu](https://github.com/MJoergen/qnice_cpu), for anything
   the NICE sources leave open, such as interrupts.

Appendix B of ISA.md lists every place where the specification departs from
a source.

## Tests

The first test vectors are the three example programs from 2004 (`count`,
`replicate`, and `print`). The assembler reproduces their original `.bin`
files byte for byte, and the emulator's results for them were checked by
hand. Both tools also have probe programs for single rules of the ISA and a
script that checks every error message. `emulator/test/cputest.asm` checks
the whole instruction set by itself, and is meant for the FPGA core as well.
