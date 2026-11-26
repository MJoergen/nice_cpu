#!/usr/bin/env python3
"""How well the random programs of random_prog.py test the core.

Usage: random_stats.py [options] FIRST LAST
       random_stats.py --test

Runs the programs of seeds FIRST to LAST on the emulator, as the makefile
does, and reports what the runs spend their steps on:
- where the steps run: the program, or elsewhere, such as the words below
  DATA or empty memory, which runs as NOPs;
- how many of the program's instructions run at least once;
- how the runs end;
- the hazards of MICROARCH.md §5, as bench/hazards.py counts them, over
  all the runs, beside the shares of the benchmark, which it reads from
  the table of MICROARCH.md §5.6.

With --test, it checks that each hazard it shows is a label of
bench/hazards.py and a row of that table.
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

MICROARCH = os.path.join(HERE, "..", "..", "doc", "MICROARCH.md")

# The hazards to show, by their labels in bench/hazards.py, with the rows of
# the table of MICROARCH.md §5.6 that hold their shares in bench.c through
# nicewasm and in hand.nasm.
SHOWN = {
    "conditional": "Conditional",
    "data read": "Data read",
    "store": "Store",
    "jump: writes R15, or control": "Jump: writes R15, or a control instruction",
    "reads a register the previous instruction writes": "Reads a register the previous instruction writes",
    "reads a register written two back, not one": "Reads a register written two back, not one",
    "conditional, SR written by the previous instruction": "Conditional, SR written by the previous instruction",
    "conditional with a data read, SR written by the previous":
        "Conditional with a data read, SR written by the previous",
    "data read after a store": "Data read after a store",
    "data read after a conditional jump": "Data read after a conditional jump",
    "R14 read as an operand or base": "R14 read as an operand",
    "R15 as a pointer, or with a side effect": "R15 as a pointer, or with a side effect",
}


def shares(path: str = MICROARCH) -> dict[str, tuple[str, str]]:
    """The shares of the hazards of SHOWN in the two benchmarks, without
    their % signs, from the table of MICROARCH.md §5.6."""
    with open(path) as f:
        text = f.read()
    start = text.index("### 5.6 ")
    section = text[start:text.index("\n#", start + 1)]
    rows = {}
    for line in section.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.startswith("|") and len(cells) == 3:
            rows[cells[0]] = (cells[1].rstrip("%"), cells[2].rstrip("%"))
    missing = [row for row in SHOWN.values() if row not in rows]
    if missing:
        sys.exit(f"random_stats.py: MICROARCH.md §5.6 has no row {', '.join(map(repr, missing))}")
    return {label: rows[row] for label, row in SHOWN.items()}


def test() -> None:
    """Checks that every hazard of SHOWN is a label of hazards.py and a row
    of MICROARCH.md §5.6 with two shares."""
    spec = importlib.util.spec_from_file_location("hazards", HAZARDS)
    assert spec is not None and spec.loader is not None
    hazards = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hazards)
    unknown = [label for label in SHOWN if label not in hazards.LABELS]
    if unknown:
        sys.exit(f"FAIL random_stats.py: not labels of hazards.py: {', '.join(map(repr, unknown))}")
    for label, (b, h) in shares().items():
        for share in (b, h):
            try:
                float(share)
            except ValueError:
                sys.exit(f"FAIL random_stats.py: share {share!r} of {label!r} in MICROARCH.md §5.6")
    print("PASS random_stats.py: the hazards it shows are rows of MICROARCH.md §5.6")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("first", type=int, nargs="?")
    p.add_argument("last", type=int, nargs="?")
    p.add_argument("--steps", type=int, default=3000, help="the step limit (default 3000)")
    p.add_argument("--generator", default=os.path.join(HERE, "random_prog.py"))
    p.add_argument("-v", "--verbose", action="store_true", help="a line for each seed")
    p.add_argument("--test", action="store_true", help="check that the hazards shown are rows of MICROARCH.md §5.6")
    args = p.parse_args()
    if args.test:
        test()
        return
    if args.first is None or args.last is None:
        p.error("FIRST and LAST are needed")
    bench = shares()

    spec = importlib.util.spec_from_file_location("hazards", HAZARDS)
    assert spec is not None and spec.loader is not None
    hazards = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hazards)
    gen = importlib.util.spec_from_file_location("gen", args.generator)
    assert gen is not None and gen.loader is not None
    generator = importlib.util.module_from_spec(gen)
    gen.loader.exec_module(generator)
    code = generator.CODE

    where: collections.Counter[str] = collections.Counter()
    ends: collections.Counter[str] = collections.Counter()
    covered = size = 0
    lines: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        binfile = os.path.join(tmp, "r.bin")
        for seed in range(args.first, args.last + 1):
            subprocess.run([sys.executable, args.generator, str(seed), binfile], check=True)
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
                [EMU, "-t", "-n", str(args.steps), "--no-cycle-counter", "--no-font", "--no-screen-mode", "--no-fpu", binfile],
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
                    else:
                        counts["elsewhere"] += 1
            ending = next((x for x in trace if x.startswith(("Halted", "Stopped"))), "?")
            ending = re.sub(r" after.*", "", ending)
            where.update(counts)
            ends[ending] += 1
            covered += len(ran & starts)
            size += len(starts)
            # The steps up to the end of the run, as hazards.profile stops
            # at the first Halted or Stopped line.
            stop = next((i for i, x in enumerate(trace) if x.startswith(("Halted", "Stopped"))), len(trace))
            lines += trace[:stop]
            if args.verbose:
                print(f"seed {seed}: {dict(counts)}, {len(ran & starts)} of {len(starts)} "
                      f"instructions ran, {ending}")

    steps = sum(where[k] for k in ("program", "elsewhere"))
    print(f"seeds {args.first} to {args.last}, {steps} steps")
    for k in ("program", "elsewhere"):
        print(f"  steps in {k:10s} {where[k]:7d} {100 * where[k] / steps:5.1f}%")
    print(f"  program instructions that ran: {100 * covered / size:.1f}%")
    for ending, n in ends.most_common():
        print(f"  {n:3d} runs: {ending}")
    prof = hazards.profile(lines)
    print(f"  hazards, in % of {prof.instructions} instructions   random  bench.c  hand.nasm")
    for label, (b, h) in bench.items():
        share = 100 * prof.counts[label] / prof.instructions
        print(f"    {label:58s} {share:5.1f} {b:>7s} {h:>9s}")


if __name__ == "__main__":
    main()
