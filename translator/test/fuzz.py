#!/usr/bin/env python3
"""A random test of nicewasm against a model of wasm written in Python.

Usage: fuzz.py [--no-mpu] [--unchecked] [--grow] [--keep DIR] [--reduce] FIRST COUNT

Each case is a module built from a random syntax tree. Every node of the
tree emits its wasm bytes and evaluates itself in Python with the
semantics of the WebAssembly specification, so the model and the module
always describe the same program. The module is translated, joined with
the runtime as run.py does, assembled, and run, and main's result in R1
must equal the model's, or if the model traps, the program must halt at
___wasm_trap with the model's trap code in R1. Seeds FIRST to FIRST +
COUNT - 1 are tried; the same seed always gives the same module.

A module has four functions: main, f(i32, i64, i32, i32) -> i32, whose
last argument goes on the stack, g(i64, i32) -> i64, and h(i32, i32) ->
i32. Each has 8 to 13 locals, i32 and i64, so that with the values on
the operand stack some live in registers and some are spilled to the
frame. The bodies use blocks,
loops, if and else, br, br_if, and br_table with and without values,
return, nop, both forms of select, calls and call_indirect, every
integer operation and comparison, global.get and global.set of mutable
i32 and i64 globals and global.get of an immutable one,
memory.fill and memory.copy, whose ranges may overlap,
comparisons kept in a local by local.tee for later conditions, a
br_if out of the function at its start, eqz
before if and br_if, i64 shifts by constants and by variables, groups
of word loads and stores at offsets from one address in a local,
multiplications by constants, divisions with nonzero divisors, some of
them constants, loads and stores of every width at
constant and at dynamic addresses, among them the addresses of array
elements, (i << s) + c, with an index i whose high bits the shift drops
and constants that may be negative, or with a masked index i = x & m,
some near the end of the memory, and local.set and local.tee of locals
whose old value is still on the operand stack. Blocks, ifs, and loops
also have block types that name a function type, with parameters and
several results, among them the type of h, which call_indirect may name
too; br, br_if, and br_table carry several values, a br_if not taken
leaves them to be dropped or set to locals, an if without else passes
its parameters on, a loop's br_if carries new parameters each time
around, and the first two arguments of a call may come from one block.
That covers the rules for
deferred values, fused comparisons, forwarded results, and register
allocation in README.md. main returns a fold of every local, of 18 memory
words, and of the globals, so a wrong value anywhere shows. Two locals of each function are
loop counters that nothing else touches, so every loop ends.

In 40% of the modules, statements and divisions may trap: an unreachable
under a condition, divisions by a value that may be 0, div_s of a value
that may be the most negative by -1 or -2, call_indirect with an index
that a condition chooses, the right one, one past the table, or that of
a function of another type, and loads, stores, memory.fill, and
memory.copy near the end of the memory that may pass it. About a fifth
of the modules trap, with each code of WASM.md but 5, which needs floats.

With --no-mpu, nicewasm is run with that option and the program is joined
with muldiv_soft.nasm instead of muldiv_mpu.nasm. With --unchecked,
nicewasm is run with --no-bounds-checks, and with --grow with
--memory-pages 2, so that the bounds checks compare with the words that
memory.grow keeps. With --unchecked, no access is out of bounds; the other
traps stay. With --keep DIR, each program is copied to DIR/fuzzSEED.bin, with
_nompu, _unchecked, or _grow added for the mode, for hdl/test/programs.py.
With --reduce, FIRST is
a failing seed: statements are removed from the functions while the
mismatch persists, and the reduced module and its translation, if
nicewasm accepts it, are written to fuzz_FIRST.wasm and fuzz_FIRST.nasm in
the current directory.

This test does not replace run.py, whose cases are checked by hand, and
which also checks a trap's R2. It is cheap to run on many seeds, and it
found three bugs while it was written, all three in the model. make test
runs 40 seeds with the math unit and 40 with --no-mpu, and 20 with
--unchecked and 20 with --grow. Each run prints how many of its modules
trap."""

from __future__ import annotations

import concurrent.futures
import os
import random
import shutil
import subprocess
import sys
import tempfile
from typing import Callable, Dict, List, Optional, Tuple

from wasm import (ADD, AND, DROP, ELSE, END, EXTEND_S, EXTEND_U, I32, I64, LT_U, MEMORY_COPY,
                  MEMORY_FILL, NOP, OR, RETURN, SELECT, SHR_U64, UNREACHABLE, WRAP, block, br, br_if,
                  br_table, call, call_indirect, code, data, elems, exports, funcs, global_get,
                  global_set, i32_const, i64_const, if_, local_get, local_set, local_tee, loop, mem,
                  memory, module, select_t, table, typed_globals, typeidx, types)

sys.setrecursionlimit(5000)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
RUNTIME = os.path.join(REPO, "runtime")
NICEWASM = os.path.join(HERE, "..", "nicewasm.py")
NICEASM = os.path.join(REPO, "assembler", "niceasm.py")
NICEEMU = os.path.join(REPO, "emulator", "zig-out", "bin", "niceemu")

M32, M64 = 0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF
I32_LOAD = 0x28


def s32(x: int) -> int:
    x &= M32
    return x - (1 << 32) if x >> 31 else x


def s64(x: int) -> int:
    x &= M64
    return x - (1 << 64) if x >> 63 else x


def sgn(t: int, x: int) -> int:
    return s32(x) if t == I32 else s64(x)


def mask(t: int) -> int:
    return M32 if t == I32 else M64


def bits(t: int) -> int:
    return 32 if t == I32 else 64


def tdiv(a: int, b: int) -> int:
    """Division rounded toward zero."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def clz(x: int, n: int) -> int:
    return n - x.bit_length()


def ctz(x: int, n: int) -> int:
    return n if x == 0 else (x & -x).bit_length() - 1


def rot(t: int, a: int, n: int, left: bool) -> int:
    n %= bits(t)
    if not left:
        n = (bits(t) - n) % bits(t)
    return ((a << n) | (a >> (bits(t) - n))) & mask(t)


# Binary operations: name -> (i32 opcode, i64 opcode, result of a and b).
BIN: Dict[str, Tuple[int, int, Callable[[int, int, int], int]]] = {
    "add": (0x6A, 0x7C, lambda t, a, b: (a + b) & mask(t)),
    "sub": (0x6B, 0x7D, lambda t, a, b: (a - b) & mask(t)),
    "mul": (0x6C, 0x7E, lambda t, a, b: (a * b) & mask(t)),
    "div_s": (0x6D, 0x7F, lambda t, a, b: tdiv(sgn(t, a), sgn(t, b)) & mask(t)),
    "div_u": (0x6E, 0x80, lambda t, a, b: a // b),
    "rem_s": (0x6F, 0x81, lambda t, a, b: (sgn(t, a) - tdiv(sgn(t, a), sgn(t, b)) * sgn(t, b)) & mask(t)),
    "rem_u": (0x70, 0x82, lambda t, a, b: a % b),
    "and": (0x71, 0x83, lambda t, a, b: a & b),
    "or": (0x72, 0x84, lambda t, a, b: a | b),
    "xor": (0x73, 0x85, lambda t, a, b: a ^ b),
    "shl": (0x74, 0x86, lambda t, a, b: (a << (b % bits(t))) & mask(t)),
    "shr_s": (0x75, 0x87, lambda t, a, b: (sgn(t, a) >> (b % bits(t))) & mask(t)),
    "shr_u": (0x76, 0x88, lambda t, a, b: a >> (b % bits(t))),
    "rotl": (0x77, 0x89, lambda t, a, b: rot(t, a, b, True)),
    "rotr": (0x78, 0x8A, lambda t, a, b: rot(t, a, b, False)),
}
DIVISIONS = ("div_s", "div_u", "rem_s", "rem_u")
SHIFTS = ("shl", "shr_s", "shr_u", "rotl", "rotr")

# Comparisons: name -> (i32 opcode, i64 opcode, result of a and b).
CMP: Dict[str, Tuple[int, int, Callable[[int, int, int], int]]] = {
    "eq": (0x46, 0x51, lambda t, a, b: int(a == b)),
    "ne": (0x47, 0x52, lambda t, a, b: int(a != b)),
    "lt_s": (0x48, 0x53, lambda t, a, b: int(sgn(t, a) < sgn(t, b))),
    "lt_u": (0x49, 0x54, lambda t, a, b: int(a < b)),
    "gt_s": (0x4A, 0x55, lambda t, a, b: int(sgn(t, a) > sgn(t, b))),
    "gt_u": (0x4B, 0x56, lambda t, a, b: int(a > b)),
    "le_s": (0x4C, 0x57, lambda t, a, b: int(sgn(t, a) <= sgn(t, b))),
    "le_u": (0x4D, 0x58, lambda t, a, b: int(a <= b)),
    "ge_s": (0x4E, 0x59, lambda t, a, b: int(sgn(t, a) >= sgn(t, b))),
    "ge_u": (0x4F, 0x5A, lambda t, a, b: int(a >= b)),
}

# Unary operations: name -> (i32 opcode, i64 opcode, result of a).
UNARY: Dict[str, Tuple[int, int, Callable[[int, int], int]]] = {
    "clz": (0x67, 0x79, lambda t, a: clz(a, bits(t))),
    "ctz": (0x68, 0x7A, lambda t, a: ctz(a, bits(t))),
    "popcnt": (0x69, 0x7B, lambda t, a: bin(a).count("1")),
    "extend8_s": (0xC0, 0xC2, lambda t, a: ((a & 0xFF) - ((a & 0x80) << 1)) & mask(t)),
    "extend16_s": (0xC1, 0xC3, lambda t, a: ((a & 0xFFFF) - ((a & 0x8000) << 1)) & mask(t)),
}

# Loads: opcode -> (type, bytes, signed). Stores: opcode -> (type, bytes).
LOADS: Dict[int, Tuple[int, int, bool]] = {
    0x28: (I32, 4, False), 0x29: (I64, 8, False), 0x2C: (I32, 1, True), 0x2D: (I32, 1, False),
    0x2E: (I32, 2, True), 0x2F: (I32, 2, False), 0x30: (I64, 1, True), 0x31: (I64, 1, False),
    0x32: (I64, 2, True), 0x33: (I64, 2, False), 0x34: (I64, 4, True), 0x35: (I64, 4, False)}
STORES: Dict[int, Tuple[int, int]] = {
    0x36: (I32, 4), 0x37: (I64, 8), 0x3A: (I32, 1), 0x3B: (I32, 2), 0x3C: (I64, 1),
    0x3D: (I64, 2), 0x3E: (I64, 4)}

# Addresses: the memory is one page, and the data segment is at DATA.
ADDR_MASK, DATA, DATA_SIZE, PAGE = 0x7FF8, 0x100, 256, 0x10000

# The globals: (type, mutable, initial value). The last one is immutable.
GLOBALS: List[Tuple[int, bool, int]] = [(I32, True, 0x12345678), (I32, True, 0xFFFFFFFB),
                                        (I64, True, 0x1_00000002), (I32, False, 0x7FFF0001)]


# The types of the module: those of the four functions, then those that
# only blocks use, with several results, or with parameters. The last
# has the parameters and results of h, so it gets the number of h's type
# (WASM.md), and a call_indirect of h may name either.
FUNC_TYPES: List[Tuple[List[int], List[int]]] = [
    ([], [I32]), ([I32, I64, I32, I32], [I32]), ([I64, I32], [I64]), ([I32, I32], [I32])]
TYPES: List[Tuple[List[int], List[int]]] = FUNC_TYPES + [
    ([], [I32, I64]), ([], [I64, I32]), ([], [I32, I32]), ([I32], [I32, I32]), ([I32, I64], [I64]),
    ([I64, I32], [I32, I64, I32]), ([I32], []), ([I32, I64], [I32, I64]), ([I64], [I64]),
    ([], [I64, I64, I32, I32, I64]), ([I32, I32], [I32])]

# The operations that fold several values into one: none of them traps.
FOLD_OPS = ("add", "sub", "xor", "mul", "rotl")


class Branch(Exception):
    """A br, br_if, or br_table taken in the model: the label's depth from
    the raising point, and the values it carries."""

    def __init__(self, depth: int, values: List[int]) -> None:
        super().__init__(depth, values)
        self.depth = depth
        self.values = values


class Trap(Exception):
    """A trap in the model, with its code of WASM.md."""

    def __init__(self, code: int) -> None:
        super().__init__(code)
        self.code = code


class State:
    """The model's state while a function runs."""

    def __init__(self, fns: List[Func], memory: bytearray) -> None:
        self.fns = fns
        self.mem = memory
        self.locals: List[int] = []
        self.globals = [v for _, _, v in GLOBALS]

    def call(self, idx: int, args: List[int]) -> int:
        fn = self.fns[idx]
        saved = self.locals
        self.locals = list(args) + [0] * (len(fn.local_types) - len(args))
        try:
            v = fn.body().ev(self)
        except Branch as b:
            assert b.depth == 0 and len(b.values) == 1
            v = b.values[0]
        self.locals = saved
        return v


class Expr:
    """A value of type t: its wasm code, and its value in the model."""

    def __init__(self, t: int, code: bytes, ev: Callable[[State], int]) -> None:
        self.t, self.code, self.ev = t, code, ev


class Stmt:
    """Code that leaves nothing on the operand stack."""

    def __init__(self, code: bytes, run: Callable[[State], None]) -> None:
        self.code, self.run = code, run


class Multi:
    """Several values, of the types ts, or none: their wasm code, and their
    values in the model."""

    def __init__(self, ts: List[int], code: bytes, ev: Callable[[State], List[int]]) -> None:
        self.ts, self.code, self.ev = ts, code, ev


class Func:
    def __init__(self, type_idx: int, params: List[int], result: int, local_types: List[int]) -> None:
        self.type_idx, self.params, self.result, self.local_types = type_idx, params, result, local_types
        self.stmts: List[Stmt] = []
        self.value: Optional[Expr] = None  # the result expression

    def body(self) -> Expr:
        """The statements and the result, as they are now."""
        assert self.value is not None
        stmts, value = self.stmts, self.value

        def ev(st: State) -> int:
            for s in stmts:
                s.run(st)
            return value.ev(st)
        return Expr(self.result, b"".join(s.code for s in stmts) + value.code, ev)


class Ctx:
    """What the generator knows while it builds one function: the labels in
    scope, from the function outward, with the types of the values that a
    branch to each carries, and the locals it may use. With risky, it makes
    statements that may trap, and with bounds, among them accesses out of
    bounds."""

    def __init__(self, rng: random.Random, fn: Func, fidx: int, fns: List[Func], risky: bool = False,
                 bounds: bool = True) -> None:
        self.rng, self.fn, self.fidx, self.fns = rng, fn, fidx, fns
        self.risky, self.bounds = risky, bounds
        self.labels: List[Tuple[str, List[int]]] = [("func", [fn.result])]
        self.loop_depth = 0
        # The last two locals are loop counters, which nothing else touches.
        self.counters = [len(fn.local_types) - 2, len(fn.local_types) - 1]
        self.usable = [i for i in range(len(fn.local_types)) if i not in self.counters]

    def locals_of(self, t: int) -> List[int]:
        return [i for i in self.usable if self.fn.local_types[i] == t]


def konst(t: int, v: int) -> Expr:
    v &= mask(t)
    c = i32_const(s32(v)) if t == I32 else i64_const(s64(v))
    return Expr(t, c, lambda st: v)


def get(t: int, i: int) -> Expr:
    return Expr(t, local_get(i), lambda st: st.locals[i])


def opcode(table: Dict[str, Tuple[int, int, Callable[..., int]]], name: str, t: int) -> bytes:
    op32, op64, _ = table[name]
    return bytes([op64 if t == I64 else op32])


def binop(name: str, t: int, a: Expr, b: Expr) -> Expr:

    def ev(st: State) -> int:
        x = a.ev(st)
        y = b.ev(st)
        return apply(name, t, x, y)
    return Expr(t, a.code + b.code + opcode(BIN, name, t), ev)


def apply(name: str, t: int, x: int, y: int) -> int:
    """The binary operation name of x and y, or a trap of a division."""
    if name in DIVISIONS and y == 0:
        raise Trap(3)
    if name == "div_s" and x == 1 << (bits(t) - 1) and y == mask(t):
        raise Trap(4)
    return BIN[name][2](t, x, y)


def gen_local_get(ctx: Ctx, t: int, depth: int) -> Expr:
    return get(t, ctx.rng.choice(ctx.locals_of(t)))


def gen_const(ctx: Ctx, t: int, depth: int) -> Expr:
    r = ctx.rng.random()
    if r < 0.3:
        v = ctx.rng.randrange(64)
    elif r < 0.5:
        v = ctx.rng.choice([0, 1, mask(t), 1 << (bits(t) - 1), 31, 32, 33, 63, 64, 0x7FFFFFFF, 0x80000000])
    else:
        v = ctx.rng.getrandbits(bits(t))
    return konst(t, v)


def gen_tee(ctx: Ctx, t: int, depth: int) -> Expr:
    i = ctx.rng.choice(ctx.locals_of(t))
    v = gen_expr(ctx, t, depth)

    def ev(st: State) -> int:
        x = v.ev(st)
        st.locals[i] = x
        return x
    return Expr(t, v.code + local_tee(i), ev)


def gen_binop(ctx: Ctx, t: int, depth: int) -> Expr:
    name = ctx.rng.choice(list(BIN))
    a = gen_expr(ctx, t, depth)
    if name in DIVISIONS and ctx.risky and ctx.rng.random() < 0.1:
        # A divisor that may be 0, or for div_s -1 with a dividend that
        # may be the most negative number.
        a, b = risky_division(ctx, name, t, depth)
    elif name in DIVISIONS and ctx.rng.random() < 0.3:
        # A constant divisor, which needs no checks, or for an unsigned i32
        # one that is a power of 2, none of the math unit.
        divisors = [1, 2, 3, 7, 16, 26, 1000, 0x7FFF, 1 << 20]
        if name != "div_s":
            divisors += [mask(t), 1 << (bits(t) - 1), 0xFFFFFFF0]
        b = konst(t, ctx.rng.choice(divisors))
    elif name in DIVISIONS:
        # A nonzero divisor, and for div_s one that is not -1, so that the
        # most negative number never overflows.
        b = binop("or", t, gen_expr(ctx, t, depth), konst(t, 1))
        if name == "div_s":
            b = binop("or", t, binop("and", t, gen_expr(ctx, t, depth), konst(t, 0x7FFF)), konst(t, 1))
    elif name == "mul" and ctx.rng.random() < 0.4:
        # A constant, which nicewasm multiplies by with shifts, additions,
        # and subtractions if few will do.
        # An i64 constant is made inline of the math unit and such steps
        # for each word, if a word has few enough, so the words vary.
        consts = [0, 1, 2, 3, 5, 12, 31, 100, 1000, 65599, 16777619, mask(t),
                  mask(t) - 2, mask(t) - 7, 1 << (bits(t) - 1), ctx.rng.getrandbits(bits(t))]
        if t == I64:
            consts += [1 << 32, (1 << 32) + 1, 0x2545F4914F6CDD1D, 0xA6CECC1B_00000001,
                       0x3_A6CECC1B, (ctx.rng.getrandbits(32) << 32) + ctx.rng.randrange(64),
                       (ctx.rng.randrange(64) << 32) + ctx.rng.getrandbits(32)]
        b = konst(t, ctx.rng.choice(consts))
        if ctx.rng.random() < 0.3:
            a, b = b, a
    elif name in SHIFTS and ctx.rng.random() < 0.5:
        b = gen_const(ctx, t, depth)  # a constant count takes the inline path
    else:
        b = gen_expr(ctx, t, depth)
    return binop(name, t, a, b)


def risky_division(ctx: Ctx, name: str, t: int, depth: int) -> Tuple[Expr, Expr]:
    """The operands of a division that may trap: a divisor that is a value
    ANDed with a small mask, or for div_s and rem_s, half the time, a
    dividend that is the most negative number or a value, and a divisor
    that is -1 or -2."""
    if name in ("div_s", "rem_s") and ctx.rng.random() < 0.5:
        least = konst(t, 1 << (bits(t) - 1))
        a = least if ctx.rng.random() < 0.3 else select(least, gen_expr(ctx, t, depth), gen_condition(ctx, depth))
        b = binop("or", t, binop("and", t, gen_expr(ctx, t, depth), konst(t, 1)), konst(t, mask(t) - 1))
        return a, b
    m = ctx.rng.choice([1, 3, 7, 0xFF])
    return gen_expr(ctx, t, depth), binop("and", t, gen_expr(ctx, t, depth), konst(t, m))


def select(a: Expr, b: Expr, c: Expr) -> Expr:
    """select of a and b by the condition c."""
    def ev(st: State) -> int:
        x = a.ev(st)
        y = b.ev(st)
        return x if c.ev(st) else y
    return Expr(a.t, a.code + b.code + c.code + SELECT, ev)


def gen_cmp(ctx: Ctx, t: int, depth: int) -> Expr:
    """An i32 that is 0 or 1: a comparison of two values of type t, or eqz."""
    if ctx.rng.random() < 0.15:
        a = gen_expr(ctx, t, depth)
        return Expr(I32, a.code + (b"\x45" if t == I32 else b"\x50"), lambda st: int(a.ev(st) == 0))
    name = ctx.rng.choice(list(CMP))
    a, b = gen_expr(ctx, t, depth), gen_expr(ctx, t, depth)
    fn = CMP[name][2]

    def ev(st: State) -> int:
        x = a.ev(st)
        y = b.ev(st)
        return fn(t, x, y)
    e = Expr(I32, a.code + b.code + opcode(CMP, name, t), ev)
    if ctx.rng.random() < 0.3:
        inner = e
        e = Expr(I32, inner.code + b"\x45", lambda st: int(inner.ev(st) == 0))
    return e


def gen_cmp_value(ctx: Ctx, t: int, depth: int) -> Expr:
    """A comparison used as a value of type t."""
    e = gen_cmp(ctx, ctx.rng.choice([I32, I64]), depth)
    if t == I64:
        return Expr(I64, e.code + EXTEND_U, e.ev)
    return e


def gen_unop(ctx: Ctx, t: int, depth: int) -> Expr:
    name = ctx.rng.choice(list(UNARY))
    a = gen_expr(ctx, t, depth)
    fn = UNARY[name][2]
    return Expr(t, a.code + opcode(UNARY, name, t), lambda st: fn(t, a.ev(st)))


def gen_convert(ctx: Ctx, t: int, depth: int) -> Expr:
    if t == I32:
        a = gen_expr(ctx, I64, depth)
        return Expr(I32, a.code + WRAP, lambda st: a.ev(st) & M32)
    a = gen_expr(ctx, I32, depth)
    if ctx.rng.random() < 0.5:
        return Expr(I64, a.code + EXTEND_S, lambda st: s32(a.ev(st)) & M64)
    return Expr(I64, a.code + EXTEND_U, a.ev)


def gen_select(ctx: Ctx, t: int, depth: int) -> Expr:
    a, b = gen_expr(ctx, t, depth), gen_expr(ctx, t, depth)
    c = gen_condition(ctx, depth)

    def ev(st: State) -> int:
        x = a.ev(st)
        y = b.ev(st)
        return x if c.ev(st) else y
    sel = SELECT if ctx.rng.random() < 0.5 else select_t(t)
    return Expr(t, a.code + b.code + c.code + sel, ev)


def gen_condition(ctx: Ctx, depth: int) -> Expr:
    """An i32 for if, br_if, or select: mostly a comparison, so that the
    flags are used directly, sometimes kept in a local by local.tee, so
    that a later condition may be the local, else any i32."""
    r = ctx.rng.random()
    if r < 0.5:
        return gen_cmp(ctx, ctx.rng.choice([I32, I64]), depth)
    if r < 0.7:
        c = gen_cmp(ctx, ctx.rng.choice([I32, I64]), depth)
        i = ctx.rng.choice(ctx.locals_of(I32))

        def ev(st: State) -> int:
            st.locals[i] = c.ev(st)
            return st.locals[i]
        return Expr(I32, c.code + local_tee(i), ev)
    return gen_expr(ctx, I32, depth)


def gen_address(ctx: Ctx, depth: int, room: int = 21) -> Expr:
    """A byte address, constant or dynamic, with room bytes from it in
    bounds: by default 8 bytes at an offset of up to 13. Dynamic addresses
    are often unaligned."""
    if ctx.rng.random() < 0.4:
        a = ctx.rng.randrange(0x400) if ctx.rng.random() < 0.7 else ctx.rng.randrange(ADDR_MASK)
        return konst(I32, a)
    if ctx.rng.random() < 0.3:
        return gen_element(ctx, depth, room)
    if ctx.rng.random() < 0.2:
        return gen_masked(ctx, depth, room)
    k = ctx.rng.randrange(8) if ctx.rng.random() < 0.6 else 0
    e = binop("and", I32, gen_expr(ctx, I32, depth), konst(I32, ADDR_MASK))
    return binop("or", I32, e, konst(I32, k)) if k else e


def gen_element(ctx: Ctx, depth: int, room: int) -> Expr:
    """The address of an array element, (i << s) + c, as clang computes
    it, sometimes with a second constant added. The index i is in 0x400
    to 0x7FF, and often has high bits set that the shift drops, so that
    the address wraps modulo 2^32 to one in bounds. The constants are
    mostly multiples of 4, and may be negative. Sometimes c / 4 is near
    the end of the memory instead (gen_end)."""
    s = ctx.rng.choice([2, 2, 3])
    if ctx.rng.random() < 0.3:
        return gen_end(ctx, depth, room, s)
    e = binop("and", I32, gen_expr(ctx, I32, depth), konst(I32, 0x3FF))
    e = binop("or", I32, e, konst(I32, 0x400))
    if ctx.rng.random() < 0.5:
        hi = ctx.rng.choice([0x40000000, 0x80000000, 0xC0000000]) >> (s - 2)
        e = binop("or", I32, e, konst(I32, hi))
    a = binop("shl", I32, e, konst(I32, s))
    # (i << s) is in 0x1000 to 0x1FFC, or 0x2000 to 0x3FF8 for s = 3, so the
    # address is in 0 to 0x6400.
    cs = [ctx.rng.randrange(-0xC00, 0x2000) // 4 * 4]
    if ctx.rng.random() < 0.3:
        cs.append(ctx.rng.randrange(-0x400, 0x400) // 4 * 4)
    if ctx.rng.random() < 0.1:
        cs[-1] += ctx.rng.randrange(1, 4)
    for c in cs:
        a = binop("add", I32, a, konst(I32, c))
    return a


def gen_end(ctx: Ctx, depth: int, room: int, s: int) -> Expr:
    """The address (i << s) + c of an array element near the end of the
    memory, with room bytes from it in bounds. Either i is at most 3, and
    c is a multiple of 4 that puts the last address that i allows at the
    last place that leaves room bytes, or up to 8 bytes before it, so that
    with room = 8 an i64 is at the last two words. Half the time i goes
    through a subtraction of 0, so that nicewasm knows no bound on it and
    keeps the compare. Or i is -16 to -9, so that i << s is -64 to -36,
    or -128 to -72 for s = 3, and c / 4 is one word below the end,
    the end, or one word past it. Then a folded access fails its compare,
    and its stub does the access, and an access with the ADD of its word
    index passes its compare."""
    top = 0x10000 - room  # the last address with room bytes in bounds
    x = gen_expr(ctx, I32, depth)
    if ctx.rng.random() < 0.6:
        m = ctx.rng.choice([0, 1, 3])
        i = binop("and", I32, x, konst(I32, m))
        if ctx.rng.random() < 0.5:
            i = binop("sub", I32, i, konst(I32, 0))
        c = (top - (m << s)) // 4 * 4 - 4 * ctx.rng.randrange(3)
    else:
        i = binop("or", I32, binop("and", I32, x, konst(I32, 7)), konst(I32, 0xFFFFFFF0))
        c = 0x10000 + 4 * ctx.rng.randrange(-1, 2)
    return binop("add", I32, binop("shl", I32, i, konst(I32, s)), konst(I32, c))


def gen_masked(ctx: Ctx, depth: int, room: int) -> Expr:
    """The address of an array element, (i << s) + c, with a masked index
    i = x & m, whose bound m may let a word access go without its compare
    (README.md). Often c puts the bound's last element just at the end of
    the memory, or a little before or past it. The value of i keeps the
    access in bounds: x is first ANDed with the largest index that fits.
    Half the time that value then goes through a subtraction of 0, so that
    nicewasm knows only the bound m, which may not fit."""
    s = ctx.rng.choice([2, 2, 3])
    m = ctx.rng.choice([0x7, 0xFF, 0x3FF, 0xFFF, 0x3FFF, 0xFFFF, 0x7FFFFFFF, M32])
    if m << s < 0x10000 and ctx.rng.random() < 0.7:
        c = (0x10000 - (m << s) - ctx.rng.randrange(-8, 64)) // 4 * 4
    else:
        c = ctx.rng.randrange(0, 0x2000) // 4 * 4
    c = min(max(c, 0), 0x10000 - room) // 4 * 4
    fits = (0x10000 - room - c) >> s  # the largest index that leaves room bytes in bounds
    x = binop("and", I32, gen_expr(ctx, I32, depth), konst(I32, fits))
    if ctx.rng.random() < 0.5:
        x = binop("sub", I32, x, konst(I32, 0))
    i = (binop("and", I32, x, konst(I32, m)) if ctx.rng.random() < 0.7
         else binop("and", I32, konst(I32, m), x))
    return binop("add", I32, binop("shl", I32, i, konst(I32, s)), konst(I32, c))


def in_bounds(addr: int, n: int) -> int:
    """The address of an access of n bytes, if they are in the memory; else
    the access traps."""
    if addr + n > PAGE:
        raise Trap(2)
    return addr


def gen_load(ctx: Ctx, t: int, depth: int) -> Expr:
    op = ctx.rng.choice([o for o, (rt, n, s) in LOADS.items() if rt == t])
    n = LOADS[op][1]
    offset = ctx.rng.choice([0, 0, 1, 4, 8, 13])
    return load(op, offset, gen_address(ctx, depth, offset + n))


def load(op: int, offset: int, a: Expr) -> Expr:
    """The load op at the address a plus offset."""
    t, n, signed = LOADS[op]

    def ev(st: State) -> int:
        addr = in_bounds(a.ev(st) + offset, n)
        v = int.from_bytes(st.mem[addr:addr + n], "little")
        if signed and v >> (8 * n - 1):
            v -= 1 << (8 * n)
        return v & mask(t)
    return Expr(t, a.code + mem(op, offset), ev)


def gen_store(ctx: Ctx, depth: int) -> Stmt:
    op = ctx.rng.choice(list(STORES))
    t, n = STORES[op]
    offset = ctx.rng.choice([0, 0, 2, 4, 9])
    return store(op, offset, gen_address(ctx, depth, offset + n), gen_expr(ctx, t, depth))


def store(op: int, offset: int, a: Expr, v: Expr) -> Stmt:
    """The store op of the value v at the address a plus offset."""
    n = STORES[op][1]

    def run(st: State) -> None:
        addr = a.ev(st) + offset
        x = v.ev(st)
        in_bounds(addr, n)
        st.mem[addr:addr + n] = (x & ((1 << (8 * n)) - 1)).to_bytes(n, "little")
    return Stmt(a.code + v.code + mem(op, offset), run)


def gen_group(ctx: Ctx, depth: int) -> Stmt:
    """An address in an i32 local, often not a multiple of 4, then two to
    four loads and stores of 4 or 8 bytes at offsets 0, 4, and 8 from the
    local, with other statements between. In a loop, nicewasm checks them
    with one compare (share_checks)."""
    base = ctx.rng.choice(ctx.locals_of(I32))
    a = gen_address(ctx, depth)

    def set_base(st: State) -> None:
        st.locals[base] = a.ev(st)
    steps = [Stmt(a.code + local_set(base), set_base)]
    k = ctx.usable.index(base)
    del ctx.usable[k]  # nothing between changes the address
    for _ in range(ctx.rng.randrange(2, 5)):
        if ctx.rng.random() < 0.3:
            steps.append(gen_set(ctx, 0))
        offset = ctx.rng.choice([0, 4, 8])
        if ctx.rng.random() < 0.5:
            op = ctx.rng.choice([0x28, 0x29, 0x34, 0x35])
            t, n, signed = LOADS[op]
            j = ctx.rng.choice(ctx.locals_of(t))

            def load(st: State, t: int = t, n: int = n, signed: bool = signed, j: int = j,
                     offset: int = offset) -> None:
                addr = in_bounds(st.locals[base] + offset, n)
                v = int.from_bytes(st.mem[addr:addr + n], "little")
                if signed and v >> (8 * n - 1):
                    v -= 1 << (8 * n)
                st.locals[j] = v & mask(t)
            steps.append(Stmt(local_get(base) + mem(op, offset) + local_set(j), load))
        else:
            op = ctx.rng.choice([0x36, 0x37, 0x3E])
            t, n = STORES[op]
            v = gen_expr(ctx, t, 0)

            def store(st: State, n: int = n, v: Expr = v, offset: int = offset) -> None:
                addr = st.locals[base] + offset
                x = v.ev(st)
                in_bounds(addr, n)
                st.mem[addr:addr + n] = (x & ((1 << (8 * n)) - 1)).to_bytes(n, "little")
            steps.append(Stmt(local_get(base) + v.code + mem(op, offset), store))
    ctx.usable.insert(k, base)

    def run(st: State) -> None:
        for step in steps:
            step.run(st)
    return Stmt(b"".join(step.code for step in steps), run)


def gen_call(ctx: Ctx, t: int, depth: int) -> Expr:
    """A call of a later function, so that there is no recursion; a quarter
    of them through the table."""
    cands = [i for i, fn in enumerate(ctx.fns) if fn.result == t and i > ctx.fidx]
    if not cands:
        return gen_const(ctx, t, depth)
    idx = ctx.rng.choice(cands)
    fn = ctx.fns[idx]
    # Sometimes the first two arguments come from one block with two
    # results.
    first = gen_multi(ctx, depth, fn.params[:2]) if ctx.rng.random() < 0.15 else None
    rest = fn.params[2:] if first is not None else fn.params
    args = [gen_expr(ctx, pt, depth) for pt in rest]
    if ctx.rng.random() < 0.25:
        target = i32_const(idx - 1) + call_indirect(ctx.rng.choice(same_types(fn.type_idx)))
    else:
        target = call(idx)

    def ev(st: State) -> int:
        values = first.ev(st) if first is not None else []
        return st.call(idx, values + [a.ev(st) for a in args])
    code_ = (first.code if first is not None else b"") + b"".join(a.code for a in args)
    return Expr(t, code_ + target, ev)


def same_types(k: int) -> List[int]:
    """The indices of the types with the parameters and results of type k."""
    return [j for j, ft in enumerate(TYPES) if ft == TYPES[k]]


def catch(b: Branch, levels: int) -> List[int]:
    """What a block that is levels labels deep makes of a branch that
    reached it: the values if the branch ends here, else it goes on."""
    if b.depth < levels:
        return b.values
    raise Branch(b.depth - levels, b.values)


def gen_if_expr(ctx: Ctx, t: int, depth: int) -> Expr:
    c = gen_condition(ctx, depth)
    ctx.labels.append(("if", [t]))
    then, els = gen_body(ctx, t, depth), gen_body(ctx, t, depth)
    ctx.labels.pop()

    def ev(st: State) -> int:
        z = c.ev(st)
        try:
            return (then if z else els).ev(st)
        except Branch as b:
            return catch(b, 1)[0]
    return Expr(t, c.code + if_(t) + then.code + ELSE + els.code + END, ev)


def gen_block_expr(ctx: Ctx, t: int, depth: int) -> Expr:
    ctx.labels.append(("block", [t]))
    body = gen_body(ctx, t, depth)
    ctx.labels.pop()

    def ev(st: State) -> int:
        try:
            return body.ev(st)
        except Branch as b:
            return catch(b, 1)[0]
    return Expr(t, block(t) + body.code + END, ev)


def gen_br_table_expr(ctx: Ctx, t: int, depth: int) -> Expr:
    """block (result i32) block (result i32) v i br_table 0 1 0 end
    i32.const c i32.add end: index 1 leaves v, every other index v + c."""
    if t != I32:
        return gen_block_expr(ctx, t, depth)
    ctx.labels += [("block", [I32]), ("block", [I32])]
    v, i = gen_expr(ctx, I32, depth), gen_expr(ctx, I32, depth)
    ctx.labels[-2:] = []
    c = ctx.rng.randrange(1, 100)

    def ev(st: State) -> int:
        try:
            x = v.ev(st)
            inner = i.ev(st) != 1
        except Branch as b:
            if b.depth >= 2:
                raise Branch(b.depth - 2, b.values)
            x, inner = b.values[0], b.depth == 0
        return (x + c) & M32 if inner else x
    return Expr(I32, block(I32) + block(I32) + v.code + i.code + br_table([0, 1], 0) + END
                + i32_const(c) + ADD + END, ev)


def gen_global_get(ctx: Ctx, t: int, depth: int) -> Expr:
    """global.get of a global of type t, mutable or not."""
    k = ctx.rng.choice([k for k, (gt, _, _) in enumerate(GLOBALS) if gt == t])
    return Expr(t, global_get(k), lambda st: st.globals[k])


def gen_global_set(ctx: Ctx, depth: int) -> Stmt:
    k = ctx.rng.choice([k for k, (_, m, _) in enumerate(GLOBALS) if m])
    v = gen_expr(ctx, GLOBALS[k][0], depth)

    def run(st: State) -> None:
        st.globals[k] = v.ev(st)
    return Stmt(v.code + global_set(k), run)


def gen_bulk(ctx: Ctx, depth: int) -> Stmt:
    """memory.fill or memory.copy of up to 63 bytes, each address and the
    count a constant or masked, so that the ranges stay in the memory.
    Mostly in the first 1 KB, which main's result folds, and the ranges of
    a copy may overlap."""
    def operand(m: int) -> Expr:
        if ctx.rng.random() < 0.4:
            return konst(I32, ctx.rng.randrange(m + 1))
        return binop("and", I32, gen_expr(ctx, I32, depth), konst(I32, m))
    m = 0x3FF if ctx.rng.random() < 0.7 else ADDR_MASK
    d = operand(m)
    fill = ctx.rng.random() < 0.5
    x = gen_expr(ctx, I32, depth) if fill else operand(m)
    return bulk(fill, d, x, operand(63))


def bulk(fill: bool, d: Expr, x: Expr, n: Expr) -> Stmt:
    """memory.fill of n bytes at d with the value x, or memory.copy of n
    bytes from x to d."""
    def run(st: State) -> None:
        a, v, k = d.ev(st), x.ev(st), n.ev(st)
        in_bounds(a, k)
        if not fill:
            in_bounds(v, k)
        if fill:
            st.mem[a:a + k] = bytes([v & 0xFF]) * k
        else:
            st.mem[a:a + k] = st.mem[v:v + k]
    return Stmt(d.code + x.code + n.code + (MEMORY_FILL if fill else MEMORY_COPY), run)


def gen_nop(ctx: Ctx, depth: int) -> Stmt:
    return Stmt(NOP, lambda st: None)


def gen_expr(ctx: Ctx, t: int, depth: int) -> Expr:
    """A random expression of type t, with nested expressions up to depth."""
    if depth <= 0:
        return gen_local_get(ctx, t, 0) if ctx.rng.random() < 0.65 else gen_const(ctx, t, 0)
    x = ctx.rng.random()
    for fn, p in EXPRS:
        x -= p
        if x < 0:
            return fn(ctx, t, depth - 1)
    return gen_local_get(ctx, t, 0)


def gen_body(ctx: Ctx, t: Optional[int], depth: int) -> Expr:
    """The body of a block: statements, then a value of type t, or nothing.
    Sometimes a br with the value comes before the value, so that the
    value is never reached."""
    stmts = [gen_stmt(ctx, depth - 1) for _ in range(ctx.rng.randrange(0, 4))]
    value = gen_expr(ctx, t, depth) if t is not None else None
    tail = gen_br(ctx, depth, unconditional=True) if ctx.rng.random() < 0.15 else None

    def ev(st: State) -> int:
        for s in stmts:
            s.run(st)
        if tail is not None:
            tail.run(st)
        return value.ev(st) if value is not None else 0
    code = b"".join(s.code for s in stmts)
    code += tail.code if tail is not None else b""
    code += value.code if value is not None else b""
    return Expr(t if t is not None else I32, code, ev)


def gen_br(ctx: Ctx, depth: int, unconditional: bool = False, out: bool = False) -> Stmt:
    """br_if n, or br n, to a block, an if, or the function, with the values
    the label takes. Never to a loop, so that every loop ends. With out,
    to the function. The values that a br_if not taken leaves are dropped
    or kept in locals."""
    cands = [n for n, (kind, lt) in enumerate(reversed(ctx.labels)) if kind != "loop"]
    n = cands[-1] if out else ctx.rng.choice(cands)
    _, lts = ctx.labels[len(ctx.labels) - 1 - n]
    vs = [gen_expr(ctx, lt, depth) for lt in lts]
    vcode = b"".join(v.code for v in vs)
    if unconditional:
        def run(st: State) -> None:
            raise Branch(n, [v.ev(st) for v in vs])
        # A br to the function's label is a return, which may say so.
        jump = RETURN if n == len(ctx.labels) - 1 and ctx.rng.random() < 0.5 else br(n)
        return Stmt(vcode + jump, run)
    c = gen_condition(ctx, depth)
    keep, after = consume(ctx, lts)

    def run_if(st: State) -> None:
        xs = [v.ev(st) for v in vs]
        if c.ev(st):
            raise Branch(n, xs)
        keep(st, xs)
    return Stmt(vcode + c.code + br_if(n) + after, run_if)


def consume(ctx: Ctx, ts: List[int]) -> Tuple[Callable[[State, List[int]], None], bytes]:
    """Code that takes values of the types ts off the operand stack, the
    last first, and drops each or sets a local to it, and its model, a
    function of the values."""
    dests = [ctx.rng.choice(ctx.locals_of(t)) if ctx.rng.random() < 0.75 else None for t in ts]

    def keep(st: State, xs: List[int]) -> None:
        for j, x in reversed(list(zip(dests, xs))):
            if j is not None:
                st.locals[j] = x
    return keep, b"".join(local_set(j) if j is not None else DROP for j in reversed(dests))


def gen_set(ctx: Ctx, depth: int) -> Stmt:
    t = ctx.rng.choice([I32, I32, I64])
    i = ctx.rng.choice(ctx.locals_of(t))
    if ctx.rng.random() < 0.3:
        # The old value stays on the operand stack while a local.tee
        # changes the local; then both are combined into the local.
        name = ctx.rng.choice(["add", "sub", "xor", "or"])
        inner = gen_expr(ctx, t, depth)

        def tee(st: State) -> int:
            x = inner.ev(st)
            st.locals[i] = x
            return x
        v = binop(name, t, get(t, i), Expr(t, inner.code + local_tee(i), tee))
    else:
        v = gen_expr(ctx, t, depth)

    def run(st: State) -> None:
        st.locals[i] = v.ev(st)
    return Stmt(v.code + local_set(i), run)


def gen_loop(ctx: Ctx, depth: int) -> Stmt:
    """A loop that runs 1 to 4 times, counted in a counter local."""
    if ctx.loop_depth >= 2:
        return gen_set(ctx, depth)
    ctr, k = ctx.counters[ctx.loop_depth], ctx.rng.randrange(1, 5)
    ctx.loop_depth += 1
    ctx.labels.append(("loop", []))
    stmts = [gen_stmt(ctx, depth - 1) for _ in range(ctx.rng.randrange(1, 4))]
    ctx.labels.pop()
    ctx.loop_depth -= 1

    def run(st: State) -> None:
        st.locals[ctr] = 0
        while True:
            try:
                for s in stmts:
                    s.run(st)
            except Branch as b:
                assert b.depth != 0  # no branch targets the loop itself
                raise Branch(b.depth - 1, b.values)
            st.locals[ctr] = (st.locals[ctr] + 1) & M32
            if st.locals[ctr] >= k:
                return
    code = i32_const(0) + local_set(ctr) + loop() + b"".join(s.code for s in stmts)
    code += local_get(ctr) + i32_const(1) + ADD + local_tee(ctr) + i32_const(k) + LT_U + br_if(0) + END
    return Stmt(code, run)


def gen_if_stmt(ctx: Ctx, depth: int) -> Stmt:
    c = gen_condition(ctx, depth)
    ctx.labels.append(("if", []))
    then = gen_body(ctx, None, depth)
    els = gen_body(ctx, None, depth) if ctx.rng.random() < 0.6 else None
    ctx.labels.pop()

    def run(st: State) -> None:
        z = c.ev(st)
        try:
            if z:
                then.ev(st)
            elif els is not None:
                els.ev(st)
        except Branch as b:
            catch(b, 1)
    return Stmt(c.code + if_() + then.code + (ELSE + els.code if els is not None else b"") + END, run)


def gen_block_stmt(ctx: Ctx, depth: int) -> Stmt:
    ctx.labels.append(("block", []))
    body = gen_body(ctx, None, depth)
    ctx.labels.pop()

    def run(st: State) -> None:
        try:
            body.ev(st)
        except Branch as b:
            catch(b, 1)
    return Stmt(block() + body.code + END, run)


def convert(t: int, to: int, signed: bool) -> Tuple[bytes, Callable[[int], int]]:
    """The conversion of a value of type t to type to: i32.wrap_i64,
    i64.extend_i32_s or _u, or nothing, and its model."""
    if t == to:
        return b"", lambda x: x
    if to == I32:
        return WRAP, lambda x: x & M32
    if signed:
        return EXTEND_S, lambda x: s32(x) & M64
    return EXTEND_U, lambda x: x


def fold(ctx: Ctx, ts: List[int], to: int) -> Tuple[bytes, Callable[[List[int]], int]]:
    """Code that folds values of the types ts on the operand stack into one
    of type to, each time the top one into the one below it, and its model,
    a function of the values."""
    steps: List[Tuple[int, str, Callable[[int], int]]] = []
    code_ = b""
    for i in reversed(range(len(ts) - 1)):
        cc, cf = convert(ts[i + 1], ts[i], ctx.rng.random() < 0.5)
        name = ctx.rng.choice(FOLD_OPS)
        steps.append((i, name, cf))
        code_ += cc + opcode(BIN, name, ts[i])
    lc, lf = convert(ts[0], to, ctx.rng.random() < 0.5)

    def ev(xs: List[int]) -> int:
        acc = xs[-1]
        for i, name, cf in steps:
            acc = apply(name, ts[i], xs[i], cf(acc))
        return lf(acc)
    return code_ + lc, ev


Arm = Tuple[bytes, Callable[[State, List[int]], List[int]]]


def reshape(ctx: Ctx, ps: List[int], rs: List[int], depth: int) -> Arm:
    """Code that turns values of the types ps on the operand stack into
    values of the types rs, and its model, a function of the values: the
    values are folded into the first result, or dropped if there is none,
    and the other results are new expressions. If the types are the same,
    sometimes the values are left as they are."""
    if ps == rs and ps and ctx.rng.random() < 0.25:
        return b"", lambda st, xs: list(xs)
    first: Optional[Callable[[State, List[int]], int]] = None
    code_ = b""
    if ps:
        fc, ff = fold(ctx, ps, rs[0] if rs else I32)
        if rs:
            name, e, t = ctx.rng.choice(FOLD_OPS), gen_expr(ctx, rs[0], depth), rs[0]
            code_ = fc + e.code + opcode(BIN, name, t)

            def first_value(st: State, xs: List[int]) -> int:
                x = ff(xs)
                return apply(name, t, x, e.ev(st))
            first = first_value
        else:
            code_ = fc + DROP
    others = [gen_expr(ctx, t, depth) for t in (rs[1:] if ps else rs)]

    def ev(st: State, xs: List[int]) -> List[int]:
        out = [first(st, xs)] if first is not None else []
        return out + [o.ev(st) for o in others]
    return code_ + b"".join(o.code for o in others), ev


def gen_arm(ctx: Ctx, ps: List[int], rs: List[int], depth: int) -> Arm:
    """The body of a block, or of one arm of an if, of the type ps -> rs:
    statements, with the parameters still on the operand stack, sometimes
    a br, then the results made from the parameters by reshape. Its code,
    and its model, a function of the parameters."""
    stmts = [gen_stmt(ctx, depth - 1) for _ in range(ctx.rng.randrange(0, 4))]
    tail = gen_br(ctx, depth, unconditional=True) if ctx.rng.random() < 0.1 else None
    rc, rf = reshape(ctx, ps, rs, depth)

    def ev(st: State, xs: List[int]) -> List[int]:
        for s in stmts:
            s.run(st)
        if tail is not None:
            tail.run(st)
        return rf(st, xs)
    return b"".join(s.code for s in stmts) + (tail.code if tail is not None else b"") + rc, ev


def gen_multi(ctx: Ctx, depth: int, rs: Optional[List[int]] = None, results: bool = False) -> Multi:
    """A block, if, loop, or br_table of a block type that names a function
    type, so that it may have parameters and several results: of the types
    rs if given, else with at least one result if results is set. Its
    parameters come first."""
    ks = [k for k, (_, r) in enumerate(TYPES) if (r == rs if rs is not None else r or not results)]
    k = ctx.rng.choice(ks)
    ps, rs = TYPES[k]
    forms = ["block", "if", "if"]
    if ctx.loop_depth < 2:
        forms.append("loop")
    if not ps and rs:
        forms.append("br_table")
    form = ctx.rng.choice(forms)
    if form == "br_table":
        return gen_br_table_multi(ctx, k, depth)
    args = [gen_expr(ctx, p, depth) for p in ps]
    acode = b"".join(a.code for a in args)

    def params(st: State) -> List[int]:
        return [a.ev(st) for a in args]
    if form == "block":
        ctx.labels.append(("block", rs))
        bc, bf = gen_arm(ctx, ps, rs, depth)
        ctx.labels.pop()

        def ev_block(st: State) -> List[int]:
            xs = params(st)
            try:
                return bf(st, xs)
            except Branch as b:
                return list(catch(b, 1))
        return Multi(rs, acode + block(typeidx(k)) + bc + END, ev_block)
    if form == "if":
        c = gen_condition(ctx, depth)
        ctx.labels.append(("if", rs))
        tc, tf = gen_arm(ctx, ps, rs, depth)
        # Without else, the parameters are the results.
        els = gen_arm(ctx, ps, rs, depth) if ps != rs or ctx.rng.random() < 0.7 else None
        ctx.labels.pop()

        def ev_if(st: State) -> List[int]:
            xs = params(st)
            z = c.ev(st)
            try:
                if z:
                    return tf(st, xs)
                return els[1](st, xs) if els is not None else xs
            except Branch as b:
                return list(catch(b, 1))
        ecode = ELSE + els[0] if els is not None else b""
        return Multi(rs, acode + c.code + if_(typeidx(k)) + tc + ecode + END, ev_if)
    # A loop that runs 1 to 4 times, counted in a counter local, whose
    # br_if carries new parameters each time around.
    ctr, n = ctx.counters[ctx.loop_depth], ctx.rng.randrange(1, 5)
    ctx.loop_depth += 1
    ctx.labels.append(("loop", ps))
    stmts = [gen_stmt(ctx, depth - 1) for _ in range(ctx.rng.randrange(0, 3))]
    ac, af = reshape(ctx, ps, ps, depth)
    oc, of = reshape(ctx, ps, rs, depth)
    ctx.labels.pop()
    ctx.loop_depth -= 1

    def ev_loop(st: State) -> List[int]:
        xs = params(st)
        st.locals[ctr] = 0
        while True:
            try:
                for s in stmts:
                    s.run(st)
                xs = af(st, xs)
                st.locals[ctr] += 1
                if st.locals[ctr] < n:
                    continue
                return of(st, xs)
            except Branch as b:
                assert b.depth != 0  # no branch targets the loop itself
                raise Branch(b.depth - 1, b.values)
    lcode = acode + i32_const(0) + local_set(ctr) + loop(typeidx(k)) + b"".join(s.code for s in stmts) + ac
    lcode += local_get(ctr) + i32_const(1) + ADD + local_tee(ctr) + i32_const(n) + LT_U + br_if(0)
    return Multi(rs, lcode + oc + END, ev_loop)


def gen_br_table_multi(ctx: Ctx, k: int, depth: int) -> Multi:
    """block (type k) block (type k) v1 ... vn i br_table ... end c add end,
    where type k has no parameters: target 1 leaves v1 to vn, target 0
    adds c to vn, and a target past them, to an enclosing block, if, or
    function with the same results, goes on."""
    rs = TYPES[k][1]
    ctx.labels += [("block", rs), ("block", rs)]
    vs = [gen_expr(ctx, t, depth) for t in rs]
    i = gen_expr(ctx, I32, depth)
    if ctx.rng.random() < 0.6:
        i = binop("and", I32, i, konst(I32, 3))
    ctx.labels[-2:] = []
    outer = [n + 2 for n, (kind, lts) in enumerate(reversed(ctx.labels)) if kind != "loop" and lts == rs]

    def target() -> int:
        return ctx.rng.choice(outer) if outer and ctx.rng.random() < 0.1 else ctx.rng.randrange(2)
    labels = [target() for _ in range(ctx.rng.randrange(1, 4))]
    default = target()
    c, tl = ctx.rng.randrange(1, 100), rs[-1]

    def ev(st: State) -> List[int]:
        try:
            xs = [v.ev(st) for v in vs]
            idx = i.ev(st)
        except Branch as b:
            if b.depth >= 2:
                raise Branch(b.depth - 2, b.values)
            xs, to = list(b.values), b.depth
        else:
            to = labels[idx] if idx < len(labels) else default
            if to >= 2:
                raise Branch(to - 2, xs)
        if to == 0:
            xs[-1] = (xs[-1] + c) & mask(tl)
        return xs
    code_ = block(typeidx(k)) + block(typeidx(k)) + b"".join(v.code for v in vs) + i.code
    code_ += br_table(labels, default) + END + konst(tl, c).code + opcode(BIN, "add", tl) + END
    return Multi(rs, code_, ev)


def gen_multi_expr(ctx: Ctx, t: int, depth: int) -> Expr:
    """A block with several results, or one, folded into a value of type t."""
    m = gen_multi(ctx, depth, results=True)
    fc, ff = fold(ctx, m.ts, t)
    return Expr(t, m.code + fc, lambda st: ff(m.ev(st)))


def gen_multi_stmt(ctx: Ctx, depth: int) -> Stmt:
    """A block with several results, or none, each dropped or kept in a
    local."""
    m = gen_multi(ctx, depth)
    keep, after = consume(ctx, m.ts)

    def run(st: State) -> None:
        keep(st, m.ev(st))
    return Stmt(m.code + after, run)


def gen_trap(ctx: Ctx, depth: int) -> Stmt:
    """A statement that may trap: an unreachable under a condition, a
    division that may be by 0 or overflow, a call_indirect whose index may
    be past the table or name a function of another type, and with bounds,
    an access, memory.fill, or memory.copy that may pass the end of the
    memory. Sometimes under a condition of its own."""
    kinds = ["unreachable", "div", "indirect"] + (["load", "store", "bulk"] if ctx.bounds else [])
    kind = ctx.rng.choice(kinds)
    if kind == "unreachable" or (kind == "indirect" and ctx.fidx == len(ctx.fns) - 1):
        return maybe_unreachable(ctx, depth)
    c = gen_condition(ctx, depth) if ctx.rng.random() < 0.4 else None
    if c is not None:
        ctx.labels.append(("if", []))
    if kind == "div":
        t = ctx.rng.choice([I32, I64])
        name = ctx.rng.choice(DIVISIONS + ("div_s", "div_s"))  # half div_s, which may overflow
        a, b = risky_division(ctx, name, t, depth)
        st_ = set_local(ctx.rng.choice(ctx.locals_of(t)), binop(name, t, a, b))
    elif kind == "indirect":
        st_ = risky_indirect(ctx, depth)
    elif kind == "load":
        op = ctx.rng.choice(list(LOADS))
        offset = ctx.rng.choice([0, 0, 3, 8])
        e = load(op, offset, risky_address(ctx, depth, offset))
        st_ = set_local(ctx.rng.choice(ctx.locals_of(e.t)), e)
    elif kind == "store":
        op = ctx.rng.choice(list(STORES))
        offset = ctx.rng.choice([0, 0, 3, 8])
        st_ = store(op, offset, risky_address(ctx, depth, offset), gen_expr(ctx, STORES[op][0], depth))
    else:
        fill = ctx.rng.random() < 0.5
        d = risky_address(ctx, depth, 0)
        x = gen_expr(ctx, I32, depth) if fill else risky_address(ctx, depth, 0)
        n = (binop("and", I32, gen_expr(ctx, I32, depth), konst(I32, 0x3F)) if ctx.rng.random() < 0.8
             else konst(I32, ctx.rng.choice([0, 1, PAGE])))
        st_ = bulk(fill, d, x, n)
    if c is None:
        return st_
    ctx.labels.pop()
    cond, inner = c, st_

    def run_if(st: State) -> None:
        if cond.ev(st):
            try:
                inner.run(st)
            except Branch as b:
                catch(b, 1)
    return Stmt(c.code + if_() + inner.code + END, run_if)


def maybe_unreachable(ctx: Ctx, depth: int) -> Stmt:
    """if c unreachable end."""
    c = gen_condition(ctx, depth)

    def run(st: State) -> None:
        if c.ev(st):
            raise Trap(1)
    return Stmt(c.code + if_() + UNREACHABLE + END, run)


def set_local(i: int, v: Expr) -> Stmt:
    def run(st: State) -> None:
        st.locals[i] = v.ev(st)
    return Stmt(v.code + local_set(i), run)


def risky_address(ctx: Ctx, depth: int, offset: int) -> Expr:
    """An address that, with offset, is near the end of the memory, so that
    an access there may pass it, or sometimes far past it."""
    if ctx.rng.random() < 0.15:
        return konst(I32, ctx.rng.choice([PAGE, PAGE - 1, 0xFFFFFFFC, 0x80000000, M32 - offset]))
    m = ctx.rng.choice([0x7, 0x1F, 0x3F])
    e = binop("and", I32, gen_expr(ctx, I32, depth), konst(I32, m))
    return binop("add", I32, e, konst(I32, PAGE - offset - ctx.rng.choice([4, 8, 16, 32, 64])))


def risky_indirect(ctx: Ctx, depth: int) -> Stmt:
    """call_indirect of a later function, with an index that a condition
    chooses: the function's, or one past the table, or that of a function
    of another type. Its result goes to a local."""
    idx = ctx.rng.choice([i for i in range(1, len(ctx.fns)) if i > ctx.fidx])
    fn = ctx.fns[idx]
    k = ctx.rng.choice(same_types(fn.type_idx))
    bad = ctx.rng.choice([3, 4, 100, M32, 0x80000000]
                         + [e for e in range(3) if TYPES[ctx.fns[e + 1].type_idx] != TYPES[k]])
    args = [gen_expr(ctx, p, depth) for p in fn.params]
    index = select(konst(I32, idx - 1), konst(I32, bad), gen_condition(ctx, depth))
    j = ctx.rng.choice(ctx.locals_of(fn.result))

    def run(st: State) -> None:
        xs = [a.ev(st) for a in args]
        e = index.ev(st)
        if e >= 3:
            raise Trap(6)
        if TYPES[ctx.fns[e + 1].type_idx] != TYPES[k]:
            raise Trap(7)
        st.locals[j] = st.call(e + 1, xs)
    code_ = b"".join(a.code for a in args) + index.code + call_indirect(k) + local_set(j)
    return Stmt(code_, run)


def gen_drop(ctx: Ctx, depth: int) -> Stmt:
    e = gen_expr(ctx, ctx.rng.choice([I32, I64]), depth)

    def run(st: State) -> None:
        e.ev(st)
    return Stmt(e.code + DROP, run)


EXPRS: List[Tuple[Callable[[Ctx, int, int], Expr], float]] = [
    (gen_local_get, 0.15), (gen_global_get, 0.03), (gen_const, 0.10), (gen_binop, 0.23), (gen_cmp_value, 0.05),
    (gen_unop, 0.04), (gen_convert, 0.06), (gen_select, 0.05), (gen_load, 0.08),
    (gen_tee, 0.06), (gen_call, 0.05), (gen_if_expr, 0.04), (gen_block_expr, 0.02),
    (gen_br_table_expr, 0.02), (gen_multi_expr, 0.02)]


def gen_stmt(ctx: Ctx, depth: int) -> Stmt:
    if ctx.risky and ctx.rng.random() < 0.04:
        return gen_trap(ctx, max(depth, 1))
    r = ctx.rng.random()
    if depth <= 0:
        # Only statements that nest nothing.
        if r < 0.45:
            return gen_set(ctx, 1)
        if r < 0.5:
            return gen_global_set(ctx, 1)
        if r < 0.75:
            return gen_store(ctx, 1)
        if r < 0.9:
            return gen_br(ctx, 1)
        if r < 0.92:
            return gen_nop(ctx, 1)
        return gen_drop(ctx, 1)
    if r < 0.30:
        return gen_set(ctx, depth)
    if r < 0.34:
        return gen_global_set(ctx, depth)
    if r < 0.40:
        return gen_group(ctx, depth)
    if r < 0.51:
        return gen_store(ctx, depth)
    if r < 0.55:
        return gen_bulk(ctx, depth)
    if r < 0.65:
        return gen_loop(ctx, depth)
    if r < 0.75:
        return gen_if_stmt(ctx, depth)
    if r < 0.80:
        return gen_block_stmt(ctx, depth)
    if r < 0.85:
        return gen_multi_stmt(ctx, depth)
    if r < 0.93:
        return gen_br(ctx, depth)
    return gen_drop(ctx, depth)


def checksum(fn: Func) -> Expr:
    """main's result: a fold of every local, of 18 memory words, and of
    the globals."""
    def low(i: int) -> Expr:
        return Expr(I32, local_get(i) + WRAP, lambda st: st.locals[i] & M32)

    def high(i: int) -> Expr:
        return Expr(I32, local_get(i) + i64_const(32) + SHR_U64 + WRAP, lambda st: st.locals[i] >> 32)

    def glow(k: int) -> Expr:
        return Expr(I32, global_get(k) + (WRAP if GLOBALS[k][0] == I64 else b""),
                    lambda st: st.globals[k] & M32)

    def ghigh(k: int) -> Expr:
        return Expr(I32, global_get(k) + i64_const(32) + SHR_U64 + WRAP, lambda st: st.globals[k] >> 32)

    def word(a: int) -> Expr:
        return Expr(I32, i32_const(a) + mem(I32_LOAD), lambda st: int.from_bytes(st.mem[a:a + 4], "little"))

    parts: List[Expr] = []
    for i, t in enumerate(fn.local_types):
        parts += [get(I32, i)] if t == I32 else [low(i), high(i)]
    parts += [word(a) for a in range(0, 0x400, 0x3C)]
    for k, (t, _, _) in enumerate(GLOBALS):
        parts += [glow(k)] if t == I32 else [glow(k), ghigh(k)]
    code = i32_const(0)
    for p in parts:
        code += i32_const(31) + b"\x6c" + p.code + ADD

    def ev(st: State) -> int:
        acc = 0
        for p in parts:
            acc = (acc * 31 + p.ev(st)) & M32
        return acc
    return Expr(I32, code, ev)


def build(seed: int, bounds: bool = True) -> Tuple[List[Func], bytes]:
    """The four functions, with random bodies, and the data segment. In 40%
    of the modules, the bodies have statements and divisions that may trap,
    and with bounds, among them accesses out of bounds."""
    rng = random.Random(seed)
    risky = rng.random() < 0.4
    fns = [Func(0, [], I32, [I32] * 7 + [I64] * 3 + [I32, I32]),
           Func(1, [I32, I64, I32, I32], I32, [I32, I64, I32, I32] + [I32] * 3 + [I64] * 2 + [I32, I32]),
           Func(2, [I64, I32], I64, [I64, I32] + [I32] * 2 + [I64] * 2 + [I32, I32]),
           Func(3, [I32, I32], I32, [I32, I32] + [I32] * 6 + [I64] + [I32, I32])]
    for idx, fn in enumerate(fns):
        ctx = Ctx(rng, fn, idx, fns, risky, bounds)
        count = rng.randrange(8, 20) if idx == 0 else rng.randrange(3, 10)
        # Half of the other functions start with a br_if out of the
        # function, an early exit before the prologue (README.md).
        fn.stmts = [gen_br(ctx, 0, out=True)] if idx and rng.random() < 0.5 else []
        fn.stmts += [gen_stmt(ctx, 3) for _ in range(count)]
        fn.value = checksum(fn) if idx == 0 else gen_expr(ctx, fn.result, 3)
    return fns, bytes(rng.getrandbits(8) for _ in range(DATA_SIZE))


# What a program does: ("value", main's result) or ("trap", the code).
Outcome = Tuple[str, int]


def show(o: Optional[Outcome]) -> str:
    if o is None:
        return "no result"
    return f"{o[1]:#010x}" if o[0] == "value" else f"trap {o[1]}"


def finish(fns: List[Func], segment: bytes) -> Tuple[bytes, Outcome]:
    """The module, and the outcome the model gives for it."""
    mod = module(
        types(*TYPES),
        funcs(*[fn.type_idx for fn in fns]),
        table(3),
        memory(1),
        typed_globals(*[(t, m, s32(v) if t == I32 else s64(v)) for t, m, v in GLOBALS]),
        exports(("main", 0, 0)),
        elems((0, [1, 2, 3])),
        code(*[(fn.local_types[len(fn.params):], fn.body().code) for fn in fns]),
        data((DATA, segment)))
    memory_ = bytearray(65536)
    memory_[DATA:DATA + DATA_SIZE] = segment
    try:
        return mod, ("value", State(fns, memory_).call(0, []))
    except Trap as t:
        return mod, ("trap", t.code)


def run(cmd: List[str]) -> None:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(" ".join(cmd) + "\n" + p.stdout + p.stderr)


def pipeline(mod: bytes, tmp: str, opts: List[str], name: str) -> Tuple[Optional[Outcome], str]:
    """Translates the module with the options opts of nicewasm, joins,
    assembles, and runs it. Returns the outcome, R1 after a HALT, or the
    code in R1 after a halt at ___wasm_trap, or None after any other halt,
    and the emulator's output."""
    wasm_file = os.path.join(tmp, name + ".wasm")
    with open(wasm_file, "wb") as f:
        f.write(mod)
    asm = os.path.join(tmp, name + ".nasm")
    nompu = "--no-mpu" in opts
    run([sys.executable, NICEWASM, *opts, "-o", asm, wasm_file])
    parts = [os.path.join(RUNTIME, "start_wasm.nasm"), asm, os.path.join(RUNTIME, "lib.nasm"),
             os.path.join(RUNTIME, "muldiv_soft.nasm" if nompu else "muldiv_mpu.nasm")]
    full = os.path.join(tmp, name + ".full.nasm")
    with open(full, "w") as out:
        for part in parts:
            with open(part) as f:
                out.write(f.read() + "\n")
    binary = os.path.join(tmp, name + ".bin")
    run([sys.executable, NICEASM, "-o", binary, full])
    p = subprocess.run([NICEEMU, "-n", "20000000", binary], capture_output=True, text=True)
    r1 = None
    for line in p.stdout.splitlines():
        if line.startswith("R0 "):
            tokens = line.split()
            r1 = int(tokens[tokens.index("R1") + 1], 16)
    if r1 is not None and p.returncode == 0 and p.stdout.startswith("Halted (HALT)"):
        return ("value", r1), p.stdout
    if r1 is not None and p.returncode == 2 and p.stdout.startswith("Halted (reserved control instruction)"):
        return ("trap", r1), p.stdout
    return None, p.stdout


def check(seed: int, tmp: str, opts: List[str], keep: Optional[str] = None) -> Tuple[Optional[str], Outcome]:
    """Runs one seed. Returns a description of the failure, or None, and
    the outcome the model expected. With keep, the program is copied to
    keep/fuzzSEED.bin, with the mode in the name."""
    fns, segment = build(seed, "--no-bounds-checks" not in opts)
    mod, expected = finish(fns, segment)
    try:
        got, output = pipeline(mod, tmp, opts, f"fuzz{seed}")
    except RuntimeError as e:
        return f"seed {seed}: " + str(e).replace("\n", "\n  "), expected
    if keep is not None:
        suffix = "".join(a.replace("--", "_").replace("-", "") for a in MODES if MODES[a][0] in opts)
        shutil.copy(os.path.join(tmp, f"fuzz{seed}.bin"), os.path.join(keep, f"fuzz{seed}{suffix}.bin"))
    if got == expected:
        return None, expected
    first = output.splitlines()[0] if output else ""
    return f"seed {seed}: expected {show(expected)}, got {show(got)}\n  {first}", expected


def reduce(seed: int, tmp: str, opts: List[str]) -> None:
    """Removes statements while the mismatch persists, and writes the
    reduced module and its translation to the current directory."""
    fns, segment = build(seed, "--no-bounds-checks" not in opts)

    def mismatch() -> bool:
        mod, expected = finish(fns, segment)
        try:
            got, _ = pipeline(mod, tmp, opts, "reduce")
        except RuntimeError:
            return True
        return got != expected
    if not mismatch():
        sys.exit(f"seed {seed} does not fail")
    changed = True
    while changed:
        changed = False
        for fn in fns:
            for i in reversed(range(len(fn.stmts))):
                saved = fn.stmts.pop(i)
                if mismatch():
                    changed = True
                else:
                    fn.stmts.insert(i, saved)
    mod, expected = finish(fns, segment)
    with open(f"fuzz_{seed}.wasm", "wb") as f:
        f.write(mod)
    try:
        got, _ = pipeline(mod, tmp, opts, "reduce")
    except RuntimeError as e:
        # The translator rejected the module, or the assembler the translation.
        print(f"reduced to {[len(fn.stmts) for fn in fns]} statements: {str(e).strip().splitlines()[-1]}; "
              f"see fuzz_{seed}.wasm")
        return
    shutil.move(os.path.join(tmp, "reduce.nasm"), f"fuzz_{seed}.nasm")
    print(f"reduced to {[len(fn.stmts) for fn in fns]} statements: expected {show(expected)}, "
          f"got {show(got)}; see fuzz_{seed}.wasm and fuzz_{seed}.nasm")


# The modes: fuzz.py's option -> nicewasm's options.
MODES = {"--no-mpu": ["--no-mpu"], "--unchecked": ["--no-bounds-checks"],
         "--grow": ["--memory-pages", "2"]}


def main() -> None:
    args = sys.argv[1:]
    keep = None
    if "--keep" in args:
        i = args.index("--keep")
        if i + 1 >= len(args):
            sys.exit(__doc__.split("\n\n")[1])
        keep = args[i + 1]
        del args[i:i + 2]
        os.makedirs(keep, exist_ok=True)
    opts = [o for a in args for o in MODES.get(a, [])]
    do_reduce = "--reduce" in args
    numbers = [a for a in args if not a.startswith("--")]
    if len(numbers) != 2 or any(a not in (*MODES, "--reduce") for a in args if a.startswith("--")):
        sys.exit(__doc__.split("\n\n")[1])
    first, count = int(numbers[0]), int(numbers[1])
    with tempfile.TemporaryDirectory() as tmp:
        if do_reduce:
            reduce(first, tmp, opts)
            return
        # The seeds run in parallel, each with files of its own name.
        failures = []
        traps = 0
        with concurrent.futures.ThreadPoolExecutor(os.cpu_count()) as pool:
            for problem, expected in pool.map(lambda seed: check(seed, tmp, opts, keep), range(first, first + count)):
                traps += expected[0] == "trap"
                if problem is not None:
                    failures.append(problem)
                    print("FAIL " + problem)
    suffix = "".join(", " + a for a in args if a in MODES)
    print(f"{'FAIL' if failures else 'PASS'} fuzz ({count} cases{suffix}, {traps} of them trap)")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
