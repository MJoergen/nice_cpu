#!/usr/bin/env python3
"""Runs a program on the core with an interrupt request before each step.

Usage: irq_sweep.py [options] PROGRAM.bin

Step 5 of the test order in MICROARCH.md §9. The program runs once on the
emulator, which gives its number of steps N. Then, for each kind of request
(NMI and IRQ) and each step S from 0 to N - 1, it runs once on the core in
tb_multicycle and once on the emulator, with the one request "--nmi S:VEC"
or "--irq S:VEC". The trace, the output, and the exit status of the two
must be the same, as in the makefile's other runs. Each run on the
emulator must also take the request, so the trace has no "Pending:" line,
and with --self-check, end as test/hazard.nasm does when it passes: with
R12 = 0 and exit status 0.

The runs are independent, so they go in parallel, each worker in its own
directory under BUILD/sweep, because GHDL's LLVM and GCC backends write an
executable where they run. The VHDL must be analysed in BUILD already.

For the multi-cycle core the request step decides where the request is
taken. For the pipelined core it does not (MICROARCH.md §9), and this
script will need the comparison that reads where it was taken.
"""

import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BUILD = os.path.join(HERE, "..", "build")
DEFAULT_EMU = os.path.join(HERE, "..", "..", "emulator", "zig-out", "bin", "niceemu")


def run_emulator(emu: str, binfile: str, opts: list[str]) -> str:
    r = subprocess.run(
        [emu, "-t", *opts, binfile], stdin=subprocess.DEVNULL, capture_output=True, text=True
    )
    return r.stdout + f"exit {r.returncode}\n"


class Workers:
    """One directory for each worker thread."""

    def __init__(self, build: str) -> None:
        self.root = os.path.join(os.path.abspath(build), "sweep")
        self.local = threading.local()
        self.count = 0
        self.lock = threading.Lock()

    def directory(self) -> str:
        d: str | None = getattr(self.local, "dir", None)
        if d is None:
            with self.lock:
                self.count += 1
                d = os.path.join(self.root, str(self.count))
            os.makedirs(d, exist_ok=True)
            self.local.dir = d
        return d


def run_core(args: argparse.Namespace, workers: Workers, opts: list[str], seed: int) -> str:
    d = workers.directory()
    trace = os.path.join(d, "core.out")
    cmd = [
        args.ghdl, "--elab-run", "--std=08", "--workdir=" + os.path.abspath(args.build),
        "tb_multicycle", "-gG_BIN_FILE=" + os.path.abspath(args.program),
        "-gG_TRACE_FILE=" + trace, "-gG_INTERRUPTS=" + " ".join(opts),
        f"-gG_STALL={args.stall}", f"-gG_SEED={seed}",
    ]
    if os.path.exists(trace):
        os.remove(trace)
    r = subprocess.run(cmd, cwd=d, stdin=subprocess.DEVNULL, capture_output=True, text=True)
    if not os.path.exists(trace):
        return f"no trace from GHDL, exit {r.returncode}\n" + r.stdout + r.stderr
    with open(trace) as f:
        out = f.read()
    return out + f"exit {r.returncode}\n" + ("" if r.returncode in (0, 2, 3) else r.stdout + r.stderr)


def check(args: argparse.Namespace, workers: Workers, kind: str, vec: int, step: int) -> str | None:
    """Returns None if the run passes, or what went wrong."""
    opts = [f"--{kind}", f"{step}:{vec}"]
    name = f"--{kind} {step}:{vec}"
    expected = run_emulator(args.emu, args.program, opts)
    if "Pending:" in expected:
        return f"{name}: the emulator never took the request"
    if args.self_check and not (
        re.search(r"^R12 00000000", expected, re.M) and expected.endswith("exit 0\n")
    ):
        return f"{name}: the program's own checks failed on the emulator\n" + expected[-400:]
    got = run_core(args, workers, opts, step + 1)
    if got != expected:
        e, g = expected.splitlines(), got.splitlines()
        i = next((i for i, (a, b) in enumerate(zip(e, g)) if a != b), min(len(e), len(g)))
        return f"{name}: the traces differ at line {i + 1}\n" + "\n".join(
            [f"  emulator: {line}" for line in e[i : i + 3]] + [f"  core:     {line}" for line in g[i : i + 3]]
        )
    return None


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("program")
    p.add_argument("--nmi", type=lambda s: int(s, 0), default=8, help="the NMI vector (default 8)")
    p.add_argument("--irq", type=lambda s: int(s, 0), default=9, help="the IRQ vector (default 9)")
    p.add_argument("--stall", type=int, default=0, help="G_STALL of the memory, in percent")
    p.add_argument("--self-check", action="store_true", help="every run must pass as hazard.nasm does")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    p.add_argument("--build", default=DEFAULT_BUILD)
    p.add_argument("--emu", default=DEFAULT_EMU)
    p.add_argument("--ghdl", default=os.environ.get("GHDL", "ghdl"))
    args = p.parse_args()

    plain = run_emulator(args.emu, args.program, [])
    m = re.search(r"after (\d+) steps", plain)
    if not m:
        sys.exit(f"irq_sweep: the program does not halt on the emulator:\n{plain[-400:]}")
    steps = int(m.group(1))

    workers = Workers(args.build)
    jobs = [(kind, vec, s) for kind, vec in (("nmi", args.nmi), ("irq", args.irq)) for s in range(steps)]
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda j: check(args, workers, *j), jobs))
    shutil.rmtree(workers.root, ignore_errors=True)

    failures = [r for r in results if r is not None]
    for r in failures[:10]:
        print(r)
    name = os.path.basename(args.program)
    if failures:
        print(f"FAIL irq_sweep {name}: {len(failures)} of {len(jobs)} runs")
        sys.exit(1)
    print(f"PASS irq_sweep {name}: {len(jobs)} runs")


if __name__ == "__main__":
    main()
