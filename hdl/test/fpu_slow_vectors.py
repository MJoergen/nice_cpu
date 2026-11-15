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
- SIN, COS, and TAN, which take the most rounds of the reduction near a
  multiple of pi/2. The scan has them of the values next to k pi/2 for
  the k of HARD_K, of 1 to 9, and of 40 random k, and of 4 random values
  in each binade from 2^-30 to 2^20. In the scan of 2026-11-15 the
  slowest SIN took 1561 cycles, COS 1576, and TAN 2079.

A change to DIGITS or SCALE10 in src/fpu.vhd may make other values the
slowest, so such a change runs the scan again."""

from __future__ import annotations

import argparse
import os
import random
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


# The k up to 2^20 for which the binary64 value nearest k pi/2 is nearest
# to it, within 2e-5 of its ulp, from a search of every k: SIN, COS, and
# TAN of them reduce in three rounds of musl's __rem_pio2.
HARD_K = [
    818204, 409102, 204551, 789615, 554999, 526410, 263205, 846793, 761026, 380513, 1024231,
    875382, 437691, 643718, 321859, 732437, 583588, 291794, 145897, 995642, 497821, 903971,
    703848, 351924, 175962, 87981, 967053, 932560, 466280, 233140, 116570, 58285, 615129,
    669355, 675259, 612177, 938464, 469232, 234616, 117308,
]

# pi to 60 digits.
PI = Fraction(314159265358979323846264338327950288419716939937510582097494, 10**59)

# The slowest function of the scan: the value and the function.
SLOW_FUNCTIONS = [
    (0x4116FF6B1357E177, "SIN"),
    (0xC00921FB54442D18, "COS"),
    (0x4107B5820700A668, "TAN"),
    (0xC133287FA423FC65, "TAN"),
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
    # The functions near a multiple of pi/2, where the reduction takes
    # more rounds, and in every binade up to the bound of §11.3.
    rnd = random.Random(1)
    values = []
    for k in list(range(1, 10)) + HARD_K + [rnd.randrange(1, 2**20) for _ in range(40)]:
        v = F64.round(k * PI / 2)[0]
        values += [v - 2, v - 1, v, v + 1, v + 2]
    for e in range(-30, 21):
        values += [F64.round(Fraction(2) ** e * (1 + Fraction(rnd.random())))[0] for _ in range(4)]
    for v in values:
        for name in ("SIN", "COS", "TAN"):
            g.cmd([v], name)
            g.cmd([v | 1 << 63], name)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--scan", action="store_true", help="write the lines of the scan instead")
    args = p.parse_args()

    g = Generator()
    if args.scan:
        scan(g)
    else:
        g.comment("The slowest DIGITS, SCALE10, FMOD, and functions, from fpu_slow_vectors.py")
        for a, n in SLOW_DIGITS:
            g.cmd([a], f"DIGITS {n}")
        for k in (255, 511, 639):
            g.cmd([ten(-300), F64.from_int(k)], "SCALE10")
            g.cmd([ten(300), F64.from_int(-k)], "SCALE10")
        g.cmd([0x7FEFFFFFFFFFFFFF, 1], "FMOD")
        g.cmd([0x7FEFFFFFFFFFFFFF, 0x0010000000000000], "FMOD")
        for v, name in SLOW_FUNCTIONS:
            g.cmd([v], name)
    print("\n".join(g.lines))


if __name__ == "__main__":
    main()
