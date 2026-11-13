#!/usr/bin/env python3
"""A random test of the C library's strtod and strtof against exact
arithmetic.

Usage: fuzz_strtod.py [--no-fpu] SEED COUNT

It writes a C program that calls strtod and strtof on COUNT random
strings and prints, for each, the bits of both results, how many bytes
each took, and errno after strtod. The strings are decimals of up to 120
digits with exponents up to 350, hex floats with exponents up to 1150,
exact halfway cases between two doubles and a hair off them, the shortest
decimals of random floats, infinities, NaNs, and the partial forms that
end a float early, such as "1e+", "0x", and "infin", with white space, a
sign, or a stray byte around them. The program is compiled with clang and
the library, translated, joined with the float library, assembled, and
run, and its console output is compared line by line with the model.

The model parses the longest prefix that C17 7.22.1.3 allows and rounds
its exact value, a Fraction, to the nearest double or float, ties to even,
subnormals included. A NaN's bits are not compared, only that it is one.
errno must be ERANGE when a finite value overflows or a nonzero one
rounds to 0, and 0 for a normal result, 0, an infinity, or a NaN. For a
subnormal, or when there is no float, C leaves it to the library, and it
is not checked.

Needs clang with the wasm32 target, and ../libc.a from make -C .. libc.a.
The same seed always gives the same program."""

from __future__ import annotations

import os
import random
import re
import struct
import subprocess
import sys
import tempfile
from decimal import Decimal, getcontext
from fractions import Fraction
from typing import List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
LIBC = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(LIBC))
RUNTIME = os.path.join(REPO, "runtime")
NICEWASM = os.path.join(REPO, "translator", "nicewasm.py")
NICEASM = os.path.join(REPO, "assembler", "niceasm.py")
NICEEMU = os.path.join(REPO, "emulator", "zig-out", "bin", "niceemu")
# The float library: float_fpu.nasm, with the FPU of SYSTEM.md §11, or
# float.nasm, in software, with --no-fpu.
FLOAT_LIB = "float_fpu.nasm"

CFLAGS = ["--target=wasm32", "-mbulk-memory", "-O2", "-ffreestanding", "-nostdlibinc",
          "-isystem", os.path.join(LIBC, "include"), "-Wall"]
LDFLAGS = ["-nostdlib", "-Wl,--no-entry", "-Wl,--export=main", "-Wl,--stack-first",
           "-Wl,-z,stack-size=65536"]
ERANGE = 34

SPACE = " \t\n\v\f\r"
INF = re.compile(r"inf(inity)?", re.I)
NAN = re.compile(r"nan(\([0-9A-Za-z_]*\))?", re.I)
HEX = re.compile(r"0x([0-9a-f]+\.?[0-9a-f]*|\.[0-9a-f]+)(p[+-]?[0-9]+)?", re.I)
DEC = re.compile(r"([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?")

# A double or float: the bits of a significand, and the exponent of the
# smallest subnormal and of the first power of 2 past the largest value.
DOUBLE = (53, -1074, 1024)
FLOAT = (24, -149, 128)


def parse(s: str) -> Tuple[Optional[Fraction], bool, bool, int]:
    """The value of the longest prefix of s that is a float, as strtod
    reads it: the exact value, or None for no conversion, whether it is
    negative, whether it is infinite (else, if the value is None and a
    prefix was taken, a NaN), and the number of bytes taken."""
    i = 0
    while i < len(s) and s[i] in SPACE:
        i += 1
    neg = False
    if i < len(s) and s[i] in "+-":
        neg = s[i] == "-"
        i += 1
    m = INF.match(s, i)
    if m:
        return None, neg, True, m.end()
    m = NAN.match(s, i)
    if m:
        return None, neg, False, m.end()
    m = HEX.match(s, i)
    if m:
        whole, _, frac = m.group(1).partition(".")
        digits = whole + frac
        v = Fraction(int(digits, 16), 16 ** len(frac))
        if m.group(2):
            v *= Fraction(2) ** int(m.group(2)[1:])
        return v, neg, False, m.end()
    m = DEC.match(s, i)
    if m:
        whole, _, frac = m.group(1).partition(".")
        v = Fraction(int(whole + frac or "0"), 10 ** len(frac))
        if m.group(2):
            v *= Fraction(10) ** int(m.group(2)[1:])
        return v, neg, False, m.end()
    return None, False, False, 0


def round_bits(v: Fraction, fmt: Tuple[int, int, int]) -> Tuple[int, int]:
    """|v| rounded to the format, ties to even: the significand n and
    exponent e of n * 2^e, or n = -1 for an overflow to infinity."""
    prec, emin, emax = fmt
    if v == 0:
        return 0, emin
    e = v.numerator.bit_length() - v.denominator.bit_length()
    if Fraction(2) ** e > v:
        e -= 1
    e = max(e - prec + 1, emin)  # the exponent of the last bit kept
    q = v / Fraction(2) ** e
    n = q.numerator // q.denominator
    rem = q - n
    if rem > Fraction(1, 2) or (rem == Fraction(1, 2) and n & 1):
        n += 1
    if n >= 1 << prec:
        n >>= 1
        e += 1
    if n and e + n.bit_length() > emax:
        return -1, 0
    return n, e


def to_bits(v: Optional[Fraction], neg: bool, inf: bool, fmt: Tuple[int, int, int]) -> Tuple[int, bool]:
    """The bits of the result in the format, and whether it overflowed or
    underflowed to 0 from a nonzero value."""
    prec, emin, _ = fmt
    width = 64 if prec == 53 else 32
    expbits = 11 if prec == 53 else 8
    sign = int(neg) << (width - 1)
    infbits = ((1 << expbits) - 1) << (prec - 1)
    if v is None:
        return sign | infbits if inf else 0, False
    n, e = round_bits(v, fmt)
    if n < 0:
        return sign | infbits, True
    if n == 0:
        return sign, v != 0
    if n < 1 << (prec - 1):  # subnormal
        return sign | n, False
    biased = e - emin + 1
    return sign | (biased << (prec - 1)) | (n & ((1 << (prec - 1)) - 1)), False


def rand_string(rng: random.Random) -> str:
    s = ""
    if rng.random() < 0.1:
        s += rng.choice(" \t\n")
    if rng.random() < 0.3:
        s += rng.choice("+-")
    r = rng.random()
    if r < 0.12:
        s += rng.choice(["inf", "INFINITY", "infin", "Infinity", "nan", "NaN(abc_1)", "nan(", "nan(x",
                         "in", "0x", "0X.p1", "0x1p", "1e", "1e+", ".", ".e1", "e5", "0x1p-1074",
                         "0x1p-1075", "0x1.0000000000001p-1075", "0x1.fffffffffffff8p1023",
                         "2.4703282292062328e-324", "1e-400", "1e400", "1.17549435e-38",
                         "3.4028235677973366e38", "7.0064923216240854e-46"])
    elif r < 0.5:
        s += "".join(rng.choice("0123456789") for _ in range(rng.randrange(1, 121 if rng.random() < 0.2 else 21)))
        if rng.random() < 0.5:
            s += "." + "".join(rng.choice("0123456789") for _ in range(rng.randrange(0, 25)))
        if rng.random() < 0.5:
            s += rng.choice("eE") + str(rng.randrange(-350, 350))
    elif r < 0.7:
        s += rng.choice(["0x", "0X"])
        s += "".join(rng.choice("0123456789abcdefABCDEF") for _ in range(rng.randrange(1, 21)))
        if rng.random() < 0.5:
            s += "." + "".join(rng.choice("0123456789abcdef") for _ in range(rng.randrange(0, 16)))
        if rng.random() < 0.7:
            s += rng.choice("pP") + str(rng.randrange(-1150, 1150))
    elif r < 0.85:
        # Halfway between two doubles, exactly or a hair off.
        bits = rng.getrandbits(63)
        if bits >> 52 == 0x7FF:
            bits ^= 1 << 62
        a = Fraction(struct.unpack("<d", struct.pack("<Q", bits))[0])
        b = Fraction(struct.unpack("<d", struct.pack("<Q", bits + 1))[0]) if bits + 1 < 0x7FF << 52 else a
        mid = (a + b) / 2
        text = format(Decimal(mid.numerator) / Decimal(mid.denominator), "e")
        if rng.random() < 0.5:
            mant, _, exp = text.partition("e")
            mant += "1" if "." in mant else ".1"
            text = mant + "e" + exp
        s += text
    else:
        bits = rng.getrandbits(31)
        if bits >> 23 == 0xFF:
            bits ^= 1 << 30
        s += repr(struct.unpack("<f", struct.pack("<I", bits))[0])
    if rng.random() < 0.25:
        s += rng.choice(["x", " ", ".", "e9", "p1", "("])
    return s


def program(rng: random.Random, count: int) -> Tuple[str, List[str], List[str]]:
    """The C program, the lines it must print, with NaN bits as "nan", and
    the strings."""
    lines, expected, strings = [], [], []
    for _ in range(count):
        s = rand_string(rng)
        strings.append(s)
        lines.append(f'    check("{s.encode("unicode_escape").decode()}");')
        v, neg, inf, n = parse(s)
        d, drange = to_bits(v, neg, inf, DOUBLE)
        f, _ = to_bits(v, neg, inf, FLOAT)
        nan = v is None and not inf and n > 0
        dtext = "nan" if nan else f"{d:016x}"
        ftext = "nan" if nan else f"{f:08x}"
        normal = v is not None and (d >> 52) & 0x7FF != 0 and not drange
        if drange:
            err = str(ERANGE)
        elif normal or nan or inf or v == 0:
            err = "0"
        else:
            err = "*"  # a subnormal, or no conversion
        expected.append(f"{dtext} {n} {err} {ftext} {n}")
    text = r"""#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void check(const char *s)
{
    char *e1, *e2;
    errno = 0;
    double d = strtod(s, &e1);
    int err = errno;
    float f = strtof(s, &e2);
    uint64_t db;
    uint32_t fb;
    memcpy(&db, &d, 8);
    memcpy(&fb, &f, 4);
    if (d != d)
        printf("nan");
    else
        printf("%016llx", (unsigned long long)db);
    printf(" %d %d ", (int)(e1 - s), err);
    if (f != f)
        printf("nan");
    else
        printf("%08x", (unsigned)fb);
    printf(" %d\n", (int)(e2 - s));
}

int main(void)
{
"""
    text += "\n".join(lines) + "\n    return 0;\n}\n"
    return text, expected, strings


def run(cmd: List[str]) -> None:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(" ".join(cmd) + "\n" + p.stdout + p.stderr)


def matches(got: str, want: str) -> bool:
    g, w = got.split(), want.split()
    return len(g) == len(w) and all(b == "*" or a == b for a, b in zip(g, w))


def main() -> None:
    global FLOAT_LIB
    argv = sys.argv[1:]
    if argv[:1] == ["--no-fpu"]:
        FLOAT_LIB = "float.nasm"
        argv = argv[1:]
    if len(argv) != 2:
        sys.exit(__doc__.split("\n\n")[1])
    seed, count = int(argv[0]), int(argv[1])
    getcontext().prec = 1200
    text, expected, strings = program(random.Random(seed), count)
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "fuzz.c")
        with open(src, "w") as f:
            f.write(text)
        # The stack, the library's data, and the strings.
        pages = 2 + (sum(len(s) + 1 for s in strings) + 65535) // 65536
        wasm = os.path.join(tmp, "fuzz.wasm")
        run(["clang", *CFLAGS, *LDFLAGS, f"-Wl,--initial-memory={pages * 65536}", "-o", wasm, src,
             os.path.join(LIBC, "libc.a")])
        asm = os.path.join(tmp, "fuzz.nasm")
        run([sys.executable, NICEWASM, "--memory-pages", str(pages), "-o", asm, wasm])
        if FLOAT_LIB == "float.nasm":
            run(["make", "-s", "-C", RUNTIME, "float.nasm"])
        full = os.path.join(tmp, "fuzz.full.nasm")
        with open(full, "w") as out:
            for part in ["start_wasm.nasm", asm, "lib.nasm", "muldiv_mpu.nasm", FLOAT_LIB]:
                with open(part if os.path.isabs(part) else os.path.join(RUNTIME, part)) as f:
                    out.write(f.read() + "\n")
        binary = os.path.join(tmp, "fuzz.bin")
        run([sys.executable, NICEASM, "-o", binary, full])
        p = subprocess.run([NICEEMU, "-n", "2000000000", binary], capture_output=True)
    output = p.stdout.decode("latin-1")
    console = output[:output.index("Halted")] if "Halted" in output else output
    got = console.splitlines()
    bad = 0
    for i, (g, w) in enumerate(zip(got, expected)):
        if not matches(g, w):
            bad += 1
            if bad <= 20:
                print(f"MISMATCH in string {i}, {strings[i]!r}:\n  got  {g!r}\n  want {w!r}")
    if len(got) != len(expected) or p.returncode != 0:
        bad += 1
        print(f"{len(got)} lines instead of {len(expected)}, exit status {p.returncode}:\n"
              + "\n".join(output.splitlines()[-5:]))
    print(f"{'FAIL' if bad else 'PASS'} strtod fuzz (seed {seed}, {count} strings)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
