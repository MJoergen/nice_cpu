#!/usr/bin/env python3
"""The expected results of the phases of float.c, computed in Python.

    ./floatexpected.py [float.c]            print the EXPECT defines
    ./floatexpected.py --check float.c      fail if the file has other values

The sizes are read from the defines in float.c, so that the two cannot
disagree. Each phase is written again here from its description, not
copied from the C, so that a wrong result in the C is caught.

Python's floats are f64. An f32 operation is done in f64 and rounded to
f32 with struct: for +, -, *, /, and sqrt of two f32 operands, the f64
result rounded to f32 is the correctly rounded f32 result, because f64
has more than twice the bits of f32's significand.
"""

import math
import re
import struct
import sys
from typing import Dict, List, Tuple

MASK = 0xFFFFFFFF
FNV_BASIS = 0x811C9DC5
FNV_PRIME = 16777619
SEED = 0x9E3779B9
NAMES = ("CONV_COUNT", "MANDEL_W", "MANDEL_H", "MANDEL_ITER", "NORM_COUNT")


def f32(x: float) -> float:
    """x rounded to the nearest f32, ties to even."""
    return float(struct.unpack("<f", struct.pack("<f", x))[0])


def bits32(x: float) -> int:
    return int(struct.unpack("<I", struct.pack("<f", x))[0])


def bits64(x: float) -> int:
    """The two words of an f64, xored."""
    u = int(struct.unpack("<Q", struct.pack("<d", x))[0])
    return (u ^ (u >> 32)) & MASK


def fnv(h: int, x: int) -> int:
    return ((h ^ (x & MASK)) * FNV_PRIME) & MASK


def signed32(x: int) -> int:
    x &= MASK
    return x - (1 << 32) if x >= (1 << 31) else x


def phase_convert(count: int) -> Tuple[int, List[float], List[float]]:
    s = SEED
    h = FNV_BASIS
    xs32 = []
    xs64 = []
    for _ in range(count):
        s ^= (s << 13) & MASK
        s ^= s >> 17
        s ^= (s << 5) & MASK
        x = signed32(s)
        f = f32(float(x))
        d = float(x)
        third = d / 3.0
        h = fnv(h, math.trunc(f32(f * 0.75)))
        h = fnv(h, math.trunc(third))
        h = fnv(h, bits32(f32(third)))
        h = fnv(h, bits64(f))
        xs32.append(f * 2.0**-31)
        xs64.append(d * 2.0**-31)
    return h, xs32, xs64


def phase_dot32(xs: List[float]) -> int:
    total = 0.0
    for i in range(len(xs)):
        total = f32(total + f32(xs[i] * xs[len(xs) - 1 - i]))
    return bits32(total)


def phase_dot64(xs: List[float]) -> int:
    total = 0.0
    for i in range(len(xs)):
        total += xs[i] * xs[len(xs) - 1 - i]
    return bits64(total)


def phase_mandel(w: int, hgt: int, steps: int) -> int:
    h = FNV_BASIS
    for iy in range(hgt):
        ci = f32(-1.25 + f32(f32(2.5 * iy) / hgt))
        for ix in range(w):
            cr = f32(-2.0 + f32(f32(2.5 * ix) / w))
            zr = zi = 0.0
            n = 0
            while n < steps:
                zr2 = f32(zr * zr)
                zi2 = f32(zi * zi)
                if f32(zr2 + zi2) > 4.0:
                    break
                zi = f32(f32(f32(2.0 * zr) * zi) + ci)
                zr = f32(f32(zr2 - zi2) + cr)
                n += 1
            h = fnv(h, n)
    return h


def phase_norm(xs: List[float], count: int) -> int:
    h = FNV_BASIS
    for j in range(count):
        x, y, z = xs[3 * j:3 * j + 3]
        r = f32(math.sqrt(f32(f32(f32(x * x) + f32(y * y)) + f32(z * z))))
        for c in (x, y, z):
            h = fnv(h, bits32(f32(c / r)))
    return h


def sizes(source: str) -> Dict[str, int]:
    found = dict(re.findall(rf"^#define ({'|'.join(NAMES)}) (\d+)", source, re.M))
    missing = set(NAMES) - set(found)
    if missing:
        sys.exit(f"floatexpected.py: no define for {', '.join(sorted(missing))}")
    return {k: int(v) for k, v in found.items()}


def expected(s: Dict[str, int]) -> Dict[str, int]:
    if 3 * s["NORM_COUNT"] > s["CONV_COUNT"]:
        sys.exit("floatexpected.py: NORM_COUNT needs 3 * NORM_COUNT elements of CONV_COUNT")
    out = {}
    out["CONVERT"], xs32, xs64 = phase_convert(s["CONV_COUNT"])
    out["DOT32"] = phase_dot32(xs32)
    out["DOT64"] = phase_dot64(xs64)
    out["MANDEL"] = phase_mandel(s["MANDEL_W"], s["MANDEL_H"], s["MANDEL_ITER"])
    out["NORM"] = phase_norm(xs32, s["NORM_COUNT"])
    return out


def check(path: str, values: Dict[str, int]) -> bool:
    """Whether the EXPECT values in path are the ones computed here. Prints
    each one that is not."""
    source = open(path).read()
    good = True
    for name, value in values.items():
        m = re.search(rf"^#define EXPECT_{name} 0x([0-9A-Fa-f]+)u", source, re.M)
        if m is None:
            print(f"{path}: no EXPECT_{name}")
            good = False
        elif int(m.group(1), 16) != value:
            print(f"{path}: EXPECT_{name} is {int(m.group(1), 16):#010x}, "
                  f"floatexpected.py gets {value:#010x}")
            good = False
    return good


def main() -> None:
    args = sys.argv[1:]
    checking = bool(args) and args[0] == "--check"
    if checking:
        args = args[1:]
    path = args[0] if args else "float.c"
    values = expected(sizes(open(path).read()))
    if not checking:
        for name, value in values.items():
            print(f"#define EXPECT_{name} 0x{value:08X}u")
        return
    if not check(path, values):
        sys.exit(1)
    print(f"PASS floatexpected.py: {path} has the values of floatexpected.py")


if __name__ == "__main__":
    main()
