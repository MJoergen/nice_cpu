# CLAUDE.md

NICE is a 32-bit CPU by B. Ulmann; this repo implements it on an FPGA.
The repo holds the spec, an assembler, an emulator, a runtime library, a wasm
translator, and two FPGA cores. See README.md.

## Layout

- `TODO.md`: the single list of open items, undecided questions, and ideas.
  Add new ones there, not in other files or code comments.
- `doc/ISA.md`: the specification. It is authoritative for all code here.
  `doc/review/` records how decisions were reached; ISA.md supersedes it.
- `doc/SYSTEM.md`: the devices that the emulator maps into the I/O range
  (console, math unit, counters, timer). ISA.md reserves the range and
  defines no device. ISA.md wins over it.
- `doc/HISTORY.md`: what used to be true, and how the code got here. Keep it
  out of the other docs, which say only what is true now.
- `doc/intro/`: beginner's slides (`nice_intro.tex`, built `nice_intro.pdf`)
  and their example programs. ISA.md wins over them.
- `doc/MICROARCH.md`: design note for the FPGA core. ISA.md wins over it.
  Its block diagram is `doc/pipeline.tex`, and its timing diagrams
  `doc/flow.tex` and `doc/interrupt.tex`, rendered to PNGs by `make diagrams`; edit the `.tex`
  and commit both. The timing values are read off a simulation by hand.
- `assembler/niceasm.py`: Python 3, standard library only, `mypy --strict` clean.
- `emulator/`: Zig 0.15.
- `runtime/`: start-up code and runtime routines in NICE assembly (`runtime/ABI.md`).
- `translator/nicewasm.py`: wasm -> NICE assembly (`translator/WASM.md`). Same rules as niceasm.py.
- `bench/bench.c`: a benchmark of translated code, six kernels with known
  results, timed with the performance counters. `hand.nasm` is the same
  benchmark written by hand, the ceiling to compare with. `simple.nasm` is
  `hand.nasm` with `vm` and `strings` as a simple C compiler would emit
  them. `expected.py` computes the results in Python, and `make test`
  checks all three against them.
  `dhrystone/` is Dhrystone 2.1 on the C library, checked by `dhrycheck.py`.
- `hdl/`: VHDL-2008, GHDL. Two cores with the same ports, but for the
  pipelined one's `stats_o`: the pipelined one of
  MICROARCH.md in `src/pipeline.vhd`, the default, which connects
  `src/pipe_fetch.vhd`, `pipe_decode.vhd`, `pipe_prepare.vhd`,
  `pipe_dbus.vhd`, and `pipe_write.vhd`, with `pipe_pkg.vhd`; its choices
  are in `hdl/ASSUMPTIONS.md`; and a simple multi-cycle one in
  `src/multicycle.vhd`, the variant. Both use
  `src/nice_pkg.vhd` and `src/trace_pkg.vhd`. Style follows `hdl/CODING_STYLE.md`,
  checked by vsg with `hdl/vsg.yml`.

## Commands

    make                             # help: the top-level targets, which run the ones below
    make test                        # every quick make test below, in parallel
    cd assembler && make test        # .nasm -> .bin comparisons, then test/errors.py
    cd assembler && make typecheck   # mypy --strict
    cd emulator  && make test        # zig unit tests, example and probe programs, test/errors.py
    cd emulator  && make typecheck   # mypy --strict
    cd emulator  && make bins        # reassemble test/*.bin after editing a probe .nasm
    cd runtime   && make test        # join, assemble, and run each test/*.nasm
    cd runtime   && make typecheck   # mypy --strict
    cd translator && make test       # test/run.py, errors.py, fuzz.py in four modes, and passes.py
    cd translator && make typecheck  # mypy --strict
    cd bench     && make test        # the benchmark on the emulator, with its results checked
    cd bench     && make core        # the benchmark on a core in GHDL, CORE=pipeline or multicycle (minutes)
    cd bench     && make hazards     # how often the pipeline hazards of MICROARCH.md §5 occur
    cd bench     && make cycles      # the estimated cycles on the pipelined core, per phase
    cd bench     && make profile     # the same, per source line, in bench/build/*.cyc.txt
    cd bench     && make compare     # the estimate beside the pipelined core's cycles, after make core
    cd bench     && make words       # the size in words of the benchmark, safe.zig, and float modules
    cd bench     && make typecheck   # mypy --strict
    cd hdl && make test              # synth check, unit tests, tb_trace, then both cores diffed against niceemu
    cd hdl && make typecheck         # mypy --strict
    cd hdl && make lint              # vsg style check (pip install vsg)
    cd hdl && make formal            # SymbiYosys: the ports of both cores and wb_dmux; proofs of FETCH, DECODE, PREPARE, DBUS, WRITE's halt and pause, the shared functions, the devices, and the debug link
    cd hdl && make timing            # the pipelined core's worst paths out of context in Vivado, BOARD=mega65 or nexys4ddr, FLOW=default or timing (10 minutes)
    cd hdl && make programs          # the runtime and translator programs on CORE (minutes)
    cd hdl && make random-sweep      # random programs, seeds 1 to RANDOM_LAST (1000), on each core of CORES (an hour or more)
    cd hdl && make sweep             # pcfx and sidefx with one interrupt per run on CORE (hours)
    cd doc/intro && make test        # run the slides' example programs
    cd doc/intro && make pdf         # rebuild the slides (pdflatex, beamer)
    cd doc/intro && make pdfcheck    # check that nice_intro.pdf matches the .tex
    cd doc && make test              # the section references and links of every Markdown file
    cd doc && make typecheck         # mypy --strict
    make diagrams                    # render the diagrams in doc/ to PNG (pdflatex, pdftoppm)

Run the relevant `make test` after every change.

## Conventions

- Behavior changes start in ISA.md; code follows the spec, never the reverse.
  Departures from the sources go in ISA.md Appendix B.
- Every bug fix or new rule gets a test: an `errors.py` case, a line in
  `assembler/test/encoding.nasm`, or an emulator probe with a hand-checked
  `.expected` file. Never generate `.expected` or `.bin` files by copying tool
  output without checking it.
- The 2004 example `.bin` files are original `NICE.pm` output; do not change them.
- Keep the READMEs in sync with the tools' options, formats, and error behavior.
- Docs: plain, short sentences. Use the Oxford comma by default ("a, b, and c").
- American spelling everywhere, in docs, comments, and identifiers
  ("behavior", "color", "analyze", "labeled", "gray").
- Commit subjects: `niceasm: ...`, `niceemu: ...`, `runtime: ...`, `nicewasm: ...`, `nicecc: ...`, `nicehdl: ...`, `bench: ...`, `intro: ...`, `ISA: ...`, `Review: ...`.
