# CLAUDE.md

NICE is a 32-bit CPU by B. Ulmann; this repo implements it on an FPGA.
The repo holds the spec, an assembler, an emulator, a runtime library, a wasm
translator, and two FPGA cores. See README.md.

## Layout

- `TODO.md`: the single list of open items, undecided questions, and ideas.
  Add new ones there, not in other files or code comments.
- `RELEASE_NOTES.md`: the user-visible changes of each release tag
  (`Vmajor.minor`, the `RC*` tags before `V1.0`), newest first, by component. Add a section for every new tag when it is created.
- `doc/ISA.md`: the specification. It is authoritative for all code here.
  `doc/review/` records how decisions were reached; ISA.md supersedes it.
- `doc/SYSTEM.md`: the devices that the emulator maps into the I/O range
  (console, math unit, counters, timer). ISA.md reserves the range and
  defines no device. ISA.md wins over it.
- `doc/HISTORY.md`: what used to be true, and how the code got here. Keep it
  out of the other docs, which say only what is true now.
- `doc/DEBUG.md`: the debug link, which a host uses to read and write the
  memory and to load, start, pause, and step a program. The emulator serves
  it with `--link`, and the board repository over its UART. ISA.md and
  SYSTEM.md win over it.
- `doc/intro/`: beginner's slides (`nice_intro.tex`, built `nice_intro.pdf`)
  and their example programs. ISA.md wins over them.
- `doc/MICROARCH.md`: design note for the FPGA core. ISA.md wins over it.
  Its block diagram is `doc/pipeline.tex`, and its timing diagrams
  `doc/flow.tex` and `doc/interrupt.tex`, rendered to PNGs by `make diagrams`; edit the `.tex`
  and commit both. The timing values are read off a simulation by hand.
- `assembler/niceasm.py`: Python 3, standard library only, `mypy --strict` clean.
  `assembler/nicefmt.py` checks the column layout of `.nasm` files, or fixes it with `--write`.
- `emulator/`: Zig 0.17.
- `runtime/`: start-up code and runtime routines in NICE assembly (`runtime/ABI.md`).
  `runtime/libc/` is the C library for translated programs.
- `translator/nicewasm.py`: wasm -> NICE assembly (`translator/WASM.md`). Same rules as niceasm.py.
  `translator/nicebuild.py` builds a `.c`, `.zig`, or `.rs` file into a `.bin`.
- `bench/bench.c`: a benchmark of translated code, six kernels with known
  results, timed with the performance counters. `hand.nasm` is the same
  benchmark written by hand, the ceiling to compare with. `simple.nasm` is
  `hand.nasm` with `vm` and `strings` as a simple C compiler would emit
  them. `expected.py` computes the results in Python, and `make test`
  checks all three against them.
  `dhrystone/` is Dhrystone 2.1 on the C library, checked by `dhrycheck.py`.
- `release/`: `RELEASE.md` is the checklist for a release, and `release.py` scripts its mechanical
  parts (preflight, the gates and their stamp, CI, the tag). `test.py` tests it. Same rules as niceasm.py.
- `hdl/`: VHDL-2008, GHDL. Two cores with the same ports, but for the
  pipelined one's `stats_o`: the pipelined one of
  MICROARCH.md in `src/pipeline.vhd`, the default, which connects
  `src/pipe_fetch.vhd`, `pipe_decode.vhd`, `pipe_prepare.vhd`,
  `pipe_dbus.vhd`, and `pipe_write.vhd`, with `pipe_pkg.vhd`; its choices
  are in `hdl/ASSUMPTIONS.md`; and a simple multi-cycle one in
  `src/multicycle.vhd`, the variant. Both use
  `src/nice_pkg.vhd` and `src/trace_pkg.vhd`. Style follows `hdl/CODING_STYLE.md`,
  checked by vsg with `hdl/vsg.yml`. `hdl/CLAUDE.md` has the Vivado path.

## Commands

    make                             # help: the top-level targets, which run the ones below
    make test                        # every quick make test below, in parallel
    cd assembler && make test        # .nasm -> .bin comparisons, test/errors.py and fmt.py, and the layout of every .nasm
    cd assembler && make typecheck   # mypy --strict
    cd emulator  && make test        # zig unit tests, example and probe programs, test/errors.py and link.py
    cd emulator  && make typecheck   # mypy --strict
    cd emulator  && make bincheck    # fail if a probe .bin is stale
    cd emulator  && make bins        # reassemble test/*.bin after editing a probe .nasm
    cd runtime   && make test        # join, assemble, and run each test/*.nasm, then the C library tests
    cd runtime   && make typecheck   # mypy --strict
    cd translator && make test       # test/run.py, errors.py, fuzz.py in four modes, passes.py, and build.py
    cd translator && make typecheck  # mypy --strict
    cd bench     && make test        # the benchmark on the emulator, with its results checked
    cd bench     && make core        # the benchmark on a core in GHDL, CORE=pipeline or multicycle (minutes)
    cd bench     && make dhry        # Dhrystone on the emulator, checked by dhrycheck.py
    cd bench     && make core-dhry   # Dhrystone on a core in GHDL, CORE as above, with its output checked (minutes)
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
    cd hdl && make timing            # the pipelined core's worst paths out of context in Vivado, BOARD=mega65 or nexys4ddr, FLOW=default or timing (3 minutes)
    cd hdl && make programs          # the runtime and translator programs on CORE, or its share SHARD=I/N (minutes)
    cd hdl && make random-sweep      # random programs, seeds 1 to RANDOM_LAST (1000), on each core of CORES (an hour or more)
    cd hdl && make sweep             # pcfx and sidefx with one interrupt per run on CORE (hours)
    cd doc/intro && make test        # run the slides' example programs
    cd doc/intro && make pdf         # rebuild the slides (pdflatex, beamer)
    cd doc/intro && make pdfcheck    # check that nice_intro.pdf matches the .tex
    cd doc && make test              # the section references and links of every Markdown file
    cd doc && make typecheck         # mypy --strict
    make release-check               # the gates of release/RELEASE.md and the stamp for tagging (hours)
    cd release && make test          # the tests of release.py
    cd release && make typecheck     # mypy --strict
    make wasmcheck                   # rebuild the checked-in .wasm files and compare (clang, zig, rustc)
    make diagrams                    # render the diagrams in doc/ to PNG (pdflatex, pdftoppm)

Run the relevant `make test` after every change.

Vivado 2025.1 is installed at `/opt/Xilinx/2025.1/Vivado/bin/vivado`, not on PATH.
`hdl/Makefile` defaults `VIVADO` to that path, so `make timing` works as is.

## Conventions

- Nothing in this repository depends on NiceMonMEGA65, and no release waits
  for it. The pipelined core meeting 100 MHz on the MEGA65 is a goal to keep:
  a change under `hdl/src/pipe_*` that touches the paths of `timing_groups.rpt`
  needs `make -C hdl timing` before and after, with both figures in the commit
  message. `hdl/test/timing_budget.py` holds the budget; a miss warns and never
  fails (release/RELEASE.md, Timing).
- Behavior changes start in ISA.md; code follows the spec, never the reverse.
  Departures from the sources go in ISA.md Appendix B.
- Every bug fix or new rule gets a test: an `errors.py` case, a line in
  `assembler/test/encoding.nasm`, or an emulator probe with a hand-checked
  `.expected` file. Never generate `.expected` or `.bin` files by copying tool
  output without checking it.
- The 2004 example `.bin` files are original `NICE.pm` output; do not change them.
- Keep the READMEs in sync with the tools' options, formats, and error behavior.
- Docs: plain, short sentences. Use the Oxford comma by default ("a, b, and c").
- NICE assembly (`.nasm` files, listings in docs, and the output of
  generators) is laid out in columns, with spaces only and no tabs: the
  label in column 0, the condition in column 8, the mnemonic in column 16,
  the operands in column 24, and the comment in column 40. A label of 8 or
  more characters goes on a line of its own. `assembler/nicefmt.py --write`
  fixes a file, and `make test` checks every `.nasm` file. Listings in
  docs and strings in Python are not checked.
- American spelling everywhere, in docs, comments, and identifiers
  ("behavior", "color", "analyze", "labeled", "gray").
- Commit subjects: `niceasm: ...`, `niceemu: ...`, `runtime: ...`, `nicewasm: ...`, `nicecc: ...`, `nicehdl: ...`, `bench: ...`, `release: ...`, `intro: ...`, `ISA: ...`, `Review: ...`.
- Commit messages follow the 50/72 style: the subject, prefix included, is at
  most 50 characters. A blank line follows it. The body is wrapped at 70
  characters per line.
