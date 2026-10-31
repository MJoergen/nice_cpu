# Contributing

This file is for anyone who changes the repository: how to run the
tests, what they cover, and the rules a change follows.

## Running the tests

The tests need what the [quick start](README.md#quick-start) needs:
Python 3.10 or later, GNU make 4 or later with coreutils, and Zig 0.17
exactly. All the tests but those of the assembler and the documents run
programs on the emulator, so they build it first. The `.wasm` files the
tests translate are checked in, so the tests need no C, Zig, or Rust
compiler for wasm. The tests of the cores need GHDL.
[doc/TOOLCHAIN.md](doc/TOOLCHAIN.md) lists the other host tools and what
needs them.

    make                              # list the top-level targets
    make test                         # all of the tests below, in parallel (stops at once without GHDL)

    cd assembler && make test         # test the assembler
    cd emulator && make test          # build and test the emulator
    cd runtime && make test           # test the start-up code and runtime library
    cd translator && make test        # test the wasm translator
    cd bench && make test             # run the benchmark on the emulator and check its results
    cd hdl && make test               # test both cores (needs GHDL)
    cd doc/intro && make test         # run the example programs of the introduction
    cd doc && make test               # check the section references and links of the documents

Each directory with Python in it also has `make typecheck`, which runs
`mypy --strict`. The README of each directory lists its other targets,
such as the long simulations and the formal checks of `hdl/`. Run the
relevant `make test` after every change. GitHub Actions runs every
`make test` and `make typecheck`, the document checks, `make programs`
on both cores, `make lint`, `make formal`, and `make pdfcheck` on each
push.

## What the tests cover

The first test vectors are the three example programs from 2004
(`count`, `replicate`, and `print`). The assembler reproduces their
original `.bin` files byte for byte, and the emulator's results for them
were checked by hand. Both tools also have probe programs for single
rules of the ISA and a script that checks every error message.
`emulator/test/cputest.nasm` checks the whole instruction set by itself,
and is meant for the FPGA core as well.

## Rules

**The specification comes first.** [doc/ISA.md](doc/ISA.md) is
authoritative for all code here. A change of behavior starts in ISA.md,
and the code follows the specification, never the reverse. Departures
from the sources go in ISA.md Appendix B.

**Every bug fix or new rule gets a test:** an `errors.py` case, a line in
`assembler/test/encoding.nasm`, or an emulator probe with a hand-checked
`.expected` file. Never generate an `.expected` or `.bin` file by copying
tool output without checking it. The 2004 example `.bin` files are
original `NICE.pm` output; do not change them.

**Open items go in GitHub issues**, not in files or code comments. Label
them `bug`, `enhancement`, `documentation`, `question`, or `idea`, with
the milestone of the next release when planned.
[doc/review/decisions.md](doc/review/decisions.md) lists what was decided
against.

**The cores.** Nothing in this repository depends on
[NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65), and no
release waits for it. The pipelined core meeting 100 MHz on the MEGA65 is
a goal to keep: a change under `hdl/src/pipe_*` that touches the paths of
`timing_groups.rpt` needs `make -C hdl timing` before and after, with
both figures in the commit message. `hdl/test/timing_budget.py` holds the
budget; a miss warns and never fails. A change to the interrupt path of a
core (WRITE's interrupt entry, RTI, or the request ports) needs
`make -C hdl sweep CORE=...` on that core, which takes hours. No release
runs it. VHDL follows [hdl/CODING_STYLE.md](hdl/CODING_STYLE.md), which
`make -C hdl lint` checks.

**Python** uses the standard library only and is `mypy --strict` clean.

**NICE assembly** (`.nasm` files, listings in documents, and the output
of generators) is laid out in columns, with spaces only and no tabs: the
label in column 0, the condition in column 8, the mnemonic in column 16,
the operands in column 24, and the comment in column 40. A label of 8 or
more characters goes on a line of its own. `assembler/nicefmt.py --write`
fixes a file, and `make test` checks every `.nasm` file. Listings in
documents and strings in Python are not checked.

**Documents.** Keep the READMEs in sync with the tools' options, formats,
and error behavior. Write plain, short sentences, with the Oxford comma
("a, b, and c"). The documents say only what is true now;
[doc/HISTORY.md](doc/HISTORY.md) says what used to be true.
[RELEASE_NOTES.md](RELEASE_NOTES.md) gets a section for every new tag.
Use American spelling everywhere, in documents, comments, and identifiers
("behavior", "color", "analyze", "labeled", "gray").

**Commit messages** follow the 50/72 style: the subject, prefix included,
is at most 50 characters, a blank line follows it, and the body is
wrapped at 70 characters per line. The subject starts with the part it
changes: `niceasm:`, `niceemu:`, `runtime:`, `nicewasm:`, `nicecc:`,
`nicehdl:`, `bench:`, `release:`, `intro:`, `ISA:`, or `Review:`.
