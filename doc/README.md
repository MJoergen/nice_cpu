# doc

The documents of the NICE processor. [ISA.md](ISA.md) is the
specification, and it wins over every other document here.

| Path | What it is |
|---|---|
| [ISA.md](ISA.md) | The instruction set: the specification for everything else here. |
| [SYSTEM.md](SYSTEM.md) | The devices that the emulator maps into the I/O range: console, math unit, performance counters, and timer. |
| [MICROARCH.md](MICROARCH.md) | The design note for the pipelined FPGA core. |
| [REFERENCES.md](REFERENCES.md) | The NICE and QNICE sources the specification is based on. |
| [HISTORY.md](HISTORY.md) | How the design and the tools got here: what the documents used to say, and the steps of the optimizations. |
| [review/](review/) | Notes on how each ISA decision was reached, and the reviews of the tools. ISA.md supersedes them. |
| [intro/](intro/nice_intro.pdf) | A beginner's introduction to NICE: slides, with example programs that assemble and run. |

## Diagrams

`pipeline.tex` is the block diagram of MICROARCH.md, `flow.tex` its
timing diagram of one instruction, and `interrupt.tex` its interrupt
timing diagram. `make diagrams` in the top directory renders
them to PNGs. Edit the `.tex`, and commit both it and the `.png`.

## Test

    make test

This runs `check_refs.py`. It checks that every `FILE.md §n.m` in the
repository names a section that FILE.md has, and that every link of every
Markdown file names a file that exists and a heading it has.

`make typecheck` checks the script with `mypy --strict` (install mypy
first).
