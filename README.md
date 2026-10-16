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
a complete specification. The FPGA implementation follows it. So far the
repository holds the specification, an assembler, an emulator, a runtime
library with integer and floating-point routines, and a WebAssembly
translator that runs C, Zig, and Rust programs. The `hdl/` directory holds
a simple multi-cycle core, which passes every comparison with the emulator,
and the test setup for it. The pipelined core is not written yet.

The core is FPGA-agnostic. This repository has no board top level and no
synthesis for a particular board. The example design for the MEGA65 lives in
the separate [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65) repository.

## Contents

| Path | What it is |
|---|---|
| [doc/ISA.md](doc/ISA.md) | The instruction set: the specification for everything else here. |
| [doc/intro/](doc/intro/nice_intro.pdf) | A beginner's introduction to NICE: slides, with example programs that assemble and run. |
| [doc/MICROARCH.md](doc/MICROARCH.md) | A draft design note for the FPGA core. |
| [doc/REFERENCES.md](doc/REFERENCES.md) | The NICE and QNICE sources the specification is based on. |
| [doc/review/](doc/review/) | Notes on how each ISA decision was reached, and the reviews of the tools. ISA.md supersedes them. |
| [assembler/](assembler/README.md) | `niceasm`, the assembler: one Python 3 script with no dependencies. |
| [emulator/](emulator/README.md) | `niceemu`, the emulator, written in Zig. |
| [runtime/](runtime/README.md) | The start-up code and runtime library for C and wasm programs, and a small C library. |
| [translator/](translator/README.md) | `nicewasm`, which translates WebAssembly into NICE assembly. |
| [bench/](bench/README.md) | A benchmark of translated code: six kernels with known results, timed with the performance counters, and the same benchmark written by hand. |
| [hdl/](hdl/README.md) | The FPGA implementation in VHDL. So far a simple multi-cycle core, and the memory model and trace writer it is tested with. |
| [TODO.md](TODO.md) | The single list of open items, undecided questions, and ideas for later. |

## Quick start

You need Python 3 and Zig 0.15 ([download](https://ziglang.org/download/),
or see [installing Zig](https://ziglang.org/learn/getting-started/)).

**Use Zig 0.15 exactly (tested with 0.15.2).** It is the only supported
version. Zig changes its language and standard library between releases, so
the emulator is unlikely to build with a newer or older version. On the
download page, pick 0.15.2 rather than the latest release or master.

    make                              # list the top-level targets
    make test                         # all of the tests below, in order

    cd assembler && make test         # test the assembler
    cd emulator && make test          # build and test the emulator
    cd runtime && make test           # test the start-up code and runtime library
    cd translator && make test        # test the wasm translator
    cd bench && make test             # run the benchmark on the emulator and check its results
    cd hdl && make test               # test the multi-cycle core (needs GHDL)
    cd doc/intro && make test         # run the example programs of the introduction

To assemble and run a program:

    assembler/niceasm.py -o count.bin assembler/test/count.nasm
    emulator/zig-out/bin/niceemu count.bin

The emulator's `--trace` option prints one line per instruction, in a format
meant for comparing the FPGA core with the emulator.

## Toolchain

There are four tools. Three run on the host, and one is NICE assembly that
is joined into every program. Each follows one part of
[doc/ISA.md](doc/ISA.md).

| Tool | Where | Written in | Reads | Writes | Follows |
|---|---|---|---|---|---|
| `niceasm`, the assembler | [assembler/niceasm.py](assembler/niceasm.py) | Python 3, standard library only | `.nasm` | `.bin` | ISA.md §10 |
| `niceemu`, the emulator | [emulator/](emulator/) | Zig 0.15 | `.bin` | Console output, the registers, memory dumps, and a trace | ISA.md §1–8 |
| The runtime library | [runtime/](runtime/) | NICE assembly | | | ISA.md §9.3 and §9.4 |
| `nicewasm`, the wasm translator | [translator/nicewasm.py](translator/nicewasm.py) | Python 3, standard library only | `.wasm` | `.nasm` | ISA.md §9.4 |

A program is built in these steps. There is no linker. The pieces are
assembly files, joined with `cat` in the order ISA.md §9.3 gives, and the
whole program is assembled at once.

    prog.c, prog.zig, or prog.rs
        |  clang, zig, or rustc, with a wasm32 target
        v
    prog.wasm
        |  translator/nicewasm.py
        v
    prog.nasm
        |
        |  cat, in this order: runtime/start_wasm.nasm (or start.nasm for a
        |  program with no wasm module, or their _mon versions for a program
        |  that a monitor runs), hand-written .nasm files, prog.nasm,
        |  runtime/lib.nasm, runtime/muldiv_mpu.nasm (or muldiv_soft.nasm
        |  without the math unit), and runtime/float.nasm if prog uses floats
        v
    full.nasm
        |  assembler/niceasm.py
        v
    full.bin
        |  emulator/zig-out/bin/niceemu, or later the FPGA core
        v
    console output, the registers, and an exit status

A hand-written program that does not use the runtime library needs only
the last two steps, as in the quick start above. The
[translator README](translator/README.md) gives the exact clang, Zig, and Rust
command lines for the first step, and the [runtime README](runtime/README.md)
the join.

**How the tools use each other.**

- `niceemu` runs the `.bin` files that `niceasm` writes. Its probe programs
  are assembled with `niceasm` (`make bins`), and its tests also run the
  assembler's example programs.
- The runtime library's start-up code calls `_main`, and `start_wasm.nasm`
  first calls the `___wasm_start` that `nicewasm` emits. Translated code
  uses the math unit through the labels in `muldiv_mpu.nasm` for `i32.mul`
  and the divisions, or calls `__mul`, `__div`, and the like with
  `--no-mpu`, and traps through `___wasm_trap_vector`. A C compiler for
  NICE would call the same routines.
- The float routines are themselves translated by `nicewasm`: `runtime/
  float.zig` and parts of Zig's compiler_rt are compiled to
  `runtime/float.wasm`, and `nicewasm --library float` turns that into
  `runtime/float.nasm` (`make -C runtime float.nasm`).
- The tests of the runtime use `niceasm` and `niceemu`. The tests of
  `nicewasm` use all three other tools: they translate each module, join it
  with the runtime, assemble it, and run it.
- The `.bin` format is the text format of the 2004 `NICE.pm` assembler, so
  its example binaries can be compared directly.
- The FPGA core will take the place of `niceemu` at the end of the
  pipeline. `emulator/test/cputest.nasm` and the `--trace` format are there
  to compare the two.

**Compilers.** No compiler targets NICE directly yet. ISA.md §9.3 defines
the C ABI for one, with a one-word `char` and `CHAR_BIT` = 32. Until there
is one, compiled code reaches NICE through WebAssembly: clang (with
`wasm-ld`), Zig, and Rust all have a wasm32 target, and `nicewasm`
translates the module. That gives C code the 8-bit bytes of wasm linear
memory, which Rust and Zig need anyway. GCC has no wasm32 target and no
NICE target, so it is not used. All three are tested. C programs can use
the small C library in [runtime/libc/](runtime/README.md#c-library):
`printf`, the `string.h` functions, `malloc`, and a few more. It is
compiled to wasm with the program, so it is not one of the joined files.

**Host tools.** Python 3 runs `niceasm`, `nicewasm`, and the test scripts.
Nothing beyond the standard library is needed, and `make typecheck` checks
the Python with `mypy --strict` if mypy is installed. Zig 0.15 builds
`niceemu` and compiles the Zig test modules. clang with the wasm32 target
and `wasm-ld`, and rustc with the `wasm32-unknown-unknown` target, are
needed only for `make wasm` in `translator/`, which rebuilds the compiled
test modules. Their `.wasm` files are checked in, so `make test` needs no
C or Rust compiler. The same holds for the C library's tests in
`runtime/libc/`, which `make -C runtime/libc wasm` rebuilds. The tests use
`make`, `cat`, `cmp`, `diff`, `sed`, `grep`, and `cut`. GitHub Actions runs every `make test` and `make typecheck` on each
push.

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
script that checks every error message. `emulator/test/cputest.nasm` checks
the whole instruction set by itself, and is meant for the FPGA core as well.
