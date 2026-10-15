#!/usr/bin/env python3
"""Runs every program in some directories on the core and on the emulator.

Usage: programs.py [options] DIR...

Step 6 of the test order in MICROARCH.md §9: the runtime's and the
translator's test programs, which "make test KEEP=DIR" in runtime/ and
"test/run.py --keep DIR" in translator/ leave in DIR. Each DIR/X.bin runs
on the core in tb_multicycle and on the emulator, with DIR/X.input as the
console input if it exists, and with no input otherwise. The trace, the
output, and the exit status of the two must be the same, as in the
makefile's other runs.

The runtime's clock reads the cycle counter, where the core counts cycles
and the emulator steps (ISA.md §8.5), so its two words are memory on both
sides: G_CYCLE_COUNTER=false and --no-cycle-counter.

The runs go in parallel, the longest first, as test/core_runs.py
describes. The VHDL must be analysed in BUILD already.
"""

import argparse
import concurrent.futures
import os
import sys

from core_runs import DEFAULT_BUILD, DEFAULT_EMU, Core, difference, run_emulator


def check(args: argparse.Namespace, core: Core, binfile: str, seed: int) -> str | None:
    """Returns None if the run passes, or what went wrong."""
    name = os.path.basename(binfile)
    infile = binfile[: -len(".bin")] + ".input"
    has_input = os.path.exists(infile)
    expected = run_emulator(
        args.emu, binfile, ["--no-cycle-counter", *(["--input", infile] if has_input else [])]
    )
    generics = ["-gG_CYCLE_COUNTER=false", f"-gG_STALL={args.stall}", f"-gG_SEED={seed}"]
    if has_input:
        generics.append("-gG_INPUT_FILE=" + os.path.abspath(infile))
    diff = difference(expected, core.run(binfile, generics))
    return None if diff is None else f"{name}: {diff}"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("dirs", nargs="+", metavar="DIR")
    p.add_argument("--stall", type=int, default=0, help="G_STALL of the memory, in percent")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    p.add_argument("--build", default=DEFAULT_BUILD)
    p.add_argument("--emu", default=DEFAULT_EMU)
    p.add_argument("--ghdl", default=os.environ.get("GHDL", "ghdl"))
    args = p.parse_args()

    programs = [os.path.join(d, f) for d in args.dirs for f in os.listdir(d) if f.endswith(".bin")]
    if not programs:
        sys.exit("programs: no .bin files")
    # The size of a program is a guess at its length, and the longest go
    # first, so that no long run starts last.
    programs.sort(key=lambda f: (-os.path.getsize(f), f))

    core = Core(args.ghdl, args.build, "programs")
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda j: check(args, core, j[1], j[0] + 1), enumerate(programs)))
    core.clean()

    failures = [r for r in results if r is not None]
    for r in failures:
        print("FAIL " + r)
    print(f"{'FAIL' if failures else 'PASS'} programs: {len(programs) - len(failures)} of "
          f"{len(programs)} in {', '.join(args.dirs)}")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
