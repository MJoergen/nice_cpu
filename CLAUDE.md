# CLAUDE.md

NICE is a 32-bit CPU by B. Ulmann; this repo will implement it on an FPGA.
So far: the spec, an assembler, an emulator, a runtime library, and a wasm translator. See README.md.

## Layout

- `doc/ISA.md`: the specification. It is authoritative for all code here.
  `doc/review/` records how decisions were reached; ISA.md supersedes it.
- `doc/intro/`: beginner's slides (`nice_intro.tex`, built `nice_intro.pdf`)
  and their example programs. ISA.md wins over them.
- `doc/MICROARCH.md`: draft design note for the FPGA core. ISA.md wins over it.
- `assembler/niceasm.py`: Python 3, standard library only, `mypy --strict` clean.
- `emulator/src/cpu.zig` (core, unit tests) and `main.zig` (CLI, loader). Zig 0.15.
- `runtime/`: start-up code and runtime routines in NICE assembly (ISA.md §9.3).
- `translator/nicewasm.py`: wasm -> NICE assembly (ISA.md §9.4). Same rules as niceasm.py.
- `hdl/`: VHDL-2008, GHDL. A simple multi-cycle core in `src/multicycle.vhd`,
  `src/trace_pkg.vhd`, the simulation-only memory model and trace writer
  in `sim/`, and the testbenches, test programs, and random program
  generator in `test/`. No pipelined core yet. Style follows qnice_cpu's
  CODING_STYLE.md.

## Commands

    cd assembler && make test        # .asm -> .bin comparisons, then test/errors.py
    cd assembler && make typecheck   # mypy --strict
    cd emulator  && make test        # zig unit tests, example and probe programs, test/errors.py
    cd emulator  && make bins        # reassemble test/*.bin after editing a probe .asm
    cd runtime   && make test        # join, assemble, and run each test/*.asm
    cd translator && make test       # test/run.py, then test/errors.py
    cd translator && make typecheck  # mypy --strict
    cd hdl && make test              # synth check, tb_mem, then tb_trace and the core diffed against niceemu
    cd doc/intro && make test        # run the slides' example programs
    cd doc/intro && make pdf         # rebuild the slides (pdflatex, beamer)

Run the relevant `make test` after every change.

## Conventions

- Behaviour changes start in ISA.md; code follows the spec, never the reverse.
  Departures from the sources go in ISA.md Appendix B.
- Every bug fix or new rule gets a test: an `errors.py` case, a line in
  `assembler/test/encoding.asm`, or an emulator probe with a hand-checked
  `.expected` file. Never generate `.expected` or `.bin` files by copying tool
  output without checking it.
- The 2004 example `.bin` files are original `NICE.pm` output; do not change them.
- Keep the READMEs in sync with the tools' options, formats, and error behaviour.
- Docs: plain, short sentences. Use the Oxford comma by default ("a, b, and c").
- Commit subjects: `niceasm: ...`, `niceemu: ...`, `runtime: ...`, `nicewasm: ...`, `nicehdl: ...`, `intro: ...`, `ISA: ...`, `Review: ...`.
