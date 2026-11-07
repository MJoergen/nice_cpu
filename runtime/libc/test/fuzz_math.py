#!/usr/bin/env python3
"""A random test of the C library's math functions, against the same code
on the host and against the host's own libm.

Usage: fuzz_math.py [--errors] SEED COUNT [NAME...]

It writes a C program that calls each function of math.h, or each NAME,
on COUNT inputs: the special values (zeros, infinities, NaNs, the limits,
and subnormals), random bits, and random numbers in the range where the
function is most used. The program prints the bits of each result. It is
compiled with clang and the library, translated, joined with the float
library, assembled, and run. The same program is compiled for the host,
with the library's math sources, and run there. Two checks follow:

- The two must give the same bits, but that any NaN equals any other: the
  float library rounds as the host does, so a difference is a fault of
  the float library, nicewasm, or the runtime.
- The exact functions (sqrt, fmod, frexp, ldexp, scalbn, modf, fmin,
  fmax, the roundings, fabs, and copysign) must give the host libm's
  result, through ctypes. The others must be within 1 ulp of the true
  value, the bound that the C library's README states, and give the
  host libm's result where that is not finite. The true value of a float
  function is the host's double function, rounded to double. That of exp,
  log, log2, log10, and pow comes from Python's decimal module, which
  rounds them correctly, and that of the other double functions is the
  host libm's, as glibc's are correctly rounded. A result is compared
  with the true value in units of the last place of the true value
  rounded to the result's type.

Needs clang with the wasm32 target and a host target, the host's libm,
and ../libc.a from make -C .. libc.a. The same seed always gives the same
program."""

from __future__ import annotations

import ctypes
import ctypes.util
import decimal
import glob
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
from typing import Callable, Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
LIBC = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(LIBC))
RUNTIME = os.path.join(REPO, "runtime")
NICEWASM = os.path.join(REPO, "translator", "nicewasm.py")
NICEASM = os.path.join(REPO, "assembler", "niceasm.py")
NICEEMU = os.path.join(REPO, "emulator", "zig-out", "bin", "niceemu")
INCLUDE = os.path.join(LIBC, "include")
MATH = os.path.join(LIBC, "src", "math")

CFLAGS = ["--target=wasm32", "-mbulk-memory", "-O2", "-ffreestanding", "-nostdlibinc",
          "-isystem", INCLUDE, "-Wall"]
LDFLAGS = ["-nostdlib", "-Wl,--no-entry", "-Wl,--export=main", "-Wl,--stack-first",
           "-Wl,-z,stack-size=65536"]
# The host build: no fused multiply-add, which wasm does not have, and
# SSE4.1, so that floor and the other roundings are instructions rather
# than calls of the functions that use them.
HOST_CFLAGS = ["-O2", "-ffp-contract=off", "-fno-math-errno", "-msse4.1", "-ffreestanding", "-nostdlibinc",
               "-isystem", INCLUDE, "-w"]

# The kinds of function: the argument types, then what it returns. d is a
# double, f a float, i an int; "pi" and "pd" a result through a pointer.
KINDS = {"d": ("d",), "dd": ("d", "d"), "di": ("d", "i"), "dpi": ("d",), "dpd": ("d",)}

# name: (kind, exact, the inputs it is most used with)
Gen = Callable[[random.Random, bool], Tuple[float, ...]]


def logu(lo: int, hi: int, signed: bool = True) -> Callable[[random.Random, bool], float]:
    """A number of magnitude 2^lo to 2^hi, with random bits below."""
    def g(rng: random.Random, single: bool) -> float:
        if single:
            lo2, hi2 = max(lo, -149), min(hi, 127)
        else:
            lo2, hi2 = lo, hi
        x = math.ldexp(1.0 + rng.random(), rng.randint(lo2, hi2))
        return -x if signed and rng.random() < 0.5 else x
    return g


def uniform(a: float, b: float) -> Callable[[random.Random, bool], float]:
    return lambda rng, single: rng.uniform(a, b)


def one(*gens: Callable[[random.Random, bool], float]) -> Gen:
    """One argument, from one of the generators."""
    return lambda rng, single: (rng.choice(gens)(rng, single),)


def two(a: Callable[[random.Random, bool], float],
        b: Callable[[random.Random, bool], float]) -> Gen:
    return lambda rng, single: (a(rng, single), b(rng, single))


def pow_args(rng: random.Random, single: bool) -> Tuple[float, ...]:
    r = rng.random()
    if r < 0.4:
        return (logu(-10, 10, False)(rng, single), rng.uniform(-40, 40))
    if r < 0.6:
        return (-logu(-5, 5, False)(rng, single), float(rng.randint(-60, 60)))
    if r < 0.8:
        return (1 + rng.uniform(-1e-3, 1e-3), rng.uniform(-1e5, 1e5))
    return (logu(-1074, 1023)(rng, single), logu(-30, 30)(rng, single))


def ldexp_args(rng: random.Random, single: bool) -> Tuple[float, ...]:
    return (logu(-1074, 1023)(rng, single), float(rng.randint(-2200, 2200)))


def half(rng: random.Random, single: bool) -> float:
    """A number that is k + 0.5, for the ties of round and rint."""
    return rng.randint(-1000, 1000) + 0.5


FUNCS: Dict[str, Tuple[str, bool, Gen]] = {
    "sin": ("d", False, one(uniform(-10, 10), logu(-30, 30), logu(-1074, 1023))),
    "cos": ("d", False, one(uniform(-10, 10), logu(-30, 30), logu(-1074, 1023))),
    "tan": ("d", False, one(uniform(-10, 10), logu(-30, 30), logu(-1074, 1023))),
    "asin": ("d", False, one(uniform(-1, 1), uniform(-1.1, 1.1), logu(-60, 0))),
    "acos": ("d", False, one(uniform(-1, 1), uniform(-1.1, 1.1), logu(-60, 0))),
    "atan": ("d", False, one(logu(-30, 60), logu(-1074, 1023))),
    "atan2": ("dd", False, two(logu(-30, 30), logu(-30, 30))),
    "exp": ("d", False, one(uniform(-760, 720), uniform(-1, 1), uniform(-110, 95))),
    "log": ("d", False, one(logu(-1074, 1023, False), uniform(0.99, 1.01))),
    "log10": ("d", False, one(logu(-1074, 1023, False), uniform(0.99, 1.01))),
    "log2": ("d", False, one(logu(-1074, 1023, False), uniform(0.99, 1.01))),
    "pow": ("dd", False, pow_args),
    "sqrt": ("d", True, one(logu(-1074, 1023, False))),
    "fmod": ("dd", True, two(logu(-20, 60), logu(-20, 60))),
    "frexp": ("dpi", True, one(logu(-1074, 1023))),
    "ldexp": ("di", True, ldexp_args),
    "scalbn": ("di", True, ldexp_args),
    "modf": ("dpd", True, one(logu(-30, 60), half)),
    "fmin": ("dd", True, two(logu(-3, 3), logu(-3, 3))),
    "fmax": ("dd", True, two(logu(-3, 3), logu(-3, 3))),
    "floor": ("d", True, one(logu(-30, 60), half)),
    "ceil": ("d", True, one(logu(-30, 60), half)),
    "trunc": ("d", True, one(logu(-30, 60), half)),
    "round": ("d", True, one(logu(-30, 60), half)),
    "rint": ("d", True, one(logu(-30, 60), half)),
    "nearbyint": ("d", True, one(logu(-30, 60), half)),
    "fabs": ("d", True, one(logu(-1074, 1023))),
    "copysign": ("dd", True, two(logu(-1074, 1023), logu(-1074, 1023))),
}

# The functions whose bound is more than 1 ulp: atan2f's errors reach
# 1.23 ulp on 1.1 million inputs, measured with --errors, and glibc's
# atan2f gives the same results there.
BOUNDS: Dict[str, float] = {"atan2f": 1.5}

SPECIALS = [0.0, -0.0, math.inf, -math.inf, math.nan, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0,
            5e-324, -5e-324, 2.2250738585072014e-308, 1.7976931348623157e308,
            -1.7976931348623157e308, math.pi, -math.pi, math.pi / 2, 10.0, 1e-300, 1e300]
SPECIALS_F = [0.0, -0.0, math.inf, -math.inf, math.nan, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0,
              1.401298464324817e-45, 1.1754943508222875e-38, 3.4028234663852886e+38,
              -3.4028234663852886e+38, 3.1415927410125732, 10.0, 1e-30, 1e30]


def to_f32(x: float) -> float:
    """x rounded to a float, or an infinity if it is too large."""
    try:
        return float(struct.unpack("<f", struct.pack("<f", x))[0])
    except OverflowError:
        return math.copysign(math.inf, x)


def bits(x: float, single: bool) -> int:
    if single:
        return int(struct.unpack("<I", struct.pack("<f", x))[0])
    return int(struct.unpack("<Q", struct.pack("<d", x))[0])


def inputs(rng: random.Random, name: str, single: bool, count: int) -> List[Tuple[float, ...]]:
    """COUNT argument tuples: a quarter special values, a quarter random
    bits, and the rest from the function's own range."""
    kind, _, gen = FUNCS[name]
    nargs = len(KINDS[kind])
    specials = SPECIALS_F if single else SPECIALS
    out: List[Tuple[float, ...]] = []
    for k in range(count):
        r = k % 4
        if r == 0:
            args = tuple(rng.choice(specials) for _ in range(nargs))
        elif r == 1:
            if single:
                args = tuple(struct.unpack("<f", struct.pack("<I", rng.getrandbits(32)))[0]
                             for _ in range(nargs))
            else:
                args = tuple(struct.unpack("<d", struct.pack("<Q", rng.getrandbits(64)))[0]
                             for _ in range(nargs))
        else:
            args = gen(rng, single)
        if kind == "di":
            args = (args[0], float(int(args[1]) if math.isfinite(args[1]) and abs(args[1]) < 1e4
                                   else rng.randint(-2200, 2200)))
        if single:
            args = tuple(to_f32(a) if i == 0 or kind != "di" else a for i, a in enumerate(args))
        out.append(args)
    return out


def program(cases: List[Tuple[str, bool, List[Tuple[float, ...]]]]) -> str:
    """The C program: an array of inputs and a loop for each function. Each
    prints the bits of its results in hex, one line per call."""
    text = ["#include <math.h>", "int printf(const char *, ...);",
            "typedef unsigned long long u64;",
            "static double D(u64 b) { union { u64 i; double d; } u = { b }; return u.d; }",
            "static u64 B(double d) { union { double d; u64 i; } u = { d }; return u.i; }",
            "static float F(unsigned b) { union { unsigned i; float f; } u = { b }; return u.f; }",
            "static unsigned FB(float f) { union { float f; unsigned i; } u = { f }; return u.i; }",
            ""]
    body = []
    for n, (name, single, args) in enumerate(cases):
        kind = FUNCS[name][0]
        fn = name + ("f" if single else "")
        width = 1 if kind in ("d", "dpi", "dpd") else 2
        if single:
            vals = [str(bits(a, True) if kind != "di" or i == 0 else int(a) & 0xFFFFFFFF) + "u"
                    for t in args for i, a in enumerate(t)]
            text.append(f"static const unsigned in{n}[] = {{{', '.join(vals)}}};")
        else:
            vals = [f"0x{bits(a, False) if kind != 'di' or i == 0 else int(a) & 0xFFFFFFFFFFFFFFFF:x}ull"
                    for t in args for i, a in enumerate(t)]
            text.append(f"static const u64 in{n}[] = {{{', '.join(vals)}}};")
        conv = "F" if single else "D"
        back = "FB" if single else "B"
        pr = '"%08x' if single else '"%016llx'
        lines = [f"    for (unsigned k = 0; k < {len(args) * width}; k += {width}) {{"]
        a0 = f"{conv}(in{n}[k])"
        if kind == "d":
            lines.append(f"        printf({pr}\\n\", {back}({fn}({a0})));")
        elif kind == "dd":
            lines.append(f"        printf({pr}\\n\", {back}({fn}({a0}, {conv}(in{n}[k + 1]))));")
        elif kind == "di":
            lines.append(f"        printf({pr}\\n\", {back}({fn}({a0}, (int)in{n}[k + 1])));")
        elif kind == "dpi":
            # C leaves the exponent unspecified for an infinity or a NaN,
            # and musl does not store it then.
            lines.append("        int e = 0;")
            lines.append(f"        u64 r = {back}({fn}({a0}, &e));")
            lines.append(f"        printf({pr} %d\\n\", r, e);")
        else:
            ty = "float" if single else "double"
            lines.append(f"        {ty} ip;")
            lines.append(f"        u64 r = {back}({fn}({a0}, &ip));")
            lines.append(f"        printf({pr} {pr[1:]}\\n\", r, (u64){back}(ip));")
        lines.append("    }")
        body += lines
    text.append("")
    text.append("int main(void)\n{")
    text += body
    text.append("    return 0;\n}")
    # A float's bits are printed from a u64 with %08x: give them their own type.
    out = "\n".join(text) + "\n"
    return out.replace('"%08x\\n", FB(', '"%08x\\n", (unsigned)FB(').replace(
        "u64 r = FB(", "unsigned r = FB(").replace("(u64)FB(ip)", "FB(ip)")


def run(cmd: List[str], cwd: Optional[str] = None) -> str:
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    if p.returncode != 0:
        sys.exit(" ".join(cmd) + "\n" + p.stdout + p.stderr)
    return p.stdout


def nice_lines(src: str, tmp: str, count: int) -> List[str]:
    """The console output of the program on niceemu. Its memory holds the
    stack, 64 KB, and the inputs, about 16 bytes for each call."""
    pages = 2 + (count * 2 * len(FUNCS) * 16 + 65535) // 65536
    wasm = os.path.join(tmp, "fuzz.wasm")
    run(["clang", *CFLAGS, *LDFLAGS, f"-Wl,--initial-memory={pages * 65536}", "-o", wasm, src,
         os.path.join(LIBC, "libc.a")])
    asm = os.path.join(tmp, "fuzz.nasm")
    run([sys.executable, NICEWASM, "--memory-pages", str(pages), "-o", asm, wasm])
    run(["make", "-s", "-C", RUNTIME, "float.nasm"])
    full = os.path.join(tmp, "fuzz.full.nasm")
    with open(full, "w") as out:
        for part in ["start_wasm.nasm", asm, "lib.nasm", "muldiv_mpu.nasm", "float.nasm"]:
            with open(part if os.path.isabs(part) else os.path.join(RUNTIME, part)) as f:
                out.write(f.read() + "\n")
    binary = os.path.join(tmp, "fuzz.bin")
    run([sys.executable, NICEASM, "-o", binary, full])
    p = subprocess.run([NICEEMU, "-n", "4000000000", binary], capture_output=True)
    output = p.stdout.decode("latin-1")
    if p.returncode != 0 or "Halted" not in output:
        sys.exit(f"niceemu exit status {p.returncode}:\n" + "\n".join(output.splitlines()[-5:]))
    return output[:output.index("Halted")].splitlines()


def host_lines(src: str, tmp: str) -> List[str]:
    """The output of the same program, with the same math sources, on the
    host."""
    objs = []
    for c in sorted(glob.glob(os.path.join(MATH, "*.c"))) + [src]:
        o = os.path.join(tmp, "h_" + os.path.basename(c)[:-2] + ".o")
        run(["clang", *HOST_CFLAGS, "-I", MATH, "-c", "-o", o, c])
        objs.append(o)
    exe = os.path.join(tmp, "host")
    run(["clang", "-o", exe, *objs])
    return run([exe]).splitlines()


def libm() -> ctypes.CDLL:
    name = ctypes.util.find_library("m")
    if name is None:
        sys.exit("no host libm")
    return ctypes.CDLL(name)


def reference(lib: ctypes.CDLL, name: str, single: bool, args: Tuple[float, ...]) -> str:
    """The host libm's result, printed as the program prints it."""
    kind = FUNCS[name][0]
    ty = ctypes.c_float if single else ctypes.c_double
    fn = getattr(lib, name + ("f" if single else ""))
    fn.restype = ty
    fmt = "{:08x}" if single else "{:016x}"
    if kind == "d":
        fn.argtypes = [ty]
        return fmt.format(bits(fn(args[0]), single))
    if kind == "dd":
        fn.argtypes = [ty, ty]
        return fmt.format(bits(fn(args[0], args[1]), single))
    if kind == "di":
        fn.argtypes = [ty, ctypes.c_int]
        return fmt.format(bits(fn(args[0], int(args[1])), single))
    if kind == "dpi":
        e = ctypes.c_int()
        fn.argtypes = [ty, ctypes.POINTER(ctypes.c_int)]
        r = fn(args[0], ctypes.byref(e))
        return fmt.format(bits(r, single)) + f" {e.value}"
    ip = ty()
    fn.argtypes = [ty, ctypes.POINTER(ty)]
    r = fn(args[0], ctypes.byref(ip))
    return fmt.format(bits(r, single)) + " " + fmt.format(bits(ip.value, single))


def value(h: str, single: bool) -> float:
    """The number whose bits are printed in h."""
    if single:
        return float(struct.unpack("<f", struct.pack("<I", int(h, 16)))[0])
    return float(struct.unpack("<d", struct.pack("<Q", int(h, 16)))[0])


def truth(lib: ctypes.CDLL, name: str, single: bool,
          args: Tuple[float, ...]) -> Optional[decimal.Decimal]:
    """The true value of a function that is not exact, if it is finite and
    known, as described above."""
    D = decimal.Decimal
    if single:
        fn = getattr(lib, name)
        fn.restype = ctypes.c_double
        fn.argtypes = [ctypes.c_double] * len(args)
        r = fn(*args)
        return D(r) if math.isfinite(r) else None
    if name not in ("exp", "log", "log2", "log10", "pow"):
        r = reference_value(lib, name, args)
        return D(r) if math.isfinite(r) else None
    with decimal.localcontext() as ctx:
        ctx.prec = 40
        x = D(args[0])
        if not x.is_finite():
            return None
        if name == "exp":
            return x.exp()
        if x <= 0 and name != "pow":
            return None
        if name == "log":
            return x.ln()
        if name == "log2":
            return x.ln() / D(2).ln()
        if name == "log10":
            return x.log10()
        y = D(args[1])
        if not y.is_finite() or x == 0 or (x < 0 and y != y.to_integral_value()):
            return None
        if y == 0:
            return D(1)
        r = (y * abs(x).ln()).exp()
        # An integer of 2^53 or more is even.
        odd = abs(y) < 2 ** 53 and int(y) % 2 == 1
        return -r if x < 0 and odd else r


def reference_value(lib: ctypes.CDLL, name: str, args: Tuple[float, ...]) -> float:
    fn = getattr(lib, name)
    fn.restype = ctypes.c_double
    fn.argtypes = [ctypes.c_double] * len(args)
    return float(fn(*args))


def ulp(x: float, single: bool) -> float:
    """The unit in the last place of x rounded to the type."""
    if single:
        x = abs(to_f32(x))
        if x < 2.0 ** -126:
            return 2.0 ** -149
        if math.isinf(x):
            return 2.0 ** 104
        return 2.0 ** (math.frexp(x)[1] - 24)
    return math.ulp(abs(x)) if math.isfinite(x) else 2.0 ** 971


def accurate(lib: ctypes.CDLL, name: str, single: bool, args: Tuple[float, ...],
             got: str, ref: str) -> Tuple[bool, str, float]:
    """Whether a result of a function that is not exact is within its
    bound of the true value, what was expected if it is not, and the
    error in ulps, 0 where the true value is not known."""
    r = value(got, single)
    bound = BOUNDS.get(name + ("f" if single else ""), 1.0)
    if not math.isfinite(r) or not math.isfinite(value(ref, single)):
        return same(got, ref, single, 0), ref, 0.0
    t = truth(lib, name, single, args)
    if t is None:
        return same(got, ref, single, math.ceil(bound)), ref, 0.0
    with decimal.localcontext() as ctx:
        ctx.prec = 40
        err = float(abs(decimal.Decimal(r) - t) / decimal.Decimal(ulp(float(t), single)))
    return err <= bound, f"{float(t)!r}, an error of {err:.3f} ulp", err


def c_minmax(name: str, single: bool, args: Tuple[float, ...]) -> str:
    """fmin or fmax as C defines it: a NaN is a missing value, signaling or
    not, and, as musl does and C17 F.10.9.2 calls ideal, -0 is below +0."""
    a, b = args
    if math.isnan(a):
        r = b
    elif math.isnan(b):
        r = a
    elif a == b == 0:
        neg = math.copysign(1, a) < 0 or math.copysign(1, b) < 0
        pos = math.copysign(1, a) > 0 or math.copysign(1, b) > 0
        r = -0.0 if (name == "fmin" and neg) or (name == "fmax" and not pos) else 0.0
    else:
        r = min(a, b) if name == "fmin" else max(a, b)
    return ("{:08x}" if single else "{:016x}").format(bits(r, single))


def is_nan(h: str, single: bool) -> bool:
    v = int(h, 16)
    return (v & 0x7FFFFFFF) > 0x7F800000 if single else \
        (v & 0x7FFFFFFFFFFFFFFF) > 0x7FF0000000000000


def same(a: str, b: str, single: bool, ulps: int) -> bool:
    """Whether two printed results agree: every field the same, any NaN
    equal to any other, and the first within ulps units in the last place.
    The numbers' order is that of their magnitudes, negative below 0."""
    fa, fb = a.split(), b.split()
    if len(fa) != len(fb):
        return False
    for i, (x, y) in enumerate(zip(fa, fb)):
        if x == y:
            continue
        if len(x) < 8:  # the exponent of frexp
            return False
        if is_nan(x, single) and is_nan(y, single):
            continue
        if is_nan(x, single) or is_nan(y, single) or i > 0 or ulps == 0:
            return False
        sign = 1 << (31 if single else 63)

        def key(h: str) -> int:
            v = int(h, 16)
            return -(v & ~sign) if v & sign else v
        if abs(key(x) - key(y)) > ulps:
            return False
    return True


def main() -> None:
    argv = sys.argv[1:]
    errors = argv[:1] == ["--errors"]
    if errors:
        argv = argv[1:]
    if len(argv) < 2:
        sys.exit(__doc__.split("\n\n")[1])
    seed, count = int(argv[0]), int(argv[1])
    names = argv[2:] or list(FUNCS)
    for n in names:
        if n not in FUNCS:
            sys.exit(f"no function {n}; the names are {' '.join(FUNCS)}")
    rng = random.Random(seed)
    cases = [(n, single, inputs(rng, n, single, count)) for n in names for single in (False, True)]
    src_text = program(cases)
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "fuzz.c")
        with open(src, "w") as f:
            f.write(src_text)
        got = nice_lines(src, tmp, count)
        host = host_lines(src, tmp)
    lib = libm()
    bad = 0
    line = 0
    worst: Dict[str, float] = {}
    total = sum(len(a) for _, _, a in cases)
    if len(got) != total or len(host) != total:
        print(f"{len(got)} lines on NICE, {len(host)} on the host, instead of {total}")
        bad += 1
    for name, single, args in cases:
        exact = FUNCS[name][1]
        fn = name + ("f" if single else "")
        for a in args:
            if line >= min(len(got), len(host)):
                break
            g, h = got[line], host[line]
            line += 1
            if name in ("fmin", "fmax"):
                ref = c_minmax(name, single, a)
            else:
                ref = reference(lib, name, single, a)
            if exact:
                ok, want = same(g, ref, single, 0), ref
            else:
                ok, want, err = accurate(lib, name, single, a, g, ref)
                worst[fn] = max(worst.get(fn, 0.0), err)
            for what, good, shown in (("host", same(g, h, single, 0), h), ("true", ok, want)):
                if not good:
                    bad += 1
                    if bad <= 20:
                        arg = ", ".join(f"{bits(x, single) if FUNCS[name][0] != 'di' or i == 0 else int(x):#x}"
                                        for i, x in enumerate(a))
                        print(f"MISMATCH {fn}({arg}): NICE {g}, {what} {shown}")
    if errors:
        for fn, err in worst.items():
            print(f"{fn:8} {err:.3f} ulp")
    print(f"{'FAIL' if bad else 'PASS'} math fuzz (seed {seed}, {count} inputs to each of "
          f"{2 * len(names)} functions)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
