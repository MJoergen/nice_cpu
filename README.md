# nice_cpu

[![CI](https://github.com/MJoergen/nice_cpu/actions/workflows/ci.yml/badge.svg)](https://github.com/MJoergen/nice_cpu/actions/workflows/ci.yml)
[![MEGA65 100 MHz](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/MJoergen/NiceMonMEGA65/main/badge-mega65.json)](https://github.com/MJoergen/NiceMonMEGA65#the-timing-badge)

An implementation of the NICE processor on an FPGA.

NICE ("NICE Is Charmingly Elegant") is a 32-bit processor designed by
B. Ulmann and described in [two articles (1997, 1999) and a 2004 web
page](doc/REFERENCES.md) with
a Perl emulator. It has sixteen 32-bit registers, word-addressed memory, a
single instruction word format with conditional execution on every
instruction, and memory-to-memory operands with pre-decrement, post-increment,
and indexed addressing.

The repository
holds the [specification](doc/ISA.md), an [assembler](assembler),
an [emulator](emulator), a [runtime library](runtime)
with integer and floating-point routines, and a [WebAssembly
translator](translator)
that runs C, Zig, and Rust programs. The [hdl](hdl) directory holds two
different FPGA implementations, the pipelined one of MICROARCH.md, which
is the default, and a simple multi-cycle one. They both pass every comparison with the
emulator, the test setup for them, and formal checks of their ports, of
five stages of the pipeline, of the devices, and of the shifter and the
ALU for every input.

The core is FPGA-agnostic. This repository has no board top level and no
synthesis for a particular board. An example design for the MEGA65 lives in
the separate [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65) repository.

That design is an example, not a dependency: nothing here refers to it in
code or in a gate, and a release does not wait for it. It shows that the
pipelined core meets 100 MHz on the MEGA65, and this repository avoids
changes that would take that away. The MEGA65 badge at the top shows the
result of the last tag that NiceMonMEGA65 built, not of `main` here: after
a new tag it shows the one before until NiceMonMEGA65 follows.
`make -C hdl timing` here checks the core alone against a budget, and
[release/RELEASE.md](release/RELEASE.md) (step 7) says how NiceMonMEGA65
follows a tag.

## The emulator

`niceemu` runs NICE programs on the host. It implements the whole
instruction set of [doc/ISA.md](doc/ISA.md), the interrupts included,
and the devices of [doc/SYSTEM.md](doc/SYSTEM.md): the console, the
80×25 character screen, the math unit, the performance counters, and
the timer. It is the reference that the FPGA cores are compared with.
It can:

- run a program until it halts, and print why it stopped, the number of
  steps, and the registers, with memory dumps and the screen if asked;
- print a trace of one line per instruction, in the format that the
  tests of the cores compare;
- show the screen in a window while the program runs, with the keys
  typed into it going to the console, at a set speed or as fast as the
  host can (a build with `-Dwindow`);
- raise IRQ and NMI requests at chosen steps, and stop at a step limit;
- name the label where a program halted or trapped, from the symbols
  file of the assembler;
- serve the debug link of [doc/DEBUG.md](doc/DEBUG.md) over TCP, so that
  a host can load, start, pause, and single-step programs, set
  breakpoints, and read and write the memory, as it does with a board.

[emulator/README.md](emulator/README.md) describes its options, memory
map, debug link, and trace format.

### Building the emulator

You need Python 3.10 or later and GNU make 4 or later, with coreutils, as on Linux. Zig 0.17 is needed only to build the emulator
([download](https://ziglang.org/download/), or see
[installing Zig](https://ziglang.org/learn/getting-started/)).

**Use Zig 0.17 exactly (tested with 0.17.0).** It is the only supported
version. Zig changes its language and standard library between releases, so
the emulator is unlikely to build with a newer or older version. On the
download page, pick 0.17.0 rather than the latest release or master.

To build the emulator, run this in the top directory:

    make -C emulator build

This writes `emulator/zig-out/bin/niceemu`.
[CONTRIBUTING.md](CONTRIBUTING.md) says how to run the tests.

### Worked example

[doc/intro/examples/hello.nasm](doc/intro/examples/hello.nasm) prints a
string on the console with a subroutine:

    SP              .EQU    R13
    PC              .EQU    R15
    CONSOLE         .EQU    0xFFFFFF00

                    MOVE    SP, 0x1000      ; set up the stack
                    MOVE    R1, TEXT        ; the argument: the string's address
                    ADD     @--SP, 2, PC    ; push the return address ...
                    MOVE    PC, PUTS        ; ... and jump: a subroutine call
                    MOVE    @CONSOLE, 10    ; a newline
                    HALT

    ; PUTS prints the string at R1. The string ends with a 0 word.
    PUTS            MOVE[M] R2, @R1++       ; next character, and set Z if it is 0
            ?Z      MOVE    PC, @SP++       ; at the end: return
                    MOVE    @CONSOLE, R2    ; print the character
                    MOVE    PC, PUTS        ; and loop

    TEXT            .ASCII_L 'Hello, NICE!'

Assemble it into `hello.bin`, and run it:

    $ assembler/niceasm.py -o hello.bin doc/intro/examples/hello.nasm
    $ emulator/zig-out/bin/niceemu hello.bin
    Hello, NICE!
    Halted (HALT) after 56 steps, PC=0000000c
    R0  00000000 R1  0000001f R2  00000000 R3  00000000
    R4  00000000 R5  00000000 R6  00000000 R7  00000000
    R8  00000000 R9  00000000 R10 00000000 R11 00000000
    R12 00000000 R13 00001000 R14 09000000 R15 0000000c

The first line is the program's output on the console. Then the
emulator says why the program stopped, after how many steps, and shows
the registers. The exit status is 0 after `HALT`.

`--trace` shows what each instruction did, and `-n` stops the program
after a number of steps. These are the first five, up to the first
character that `PUTS` reads:

    $ emulator/zig-out/bin/niceemu --trace -n 5 hello.bin
    00000000 00035800 R13=00001000
    00000002 00005800 R1=00000012
    00000004 0077580f R13=00000fff [00000fff]=00000008
    00000006 0003d800 R15=0000000c
    0000000c 0200b080 R1=00000013 R2=00000048
    Stopped at the step limit after 5 steps, PC=0000000d
    ...

Each line has the address and the word of an instruction, and then what
it changed: registers, and memory in brackets. The third line pushes the
return address, 8, onto the stack, and the fourth jumps to `PUTS`. The
exit status is 3 at the step limit.

`--dump` shows memory after the halt, here the string at `TEXT`, one
character in each word and a 0 word at the end:

    $ emulator/zig-out/bin/niceemu --dump 0x12:16 hello.bin
    ...
    00000012: 00000048 00000065 0000006c 0000006c 0000006f 0000002c 00000020 0000004e
    0000001a: 00000049 00000043 00000045 00000021 00000000 00000000 00000000 00000000

`niceemu --help` lists the other options, and
[emulator/README.md](emulator/README.md) describes them.

## Toolchain

The host tools are `niceasm`, the assembler, `nicedis`, the
disassembler, `niceemu`, the emulator, `nicewasm`, the wasm translator,
and `nicebuild`, which builds a C, Zig, or Rust file into a `.bin` file
in one step:

    translator/nicebuild.py -o prog.bin prog.c

There is no linker: a program is assembly files joined with `cat` and
assembled at once. No compiler targets NICE directly, so compiled code
reaches NICE through WebAssembly. [doc/TOOLCHAIN.md](doc/TOOLCHAIN.md)
gives the build steps, how the tools use each other, and the compilers
and host tools they need.

## The specification

[doc/ISA.md](doc/ISA.md) covers the programmer's model, the instruction
format, conditional execution, addressing modes, execution, flags,
interrupts, reset, memory, the I/O range, software conventions, the assembler syntax, and the `.bin` object format. Where the sources disagree, it follows this
order:

1. The intended behavior of the 2004 emulator `NICE.pm` and web page (not
   its bugs).
2. The 1999 and 1997 articles.
3. QNICE, the 16-bit descendant of NICE, as implemented in
   [MJoergen/qnice_cpu](https://github.com/MJoergen/qnice_cpu), for anything
   the NICE sources leave open, such as interrupts.

Appendix B of ISA.md lists every place where the specification departs from
a source.

## Contents

| Path | What it is |
|---|---|
| [doc/](doc/README.md) | The specification, [ISA.md](doc/ISA.md), and the other documents: the I/O devices ([SYSTEM.md](doc/SYSTEM.md)), the design note for the pipelined core, the sources, the history, the reviews, and a beginner's introduction in slides. |
| [assembler/](assembler/README.md) | `niceasm`, the assembler, and `nicedis`, the disassembler: Python 3 scripts with no dependencies. |
| [emulator/](emulator/README.md) | `niceemu`, the emulator, written in Zig. |
| [runtime/](runtime/README.md) | The start-up code and runtime library for C and wasm programs, and a small C library. [ABI.md](runtime/ABI.md) gives the C ABI: registers, calls, the stack, and the runtime library's conventions. |
| [translator/](translator/README.md) | `nicewasm`, which translates WebAssembly into NICE assembly. [WASM.md](translator/WASM.md) says how WebAssembly maps to NICE. |
| [bench/](bench/README.md) | A benchmark of translated code: six kernels with known results, timed with the performance counters, and the same benchmark written by hand. |
| [hdl/](hdl/README.md) | The FPGA implementation in VHDL: a multi-cycle core and a pipelined core, the memory model and trace writer they are tested with, and the formal checks. |
| [release/](release/README.md) | `release.py`, which scripts the mechanical parts of [RELEASE.md](release/RELEASE.md). |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to run the tests, what they cover, and the rules a change follows. |
| [TODO.md](TODO.md) | Where the open items are: the [issues](https://github.com/MJoergen/nice_cpu/issues), and [doc/review/decisions.md](doc/review/decisions.md) for what was decided against. |
| [RELEASE_NOTES.md](RELEASE_NOTES.md) | The changes in each release, newest first. |

## License

The code and the documents are under the [MIT license](LICENSE), `mchess.c`
included. Dhrystone 2.1 in `bench/dhrystone/` is not covered by it; it is
R. P. Weicker's, and its files state no terms (bench/README.md, Dhrystone). The three
2004 example programs (`count`, `replicate`, and `print`), their sources and
their `.bin` files in `assembler/test/`, are by B. Ulmann and T. Kratz and
are not covered by it; see
[doc/REFERENCES.md](doc/REFERENCES.md).
