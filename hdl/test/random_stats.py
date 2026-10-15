#!/usr/bin/env python3
"""How well the random programs of random_prog.py test the core.

Usage: random_stats.py [options] FIRST LAST

Runs the programs of seeds FIRST to LAST on the emulator, as the makefile
does, and reports what the runs spend their steps on:
- where the steps run: the program, its interrupt routines, or elsewhere,
  such as the words below DATA or empty memory, which runs as NOPs;
- how many of the program's instructions run at least once;
- the interrupt requests, and how many are taken;
- how the runs end;
- the hazards of MICROARCH.md §5, as bench/hazards.py counts them, over
  all the runs, beside the shares of the benchmark of MICROARCH.md §5.6.
"""

import argparse
import collections
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EMU = os.path.join(HERE, "..", "..", "emulator", "zig-out", "bin", "niceemu")
HAZARDS = os.path.join(HERE, "..", "..", "bench", "hazards.py")

# The hazards to show, with their shares in bench.c through nicewasm and in
# hand.nasm (MICROARCH.md §5.6).
SHOWN = {
    "conditional": "22.5 27.7",
    "data read": "25.9 41.7",
    "store": "27.4 15.4",
    "jump: writes R15, or control": "19.3 21.1",
    "reads a register the previous instruction writes": "26.9 30.0",
    "reads a register written two back, not one": "4.3 14.0",
    "conditional, SR written by the previous instruction": "15.3 20.3",
    "conditional with a data read, SR written by the previous": "1.1 3.8",
    "data read after a store": "15.3 8.1",
    "data read after a conditional jump": "0.9 7.6",
    "R14 read as an operand or base": "0.8 6.6",
    "R15 as a pointer, or with a side effect": "0 0",
}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("first", type=int)
    p.add_argument("last", type=int)
    p.add_argument("--steps", type=int, default=3000, help="the step limit (default 3000)")
    p.add_argument("--generator", default=os.path.join(HERE, "random_prog.py"))
    p.add_argument("-v", "--verbose", action="store_true", help="a line for each seed")
    args = p.parse_args()

    spec = importlib.util.spec_from_file_location("hazards", HAZARDS)
    assert spec is not None and spec.loader is not None
    hazards = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hazards)
    gen = importlib.util.spec_from_file_location("gen", args.generator)
    assert gen is not None and gen.loader is not None
    generator = importlib.util.module_from_spec(gen)
    gen.loader.exec_module(generator)
    code = generator.CODE
    routines = getattr(generator, "ROUTINES", None)

    where: collections.Counter[str] = collections.Counter()
    ends: collections.Counter[str] = collections.Counter()
    requested = taken = covered = size = 0
    lines: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        binfile = os.path.join(tmp, "r.bin")
        for seed in range(args.first, args.last + 1):
            opts = subprocess.run(
                [sys.executable, args.generator, str(seed), binfile],
                capture_output=True, text=True, check=True,
            ).stdout.split()
            with open(binfile) as f:
                image = dict((int(a, 16), int(w, 16)) for a, w in (line.split() for line in f))
            end = max(a for a in image if code <= a < code + 0x10000)
            # The program's instructions, decoded in order from CODE.
            starts = set()
            a = code
            while a <= end:
                starts.add(a)
                a += hazards.decode(image.get(a, 0)).words
            trace = subprocess.run(
                [EMU, "-t", "-n", str(args.steps), "--no-cycle-counter", *opts, binfile],
                capture_output=True, stdin=subprocess.DEVNULL,
            ).stdout.decode(errors="replace").splitlines()
            ran: set[int] = set()
            counts: collections.Counter[str] = collections.Counter()
            for line in trace:
                m = re.match(r"([0-9a-f]{8}) [0-9a-f]{8}", line)
                if m:
                    a = int(m.group(1), 16)
                    if code <= a <= end:
                        counts["program"] += 1
                        ran.add(a)
                    elif routines is not None and routines <= a < routines + 0x1000:
                        counts["routines"] += 1
                    else:
                        counts["elsewhere"] += 1
                elif line.startswith(("NMI ", "IRQ ")):
                    counts["interrupts"] += 1
            # The requests raised before the run ended: before its last step.
            m = re.search(r"after (\d+) step", "\n".join(trace))
            last = int(m.group(1)) if m else args.steps
            n_req = sum(int(o.split(":")[0]) < last for o in opts[1::2])
            ending = next((x for x in trace if x.startswith(("Halted", "Stopped"))), "?")
            ending = re.sub(r" after.*", "", ending)
            where.update(counts)
            ends[ending] += 1
            requested += n_req
            taken += counts["interrupts"]
            covered += len(ran & starts)
            size += len(starts)
            lines += trace
            if args.verbose:
                print(f"seed {seed}: {dict(counts)}, {len(ran & starts)} of {len(starts)} "
                      f"instructions ran, {n_req} requests, {ending}")

    steps = sum(where[k] for k in ("program", "routines", "elsewhere"))
    print(f"seeds {args.first} to {args.last}, {steps} steps")
    for k in ("program", "routines", "elsewhere"):
        print(f"  steps in {k:10s} {where[k]:7d} {100 * where[k] / steps:5.1f}%")
    print(f"  program instructions that ran: {100 * covered / size:.1f}%")
    print(f"  interrupt requests taken: {taken} of the {requested} raised before the run ended")
    for ending, n in ends.most_common():
        print(f"  {n:3d} runs: {ending}")
    prof = hazards.profile(lines)
    print(f"  hazards, in % of {prof.instructions} instructions   random  bench.c  hand.nasm")
    for label, bench in SHOWN.items():
        share = 100 * prof.counts[label] / prof.instructions
        b, h = bench.split()
        print(f"    {label:58s} {share:5.1f} {b:>7s} {h:>9s}")


if __name__ == "__main__":
    main()
