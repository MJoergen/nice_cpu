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
  slowest SIN took 1533 cycles, COS 1552, and TAN 2043.
- ASIN, ACOS, ATAN, and ATAN2, of 4 random values in each binade from
  2^-70 to 2^70 and of the values next to the bounds where their paths
  part. In the scan of 2026-11-15 the slowest ASIN took 1106 cycles,
  ACOS 954, ATAN 944, and ATAN2 1323.
- LN, LOG2, LOG10, and EXP, of 4 random values in every third binade,
  and for EXP of each binade from 2^-40 to 2^9 and 400 random values
  from -745 to 709, and of the values next to the bounds where their
  paths part. In the scan of 2026-11-15 the slowest LN took 922 cycles,
  LOG2 1144, LOG10 1214, and EXP 822.
- POW2, POW, and HYPOT, of random values and pairs over the whole range
  (scan_pow). In the scan of 2026-11-15 the slowest POW2 took 1053
  cycles, POW 3018, of a negative Y to a whole X, and HYPOT 542.

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
    (0xC137C1DC0A55002A, "SIN"),
    (0xC00921FB54442D18, "COS"),
    (0x400921FB54442D18, "COS"),
    (0x4107B5820700A668, "TAN"),
    (0xC133287FA423FC65, "TAN"),
    (0xBFEF3332FFFFFFFF, "ASIN"),
    (0xBFEFFFFFFFFFFFFF, "ACOS"),
    (0x3FEF3332FFFFFFFF, "ACOS"),
    (0x3FDF86339515FA52, "ATAN"),
    (0xBFE00375C03F6FEC, "ATAN"),
    (0x0B46A6213E555974, "LN"),
    (0x0000000000001F31, "LOG2"),
    (0x6546A161E061BBCA, "LN"),
    (0x07BF9A6A3B2A6245, "LOG2"),
    (0x15FF9D36E26866A7, "LOG10"),
    (0xC087491000000000, "EXP"),
    (0xC087491000000001, "EXP"),
    (0xC045770A3D70A3D7, "POW2"),
    (0xC04207CED916872B, "POW2"),
]

# The slowest functions of two operands of the scan: Y, X, and the function.
SLOW_PAIRS = [
    (0x3FDF86339515FA52, 0xBFF0000000000000, "ATAN2"),
    (0x3FE00375C03F6FEC, 0xBFF0000000000000, "ATAN2"),
    (0xB4662E58066BB43C, 0xC000000000000000, "POW"),
    (0xC5E92B7562233FCD, 0xC026000000000000, "POW"),
    (0x8000044EFFA30F84, 0x800002329496D03F, "HYPOT"),
    (0x80000085AE49137B, 0x8000007D44CBCA66, "HYPOT"),
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
    scan_inverse(g, rnd)
    scan_log(g, rnd)
    scan_pow(g, rnd)


def scan_pow(g: Generator, rnd: random.Random) -> None:
    """POW2, POW, and HYPOT: POW2 of 4 random values in each binade
    from 2^-40 to 2^10, and of 400 random values from -1075 to 1024;
    POW of random bases, near 1 too, of each sign, to random powers,
    whole ones too, and huge ones; HYPOT of pairs in every third binade,
    whose exponents are near or far apart. Each goes twice, as tb_fpu
    does not time every third line."""
    values = [F64.round(Fraction(2) ** e * (1 + Fraction(rnd.random())))[0] for e in range(-40, 11) for _ in range(4)]
    values += [F64.round(Fraction(rnd.randint(-1075000, 1024000), 1000))[0] for _ in range(400)]
    for v in values:
        for _ in range(2):
            g.cmd([v], "POW2")
            g.cmd([v ^ 1 << 63], "POW2")
    bases = [F64.round(Fraction(2) ** e * (1 + Fraction(rnd.random())))[0] for e in range(-1074, 1024, 7)]
    bases += [0x3FF0000000000000 + rnd.randint(-2**33, 2**33) for _ in range(100)]
    for i, b in enumerate(bases):
        for x in (F64.from_int(rnd.randint(-40, 40)), F64.round(Fraction(rnd.randint(-10**6, 10**6), 1000))[0],
                  F64.round(Fraction(2) ** rnd.randint(-60, 70) * (1 + Fraction(rnd.random())))[0]):
            for _ in range(2):
                g.cmd([b | (i & 1) << 63, x | (i >> 1 & 1) << 63], "POW")
    for e in range(-1074, 1024, 3):
        y = F64.round(Fraction(2) ** e * (1 + Fraction(rnd.random())))[0]
        for d in (0, 1, 30, 64, 65):
            ex = min(max(e - d, -1074), 1022)
            x = F64.round(Fraction(2) ** ex * (1 + Fraction(rnd.random())))[0]
            ops = [y | rnd.getrandbits(1) << 63, x | rnd.getrandbits(1) << 63]
            g.cmd(ops, "HYPOT")
            g.cmd(ops, "HYPOT")


def scan_log(g: Generator, rnd: random.Random) -> None:
    """LN, LOG2, LOG10, and EXP: 4 random values in each binade, of
    each sign, and the values next to the bounds where their paths
    part."""
    bounds = [0x3FF6147A, 0x3FF6B852, 0x3FE6B852, 0x3FF6A09C, 0x3FF6A09E, 0x3FE6A09C, 0x3FEFFFFE,
              0x3FF00001, 0x3FF00000, 0x00100000]
    values = [(h << 32) + i for h in bounds for i in (-1, 0, 1)]
    for e in range(-1074, 1024, 3):
        values += [F64.round(Fraction(2) ** e * (1 + Fraction(rnd.random())))[0] for _ in range(4)]
    # tb_fpu does not time every third line, so the order turns.
    names = ["LN", "LOG2", "LOG10"]
    for i, v in enumerate(values):
        for name in names[i % 3:] + names[:i % 3]:
            g.cmd([v], name)
            g.cmd([v ^ 1 << 63], name)
    bounds = [0x40862E42, 0x3FD62E42, 0x3FF0A2B2, 0x3E300000, 0x40874910, 0x40862000]
    values = [(h << 32) + i for h in bounds for i in (-1, 0, 1)]
    for e in range(-40, 10):
        values += [F64.round(Fraction(2) ** e * (1 + Fraction(rnd.random())))[0] for _ in range(4)]
    values += [F64.round(Fraction(rnd.randint(-745000, 709000), 1000))[0] for _ in range(400)]
    for v in values:
        g.cmd([v], "EXP")
        g.cmd([v ^ 1 << 63], "EXP")


def scan_inverse(g: Generator, rnd: random.Random) -> None:
    """ASIN, ACOS, ATAN, and ATAN2, whose paths part at the bounds of
    their high words: 4 random values in each binade, of each sign, and
    the values next to each bound."""
    bounds = [0x3E400000, 0x3E500000, 0x3C600000, 0x3FDC0000, 0x3FE00000, 0x3FE60000, 0x3FEF3333,
              0x3FF00000, 0x3FF30000, 0x40038000, 0x44100000]
    values = [(h << 32) + i for h in bounds for i in (-1, 0, 1)]
    for e in range(-70, 71):
        values += [F64.round(Fraction(2) ** e * (1 + Fraction(rnd.random())))[0] for _ in range(4)]
    for v in values:
        for name in ("ASIN", "ACOS", "ATAN"):
            g.cmd([v], name)
            g.cmd([v | 1 << 63], name)
    for v in values[::3]:
        for x in (values[rnd.randrange(len(values))], 0x3FF0000000000000):
            for signs in range(4):
                g.cmd([v | (signs & 1) << 63, x | (signs >> 1) << 63], "ATAN2")


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
        for y, x, name in SLOW_PAIRS:
            g.cmd([y, x], name)
    print("\n".join(g.lines))


if __name__ == "__main__":
    main()
