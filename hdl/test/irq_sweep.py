#!/usr/bin/env python3
"""Runs a program on the core with an interrupt request before each step.

Usage: irq_sweep.py [options] PROGRAM.bin

Step 5 of the test order in MICROARCH.md §9. The program runs once on the
emulator, which gives its number of steps N. Then, for each kind of request
(NMI and IRQ) and each step S from 0 to N - 1, it runs once on the core in
tb_core and once on the emulator, with the one request "--nmi S:VEC"
or "--irq S:VEC". The trace, the output, and the exit status of the two
must be the same, as in the makefile's other runs. test/irq_compare.py
must also pass, with the steps where the core took the request. Each run on the
emulator must also take the request, so the trace has no "Pending:" line,
and with --self-check, end as test/hazard.nasm does when it passes: with
R12 = 0 and exit status 0.

The runs are independent, so they go in parallel, as test/core_runs.py
describes. The VHDL must be analysed in BUILD already.

For the multi-cycle core the request step decides where the request is
taken. For the pipelined core it does not (MICROARCH.md §9). With
--read-delay, the core's run is not compared with the emulator's run with
the request as raised, but only by test/irq_compare.py with --read-delay,
which reads where the core took it. With --self-check, the core's run must
then end as hazard.nasm does when it passes, too.

With --delays, each run is repeated with tb_core's G_INTR_DELAY set to
each of the delays given, so that the request arrives that many cycles
after the step it names would raise it, anywhere within an instruction.
A run with a delay is also compared only through irq_compare.py. The
last step gets no delayed request (see main).
"""

import argparse
import concurrent.futures
import os
import re
import sys

from core_runs import DEFAULT_BUILD, DEFAULT_CORE, DEFAULT_EMU, Core, difference, run_emulator
from irq_compare import check as irq_compare


def check(args: argparse.Namespace, core: Core, kind: str, vec: int, step: int,
          delay: int) -> str | None:
    """Returns None if the run passes, or what went wrong."""
    opts = [f"--{kind}", f"{step}:{vec}"]
    name = f"--{kind} {step}:{vec} delay {delay}"
    expected = run_emulator(args.emu, args.program, opts)
    if "Pending:" in expected:
        return f"{name}: the emulator never took the request"
    if args.self_check and not (
        re.search(r"^R12 00000000", expected, re.M) and expected.endswith("exit 0\n")
    ):
        return f"{name}: the program's own checks failed on the emulator\n" + expected[-400:]
    got, log = core.run_logged(
        args.program,
        ["-gG_INTERRUPTS=" + " ".join(opts), f"-gG_STALL={args.stall}", f"-gG_SEED={step + 1}",
         f"-gG_INTR_DELAY={delay}"],
    )
    if args.read_delay or delay > 0:
        if args.self_check and not (re.search(r"^R12 00000000", got, re.M) and got.endswith("exit 0\n")):
            return f"{name}: the program's own checks failed on the core\n" + got[-400:]
    else:
        diff = difference(expected, got)
        if diff is not None:
            return f"{name}: {diff}"
    problems = irq_compare(args.emu, args.program, got, log, [], read_delay=args.read_delay)
    return None if not problems else f"{name}: irq_compare: " + "\n".join(problems)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("program")
    p.add_argument("--nmi", type=lambda s: int(s, 0), default=8, help="the NMI vector (default 8)")
    p.add_argument("--irq", type=lambda s: int(s, 0), default=9, help="the IRQ vector (default 9)")
    p.add_argument("--stall", type=int, default=0, help="G_STALL of the memory, in percent")
    p.add_argument("--self-check", action="store_true", help="every run must pass as hazard.nasm does")
    p.add_argument("--read-delay", action="store_true",
                   help="the core may take a request late, after instructions with a data read")
    p.add_argument("--delays", type=lambda s: [int(d) for d in s.split(",")], default=[0],
                   help="the delays of the request in cycles, comma-separated (default 0)")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    p.add_argument("--core", default=DEFAULT_CORE, help="G_CORE of tb_core (default multicycle)")
    p.add_argument("--build", default=DEFAULT_BUILD)
    p.add_argument("--emu", default=DEFAULT_EMU)
    p.add_argument("--ghdl", default=os.environ.get("GHDL", "ghdl"))
    args = p.parse_args()

    plain = run_emulator(args.emu, args.program, [])
    m = re.search(r"after (\d+) steps", plain)
    if not m:
        sys.exit(f"irq_sweep: the program does not halt on the emulator:\n{plain[-400:]}")
    steps = int(m.group(1))

    # Each sweep has its own directory, so that sweeps can go in parallel.
    name = os.path.basename(args.program)
    work = os.path.join("sweep", f"{args.core}_{os.path.splitext(name)[0]}")
    core = Core(args.ghdl, args.build, work, args.core)
    # A request delayed into the last step, the halt, would be pending at
    # the end, which the emulator cannot be told: it raises a request only
    # before a step.
    jobs = [(kind, vec, s, d) for kind, vec in (("nmi", args.nmi), ("irq", args.irq))
            for s in range(steps) for d in args.delays if d == 0 or s < steps - 1]
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda j: check(args, core, *j), jobs))
    core.clean()

    failures = [r for r in results if r is not None]
    for r in failures[:10]:
        print(r)
    if failures:
        print(f"FAIL irq_sweep {args.core} {name}: {len(failures)} of {len(jobs)} runs")
        sys.exit(1)
    print(f"PASS irq_sweep {args.core} {name}: {len(jobs)} runs")


if __name__ == "__main__":
    main()
