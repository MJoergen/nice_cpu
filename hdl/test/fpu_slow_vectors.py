#!/usr/bin/env python3
"""Vectors of the FPU's slowest commands, for tb_fpu's bounds on cycles.

Usage: fpu_slow_vectors.py [--scan]

Writes to standard output lines of the format of
emulator/test/fpu_vectors.py, from its model, so that the results are
checked too, for the commands whose time in src/fpu.vhd depends most on
the operands:

- DIGITS n of the values below, which took longest in a scan: tb_fpu
  with G_SLOW, on the lines that --scan writes, which are DIGITS 1 to 15
  of the values next to each power of ten, and SCALE10 by every count
  from -660 to 660. DIGITS lowers its exponent until the digits come
  out, and each round runs SCALE10, whose time grows with the bits of
  its count. In the scan of 2026-11-14 the slowest DIGITS took 3363
  cycles from its request to the ACK of the read of STATUS after it,
  and the slowest SCALE10, of 10^300 by -511, 1235.
- SCALE10 by counts with many bits set, 255, 511, and 639, both ways.
- FMOD with the largest difference of the exponents.

A change to DIGITS or SCALE10 in src/fpu.vhd may make other values the
slowest, so such a change runs the scan again."""

from __future__ import annotations

import argparse
import os
import sys
from fractions import Fraction

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "emulator", "test"))

from fpu_model import F64  # noqa: E402
from fpu_vectors import Generator  # noqa: E402

# The slowest of the scan: the value and n.
SLOW_DIGITS = [
    (0x7580A6650B926D66, 5),
    (0x754AA3D4DF50AF0C, 4),
    (0x7620427EAD4CFED7, 8),
    (0x75EA03FDE214CAF1, 7),
    (0x7728CF768B2F9C5A, 13),
    (0x74AB4781EAD1989D, 1),
    (0x768967E5EEC84E30, 10),
    (0x7580A6650B926D68, 5),
    (0x76BFC1DF6A7A61BB, 11),
    (0x754AA3D4DF50AF0A, 4),
    (0x74E10CB132C2FF63, 2),
    (0x775F03542DFB8370, 14),
]


def ten(p: int) -> int:
    return F64.round(Fraction(10) ** p)[0]


def scan(g: Generator) -> None:
    for p in range(-324, 309):
        v = ten(p)
        for a in (v - 1, v, v + 1):
            if 0 < a < 0x7FF0000000000000:
                for n in range(1, 16):
                    g.cmd([a], f"DIGITS {n}")
    for k in range(-660, 661):
        for y in (ten(300) if k < 0 else ten(-300), 0x3FF8000000000000):
            g.cmd([y, F64.from_int(k)], "SCALE10")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--scan", action="store_true", help="write the lines of the scan instead")
    args = p.parse_args()

    g = Generator()
    if args.scan:
        scan(g)
    else:
        g.comment("The slowest DIGITS, SCALE10, and FMOD, from fpu_slow_vectors.py")
        for a, n in SLOW_DIGITS:
            g.cmd([a], f"DIGITS {n}")
        for k in (255, 511, 639):
            g.cmd([ten(-300), F64.from_int(k)], "SCALE10")
            g.cmd([ten(300), F64.from_int(-k)], "SCALE10")
        g.cmd([0x7FEFFFFFFFFFFFFF, 1], "FMOD")
        g.cmd([0x7FEFFFFFFFFFFFFF, 0x0010000000000000], "FMOD")
    print("\n".join(g.lines))


if __name__ == "__main__":
    main()
