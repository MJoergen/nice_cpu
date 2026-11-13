#!/usr/bin/env python3
"""The test vectors of the FPU of doc/SYSTEM.md §11, from fpu_model.py.

A vector is one access: the state before it, the access, and the state
after it. The state is all of the FPU's state, the flags and the stack,
so each line stands alone, and a line that fails is its own smallest
case. The emulator, tb_fpu, both cores, and the board replay the same
lines. No expected value comes from niceemu.

A line is fields of hex digits, separated by spaces:

    F DD V1 ... Vn : A R WWWWWWWW : F DD V1 ... Vn

F is the flags, bits 11..8 of FPU_STATUS, DD the depth, and V1 to Vn
the values of the stack, the deepest first, each 16 digits. A is R for
a read and W for a write, R the register, its offset 0 to 7 from
0xFFFFFF88, and W the word written, or the word that the read returns.
A line that starts with # is a comment.

The vectors are of two kinds. The directed ones come from the lists
below, by group: the registers, every command number and the command
words that are not valid, the depths 0, 1, 2, 15, and 16, the special
values each with each, the rounding, the conversions, and the decimal
commands. The random ones are a sequence of accesses from a seed, so
that the depth and the faults take part.

The coverage counts bins: the command, the class of each operand, the
rounding case (exact, down, up, or a tie, by magnitude), the class of
the result, and the flags each command sets. For each S form it also
counts the results that the command and then ROUND32 would not give,
which round twice. It fails if a bin that can occur is empty, and if a
command sets a flag that its row of FLAGS does not allow.

    fpu_vectors.py [-o FILE] [--seed S] [--count N]

writes the vectors to FILE, if given, checks the coverage, and parses
each line back and replays it on the model. It exits 1 on a failure."""

from __future__ import annotations

import argparse
import os
import random
import sys
from fractions import Fraction
from typing import Dict, Iterator, List, Optional, Set, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fpu_model import (  # noqa: E402
    CANONICAL_NAN,
    CMD,
    COMMANDS,
    DEPTH,
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
    pow2,
    round32,
    s64,
)

State = Tuple[Tuple[int, ...], int]
Access = Tuple[str, int, int]  # "R" or "W", the offset, the word
Line = Tuple[State, Access, State]

# Values, one or more of each class.
NZ = F64.sign
SPECIALS = [
    0, NZ, 0x0000000000000001, 0x8000000000000001, 0x000FFFFFFFFFFFFF, 0x0010000000000000,
    0x8010000000000000, 0x3FE0000000000000, 0x3FF0000000000000, 0xBFF0000000000000, 0x3FF8000000000000,
    0x4000000000000000, 0x4008000000000000, 0xC004000000000000, 0x3FB999999999999A, 0x7E37E43C8800759C,
    0x81A56E1FC2F8F359, 0x7FEFFFFFFFFFFFFF, 0xFFEFFFFFFFFFFFFF, F64.inf, F64.inf | NZ, 0x7FF8000000000123,
    0xFFF8000000000000, 0x7FF0000000000001, 0xFFF4000000000000, 0x41DFFFFFFFE00000, 0xC1E0000000000000,
    0x4340000000000000, 0x43E0000000000000,
]

# The flags each command may set, but the stack fault: a command that
# sets another fails the coverage, and one that never sets one of these
# leaves a bin empty.
I, Z, O = INVALID, DIVZERO, OVERFLOW
FLAGS: Dict[str, int] = {
    "NOP": 0, "CLEAR": 0, "DUP": 0, "DROP": 0, "SWAP": 0, "OVER": 0, "PICK": 0,
    "ADD": I | O, "SUB": I | O, "MUL": I | O, "DIV": I | Z | O, "SQRT": I,
    "ADD.S": I | O, "SUB.S": I | O, "MUL.S": I | O, "DIV.S": I | Z | O, "SQRT.S": I | O,
    "NEG": 0, "ABS": 0, "MIN": I, "MAX": I, "ROUND32": I | O, "ISQRT": I, "SIGN": I, "CMP": I, "FMOD": I,
    "FLOOR": I, "CEIL": I, "TRUNC": I, "NEAREST": I, "ROUND": I,
    "ITOF": 0, "UTOF": 0, "FTOI": I, "FTOU": I, "CONST": I, "SCALE2": I | O, "SCALE10": I | O,
    "DIGITS": I, "FROMBCD": I, "GETEXP": I | Z, "GETMANT": I,
    "AND": I, "OR": I, "XOR": I, "NOT": I, "SHL": I, "SHR": I, "IDIV": I, "MOD": I,
}

# The values each command pushes. The others push one.
PUSHES = {"NOP": 0, "CLEAR": 0, "DROP": 0, "SWAP": 2, "DIGITS": 2}

# The commands that copy a value and pop none, with the n they copy.
COPIES = {"DUP": 0, "OVER": 1}

# The rounding cases that can occur, for the commands that round. A
# square root is never a tie, nor is a quotient but in the subnormals,
# such as 3 · 2^-1074 / 2. FROMBCD's 16 digits are below 2^54, so a
# value it rounds is odd, and a tie.
ALL4 = {"exact", "down", "up", "tie"}
ROUNDING: Dict[str, Set[str]] = {
    "ADD": ALL4, "SUB": ALL4, "MUL": ALL4, "DIV": ALL4, "SQRT": {"exact", "down", "up"},
    "ADD.S": ALL4, "SUB.S": ALL4, "MUL.S": ALL4, "DIV.S": ALL4, "SQRT.S": ALL4,
    "ROUND32": ALL4, "ITOF": ALL4, "UTOF": ALL4, "SCALE2": ALL4, "FROMBCD": {"exact", "tie"}, "R X_S": ALL4,
}

CLASSES = ["+0", "-0", "+sub", "-sub", "+norm", "-norm", "+inf", "-inf", "qnan", "snan"]
RESULTS = [c for c in CLASSES if c != "snan"]
RESULT_CLASSES: Dict[str, List[str]] = {
    "ADD": RESULTS, "SUB": RESULTS, "MUL": RESULTS, "DIV": RESULTS,
    "SQRT": ["+0", "-0", "+norm", "+inf", "qnan"],
    "SCALE2": RESULTS, "SCALE10": RESULTS,
}

REG_NAMES = ["X_LO", "X_HI", "X_S", "X_W", "CMD", "STATUS", "REL", "7"]


def klass(a: int) -> str:
    sign = "-" if F64.is_neg(a) else "+"
    if F64.is_nan(a):
        return "snan" if F64.is_snan(a) else "qnan"
    if F64.is_inf(a):
        return sign + "inf"
    if F64.is_zero(a):
        return sign + "0"
    return sign + ("sub" if a & ~NZ < 0x0010000000000000 else "norm")


def rounding_case(fmt: Format, q: Fraction, r: int) -> str:
    """How r is q rounded in fmt: exact, down or up in magnitude, or a tie."""
    if fmt.is_finite(r) and fmt.value(r) == q:
        return "exact"
    lo = fmt.round(q, toward_zero=True)[0]
    hi = lo + 1
    lv = abs(fmt.value(lo))
    hv = pow2(fmt.emax + 1) if fmt.is_inf(hi) else abs(fmt.value(hi))
    if 2 * abs(q) == lv + hv:
        return "tie"
    return "down" if r == lo else "up"


def tie32(a: int) -> bool:
    """Whether the binary64 value a lies halfway between two binary32
    values, so that ROUND32 of it is a tie."""
    return F64.is_finite(a) and rounding_case(F32, F64.value(a), F32.convert(a, F64)[0]) == "tie"


def sqrt_case(fmt: Format, q: Fraction, r: int) -> str:
    """How a finite r is √q rounded in fmt, for q > 0: a tie where √q is
    the midpoint of r and the value on the other side of it."""
    v = fmt.value(r)
    if v * v == q:
        return "exact"
    low = v * v < q
    other = r + 1 if low else r - 1
    mid = (v + (pow2(fmt.emax + 1) if fmt.is_inf(other) else fmt.value(other))) / 2
    if mid * mid == q:
        return "tie"
    return "down" if low else "up"


def decode(word: int) -> Tuple[Optional[str], int, int, Optional[str]]:
    """A command word: its name, n, S, and why it is not valid, if not."""
    num, n, s = word & 0xFF, word >> 8 & 0xFF, word >> 16 & 1
    c = COMMANDS.get(num)
    if c is None:
        return None, n, s, "number"
    if word >> 17:
        return c.name, n, s, "bits 31..17"
    if s and not c.s:
        return c.name, n, s, "S"
    if n & ~c.nmask:
        return c.name, n, s, "n"
    return c.name, n, s, None


class Coverage:
    def __init__(self) -> None:
        self.bins: Dict[Tuple[str, ...], int] = {}
        self.errors: List[str] = []

    def hit(self, *key: str) -> None:
        self.bins[key] = self.bins.get(key, 0) + 1

    def record(self, line: Line) -> None:
        (stack, flags), (kind, reg, word), (after, flags_after) = line
        new = flags_after & ~flags
        if kind == "R":
            self.hit("read", REG_NAMES[reg])
            if reg == STATUS:
                for bit in range(16, 22):
                    if word >> bit & 1:
                        self.hit("class bit", str(bit))
            if reg == X_S and stack and F64.is_finite(stack[-1]) and F32.is_finite(word):
                self.hit("rounding", "R X_S", rounding_case(F32, F64.value(stack[-1]), word))
            return
        if reg != CMD:
            self.hit("write", REG_NAMES[reg])
            if new & STACK:
                self.hit("flag", "W " + REG_NAMES[reg], "STACK")
            return
        name, n, s, bad = decode(word)
        if bad is not None:
            self.hit("not valid", bad)
            if new != (INVALID if flags & INVALID == 0 else 0):
                self.errors.append(f"a word that is not valid set {new:X}")
            return
        assert name is not None
        key = name + (".S" if s else "")
        self.hit("depth", key, str(min(len(stack), 3)) if len(stack) < 15 else str(len(stack)))
        for f, fname in ((INVALID, "I"), (DIVZERO, "Z"), (OVERFLOW, "O"), (STACK, "STACK")):
            if new & f:
                self.hit("flag", key, fname)
                if f != STACK and not FLAGS[key] & f:
                    self.errors.append(f"{key} set the flag {fname}: {line_text(line)}")
        c = COMMANDS[NUMBERS[name]]
        if c.pops == 0 or name == "SWAP":
            return
        ops = list(stack[-c.pops:]) if len(stack) >= c.pops else None
        if ops is None:
            return
        self.hit("operands", key, *[klass(a) for a in ops])
        result = after[-1] if after else CANONICAL_NAN
        self.hit("result", key, klass(result))
        if s and round32(c.run(ops, 0)[0][0])[0] != result:
            self.hit("once", key)
        case = self.rounding(name, s, ops, result)
        if case is not None:
            self.hit("rounding", key, case)

    def rounding(self, name: str, s: int, ops: List[int], r: int) -> Optional[str]:
        if not all(F64.is_finite(a) for a in ops) and name not in ("ITOF", "UTOF", "FROMBCD"):
            return None
        # With S the exact result is rounded once, to binary32, and r
        # holds that value.
        fmt = F32 if s else F64
        if s:
            r = F32.convert(r, F64)[0]
            if not F32.is_finite(r):
                return None
        if name in ("ADD", "SUB", "MUL", "DIV"):
            y, x = F64.value(ops[0]), F64.value(ops[1])
            if name == "DIV" and x == 0:
                return None
            q = {"ADD": y + x, "SUB": y - x, "MUL": y * x, "DIV": y / x if x else Fraction(0)}[name]
        elif name == "SQRT":
            q = F64.value(ops[0])
            return sqrt_case(fmt, q, r) if q > 0 else None
        elif name == "ROUND32":
            return rounding_case(F32, F64.value(ops[0]), F32.convert(r, F64)[0])
        elif name == "ITOF":
            q = Fraction(s64(ops[0]))
        elif name == "UTOF":
            q = Fraction(ops[0])
        elif name == "FROMBCD":
            if any(ops[0] >> i & 0xF > 9 for i in range(0, 64, 4)):
                return None
            q = Fraction(int(f"{ops[0]:016X}"))
        elif name == "SCALE2":
            k = F64.value(ops[1])
            if k.denominator != 1:
                return None
            q = F64.value(ops[0]) * pow2(max(-2100, min(2100, int(k))))
        else:
            return None
        if q == 0:
            return None
        return rounding_case(fmt, q, r)

    def required(self) -> List[Tuple[str, ...]]:
        """The bins that can occur, and so must not be empty."""
        req: List[Tuple[str, ...]] = []
        req += [("read", r) for r in REG_NAMES] + [("write", r) for r in REG_NAMES if r != "CMD"]
        req += [("class bit", str(b)) for b in range(16, 22)]
        req += [("flag", "W " + r, "STACK") for r in ("X_LO", "X_HI", "X_S", "X_W")]
        req += [("not valid", why) for why in ("number", "bits 31..17", "S", "n")]
        for key, allowed in FLAGS.items():
            for f, fname in ((INVALID, "I"), (DIVZERO, "Z"), (OVERFLOW, "O")):
                if allowed & f:
                    req.append(("flag", key, fname))
            if key not in ("NOP", "CLEAR"):
                req.append(("flag", key, "STACK"))
            for depth in ("0", "1", "2", "15", "16"):
                req.append(("depth", key, depth))
            name = key.split(".")[0]
            c = COMMANDS[NUMBERS[name]]
            if c.pops and name != "SWAP":
                ops: List[List[str]] = [[]]
                for _ in range(c.pops):
                    ops = [o + [k] for o in ops for k in CLASSES]
                req += [("operands", key) + tuple(o) for o in ops]
        for key, cases in ROUNDING.items():
            req += [("rounding", key, case) for case in sorted(cases)]
        req += [("once", key) for key in FLAGS if key.endswith(".S")]
        for key, classes in RESULT_CLASSES.items():
            req += [("result", key, k) for k in classes]
        return req

    def check(self) -> List[str]:
        missing = [" ".join(b) for b in self.required() if b not in self.bins]
        for key, cases in ROUNDING.items():
            for (kind, *rest) in self.bins:
                if kind == "rounding" and rest[0] == key and rest[1] not in cases:
                    self.errors.append(f"{key} rounds as {rest[1]}, which ROUNDING says cannot occur")
        return missing


def state_text(s: State) -> str:
    stack, flags = s
    return f"{flags:X} {len(stack):02X}" + "".join(f" {v:016X}" for v in stack)


def line_text(line: Line) -> str:
    before, (kind, reg, word), after = line
    return f"{state_text(before)} : {kind} {reg:X} {word:08X} : {state_text(after)}"


def parse_state(text: str) -> State:
    f = text.split()
    depth = int(f[1], 16)
    if len(f) != 2 + depth or depth > DEPTH:
        raise ValueError("a state of the wrong length: " + text)
    return tuple(int(v, 16) for v in f[2:]), int(f[0], 16)


def parse_line(text: str) -> Line:
    before, access, after = text.split(":")
    kind, reg, word = access.split()
    return parse_state(before), (kind, int(reg, 16), int(word, 16)), parse_state(after)


def replay(line: Line) -> bool:
    """Whether the model gives the line's state after and value read."""
    (stack, flags), (kind, reg, word), after = line
    fpu = FPU(list(stack), flags)
    if kind == "R":
        if fpu.read(reg) != word:
            return False
    else:
        fpu.write(reg, word)
    return fpu.state() == after


class Generator:
    """Runs accesses on the model, and keeps them as lines."""

    def __init__(self) -> None:
        self.lines: List[str] = []
        self.coverage = Coverage()

    def access(self, fpu: FPU, kind: str, reg: int, word: int = 0) -> None:
        before = fpu.state()
        if kind == "R":
            word = fpu.read(reg)
        else:
            fpu.write(reg, word)
        line = (before, (kind, reg, word & 0xFFFFFFFF), fpu.state())
        self.coverage.record(line)
        self.lines.append(line_text(line))

    def comment(self, text: str) -> None:
        self.lines.append("# " + text)

    def on(self, stack: List[int], kind: str, reg: int, word: int = 0, flags: int = 0) -> None:
        self.access(FPU(stack, flags), kind, reg, word)

    def cmd(self, stack: List[int], text: str, flags: int = 0) -> None:
        self.on(stack, "W", CMD, word_of(text), flags)


def word_of(text: str) -> int:
    """A command word by name, as "ADD", "ADD.S", or "PICK 15"."""
    parts = text.split()
    name, s = (parts[0][:-2], 1) if parts[0].endswith(".S") else (parts[0], 0)
    n = int(parts[1], 0) if len(parts) > 1 else 0
    return NUMBERS[name] | n << 8 | s << 16


def d(x: Fraction) -> int:
    return F64.round(x)[0]


def f64_of_32(w: int) -> int:
    return F64.convert(w, F32)[0]


def command_texts() -> List[str]:
    """Every command, with an n that does something, and the S forms."""
    out = []
    for c in COMMANDS.values():
        n = {"PICK": " 1", "DROP": " 1", "CONST": " 3", "DIGITS": " 5", "CMP": " 5", "CLEAR": " 1"}.get(c.name, "")
        out.append(c.name + n)
        if c.s:
            out.append(c.name + ".S")
    return out


def directed(g: Generator, rnd: random.Random) -> None:
    one = 0x3FF0000000000000
    g.comment("The registers: a read of each, of each special value")
    for v in SPECIALS:
        for reg in range(8):
            g.on([one, v], "R", reg)
    for reg in range(8):
        g.on([], "R", reg)
    g.on(list(range(1, 17)), "R", STATUS)
    for flags in range(16):
        g.on([one], "R", STATUS, flags=flags)
    g.comment("The registers: writes, at the depths 0, 1, 15, and 16")
    words = [0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x3F800000, 0x7F800001, 0x7FC00000, 0xFF800000,
             0x00400000, 0x80000001, 0x7F7FFFFF]
    for depth in (0, 1, 15, 16):
        for reg in range(8):
            if reg == CMD:
                continue
            for w in words:
                g.on([SPECIALS[i % len(SPECIALS)] for i in range(depth)], "W", reg, w)
    for w in (0, 0x100, 0x200, 0x400, 0x800, 0xF00, 0xFFFFF0FF, 0xFFFFFFFF):
        g.on([one], "W", STATUS, w, flags=0xA)

    g.comment("Every command number, with n = 0, S, each bit of n, and bits 31..17")
    three = [0x4000000000000000, 0x4008000000000000, 0x3FF8000000000000]
    for num in range(256):
        g.on(three, "W", CMD, num)
        g.on(three, "W", CMD, num | 1 << 16)
        for b in range(8):
            g.on(three, "W", CMD, num | 1 << (8 + b))
    for b in range(17, 32):
        g.on(three, "W", CMD, NUMBERS["ADD"] | 1 << b)

    g.comment("Every command at the depths 0, 1, 2, 15, and 16")
    for text in command_texts() + ["PICK 15", "DROP 3", "DIGITS 15", "SWAP"]:
        for depth in (0, 1, 2, 15, 16):
            g.cmd([SPECIALS[(3 * i + 8) % len(SPECIALS)] for i in range(depth)], text)

    g.comment("The special values, each with each")
    for c in COMMANDS.values():
        if c.pops == 0 or c.name == "SWAP":
            continue
        texts = [c.name + (" 7" if c.name == "CMP" else " 15" if c.name == "DIGITS" else "")]
        if c.s:
            texts.append(c.name + ".S")
        if c.name == "CMP":
            texts += ["CMP 1", "CMP 2", "CMP 4"]
        for text in texts:
            if c.pops == 1:
                for v in SPECIALS:
                    g.cmd([v], text)
            else:
                for y in SPECIALS:
                    for x in SPECIALS:
                        g.cmd([y, x], text)

    rounding(g, rnd)
    conversions(g, rnd)
    decimal_cmds(g, rnd)


def random_finite(rnd: random.Random, lo: int = 1, hi: int = 2046) -> int:
    return rnd.getrandbits(52) | rnd.randint(lo, hi) << 52 | rnd.getrandbits(1) << 63


def rounding(g: Generator, rnd: random.Random) -> None:
    g.comment("Rounding: ties, carries, subnormals, and the threshold of the overflow")
    half_ulp_of_1 = 0x3CA0000000000000  # 2^-53
    for _ in range(40):
        a = random_finite(rnd, 1000, 1100) & ~NZ
        e = (a >> 52) - 1023 - 53
        g.cmd([a, d(pow2(e))], "ADD")  # half an ulp: a tie
        g.cmd([a, d(3 * pow2(e - 1))], "ADD")  # three quarters: up
        g.cmd([a, d(pow2(e - 1))], "SUB")  # a quarter, below: down or a tie
        g.cmd([a | NZ, d(pow2(e))], "SUB")
        # Two odd 27-bit numbers whose product has 54 bits: a tie.
        while True:
            m1, m2 = rnd.getrandbits(27) | 1 << 26 | 1, rnd.getrandbits(27) | 1 << 26 | 1
            if (m1 * m2).bit_length() == 54:
                break
        k = rnd.randint(-600, 500)
        g.cmd([d(Fraction(m1) * pow2(k)), d(Fraction(m2))], "MUL")
        g.cmd([random_finite(rnd), random_finite(rnd)], "MUL")
        g.cmd([random_finite(rnd), random_finite(rnd)], "DIV")
        g.cmd([random_finite(rnd) & ~NZ], "SQRT")
        g.cmd([random_finite(rnd, 1000, 1046), random_finite(rnd, 1000, 1046)], "ADD")
    g.cmd([3, 0x4000000000000000], "DIV")  # a tie in the subnormals
    g.cmd([0x3FF0000000000001, half_ulp_of_1], "ADD")  # a tie that carries to even
    g.cmd([0x3FFFFFFFFFFFFFFF, half_ulp_of_1], "ADD")  # a carry into the exponent
    for v in (0x7C90000000000000, 0x7C8FFFFFFFFFFFFF, 0x7C80000000000000):
        g.cmd([0x7FEFFFFFFFFFFFFF, v], "ADD")  # MAX plus about half its ulp
    for _ in range(20):
        # Products and quotients in the subnormals, and on the edges of
        # the overflow.
        g.cmd([random_finite(rnd, 1, 60), random_finite(rnd, 900, 1000)], "MUL")
        g.cmd([random_finite(rnd, 1, 60), random_finite(rnd, 1030, 1100)], "DIV")
        g.cmd([random_finite(rnd, 1990, 2046), random_finite(rnd, 1023, 1060)], "MUL")
        g.cmd([random_finite(rnd, 1, 2), random_finite(rnd, 1, 2)], "SUB")
        g.cmd([random_finite(rnd, 2040, 2046), random_finite(rnd, 2040, 2046)], "ADD")
        g.cmd([random_finite(rnd, 1, 4) & ~NZ], "SQRT")
        g.cmd([random_finite(rnd, 1, 100), random_finite(rnd, 1, 100)], "MUL")
        g.cmd([random_finite(rnd, 1, 100), random_finite(rnd, 1100, 2000)], "DIV")

    g.comment("Rounding to binary32: the S forms, ROUND32, and X_S")
    for _ in range(40):
        w = rnd.getrandbits(31)
        if F32.is_finite(w) and w != F32.max_finite:
            v = f64_of_32(w)
            mid = v + (1 << 28)  # half a binary32 ulp above, for a normal w
            for text in ("ADD.S", "SUB.S"):
                g.cmd([mid, 0], text)
            g.cmd([mid, 0x3FF0000000000000], "MUL.S")
            g.cmd([mid, 0x3FF0000000000000], "DIV.S")
            g.cmd([mid], "ROUND32")
            g.on([mid], "R", X_S)
            g.on([v + (3 << 27)], "R", X_S)
            g.on([v + (1 << 27)], "R", X_S)
            # The square of a 25-bit tie, 50 bits, is exact in binary64.
            t = Fraction(rnd.getrandbits(24) | 1 << 24 | 1, 1 << 24)
            g.cmd([d(t * t)], "SQRT.S")
        g.cmd([random_finite(rnd, 900, 1150), random_finite(rnd, 900, 1150)], "MUL.S")
        g.cmd([random_finite(rnd, 900, 1150), random_finite(rnd, 900, 1150)], "DIV.S")
        g.cmd([random_finite(rnd, 900, 1150), random_finite(rnd, 900, 1150)], "ADD.S")
        g.cmd([random_finite(rnd, 0, 1300) & ~NZ], "SQRT.S")
        g.cmd([random_finite(rnd, 850, 900)], "ROUND32")  # binary32 subnormals
        g.on([random_finite(rnd, 850, 900)], "R", X_S)
    for v in (0x47EFFFFFE0000000, 0x47EFFFFFF0000000, 0x47EFFFFFEFFFFFFF, 0x3690000000000000, 0x36A8000000000000):
        g.cmd([v], "ROUND32")
        g.on([v], "R", X_S)
    g.cmd([0x47EFFFFFE0000000, 0x4000000000000000], "MUL.S")
    g.cmd([0x7E37E43C8800759C], "SQRT.S")
    g.cmd([0x47EFFFFFE0000000, 0x3FE0000000000000], "DIV.S")

    g.comment("The S forms round once: the binary64 result is a tie in binary32, and the exact result is not")
    # The hand-checked cases of fpu_model_test.py.
    g.cmd([0x3FF0000010000000, 0x3C90000000000000], "ADD.S")
    g.cmd([0x3FF0000030000000, 0x3C90000000000000], "SUB.S")
    g.cmd([0x4008000000000000, 0x433555556AAAAAAB], "MUL.S")
    g.cmd([0x44B0000030000001, 0x4330000000000001], "DIV.S")
    g.cmd([0x3FF0000020000011], "SQRT.S")
    for _ in range(40):
        # sig is 25 bits and odd: as a binary32 significand, the tie above
        # that of w. tie is that value in binary64.
        w = rnd.getrandbits(23) | rnd.randint(1, 254) << 23
        sig = 2 * (w & 0x7FFFFF | 0x800000) + 1
        tie = f64_of_32(w) + (1 << 28)
        # Less than half a binary64 ulp of the tie, added and subtracted.
        # One of the two sides is not the side of the even neighbor.
        tiny = ((tie >> 52) - rnd.randint(54, 200)) << 52
        for sign in (0, NZ):
            for text in ("ADD.S", "SUB.S"):
                assert tie32(COMMANDS[NUMBERS[text[:3]]].run([tie | sign, tiny], 0)[0][0])
                g.cmd([tie | sign, tiny], text)
        # a · b = sig · 2^80 + delta: the product has 105 bits, so a binary64
        # ulp of it is 2^52, and a delta below half of that is lost.
        while True:
            a = rnd.getrandbits(53) | 1 << 52
            b = (sig << 80) // a + rnd.randrange(2)
            delta = a * b - (sig << 80)
            if b < 1 << 53 and 0 < abs(delta) < 1 << 51:
                break
        ops = [d(Fraction(a) * pow2(rnd.randint(-180, -30))), d(Fraction(b))]
        assert tie32(F64.mul(*ops)[0])
        g.cmd(ops, "MUL.S")
        # y is sig · x rounded to binary64, which sig · x, odd and of 77
        # bits or more, is not. So y / x is not sig, and about half the time
        # it is near enough for the binary64 quotient to be sig.
        while True:
            x = rnd.getrandbits(53) | 1 << 52 | 1
            y = d(Fraction(sig * x))
            if F64.div(y, d(Fraction(x)))[0] == d(Fraction(sig)):
                break
        ops = [d(F64.value(y) * pow2(rnd.randint(-100, 60))), d(Fraction(x))]
        assert tie32(F64.div(*ops)[0])
        g.cmd(ops, "DIV.S")
        # For an odd root of 25 bits below √2 · 2^24, its square is 49
        # bits, so a double, and the doubles next to that have a square
        # root within half a binary64 ulp of root, on either side.
        root = rnd.randrange(1 << 24, 23726566) | 1
        k = rnd.randint(-40, 40)
        sq = d(Fraction(root * root) * pow2(2 * k)) + rnd.choice([-1, 1])
        assert F64.sqrt(sq)[0] == d(Fraction(root) * pow2(k))
        g.cmd([sq], "SQRT.S")


def conversions(g: Generator, rnd: random.Random) -> None:
    g.comment("The conversions, the word operators, and the constants")
    ints = [0, 1, (1 << 53) + 1, (1 << 53) + 3, (1 << 63) - 1, 1 << 63, (1 << 64) - 1, (1 << 54) + 2]
    ints += [rnd.getrandbits(rnd.choice([16, 32, 53, 54, 60, 64])) for _ in range(60)]
    for i in ints:
        g.cmd([i], "ITOF")
        g.cmd([i], "UTOF")
    for _ in range(40):
        v = d(Fraction(rnd.randint(-(10**20), 10**20), rnd.choice([1, 2, 4, 3, 1000])))
        for text in ("FTOI", "FTOU", "FLOOR", "CEIL", "TRUNC", "NEAREST", "ROUND", "ISQRT", "SIGN", "GETEXP", "GETMANT"):
            g.cmd([v], text)
        g.on([v], "R", X_W)
        g.on([v], "R", STATUS)
    for v in (0x43E0000000000000, 0xC3E0000000000000, 0x43F0000000000000, 0x43EFFFFFFFFFFFFF, 0xC3E0000000000001):
        g.cmd([v], "FTOI")
        g.cmd([v], "FTOU")
    for _ in range(21):
        # ISQRT near squares, where SQRT rounds up to the next whole number.
        m = (1 << 26) + rnd.getrandbits(26)
        g.cmd([d(Fraction(m * m - 1))], "ISQRT")
        g.cmd([d(Fraction(m * m))], "ISQRT")
    g.cmd([0x4690000000000002], "ISQRT")
    counts = [0, 1, 31, 32, 33, -1, 5]
    words = [0, 1, -1, 7, -7, 2, -2, (1 << 31) - 1, -(1 << 31)]
    for name in ("AND", "OR", "XOR", "SHL", "SHR", "IDIV", "MOD"):
        for y in words:
            for x in (counts if name in ("SHL", "SHR") else words):
                g.cmd([d(Fraction(y)), d(Fraction(x))], name)
    for y in words:
        g.cmd([d(Fraction(y))], "NOT")
    for n in range(256):
        g.cmd([], f"CONST {n}")
    for _ in range(40):
        a, b = random_finite(rnd, 900, 1150), random_finite(rnd, 900, 1150)
        g.cmd([a, b], "FMOD")
        g.cmd([a, b], "MIN")
        g.cmd([a, b], "MAX")
        g.cmd([a, b], f"CMP {rnd.randint(0, 7)}")
        g.on([a, b], "R", REL)

    g.comment("SCALE2 into the subnormals, and SCALE10 by each bit of k")
    for k in range(-1080, -1018):
        g.cmd([random_finite(rnd, 1020, 1026), d(Fraction(k))], "SCALE2")
    g.cmd([0x4008000000000000, d(Fraction(-1075))], "SCALE2")
    for k in (1023, 1024, 2098, -2098, 2100, 2101, -2101):
        g.cmd([0x7FEFFFFFFFFFFFFF, d(Fraction(k))], "SCALE2")
        g.cmd([1, d(Fraction(k))], "SCALE2")
    ks = [1 << b for b in range(10)] + [22, 23, 650, 651, 307, 308, 309, 323, 324, 325]
    for k in ks + [-k for k in ks]:
        for y in (0x3FF0000000000000, 0xC00921FB54442D18, random_finite(rnd, 900, 1150), 1, 0x7FEFFFFFFFFFFFFF):
            g.cmd([y, d(Fraction(k))], "SCALE10")


def bcd(digits: str) -> int:
    return int(digits.ljust(16, "0"), 16)


def decimal_cmds(g: Generator, rnd: random.Random) -> None:
    g.comment("DIGITS, FROMBCD, GETEXP, GETMANT, and FMOD")
    values = [0x3FF0000000000000, 0x3FB999999999999A, 0x400921FB54442D18, 0x7FEFFFFFFFFFFFFF, 1, 0x4023333333333333]
    values += [random_finite(rnd, 1, 2046) for _ in range(10)]
    for v in values:
        for n in list(range(17)) + [255]:
            g.cmd([v], f"DIGITS {n}")
    for _ in range(30):
        digits = str(rnd.randint(10**14, 10**15 - 1))
        g.cmd([bcd(digits)], "FROMBCD")
    for w in (0x9999999999999999, 0x9007199254740993, 0x9007199254740992, 0x123, 0):
        g.cmd([w], "FROMBCD")
    for i in range(16):
        g.cmd([0xA << (4 * i)], "FROMBCD")
        g.cmd([0xF << (4 * i) | 0x1234], "FROMBCD")
    for e in range(-1074, -1020, 3):
        v = d(pow2(e) * 3)
        g.cmd([v], "GETEXP")
        g.cmd([v], "GETMANT")
    for _ in range(30):
        y = random_finite(rnd)
        ey = y >> 52 & 0x7FF
        x = random_finite(rnd, max(1, ey - 60), max(1, ey))  # some 60 steps of FMOD
        g.cmd([y, x], "FMOD")


def random_value(rnd: random.Random) -> int:
    kind = rnd.randrange(8)
    if kind == 0:
        return rnd.choice(SPECIALS)
    if kind == 1:
        return rnd.getrandbits(64)
    if kind == 2:
        return random_finite(rnd, 1013, 1033)
    if kind == 3:
        return d(Fraction(rnd.randint(-1000, 1000)))
    if kind == 4:
        return f64_of_32(rnd.getrandbits(32))
    if kind == 5:
        return bcd(str(rnd.randint(1, 10**15 - 1)))
    if kind == 6:
        return rnd.getrandbits(rnd.choice([8, 32, 64]))
    return random_finite(rnd)


def random_word(rnd: random.Random) -> int:
    """A random command word, nearly always a valid one."""
    if rnd.randrange(20) == 0:
        return rnd.choice([rnd.getrandbits(8), rnd.getrandbits(17), rnd.getrandbits(32)])
    c = rnd.choice(list(COMMANDS.values()))
    if c.name == "CLEAR" and rnd.randrange(4):
        c = COMMANDS[NUMBERS["ADD"]]
    n = 0
    if c.nmask == 0xFF:
        n = rnd.choice([rnd.randint(0, 17), rnd.randint(0, 255)])
    elif c.nmask:
        n = rnd.randint(0, c.nmask)
    s = 1 if c.s and rnd.randrange(2) else 0
    return NUMBERS[c.name] | n << 8 | s << 16


def random_run(g: Generator, seed: int, count: int) -> None:
    g.comment(f"A random sequence, seed {seed}, {count} accesses")
    rnd = random.Random(seed)
    fpu = FPU()
    start = len(g.lines)
    while len(g.lines) - start <= count:
        r = rnd.random()
        if r < 0.15:
            v = random_value(rnd)
            g.access(fpu, "W", X_LO, v & 0xFFFFFFFF)
            g.access(fpu, "W", X_HI, v >> 32)
        elif r < 0.22:
            g.access(fpu, "W", X_S, rnd.choice([rnd.getrandbits(32), F32.convert(random_value(rnd), F64)[0]]))
        elif r < 0.27:
            g.access(fpu, "W", X_W, rnd.getrandbits(32))
        elif r < 0.29:
            g.access(fpu, "W", X_LO, rnd.getrandbits(32))
        elif r < 0.41:
            g.access(fpu, "R", rnd.randrange(8))
        elif r < 0.49:
            # The flags are sticky: clear them often, so that a command
            # can be seen to set one.
            g.access(fpu, "W", STATUS, rnd.choice([0, 0, 0, rnd.getrandbits(32)]))
        elif r < 0.50:
            g.access(fpu, "W", rnd.choice([REL, 7]), rnd.getrandbits(32))
        else:
            g.access(fpu, "W", CMD, random_word(rnd))


def main() -> None:
    p = argparse.ArgumentParser(description="Write and check the FPU's test vectors.")
    p.add_argument("-o", "--output", help="the file to write the vectors to")
    p.add_argument("--seed", type=int, default=161, help="the seed of the random sequence (161)")
    p.add_argument("--count", type=int, default=20000, help="the accesses of the random sequence (20000)")
    a = p.parse_args()
    g = Generator()
    directed(g, random.Random(a.seed))
    directed_count = len(g.lines)
    random_run(g, a.seed, a.count)
    failed = False
    for text in g.lines:
        if not text.startswith("#") and not replay(parse_line(text)):
            print("FAIL the line does not replay: " + text)
            failed = True
            break
    missing = g.coverage.check()
    for b in missing:
        print("FAIL an empty bin: " + b)
    for e in g.coverage.errors[:20]:
        print("FAIL " + e)
    if a.output:
        with open(a.output, "w") as f:
            f.write("# The FPU's test vectors, from emulator/test/fpu_vectors.py.\n")
            f.write("".join(t + "\n" for t in g.lines))
    req = len(g.coverage.required())
    print(f"{directed_count} directed lines, {len(g.lines) - directed_count} random ones, "
          f"{len(g.coverage.bins)} bins hit, {req - len(missing)} of the {req} required")
    if failed or missing or g.coverage.errors:
        sys.exit(1)
    print("PASS fpu_vectors")


if __name__ == "__main__":
    main()
