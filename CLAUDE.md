# CLAUDE.md

NICE is a 32-bit CPU by B. Ulmann; this repo implements it on an FPGA.
The repo holds the spec, an assembler, an emulator, a debugger, a runtime
library, a wasm translator, and two FPGA cores. See README.md.

The rules a change follows, and the tests, are in CONTRIBUTING.md:

@CONTRIBUTING.md

## Layout

- `doc/review/decisions.md`: what was decided against.
- `RELEASE_NOTES.md`: the user-visible changes of each release tag
  (`Vmajor.minor`, the `RC*` tags before `V1.0`), newest first, by component.
- `doc/ISA.md`: the specification. It is authoritative for all code here.
  `doc/review/` records how decisions were reached; ISA.md supersedes it.
- `doc/DEVICES.md`: the devices that the emulator maps into the I/O range
  (console, math unit, counters, timer, SD card, network station,
  Ethernet frames, clock, FPU). ISA.md reserves the range and defines no device.
  ISA.md wins over it.
- `doc/TOOLCHAIN.md`: the tools, what each reads and writes, the steps
  that build a program, how the tools use each other, and the compilers
  and host tools they need. ISA.md wins over it.
- `doc/HISTORY.md`: what used to be true, and how the code got here. Keep it
  out of the other docs, which say only what is true now.
- `doc/DEBUG.md`: the debug link, which a host uses to read and write the
  memory and to load, start, pause, and step a program. The emulator serves
  it with `--link`, and the board repository over its UART. ISA.md and
  DEVICES.md win over it.
- `doc/intro/`: beginner's slides (`nice_intro.tex`, built `nice_intro.pdf`)
  and their example programs. ISA.md wins over them.
- `doc/MICROARCH.md`: design note for the FPGA core. ISA.md wins over it.
  Its block diagram is `doc/pipeline.tex`, and its timing diagrams
  `doc/flow.tex` and `doc/interrupt.tex`, rendered to PNGs by `make diagrams`; edit the `.tex`
  and commit both. The timing values are read off a simulation by hand.
- `assembler/niceasm.py`: Python 3, standard library only, `mypy --strict` clean.
  `assembler/nicefmt.py` checks the column layout of `.nasm` files, or fixes it with `--write`.
  `assembler/nicedis.py` disassembles a `.bin` file back to `.nasm`. Same rules as niceasm.py.
- `emulator/`: Zig 0.17, laid out by `zig fmt`, which `make test` checks.
  `emulator/tools/nicetap.py` joins niceemu's UDP socket for Ethernet frames
  to a TAP device on Linux. Same rules as niceasm.py.
- `debugger/nicedbg.py`: the interactive debugger on the debug link of DEBUG.md,
  over TCP to `niceemu --link` or a UART. `nicelink.py` is the link, and
  `nicebin.py` reads the `.bin` and `.sym` files and loads a program; a
  board's tools import them, with hooks for their own transports and memory.
  Same rules as niceasm.py.
- `runtime/`: start-up code and runtime routines in NICE assembly (`runtime/ABI.md`).
  `runtime/libc/` is the C library for translated programs.
- `translator/nicewasm.py`: wasm -> NICE assembly (`translator/WASM.md`; how it does it is `translator/DESIGN.md`). Same rules as niceasm.py.
  `translator/nicebuild.py` builds a `.c`, `.zig`, or `.rs` file into a `.bin`.
- `bench/bench.c`: a benchmark of translated code, six kernels with known
  results, timed with the performance counters. `hand.nasm` is the same
  benchmark written by hand, the ceiling to compare with. `simple.nasm` is
  `hand.nasm` with `vm` and `strings` as a simple C compiler would emit
  them. `expected.py` computes the results in Python, and `make test`
  checks all three against them. `float.c` is a benchmark of float code,
  and so of the float library, checked against `floatexpected.py`.
  `dhrystone/` is Dhrystone 2.1 on the C library, checked by `dhrycheck.py`.
  `coremark/` is CoreMark on the C library, its upstream files unchanged
  but for `core_portme.c` and `core_portme.h`, checked by `coremarkcheck.py`.
- `demo/demo.nasm`: the demo, a program under a monitor at `0x8000`, which
  runs in `niceemu --window` behind the runtime's stand-in for a monitor,
  and which a board keeps in its ROM (NiceMonMEGA65 joins its own text
  for `text.nasm`). `make test` compares its screens with the hand-checked
  `test.expected`.
- `release/`: `RELEASE.md` is the checklist for a release, and `release.py` scripts its mechanical
  parts (preflight, the gates and their stamp, CI, the tag). `test.py` tests it. Same rules as niceasm.py.
- `hdl/`: VHDL-2008, GHDL, and nvc for the long runs (`hdl/sim.mk`). Two cores with the same ports, but for the
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
    cd assembler && make test        # .nasm -> .bin comparisons, test/errors.py, fmt.py, and dis.py, and the layout of every .nasm
    cd assembler && make typecheck   # mypy --strict
    cd emulator  && make test        # zig fmt --check, zig unit tests, example and probe programs, test/errors.py and link.py, the FPU's model and vectors
    cd emulator  && make typecheck   # mypy --strict
    cd emulator  && make bincheck    # fail if a probe .bin is stale
    cd emulator  && make bins        # reassemble test/*.bin after editing a probe .nasm
    cd emulator  && make fpu-long    # the FPU's vectors with a million random accesses, SEED=1
    cd emulator  && make window-test # build with -Dwindow (SDL from source), run test/window.py headless
    cd debugger  && make test        # test/errors.py, then test/link.py: the link, the loader, and nicedbg's commands on niceemu --link
    cd debugger  && make typecheck   # mypy --strict
    cd runtime   && make test        # join, assemble, and run each test/*.nasm, the Zig and Rust tests, float_fpu.nasm against float.nasm, then the C library tests
    cd runtime   && make typecheck   # mypy --strict
    cd translator && make test       # test/run.py, errors.py, fuzz.py in four modes, passes.py, and build.py
    cd translator && make typecheck  # mypy --strict
    cd bench     && make test        # the benchmark on the emulator, with its results checked
    cd bench     && make core        # the benchmark on a core in simulation, CORE=pipeline or multicycle, SIM=ghdl or nvc (minutes)
    cd bench     && make dhry        # Dhrystone on the emulator, checked by dhrycheck.py
    cd bench     && make core-dhry   # Dhrystone on a core in simulation, CORE and SIM as above, with its output checked (minutes)
    cd bench     && make coremark    # CoreMark on the emulator with both sets of seeds, which make test checks
    cd bench     && make core-coremark # CoreMark on a core in simulation, CORE and SIM as above, with its output checked (minutes)
    cd bench     && make hazards     # how often the pipeline hazards of MICROARCH.md §5 occur
    cd bench     && make cycles      # the estimated cycles on the pipelined core, per phase
    cd bench     && make profile     # the same, per source line, in bench/build/*.cyc.txt
    cd bench     && make compare     # the model's cycles beside the pipelined core's, by phase and by cause, after make core
    cd bench     && make words       # the size in words of the benchmark, safe.zig, CoreMark, float, and math modules
    cd bench     && make typecheck   # mypy --strict
    cd demo      && make test        # the demo on the emulator, its screens compared with test.expected
    cd demo      && make window      # the demo in niceemu --window (make -C emulator window first)
    cd hdl && make test              # synth check, unit tests, tb_trace, then both cores diffed against niceemu
    cd hdl && make typecheck         # mypy --strict
    cd hdl && make lint              # vsg style check (pip install vsg)
    cd hdl && make formal            # SymbiYosys: the ports of both cores and wb_dmux; proofs of FETCH, DECODE, PREPARE, DBUS, WRITE's halt and pause, the shared functions, the devices, and the debug link
    cd hdl && make timing            # the pipelined core's worst paths out of context in Vivado, BOARD=mega65 or nexys4ddr, FLOW=default or timing (3 minutes)
    cd hdl && make timing-spread     # make timing with seven counts of breakpoints and watchpoints at once, and the median of each slack (11 minutes, 40 with FLOW=timing)
    cd hdl && make programs          # the runtime and translator programs on CORE, or its share SHARD=I/N, SIM=ghdl or nvc (minutes)
    cd hdl && make random-sweep      # random programs, seeds 1 to RANDOM_LAST (1000), on each core of CORES (an hour or more)
    cd hdl && make strides           # pcfx and sidefx swept with strides 17, 31, and 64 on CORE (minutes)
    cd hdl && make sweep             # pcfx and sidefx with one interrupt per run on CORE, after an interrupt-path change, SIM=nvc for speed (hours)
    cd doc/intro && make test        # run the slides' example programs
    cd doc/intro && make pdf         # rebuild the slides (pdflatex, beamer)
    cd doc/intro && make pdfcheck    # check that nice_intro.pdf matches the .tex
    cd doc && make test              # the section references and links of every Markdown file
    cd doc && make typecheck         # mypy --strict
    make release-check               # the gates of release/RELEASE.md and the stamp for tagging (about an hour)
    cd release && make test          # the tests of release.py
    cd release && make typecheck     # mypy --strict
    make wasmcheck                   # rebuild the checked-in .wasm files and compare (clang, zig, rustc)
    make diagrams                    # render the diagrams in doc/ to PNG (pdflatex, pdftoppm)
