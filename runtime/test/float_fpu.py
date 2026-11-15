#!/usr/bin/env python3
"""Checks float_fpu.nasm, the float library, against exact arithmetic.

Usage: float_fpu.py [--seed N] [--count N] [--keep DIR]

One program calls every routine of the float library for a float
operation on special operands, each with each, and on random ones:
values near the integers, the ties of the rounding, and the limits of
the conversions. Each result must be the one that the operation gives
in wasm, which reference() computes exactly with emulator/test/
fpu_model.py's formats, but that a NaN may be any NaN: the FPU gives
the canonical NaN, which wasm allows. A comparison must give libgcc's
result, -1, 0, or 1, and for a NaN the value that makes its test fail.

A routine leaves the FPU's stack as it found it, so that a caller may
keep values there across a call (DEVICES.md §11.5, ABI.md). So the
program pushes the 14 values of KEPT before the calls, the most that
leaves a routine room for its two operands. After the calls it reads the
FPU's STATUS, whose depth must be 14, with no stack fault, and then pops
the values, which must be those it pushed, and reads STATUS again, whose
depth must be 0.

It runs a second time with the float operations that nicewasm's
--inline-fpu writes inline: a wasm module has a function for each
routine, which does the wasm instruction that calls it, trunc_sat for a
conversion to an integer, translated with --inline-fpu, and the program
calls those functions instead. A comparison gives 0 or 1 there, which
must be the test of the routine's result. With --keep DIR, the first
program is left in DIR/float_fpu.bin for the tests of the FPGA cores.

A second program calls the routines of the functions of math.h in the
same way, with one value kept, as they use up to 15 (ABI.md). Their
results must be those of fpu_model.py's FPU, which runs the commands
that DEVICES.md §11.3 defines, with the special cases of C: pow of a
zero exponent or of 1 is 1, and hypot of an infinity is +inf, with a
NaN as the other operand too.
"""

import argparse
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
from fractions import Fraction
from typing import Callable, Dict, List, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME = os.path.dirname(HERE)
ROOT = os.path.dirname(RUNTIME)
NICEASM = os.path.join(ROOT, "assembler", "niceasm.py")
NICEEMU = os.environ.get("NICEEMU", os.path.join(ROOT, "emulator", "zig-out", "bin", "niceemu"))
NICEWASM = os.path.join(ROOT, "translator", "nicewasm.py")
sys.path.insert(0, os.path.join(ROOT, "translator"))
sys.path.insert(0, os.path.join(ROOT, "translator", "test"))
sys.path.insert(0, os.path.join(ROOT, "emulator", "test"))
import fpu_model  # noqa: E402
import nicewasm  # noqa: E402
import wasm  # noqa: E402
from fpu_model import F32, F64, Format  # noqa: E402

# The routines: label -> (the types of the operands, the type of the
# result). f is an f32, d an f64, i a word, and l a long long.
ROUTINES: Dict[str, Tuple[str, str]] = {}
for _s, _t in (("sf", "f"), ("df", "d")):
    for _n in ("add", "sub", "mul", "div"):
        ROUTINES[f"___{_n}{_s}3"] = (_t + _t, _t)
    for _n in ("min", "max"):
        ROUTINES[f"___{_n}{_s}"] = (_t + _t, _t)
    for _n in ("sqrt", "ceil", "floor", "trunc", "nearest"):
        ROUTINES[f"___{_n}{_s}"] = (_t, _t)
    for _n in ("eq", "ne", "lt", "le", "gt", "ge"):
        ROUTINES[f"___{_n}{_s}2"] = (_t + _t, "i")
    for _from, _int, _i in (("si", "si", "i"), ("unsi", "unssi", "i"), ("di", "di", "l"),
                            ("undi", "unsdi", "l")):
        ROUTINES[f"___float{_from}{_s}"] = (_i, _t)
        _u = "uns" if "uns" in _int else ""
        ROUTINES[f"___fix{_u}{_s}{_int[-2:]}"] = (_t, _i)
ROUTINES["___extendsfdf2"] = ("f", "d")
ROUTINES["___truncdfsf2"] = ("d", "f")
WORDS = {"f": 1, "i": 1, "d": 2, "l": 2}

# The routines of the functions of math.h: label -> (the types of the
# operands, the type of the result, the command). The float version of
# each has the label with f, and the types with f for d.
MATH: Dict[str, Tuple[str, str, int]] = {}
for _name, _cmd in (("_nice_sin", 0x40), ("_nice_cos", 0x41), ("_nice_tan", 0x42), ("_asin", 0x43),
                    ("_acos", 0x44), ("_atan", 0x45), ("_log", 0x48), ("_log2", 0x49),
                    ("_log10", 0x4A), ("_exp", 0x4C), ("_exp2", 0x4D), ("_round", 0x24),
                    ("_atan2", 0x46), ("_fmod", 0x1D), ("_pow", 0x4E), ("_hypot", 0x4F),
                    ("_ldexp", 0x38), ("_scalbn", 0x38)):
    _args = "di" if _cmd == 0x38 else "dd" if _cmd in (0x46, 0x1D, 0x4E, 0x4F) else "d"
    MATH[_name] = (_args, "d", _cmd)
    if not _name.startswith("_nice"):
        MATH[_name + "f"] = (_args.replace("d", "f"), "f", _cmd)
M32 = 0xFFFFFFFF

# The values that the program keeps on the FPU's stack across the calls,
# pushed in this order as raw bits, a NaN with a payload among them, and
# the one value that the program of the functions keeps.
KEPT = [0x3FF0000000000000 + (i << 44) + 0x0123456789 * i for i in range(13)] + [0x7FF4000000000BAD]
KEPT_MATH = [0x7FF4000000000BAD]
STACK_FAULT = 1 << 11

F32_SPECIALS = [0x00000000, 0x80000000, 0x00000001, 0x80000001, 0x007FFFFF, 0x00800000,
                0x7F7FFFFF, 0xFF7FFFFF, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000,
                0x7F800001, 0x7FC12345, 0x3F800000, 0xBF800000, 0x3FC00000, 0xC0200000,
                0x3F000000, 0x40400000, 0x4B000001, 0x4EFFFFFF, 0x4F000000, 0xCF000000,
                0xCF000001, 0x4F800000, 0x5F000000, 0xDF000000, 0x5F800000, 0xBF7FFFFF]
F64_SPECIALS = [0x0000000000000000, 0x8000000000000000, 0x0000000000000001, 0x8000000000000001,
                0x000FFFFFFFFFFFFF, 0x0010000000000000, 0x7FEFFFFFFFFFFFFF, 0xFFEFFFFFFFFFFFFF,
                0x7FF0000000000000, 0xFFF0000000000000, 0x7FF8000000000000, 0xFFF8000000000000,
                0x7FF0000000000001, 0x7FF8000012345678, 0x3FF0000000000000, 0xBFF0000000000000,
                0x3FF8000000000000, 0xC004000000000000, 0x3FE0000000000000, 0x4330000000000001,
                0x41DFFFFFFFC00000, 0x41E0000000000000, 0xC1E0000000000000, 0xC1E0000000200000,
                0x41EFFFFFFFE00000, 0x41F0000000000000, 0x43E0000000000000, 0xC3E0000000000000,
                0x43F0000000000000, 0x36A0000000000000, 0x47EFFFFFE0000000, 0x47EFFFFFF0000000,
                0x3810000000000000, 0x380FFFFFF0000000]
I64_SPECIALS = [0, 1, (1 << 64) - 1, 1 << 63, (1 << 63) - 1, (1 << 24) + 1, (1 << 53) - 1,
                1 << 53, (1 << 53) + 1, (1 << 54) + 3, 0x7FFFFF8000000000, 0x7FFFFFC000000000,
                0xFFFFFF8000000000, 0xFFFFFF7FFFFFFFFF, (1 << 64) - (1 << 53) - 1, 0x00FFFFFF80000001,
                0x0000000100000000, 0xFFFFFFFF00000000, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
                0xFFFFFFFF80000000,
                # Above 2^53, a tie of the rounding to binary32 with a 1 in
                # bit 0, which a conversion through binary64 loses: kept
                # part even, which rounds down without the sticky bit, odd,
                # and their negatives.
                (1 << 60) | (1 << 36) | 1, (1 << 60) | (3 << 36) | 1,
                (1 << 63) | (1 << 39) | 1, (1 << 54) | (1 << 30) | 1,
                -((1 << 60) | (1 << 36) | 1) & ((1 << 64) - 1),
                -((1 << 62) | (1 << 38) | 1) & ((1 << 64) - 1),
                (1 << 60) | (1 << 36) | (1 << 10), (1 << 60) | (1 << 36) - 1]


def random_f32(r: random.Random) -> int:
    k = r.randrange(6)
    if k == 0:
        return r.getrandbits(32)
    if k == 1:  # a small integer, or a half
        v = r.randrange(-300, 300) / r.choice([1, 2, 4])
        return int.from_bytes(struct.pack(">f", v), "big")
    if k == 2:  # near the limits of the conversions and the integers
        return (r.choice([0x4B, 0x4E, 0x4F, 0x5E, 0x5F, 0xCE, 0xCF, 0xDE, 0xDF, 0x4A, 0x3F, 0xBF]) << 24
                | r.getrandbits(24))
    if k == 3:  # a subnormal or near one
        return r.getrandbits(1) << 31 | r.randrange(0, 0x01000000)
    return r.getrandbits(1) << 31 | r.randrange(0x30000000, 0x50000000)


def random_f64(r: random.Random) -> int:
    k = r.randrange(6)
    if k == 0:
        return r.getrandbits(64)
    if k == 1:
        v = r.randrange(-3000, 3000) / r.choice([1, 2, 4, 8])
        return int.from_bytes(struct.pack(">d", v), "big")
    if k == 2:
        return (r.choice([0x433, 0x41D, 0x41E, 0x41F, 0x43D, 0x43E, 0x43F, 0xC1E, 0xC3E, 0x432, 0x3FF,
                          0x47E, 0x380, 0x381, 0x36A, 0x369]) << 52 | r.getrandbits(52))
    if k == 3:
        return r.getrandbits(1) << 63 | r.randrange(0, 1 << 54)
    if k == 4:  # a binary32 value, exact, or one ulp of binary32 and a half away
        b = int.from_bytes(struct.pack(">d", struct.unpack(">f", random_f32(
            r).to_bytes(4, "big"))[0]), "big")
        return (b + r.choice([0, 1 << 28, (1 << 28) - 1, (1 << 28) + 1, -(1 << 28)])) & ((1 << 64) - 1)
    return r.getrandbits(1) << 63 | r.randrange(0x3C00000000000000, 0x4400000000000000)


def random_i64(r: random.Random) -> int:
    k = r.randrange(5)
    if k == 0:
        return r.getrandbits(64)
    if k == 1:
        return r.randrange(-(1 << 31), 1 << 31) & ((1 << 64) - 1)
    if k == 2:  # near a tie of the rounding to binary32 or binary64
        s = r.randrange(25, 64)
        m = r.getrandbits(s)
        keep = r.choice([24, 53])
        if s <= keep:
            return m
        low = s - keep
        m = (m >> low << low) | (1 << (low - 1)) + r.choice([-1, 0, 0, 1])
        return (m if r.getrandbits(1) else -m) & ((1 << 64) - 1)
    if k == 3:
        return r.getrandbits(r.randrange(1, 64))
    return (-r.getrandbits(r.randrange(1, 64))) & ((1 << 64) - 1)


def operands(r: random.Random, t: str) -> int:
    if t == "f":
        return random_f32(r)
    if t == "d":
        return random_f64(r)
    v = random_i64(r)
    return v & 0xFFFFFFFF if t == "i" else v


def specials(t: str) -> List[int]:
    if t == "f":
        return F32_SPECIALS
    if t == "d":
        return F64_SPECIALS
    if t == "i":
        return sorted({v & 0xFFFFFFFF for v in I64_SPECIALS} | {0x4B000001, 0x01000001, 0xFF000001})
    return I64_SPECIALS


def cases(r: random.Random, args: str, count: int) -> List[Tuple[int, ...]]:
    """The operands of a routine: the specials, each with each, and random
    ones."""
    out: List[Tuple[int, ...]] = []
    if len(args) == 1:
        out += [(v,) for v in specials(args)]
    else:
        out += [(a, b) for a in specials(args[0]) for b in specials(args[1])]
    for _ in range(count):
        a = operands(r, args[0])
        if len(args) == 1:
            out.append((a,))
        elif r.randrange(4) == 0:  # close to a, for the cancellation
            out.append((a, a ^ r.getrandbits(r.randrange(1, 30)) ^ (r.getrandbits(1) << (WORDS[args[0]] * 32 - 1))))
        else:
            out.append((a, operands(r, args[1])))
    return out


def words(args: str, values: Tuple[int, ...]) -> List[int]:
    """The four words of R1 to R4 for the operands (ABI.md)."""
    out: List[int] = []
    for t, v in zip(args, values):
        out += [v & 0xFFFFFFFF] + ([v >> 32] if WORDS[t] == 2 else [])
    return out + [0] * (4 - len(out))


def program(calls: List[Tuple[str, List[int]]], kept: List[int]) -> str:
    """The test's main: the values of kept pushed; for each call, R1 to R4
    from the table, the call, and R1 and R2 to the results; then STATUS,
    the kept values, popped, and STATUS again."""
    lines = ["_main          MOVE    R10, TABLE",
             "                MOVE    R11, RESULTS"]
    for v in kept:
        lines += [f"                MOVE    @0xFFFFFF88, 0x{v & 0xFFFFFFFF:08X}  ; X_LO",
                  f"                MOVE    @0xFFFFFF89, 0x{v >> 32:08X}  ; X_HI"]
    lines += [
             f"                MOVE    R9, {len(calls)}",
             ":               MOVE    R1, @R10++",
             "                MOVE    R2, @R10++",
             "                MOVE    R3, @R10++",
             "                MOVE    R4, @R10++",
             "                MOVE    R8, @R10++",
             "                CALL    R8",
             "                MOVE    @R11++, R1",
             "                MOVE    @R11++, R2",
             "                DEC[M]  R9, R9",
             "        ?!Z     JMP     :-",
             "                MOVE    @R11++, @0xFFFFFF8D  ; STATUS"]
    for _ in kept:
        lines += ["                MOVE    @R11++, @0xFFFFFF88  ; X_LO",
                  "                MOVE    @R11++, @0xFFFFFF89  ; X_HI",
                  "                MOVE    @0xFFFFFF8C, 3  ; DROP"]
    lines += ["                MOVE    @R11++, @0xFFFFFF8D  ; STATUS",
              "                MOVE    R1, R0",
              "                RET",
              "TABLE"]
    for label, w in calls:
        lines.append("                .DAT    " + ", ".join(f"0x{x:08X}" for x in w) + f", {label}")
    lines.append("RESULTS         .RES    " + str(2 * len(calls) + 2 + 2 * len(kept)))
    return "\n".join(lines) + "\n"


# The wasm instruction of each routine, and for a comparison its test.
WASM_TYPES = {"f": wasm.F32, "d": wasm.F64, "i": wasm.I32, "l": wasm.I64}
OPCODES: Dict[str, bytes] = {}
TESTS: Dict[str, str] = {}
for _op, (_routine, _params, _result) in nicewasm.FLOAT_OPS.items():
    OPCODES["_" + _routine] = bytes([_op])
for _sat, _op in nicewasm.TRUNC_SAT_OPS.items():
    OPCODES["_" + nicewasm.TRUNC_OPS[_op][0]] = b"\xfc" + wasm.u(_sat - 0x100)
for _op, (_ctype, _routine, _test) in nicewasm.FLOAT_CMP_OPS.items():
    OPCODES["_" + _routine] = bytes([_op])
    TESTS["_" + _routine] = _test


def inline_module() -> bytes:
    """A wasm module with the function t_X for each routine ___X, which
    does the routine's wasm instruction on its parameters."""
    labels = sorted(ROUTINES)
    fts = []
    for label in labels:
        args, result = ROUTINES[label]
        res = "i" if label in TESTS else result
        fts.append(([WASM_TYPES[t] for t in args], [WASM_TYPES[res]]))
    bodies = []
    for label in labels:
        args, _ = ROUTINES[label]
        body = b"".join(wasm.local_get(i) for i in range(len(args))) + OPCODES[label]
        bodies.append((0, body))
    return wasm.module(wasm.types(*fts), wasm.funcs(*range(len(labels))),
                       wasm.exports(*[("t_" + label[3:], 0, i) for i, label in enumerate(labels)]),
                       wasm.code(*bodies))


def fmt(t: str) -> Format:
    return F32 if t == "f" else F64


def min_max(f: Format, a: int, b: int, want_max: bool) -> int:
    """wasm's min and max: a NaN gives a NaN, and -0 is below +0."""
    if f.is_nan(a) or f.is_nan(b):
        return f.qnan
    c = f.compare(a, b)
    assert c is not None
    if c == 0:  # equal, or zeros of either sign: the sign bits ANDed or ORed
        return a & b if want_max else a | b
    return a if (c > 0) == want_max else b


def signed(v: int, bits: int) -> int:
    return v - (1 << bits) if v >> (bits - 1) else v


def reference(label: str, values: Tuple[int, ...]) -> int:
    """The result of the float operation of a routine of ROUTINES, exact,
    as the bits of its type."""
    args, result = ROUTINES[label]
    name = label[3:]
    f = fmt(args[0])
    a = values[0]
    b = values[1] if len(values) > 1 else 0
    for op in ("add", "sub", "mul", "div"):
        if name == f"{op}{name[3:5]}3":
            r: int = getattr(f, op)(a, b)[0]
            return r
    if name[:3] in ("min", "max"):
        return min_max(f, a, b, name[:3] == "max")
    if name[:-2] in ("sqrt", "ceil", "floor", "trunc", "nearest"):
        how = name[:-2]
        if how == "sqrt":
            return f.sqrt(a)[0]
        return f.to_integral(a, "even" if how == "nearest" else how)[0]
    if len(name) == 5 and name[:2] in ("eq", "ne", "lt", "le", "gt", "ge"):
        c = f.compare(a, b)
        if c is None:  # a NaN: the value that makes the test fail
            c = -1 if name[0] == "g" else 1
        return c & M32
    if name.startswith("float"):
        bits = 32 if args == "i" else 64
        i = a if "un" in name else signed(a, bits)
        return fmt(result).round(Fraction(i))[0]
    if name.startswith("fix"):
        bits = 32 if result == "i" else 64
        return f.to_int(a, bits, "uns" not in name)[0] & ((1 << bits) - 1)
    if name == "extendsfdf2":
        return F64.convert(a, F32)[0]
    assert name == "truncdfsf2"
    return F32.convert(a, F64)[0]


def is_inf(t: str, v: int) -> bool:
    return fmt(t).is_inf(v)


def math_reference(label: str, values: Tuple[int, ...]) -> int:
    """The result of a routine of MATH: the special cases of C, and
    otherwise the command on fpu_model.py's FPU, with the operands pushed
    and the result read as the routine does."""
    args, result, cmd = MATH[label]
    t = args[0]
    one = 0x3F800000 if t == "f" else 0x3FF0000000000000
    if label.startswith("_pow"):
        x, y = values
        if fmt(t).is_zero(y) or x == one:
            return one
    if label.startswith("_hypot") and (is_inf(t, values[0]) or is_inf(t, values[1])):
        return fmt(t).inf
    fpu = fpu_model.FPU()
    for ty, v in zip(args, values):
        if ty == "d":
            fpu.write(fpu_model.X_LO, v & M32)
            fpu.write(fpu_model.X_HI, v >> 32)
        else:
            fpu.write(fpu_model.X_S if ty == "f" else fpu_model.X_W, v)
    fpu.write(fpu_model.CMD, cmd)
    return fpu.read(fpu_model.X_S) if result == "f" else fpu.x()


def is_nan(t: str, v: int) -> bool:
    if t == "f":
        return (v & 0x7FFFFFFF) > 0x7F800000
    return t == "d" and (v & 0x7FFFFFFFFFFFFFFF) > 0x7FF0000000000000


def run(tmp: str, main: str, kept: List[int], name: str, module: str = "") -> List[int]:
    """Joins the program with float_fpu.nasm, and the translated module if
    given, assembles it as tmp/name.bin, runs it, and returns the
    results."""
    src = os.path.join(tmp, name + ".nasm")
    with open(src, "w") as f:
        for part in ["start_wasm.nasm" if module else "start.nasm", None, "lib.nasm",
                     "muldiv_mpu.nasm", "float_fpu.nasm"]:
            if part is None:
                f.write(main + module)
            else:
                with open(os.path.join(RUNTIME, part)) as p:
                    f.write(p.read())
    binary = os.path.join(tmp, name + ".bin")
    sym_file = os.path.join(tmp, name + ".sym")
    subprocess.run([sys.executable, NICEASM, "-o", binary, "--symbols", sym_file, src], check=True)
    with open(sym_file) as f:
        sym = dict((p[1], int(p[0], 16)) for p in (line.split() for line in f) if len(p) == 2)
    count = main.count(".DAT")
    base = sym["RESULTS"]
    proc = subprocess.run([NICEEMU, "-n", "200000000", "-d", f"0x{base:x}:{2 * count + 2 + 2 * len(kept)}",
                           binary], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if proc.returncode != 0:
        raise RuntimeError(f"{name}: exit {proc.returncode}\n{proc.stdout[-2000:]}{proc.stderr}")
    out: List[int] = []
    for line in proc.stdout.splitlines():
        head, _, rest = line.partition(":")
        if rest and len(head) == 8 and int(head, 16) >= base:
            out += [int(w, 16) for w in rest.split()]
    return out


def kept_failures(what: str, tail: List[int], kept: List[int]) -> List[str]:
    """What is wrong with the FPU's stack after the calls: tail is STATUS,
    the kept values popped from the top, and STATUS again."""
    out: List[str] = []
    status, popped, last = tail[0], tail[1:-1], tail[-1]
    if status & 0x1F != len(kept) or status & STACK_FAULT:
        out.append(f"{what}: after the calls, the FPU's depth is {status & 0x1F}, not {len(kept)},"
                   f" or the stack fault is set: STATUS 0x{status:08X}")
    for i, v in enumerate(reversed(kept)):
        got = popped[2 * i] | popped[2 * i + 1] << 32
        if got != v:
            out.append(f"{what}: kept value {len(kept) - 1 - i} is 0x{got:016X}, not 0x{v:016X}")
    if last & 0x1F != 0 or last & STACK_FAULT:
        out.append(f"{what}: after the pops, STATUS 0x{last:08X}")
    return out


def result_of(out: List[int], i: int, t: str) -> int:
    """The result of call i, of type t, from the words that the program
    stored."""
    return out[2 * i] | (out[2 * i + 1] << 32 if WORDS[t] == 2 else 0)


def ops_text(values: Tuple[int, ...]) -> str:
    return ", ".join(f"0x{v:X}" for v in values)


def check_results(what: str, meta: List[Tuple[str, str, Tuple[int, ...]]], out: List[int],
                  ref: Callable[[str, Tuple[int, ...]], int]) -> List[str]:
    """The calls whose results differ from ref's, but that a NaN may be
    any NaN."""
    failures = []
    for i, (label, result, values) in enumerate(meta):
        got, want = result_of(out, i, result), ref(label, values)
        if got != want and not (is_nan(result, got) and is_nan(result, want)):
            failures.append(f"{label}({ops_text(values)}){what}: 0x{got:X}, want 0x{want:X}")
    return failures


def main() -> None:
    ap = argparse.ArgumentParser(description="float_fpu.nasm against exact arithmetic")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=300, help="random cases for each routine")
    ap.add_argument("--keep", help="leave the program of the float operations in DIR/float_fpu.bin")
    args = ap.parse_args()
    r = random.Random(args.seed)
    calls: List[Tuple[str, List[int]]] = []
    meta: List[Tuple[str, str, Tuple[int, ...]]] = []
    for label in sorted(ROUTINES):
        types, result = ROUTINES[label]
        for values in cases(r, types, args.count):
            calls.append((label, words(types, values)))
            meta.append((label, result, values))
    math_calls: List[Tuple[str, List[int]]] = []
    math_meta: List[Tuple[str, str, Tuple[int, ...]]] = []
    for label in sorted(MATH):
        types, result, _ = MATH[label]
        for values in cases(r, types, args.count // 3):
            math_calls.append((label, words(types, values)))
            math_meta.append((label, result, values))
    with tempfile.TemporaryDirectory() as tmp:
        fpu = run(tmp, program(calls, KEPT), KEPT, "float_fpu")
        mod = os.path.join(tmp, "inline.wasm")
        with open(mod, "wb") as wf:
            wf.write(inline_module())
        subprocess.run([sys.executable, NICEWASM, "--inline-fpu", "-o", mod + ".nasm", mod], check=True)
        with open(mod + ".nasm") as nf:
            module_text = nf.read()
        inline_text = program([("_t_" + label[3:], w) for label, w in calls], KEPT)
        inline = run(tmp, inline_text, KEPT, "inline", module_text)
        if args.keep:
            os.makedirs(args.keep, exist_ok=True)
            shutil.copy(os.path.join(tmp, "float_fpu.bin"), os.path.join(args.keep, "float_fpu.bin"))
        math = run(tmp, program(math_calls, KEPT_MATH), KEPT_MATH, "math")
    failures = check_results("", meta, fpu, reference)
    for i, (label, result, values) in enumerate(meta):
        want = reference(label, values)
        c = result_of(inline, i, "i" if label in TESTS else result)
        if label in TESTS:
            v = signed(want, 32)
            passes = int({"==": v == 0, "!=": v != 0, "<": v < 0, "<=": v <= 0, ">": v > 0,
                          ">=": v >= 0}[TESTS[label]])
            if c != passes:
                failures.append(f"{label}({ops_text(values)}) inline: {c}, the routine's test {passes}")
        elif c != want and not (is_nan(result, c) and is_nan(result, want)):
            failures.append(f"{label}({ops_text(values)}) inline: 0x{c:X}, want 0x{want:X}")
    failures += check_results("", math_meta, math, math_reference)
    for out, what, kept, n in ((fpu, "float_fpu.nasm", KEPT, len(meta)), (inline, "inline", KEPT, len(meta)),
                               (math, "math", KEPT_MATH, len(math_meta))):
        failures += kept_failures(what, out[2 * n:], kept)
    for f in failures[:30]:
        print(f)
    total = len(meta) + len(math_meta)
    if failures:
        print(f"FAIL float_fpu: {len(failures)} of {total} calls")
        sys.exit(1)
    print(f"PASS float_fpu ({len(meta)} calls of {len(ROUTINES)} routines, and inline, and"
          f" {len(math_meta)} of the {len(MATH)} routines of math.h)")


if __name__ == "__main__":
    main()
