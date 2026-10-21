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

With --stride K, a run raises a request before every Kth step of the
program, from step k, and K runs, k = 0 to K - 1, cover every step. That
takes K runs per kind instead of N, each a little longer. Each request
taken adds H steps, its entry and its routine, which a run of the
emulator with one request measures, so the request before the program's
step P, after i requests taken, is raised for step P + H * i. The sweep
counts the steps of the program that a request came before, from the
emulator's traces, and prints that for each kind. A program that writes
R14 with any value may have no vector table at some steps. So each
interrupt entry must find a vector word in the program's image that
names the same routine as the entry for VBASE = 0, which every swept
program has. If one does not, its request is dropped from the run, which is planned again,
and the step it would have come before is left out, counted in the
summary. Without
--stride, each run has one request, and there are N runs per kind.
"""

import argparse
import concurrent.futures
import os
import re
import sys

from core_runs import DEFAULT_BUILD, DEFAULT_CORE, DEFAULT_EMU, Core, difference, run_emulator
from irq_compare import check as irq_compare

ENTRY = re.compile(r"(NMI|IRQ) ([0-9a-f]{2}) ")
INSN = re.compile(r"[0-9a-f]{8} [0-9a-f]{8}")
R14 = re.compile(r"\bR14=([0-9a-f]{8})")
IO = 0xFFFFFF00


def image(binfile: str) -> dict[int, int]:
    """The words of the program's image, by address."""
    with open(binfile) as f:
        return {int(a, 16): int(w, 16) for a, w in (line.split() for line in f if line.strip())}


def scan(trace: str, extra: int, words: dict[int, int]) -> tuple[set[int], list[int]]:
    """The steps of the program that an interrupt entry in the trace came
    before, and the numbers of the entries whose vector word in words does
    not name the routine that VBASE = 0 names. Each entry adds extra steps,
    itself included."""
    r14, plain, skip, n = 0x01000000, 0, 0, 0
    covered: set[int] = set()
    bad: list[int] = []
    for line in trace.splitlines():
        m = ENTRY.match(line)
        if m:
            vec = int(m.group(2), 16)
            vaddr = ((r14 & 0xFFFFFF) << 8) + vec
            if vaddr >= IO or vaddr not in words or words[vaddr] != words.get(vec):
                bad.append(n)
            n += 1
            covered.add(plain)
            skip = extra - 1
        elif INSN.match(line):
            if skip:
                skip -= 1
            else:
                plain += 1
        for v in R14.findall(line):
            r14 = int(v, 16)
    return covered, bad


def plan(args: argparse.Namespace, steps: int, extra: int, words: dict[int, int], kind: str,
         vec: int, first: int) -> tuple[list[int], set[int], set[int]]:
    """The steps to raise requests for, in a run from the program's step
    first, the program's steps they come before, and those left out."""
    wanted = list(range(first, steps, args.stride or steps))
    dropped: set[int] = set()
    while True:
        keep = [s for s in wanted if s not in dropped]
        raised = [s + extra * i for i, s in enumerate(keep)]
        # A run that goes astray stops once it has had the steps it needs.
        limit = ["-n", str(steps + extra * len(keep))]
        trace = run_emulator(args.emu, args.program, [o for s in raised for o in (f"--{kind}", f"{s}:{vec}")] + limit)
        covered, bad = scan(trace, extra, words)
        # After the first entry with no vector, the run goes astray.
        if not bad or bad[0] >= len(keep):
            return raised, covered, dropped
        dropped.add(keep[bad[0]])


def check(args: argparse.Namespace, core: Core, kind: str, vec: int, raised: list[int],
          delay: int) -> str | None:
    """Returns None if the run passes, or what went wrong."""
    opts = [o for s in raised for o in (f"--{kind}", f"{s}:{vec}")]
    first = f"{raised[0]}, every {args.stride}" if len(raised) > 1 else str(raised[0])
    name = f"--{kind} {first}:{vec} delay {delay}"
    expected = run_emulator(args.emu, args.program, opts)
    if "Pending:" in expected:
        return f"{name}: the emulator never took the request"
    if args.self_check and not (
        re.search(r"^R12 00000000", expected, re.M) and expected.endswith("exit 0\n")
    ):
        return f"{name}: the program's own checks failed on the emulator\n" + expected[-400:]
    got, log = core.run_logged(
        args.program,
        ["-gG_INTERRUPTS=" + " ".join(opts), f"-gG_STALL={args.stall}", f"-gG_SEED={raised[0] + 1}",
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
    p.add_argument("--stride", type=int,
                   help="raise a request before every this many steps in each run (default: one per run)")
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
    words = image(args.program)
    kinds = [("nmi", args.nmi), ("irq", args.irq)]
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        extra = {}
        for kind, vec in kinds:
            one = run_emulator(args.emu, args.program, [f"--{kind}", f"{steps // 2}:{vec}"])
            m = re.search(r"after (\d+) steps", one)
            if not m:
                sys.exit(f"irq_sweep: the program does not halt with one {kind}:\n{one[-400:]}")
            extra[kind] = int(m.group(1)) - steps
        plans = {(kind, vec, k): pool.submit(plan, args, steps, extra[kind], words, kind, vec, k)
                 for kind, vec in kinds for k in range(min(args.stride or steps, steps))}
        # A request delayed into the last step, the halt, would be pending
        # at the end, which the emulator cannot be told: it raises a
        # request only before a step.
        jobs = []
        for (kind, vec, k), f in plans.items():
            raised = f.result()[0]
            last = (steps - 1 - k) % (args.stride or steps) == 0
            for d in args.delays:
                kept = raised[:-1] if d > 0 and last else raised
                if kept:
                    jobs.append((kind, vec, kept, d))
        results = list(pool.map(lambda j: check(args, core, *j), jobs))
    core.clean()

    failures = [r for r in results if r is not None]
    for fail in failures[:10]:
        print(fail)
    if failures:
        print(f"FAIL irq_sweep {args.core} {name}: {len(failures)} of {len(jobs)} runs")
        sys.exit(1)
    summary = []
    for kind, vec in kinds:
        runs = [f.result() for (k, _, _), f in plans.items() if k == kind]
        covered = set().union(*(c for _, c, _ in runs))
        dropped = set().union(*(d for _, _, d in runs))
        summary.append(f"{kind} before {len(covered)} of {steps} steps"
                       + (f" ({len(dropped)} left out, no vector table)" if dropped else ""))
    print(f"PASS irq_sweep {args.core} {name}: {len(jobs)} runs, {', '.join(summary)}")


if __name__ == "__main__":
    main()
