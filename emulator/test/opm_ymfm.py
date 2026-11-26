#!/usr/bin/env python3
"""Check the model of the FM synthesizer, opm_model.py, against ymfm.

Builds opm_ymfm.cpp against the ymfm sources in --ymfm, with the one
change its comment names, then runs random logs of writes from
opm_vectors.py, and any logs given, through both, and compares every
sample. Needs a C++ compiler, CXX (default c++).
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

import opm_model
import opm_vectors

HERE = os.path.dirname(os.path.abspath(__file__))

# The line of ymfm's engine that leaves out the channels whose operators
# are all quiet in their release, which the chip computes like the others.
SKIP_LINE = "chanmask &= m_active_channels;"


def build(ymfm: str, out: str) -> str:
    src = os.path.join(ymfm, "src")
    for name in ("ymfm.h", "ymfm_fm.h", "ymfm_opm.h", "ymfm_opm.cpp"):
        shutil.copy(os.path.join(src, name), out)
    with open(os.path.join(src, "ymfm_fm.ipp")) as f:
        text = f.read()
    if text.count(SKIP_LINE) != 1:
        raise SystemExit(f"opm_ymfm: {SKIP_LINE!r} is not once in ymfm_fm.ipp")
    with open(os.path.join(out, "ymfm_fm.ipp"), "w") as f:
        f.write(text.replace(SKIP_LINE, "// every channel, as the chip computes"))
    exe = os.path.join(out, "opm_ymfm")
    cxx = os.environ.get("CXX", "c++")
    subprocess.run(
        [cxx, "-O2", "-std=c++14", "-I", out, "-o", exe, os.path.join(HERE, "opm_ymfm.cpp"), os.path.join(out, "ymfm_opm.cpp")],
        check=True,
    )
    return exe


def compare(exe: str, log: str, name: str) -> bool:
    got = subprocess.run([exe, log], check=True, capture_output=True, text=True).stdout.split("\n")
    with open(log) as f:
        writes, count = opm_model.read_log(f.readlines())
    for n, (left, right) in enumerate(opm_model.run(writes, count)):
        if got[n] != f"{left} {right}":
            print(f"FAIL {name}: sample {n} is {left} {right} in the model, {got[n]} in ymfm")
            return False
    print(f"PASS {name}: {count} samples")
    return True


def main() -> int:
    p = argparse.ArgumentParser(description="Compare the model with ymfm on logs of writes.")
    p.add_argument("--ymfm", required=True, help="a checkout of ymfm")
    p.add_argument("--seeds", type=int, default=20, help="the number of random logs, from seed 1")
    p.add_argument("--count", type=int, default=30000, help="the samples of each random log")
    p.add_argument("logs", nargs="*", help="more logs of writes")
    a = p.parse_args()
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        exe = build(a.ymfm, tmp)
        for seed in range(1, a.seeds + 1):
            path = os.path.join(tmp, f"seed{seed}.log")
            with open(path, "w") as f:
                f.write(opm_vectors.write_log(opm_vectors.random_log(seed, a.count), a.count))
            ok = compare(exe, path, f"seed {seed}") and ok
        for log in a.logs:
            ok = compare(exe, log, log) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
