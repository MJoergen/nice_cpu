#!/usr/bin/env python3
"""A reference model of the floating-point unit of doc/SYSTEM.md §11, phase 1.

The model is the oracle of the FPU's tests: the emulator, tb_fpu, both
cores, and the board replay what it computes. So it shares nothing with
them. It computes every result exactly, with fractions.Fraction, and
rounds it itself. It never uses the host's floats, whose NaNs differ
between an x86 and an ARM host, and which have no fma in Python 3.12.

Format is any binary interchange format, with the widths of the
exponent and of the fraction as parameters, so the arithmetic can be
checked exhaustively at a small width. FPU is the device of §11 at
binary64, with the binary32 view.

Where §11 leaves a choice open, the model takes the reading below:

- SCALE10 for k > 22 multiplies pairs as mul_pair() does, and adds the
  high and the low part at the end. The table is TEN_PAIRS.
"""

from __future__ import annotations

from fractions import Fraction
from math import isqrt
from typing import Callable, Dict, List, Optional, Tuple

# The flags, as bits 11..8 of FPU_STATUS hold them, shifted down by 8.
INVALID = 1
DIVZERO = 2
OVERFLOW = 4
STACK = 8

# Results, with the flags that the operation sets.
Result = Tuple[int, int]

DEPTH = 16


def pow2(k: int) -> Fraction:
    return Fraction(1 << k) if k >= 0 else Fraction(1, 1 << -k)


def floor_log2(x: Fraction) -> int:
    """The e with 2^e <= x < 2^(e+1), for x > 0."""
    n, d = x.numerator, x.denominator
    e = n.bit_length() - d.bit_length()
    if (n << max(-e, 0)) < (d << max(e, 0)):
        e -= 1
    return e


def trunc(x: Fraction) -> int:
    """x rounded toward zero."""
    q = abs(x.numerator) // x.denominator
    return -q if x < 0 else q


class Format:
    """An IEEE 754 binary format with ebits of exponent and fbits of
    fraction. A value is its bit pattern, an int."""

    def __init__(self, ebits: int, fbits: int) -> None:
        self.ebits = ebits
        self.fbits = fbits
        self.width = 1 + ebits + fbits
        self.bias = (1 << (ebits - 1)) - 1
        self.emin = 1 - self.bias
        self.emax = self.bias
        self.sign = 1 << (ebits + fbits)
        self.inf = ((1 << ebits) - 1) << fbits
        self.qnan = self.inf | (1 << (fbits - 1))
        self.max_finite = self.inf - 1
        self.mask = (1 << self.width) - 1

    # Classes.

    def is_neg(self, a: int) -> bool:
        return a & self.sign != 0

    def is_nan(self, a: int) -> bool:
        return a & ~self.sign & self.mask > self.inf

    def is_snan(self, a: int) -> bool:
        return self.is_nan(a) and a & (1 << (self.fbits - 1)) == 0

    def is_inf(self, a: int) -> bool:
        return a & ~self.sign & self.mask == self.inf

    def is_zero(self, a: int) -> bool:
        return a & ~self.sign & self.mask == 0

    def is_finite(self, a: int) -> bool:
        return a & ~self.sign & self.mask < self.inf

    def value(self, a: int) -> Fraction:
        """The exact value of a finite a."""
        assert self.is_finite(a)
        exp = (a >> self.fbits) & ((1 << self.ebits) - 1)
        frac = a & ((1 << self.fbits) - 1)
        if exp == 0:
            v = frac * pow2(self.emin - self.fbits)
        else:
            v = (frac | (1 << self.fbits)) * pow2(exp - self.bias - self.fbits)
        return -v if self.is_neg(a) else v

    def finite_values(self) -> List[int]:
        """Every finite value, for the exhaustive tests of a small format."""
        return [a for a in range(1 << self.width) if self.is_finite(a)]

    # Rounding.

    def round(self, x: Fraction, zero_neg: bool = False, toward_zero: bool = False) -> Result:
        """x rounded to nearest, ties to even, or toward zero, with
        subnormals. An exact zero has the sign zero_neg; any other x keeps
        its sign, also when it rounds to a zero. Rounding to nearest
        beyond the largest value gives an infinity and the overflow flag."""
        if x == 0:
            return (self.sign if zero_neg else 0), 0
        sign = self.sign if x < 0 else 0
        mag = abs(x)
        e = max(floor_log2(mag), self.emin)
        sh = e - self.fbits  # the unit in the last place is 2^sh
        num = mag.numerator << max(-sh, 0)
        den = mag.denominator << max(sh, 0)
        m, r = divmod(num, den)
        if not toward_zero and (2 * r > den or (2 * r == den and m & 1)):
            m += 1
        if m >> (self.fbits + 1):
            m >>= 1
            e += 1
        if e > self.emax:
            if toward_zero:
                return sign | self.max_finite, 0
            return sign | self.inf, OVERFLOW
        if m >> self.fbits == 0:
            return sign | m, 0  # a subnormal, or a zero
        return sign | ((e + self.bias) << self.fbits) | (m & ((1 << self.fbits) - 1)), 0

    def round_sqrt(self, x: Fraction, toward_zero: bool = False) -> Result:
        """√x rounded, for x > 0. The square root is computed to g bits
        below the finest unit in the last place that the result can have,
        and, if it is not exact, replaced by the midpoint of the interval
        of 2^-g that holds it. No boundary of the rounding lies inside that
        interval, so the midpoint rounds as √x does."""
        er = floor_log2(x) // 2
        g = self.fbits + 3 - min(er, self.emin)
        t = x * pow2(2 * g)
        whole = t.numerator // t.denominator
        s = isqrt(whole)
        if s * s == whole and t.denominator == 1:
            return self.round(s * pow2(-g), toward_zero=toward_zero)
        return self.round((2 * s + 1) * pow2(-g - 1), toward_zero=toward_zero)

    def from_int(self, i: int) -> int:
        """The integer i, rounded. 0 gives +0."""
        return self.round(Fraction(i))[0]

    def convert(self, a: int, src: Format) -> Result:
        """a of format src, in this format. A NaN becomes the canonical
        NaN, and a signaling one sets the invalid flag."""
        if src.is_nan(a):
            return self.qnan, INVALID if src.is_snan(a) else 0
        sign = self.sign if src.is_neg(a) else 0
        if src.is_inf(a):
            return sign | self.inf, 0
        return self.round(src.value(a), zero_neg=sign != 0)

    # Operations. Each returns the result and the flags it sets.

    def nan(self, *ops: int) -> Result:
        """The canonical NaN, for an operation with a NaN operand."""
        return self.qnan, INVALID if any(self.is_snan(a) for a in ops) else 0

    def neg(self, a: int) -> int:
        return a ^ self.sign

    def abs(self, a: int) -> int:
        return a & ~self.sign

    def add(self, a: int, b: int) -> Result:
        if self.is_nan(a) or self.is_nan(b):
            return self.nan(a, b)
        if self.is_inf(a) or self.is_inf(b):
            if self.is_inf(a) and self.is_inf(b) and self.is_neg(a) != self.is_neg(b):
                return self.qnan, INVALID
            return (a if self.is_inf(a) else b), 0
        both_neg = self.is_neg(a) and self.is_neg(b)
        return self.round(self.value(a) + self.value(b), zero_neg=both_neg)

    def sub(self, a: int, b: int) -> Result:
        if self.is_nan(b):
            return self.nan(a, b)
        return self.add(a, self.neg(b))

    def mul(self, a: int, b: int) -> Result:
        if self.is_nan(a) or self.is_nan(b):
            return self.nan(a, b)
        neg = self.is_neg(a) != self.is_neg(b)
        if self.is_inf(a) or self.is_inf(b):
            if self.is_zero(a) or self.is_zero(b):
                return self.qnan, INVALID
            return (self.sign if neg else 0) | self.inf, 0
        return self.round(self.value(a) * self.value(b), zero_neg=neg)

    def div(self, a: int, b: int) -> Result:
        if self.is_nan(a) or self.is_nan(b):
            return self.nan(a, b)
        neg = self.is_neg(a) != self.is_neg(b)
        sign = self.sign if neg else 0
        if self.is_inf(a):
            if self.is_inf(b):
                return self.qnan, INVALID
            return sign | self.inf, 0
        if self.is_inf(b):
            return sign, 0
        if self.is_zero(b):
            if self.is_zero(a):
                return self.qnan, INVALID
            return sign | self.inf, DIVZERO
        return self.round(self.value(a) / self.value(b), zero_neg=neg)

    def sqrt(self, a: int, toward_zero: bool = False) -> Result:
        if self.is_nan(a):
            return self.nan(a)
        if self.is_zero(a):
            return a, 0
        if self.is_neg(a):
            return self.qnan, INVALID
        if self.is_inf(a):
            return a, 0
        return self.round_sqrt(self.value(a), toward_zero=toward_zero)

    def fma(self, a: int, b: int, c: int) -> Result:
        """a · b + c, rounded once, for finite operands."""
        x = self.value(a) * self.value(b) + self.value(c)
        prod_neg = self.is_neg(a) != self.is_neg(b)
        prod_zero = self.is_zero(a) or self.is_zero(b)
        zero_neg = prod_zero and self.is_zero(c) and prod_neg and self.is_neg(c)
        return self.round(x, zero_neg=zero_neg)

    def compare(self, a: int, b: int) -> Optional[int]:
        """-1, 0, or 1 as a < b, a = b, or a > b, and None if unordered."""
        if self.is_nan(a) or self.is_nan(b):
            return None
        x, y = self.key(a), self.key(b)
        return -1 if x < y else 1 if x > y else 0

    def key(self, a: int) -> Tuple[int, Fraction]:
        """a as a key that sorts as the values do, for a that is not a NaN."""
        if self.is_inf(a):
            return (-1 if self.is_neg(a) else 1), Fraction(0)
        return 0, self.value(a)

    def to_integral(self, a: int, how: str) -> Result:
        """a rounded to a whole number: how is floor, ceil, trunc, even,
        or away. A result of zero has the sign of a."""
        if self.is_nan(a):
            return self.nan(a)
        if not self.is_finite(a) or self.is_zero(a):
            return a, 0
        x = self.value(a)
        fl = x.numerator // x.denominator
        frac = x - fl
        if how == "floor":
            i = fl
        elif how == "ceil":
            i = fl + (frac != 0)
        elif how == "trunc":
            i = trunc(x)
        elif how == "even":
            i = fl + (frac > Fraction(1, 2) or (frac == Fraction(1, 2) and fl & 1 == 1))
        elif how == "away":
            i = trunc(x + Fraction(1, 2)) if x > 0 else trunc(x - Fraction(1, 2))
        else:
            raise ValueError(how)
        return self.round(Fraction(i), zero_neg=self.is_neg(a))

    def to_int(self, a: int, bits: int, signed: bool) -> Tuple[int, int]:
        """a rounded toward zero, as an integer of bits bits, saturated,
        and 0 for a NaN. A NaN and a value out of range set the invalid
        flag."""
        lo = -(1 << (bits - 1)) if signed else 0
        hi = (1 << (bits - 1)) - 1 if signed else (1 << bits) - 1
        if self.is_nan(a):
            return 0, INVALID
        if self.is_inf(a):
            return (lo if self.is_neg(a) else hi), INVALID
        i = trunc(self.value(a))
        if i < lo:
            return lo, INVALID
        if i > hi:
            return hi, INVALID
        return i, 0


F64 = Format(11, 52)
F32 = Format(8, 23)

CANONICAL_NAN = F64.qnan  # 0x7FF80000_00000000
NAN32 = F32.qnan  # 0x7FC00000


def f64(x: Fraction) -> int:
    """The binary64 value nearest x."""
    return F64.round(x)[0]


def s32(w: int) -> int:
    """A word as a signed 32-bit integer."""
    w &= 0xFFFFFFFF
    return w - (1 << 32) if w >> 31 else w


def s64(w: int) -> int:
    w &= (1 << 64) - 1
    return w - (1 << 64) if w >> 63 else w


# The constant table of CONST n, §11.3, each the binary64 value nearest
# the number. The test checks them against decimal.
CONSTANTS = [
    0x0000000000000000,  # 0
    0x3FF0000000000000,  # 1
    0x4024000000000000,  # 10
    0x400921FB54442D18,  # π
    0x4005BF0A8B145769,  # e
    0x3FE62E42FEFA39EF,  # ln 2
    0x40026BB1BBB55516,  # ln 10
    0x3FD34413509F79FF,  # log10 2
    0x3FD45F306DC9C883,  # 1/π
    0x3FB999999999999A,  # 1/10
    0x3FF921FB54442D18,  # π/2
    0x401921FB54442D18,  # 2π
    0x3FF71547652B82FE,  # log2 e
    0x3FDBCB7B1526E50E,  # log10 e
    0x400A934F0979A371,  # log2 10
    0x3FF6A09E667F3BCD,  # √2
]


def ten_pair(m: int) -> Tuple[int, int]:
    """10^m as a pair of binary64 values: the high part, the value nearest
    10^m, and the low part, the value nearest what remains."""
    exact = Fraction(10) ** m
    hi = f64(exact)
    return hi, f64(exact - F64.value(hi))


# SCALE10's table: TEN_PAIRS[0][i] is 10^(2^i), and TEN_PAIRS[1][i] is
# 10^(-2^i), for i from 0 to 8.
TEN_PAIRS = [[ten_pair(1 << i) for i in range(9)], [ten_pair(-(1 << i)) for i in range(9)]]


def mul_pair(a: Tuple[int, int], b: Tuple[int, int]) -> Tuple[int, int]:
    """Dekker's product of two pairs, each step one binary64 operation:

        p = ah · bh
        e = fma(ah, bh, -p)          the exact error of p
        e = e + ah · bl
        e = e + al · bh
        h = p + e
        l = e - (h - p)

    If p or h is infinite, the product is that infinity, with a low part
    of 0."""
    ah, al = a
    bh, bl = b
    p = F64.mul(ah, bh)[0]
    if F64.is_inf(p):
        return p, 0
    e = F64.fma(ah, bh, F64.neg(p))[0]
    e = F64.add(e, F64.mul(ah, bl)[0])[0]
    e = F64.add(e, F64.mul(al, bh)[0])[0]
    h = F64.add(p, e)[0]
    if F64.is_inf(h):
        return h, 0
    return h, F64.sub(e, F64.sub(h, p)[0])[0]


def scale10(y: int, k: int) -> Result:
    """Y · 10^k for a finite nonzero Y, by SCALE10's sequence (§11.3)."""
    neg = k < 0
    k = min(abs(k), 650)
    if k <= 22:
        p = f64(Fraction(10) ** k)
        return F64.div(y, p) if neg else F64.mul(y, p)
    table = TEN_PAIRS[1 if neg else 0]
    r = (y, 0)
    for i in range(9):
        if k >> i & 1:
            r = mul_pair(r, table[i])
    if k >> 9 & 1:
        r = mul_pair(r, table[8])
        r = mul_pair(r, table[8])
    if F64.is_inf(r[0]):
        return r[0], OVERFLOW
    return F64.add(r[0], r[1])


def floor_log10(x: Fraction) -> int:
    """The e with 10^e <= x < 10^(e+1), for x > 0."""
    e = (floor_log2(x) * 30103) // 100000  # log10 2 = 0.30103, low by < 1
    while Fraction(10) ** (e + 1) <= x:
        e += 1
    while Fraction(10) ** e > x:
        e -= 1
    return e


def digits(a: int, n: int) -> Tuple[int, int]:
    """DIGITS n of a finite nonzero a: the digits as a whole number D,
    and the exponent e. D is NEAREST of SCALE10 of |a| by n - 1 - e, and
    e is the largest whole number for which D >= 10^(n-1)."""
    ax = F64.abs(a)
    e = floor_log10(F64.value(ax)) + 1
    while True:
        d = F64.to_integral(scale10(ax, n - 1 - e)[0], "even")[0]
        dv = trunc(F64.value(d))
        if dv >= 10 ** (n - 1):
            assert dv < 10**n, "DIGITS: more than n digits"
            return dv, e
        e -= 1


class Command:
    """A command of §11.3: its number, the bits of n it uses, whether S
    applies, the values it pops, and what it computes from them, deeper
    first, with n. It returns the values to push, in the order pushed,
    and the flags."""

    def __init__(
        self,
        name: str,
        pops: int,
        run: Callable[[List[int], int], Tuple[List[int], int]],
        nmask: int = 0,
        s: bool = False,
    ) -> None:
        self.name = name
        self.pops = pops
        self.run = run
        self.nmask = nmask
        self.s = s


def one(op: Callable[[int], Result]) -> Callable[[List[int], int], Tuple[List[int], int]]:
    def run(v: List[int], n: int) -> Tuple[List[int], int]:
        r, f = op(v[0])
        return [r], f

    return run


def two(op: Callable[[int, int], Result]) -> Callable[[List[int], int], Tuple[List[int], int]]:
    def run(v: List[int], n: int) -> Tuple[List[int], int]:
        r, f = op(v[0], v[1])
        return [r], f

    return run


def round32(a: int) -> Result:
    r, f = F32.convert(a, F64)
    return F64.convert(r, F32)[0], f


def isqrt_cmd(a: int) -> Result:
    r, f = F64.sqrt(a, toward_zero=True)
    r2, f2 = F64.to_integral(r, "trunc")
    return r2, f | f2


def sign_cmd(a: int) -> Result:
    if F64.is_nan(a):
        return F64.nan(a)
    if F64.is_zero(a):
        return 0, 0
    return F64.from_int(-1 if F64.is_neg(a) else 1), 0


def min_max(a: int, b: int, want_max: bool) -> Result:
    if F64.is_nan(a) or F64.is_nan(b):
        return F64.nan(a, b)
    c = F64.compare(a, b)
    assert c is not None
    if c == 0:
        # Equal values differ only as zeros of two signs: -0 < +0.
        if want_max:
            return (a if not F64.is_neg(a) else b), 0
        return (a if F64.is_neg(a) else b), 0
    return (a if (c > 0) == want_max else b), 0


def cmp_cmd(v: List[int], n: int) -> Tuple[List[int], int]:
    c = F64.compare(v[0], v[1])
    if c is None:
        return [0], INVALID
    return [F64.from_int(-1) if n >> (c + 1) & 1 else 0], 0


def fmod(y: int, x: int) -> Result:
    if F64.is_nan(y) or F64.is_nan(x):
        return F64.nan(y, x)
    if F64.is_inf(y) or F64.is_zero(x):
        return F64.qnan, INVALID
    if F64.is_inf(x) or F64.is_zero(y):
        return y, 0
    vy, vx = F64.value(y), F64.value(x)
    return F64.round(vy - trunc(vy / vx) * vx, zero_neg=F64.is_neg(y))


def itof(a: int) -> Result:
    return F64.from_int(s64(a)), 0


def utof(a: int) -> Result:
    return F64.from_int(a), 0


def ftoi(a: int) -> Result:
    i, f = F64.to_int(a, 64, True)
    return i & F64.mask, f


def ftou(a: int) -> Result:
    return F64.to_int(a, 64, False)


def word(a: int) -> Optional[int]:
    """An operand of the word operators: a rounded toward zero, if it
    fits a signed 32-bit integer."""
    if not F64.is_finite(a):
        return None
    i = trunc(F64.value(a))
    return i if -(1 << 31) <= i < (1 << 31) else None


def word_op(op: Callable[[int, int], Optional[int]]) -> Callable[[int, int], Result]:
    def run(y: int, x: int) -> Result:
        wy, wx = word(y), word(x)
        if wy is None or wx is None:
            return F64.qnan, INVALID
        r = op(wy, wx)
        if r is None:
            return F64.qnan, INVALID
        return F64.from_int(r), 0

    return run


def shl(y: int, x: int) -> Optional[int]:
    if x < 0:
        return None
    return s32(y << x) if x < 32 else 0


def shr(y: int, x: int) -> Optional[int]:
    if x < 0:
        return None
    return s32((y & 0xFFFFFFFF) >> x) if x < 32 else 0


def idiv(y: int, x: int) -> Optional[int]:
    if x == 0:
        return None
    q = abs(y) // abs(x)
    return -q if (y < 0) != (x < 0) else q


def imod(y: int, x: int) -> Optional[int]:
    q = idiv(y, x)
    return None if q is None else y - q * x


def not_cmd(a: int) -> Result:
    w = word(a)
    if w is None:
        return F64.qnan, INVALID
    return F64.from_int(-w - 1), 0


def const_cmd(v: List[int], n: int) -> Tuple[List[int], int]:
    if n < len(CONSTANTS):
        return [CONSTANTS[n]], 0
    return [F64.qnan], INVALID


def scale_x(x: int, limit: int) -> Optional[int]:
    """The whole X of SCALE2 and SCALE10, with an infinity, and any
    larger X, counted as ±limit. None for a NaN or an X not whole."""
    if F64.is_nan(x):
        return None
    if F64.is_inf(x):
        return -limit if F64.is_neg(x) else limit
    v = F64.value(x)
    if v.denominator != 1:
        return None
    return max(-limit, min(limit, int(v)))


def scale_cmd(limit: int, finite: Callable[[int, int], Result]) -> Callable[[int, int], Result]:
    def run(y: int, x: int) -> Result:
        k = scale_x(x, limit)
        if k is None:
            return F64.qnan, INVALID | F64.nan(y)[1]
        if F64.is_nan(y):
            return F64.nan(y)
        if F64.is_inf(y) or F64.is_zero(y):
            return y, 0
        r, f = finite(y, k)
        # An infinite X sets no overflow flag (§11.3).
        return r, 0 if F64.is_inf(x) else f

    return run


def scale2(y: int, k: int) -> Result:
    return F64.round(F64.value(y) * pow2(k))


def digits_cmd(v: List[int], n: int) -> Tuple[List[int], int]:
    a = v[0]
    if not F64.is_finite(a) or n == 0 or n > 15:
        return [F64.qnan, F64.qnan], INVALID | F64.nan(a)[1]
    if F64.is_zero(a):
        return [0, 0], 0
    d, e = digits(a, n)
    bcd = 0
    for i, c in enumerate(str(d)):
        bcd |= int(c) << (60 - 4 * i)
    return [bcd, F64.from_int(e)], 0


def frombcd(a: int) -> Result:
    v = 0
    for i in range(16):
        c = a >> (60 - 4 * i) & 0xF
        if c > 9:
            return F64.qnan, INVALID
        v = 10 * v + c
    return F64.from_int(v), 0


def getexp(a: int) -> Result:
    if F64.is_nan(a):
        return F64.nan(a)
    if F64.is_zero(a):
        return F64.sign | F64.inf, DIVZERO
    if F64.is_inf(a):
        return F64.inf, 0
    return F64.from_int(floor_log2(abs(F64.value(a)))), 0


def getmant(a: int) -> Result:
    if F64.is_nan(a):
        return F64.nan(a)
    if not F64.is_finite(a) or F64.is_zero(a):
        return a, 0
    x = F64.value(a)
    return F64.round(x * pow2(-floor_log2(abs(x))))


def keep(v: List[int], n: int) -> Tuple[List[int], int]:
    return [], 0


def swap(v: List[int], n: int) -> Tuple[List[int], int]:
    return [v[1], v[0]], 0


COMMANDS: Dict[int, Command] = {
    0x00: Command("NOP", 0, keep),
    0x01: Command("CLEAR", 0, keep, nmask=0x01),  # by FPU.command
    0x02: Command("DUP", 0, keep),  # by FPU.command, a copy
    0x03: Command("DROP", 0, keep, nmask=0xFF),  # by FPU.command
    0x04: Command("SWAP", 2, swap),
    0x05: Command("OVER", 0, keep),  # by FPU.command, a copy
    0x06: Command("PICK", 0, keep, nmask=0xFF),  # by FPU.command, a copy
    0x10: Command("ADD", 2, two(F64.add), s=True),
    0x11: Command("SUB", 2, two(F64.sub), s=True),
    0x12: Command("MUL", 2, two(F64.mul), s=True),
    0x13: Command("DIV", 2, two(F64.div), s=True),
    0x14: Command("SQRT", 1, one(F64.sqrt), s=True),
    0x15: Command("NEG", 1, one(lambda a: (F64.neg(a), 0))),
    0x16: Command("ABS", 1, one(lambda a: (F64.abs(a), 0))),
    0x17: Command("MIN", 2, two(lambda y, x: min_max(y, x, False))),
    0x18: Command("MAX", 2, two(lambda y, x: min_max(y, x, True))),
    0x19: Command("ROUND32", 1, one(round32)),
    0x1A: Command("ISQRT", 1, one(isqrt_cmd)),
    0x1B: Command("SIGN", 1, one(sign_cmd)),
    0x1C: Command("CMP", 2, cmp_cmd, nmask=0x07),
    0x1D: Command("FMOD", 2, two(fmod)),
    0x20: Command("FLOOR", 1, one(lambda a: F64.to_integral(a, "floor"))),
    0x21: Command("CEIL", 1, one(lambda a: F64.to_integral(a, "ceil"))),
    0x22: Command("TRUNC", 1, one(lambda a: F64.to_integral(a, "trunc"))),
    0x23: Command("NEAREST", 1, one(lambda a: F64.to_integral(a, "even"))),
    0x24: Command("ROUND", 1, one(lambda a: F64.to_integral(a, "away"))),
    0x28: Command("ITOF", 1, one(itof)),
    0x29: Command("UTOF", 1, one(utof)),
    0x2A: Command("FTOI", 1, one(ftoi)),
    0x2B: Command("FTOU", 1, one(ftou)),
    0x30: Command("CONST", 0, const_cmd, nmask=0xFF),
    0x38: Command("SCALE2", 2, two(scale_cmd(2100, scale2))),
    0x39: Command("SCALE10", 2, two(scale_cmd(650, scale10))),
    0x3A: Command("DIGITS", 1, digits_cmd, nmask=0xFF),
    0x3B: Command("FROMBCD", 1, one(frombcd)),
    0x3C: Command("GETEXP", 1, one(getexp)),
    0x3D: Command("GETMANT", 1, one(getmant)),
    0x60: Command("AND", 2, two(word_op(lambda y, x: s32(y & x)))),
    0x61: Command("OR", 2, two(word_op(lambda y, x: s32(y | x)))),
    0x62: Command("XOR", 2, two(word_op(lambda y, x: s32(y ^ x)))),
    0x63: Command("NOT", 1, one(not_cmd)),
    0x64: Command("SHL", 2, two(word_op(shl))),
    0x65: Command("SHR", 2, two(word_op(shr))),
    0x66: Command("IDIV", 2, two(word_op(idiv))),
    0x67: Command("MOD", 2, two(word_op(imod))),
}

NUMBERS = {c.name: num for num, c in COMMANDS.items()}

# The registers of §11.1, by their offset from 0xFFFFFF88.
X_LO, X_HI, X_S, X_W, CMD, STATUS, REL = range(7)


class FPU:
    """The device of §11: the stack, bottom first, and the flags."""

    def __init__(self, stack: Optional[List[int]] = None, flags: int = 0) -> None:
        self.stack: List[int] = list(stack or [])
        self.flags = flags

    def state(self) -> Tuple[Tuple[int, ...], int]:
        return tuple(self.stack), self.flags

    def x(self) -> int:
        return self.stack[-1] if self.stack else CANONICAL_NAN

    def y(self) -> int:
        return self.stack[-2] if len(self.stack) >= 2 else CANONICAL_NAN

    def push(self, v: int) -> None:
        if len(self.stack) == DEPTH:
            del self.stack[0]
            self.flags |= STACK
        self.stack.append(v)

    def pop(self, k: int) -> List[int]:
        """k values, deeper first; a value that is not there is the
        canonical NaN, and sets the stack fault."""
        out = []
        for _ in range(k):
            if self.stack:
                out.append(self.stack.pop())
            else:
                out.append(CANONICAL_NAN)
                self.flags |= STACK
        return out[::-1]

    def copy(self, n: int) -> int:
        if n < len(self.stack):
            return self.stack[-1 - n]
        self.flags |= STACK
        return CANONICAL_NAN

    def classify(self) -> int:
        """The class of X, bits 21..16 of FPU_STATUS, shifted down by 16."""
        a = self.x()
        c = 0
        if F64.is_neg(a):
            c |= 1
        if F64.is_zero(a):
            c |= 2
        if F64.is_inf(a):
            c |= 4
        if F64.is_nan(a):
            c |= 8
        if F64.is_finite(a):
            v = F64.value(a)
            if v.denominator == 1:
                c |= 16
            if word(a) is not None:
                c |= 32
        return c

    def read(self, offset: int) -> int:
        """A data read of the register at offset, which changes nothing."""
        if offset == X_LO:
            return self.x() & 0xFFFFFFFF
        if offset == X_HI:
            return self.x() >> 32
        if offset == X_S:
            return F32.convert(self.x(), F64)[0]
        if offset == X_W:
            return F64.to_int(self.x(), 32, True)[0] & 0xFFFFFFFF
        if offset == STATUS:
            return len(self.stack) | self.flags << 8 | self.classify() << 16
        if offset == REL:
            c = F64.compare(self.y(), self.x())
            return 2 if c is None else c & 0xFFFFFFFF
        return 0

    def write(self, offset: int, w: int) -> None:
        w &= 0xFFFFFFFF
        if offset == X_LO:
            self.push(w)
        elif offset == X_HI:
            if self.stack:
                self.stack[-1] = (self.stack[-1] & 0xFFFFFFFF) | w << 32
            else:
                self.flags |= STACK
        elif offset == X_S:
            self.push(F64.convert(w, F32)[0])
        elif offset == X_W:
            self.push(F64.from_int(s32(w)))
        elif offset == CMD:
            self.command(w)
        elif offset == STATUS:
            self.flags = w >> 8 & 0xF

    def command(self, w: int) -> None:
        num, n, s = w & 0xFF, w >> 8 & 0xFF, w >> 16 & 1
        c = COMMANDS.get(num)
        if c is None or w >> 17 or (s and not c.s) or n & ~c.nmask:
            self.flags |= INVALID
            return
        if c.name == "CLEAR":
            self.stack = []
            if n:
                self.flags = 0
            return
        if c.name == "DROP":
            self.pop(n or 1)
            return
        if c.name in ("DUP", "OVER", "PICK"):
            self.push(self.copy({"DUP": 0, "OVER": 1}.get(c.name, n)))
            return
        results, f = c.run(self.pop(c.pops), n)
        if s:
            r, f2 = round32(results[0])
            results, f = [r], f | f2
        self.flags |= f
        for r in results:
            self.push(r)
