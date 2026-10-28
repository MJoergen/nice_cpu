#!/usr/bin/env python3
"""Runs every program in some directories on the core and on the emulator.

Usage: programs.py [options] DIR...

With --shard I/N it runs only the Ith share of N, as one of N jobs. The
shares have nearly equal steps on the emulator. "programs.py --test" checks
how they are made.

Step 7 of the test order in MICROARCH.md §9: the runtime's and the
translator's test programs, which "make test KEEP=DIR" in runtime/ and
"test/run.py --keep DIR" in translator/ leave in DIR, and the random
modules that "test/fuzz.py --keep DIR" leaves. Each DIR/X.bin runs
on the core in tb_core and on the emulator, with DIR/X.input as the
console input if it exists, and with no input otherwise. The trace, the
output, and the exit status of the two must be the same, as in the
makefile's other runs.

The runtime's clock reads the cycle counter, where the core counts cycles
and the emulator steps (SYSTEM.md §3), so its two words are memory on both
sides: G_CYCLE_COUNTER=false and --no-cycle-counter.

The runs go in parallel, the longest first, as test/core_runs.py
describes. The VHDL must be analyzed in BUILD already.
"""

import argparse
import concurrent.futures
import os
import sys

from core_runs import DEFAULT_BUILD, DEFAULT_CORE, DEFAULT_EMU, Core, add_sim_args, difference, run_emulator


def emulate(args: argparse.Namespace, binfile: str) -> str:
    """The emulator's trace, output, and exit status of the program."""
    infile = binfile[: -len(".bin")] + ".input"
    opts = ["--no-cycle-counter", *(["--input", infile] if os.path.exists(infile) else [])]
    return run_emulator(args.emu, binfile, opts)


def steps(args: argparse.Namespace, binfile: str) -> int:
    """The steps the emulator takes, the lines of its trace. The trace of the
    longest program is hundreds of megabytes, so it is not kept."""
    return emulate(args, binfile).count("\n")


def check(args: argparse.Namespace, core: Core, binfile: str, seed: int) -> str | None:
    """Returns None if the run passes, or what went wrong."""
    name = os.path.basename(binfile)
    expected = emulate(args, binfile)
    infile = binfile[: -len(".bin")] + ".input"
    generics = ["-gG_CYCLE_COUNTER=false", f"-gG_STALL={args.stall}", f"-gG_SEED={seed}"]
    if os.path.exists(infile):
        generics.append("-gG_INPUT_FILE=" + os.path.abspath(infile))
    diff = difference(expected, core.run(binfile, generics))
    return None if diff is None else f"{name}: {diff}"


def split(weights: dict[str, int], count: int) -> list[list[str]]:
    """The programs in COUNT shares of nearly equal total weight: the
    heaviest first, each into the share with the least so far."""
    shares: list[list[str]] = [[] for _ in range(count)]
    load = [0] * count
    for name in sorted(weights, key=lambda n: (-weights[n], n)):
        i = load.index(min(load))
        shares[i].append(name)
        load[i] += weights[name]
    return shares


def self_test() -> None:
    """The shares hold every program once, and balance as well as they can:
    a program with most of the steps has a share of its own."""
    weight = {f"p{i}": w for i, w in enumerate([1000, 40, 35, 30, 25, 20, 15, 10, 5, 5, 3, 2])}
    for count in (1, 2, 3, 5):
        shares = split(weight, count)
        names = sorted(n for share in shares for n in share)
        assert names == sorted(weight), (count, shares)
    assert split(weight, 3)[0] == ["p0"], split(weight, 3)
    loads = sorted(sum(weight[n] for n in share) for share in split(weight, 3))
    assert loads[1] - loads[0] <= 40 and loads[2] == 1000, loads
    assert split({"a": 5, "b": 5}, 4) == [["a"], ["b"], [], []]
    print("PASS programs.py --test")


def main() -> None:
    if sys.argv[1:] == ["--test"]:
        self_test()
        return
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("dirs", nargs="+", metavar="DIR")
    p.add_argument("--stall", type=int, default=0, help="G_STALL of the memory, in percent")
    p.add_argument("--shard", default="1/1", metavar="I/N",
                   help="run the Ith of N shares of nearly equal steps (default 1/1)")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    p.add_argument("--core", default=DEFAULT_CORE, help="G_CORE of tb_core (default pipeline)")
    p.add_argument("--build", default=DEFAULT_BUILD)
    p.add_argument("--emu", default=DEFAULT_EMU)
    add_sim_args(p)
    args = p.parse_args()

    programs = [os.path.join(d, f) for d in args.dirs for f in os.listdir(d) if f.endswith(".bin")]
    if not programs:
        sys.exit("programs: no .bin files")
    try:
        index, count = (int(x) for x in args.shard.split("/"))
        if not 1 <= index <= count:
            raise ValueError
    except ValueError:
        sys.exit(f"programs: --shard wants I/N with 1 <= I <= N, not {args.shard}")
    programs.sort()
    # The emulator runs every program first, in every shard: it takes
    # seconds, and its steps are what the core's time follows. The shares
    # are of nearly equal total steps. The longest program, libc_mchess,
    # has most of them, so it gets a share of its own when it can, and the
    # others share the rest.
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        weight = dict(zip(programs, pool.map(lambda f: steps(args, f), programs)))
    shares = split(weight, count)
    # Within the share, the longest first, so that no long run starts last.
    programs = sorted(shares[index - 1], key=lambda f: (-weight[f], f))

    core = Core(args, args.build, "programs", args.core)
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda j: check(args, core, j[1], j[0] + 1), enumerate(programs)))
    core.clean()

    failures = [r for r in results if r is not None]
    for r in failures:
        print("FAIL " + r)
    shard = "" if args.shard == "1/1" else f" shard {args.shard}"
    print(f"{'FAIL' if failures else 'PASS'} programs {args.core}{shard}: {len(programs) - len(failures)} of "
          f"{len(programs)} in {', '.join(args.dirs)}")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
