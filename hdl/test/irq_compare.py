#!/usr/bin/env python3
"""Compares a core's run with interrupt requests against the emulator.

Usage: irq_compare.py [options] PROGRAM.bin CORE.out INTR.log [-- EMULATOR_OPTIONS...]

CORE.out is the core's trace and output, with "exit N" appended, as the
makefile writes it. INTR.log is the interrupt log of tb_multicycle's
G_INTR_LOG. EMULATOR_OPTIONS go to the emulator as they are, for example
--no-cycle-counter or --input FILE.

The emulator raises a request before a given step and takes it at the
first step that ISA.md §7.1 allows. The pipelined core may take it later,
after an instruction that had already issued a data read (MICROARCH.md §6),
so the steps of the requests alone do not predict its trace (MICROARCH.md
§9). This script reads from the log where the core took each request
instead:

1. Each request that the core took becomes "--nmi S:V" or "--irq S:V",
   where S is the step of its interrupt entry, and V the vector it took.
   Requests that merged count as one. A request that the core never took
   keeps the step it was raised for, so that the emulator holds it pending
   too.
2. The emulator runs the program with those options. Its trace, output,
   and exit status must equal the core's. So the core took each request
   at a step where ISA.md §7.1 allows it, and with the right vector.
3. The core must not take a request late. For each request it took at
   step S, the emulator runs with that request raised for the step it was
   raised for, and stops after S - D steps, where D is --max-delay. The
   request must still be pending: the emulator would not have taken it
   before step S - D either. The multi-cycle core takes a request at the
   first step it may, so D is 0 for it.
"""

import argparse
import os
import re
import sys
from dataclasses import dataclass

from core_runs import DEFAULT_EMU, difference, run_emulator


@dataclass
class Take:
    """Requests of one kind, merged and taken by one interrupt entry."""

    kind: str  # "nmi" or "irq"
    raised: int  # The step the first of them was raised for
    vector_raised: int  # Its vector
    step: int  # The step of the interrupt entry
    vector: int  # The vector taken


def infer(log: str) -> tuple[list[str], list[Take], list[str]]:
    """The emulator's interrupt options from an interrupt log, the takes,
    and any problems with the log."""
    options: list[str] = []
    takes: list[Take] = []
    problems: list[str] = []
    pending: dict[str, list[tuple[int, int]]] = {"nmi": [], "irq": []}
    accepted: dict[str, list[tuple[int, int]]] = {"nmi": [], "irq": []}
    for n, line in enumerate(log.splitlines(), 1):
        f = line.split()
        if len(f) == 4 and f[0] == "raised" and f[2] in pending:
            pending[f[2]].append((int(f[1]), int(f[3], 16)))
        elif len(f) == 2 and f[0] == "accepted" and f[1] in pending:
            if not pending[f[1]]:
                problems.append(f"log line {n}: {f[1]} accepted with no request raised")
            elif accepted[f[1]]:
                problems.append(f"log line {n}: {f[1]} accepted twice before its entry")
            accepted[f[1]] = pending[f[1]]
            pending[f[1]] = []
        elif len(f) == 4 and f[0] == "taken" and f[2] in pending:
            kind, step, vector = f[2], int(f[1]), int(f[3], 16)
            reqs = accepted[kind]
            if not reqs:
                problems.append(f"log line {n}: {kind} entry at step {step} with no request accepted")
                continue
            accepted[kind] = []
            if vector != reqs[-1][1]:
                problems.append(f"log line {n}: {kind} entry at step {step} with vector {vector:02x}, "
                                f"but the last request raised has {reqs[-1][1]:02x}")
            takes.append(Take(kind, reqs[0][0], reqs[0][1], step, vector))
            options += [f"--{kind}", f"{step}:{vector}"]
        else:
            problems.append(f"log line {n}: cannot read {line!r}")
    for kind in ("nmi", "irq"):
        if accepted[kind]:
            problems.append(f"{kind} accepted, but its entry never reported")
        for step, vector in pending[kind]:
            options += [f"--{kind}", f"{step}:{vector}"]
    return options, takes, problems


def check(emu: str, binfile: str, core_output: str, log: str, emu_options: list[str],
          max_delay: int = 0) -> list[str]:
    """The problems with a core's run, or none."""
    options, takes, problems = infer(log)
    expected = run_emulator(emu, binfile, [*emu_options, *options])
    diff = difference(expected, core_output)
    if diff is not None:
        problems.append(f"with {' '.join(options)}: {diff}")
    for i, t in enumerate(takes):
        limit = t.step - max_delay
        if limit <= t.raised:
            continue
        # The other requests as the core took them, and this one as it was
        # raised.
        others = [o for j, u in enumerate(takes) if j != i
                  for o in (f"--{u.kind}", f"{u.step}:{u.vector}")]
        early = [*emu_options, *others, f"--{t.kind}", f"{t.raised}:{t.vector_raised}",
                 "-n", str(limit)]
        out = run_emulator(emu, binfile, early)
        pend = re.search(r"^Pending:(.*)$", out, re.M)
        if pend is None or t.kind.upper() not in pend.group(1):
            problems.append(f"{t.kind} raised for step {t.raised} was taken at step {t.step}, "
                            f"but the emulator takes it before step {limit}")
    return problems


def main() -> None:
    args, emu_options = sys.argv[1:], []
    if "--" in args:
        i = args.index("--")
        args, emu_options = args[:i], args[i + 1:]
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("program")
    p.add_argument("core")
    p.add_argument("log")
    p.add_argument("--max-delay", type=int, default=0,
                   help="steps a request may be taken late (default 0)")
    p.add_argument("--emu", default=DEFAULT_EMU)
    p.add_argument("--name", help="the name of the run, for the PASS or FAIL line")
    a = p.parse_args(args)
    with open(a.core, errors="replace") as f:
        core_output = f.read()
    # No log means that no request was raised.
    log = ""
    if os.path.exists(a.log):
        with open(a.log) as f:
            log = f.read()
    problems = check(a.emu, a.program, core_output, log, emu_options, a.max_delay)
    name = a.name or os.path.basename(a.core)
    for problem in problems:
        print(problem)
    print(f"{'FAIL' if problems else 'PASS'} irq_compare {name}")
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
