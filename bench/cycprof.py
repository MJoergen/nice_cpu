#!/usr/bin/env python3
"""The cycle estimate of pipecycles.py, line by line of a program's source.

    ./cycprof.py [-o OUT] FULL.nasm FILE.bin    profile a program
    ./cycprof.py --test                         check the charging on a snippet

FULL.nasm is the assembly source of the whole program, and FILE.bin the
file assembled from it, such as build/bench.full.nasm and build/bench.bin.
The program runs on the emulator with --trace (hazards.py says which
emulator), the model of pipecycles.py runs on the trace, and the model's
cycles are charged to the source line of the instruction in whose WRITE
they appear. So the cycles of a taken jump land on the instruction at its
target, where the pipeline waits for it, and those of a math unit wait on
the read of the result.

The output, OUT or FILE.cyc.txt next to FILE.bin, is the source with two
columns in front of each line, how often its instruction ran and the
cycles it cost above one per run, and the causes of those cycles after the
line, as pipecycles.py names them, with their cycles. The summary of
pipecycles.py is printed.
"""

import argparse
import collections
import os
import sys
from typing import Dict, List, Tuple

import hazards
import pipecycles

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "assembler"))
import niceasm  # noqa: E402

Costs = Dict[int, "collections.Counter[str]"]


class Profile(pipecycles.Model):
    """The model, counting the runs and the charged cycles of each address."""

    def __init__(self, mem: Dict[int, int]) -> None:
        super().__init__(mem)
        self.runs: "collections.Counter[int]" = collections.Counter()
        self.costs: Costs = collections.defaultdict(collections.Counter)

    def step(self, pc: int, iw: int, skipped: bool, changes: List[str]) -> None:
        gaps, multi = dict(self.gaps), self.multi
        super().step(pc, iw, skipped, changes)
        self.runs[pc] += 1
        for cause, v in self.gaps.items():
            if v != gaps[cause]:
                self.costs[pc][cause] += v - gaps[cause]
        if self.multi != multi:
            self.costs[pc]["multi"] += self.multi - multi


def assemble(lines: List[str], name: str) -> Dict[int, int]:
    """The source line of each address of the program."""
    a = niceasm.Assembler()
    errors = a.run(lines, name)
    if errors:
        sys.exit("\n".join(errors))
    return {addr: line for addr, (_, line) in a.words.items()}


def profile(lines: List[str], binpath: str, name: str
            ) -> Tuple[Profile, "collections.Counter[int]", Costs]:
    """Runs the model on the program and charges its cycles to lines:
    the model, the runs of each line, and the costs of each line."""
    line_of = assemble(lines, name)
    m = Profile(pipecycles.load_bin(binpath))
    pipecycles.run_model(m, hazards.trace_lines(binpath))
    runs: "collections.Counter[int]" = collections.Counter()
    costs: Costs = collections.defaultdict(collections.Counter)
    for pc, n in m.runs.items():
        if pc in line_of:
            runs[line_of[pc]] += n
            costs[line_of[pc]].update(m.costs[pc])
    return m, runs, costs


def listing(lines: List[str], runs: "collections.Counter[int]", costs: Costs) -> List[str]:
    out = []
    for i, text in enumerate(lines, 1):
        c = costs.get(i)
        causes = " ".join(f"{k}{v}" for k, v in sorted(c.items(), key=lambda kv: -kv[1])) if c else ""
        extra = sum(c.values()) if c else ""
        out.append(f"{runs.get(i, ''):>8} {extra:>7} {text.rstrip():60s} {causes}".rstrip())
    return out


# --test: a counted loop, with the charges worked out from the model as
# pipecycles.py's test of the same loop does. The first instruction gets
# the 6 cycles of the pipeline start. Each of the 9 taken jumps costs 7
# cycles, charged to the SUB at its target, which waits for the refetch.
# The jump itself and the HALT after its last, untaken, run cost nothing.
TEST = """        MOVE R1, 10
loop    SUB[M] R1, R1, 1
        ?!Z MOVE R15, loop
        HALT
"""
TEST_LINES = [(1, 6, {"startup": 6}), (10, 63, {"flush": 63}), (10, 0, {}), (1, 0, {})]


def test() -> None:
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        nasm, binp = os.path.join(tmp, "t.nasm"), os.path.join(tmp, "t.bin")
        with open(nasm, "w") as f:
            f.write(TEST)
        subprocess.run([sys.executable, os.path.join(HERE, "..", "assembler", "niceasm.py"),
                        "-o", binp, nasm], check=True, stdout=subprocess.DEVNULL)
        _, runs, costs = profile(TEST.splitlines(keepends=True), binp, nasm)
    bad = 0
    for i, (n, extra, causes) in enumerate(TEST_LINES, 1):
        have = (runs.get(i, 0), sum(costs[i].values()) if i in costs else 0,
                {k: v for k, v in costs[i].items() if v} if i in costs else {})
        ok = have == (n, extra, causes)
        bad += not ok
        print(f"{'PASS' if ok else 'FAIL'} line {i}: {have[0]} runs, {have[1]} extra cycles"
              + ("" if ok else f" {have[2]}, expected {n}, {extra}, {causes}"))
    if bad:
        sys.exit(f"FAIL cycprof.py --test: {bad} of {len(TEST_LINES)} lines")
    print("PASS cycprof.py --test")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="*", metavar="FILE", help="FULL.nasm and FILE.bin")
    ap.add_argument("-o", dest="out", help="the listing (FILE.cyc.txt)")
    ap.add_argument("--test", action="store_true")
    a = ap.parse_args()
    if a.test:
        test()
        return
    if len(a.files) != 2:
        ap.error("needs FULL.nasm and FILE.bin")
    src, binpath = a.files
    out = a.out or os.path.splitext(binpath)[0] + ".cyc.txt"
    with open(src) as f:
        lines = f.readlines()
    m, runs, costs = profile(lines, binpath, src)
    with open(out, "w") as f:
        f.write("\n".join(listing(lines, runs, costs)) + "\n")
    print(pipecycles.report(os.path.basename(binpath), m))
    print(f"listing: {out}")


if __name__ == "__main__":
    main()
