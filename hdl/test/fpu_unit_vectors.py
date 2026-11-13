#!/usr/bin/env python3
"""The vectors of tb_fpu_unit: every operation of src/fpu_unit.vhd on
every operand, or every pair of operands, of a small format, with the
results of emulator/test/fpu_model.py.

The format has 4 bits of exponent and 3 of fraction, 8 bits in all, and
the short one 3 and 2. That has subnormals, overflow, every distance
between exponents that a shift of the unit collapses, and every special
value, in 256 values. An integer of 8 bits can overflow it, which no
64-bit integer does in binary64, so the conversions of an integer keep
the overflow flag of the rounding, which the model's from_int drops. The model's Format computes each result exactly
with fractions, as it does for binary64.

With --wide COUNT, the format is binary64 and the short one binary32,
as in the FPU, and each operation takes COUNT random operands, or pairs,
drawn so that the special values, the subnormals, the largest and the
smallest exponents, and operands of close exponents come often.

A line is

    OP RND SHORT A B K RESULT FLAGS

OP and RND are the positions of the operation and the rounding mode in
t_fpu_op and t_fpu_rnd of src/fpu_pkg.vhd, SHORT 1 for a result rounded
to the short format and given in the main one, K the scale of OP_SCALE2,
in decimal, A, B, and RESULT hex digits, and FLAGS the flags of the model,
in decimal. With SHORT, ADD, SUB, MUL, DIV, and SQRT round their exact
result once, to the short format: the S bit of SYSTEM.md §11.3. The model
rounds twice, to binary64 and then to binary32, which gives the same,
as 53 >= 2 * 24 + 2, but at the small width two roundings can differ from
one, so the vectors round once, as the unit does.

    fpu_unit_vectors.py [--wide COUNT [--seed S]] FILE"""

from __future__ import annotations

import argparse
import os
import random
import sys
from fractions import Fraction
from typing import Iterator, List, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "emulator", "test"))

from fpu_model import DIVZERO, INVALID, Format, floor_log2, pow2, trunc  # noqa: E402

# The order of t_fpu_op and t_fpu_rnd.
OPS = ["ADD", "SUB", "MUL", "MULERR", "DIV", "SQRT", "FMOD", "TOSHORT", "FROMSHORT",
       "INTEGRAL", "ITOF", "UTOF", "FTOI", "FTOU", "FTOW", "SCALE2", "GETEXP", "GETMANT",
       "ILOGB"]
RNDS = ["EVEN", "TRUNC", "FLOOR", "CEIL", "AWAY"]
HOW = {"EVEN": "even", "TRUNC": "trunc", "FLOOR": "floor", "CEIL": "ceil", "AWAY": "away"}

F = Format(4, 3)
S = Format(3, 2)
W = F.width
SCALES: List[int] = list(range(-20, 21))

Line = Tuple[str, str, int, int, int, int, int, int]


def fmod(y: int, x: int) -> Tuple[int, int]:
    """The model's fmod, of format F."""
    if F.is_nan(y) or F.is_nan(x):
        return F.nan(y, x)
    if F.is_inf(y) or F.is_zero(x):
        return F.qnan, INVALID
    if F.is_inf(x) or F.is_zero(y):
        return y, 0
    vy, vx = F.value(y), F.value(x)
    return F.round(vy - trunc(vy / vx) * vx, zero_neg=F.is_neg(y))


def short(op: str, a: int, b: int) -> Tuple[int, int]:
    """op with the S bit: the exact result rounded once to S, in F. The
    special cases are F's, whose results S holds."""
    r, f = F.sqrt(a) if op == "SQRT" else {"ADD": F.add, "SUB": F.sub, "MUL": F.mul,
                                            "DIV": F.div}[op](a, b)
    if not F.is_finite(a) or (op != "SQRT" and not F.is_finite(b)):
        return r, f
    if (op == "DIV" and F.is_zero(b)) or (op == "SQRT" and (F.is_zero(a) or F.is_neg(a))):
        return r, f
    va = F.value(a)
    vb = F.value(b) if op != "SQRT" else Fraction(0)
    if op == "ADD":
        q = va + vb
    elif op == "SUB":
        q = va - vb
    elif op == "MUL":
        q = va * vb
    elif op == "DIV":
        q = va / vb
    else:
        q = va
    if q == 0:
        return r, f
    w, f = S.round_sqrt(q) if op == "SQRT" else S.round(q)
    return F.convert(w, S)[0], f


def scale2(y: int, k: int) -> Tuple[int, int]:
    if F.is_nan(y):
        return F.nan(y)
    if F.is_inf(y) or F.is_zero(y):
        return y, 0
    return F.round(F.value(y) * pow2(k))


def getexp(a: int) -> Tuple[int, int]:
    if F.is_nan(a):
        return F.nan(a)
    if F.is_zero(a):
        return F.sign | F.inf, DIVZERO
    if F.is_inf(a):
        return F.inf, 0
    return F.from_int(floor_log2(abs(F.value(a)))), 0


def getmant(a: int) -> Tuple[int, int]:
    if F.is_nan(a):
        return F.nan(a)
    if not F.is_finite(a) or F.is_zero(a):
        return a, 0
    x = F.value(a)
    return F.round(x * pow2(-floor_log2(abs(x))))


def signed(a: int, bits: int) -> int:
    return a - (1 << bits) if a >> (bits - 1) else a


def to_int(a: int, bits: int, is_signed: bool) -> Tuple[int, int]:
    i, f = F.to_int(a, bits, is_signed)
    return i & F.mask, f


def operand(r: random.Random) -> int:
    """A random value of F, often a special one or near a limit."""
    kind = r.randrange(10)
    sign = F.sign if r.randrange(2) else 0
    if kind == 0:
        return sign | r.choice([0, F.inf, F.qnan, F.inf | 1, F.max_finite, 1,
                                F.inf | r.randrange(1, 1 << F.fbits)])
    if kind == 1:
        return sign | r.randrange(1 << F.fbits)  # a subnormal
    if kind == 2:
        e = r.choice([1, 2, (1 << F.ebits) - 2, (1 << F.ebits) - 3, F.bias, F.bias + 1])
        return sign | e << F.fbits | r.randrange(1 << F.fbits)
    if kind == 3:
        # Few bits set, so that sums and products are often exact or ties.
        e = r.randrange(1, (1 << F.ebits) - 1)
        frac = (r.randrange(1 << 8) << (F.fbits - 8)) if F.fbits > 8 else 0
        return sign | e << F.fbits | frac
    if kind == 4:
        e = F.bias + r.randrange(-70, 70)
        return sign | e << F.fbits | r.randrange(1 << F.fbits)
    return r.randrange(1 << W)


def near(r: random.Random, a: int) -> int:
    """A value of an exponent close to that of a, for cancellations."""
    if not F.is_finite(a) or r.randrange(2):
        return operand(r)
    e = max(0, min((1 << F.ebits) - 2, (a >> F.fbits & ((1 << F.ebits) - 1)) + r.randrange(-3, 4)))
    frac = (a & ((1 << F.fbits) - 1)) ^ r.randrange(1 << r.randrange(1, F.fbits + 1))
    return (r.randrange(2) * F.sign) | e << F.fbits | frac


def pairs(r: random.Random, count: int) -> Iterator[Tuple[int, int]]:
    for _ in range(count):
        a = operand(r)
        yield a, near(r, a)


def vectors(wide: int, seed: int) -> Iterator[Line]:
    rand = random.Random(seed)
    if wide:
        values = [operand(rand) for _ in range(wide)] + list(range(256))
        pair_list = list(pairs(rand, wide))
    else:
        values = list(range(1 << W))
        pair_list = [(a, b) for a in values for b in values]
    for a, b in pair_list:
        for op, fn in (("ADD", F.add), ("SUB", F.sub), ("MUL", F.mul), ("DIV", F.div),
                       ("FMOD", fmod)):
            yield (op, "EVEN", 0, a, b, 0, *fn(a, b))
            if op != "FMOD":
                yield (op, "EVEN", 1, a, b, 0, *short(op, a, b))
        # MULERR is defined for finite operands whose product is finite.
        if F.is_finite(a) and F.is_finite(b):
            p = F.mul(a, b)[0]
            if F.is_finite(p):
                yield ("MULERR", "EVEN", 0, a, b, 0, *F.fma(a, b, F.neg(p)))
    for a in values:
        yield ("SQRT", "EVEN", 0, a, 0, 0, *F.sqrt(a))
        yield ("SQRT", "EVEN", 1, a, 0, 0, *short("SQRT", a, 0))
        yield ("SQRT", "TRUNC", 0, a, 0, 0, *F.sqrt(a, toward_zero=True))
        yield ("TOSHORT", "EVEN", 0, a, 0, 0, *S.convert(a, F))
        for rnd in RNDS:
            yield ("INTEGRAL", rnd, 0, a, 0, 0, *F.to_integral(a, HOW[rnd]))
        # The model's from_int drops the overflow flag, as no 64-bit integer
        # overflows binary64. Integers of 8 bits overflow this format.
        yield ("ITOF", "EVEN", 0, a, 0, 0, *F.round(Fraction(signed(a, W))))
        yield ("UTOF", "EVEN", 0, a, 0, 0, *F.round(Fraction(a)))
        yield ("FTOI", "EVEN", 0, a, 0, 0, *to_int(a, W, True))
        yield ("FTOU", "EVEN", 0, a, 0, 0, *to_int(a, W, False))
        yield ("FTOW", "EVEN", 0, a, 0, 0, *to_int(a, W // 2, True))
        for k in (rand.sample(range(-2100, 2101), 4) + [-1, 0, 1] if wide else SCALES):
            yield ("SCALE2", "EVEN", 0, a, 0, k, *scale2(a, k))
        yield ("GETEXP", "EVEN", 0, a, 0, 0, *getexp(a))
        yield ("GETMANT", "EVEN", 0, a, 0, 0, *getmant(a))
        if F.is_finite(a) and not F.is_zero(a):
            e = floor_log2(abs(F.value(a)))
            yield "ILOGB", "EVEN", 0, a, 0, 0, e & F.mask, 0
    shorts = [rand.randrange(1 << S.width) for _ in range(wide)] if wide else range(1 << S.width)
    for w in shorts:
        yield ("FROMSHORT", "EVEN", 0, w, 0, 0, *F.convert(w, S))


def main() -> None:
    global F, S, W
    ap = argparse.ArgumentParser(description="the vectors of tb_fpu_unit")
    ap.add_argument("--wide", type=int, default=0, metavar="COUNT")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("file")
    args = ap.parse_args()
    if args.wide:
        F, S = Format(11, 52), Format(8, 23)
        W = F.width
    digits = (W + 3) // 4
    lines: List[str] = []
    for op, rnd, sh, a, b, k, r, f in vectors(args.wide, args.seed):
        lines.append(f"{OPS.index(op)} {RNDS.index(rnd)} {sh} {a:0{digits}X} {b:0{digits}X} {k} "
                     f"{r:0{digits}X} {f}")
    with open(args.file, "w") as out:
        out.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
