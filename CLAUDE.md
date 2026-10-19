# CLAUDE.md

NICE is a 32-bit CPU by B. Ulmann; this repo will implement it on an FPGA.
So far: the spec, an assembler, an emulator, a runtime library, and a wasm translator. See README.md.

## Layout

- `TODO.md`: the single list of open items, undecided questions, and ideas.
  Add new ones there, not in other files or code comments.
- `doc/ISA.md`: the specification. It is authoritative for all code here.
  `doc/review/` records how decisions were reached; ISA.md supersedes it.
- `doc/intro/`: beginner's slides (`nice_intro.tex`, built `nice_intro.pdf`)
  and their example programs. ISA.md wins over them.
- `doc/MICROARCH.md`: design note for the FPGA core. ISA.md wins over it.
  Its block diagram is `doc/pipeline.tex`, and its interrupt timing diagram
  `doc/interrupt.tex`, rendered to PNGs by `make diagrams`; edit the `.tex`
  and commit both. The timing values are read off a simulation by hand.
- `assembler/niceasm.py`: Python 3, standard library only, `mypy --strict` clean.
- `emulator/src/cpu.zig` (core, unit tests) and `main.zig` (CLI, loader). Zig 0.15.
- `runtime/`: start-up code and runtime routines in NICE assembly (ISA.md §9.3).
- `translator/nicewasm.py`: wasm -> NICE assembly (ISA.md §9.4). Same rules as niceasm.py.
- `bench/bench.c`: a benchmark of translated code, six kernels with known
  results, timed with the performance counters. `hand.nasm` is the same
  benchmark written by hand, the ceiling to compare with. `expected.py`
  computes the results in Python, and `make test` checks both against them.
  `hazards.py` counts the pipeline hazards of MICROARCH.md §5 in a program,
  `pipecycles.py` estimates a program's cycles on the pipelined core,
  `cycprof.py` charges them to the source lines, and `words.py` gives the
  size in words of a translated module.
- `hdl/`: VHDL-2008, GHDL. Two cores with the same ports, but for the
  pipelined one's `stats_o`: a simple multi-cycle one in
  `src/multicycle.vhd`, the reference, and the pipelined one of
  MICROARCH.md in `src/pipeline.vhd`, which connects
  `src/pipe_fetch.vhd`, `pipe_decode.vhd`, `pipe_prepare.vhd`,
  `pipe_dbus.vhd`, and `pipe_write.vhd`, with `pipe_pkg.vhd`; its choices
  are in `hdl/ASSUMPTIONS.md`. Both use
  `src/nice_pkg.vhd` and `src/trace_pkg.vhd`. Also the math unit in
  `src/mpu.vhd`, the performance counters in `src/perf.vhd`, the timer in
  `src/timer.vhd`, the fetch statistics of the pipelined core in
  `src/fetch_stats.vhd`, the data bus decoder in `src/wb_dmux.vhd`, the
  simulation-only memory model and trace writer in `sim/`, the
  testbenches, test programs, and random program generator in `test/`,
  and the formal checks in `formal/`. Style follows `hdl/CODING_STYLE.md`,
  checked by vsg with `hdl/vsg.yml`.

## Commands

    make                             # help: the top-level targets, which run the ones below
    make test                        # every quick make test below, in order
    cd assembler && make test        # .nasm -> .bin comparisons, then test/errors.py
    cd assembler && make typecheck   # mypy --strict
    cd emulator  && make test        # zig unit tests, example and probe programs, test/errors.py
    cd emulator  && make bins        # reassemble test/*.bin after editing a probe .nasm
    cd runtime   && make test        # join, assemble, and run each test/*.nasm
    cd translator && make test       # test/run.py, then test/errors.py
    cd translator && make typecheck  # mypy --strict
    cd bench     && make test        # the benchmark on the emulator, with its results checked
    cd bench     && make core        # the benchmark on a core in GHDL, CORE=multicycle or pipeline (minutes)
    cd bench     && make hazards     # how often the pipeline hazards of MICROARCH.md §5 occur
    cd bench     && make cycles      # the estimated cycles on the pipelined core, per phase
    cd bench     && make profile     # the same, per source line, in bench/build/*.cyc.txt
    cd bench     && make compare     # the estimate beside the pipelined core's cycles, after make core CORE=pipeline
    cd bench     && make words       # the size in words of the benchmark, safe.zig, and float modules
    cd bench     && make typecheck   # mypy --strict
    cd hdl && make test              # synth check, unit tests, tb_trace, then both cores diffed against niceemu
    cd hdl && make lint              # vsg style check (pip install vsg)
    cd hdl && make formal            # SymbiYosys: the ports of both cores, the timer, and wb_dmux; proofs of FETCH, PREPARE, and DBUS
    cd hdl && make programs          # the runtime and translator programs on CORE (minutes)
    cd doc/intro && make test        # run the slides' example programs
    cd doc/intro && make pdf         # rebuild the slides (pdflatex, beamer)
    cd doc/intro && make pdfcheck    # check that nice_intro.pdf matches the .tex
    make diagrams                    # render the diagrams in doc/ to PNG (pdflatex, pdftoppm)

Vivado 2025.1 is installed but not on PATH: `/opt/Xilinx/2025.1/Vivado/bin/vivado`.
The out-of-context timing script is in `doc/review/pipeline-timing.md` (Method).

Run the relevant `make test` after every change.

## Conventions

- Behaviour changes start in ISA.md; code follows the spec, never the reverse.
  Departures from the sources go in ISA.md Appendix B.
- Every bug fix or new rule gets a test: an `errors.py` case, a line in
  `assembler/test/encoding.nasm`, or an emulator probe with a hand-checked
  `.expected` file. Never generate `.expected` or `.bin` files by copying tool
  output without checking it.
- The 2004 example `.bin` files are original `NICE.pm` output; do not change them.
- Keep the READMEs in sync with the tools' options, formats, and error behaviour.
- Docs: plain, short sentences. Use the Oxford comma by default ("a, b, and c").
- Commit subjects: `niceasm: ...`, `niceemu: ...`, `runtime: ...`, `nicewasm: ...`, `nicehdl: ...`, `bench: ...`, `intro: ...`, `ISA: ...`, `Review: ...`.
