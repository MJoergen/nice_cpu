#!/usr/bin/env python3
"""Compares a core's run with interrupt requests against the emulator.

Usage: irq_compare.py [options] PROGRAM.bin CORE.out INTR.log [-- EMULATOR_OPTIONS...]
       irq_compare.py --test [--emu EMU]   the self-test of make test

CORE.out is the core's trace and output, with "exit N" appended, as the
makefile writes it. INTR.log is the interrupt log of tb_core's
G_INTR_LOG. EMULATOR_OPTIONS go to the emulator as they are, for example
--no-cycle-counter or --input FILE.

The emulator raises a request before a given step and takes it at the
first step that ISA.md §7.1 allows. The log holds the requests of the
timer too, so the emulator runs with --no-timer-irq, and its timer raises
none itself. The pipelined core may take it later,
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

With --read-delay, the check follows the core instead. The pipelined core
takes a request at the first instruction boundary it reaches after the
request, unless the next instruction has already issued a data read, and
then the one after, and so on (MICROARCH.md §6). So it may pass, without
taking the request, a run of instructions with a data read that starts at
the first boundary where ISA.md §7.1 allows the request, and from the end
of that run on, it must take the request as ISA.md §7.1 says. That may be
later still: an NMI goes first, and is followed by its RTI and the
instruction after it. For each request it took at step S, the emulator
runs with the request raised for the step it was raised for, and with the
other requests as the core took them. If the emulator takes it before
step S, at a step that is an instruction with a data read in the core's
trace, the emulator runs again with the request raised for the step after
that one, and so on, while the steps follow each other. The emulator must
then take the request at step S, as the core did.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
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
            if vector != reqs[0][1]:
                problems.append(f"log line {n}: {kind} entry at step {step} with vector {vector:02x}, "
                                f"but the first request raised has {reqs[0][1]:02x}")
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


STEP = re.compile(r"(?:(NMI|IRQ) [0-9a-f]{2} )|([0-9a-f]{8}) ([0-9a-f]{8})( skipped)?")


def step_lines(trace: str) -> list[str]:
    """The lines of a trace that are steps."""
    return [line for line in trace.splitlines()
            if STEP.search(line) is not None and not line.startswith(("Halted", "Stopped", "Pending"))]


def reads(trace: str) -> list[bool]:
    """For each step of a trace, whether it is an instruction that made a
    data read: an ALU or shift instruction, not skipped, with s0 or s1 in
    memory (ISA.md §8.2)."""
    steps: list[bool] = []
    for line in step_lines(trace):
        m = STEP.search(line)
        assert m is not None
        if m.group(1):
            steps.append(False)
            continue
        iw = int(m.group(3), 16)
        alu_or_shift = (iw >> 26) & 3 != 3
        memory = (iw >> 13) & 1 == 1 or (iw >> 6) & 1 == 1
        steps.append(alu_or_shift and memory and m.group(4) is None)
    return steps


def check(emu: str, binfile: str, core_output: str, log: str, emu_options: list[str],
          max_delay: int = 0, read_delay: bool = False) -> list[str]:
    """The problems with a core's run, or none."""
    options, takes, problems = infer(log)
    expected = run_emulator(emu, binfile, [*emu_options, "--no-timer-irq", *options])
    diff = difference(expected, core_output)
    if diff is not None:
        problems.append(f"with {' '.join(options)}: {diff}")
    steps = reads(expected)
    lines = step_lines(expected)
    for i, t in enumerate(takes):
        # The other requests as the core took them, and this one as it was
        # raised.
        others = [o for j, u in enumerate(takes) if j != i
                  for o in (f"--{u.kind}", f"{u.step}:{u.vector}")]
        raised = t.raised
        chained = False
        while t.step - max_delay > raised:
            early = [*emu_options, "--no-timer-irq", *others, f"--{t.kind}",
                     f"{raised}:{t.vector_raised}", "-n", str(t.step - max_delay)]
            out = run_emulator(emu, binfile, early)
            pend = re.search(r"^Pending:(.*)$", out, re.M)
            if pend is not None and t.kind.upper() in pend.group(1):
                break
            # The step where the emulator took it: the first one that is
            # not the core's.
            got = step_lines(out)
            k = next((k for k, line in enumerate(got) if k >= len(lines) or line != lines[k]),
                     len(got))
            if read_delay and k < t.step and (not chained or k == raised) and steps[k]:
                raised, chained = k + 1, True
                continue
            problems.append(f"{t.kind} raised for step {t.raised} was taken at step {t.step}, "
                            f"but the emulator takes it at step {k}")
            break
    return problems


# The program of the self-test, with its steps. The core's run of each
# case is the emulator's with the requests at the steps of the log's
# "taken" lines, which is what check 2 requires.
TEST_PROGRAM = """\
                JMP     start           ; 0
                .ORG    8
                .DAT    nmi, irq
                .ORG    0x100
start           MOVE    R14, 0x40000000 ; 1: E = 1
                MOVE    R1, data        ; 2
                ADD     R2, @R1, 1      ; 3: a data read
                ADD     R2, @R1, 2      ; 4: a data read
                ADD     R3, R3, 1       ; 5
                ADD     R3, R3, 1       ; 6
                ADD     R3, R3, 1       ; 7
                ADD     R3, R3, 1       ; 8
                HALT
nmi             RTI
irq             RTI
data            .DAT    5
"""

# Each case: the log, whether it uses --read-delay, and whether check 3
# must pass.
TEST_CASES = [
    # Taken at the first step it may be.
    ("raised 2 irq 09\naccepted irq\ntaken 2 irq 09\n", False, True),
    # Late by one step without a data read.
    ("raised 2 irq 09\naccepted irq\ntaken 3 irq 09\n", True, False),
    # Late by the reads of steps 3 and 4, right before the entry.
    ("raised 3 irq 09\naccepted irq\ntaken 5 irq 09\n", True, True),
    # The same without --read-delay.
    ("raised 3 irq 09\naccepted irq\ntaken 5 irq 09\n", False, False),
    # Late by the reads, and then by step 5, which has none.
    ("raised 3 irq 09\naccepted irq\ntaken 6 irq 09\n", True, False),
    # Late by the read of step 4, and then by an NMI at step 5, its RTI,
    # and the instruction after the RTI, which comes first.
    ("raised 4 irq 09\nraised 5 nmi 08\naccepted nmi\ntaken 5 nmi 08\n"
     "accepted irq\ntaken 8 irq 09\n", True, True),
    # The same with the NMI one step later: the IRQ could be taken at step 5.
    ("raised 4 irq 09\nraised 6 nmi 08\naccepted nmi\ntaken 6 nmi 08\n"
     "accepted irq\ntaken 9 irq 09\n", True, False),
    # The NMI before the read: no read to excuse the IRQ at step 2.
    ("raised 2 irq 09\nraised 2 nmi 08\naccepted nmi\ntaken 2 nmi 08\n"
     "accepted irq\ntaken 5 irq 09\n", True, True),
    ("raised 2 irq 09\nraised 3 nmi 08\naccepted nmi\ntaken 3 nmi 08\n"
     "accepted irq\ntaken 6 irq 09\n", True, False),
]


def self_test(emu: str) -> int:
    """The self-test: check 3 on the cases of TEST_CASES."""
    here = os.path.dirname(os.path.abspath(__file__))
    asm = os.path.join(here, "..", "..", "assembler", "niceasm.py")
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        src, binfile = os.path.join(tmp, "t.nasm"), os.path.join(tmp, "t.bin")
        with open(src, "w") as f:
            f.write(TEST_PROGRAM)
        subprocess.run([sys.executable, asm, src, "-o", binfile], check=True)
        for n, (log, read_delay, ok) in enumerate(TEST_CASES, 1):
            options, _, problems = infer(log)
            assert not problems, problems
            core = run_emulator(emu, binfile, ["--no-timer-irq", *options])
            problems = check(emu, binfile, core, log, [], read_delay=read_delay)
            if (not problems) != ok:
                failures += 1
                print(f"FAIL irq_compare self-test case {n}: expected "
                      f"{'a pass' if ok else 'a failure'}, got {problems or 'a pass'}")
    if not failures:
        print(f"PASS irq_compare self-test, {len(TEST_CASES)} cases")
    return 1 if failures else 0


def main() -> None:
    args, emu_options = sys.argv[1:], []
    if args[:1] == ["--test"]:
        t = argparse.ArgumentParser()
        t.add_argument("--test", action="store_true")
        t.add_argument("--emu", default=DEFAULT_EMU)
        sys.exit(self_test(t.parse_args(args).emu))
    if "--" in args:
        i = args.index("--")
        args, emu_options = args[:i], args[i + 1:]
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("program")
    p.add_argument("core")
    p.add_argument("log")
    p.add_argument("--max-delay", type=int, default=0,
                   help="steps a request may be taken late (default 0)")
    p.add_argument("--read-delay", action="store_true",
                   help="a request may be taken late by the instructions with a data read "
                        "right before it")
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
    problems = check(a.emu, a.program, core_output, log, emu_options, a.max_delay,
                     a.read_delay)
    name = a.name or os.path.basename(a.core)
    for problem in problems:
        print(problem)
    print(f"{'FAIL' if problems else 'PASS'} irq_compare {name}")
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
