"""The sequences of the functions of phase 2 of the FPU, DEVICES.md §11.3.

Each function is a program in a small part of Python, which follows the
C code it is taken from operation by operation, in the order C gives
them. compile_program() turns it into the steps that the FPU runs, and
fpu_model.py runs those steps. The steps are the reference: the
emulator's table and the VHDL's ROM are checked against listing().

A step is the text of a command of §11.3, such as "MUL" or "PICK 2", or
one of the steps that only the sequences have:

    K name      pushes the constant name of CONSTANTS
    PUT n       pops X, and writes it in place of the value n below the
                new X: PUT 0 replaces the new X
    JZ label    pops X, and jumps to label if X is zero
    JMP label   jumps to label
    POLE        an infinite result of finite operands is a division by
                zero, not an overflow
    label:      a place to jump to

The program's values live on the FPU's stack, in a frame above the
operands: a variable has a slot, PICK reads it and PUT writes it, and an
expression computes on top of the frame. The functions of the program
that the function calls, such as sin_k, are inlined, each with a frame
of its own that ends when it returns. A parameter given a constant is
that constant where the callee tests it, so that `if iy == 0` costs no
step.

The program may use: assignments, also of a tuple from a call; if, elif,
and else; return; + - * / and unary -; comparisons, also as values,
-1 for true and 0 for false, as CMP gives them; and, or, and not in a
test; and the calls abs, sqrt, nearest, trunc, getexp, getmant, chop,
itof, band (the command AND), scale2 (SCALE2), and nan(), the canonical
NaN, and pole(), the step POLE.
A name that is not a variable is a constant, and H(0x...) is the value
whose high word that is and whose low word is 0, so that a test of
fdlibm's high word ix, such as ix < 0x3e500000, is the test of the value
|x| < H(0x3e500000). Arithmetic on constants alone is folded, as C does,
which gives the same bits as the operation.
"""

from __future__ import annotations

import ast
import struct
from typing import Dict, List, Optional, Sequence, Tuple, Union


def bits(v: float) -> int:
    return int(struct.unpack("<Q", struct.pack("<d", v))[0])


def value(b: int) -> float:
    return float(struct.unpack("<d", struct.pack("<Q", b))[0])


# The constants of the sequences, by name. Most are the coefficients of
# the C code, which give their values as decimal: the double nearest each.
CONSTANTS: Dict[str, int] = {
    "nan": 0x7FF8000000000000,
    # __sin.c
    "S1": bits(-1.66666666666666324348e-01),
    "S2": bits(8.33333333332248946124e-03),
    "S3": bits(-1.98412698298579493134e-04),
    "S4": bits(2.75573137070700676789e-06),
    "S5": bits(-2.50507602534068634195e-08),
    "S6": bits(1.58969099521155010221e-10),
    # __cos.c
    "C1": bits(4.16666666666666019037e-02),
    "C2": bits(-1.38888888888741095749e-03),
    "C3": bits(2.48015872894767294178e-05),
    "C4": bits(-2.75573143513906633035e-07),
    "C5": bits(2.08757232129817482790e-09),
    "C6": bits(-1.13596475577881948265e-11),
    # __tan.c
    "T0": bits(3.33333333333334091986e-01),
    "T1": bits(1.33333333333201242699e-01),
    "T2": bits(5.39682539762260521377e-02),
    "T3": bits(2.18694882948595424599e-02),
    "T4": bits(8.86323982359930005737e-03),
    "T5": bits(3.59207910759131235356e-03),
    "T6": bits(1.45620945432529025516e-03),
    "T7": bits(5.88041240820264096874e-04),
    "T8": bits(2.46463134818469906812e-04),
    "T9": bits(7.81794442939557092300e-05),
    "T10": bits(7.14072491382608190305e-05),
    "T11": bits(-1.85586374855275456654e-05),
    "T12": bits(2.59073051863633712884e-05),
    "pio4": bits(7.85398163397448278999e-01),
    "pio4lo": bits(3.06161699786838301793e-17),
    # __rem_pio2.c
    "invpio2": bits(6.36619772367581382433e-01),
    "pio2_1": bits(1.57079632673412561417e00),
    "pio2_1t": bits(6.07710050650619224932e-11),
    "pio2_2": bits(6.07710050630396597660e-11),
    "pio2_2t": bits(2.02226624879595063154e-21),
    "pio2_3": bits(2.02226624871116645580e-21),
    "pio2_3t": bits(8.47842766036889956997e-32),
    # atan.c; atanhi[1] and atanlo[1] are pio4 and pio4lo
    "atanhi0": bits(4.63647609000806093515e-01),
    "atanhi2": bits(9.82793723247329054082e-01),
    "atanlo0": bits(2.26987774529616870924e-17),
    "atanlo2": bits(1.39033110312309984516e-17),
    "aT0": bits(3.33333333333329318027e-01),
    "aT1": bits(-1.99999999998764832476e-01),
    "aT2": bits(1.42857142725034663711e-01),
    "aT3": bits(-1.11111104054623557880e-01),
    "aT4": bits(9.09088713343650656196e-02),
    "aT5": bits(-7.69187620504482999495e-02),
    "aT6": bits(6.66107313738753120669e-02),
    "aT7": bits(-5.83357013379057348645e-02),
    "aT8": bits(4.97687799461593236017e-02),
    "aT9": bits(-3.65315727442169155270e-02),
    "aT10": bits(1.62858201153657823623e-02),
    # asin.c and acos.c; atanhi[3] and atanlo[3] are pio2_hi and pio2_lo
    "pio2_hi": bits(1.57079632679489655800e00),
    "pio2_lo": bits(6.12323399573676603587e-17),
    "pS0": bits(1.66666666666666657415e-01),
    "pS1": bits(-3.25565818622400915405e-01),
    "pS2": bits(2.01212532134862925881e-01),
    "pS3": bits(-4.00555345006794114027e-02),
    "pS4": bits(7.91534994289814532176e-04),
    "pS5": bits(3.47933107596021167570e-05),
    "qS1": bits(-2.40339491173441421878e00),
    "qS2": bits(2.02094576023350569471e00),
    "qS3": bits(-6.88283971605453293030e-01),
    "qS4": bits(7.70381505559019352791e-02),
    # 0x1p-120f, which C adds to raise the inexact flag
    "tiny": bits(2.0**-120),
    # atan2.c
    "pi": bits(3.1415926535897931160e00),
    "pi_lo": bits(1.2246467991473531772e-16),
    # fdlibm's e_log.c and e_exp.c
    "ln2_hi": bits(6.93147180369123816490e-01),
    "ln2_lo": bits(1.90821492927058770002e-10),
    "Lg1": bits(6.666666666666735130e-01),
    "Lg2": bits(3.999999999940941908e-01),
    "Lg3": bits(2.857142874366239149e-01),
    "Lg4": bits(2.222219843214978396e-01),
    "Lg5": bits(1.818357216161805012e-01),
    "Lg6": bits(1.531383769920937332e-01),
    "Lg7": bits(1.479819860511658591e-01),
    "o_threshold": bits(7.09782712893383973096e02),
    "u_threshold": bits(-7.45133219101941108420e02),
    "invln2": bits(1.44269504088896338700e00),
    "P1": bits(1.66666666666666019037e-01),
    "P2": bits(-2.77777777770155933842e-03),
    "P3": bits(6.61375632143793436117e-05),
    "P4": bits(-1.65339022054652515390e-06),
    "P5": bits(4.13813679705723846039e-08),
    # FreeBSD's e_log2.c
    "ivln2hi": bits(1.44269504072144627571e00),
    "ivln2lo": bits(1.67517131648865118353e-10),
    # musl's log10.c
    "ivln10hi": bits(4.34294481878168880939e-01),
    "ivln10lo": bits(2.50829467116452752298e-11),
    "log10_2hi": bits(3.01029995663611771306e-01),
    "log10_2lo": bits(3.69423907715893078616e-13),
}

# The constants that the C code writes as hex, against their decimal.
assert CONSTANTS["pio4"] == 0x3FE921FB54442D18
assert CONSTANTS["pio2_1"] == 0x3FF921FB54400000
assert CONSTANTS["pio2_3t"] == 0x397B839A252049C1
assert CONSTANTS["atanhi0"] == 0x3FDDAC670561BB4F
assert CONSTANTS["atanlo2"] == 0x3C7007887AF0CBBD
assert CONSTANTS["aT10"] == 0x3F90AD3AE322DA11
assert CONSTANTS["pio2_lo"] == 0x3C91A62633145C07
assert CONSTANTS["qS4"] == 0x3FB3B8C5B12E9282
assert CONSTANTS["pi_lo"] == 0x3CA1A62633145C07
assert CONSTANTS["ln2_hi"] == 0x3FE62E42FEE00000
assert CONSTANTS["ln2_lo"] == 0x3DEA39EF35793C76
assert CONSTANTS["Lg1"] == 0x3FE5555555555593
assert CONSTANTS["Lg7"] == 0x3FC2F112DF3E5244
assert CONSTANTS["o_threshold"] == 0x40862E42FEFA39EF
assert CONSTANTS["u_threshold"] == 0xC0874910D52D3051
assert CONSTANTS["invln2"] == 0x3FF71547652B82FE
assert CONSTANTS["P5"] == 0x3E66376972BEA4D0
assert CONSTANTS["ivln2hi"] == 0x3FF7154765200000
assert CONSTANTS["ivln2lo"] == 0x3DE705FC2EEFA200
assert CONSTANTS["ivln10hi"] == 0x3FDBCB7B15200000
assert CONSTANTS["ivln10lo"] == 0x3DBB9438CA9AADD5
assert CONSTANTS["log10_2hi"] == 0x3FD34413509F6000
assert CONSTANTS["log10_2lo"] == 0x3D59FEF311F12B36

# The programs. The names of the functions of §11.3 are in capitals; the
# others are the helpers they call.
SOURCE = '''
def sin_k(x, y, iy):
    # musl's __sin.c
    z = x*x
    w = z*z
    r = S2 + z*(S3 + z*S4) + z*w*(S5 + z*S6)
    v = z*x
    if iy == 0:
        return x + v*(S1 + z*r)
    return x - ((z*(0.5*y - v*r) - y) - v*S1)


def cos_k(x, y):
    # musl's __cos.c
    z = x*x
    w = z*z
    r = z*(C1 + z*(C2 + z*C3)) + w*w*(C4 + z*(C5 + z*C6))
    hz = 0.5*z
    w = 1.0 - hz
    return w + (((1.0 - w) - hz) + (z*r - x*y))


def tan_k(x, y, odd):
    # musl's __tan.c; big and neg stand for big and sign, and z, s, and
    # y for w0, a0, and a
    big = abs(x) >= H(0x3FE59428)
    neg = x < 0.0
    if big:
        if neg:
            x = -x
            y = -y
        x = (pio4 - x) + (pio4lo - y)
        y = 0.0
    z = x*x
    w = z*z
    r = T1 + w*(T3 + w*(T5 + w*(T7 + w*(T9 + w*T11))))
    v = z*(T2 + w*(T4 + w*(T6 + w*(T8 + w*(T10 + w*T12)))))
    s = z*x
    r = y + z*(s*(r + v) + y) + s*T0
    w = x + r
    if big:
        s = 1.0 - 2.0*odd
        v = s - 2.0*(x + (r - w*w/(w + s)))
        if neg:
            return -v
        return v
    if odd == 0:
        return w
    z = chop(w)
    v = r - (z - x)
    y = -1.0/w
    s = chop(y)
    return s + y*(1.0 + s*z + s*v)


def rem_pio2(x):
    # musl's __rem_pio2.c for |x| < 2^20 pi/2, without its goto: the
    # whole number n, and y0 + y1 = x - n pi/2
    if abs(x) < H(0x400f6a7b) and not (abs(x) >= H(0x3ff921fb) and abs(x) < H(0x3ff921fc) or abs(x) >= H(0x400921fb) and abs(x) < H(0x400921fc)):
        if abs(x) < H(0x4002d97d):
            if x > 0.0:
                r = x - pio2_1
                y0 = r - pio2_1t
                return 1.0, y0, (r - y0) - pio2_1t
            r = x + pio2_1
            y0 = r + pio2_1t
            return -1.0, y0, (r - y0) + pio2_1t
        if x > 0.0:
            r = x - 2*pio2_1
            y0 = r - 2*pio2_1t
            return 2.0, y0, (r - y0) - 2*pio2_1t
        r = x + 2*pio2_1
        y0 = r + 2*pio2_1t
        return -2.0, y0, (r - y0) + 2*pio2_1t
    if abs(x) >= H(0x400f6a7b) and abs(x) < H(0x4015fdbd) and not (abs(x) >= H(0x4012d97c) and abs(x) < H(0x4012d97d)):
        if x > 0.0:
            r = x - 3*pio2_1
            y0 = r - 3*pio2_1t
            return 3.0, y0, (r - y0) - 3*pio2_1t
        r = x + 3*pio2_1
        y0 = r + 3*pio2_1t
        return -3.0, y0, (r - y0) + 3*pio2_1t
    if abs(x) >= H(0x4015fdbd) and abs(x) < H(0x401c463c) and not (abs(x) >= H(0x401921fb) and abs(x) < H(0x401921fc)):
        if x > 0.0:
            r = x - 4*pio2_1
            y0 = r - 4*pio2_1t
            return 4.0, y0, (r - y0) - 4*pio2_1t
        r = x + 4*pio2_1
        y0 = r + 4*pio2_1t
        return -4.0, y0, (r - y0) + 4*pio2_1t
    # The medium case. fn is rint(x / (pi/2)), which C computes by adding
    # and subtracting 1.5 * 2^52, the same as NEAREST. The exponents of x
    # and y0 differ by ex - ey, from their fields in C, which GETEXP gives
    # as well: y0 is never subnormal here, and a zero y0 makes both large.
    fn = nearest(x*invpio2)
    r = x - fn*pio2_1
    w = fn*pio2_1t
    if r - w < -pio4:
        fn = fn - 1.0
        r = x - fn*pio2_1
        w = fn*pio2_1t
    elif r - w > pio4:
        fn = fn + 1.0
        r = x - fn*pio2_1
        w = fn*pio2_1t
    y0 = r - w
    if getexp(x) - getexp(y0) > 16.0:
        t = r
        w = fn*pio2_2
        r = t - w
        w = fn*pio2_2t - ((t - r) - w)
        y0 = r - w
        if getexp(x) - getexp(y0) > 49.0:
            t = r
            w = fn*pio2_3
            r = t - w
            w = fn*pio2_3t - ((t - r) - w)
            y0 = r - w
    return fn, y0, (r - y0) - w


def SIN(x):
    # musl's sin.c; beyond 2^20 pi/2 the canonical NaN
    if abs(x) < H(0x3fe921fc):
        if abs(x) < H(0x3e500000):
            return x
        return sin_k(x, 0.0, 0)
    if abs(x) >= H(0x413921fb):
        return nan()
    n, y0, y1 = rem_pio2(x)
    n = band(n, 3.0)
    if n == 0.0:
        return sin_k(y0, y1, 1)
    if n == 1.0:
        return cos_k(y0, y1)
    if n == 2.0:
        return -sin_k(y0, y1, 1)
    return -cos_k(y0, y1)


def COS(x):
    # musl's cos.c; beyond 2^20 pi/2 the canonical NaN
    if abs(x) < H(0x3fe921fc):
        if abs(x) < H(0x3e46a09e):
            return 1.0
        return cos_k(x, 0.0)
    if abs(x) >= H(0x413921fb):
        return nan()
    n, y0, y1 = rem_pio2(x)
    n = band(n, 3.0)
    if n == 0.0:
        return cos_k(y0, y1)
    if n == 1.0:
        return -sin_k(y0, y1, 1)
    if n == 2.0:
        return -cos_k(y0, y1)
    return sin_k(y0, y1, 1)


def TAN(x):
    # musl's tan.c; beyond 2^20 pi/2 the canonical NaN
    if abs(x) < H(0x3fe921fc):
        if abs(x) < H(0x3e400000):
            return x
        return tan_k(x, 0.0, 0)
    if abs(x) >= H(0x413921fb):
        return nan()
    n, y0, y1 = rem_pio2(x)
    n = band(n, 1.0)
    return tan_k(y0, y1, n)

def atan_k(x):
    # musl's atan.c. id is red, hi, and lo: red is 0 where id < 0, and
    # hi and lo are atanhi[id] and atanlo[id] where not
    if abs(x) >= H(0x44100000):
        if x < 0.0:
            return -(pio2_hi + tiny)
        return pio2_hi + tiny
    neg = x < 0.0
    if abs(x) < H(0x3fdc0000):
        if abs(x) < H(0x3e400000):
            return x
        red = 0.0
    else:
        red = 1.0
        x = abs(x)
        if x < H(0x3ff30000):
            if x < H(0x3fe60000):
                hi = atanhi0
                lo = atanlo0
                x = (2.0*x - 1.0)/(2.0 + x)
            else:
                hi = pio4
                lo = pio4lo
                x = (x - 1.0)/(x + 1.0)
        elif x < H(0x40038000):
            hi = atanhi2
            lo = atanlo2
            x = (x - 1.5)/(1.0 + 1.5*x)
        else:
            hi = pio2_hi
            lo = pio2_lo
            x = -1.0/x
    z = x*x
    w = z*z
    s1 = z*(aT0 + w*(aT2 + w*(aT4 + w*(aT6 + w*(aT8 + w*aT10)))))
    s2 = w*(aT1 + w*(aT3 + w*(aT5 + w*(aT7 + w*aT9))))
    if red == 0.0:
        return x - x*(s1 + s2)
    z = hi - ((x*(s1 + s2) - lo) - x)
    if neg:
        return -z
    return z


def asin_r(z):
    # R of musl's asin.c and acos.c
    p = z*(pS0 + z*(pS1 + z*(pS2 + z*(pS3 + z*(pS4 + z*pS5)))))
    q = 1.0 + z*(qS1 + z*(qS2 + z*(qS3 + z*qS4)))
    return p/q


def ASIN(x):
    # musl's asin.c; 0/(x-x) is nan()
    if abs(x) >= 1.0:
        if abs(x) == 1.0:
            return x*pio2_hi + tiny
        return nan()
    if abs(x) < 0.5:
        if abs(x) < H(0x3e500000) and abs(x) >= H(0x00100000):
            return x
        return x + x*asin_r(x*x)
    neg = x < 0.0
    z = (1.0 - abs(x))*0.5
    s = sqrt(z)
    r = asin_r(z)
    if abs(x) >= H(0x3fef3333):
        x = pio2_hi - (2.0*(s + s*r) - pio2_lo)
    else:
        f = chop(s)
        c = (z - f*f)/(s + f)
        x = 0.5*pio2_hi - ((2.0*s*r - (pio2_lo - 2.0*c)) - (0.5*pio2_hi - 2.0*f))
    if neg:
        return -x
    return x


def ACOS(x):
    # musl's acos.c; 0/(x-x) is nan()
    if abs(x) >= 1.0:
        if abs(x) == 1.0:
            if x < 0.0:
                return 2.0*pio2_hi + tiny
            return 0.0
        return nan()
    if abs(x) < 0.5:
        if abs(x) < H(0x3c600001):
            return pio2_hi + tiny
        return pio2_hi - (x - (pio2_lo - x*asin_r(x*x)))
    if x < 0.0:
        z = (1.0 + x)*0.5
        s = sqrt(z)
        w = asin_r(z)*s - pio2_lo
        return 2.0*(pio2_hi - (s + w))
    z = (1.0 - x)*0.5
    s = sqrt(z)
    df = chop(s)
    c = (z - df*df)/(s + df)
    w = asin_r(z)*s + c
    return 2.0*(df + w)


def ATAN(x):
    return atan_k(x)


def ATAN2(y, x):
    # musl's atan2.c. Its m is the signs of y and x, which x < 0.0 and
    # y < 0.0 test where they are not zero, and 1.0/x < 0.0 where they
    # are. A test of the high words, such as ix + (64 << 20) < iy, is one
    # of itof(chop(abs(x))), which is the high word times 2^32, exactly.
    # musl's atan(y) for x = 1 is left out: the general path gives the
    # same bits there, as atan(y) is -atan(-y) and y/1 is y.
    if y == 0.0:
        if x < 0.0 or 1.0/x < 0.0:
            if 1.0/y < 0.0:
                return -pi
            return pi
        return y
    if x == 0.0:
        if y < 0.0:
            return -pi/2
        return pi/2
    if abs(x) == H(0x7ff00000):
        if abs(y) == H(0x7ff00000):
            if x < 0.0:
                if y < 0.0:
                    return -3*pi/4
                return 3*pi/4
            if y < 0.0:
                return -pi/4
            return pi/4
        if x < 0.0:
            if y < 0.0:
                return -pi
            return pi
        if y < 0.0:
            return -0.0
        return 0.0
    if itof(chop(abs(x))) + 288230376151711744.0 < itof(chop(abs(y))) or abs(y) == H(0x7ff00000):
        if y < 0.0:
            return -pi/2
        return pi/2
    if x < 0.0 and itof(chop(abs(y))) + 288230376151711744.0 < itof(chop(abs(x))):
        z = 0.0
    else:
        z = atan_k(abs(y/x))
    if x < 0.0:
        if y < 0.0:
            return (z - pi_lo) - pi
        return pi - (z - pi_lo)
    if y < 0.0:
        return -z
    return z


def log_red(x, t):
    # The reduction of the logarithms: k and x' with x = 2^k x', where x'
    # is from about sqrt(2)/2 to sqrt(2). C takes the high word's
    # exponent, and halves x' if its fraction bits are t or more, after
    # it scales a subnormal x by 2^54. GETEXP and GETMANT give the same
    # k and x' for a subnormal x without it.
    m = getmant(x)
    if m >= t:
        return getexp(x) + 1.0, 0.5*m
    return getexp(x), m


def log1p_k(f):
    # k_log1p of FreeBSD's k_log.h, with its t1, t2, R, and hfsq in the
    # expression
    s = f/(2.0 + f)
    z = s*s
    w = z*z
    return s*(0.5*f*f + (z*(Lg1 + w*(Lg3 + w*(Lg5 + w*Lg7))) + w*(Lg2 + w*(Lg4 + w*Lg6))))


def LN(x):
    # fdlibm's e_log.c. Its tests of the fraction bits hx of x, which
    # are of x', are of the value x': hx < 3 after adding 2 is x' from
    # H(0x3feffffe) to H(0x3ff00001), and i | j > 0 is x' from the
    # fractions 0x6147a to 0x6b851, which is x' >= H(0x3ff6147a) or
    # x' < H(0x3fe6b852) where x' is halved.
    if x <= 0.0:
        if x == 0.0:
            pole()
            return -H(0x7ff00000)
        return nan()
    if x == H(0x7ff00000):
        return x
    k, x = log_red(x, H(0x3ff6a09c))
    f = x - 1.0
    if x >= H(0x3feffffe) and x < H(0x3ff00001):
        if f == 0.0:
            if k == 0.0:
                return 0.0
            return k*ln2_hi + k*ln2_lo
        r = f*f*(0.5 - 0.33333333333333333*f)
        if k == 0.0:
            return f - r
        return k*ln2_hi - ((r - k*ln2_lo) - f)
    s = f/(2.0 + f)
    z = s*s
    w = z*z
    t1 = w*(Lg2 + w*(Lg4 + w*Lg6))
    t2 = z*(Lg1 + w*(Lg3 + w*(Lg5 + w*Lg7)))
    r = t2 + t1
    if x >= H(0x3ff6147a) or x < H(0x3fe6b852):
        hfsq = 0.5*f*f
        if k == 0.0:
            return f - (hfsq - s*(hfsq + r))
        return k*ln2_hi - ((hfsq - (s*(hfsq + r) + k*ln2_lo)) - f)
    if k == 0.0:
        return f - s*(f - r)
    return k*ln2_hi - ((s*(f - r) - k*ln2_lo) - f)


def LOG2(x):
    # FreeBSD's e_log2.c and k_log.h. Its log2(1) = +0 is left out, as
    # the general path gives +0 there too.
    if x <= 0.0:
        if x == 0.0:
            pole()
            return -H(0x7ff00000)
        return nan()
    if x == H(0x7ff00000):
        return x
    k, x = log_red(x, H(0x3ff6a09c))
    f = x - 1.0
    hfsq = 0.5*f*f
    r = log1p_k(f)
    hi = chop(f - hfsq)
    lo = (f - hi) - hfsq + r
    val_hi = hi*ivln2hi
    val_lo = (lo + hi)*ivln2lo + lo*ivln2hi
    w = k + val_hi
    val_lo = val_lo + ((k - w) + val_hi)
    return val_lo + w


def LOG10(x):
    # musl's log10.c, which reduces x at the fraction 0x6a09e, not at
    # 0x6a09c as the others do. Its log10(1) = +0 is left out, as the
    # general path gives +0 there too, and s*(hfsq+R) is log1p_k(f).
    if x <= 0.0:
        if x == 0.0:
            pole()
            return -H(0x7ff00000)
        return nan()
    if x == H(0x7ff00000):
        return x
    k, x = log_red(x, H(0x3ff6a09e))
    f = x - 1.0
    hfsq = 0.5*f*f
    hi = chop(f - hfsq)
    lo = f - hi - hfsq + log1p_k(f)
    val_hi = hi*ivln10hi
    y = k*log10_2hi
    val_lo = k*log10_2lo + (lo + hi)*ivln10lo + lo*ivln10hi
    w = y + val_hi
    val_lo = val_lo + ((y - w) + val_hi)
    return val_lo + w


def EXP(x):
    # fdlibm's e_exp.c. ln2HI[xsb] and halF[xsb] of a negative x are
    # -ln2_hi and -0.5, which are added where C subtracts them. C's
    # change of y's exponent by k is SCALE2, exact as C's is, and the
    # one rounding of y*twom1000 where k < -1021.
    if abs(x) >= H(0x40862e42):
        if abs(x) == H(0x7ff00000):
            if x > 0.0:
                return x
            return 0.0
        if x > o_threshold:
            return H(0x7ff00000)
        if x < u_threshold:
            return 0.0
    if abs(x) > H(0x3fd62e42):
        if abs(x) < H(0x3ff0a2b2):
            if x < 0.0:
                hi = x + ln2_hi
                lo = -ln2_lo
                k = -1.0
            else:
                hi = x - ln2_hi
                lo = ln2_lo
                k = 1.0
        else:
            if x < 0.0:
                k = trunc(invln2*x - 0.5)
            else:
                k = trunc(invln2*x + 0.5)
            hi = x - k*ln2_hi
            lo = k*ln2_lo
        x = hi - lo
    elif abs(x) < H(0x3e300000):
        return 1.0 + x
    else:
        k = 0.0
    t = x*x
    c = x - t*(P1 + t*(P2 + t*(P3 + t*(P4 + t*P5))))
    if k == 0.0:
        return 1.0 - ((x*c)/(c - 2.0) - x)
    return scale2(1.0 - ((lo - (x*c)/(2.0 - c)) - hi), k)
'''

# The functions of §11.3 that have a sequence: their number, and the
# number of operands they pop.
FUNCTIONS: Dict[str, Tuple[int, int]] = {
    "SIN": (0x40, 1),
    "COS": (0x41, 1),
    "TAN": (0x42, 1),
    "ASIN": (0x43, 1),
    "ACOS": (0x44, 1),
    "ATAN": (0x45, 1),
    "ATAN2": (0x46, 2),
    "LN": (0x48, 1),
    "LOG2": (0x49, 1),
    "LOG10": (0x4A, 1),
    "EXP": (0x4C, 1),
}

# The calls that are one command, and the operands they take.
COMMAND_CALLS: Dict[str, Tuple[str, int]] = {
    "abs": ("ABS", 1),
    "sqrt": ("SQRT", 1),
    "nearest": ("NEAREST", 1),
    "trunc": ("TRUNC", 1),
    "getexp": ("GETEXP", 1),
    "chop": ("CHOP", 1),
    "itof": ("ITOF", 1),
    "getmant": ("GETMANT", 1),
    "band": ("AND", 2),
    "scale2": ("SCALE2", 2),
}

BINOPS = {ast.Add: "ADD", ast.Sub: "SUB", ast.Mult: "MUL", ast.Div: "DIV"}

# CMP's mask for each comparison: bit 0 for <, bit 1 for =, bit 2 for >.
MASKS = {ast.Lt: 1, ast.Eq: 2, ast.Gt: 4, ast.LtE: 3, ast.GtE: 6, ast.NotEq: 5}


class CompileError(Exception):
    pass


# A variable's place: a slot of the frame, counted from the frame's
# base, or a constant that a parameter was given.
Place = Union[int, float]


class Frame:
    """The variables of one function of the program as it is inlined:
    their places, the slots its results go to, the label after it, and
    the depth to which its return drops the stack."""

    def __init__(self, places: Dict[str, Place], results: List[int], end: str, base: int, later: List[str]) -> None:
        self.places = places
        self.results = results
        self.end = end
        self.base = base
        self.later = later


def assigned(body: Sequence[ast.stmt]) -> List[str]:
    """The names that the statements assign, in order, once each."""
    out: List[str] = []
    for node in body:
        for sub in ast.walk(node):
            if isinstance(sub, ast.Name) and isinstance(sub.ctx, ast.Store) and sub.id not in out:
                out.append(sub.id)
    return out


def late(body: Sequence[ast.stmt]) -> List[str]:
    """The names that an assignment of the function's own body assigns
    first, not one in an if. Such a name gets its slot there, on top of
    the frame, so that the frame holds it only from there on."""
    seen: List[str] = []
    out: List[str] = []
    for node in body:
        names = assigned([node])
        if isinstance(node, ast.Assign):
            out.extend(n for n in names if n not in seen)
        seen.extend(n for n in names if n not in seen)
    return out


# Comparisons with the operands exchanged: CMP's mask with bits 0 and 2
# exchanged.
def mirror(mask: int) -> int:
    return (mask & 2) | (mask & 1) << 2 | (mask & 4) >> 2


class Compiler:
    def __init__(self, source: str) -> None:
        tree = ast.parse(source)
        self.defs: Dict[str, ast.FunctionDef] = {}
        for node in tree.body:
            if not isinstance(node, ast.FunctionDef):
                raise CompileError("only functions at the top")
            self.defs[node.name] = node
        self.steps: List[str] = []
        # The depth of the frame before each step, and the most it holds.
        self.depths: List[int] = []
        self.most = 0
        self.depth = 0
        self.reachable = True
        self.count = 0
        self.constants: Dict[str, int] = dict(CONSTANTS)

    # The steps, and the depth of the stack above the base of the frame.

    def emit(self, step: str, delta: int) -> None:
        if self.reachable:
            self.steps.append(step)
            self.depths.append(self.depth)
            self.depth += delta
            self.most = max(self.most, self.depth)

    def label(self) -> str:
        self.count += 1
        return f"L{self.count}"

    def place(self, name: str) -> None:
        self.steps.append(name + ":")
        self.depths.append(self.depth)
        self.reachable = True

    def jump(self, label: str) -> None:
        self.emit("JMP " + label, 0)
        self.reachable = False

    # Constants.

    def constant(self, node: ast.expr) -> Optional[float]:
        """The value of an expression of constants alone, as C folds it,
        or None."""
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return float(node.value)
        if isinstance(node, ast.Name) and node.id in CONSTANTS:
            return value(CONSTANTS[node.id])
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            v = self.constant(node.operand)
            return None if v is None else -v
        if isinstance(node, ast.BinOp) and type(node.op) in BINOPS:
            a = self.constant(node.left)
            b = self.constant(node.right)
            if a is None or b is None:
                return None
            if isinstance(node.op, ast.Add):
                return a + b
            if isinstance(node.op, ast.Sub):
                return a - b
            if isinstance(node.op, ast.Mult):
                return a * b
            return a / b
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "H":
            arg = node.args[0]
            assert isinstance(arg, ast.Constant) and isinstance(arg.value, int)
            return value(arg.value << 32)
        return None

    def push_constant(self, v: float, name: str) -> None:
        """Pushes the constant v, by the name of a constant with its
        bits, or by name, which then names it."""
        b = bits(v)
        if self.constants.get(name) != b:
            same = next((n for n, c in self.constants.items() if c == b), None)
            if same is None:
                if name in self.constants:
                    raise CompileError(f"two constants named {name}")
                self.constants[name] = b
            else:
                name = same
        self.emit("K " + name, 1)

    @staticmethod
    def const_name(node: ast.expr) -> str:
        """The name of a constant expression: its text, or for H(h),
        H and the 8 hex digits of h."""
        if isinstance(node, ast.Name):
            return node.id
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            return "-" + Compiler.const_name(node.operand)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "H":
            arg = node.args[0]
            assert isinstance(arg, ast.Constant) and isinstance(arg.value, int)
            return f"H{arg.value:08X}"
        return ast.unparse(node).replace(" ", "")

    # Expressions.

    def need(self, node: ast.expr, frame: Frame) -> int:
        """The values on the stack that computing node takes at most."""
        if self.constant(node) is not None or isinstance(node, ast.Name):
            return 1
        if isinstance(node, ast.UnaryOp):
            return self.need(node.operand, frame)
        if isinstance(node, (ast.BinOp, ast.Compare)):
            left = node.left
            right = node.right if isinstance(node, ast.BinOp) else node.comparators[0]
            a, b = self.need(left, frame), self.need(right, frame)
            return a + 1 if a == b else max(a, b)
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id in self.defs:
                return 99
            n = [self.need(a, frame) for a in node.args]
            return max((v + i for i, v in enumerate(n)), default=1)
        return 99

    def pair(self, left: ast.expr, right: ast.expr, frame: Frame) -> bool:
        """Pushes the values of two operands, the one that needs more
        first, and says whether they are in the other order: right as Y
        and left as X."""
        if self.need(right, frame) > self.need(left, frame):
            self.expr(right, frame)
            self.expr(left, frame)
            return True
        self.expr(left, frame)
        self.expr(right, frame)
        return False

    def expr(self, node: ast.expr, frame: Frame) -> None:
        """Pushes the value of node."""
        v = self.constant(node)
        if v is not None:
            self.push_constant(v, self.const_name(node))
            return
        if isinstance(node, ast.Name):
            p = frame.places.get(node.id)
            if p is None:
                raise CompileError(f"unknown name {node.id}")
            if isinstance(p, float):
                self.push_constant(p, repr(p))
            else:
                self.emit(f"PICK {self.depth - 1 - p}", 1)
            return
        if isinstance(node, ast.BinOp) and type(node.op) in BINOPS:
            op = BINOPS[type(node.op)]
            if self.pair(node.left, node.right, frame) and op in ("SUB", "DIV"):
                self.emit("SWAP", 0)
            self.emit(op, -1)
            return
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            self.expr(node.operand, frame)
            self.emit("NEG", 0)
            return
        if isinstance(node, ast.Compare):
            if len(node.ops) != 1 or type(node.ops[0]) not in MASKS:
                raise CompileError("one comparison at a time")
            mask = MASKS[type(node.ops[0])]
            if self.pair(node.left, node.comparators[0], frame):
                mask = mirror(mask)
            self.emit(f"CMP {mask}", -1)
            return
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            name = node.func.id
            if name == "nan":
                self.emit("K nan", 1)
                return
            if name in COMMAND_CALLS:
                cmd, n = COMMAND_CALLS[name]
                if len(node.args) != n:
                    raise CompileError(f"{name} takes {n}")
                if n == 2:
                    if self.pair(node.args[0], node.args[1], frame) and cmd != "AND":
                        self.emit("SWAP", 0)
                else:
                    self.expr(node.args[0], frame)
                self.emit(cmd, 1 - n)
                return
            if name in self.defs:
                self.call(node, frame, None)
                return
        raise CompileError(f"cannot compile {ast.dump(node)}")

    def static(self, node: ast.expr, frame: Frame) -> Optional[bool]:
        """The truth of a test that is known when compiling, or None."""
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            a = self.static_value(node.left, frame)
            b = self.static_value(node.comparators[0], frame)
            if a is None or b is None:
                return None
            ops = {
                ast.Lt: a < b, ast.Eq: a == b, ast.Gt: a > b,
                ast.LtE: a <= b, ast.GtE: a >= b, ast.NotEq: a != b,
            }
            return ops[type(node.ops[0])]
        return None

    def static_value(self, node: ast.expr, frame: Frame) -> Optional[float]:
        if isinstance(node, ast.Name):
            p = frame.places.get(node.id)
            if isinstance(p, float):
                return p
        return self.constant(node)

    def test(self, node: ast.expr, frame: Frame, false: str) -> None:
        """Goes on if node holds, and jumps to false if not."""
        if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.And):
            for v in node.values:
                self.test(v, frame, false)
            return
        if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.Or):
            true = self.label()
            for v in node.values[:-1]:
                nxt = self.label()
                self.test(v, frame, nxt)
                self.jump(true)
                self.place(nxt)
            self.test(node.values[-1], frame, false)
            self.place(true)
            return
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            true = self.label()
            self.test(node.operand, frame, true)
            self.jump(false)
            self.place(true)
            return
        self.expr(node, frame)
        self.emit("JZ " + false, -1)

    # Statements.

    def put(self, slot: int) -> None:
        """Pops X into slot."""
        self.emit(f"PUT {self.depth - 2 - slot}", -1)

    def slot(self, frame: Frame, name: str) -> int:
        p = frame.places.get(name)
        if not isinstance(p, int):
            raise CompileError(f"{name} has no slot")
        return p

    def body(self, stmts: Sequence[ast.stmt], frame: Frame) -> None:
        for s in stmts:
            self.statement(s, frame)

    def leave(self, frame: Frame) -> None:
        """Drops the frame of the function, and jumps past it."""
        extra = self.depth - frame.base
        if extra > 0:
            self.emit(f"DROP {extra}", -extra)
        self.jump(frame.end)

    def statement(self, node: ast.stmt, frame: Frame) -> None:
        if not self.reachable:
            return
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant):
            return
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
            call = node.value
            if isinstance(call.func, ast.Name) and call.func.id == "pole":
                self.emit("POLE", 0)
                return
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
            value_node = node.value
            names = [target] if isinstance(target, ast.Name) else target.elts if isinstance(target, ast.Tuple) else []
            new = [e.id for e in names if isinstance(e, ast.Name) and e.id in frame.later and e.id not in frame.places]
            if isinstance(target, ast.Name) and new and not self.is_call(value_node):
                # The value stays where it is pushed, as the new slot.
                self.expr(value_node, frame)
                frame.places[target.id] = self.depth - 1
                return
            for name in new:
                self.emit("DUP" if self.depth > 0 else "K nan", 1)
                frame.places[name] = self.depth - 1
            slots = [self.slot(frame, e.id) for e in names if isinstance(e, ast.Name)]
            if self.is_call(value_node):
                assert isinstance(value_node, ast.Call)
                self.call(value_node, frame, slots)
                return
            if len(slots) == 1:
                self.expr(value_node, frame)
                self.put(slots[0])
                return
        if isinstance(node, ast.If):
            known = self.static(node.test, frame)
            if known is not None:
                self.body(node.body if known else node.orelse, frame)
                return
            other = self.label()
            end = self.label()
            self.test(node.test, frame, other)
            depth = self.depth
            self.body(node.body, frame)
            after, reach = self.depth, self.reachable
            self.jump(end)
            self.place(other)
            self.depth = depth
            self.body(node.orelse, frame)
            if reach and self.reachable and after != self.depth:
                raise CompileError("the branches end at different depths")
            if reach and not self.reachable:
                self.depth = after
            reach = reach or self.reachable
            self.place(end)
            self.reachable = reach
            return
        if isinstance(node, ast.Return) and node.value is not None:
            v = node.value
            if isinstance(v, ast.Call) and isinstance(v.func, ast.Name) and v.func.id in self.defs:
                # A tail call: its results go to this function's.
                self.call(v, frame, frame.results, tail=True)
                self.leave(frame)
                return
            values = v.elts if isinstance(v, ast.Tuple) else [v]
            if len(values) != len(frame.results):
                raise CompileError("a return of the wrong number of values")
            for e in values:
                self.expr(e, frame)
            for slot in reversed(frame.results):
                self.put(slot)
            self.leave(frame)
            return
        raise CompileError(f"cannot compile {ast.dump(node)}")

    def is_call(self, node: ast.expr) -> bool:
        """Whether node is a call of a function of the program."""
        return isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in self.defs

    def call(self, node: ast.Call, frame: Frame, targets: Optional[List[int]], tail: bool = False) -> None:
        """Inlines a function of the program. Its results go to the
        slots of targets, or, if None, its one result to the top. In a
        tail call the caller's variables are dead, so a parameter may
        take the slot of its argument even if the callee writes it."""
        assert isinstance(node.func, ast.Name)
        fn = self.defs[node.func.id]
        params = [a.arg for a in fn.args.args]
        if len(params) != len(node.args):
            raise CompileError(f"{fn.name} takes {len(params)}")
        if targets is None:
            self.emit("DUP" if self.depth > 0 else "K nan", 1)
            targets = [self.depth - 1]
        base = self.depth
        written = assigned(fn.body)
        places: Dict[str, Place] = {}
        for name, arg in zip(params, node.args):
            c = self.static_value(arg, frame)
            if c is not None and name not in written:
                places[name] = c
            elif (
                isinstance(arg, ast.Name)
                and (tail or name not in written)
                and isinstance(frame.places.get(arg.id), int)
                and frame.places[arg.id] not in places.values()
            ):
                places[name] = frame.places[arg.id]
            else:
                self.expr(arg, frame)
                places[name] = self.depth - 1
        later = late(fn.body)
        for name in written:
            if name not in places and name not in later:
                self.emit("DUP", 1)
                places[name] = self.depth - 1
        end = self.label()
        self.body(fn.body, Frame(places, targets, end, base, later))
        if self.reachable:
            raise CompileError(f"{fn.name} can end without a return")
        self.place(end)
        self.depth = base


def compile_program(name: str, compiler: Optional[Compiler] = None) -> List[str]:
    """The steps of the function name of §11.3, with its operands in the
    first slots of the frame: Y and X, or X. The steps end with the
    result in the place of the deepest operand, and nothing above it."""
    c = compiler or Compiler(SOURCE)
    fn = c.defs[name]
    params = [a.arg for a in fn.args.args]
    c.depth = len(params)
    c.most = c.depth
    written = assigned(fn.body)
    later = late(fn.body)
    places: Dict[str, Place] = {p: i for i, p in enumerate(params)}
    for v in written:
        if v in places or v in later:
            continue
        c.emit("DUP", 1)
        places[v] = c.depth - 1
    end = c.label()
    c.body(fn.body, Frame(places, [0], end, 1, later))
    if c.reachable:
        raise CompileError(f"{name} can end without a return")
    c.place(end)
    return c.steps


def constants_used(steps: List[str], compiler: Compiler) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for s in steps:
        if s.startswith("K "):
            out[s[2:]] = compiler.constants[s[2:]]
    return out


class Program:
    """A function's steps, with its labels resolved and its constants."""

    def __init__(self, name: str) -> None:
        c = Compiler(SOURCE)
        self.name = name
        self.steps = compile_program(name, c)
        self.constants = constants_used(self.steps, c)
        # The most values the frame holds: the k of §11.3, with the operands.
        self.most = c.most
        self.code: List[str] = []
        self.depths: List[int] = []
        self.targets: Dict[str, int] = {}
        for s, d in zip(self.steps, c.depths):
            if s.endswith(":"):
                self.targets[s[:-1]] = len(self.code)
            else:
                self.code.append(s)
                self.depths.append(d)


PROGRAMS: Dict[str, Program] = {name: Program(name) for name in FUNCTIONS}


def listing() -> str:
    """The steps of every function, and the constants they use."""
    lines = []
    for name, prog in PROGRAMS.items():
        num, pops = FUNCTIONS[name]
        lines.append(f"{name} 0x{num:02X} pops {pops}, {len(prog.code)} steps")
        lines.extend("  " + s if not s.endswith(":") else s for s in prog.steps)
    used: Dict[str, int] = {}
    for prog in PROGRAMS.values():
        used.update(prog.constants)
    lines.append("constants")
    lines.extend(f"  {n} {b:016X}" for n, b in used.items())
    return "\n".join(lines) + "\n"


def constant_names() -> Tuple[List[str], Dict[str, int]]:
    """The names of the constants of every program, in the order they are
    first used, and their bits."""
    names: List[str] = []
    used: Dict[str, int] = {}
    for prog in PROGRAMS.values():
        names.extend(n for n in prog.constants if n not in names)
        used.update(prog.constants)
    return names, used


def zig() -> str:
    """src/fpu_seq.zig: the steps of each function, and the constants, as
    the emulator runs them. A step is an operation and a number: the
    command word for a command, the index of the constant for K, n for
    PUT, and the index of the step for JZ and JMP."""
    names, used = constant_names()
    out = [
        "// The sequences of the FPU's functions, DEVICES.md §11.3. Written by",
        "// test/fpu_seq.py --zig from its programs; make test checks that it is",
        "// current. Do not edit.",
        "",
        "pub const Op = enum { cmd, k, put, jz, jmp, pole };",
        "pub const Step = struct { op: Op, n: u32 };",
        "pub const Program = struct { num: u8, pops: u2, steps: []const Step };",
        "",
        "pub const constants = [_]u64{",
    ]
    out.extend(f"    0x{used[n]:016X}, // {n}" for n in names)
    out.append("};")
    from fpu_model import NUMBERS  # here, as the model imports this module

    for name, prog in PROGRAMS.items():
        out.append("")
        out.append(f"const {name.lower()}_steps = [_]Step{{")
        for step in prog.code:
            parts = step.split()
            if parts[0] == "K":
                out.append(f"    .{{ .op = .k, .n = {names.index(parts[1])} }}, // {parts[1]}")
            elif parts[0] == "PUT":
                out.append(f"    .{{ .op = .put, .n = {parts[1]} }},")
            elif parts[0] in ("JZ", "JMP"):
                out.append(f"    .{{ .op = .{parts[0].lower()}, .n = {prog.targets[parts[1]]} }},")
            elif parts[0] == "POLE":
                out.append("    .{ .op = .pole, .n = 0 },")
            else:
                n = int(parts[1]) if len(parts) > 1 else 0
                out.append(f"    .{{ .op = .cmd, .n = 0x{NUMBERS[parts[0]] | n << 8:04X} }}, // {step}")
        out.append("};")
    out.append("")
    out.append("pub const programs = [_]Program{")
    for name in PROGRAMS:
        num, pops = FUNCTIONS[name]
        out.append(f"    .{{ .num = 0x{num:02X}, .pops = {pops}, .steps = &{name.lower()}_steps }},")
    out.append("};")
    return "\n".join(out) + "\n"


# The operations of a step in src/fpu_seq_pkg.vhd, bits 19..17.
VHDL_OPS = {"cmd": 0, "K": 1, "PUT": 2, "JZ": 3, "JMP": 4, "POLE": 5, "END": 6}


def vhdl() -> str:
    """hdl/src/fpu_seq_pkg.vhd: the steps of every function in one ROM,
    each program followed by END, and the constants, as src/fpu.vhd runs
    them. A step is its operation in bits 19..17 and a number in bits
    16..0: the command word for a command, the index of the constant for
    K, n for PUT, and the address of the step for JZ and JMP. The table
    of constants has a power of two of entries, so that the low bits of
    any step index it."""
    from fpu_model import NUMBERS  # here, as the model imports this module

    names, used = constant_names()
    kbits = max(1, (len(names) - 1).bit_length())
    bases: Dict[str, int] = {}
    steps: List[str] = []
    base = 0
    for name, prog in PROGRAMS.items():
        bases[name] = base
        num, _ = FUNCTIONS[name]
        for i, step in enumerate(prog.code):
            parts = step.split()
            if parts[0] == "K":
                op, n = "K", names.index(parts[1])
            elif parts[0] == "PUT":
                op, n = "PUT", int(parts[1])
            elif parts[0] in ("JZ", "JMP"):
                op, n = parts[0], base + prog.targets[parts[1]]
            elif parts[0] == "POLE":
                op, n = "POLE", 0
            else:
                op, n = "cmd", NUMBERS[parts[0]] | (int(parts[1]) if len(parts) > 1 else 0) << 8
            head = f"-- {name} 0x{num:02X}" if i == 0 else ""
            if head:
                steps.append(head)
            steps.append(f'X"{VHDL_OPS[op] << 17 | n:05X}", -- {base + i}: {step}')
        steps.append(f'X"{VHDL_OPS["END"] << 17:05X}", -- {base + len(prog.code)}: END')
        base += len(prog.code) + 1
    steps[-1] = steps[-1].replace(",", " ", 1)
    count = base
    out = [
        "-- The sequences of the FPU's functions, DEVICES.md §11.3, for",
        "-- src/fpu.vhd. Written by emulator/test/fpu_seq.py --vhdl from its",
        "-- programs; make test checks that it is current. Do not edit.",
        "--",
        "-- A step is its operation in bits 19..17 and a number in bits 16..0:",
        "-- the command word for a command, the index of the constant for K,",
        "-- n for PUT, and the address of the step for JZ and JMP. END ends",
        "-- the program. The table of constants has 2^C_SEQ_KBITS entries, so",
        "-- that the low bits of any step index it.",
        "",
        "library ieee;",
        "   use ieee.std_logic_1164.all;",
        "",
        "package fpu_seq_pkg is",
        "",
    ]
    for op, v in VHDL_OPS.items():
        out.append(f'   constant C_SEQ_{op.upper():<4} : std_logic_vector(2 downto 0) := "{v:03b}";')
    out += [
        "",
        f"   constant C_SEQ_KBITS : natural := {kbits};",
        "",
        "   type t_seq_steps is array (natural range <>) of std_logic_vector(19 downto 0);",
        "   type t_seq_consts is array (natural range <>) of std_logic_vector(63 downto 0);",
        "",
        f"   constant C_SEQ_CONSTS : t_seq_consts(0 to {2 ** kbits - 1}) := (",
    ]
    rows = [f'X"{used[n]:016X}", -- {i}: {n}' for i, n in enumerate(names)]
    rows += [f'X"{0:016X}", -- {i}: unused' for i in range(len(names), 2**kbits)]
    rows[-1] = rows[-1].replace(",", " ", 1)
    out.extend("      " + r for r in rows)
    out += ["   );", "", f"   constant C_SEQ_STEPS : t_seq_steps(0 to {count - 1}) := ("]
    out.extend("      " + s for s in steps)
    out += [
        "   );",
        "",
        "   -- The operands a function pops, 1 or 2, or 0 for a number that is",
        "   -- not a function, and the address of its first step.",
        "   function seq_pops (num : std_logic_vector(7 downto 0)) return natural;",
        "",
        "   function seq_base (num : std_logic_vector(7 downto 0)) return natural;",
        "",
        "end package fpu_seq_pkg;",
        "",
        "package body fpu_seq_pkg is",
        "",
        "   function seq_pops (num : std_logic_vector(7 downto 0)) return natural is",
        "   begin",
        "      case num is",
    ]
    for name, (num, pops) in FUNCTIONS.items():
        out.append(f'         when X"{num:02X}" => return {pops}; -- {name}')
    out += [
        "         when others => return 0;",
        "      end case;",
        "   end function seq_pops;",
        "",
        "   function seq_base (num : std_logic_vector(7 downto 0)) return natural is",
        "   begin",
        "      case num is",
    ]
    for name, (num, _) in FUNCTIONS.items():
        out.append(f'         when X"{num:02X}" => return {bases[name]}; -- {name}')
    out += [
        "         when others => return 0;",
        "      end case;",
        "   end function seq_base;",
        "",
        "end package body fpu_seq_pkg;",
    ]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    import sys

    if sys.argv[1:] == ["--zig"]:
        print(zig(), end="")
    elif sys.argv[1:] == ["--vhdl"]:
        print(vhdl(), end="")
    else:
        print(listing(), end="")
