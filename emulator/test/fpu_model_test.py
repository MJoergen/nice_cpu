#!/usr/bin/env python3
"""The test of fpu_model.py, the reference model of doc/SYSTEM.md §11.

The model is the oracle of the FPU's tests, so this checks it four ways:

1. CASES, a table of hand-checked accesses, each with its reason.
2. At binary64, the model against the host's doubles, for IEEE 754's
   operations, on special and random operands. Where the host gives a
   NaN, the model must give the canonical NaN, as the host's NaN has the
   sign of its CPU.
3. At a small width, every pair of finite values against a rounding by
   brute force, which searches the list of all values for the nearest.
   And the S form: that rounding twice, through the wider format, gives
   the narrow result, which is why 53 >= 2 · 24 + 2 is enough.
4. In exact arithmetic: the constants against decimal, ISQRT against
   math.isqrt, SCALE10 correctly rounded for k <= 22 and within a bound
   beyond, and constants of 15 digits through FROMBCD, SCALE10, and
   DIGITS 15, which must come back.

The random cases have fixed seeds. It exits 1 on the first failure."""

from __future__ import annotations

import bisect
import decimal
import math
import os
import random
import struct
import sys
from fractions import Fraction
from typing import Callable, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fpu_model import (  # noqa: E402
    CANONICAL_NAN,
    CMD,
    COMMANDS,
    CONSTANTS,
    DIVZERO,
    F32,
    F64,
    FPU,
    INVALID,
    NUMBERS,
    OVERFLOW,
    REL,
    STACK,
    STATUS,
    X_HI,
    X_LO,
    X_S,
    X_W,
    Format,
    floor_log2,
    pow2,
    s64,
    scale10,
)

FAILURES = 0


def fail(msg: str) -> None:
    global FAILURES
    FAILURES += 1
    print("FAIL " + msg)
    if FAILURES >= 10:
        sys.exit(1)


def d(x: float) -> int:
    """The bits of a binary64 value, written as a literal."""
    return int(struct.unpack("<Q", struct.pack("<d", x))[0])


def h(bits: int) -> float:
    """The host's double of bits."""
    return float(struct.unpack("<d", struct.pack("<Q", bits))[0])


N = CANONICAL_NAN  # 0x7FF80000_00000000
QN = 0x7FF8000000000123  # a quiet NaN with a payload
SN = 0x7FF0000000000001  # a signaling NaN
INF = 0x7FF0000000000000
NINF = 0xFFF0000000000000
MAX = 0x7FEFFFFFFFFFFFFF  # the largest finite value, (2 - 2^-52) · 2^1023
MINSUB = 0x0000000000000001  # 2^-1074
NZ = 0x8000000000000000  # -0
SIXTEEN = [d(float(i)) for i in range(1, 17)]

# Each case: its reason, the stack before (bottom first), the flags
# before, the access, the stack after, the flags after, and the value a
# read returns. The access is a command by name, with n and .S, a
# command word as "cmd W", a write as "w REG W", or a read as "r REG".
Case = Tuple[str, List[int], int, str, List[int], int, Optional[int]]

CASES: List[Case] = [
    # §11.1, the registers.
    ("X_LO pushes the word with a high word of 0", [], 0, "w X_LO 0x12345678", [0x12345678], 0, None),
    ("X_HI sets the high word of X in place", [0x12345678], 0, "w X_HI 0x3FF00000", [0x3FF0000012345678], 0, None),
    ("X_HI on an empty stack is ignored, with the fault", [], 0, "w X_HI 1", [], STACK, None),
    ("a push onto 16 values drops the deepest", SIXTEEN, 0, "w X_LO 5", SIXTEEN[1:] + [5], STACK, None),
    # 0.1f is 0x3DCCCCCD: exponent -4, fraction 0x4CCCCD, which is
    # 0x99999A << 28 in the 52 bits.
    ("X_S pushes a binary32 value exactly", [], 0, "w X_S 0x3DCCCCCD", [0x3FB99999A0000000], 0, None),
    ("X_S pushes a signaling NaN as the canonical one, no flag", [], 0, "w X_S 0x7F800001", [N], 0, None),
    ("X_S pushes -inf", [], 0, "w X_S 0xFF800000", [NINF], 0, None),
    ("X_S pushes a binary32 subnormal, 2^-149", [], 0, "w X_S 1", [0x36A0000000000000], 0, None),
    ("X_W pushes a signed word", [], 0, "w X_W 0xFFFFFFFF", [d(-1.0)], 0, None),
    ("X_W pushes -2^31", [], 0, "w X_W 0x80000000", [0xC1E0000000000000], 0, None),
    ("X_S reads 0.1 rounded to nearest", [d(0.1)], 0, "r X_S", [d(0.1)], 0, 0x3DCCCCCD),
    ("X_S reads a NaN as 0x7FC00000", [QN | NZ], 0, "r X_S", [QN | NZ], 0, 0x7FC00000),
    ("X_S reads the largest double as inf", [MAX], 0, "r X_S", [MAX], 0, 0x7F800000),
    ("X_S reads -1e300 as -inf", [d(-1e300)], 0, "r X_S", [d(-1e300)], 0, 0xFF800000),
    # The largest binary32, (2 - 2^-23) · 2^127, has an odd fraction.
    ("X_S reads the largest binary32", [0x47EFFFFFE0000000], 0, "r X_S", [0x47EFFFFFE0000000], 0, 0x7F7FFFFF),
    ("X_S: halfway above it, the tie goes to inf", [0x47EFFFFFF0000000], 0, "r X_S", [0x47EFFFFFF0000000], 0, 0x7F800000),
    ("X_S: 2^-150 is a tie between 0 and 2^-149, so 0", [0x3690000000000000], 0, "r X_S", [0x3690000000000000], 0, 0),
    ("X_S: -2^-150 gives -0", [0xB690000000000000], 0, "r X_S", [0xB690000000000000], 0, 0x80000000),
    ("X_S: 1.5 · 2^-149 is a tie, to 2 · 2^-149", [0x36A8000000000000], 0, "r X_S", [0x36A8000000000000], 0, 2),
    ("X_W saturates 1e10", [d(1e10)], 0, "r X_W", [d(1e10)], 0, 0x7FFFFFFF),
    ("X_W truncates -2^31 - 0.5 to -2^31", [d(-2147483648.5)], 0, "r X_W", [d(-2147483648.5)], 0, 0x80000000),
    ("X_W saturates -2^31 - 1", [d(-2147483649.0)], 0, "r X_W", [d(-2147483649.0)], 0, 0x80000000),
    ("X_W truncates -0.9 to 0", [d(-0.9)], 0, "r X_W", [d(-0.9)], 0, 0),
    ("X_W reads a NaN as 0", [QN], 0, "r X_W", [QN], 0, 0),
    ("X_W reads -inf as -2^31", [NINF], 0, "r X_W", [NINF], 0, 0x80000000),
    ("X_LO of an empty stack is the canonical NaN", [], 0, "r X_LO", [], 0, 0),
    ("X_HI of an empty stack is the canonical NaN", [], 0, "r X_HI", [], 0, 0x7FF80000),
    ("CMD reads 0", [d(1.0)], 0, "r CMD", [d(1.0)], 0, 0),
    ("offset 7 reads 0", [d(1.0)], 0, "r 7", [d(1.0)], 0, 0),
    ("offset 7 ignores a write", [d(1.0)], 0, "w 7 5", [d(1.0)], 0, None),
    ("REL ignores a write", [d(1.0)], 0, "w REL 5", [d(1.0)], 0, None),
    ("REL of an empty stack is 2", [], 0, "r REL", [], 0, 2),
    ("REL: Y < X is -1", [d(1.0), d(2.0)], 0, "r REL", [d(1.0), d(2.0)], 0, 0xFFFFFFFF),
    ("REL: Y > X is 1", [d(2.0), d(1.0)], 0, "r REL", [d(2.0), d(1.0)], 0, 1),
    ("REL: -0 = +0", [NZ, 0], 0, "r REL", [NZ, 0], 0, 0),
    ("REL: inf = inf", [INF, INF], 0, "r REL", [INF, INF], 0, 0),
    ("REL: -inf < MAX", [NINF, MAX], 0, "r REL", [NINF, MAX], 0, 0xFFFFFFFF),
    ("REL: a NaN is unordered, with no flag", [SN, d(1.0)], 0, "r REL", [SN, d(1.0)], 0, 2),
    ("REL: a missing Y is a NaN", [d(1.0)], 0, "r REL", [d(1.0)], 0, 2),
    # §11.2: the depth, the flags << 8, and the class << 16: negative 1,
    # zero 2, infinite 4, NaN 8, whole 16, and fits 32.
    ("STATUS of -0: negative, zero, whole, fits", [NZ], 0, "r STATUS", [NZ], 0, 0x00330001),
    ("STATUS of 2^31 - 0.5: fits, not whole", [d(2147483647.5)], 0, "r STATUS", [d(2147483647.5)], 0, 0x00200001),
    ("STATUS of 2^31: whole, does not fit", [d(2147483648.0)], 0, "r STATUS", [d(2147483648.0)], 0, 0x00100001),
    ("STATUS of -2^31 - 0.5: negative, fits", [d(-2147483648.5)], 0, "r STATUS", [d(-2147483648.5)], 0, 0x00210001),
    ("STATUS of -inf: negative, infinite", [d(1.0), NINF], 0, "r STATUS", [d(1.0), NINF], 0, 0x00050002),
    ("STATUS of an empty stack: the class of the canonical NaN", [], 0xF, "r STATUS", [], 0xF, 0x00080F00),
    ("STATUS of a NaN with its sign set", [QN | NZ], 0, "r STATUS", [QN | NZ], 0, 0x00090001),
    ("STATUS of 16 values: X is 16, whole, fits", SIXTEEN, 0, "r STATUS", SIXTEEN, 0, 0x00300010),
    ("a write of STATUS sets bits 11..8 only", [d(1.0)], 0xA, "w STATUS 0xFFFFF5FF", [d(1.0)], 0x5, None),
    # §11.3, the command word.
    ("ADD with n = 5 is not valid", [d(1.0), d(2.0)], 0, "cmd 0x0510", [d(1.0), d(2.0)], INVALID, None),
    ("CMP 8 is not valid", [d(1.0), d(2.0)], 0, "cmd 0x081C", [d(1.0), d(2.0)], INVALID, None),
    ("CLEAR 2 is not valid", [d(1.0)], 0, "cmd 0x0201", [d(1.0)], INVALID, None),
    ("NEG with S is not valid", [d(1.0)], 0, "cmd 0x10015", [d(1.0)], INVALID, None),
    ("bit 17 is not valid", [d(1.0)], 0, "cmd 0x20000", [d(1.0)], INVALID, None),
    ("0x07 is not defined", [], 0, "cmd 0x07", [], INVALID, None),
    ("SIN is phase 2, so not defined, and no stack fault", [], 0, "cmd 0x40", [], INVALID, None),
    ("0xFF is not defined", [], STACK, "cmd 0xFF", [], STACK | INVALID, None),
    # The stack.
    ("NOP", [d(1.0)], 0, "NOP", [d(1.0)], 0, None),
    ("CLEAR keeps the flags", [d(1.0), d(2.0)], 0x3, "CLEAR", [], 0x3, None),
    ("CLEAR 1 clears them", [d(1.0), d(2.0)], 0xF, "CLEAR 1", [], 0, None),
    ("DUP", [d(1.0)], 0, "DUP", [d(1.0), d(1.0)], 0, None),
    ("DUP keeps a NaN's bits", [SN], 0, "DUP", [SN, SN], 0, None),
    ("DUP of an empty stack", [], 0, "DUP", [N], STACK, None),
    ("DROP is DROP 1", [d(1.0), d(2.0), d(3.0)], 0, "DROP", [d(1.0), d(2.0)], 0, None),
    ("DROP 2", [d(1.0), d(2.0), d(3.0)], 0, "DROP 2", [d(1.0)], 0, None),
    ("DROP 3 of two values", [d(1.0), d(2.0)], 0, "DROP 3", [], STACK, None),
    ("SWAP", [d(1.0), d(2.0)], 0, "SWAP", [d(2.0), d(1.0)], 0, None),
    ("SWAP keeps the bits of NaNs", [QN, SN], 0, "SWAP", [SN, QN], 0, None),
    ("SWAP of one value", [d(5.0)], 0, "SWAP", [d(5.0), N], STACK, None),
    ("SWAP of an empty stack", [], 0, "SWAP", [N, N], STACK, None),
    ("OVER", [d(1.0), d(2.0)], 0, "OVER", [d(1.0), d(2.0), d(1.0)], 0, None),
    ("OVER of one value", [d(5.0)], 0, "OVER", [d(5.0), N], STACK, None),
    ("PICK 2", [d(1.0), d(2.0), d(3.0)], 0, "PICK 2", [d(1.0), d(2.0), d(3.0), d(1.0)], 0, None),
    ("PICK 3 of three values", [d(1.0), d(2.0), d(3.0)], 0, "PICK 3", [d(1.0), d(2.0), d(3.0), N], STACK, None),
    ("PICK 15 of 16 copies the deepest, and the push drops it", SIXTEEN, 0, "PICK 15", SIXTEEN[1:] + [d(1.0)], STACK, None),
    ("PICK 255 of one value", [d(1.0)], 0, "PICK 255", [d(1.0), N], STACK, None),
    # Add and subtract.
    ("1 + 2", [d(1.0), d(2.0)], 0, "ADD", [d(3.0)], 0, None),
    ("0.1 + 0.2 is 0.30000000000000004", [d(0.1), d(0.2)], 0, "ADD", [0x3FD3333333333334], 0, None),
    ("-0 + -0 is -0", [NZ, NZ], 0, "ADD", [NZ], 0, None),
    ("+0 + -0 is +0", [0, NZ], 0, "ADD", [0], 0, None),
    ("1 - 1 is +0", [d(1.0), d(1.0)], 0, "SUB", [0], 0, None),
    ("-0 - +0 is -0", [NZ, 0], 0, "SUB", [NZ], 0, None),
    ("SUB is Y - X", [d(5.0), d(3.0)], 0, "SUB", [d(2.0)], 0, None),
    ("inf - inf", [INF, INF], 0, "SUB", [N], INVALID, None),
    ("inf + -inf", [INF, NINF], 0, "ADD", [N], INVALID, None),
    ("inf + 1", [INF, d(1.0)], 0, "ADD", [INF], 0, None),
    ("a quiet NaN gives the canonical NaN, no flag", [QN, d(1.0)], 0, "ADD", [N], 0, None),
    ("a signaling NaN sets invalid", [d(1.0), SN], 0, "ADD", [N], INVALID, None),
    ("MAX + MAX", [MAX, MAX], 0, "ADD", [INF], OVERFLOW, None),
    # The unit in the last place of MAX is 2^971, half of it 2^970.
    # MAX's fraction is odd, so the tie goes up, to 2^1024.
    ("MAX + 2^970 is a tie, which overflows", [MAX, 0x7C90000000000000], 0, "ADD", [INF], OVERFLOW, None),
    ("MAX + 2^969 rounds to MAX", [MAX, 0x7C80000000000000], 0, "ADD", [MAX], 0, None),
    ("-MAX - 2^970 overflows to -inf", [MAX | NZ, 0x7C90000000000000], 0, "SUB", [NINF], OVERFLOW, None),
    ("1 + 2^-53 is a tie, to 1, which is even", [d(1.0), 0x3CA0000000000000], 0, "ADD", [d(1.0)], 0, None),
    ("(1 + 2^-52) + 2^-53 is a tie, to 1 + 2^-51", [0x3FF0000000000001, 0x3CA0000000000000], 0, "ADD", [0x3FF0000000000002], 0, None),
    ("1 + an ADD with a missing Y", [d(1.0)], 0, "ADD", [N], STACK, None),
    # Multiply and divide.
    ("2^-1074 · 0.5 is a tie, to 0", [MINSUB, d(0.5)], 0, "MUL", [0], 0, None),
    ("3 · 2^-1074 · 0.5 is a tie, to 2 · 2^-1074", [3, d(0.5)], 0, "MUL", [2], 0, None),
    ("-2^-1074 · 0.5 is -0", [MINSUB | NZ, d(0.5)], 0, "MUL", [NZ], 0, None),
    ("a subnormal product: 2^-1022 · 0.75", [0x0010000000000000, d(0.75)], 0, "MUL", [0x000C000000000000], 0, None),
    ("inf · 0", [INF, 0], 0, "MUL", [N], INVALID, None),
    ("-0 · 3", [NZ, d(3.0)], 0, "MUL", [NZ], 0, None),
    ("-MAX · 2", [MAX | NZ, d(2.0)], 0, "MUL", [NINF], OVERFLOW, None),
    ("DIV is Y / X: 3 / 10 is the double nearest 0.3", [d(3.0), d(10.0)], 0, "DIV", [0x3FD3333333333333], 0, None),
    ("1 / 3", [d(1.0), d(3.0)], 0, "DIV", [0x3FD5555555555555], 0, None),
    ("1 / 0", [d(1.0), 0], 0, "DIV", [INF], DIVZERO, None),
    ("-1 / 0", [d(-1.0), 0], 0, "DIV", [NINF], DIVZERO, None),
    ("1 / -0", [d(1.0), NZ], 0, "DIV", [NINF], DIVZERO, None),
    ("0 / 0", [0, 0], 0, "DIV", [N], INVALID, None),
    ("inf / inf", [INF, NINF], 0, "DIV", [N], INVALID, None),
    ("inf / 0 is inf, no flag", [INF, 0], 0, "DIV", [INF], 0, None),
    ("-1 / inf is -0", [d(-1.0), INF], 0, "DIV", [NZ], 0, None),
    ("MAX / 0.5", [MAX, d(0.5)], 0, "DIV", [INF], OVERFLOW, None),
    # Square root.
    ("√2", [d(2.0)], 0, "SQRT", [0x3FF6A09E667F3BCD], 0, None),
    ("√2^-1074 is 2^-537", [MINSUB], 0, "SQRT", [0x1E60000000000000], 0, None),
    ("√-0 is -0", [NZ], 0, "SQRT", [NZ], 0, None),
    ("√-1", [d(-1.0)], 0, "SQRT", [N], INVALID, None),
    ("√inf", [INF], 0, "SQRT", [INF], 0, None),
    ("√-inf", [NINF], 0, "SQRT", [N], INVALID, None),
    # The S forms. A binary32 ulp at 1 is 2^-23.
    ("ADD.S: 1 + 2^-24 is a tie in binary32, to 1", [d(1.0), 0x3E70000000000000], 0, "ADD.S", [d(1.0)], 0, None),
    ("ADD.S: 1 + 0.75 · 2^-23 rounds up", [d(1.0), 0x3E78000000000000], 0, "ADD.S", [0x3FF0000020000000], 0, None),
    ("DIV.S: 1 / 3 is 0x3EAAAAAB", [d(1.0), d(3.0)], 0, "DIV.S", [0x3FD5555560000000], 0, None),
    ("SQRT.S: √2 is 0x3FB504F3", [d(2.0)], 0, "SQRT.S", [0x3FF6A09E60000000], 0, None),
    ("MUL.S: the largest binary32 · 2 overflows", [0x47EFFFFFE0000000, d(2.0)], 0, "MUL.S", [INF], OVERFLOW, None),
    ("SUB.S of a NaN", [QN, d(1.0)], 0, "SUB.S", [N], 0, None),
    # NEG, ABS, MIN, MAX.
    ("NEG keeps a NaN's payload", [QN], 0, "NEG", [QN | NZ], 0, None),
    ("NEG of a signaling NaN sets no flag", [SN], 0, "NEG", [SN | NZ], 0, None),
    ("NEG of an empty stack", [], 0, "NEG", [0xFFF8000000000000], STACK, None),
    ("ABS of -SN", [SN | NZ], 0, "ABS", [SN], 0, None),
    ("ABS of -0", [NZ], 0, "ABS", [0], 0, None),
    ("MIN(-0, +0) is -0", [NZ, 0], 0, "MIN", [NZ], 0, None),
    ("MIN(+0, -0) is -0", [0, NZ], 0, "MIN", [NZ], 0, None),
    ("MAX(-0, +0) is +0", [NZ, 0], 0, "MAX", [0], 0, None),
    ("MAX(+0, -0) is +0", [0, NZ], 0, "MAX", [0], 0, None),
    ("MIN of a quiet NaN", [d(1.0), QN], 0, "MIN", [N], 0, None),
    ("MAX of a signaling NaN", [SN, d(1.0)], 0, "MAX", [N], INVALID, None),
    ("MIN(-inf, 1)", [NINF, d(1.0)], 0, "MIN", [NINF], 0, None),
    ("MAX(2, 1)", [d(2.0), d(1.0)], 0, "MAX", [d(2.0)], 0, None),
    # ROUND32 and ISQRT.
    ("ROUND32 of 0.1 is 0.1f", [d(0.1)], 0, "ROUND32", [0x3FB99999A0000000], 0, None),
    ("ROUND32 of MAX", [MAX], 0, "ROUND32", [INF], OVERFLOW, None),
    ("ROUND32 of -0", [NZ], 0, "ROUND32", [NZ], 0, None),
    ("ROUND32 of a signaling NaN", [SN], 0, "ROUND32", [N], INVALID, None),
    ("ROUND32 of 2^-1074 is +0", [MINSUB], 0, "ROUND32", [0], 0, None),
    ("ISQRT 15", [d(15.0)], 0, "ISQRT", [d(3.0)], 0, None),
    ("ISQRT 16", [d(16.0)], 0, "ISQRT", [d(4.0)], 0, None),
    ("ISQRT 2.5", [d(2.5)], 0, "ISQRT", [d(1.0)], 0, None),
    ("ISQRT 0.5 is +0", [d(0.5)], 0, "ISQRT", [0], 0, None),
    # n = 2^26 + 1: n^2 - 1 = 2^52 + 2^27 is a double, and its √ rounds
    # to n, so SQRT and FLOOR give n where the floor is n - 1 = 2^26.
    ("ISQRT of n^2 - 1, n = 2^26 + 1", [0x4330000008000000], 0, "ISQRT", [0x4190000000000000], 0, None),
    ("ISQRT of 2^106 + 2^55 is 2^53, not the floor", [0x4690000000000002], 0, "ISQRT", [0x4340000000000000], 0, None),
    ("ISQRT of -0", [NZ], 0, "ISQRT", [NZ], 0, None),
    ("ISQRT of -1", [d(-1.0)], 0, "ISQRT", [N], INVALID, None),
    ("ISQRT of inf", [INF], 0, "ISQRT", [INF], 0, None),
    # SIGN and CMP.
    ("SIGN of -0 is +0", [NZ], 0, "SIGN", [0], 0, None),
    ("SIGN of -3", [d(-3.0)], 0, "SIGN", [d(-1.0)], 0, None),
    ("SIGN of inf", [INF], 0, "SIGN", [d(1.0)], 0, None),
    ("SIGN of 2^-1074", [MINSUB], 0, "SIGN", [d(1.0)], 0, None),
    ("SIGN of a quiet NaN", [QN], 0, "SIGN", [N], 0, None),
    ("SIGN of a signaling NaN", [SN], 0, "SIGN", [N], INVALID, None),
    ("CMP 1: 1 < 2", [d(1.0), d(2.0)], 0, "CMP 1", [d(-1.0)], 0, None),
    ("CMP 3: 2 <= 2", [d(2.0), d(2.0)], 0, "CMP 3", [d(-1.0)], 0, None),
    ("CMP 4: 1 > 2 is false, +0", [d(1.0), d(2.0)], 0, "CMP 4", [0], 0, None),
    ("CMP 5: 1 != 2", [d(1.0), d(2.0)], 0, "CMP 5", [d(-1.0)], 0, None),
    ("CMP 2: -0 = +0", [NZ, 0], 0, "CMP 2", [d(-1.0)], 0, None),
    ("CMP 0 is never true", [d(1.0), d(1.0)], 0, "CMP", [0], 0, None),
    ("CMP 7 of a quiet NaN is false, and invalid", [d(1.0), QN], 0, "CMP 7", [0], INVALID, None),
    # FMOD.
    ("FMOD 5.5, 2", [d(5.5), d(2.0)], 0, "FMOD", [d(1.5)], 0, None),
    ("FMOD -5.5, 2", [d(-5.5), d(2.0)], 0, "FMOD", [d(-1.5)], 0, None),
    ("FMOD 5, -3: the sign of Y", [d(5.0), d(-3.0)], 0, "FMOD", [d(2.0)], 0, None),
    ("FMOD -4, 2 is -0", [d(-4.0), d(2.0)], 0, "FMOD", [NZ], 0, None),
    ("FMOD -0, 3", [NZ, d(3.0)], 0, "FMOD", [NZ], 0, None),
    ("FMOD 1, inf", [d(1.0), INF], 0, "FMOD", [d(1.0)], 0, None),
    ("FMOD inf, 1", [INF, d(1.0)], 0, "FMOD", [N], INVALID, None),
    ("FMOD 1, 0", [d(1.0), 0], 0, "FMOD", [N], INVALID, None),
    ("FMOD MAX, 2^-1074 is +0, exact", [MAX, MINSUB], 0, "FMOD", [0], 0, None),
    # 0.1 = 0x1999999999999A · 2^-56, 1e300 / 0.1 is not whole; the
    # remainder is exact, so this is C's fmod, which Python's math has.
    ("FMOD 1e300, 0.1", [d(1e300), d(0.1)], 0, "FMOD", [d(math.fmod(1e300, 0.1))], 0, None),
    # Whole numbers.
    ("FLOOR -0.5", [d(-0.5)], 0, "FLOOR", [d(-1.0)], 0, None),
    ("CEIL -0.5 is -0", [d(-0.5)], 0, "CEIL", [NZ], 0, None),
    ("CEIL 0.5", [d(0.5)], 0, "CEIL", [d(1.0)], 0, None),
    ("TRUNC -0.5 is -0", [d(-0.5)], 0, "TRUNC", [NZ], 0, None),
    ("TRUNC -1.5", [d(-1.5)], 0, "TRUNC", [d(-1.0)], 0, None),
    ("NEAREST 2.5 is 2, ties to even", [d(2.5)], 0, "NEAREST", [d(2.0)], 0, None),
    ("NEAREST 3.5 is 4", [d(3.5)], 0, "NEAREST", [d(4.0)], 0, None),
    ("NEAREST -0.5 is -0", [d(-0.5)], 0, "NEAREST", [NZ], 0, None),
    ("NEAREST 2^52 + 1 is itself", [0x4330000000000001], 0, "NEAREST", [0x4330000000000001], 0, None),
    ("ROUND 2.5 is 3, ties away", [d(2.5)], 0, "ROUND", [d(3.0)], 0, None),
    ("ROUND -2.5 is -3", [d(-2.5)], 0, "ROUND", [d(-3.0)], 0, None),
    ("ROUND -0.4 is -0", [d(-0.4)], 0, "ROUND", [NZ], 0, None),
    ("ROUND of the largest value below 0.5 is 0", [0x3FDFFFFFFFFFFFFF], 0, "ROUND", [0], 0, None),
    ("FLOOR of inf", [INF], 0, "FLOOR", [INF], 0, None),
    ("FLOOR of a quiet NaN", [QN], 0, "FLOOR", [N], 0, None),
    ("CEIL of a signaling NaN", [SN], 0, "CEIL", [N], INVALID, None),
    # Integers.
    ("ITOF of all ones is -1", [0xFFFFFFFFFFFFFFFF], 0, "ITOF", [d(-1.0)], 0, None),
    ("UTOF of all ones is 2^64", [0xFFFFFFFFFFFFFFFF], 0, "UTOF", [0x43F0000000000000], 0, None),
    ("ITOF 2^53 + 1 is a tie, to 2^53", [(1 << 53) + 1], 0, "ITOF", [0x4340000000000000], 0, None),
    ("ITOF 2^53 + 3 is a tie, to 2^53 + 4", [(1 << 53) + 3], 0, "ITOF", [0x4340000000000002], 0, None),
    ("ITOF -2^63", [1 << 63], 0, "ITOF", [0xC3E0000000000000], 0, None),
    ("ITOF 0 is +0", [0], 0, "ITOF", [0], 0, None),
    ("UTOF of a word pushed through X_LO", [0xFFFFFFFF], 0, "UTOF", [d(4294967295.0)], 0, None),
    ("FTOI -1.5", [d(-1.5)], 0, "FTOI", [0xFFFFFFFFFFFFFFFF], 0, None),
    ("FTOI 1e19 saturates", [d(1e19)], 0, "FTOI", [0x7FFFFFFFFFFFFFFF], INVALID, None),
    ("FTOI -2^63 fits", [0xC3E0000000000000], 0, "FTOI", [1 << 63], 0, None),
    ("FTOI 2^63 does not", [0x43E0000000000000], 0, "FTOI", [0x7FFFFFFFFFFFFFFF], INVALID, None),
    ("FTOI of a NaN", [QN], 0, "FTOI", [0], INVALID, None),
    ("FTOI of an empty stack", [], 0, "FTOI", [0], STACK | INVALID, None),
    ("FTOU -0.5 is 0, no flag", [d(-0.5)], 0, "FTOU", [0], 0, None),
    ("FTOU -1", [d(-1.0)], 0, "FTOU", [0], INVALID, None),
    ("FTOU 2^64", [0x43F0000000000000], 0, "FTOU", [0xFFFFFFFFFFFFFFFF], INVALID, None),
    ("FTOU of the largest value below 2^64", [0x43EFFFFFFFFFFFFF], 0, "FTOU", [0xFFFFFFFFFFFFF800], 0, None),
    ("FTOU of -inf", [NINF], 0, "FTOU", [0], INVALID, None),
    # Words.
    ("AND -1, 5.9", [d(-1.0), d(5.9)], 0, "AND", [d(5.0)], 0, None),
    ("OR 1, 2", [d(1.0), d(2.0)], 0, "OR", [d(3.0)], 0, None),
    ("XOR -1, 1", [d(-1.0), d(1.0)], 0, "XOR", [d(-2.0)], 0, None),
    ("NOT 0", [0], 0, "NOT", [d(-1.0)], 0, None),
    ("NOT -0.5 is NOT 0", [d(-0.5)], 0, "NOT", [d(-1.0)], 0, None),
    ("NOT -2^31", [0xC1E0000000000000], 0, "NOT", [d(2147483647.0)], 0, None),
    ("SHL 1, 31 is -2^31", [d(1.0), d(31.0)], 0, "SHL", [0xC1E0000000000000], 0, None),
    ("SHL 1, 32 is +0", [d(1.0), d(32.0)], 0, "SHL", [0], 0, None),
    ("SHL 1, -1", [d(1.0), d(-1.0)], 0, "SHL", [N], INVALID, None),
    ("SHR -1, 1 is 2^31 - 1", [d(-1.0), d(1.0)], 0, "SHR", [d(2147483647.0)], 0, None),
    ("SHR -1, 0 is -1", [d(-1.0), 0], 0, "SHR", [d(-1.0)], 0, None),
    ("SHR -1, 31 is 1", [d(-1.0), d(31.0)], 0, "SHR", [d(1.0)], 0, None),
    ("IDIV -1, 2 is +0", [d(-1.0), d(2.0)], 0, "IDIV", [0], 0, None),
    ("IDIV -2^31, -1 is 2^31", [0xC1E0000000000000, d(-1.0)], 0, "IDIV", [0x41E0000000000000], 0, None),
    ("IDIV 7, -2 is -3", [d(7.0), d(-2.0)], 0, "IDIV", [d(-3.0)], 0, None),
    ("IDIV 1, 0", [d(1.0), 0], 0, "IDIV", [N], INVALID, None),
    ("MOD -7, 2 is -1", [d(-7.0), d(2.0)], 0, "MOD", [d(-1.0)], 0, None),
    ("MOD 7, -2 is 1", [d(7.0), d(-2.0)], 0, "MOD", [d(1.0)], 0, None),
    ("MOD -4, 2 is +0", [d(-4.0), d(2.0)], 0, "MOD", [0], 0, None),
    ("AND 2^31, 1: 2^31 does not fit", [0x41E0000000000000, d(1.0)], 0, "AND", [N], INVALID, None),
    ("AND -2^31 - 0.5, -1: it fits, rounded toward zero", [d(-2147483648.5), d(-1.0)], 0, "AND", [0xC1E0000000000000], 0, None),
    ("AND of a quiet NaN", [QN, d(1.0)], 0, "AND", [N], INVALID, None),
    ("OR of inf", [INF, d(1.0)], 0, "OR", [N], INVALID, None),
    ("AND of one value", [d(1.0)], 0, "AND", [N], STACK | INVALID, None),
    # Constants.
    ("CONST 3 is π", [], 0, "CONST 3", [0x400921FB54442D18], 0, None),
    ("CONST 9 is 0.1", [], 0, "CONST 9", [d(0.1)], 0, None),
    ("CONST 16 is reserved", [], 0, "CONST 16", [N], INVALID, None),
    ("CONST 255 is reserved", [], 0, "CONST 255", [N], INVALID, None),
    ("CONST onto 16 values", SIXTEEN, 0, "CONST 1", SIXTEEN[1:] + [d(1.0)], STACK, None),
    # SCALE2.
    ("SCALE2 1, -1074", [d(1.0), d(-1074.0)], 0, "SCALE2", [MINSUB], 0, None),
    ("SCALE2 3, -1075 is a tie, to 2 · 2^-1074", [d(3.0), d(-1075.0)], 0, "SCALE2", [2], 0, None),
    ("SCALE2 1, 1024", [d(1.0), d(1024.0)], 0, "SCALE2", [INF], OVERFLOW, None),
    ("SCALE2 1, 0.5", [d(1.0), d(0.5)], 0, "SCALE2", [N], INVALID, None),
    ("SCALE2 1, a quiet NaN", [d(1.0), QN], 0, "SCALE2", [N], INVALID, None),
    ("SCALE2 a quiet NaN, 1", [QN, d(1.0)], 0, "SCALE2", [N], 0, None),
    ("SCALE2 0, inf is 0", [0, INF], 0, "SCALE2", [0], 0, None),
    ("SCALE2 1, inf: an infinite X sets no overflow", [d(1.0), INF], 0, "SCALE2", [INF], 0, None),
    ("SCALE2 -MAX, inf", [MAX | NZ, INF], 0, "SCALE2", [NINF], 0, None),
    ("SCALE2 -1, -inf is -0", [d(-1.0), NINF], 0, "SCALE2", [NZ], 0, None),
    ("SCALE2 inf, -inf is inf", [INF, NINF], 0, "SCALE2", [INF], 0, None),
    ("SCALE2 2^-1074, 2098 is 2^1024", [MINSUB, d(2098.0)], 0, "SCALE2", [INF], OVERFLOW, None),
    # MAX · 2^-2098 = (1 - 2^-53) · 2^-1074, above half of 2^-1074.
    ("SCALE2 MAX, -2098 rounds to 2^-1074", [MAX, d(-2098.0)], 0, "SCALE2", [MINSUB], 0, None),
    ("SCALE2 1, 1e300, counted as 2100", [d(1.0), d(1e300)], 0, "SCALE2", [INF], OVERFLOW, None),
    # SCALE10.
    ("SCALE10 3, -1 divides: the double nearest 0.3", [d(3.0), d(-1.0)], 0, "SCALE10", [0x3FD3333333333333], 0, None),
    ("SCALE10 1, 22 is exact", [d(1.0), d(22.0)], 0, "SCALE10", [d(1e22)], 0, None),
    ("SCALE10 1, 23: 10^1 · 10^2 · 10^4 · 10^16, exact pairs", [d(1.0), d(23.0)], 0, "SCALE10", [0x44B52D02C7E14AF6], 0, None),
    ("SCALE10 1, 309", [d(1.0), d(309.0)], 0, "SCALE10", [INF], OVERFLOW, None),
    ("SCALE10 1, -400", [d(1.0), d(-400.0)], 0, "SCALE10", [0], 0, None),
    ("SCALE10 5, -324 is 2^-1074", [d(5.0), d(-324.0)], 0, "SCALE10", [MINSUB], 0, None),
    ("SCALE10 1, 1.5", [d(1.0), d(1.5)], 0, "SCALE10", [N], INVALID, None),
    ("SCALE10 -0, 5", [NZ, d(5.0)], 0, "SCALE10", [NZ], 0, None),
    ("SCALE10 0, -inf", [0, NINF], 0, "SCALE10", [0], 0, None),
    ("SCALE10 1, 1e300, counted as 650", [d(1.0), d(1e300)], 0, "SCALE10", [INF], OVERFLOW, None),
    ("SCALE10 1, inf: an infinite X sets no overflow", [d(1.0), INF], 0, "SCALE10", [INF], 0, None),
    # 0x7FF00000_00000001 is 2^63 - 2^52 + 1, and the unit in the last
    # place there is 2^10: 2^63 - 2^52 = (2 - 2^-10) · 2^62.
    ("ITOF of a signaling NaN's bits converts the integer", [SN], 0, "ITOF", [0x43DFFC0000000000], 0, None),
    ("SCALE10 MAX, -650 is +0", [MAX, d(-650.0)], 0, "SCALE10", [0], 0, None),
    # DIGITS n: the digits in BCD from bit 63 down, then e.
    ("DIGITS 3 of 123.456", [d(123.456)], 0, "DIGITS 3", [0x1230000000000000, d(2.0)], 0, None),
    ("DIGITS 1 of 9.6 carries to 1e1", [d(9.6)], 0, "DIGITS 1", [0x1000000000000000, d(1.0)], 0, None),
    ("DIGITS 3 of -9.996 carries to 1.00e1", [d(-9.996)], 0, "DIGITS 3", [0x1000000000000000, d(1.0)], 0, None),
    ("DIGITS 15 of 0.1", [d(0.1)], 0, "DIGITS 15", [0x1000000000000000, d(-1.0)], 0, None),
    # π = 3.14159265358979|32...
    ("DIGITS 15 of π", [0x400921FB54442D18], 0, "DIGITS 15", [0x3141592653589790, 0], 0, None),
    # MAX = 1.79769313486231|57e308; 308 = 0x134 = 1.203125 · 2^8.
    ("DIGITS 15 of MAX", [MAX], 0, "DIGITS 15", [0x1797693134862320, 0x4073400000000000], 0, None),
    # 2^-1074 = 4.94065645841246|54e-324; -324 = -1.265625 · 2^8.
    ("DIGITS 15 of 2^-1074", [MINSUB], 0, "DIGITS 15", [0x4940656458412470, 0xC074400000000000], 0, None),
    ("DIGITS 2 of -0", [NZ], 0, "DIGITS 2", [0, 0], 0, None),
    ("DIGITS 0", [d(1.0)], 0, "DIGITS", [N, N], INVALID, None),
    ("DIGITS 16", [d(1.0)], 0, "DIGITS 16", [N, N], INVALID, None),
    ("DIGITS 1 of inf", [INF], 0, "DIGITS 1", [N, N], INVALID, None),
    ("DIGITS 15 of 16 values", SIXTEEN, 0, "DIGITS 15", SIXTEEN[1:15] + [0x1600000000000000, d(1.0)], STACK, None),
    # FROMBCD.
    ("FROMBCD 0x123", [0x123], 0, "FROMBCD", [d(123.0)], 0, None),
    ("FROMBCD of 0 is +0", [0], 0, "FROMBCD", [0], 0, None),
    ("FROMBCD of a 1 in bits 63..60 is 1e15", [0x1000000000000000], 0, "FROMBCD", [d(1e15)], 0, None),
    # 9999999999999999 lies halfway between 9999999999999998 and 1e16,
    # whose significands are odd and even: 1e16.
    ("FROMBCD of 16 nines is a tie, to 1e16", [0x9999999999999999], 0, "FROMBCD", [d(1e16)], 0, None),
    ("FROMBCD of a digit 0xA", [0xA], 0, "FROMBCD", [N], INVALID, None),
    # GETEXP and GETMANT.
    ("GETEXP 0", [0], 0, "GETEXP", [NINF], DIVZERO, None),
    ("GETEXP -0", [NZ], 0, "GETEXP", [NINF], DIVZERO, None),
    ("GETEXP 2^-1074", [MINSUB], 0, "GETEXP", [d(-1074.0)], 0, None),
    ("GETEXP -3", [d(-3.0)], 0, "GETEXP", [d(1.0)], 0, None),
    ("GETEXP 0.75", [d(0.75)], 0, "GETEXP", [d(-1.0)], 0, None),
    ("GETEXP -inf", [NINF], 0, "GETEXP", [INF], 0, None),
    ("GETEXP of a quiet NaN", [QN], 0, "GETEXP", [N], 0, None),
    ("GETMANT -3", [d(-3.0)], 0, "GETMANT", [d(-1.5)], 0, None),
    ("GETMANT 0.75", [d(0.75)], 0, "GETMANT", [d(1.5)], 0, None),
    ("GETMANT 2^-1074", [MINSUB], 0, "GETMANT", [d(1.0)], 0, None),
    ("GETMANT -0", [NZ], 0, "GETMANT", [NZ], 0, None),
    ("GETMANT -inf", [NINF], 0, "GETMANT", [NINF], 0, None),
    ("GETMANT of a signaling NaN", [SN], 0, "GETMANT", [N], INVALID, None),
]

REGS = {"X_LO": X_LO, "X_HI": X_HI, "X_S": X_S, "X_W": X_W, "CMD": CMD, "STATUS": STATUS, "REL": REL, "7": 7}


def command_word(text: str) -> int:
    """A command by name, as "ADD", "ADD.S", or "PICK 15"."""
    parts = text.split()
    name, s = (parts[0][:-2], 1) if parts[0].endswith(".S") else (parts[0], 0)
    n = int(parts[1], 0) if len(parts) > 1 else 0
    return NUMBERS[name] | n << 8 | s << 16


def run_case(case: Case) -> None:
    why, before, flags, access, after, flags_after, want = case
    fpu = FPU(before, flags)
    parts = access.split()
    got: Optional[int] = None
    if parts[0] == "r":
        got = fpu.read(REGS[parts[1]])
    elif parts[0] == "w":
        fpu.write(REGS[parts[1]], int(parts[2], 0))
    elif parts[0] == "cmd":
        fpu.write(CMD, int(parts[1], 0))
    else:
        fpu.write(CMD, command_word(access))
    if fpu.state() != (tuple(after), flags_after) or got != want:
        stack = " ".join(f"{v:016X}" for v in fpu.stack)
        fail(f"{why}: {access} gives [{stack}] flags {fpu.flags:X} read {got!r}")


# 2. Against the host's doubles.

SPECIALS = [
    0, NZ, MINSUB, MINSUB | NZ, 0x000FFFFFFFFFFFFF, 0x0010000000000000, d(0.5), d(1.0), d(-1.0), d(1.5),
    d(2.0), d(3.0), d(0.1), d(1e300), d(-1e-300), MAX, MAX | NZ, INF, NINF, QN, SN, d(2.0**53), d(2.0**63),
    d(-(2.0**63)), d(2.0**64), d(2147483647.5), d(-2147483648.5), 0x3FDFFFFFFFFFFFFF, d(4.5), d(-2.5),
]


def random_doubles(rnd: random.Random, count: int) -> List[int]:
    out = list(SPECIALS)
    while len(out) < count:
        kind = rnd.randrange(4)
        if kind == 0:
            out.append(rnd.getrandbits(64))  # any bits, so any exponent
        elif kind == 1:
            # Near 1, so that sums cancel and products round.
            out.append(rnd.getrandbits(52) | (rnd.randint(1013, 1033) << 52) | (rnd.getrandbits(1) << 63))
        elif kind == 2:
            # Near the bottom, subnormals and the smallest normals.
            out.append(rnd.getrandbits(54) | (rnd.getrandbits(1) << 63))
        else:
            # Whole numbers and halves.
            out.append(d(rnd.randint(-(10**6), 10**6) / 2))
    return out


def same(model: int, host: float, why: str) -> None:
    if math.isnan(host):
        if model != N:
            fail(f"{why}: the model gives {model:016X}, the host a NaN")
    elif model != d(host):
        fail(f"{why}: the model gives {model:016X}, the host {d(host):016X}")


def against_host() -> None:
    rnd = random.Random(161)
    vals = random_doubles(rnd, 200)
    pairs = [(a, b) for a in SPECIALS for b in SPECIALS]
    pairs += [(rnd.choice(vals), rnd.choice(vals)) for _ in range(6000)]
    # Sums and differences of close values, which cancel.
    for _ in range(2000):
        a = rnd.choice(vals)
        pairs.append((a, (a + rnd.randint(-3, 3)) & F64.mask))
    for a, b in pairs:
        x, y = h(a), h(b)
        why = f"{a:016X} {b:016X}"
        same(F64.add(a, b)[0], x + y, "ADD " + why)
        same(F64.sub(a, b)[0], x - y, "SUB " + why)
        same(F64.mul(a, b)[0], x * y, "MUL " + why)
        if y != 0:
            same(F64.div(a, b)[0], x / y, "DIV " + why)
        try:
            host_fmod = math.fmod(x, y)
        except ValueError:
            host_fmod = math.nan
        same(COMMANDS[0x1D].run([a, b], 0)[0][0], host_fmod, "FMOD " + why)
        c = F64.compare(a, b)
        want = None if math.isnan(x) or math.isnan(y) else -1 if x < y else 1 if x > y else 0
        if c != want:
            fail(f"compare {why}: {c} against {want}")
    for a in vals + [rnd.getrandbits(64) for _ in range(3000)]:
        x = h(a)
        why = f"{a:016X}"
        try:
            same(F64.sqrt(a)[0], math.sqrt(x), "SQRT " + why)
        except ValueError:
            same(F64.sqrt(a)[0], math.nan, "SQRT " + why)
        to_binary32(a, x)
        to_integers(a, x)
    for _ in range(3000):
        i = rnd.getrandbits(rnd.choice([8, 32, 53, 54, 63, 64]))
        same(COMMANDS[0x29].run([i], 0)[0][0], float(i), f"UTOF {i}")
        same(COMMANDS[0x28].run([i], 0)[0][0], float(s64(i)), f"ITOF {i}")


def to_binary32(a: int, x: float) -> None:
    """ROUND32 and a read of X_S, against the host's conversion."""
    fpu = FPU([a])
    try:
        host = struct.unpack("<I", struct.pack("<f", x))[0]
        host_flags = 0
    except OverflowError:
        host = 0x7F800000 | (0x80000000 if x < 0 else 0)
        host_flags = OVERFLOW
    if math.isnan(x):
        host = 0x7FC00000
    if fpu.read(X_S) != host:
        fail(f"X_S of {a:016X}: {fpu.read(X_S):08X} against {host:08X}")
    r, f = COMMANDS[0x19].run([a], 0)
    if r[0] != F64.convert(host, F32)[0] or (f & OVERFLOW) != host_flags:
        fail(f"ROUND32 of {a:016X}: {r[0]:016X}, flags {f:X}")


def to_integers(a: int, x: float) -> None:
    """The commands to a whole number, FTOI, FTOU, and X_W."""
    if math.isfinite(x):
        for name, host in (
            ("FLOOR", math.floor(x)),
            ("CEIL", math.ceil(x)),
            ("TRUNC", math.trunc(x)),
            ("NEAREST", round(x)),  # Python's round is ties to even
            ("ROUND", int(decimal.Decimal(x).to_integral_value(decimal.ROUND_HALF_UP))),
        ):
            r = COMMANDS[NUMBERS[name]].run([a], 0)[0][0]
            # A zero takes the sign of X, which the host's int has not.
            want = d(math.copysign(0.0, x)) if host == 0 else d(float(host))
            if r != want:
                fail(f"{name} of {a:016X}: {r:016X} against {want:016X}")
        t = math.trunc(x)
        for name, lo, hi in (("FTOI", -(1 << 63), (1 << 63) - 1), ("FTOU", 0, (1 << 64) - 1)):
            rs, f = COMMANDS[NUMBERS[name]].run([a], 0)
            want = max(lo, min(hi, t)) & F64.mask
            if rs[0] != want or (f == INVALID) != (t < lo or t > hi):
                fail(f"{name} of {a:016X}: {rs[0]:016X} flags {f:X}")
        w = max(-(1 << 31), min((1 << 31) - 1, t)) & 0xFFFFFFFF
    else:
        w = 0 if math.isnan(x) else 0x7FFFFFFF if x > 0 else 0x80000000
    if FPU([a]).read(X_W) != w:
        fail(f"X_W of {a:016X}: {FPU([a]).read(X_W):08X} against {w:08X}")


# 3. Exhaustive at a small width.


class BruteForce:
    """Rounding to nearest, ties to even, by a search of every value of a
    format, independent of Format.round. A virtual value 2^(emax+1) above
    the largest stands for the infinity: its bits are those of the
    infinity, whose fraction is even, so a tie with the largest value,
    whose fraction is odd, goes to it."""

    def __init__(self, fmt: Format) -> None:
        self.fmt = fmt
        pos = [a for a in fmt.finite_values() if not fmt.is_neg(a)]
        self.values = [fmt.value(a) for a in pos] + [pow2(fmt.emax + 1)]
        self.bits = pos + [fmt.inf]

    def nearest(self, q: Fraction) -> int:
        mag = abs(q)
        if mag >= self.values[-1]:
            i = len(self.values) - 1
        else:
            i = bisect.bisect_left(self.values, mag)
            if self.values[i] != mag:
                lo, hi = self.values[i - 1], self.values[i]
                if mag - lo < hi - mag or (mag - lo == hi - mag and self.bits[i - 1] & 1 == 0):
                    i -= 1
        return self.bits[i] | (self.fmt.sign if q < 0 else 0)

    def toward_zero(self, q: Fraction) -> int:
        i = bisect.bisect_right(self.values, abs(q)) - 1
        return self.bits[i] | (self.fmt.sign if q < 0 else 0)

    def sqrt(self, q: Fraction) -> int:
        """√q to nearest: the values' midpoints compared by their squares."""
        best = 0
        for j in range(len(self.values) - 1):
            mid = (self.values[j] + self.values[j + 1]) / 2
            if mid * mid < q or (mid * mid == q and self.bits[j] & 1):
                best = j + 1
        return self.bits[best]


def exhaustive(fmt: Format) -> None:
    brute = BruteForce(fmt)
    finite = fmt.finite_values()
    zero_sign: Dict[str, Callable[[int, int], bool]] = {
        "add": lambda a, b: fmt.is_neg(a) and fmt.is_neg(b),
        "sub": lambda a, b: fmt.is_neg(a) and not fmt.is_neg(b),
        "mul": lambda a, b: fmt.is_neg(a) != fmt.is_neg(b),
        "div": lambda a, b: fmt.is_neg(a) != fmt.is_neg(b),
    }
    exact: Dict[str, Callable[[Fraction, Fraction], Fraction]] = {
        "add": lambda x, y: x + y,
        "sub": lambda x, y: x - y,
        "mul": lambda x, y: x * y,
        "div": lambda x, y: x / y,
    }
    ops: Dict[str, Callable[[int, int], Tuple[int, int]]] = {
        "add": fmt.add,
        "sub": fmt.sub,
        "mul": fmt.mul,
        "div": fmt.div,
    }
    for a in finite:
        va = fmt.value(a)
        for b in finite:
            vb = fmt.value(b)
            for name, op in ops.items():
                if name == "div" and vb == 0:
                    continue
                q = exact[name](va, vb)
                if q == 0:
                    want = fmt.sign if zero_sign[name](a, b) else 0
                else:
                    want = brute.nearest(q)
                got, flags = op(a, b)
                over = fmt.is_inf(want)
                if got != want or flags != (OVERFLOW if over else 0):
                    fail(f"{name} at ({fmt.ebits}, {fmt.fbits}): {a:X} {b:X} gives {got:X} {flags:X}, brute force {want:X}")
        if va > 0:
            if fmt.sqrt(a)[0] != brute.sqrt(va):
                fail(f"sqrt at ({fmt.ebits}, {fmt.fbits}): {a:X}")
            # Toward zero: the largest value whose square is at most va.
            want = max(i for i in range(len(brute.values) - 1) if brute.values[i] ** 2 <= va)
            if fmt.sqrt(a, toward_zero=True)[0] != brute.bits[want]:
                fail(f"sqrt toward zero at ({fmt.ebits}, {fmt.fbits}): {a:X}")
            del want


def double_rounding(narrow: Format, wide: Format) -> None:
    """The S forms: an operation on two narrow values in the wide format,
    with p_wide >= 2 · p_narrow + 2, and then rounded to the narrow
    format, gives the narrow result, with the same flags."""
    finite = narrow.finite_values()
    w = {a: wide.convert(a, narrow)[0] for a in finite}
    for a in finite:
        for b in finite:
            for name in ("add", "sub", "mul", "div"):
                direct = getattr(narrow, name)(a, b)
                r, f = getattr(wide, name)(w[a], w[b])
                r2, f2 = narrow.convert(r, wide)
                twice = (r2, f | f2)
                if direct != twice:
                    fail(f"S {name}: {a:X} {b:X}: {direct} against {twice}")
        r, f = wide.sqrt(w[a])
        r2, f2 = narrow.convert(r, wide)
        if narrow.sqrt(a) != (r2, f | f2):
            fail(f"S sqrt: {a:X}")


# 4. Exact arithmetic.


def constants() -> None:
    """Each constant against 60 digits of decimal. A decimal value within
    1e-55 of the number rounds as the number does, unless it lies that
    close to a midpoint between two doubles, which the test checks."""
    decimal.getcontext().prec = 60
    D = decimal.Decimal
    pi = machin_pi()
    numbers = [
        D(0), D(1), D(10), pi, D(1).exp(), D(2).ln(), D(10).ln(), D(2).log10(),
        1 / pi, D(1) / 10, pi / 2, 2 * pi, 1 / D(2).ln(), D(1).exp().log10(), D(10).ln() / D(2).ln(), D(2).sqrt(),
    ]
    for n, (bits, num) in enumerate(zip(CONSTANTS, numbers)):
        q = Fraction(num)
        if F64.round(q)[0] != bits:
            fail(f"CONST {n}: {bits:016X} against {F64.round(q)[0]:016X}")
        if q != 0:
            ulp = pow2(max(floor_log2(abs(q)), F64.emin) - 52)
            off = (abs(q) - abs(F64.value(bits))) / ulp
            if abs(abs(off) - Fraction(1, 2)) < Fraction(1, 10**40):
                fail(f"CONST {n}: too close to a midpoint for 60 digits")


def machin_pi() -> decimal.Decimal:
    """π = 16 atan(1/5) - 4 atan(1/239), to the precision of the context."""

    def atan_inv(x: int) -> decimal.Decimal:
        total = term = decimal.Decimal(1) / x
        k = 1
        while True:
            term = -term / (x * x)
            nxt = total + term / (2 * k + 1)
            if nxt == total:
                return total
            total, k = nxt, k + 1

    return 16 * atan_inv(5) - 4 * atan_inv(239)


def isqrt_check(rnd: random.Random) -> None:
    run = COMMANDS[NUMBERS["ISQRT"]].run
    for _ in range(3000):
        # Any double from 0 to 2^106, whole or not, and squares near it.
        a = rnd.getrandbits(52) | rnd.randint(0, 1023 + 105) << 52
        if rnd.randrange(3) == 0:
            n = rnd.getrandbits(rnd.randint(1, 26)) | 1
            a = d(float(n * n + rnd.choice([-1, 0, 1])))
        x = F64.value(a)
        want = math.isqrt(x.numerator // x.denominator)
        got = run([a], 0)[0][0]
        if got != d(float(want)):
            fail(f"ISQRT of {a:016X}: {got:016X} against {want}")


def ulps(r: int, exact: Fraction) -> Fraction:
    e = max(floor_log2(abs(exact)), F64.emin)
    return abs(F64.value(r) - exact) / pow2(e - 52)


def scale10_check(rnd: random.Random) -> None:
    """SCALE10 is correctly rounded for k <= 22, and within a bound
    beyond, for normal results. The bound is what the samples here give,
    0.63 ulp near 10^-307, where the low parts are subnormal: §11.3 will
    state a proven one."""
    worst = Fraction(0)
    for _ in range(3000):
        y = rnd.getrandbits(52) | rnd.randint(900, 1150) << 52 | rnd.getrandbits(1) << 63
        k = rnd.randint(-22, 22) if rnd.randrange(3) == 0 else rnd.randint(-650, 650)
        r, _ = scale10(y, k)
        exact = F64.value(y) * Fraction(10) ** k
        if abs(k) <= 22:
            if r != F64.round(exact)[0]:
                fail(f"SCALE10 {y:016X}, {k}: not correctly rounded")
        elif F64.is_finite(r) and abs(exact) >= pow2(-1022):
            worst = max(worst, ulps(r, exact))
            if worst > Fraction(65, 100):
                fail(f"SCALE10 {y:016X}, {k}: {float(ulps(r, exact)):.3f} ulp")
                return


def fifteen_digits(rnd: random.Random) -> None:
    """A constant of 15 digits, read through FROMBCD and SCALE10, and
    printed through DIGITS 15, comes back."""
    for _ in range(1500):
        digs = rnd.randint(10**14, 10**15 - 1)
        e = rnd.randint(-307, 307)
        fpu = FPU()
        bcd = int(str(digs), 16) << 4
        fpu.write(X_LO, bcd & 0xFFFFFFFF)
        fpu.write(X_HI, bcd >> 32)
        fpu.write(CMD, command_word("FROMBCD"))
        fpu.write(X_W, e - 15)
        fpu.write(CMD, command_word("SCALE10"))
        fpu.write(CMD, command_word("DIGITS 15"))
        exp = h(fpu.x())
        fpu.write(CMD, command_word("DROP"))
        back = fpu.read(X_HI) << 32 | fpu.read(X_LO)
        if (back, exp, fpu.flags) != (bcd, float(e), 0):
            fail(f"15 digits: {digs}e{e - 14} comes back as {back:016X}e{exp}")


def main() -> None:
    for case in CASES:
        run_case(case)
    print(f"{len(CASES)} hand-checked cases")
    against_host()
    print("the host's doubles")
    exhaustive(Format(4, 3))
    double_rounding(Format(4, 3), Format(6, 9))
    print("exhaustive at (4, 3), and through (6, 9)")
    rnd = random.Random(1612)
    constants()
    isqrt_check(rnd)
    scale10_check(rnd)
    fifteen_digits(rnd)
    print("exact arithmetic")
    if FAILURES:
        sys.exit(1)
    print("PASS fpu_model")


if __name__ == "__main__":
    main()
