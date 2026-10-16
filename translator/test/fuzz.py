#!/usr/bin/env python3
"""A random test of nicewasm against a model of wasm written in Python.

Usage: fuzz.py [--no-mpu] [--reduce] FIRST COUNT

Each case is a module built from a random syntax tree. Every node of the
tree emits its wasm bytes and evaluates itself in Python with the
semantics of the WebAssembly specification, so the model and the module
always describe the same program. The module is translated, joined with
the runtime as run.py does, assembled, and run, and main's result in R1
must equal the model's. Seeds FIRST to FIRST + COUNT - 1 are tried; the
same seed always gives the same module.

A module has four functions: main, f(i32, i64, i32, i32) -> i32, whose
last argument goes on the stack, g(i64, i32) -> i64, and h(i32, i32) ->
i32. Each has 8 to 13 locals, i32 and i64, so that with the values on
the operand stack some live in registers and some are spilled to the
frame. The bodies use blocks,
loops, if and else, br, br_if, and br_table with and without values,
select, calls and call_indirect, every integer operation and comparison,
comparisons kept in a local by local.tee for later conditions, eqz
before if and br_if, i64 shifts by constants and by variables,
multiplications by constants, divisions with nonzero divisors, some of
them constants, loads and stores of every width at
constant and at dynamic addresses, and local.set and local.tee of locals
whose old value is still on the operand stack. That covers the rules for
deferred values, fused comparisons, forwarded results, and register
allocation in README.md. main returns a fold of every local and of 18 memory
words, so a wrong value anywhere shows. Two locals of each function are
loop counters that nothing else touches, so every loop ends.

With --no-mpu, nicewasm is run with that option and the program is joined
with muldiv_soft.nasm instead of muldiv_mpu.nasm. With --reduce, FIRST is
a failing seed: statements are removed from the functions while the
mismatch persists, and the reduced module and its translation are written
to fuzz_FIRST.wasm and fuzz_FIRST.nasm in the current directory.

This test does not replace run.py, whose cases are checked by hand. It
is cheap to run on many seeds, and it found three bugs while it was
written, all three in the model. make test runs 40 seeds in each mode."""

from __future__ import annotations

import os
import random
import shutil
import subprocess
import sys
import tempfile
from typing import Callable, Dict, List, Optional, Tuple

from wasm import (ADD, AND, DROP, ELSE, END, EXTEND_S, EXTEND_U, I32, I64, LT_U, OR, SELECT,
                  SHR_U64, WRAP, block, br, br_if, br_table, call, call_indirect, code, data,
                  elems, exports, funcs, i32_const, i64_const, if_, local_get, local_set,
                  local_tee, loop, mem, memory, module, table, types)

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
ADDR_MASK, DATA, DATA_SIZE = 0x7FF8, 0x100, 256


class Branch(Exception):
    """A br, br_if, or br_table taken in the model: the label's depth from
    the raising point, and the value it carries."""

    def __init__(self, depth: int, value: Optional[int]) -> None:
        super().__init__(depth, value)
        self.depth = depth
        self.value = value


class State:
    """The model's state while a function runs."""

    def __init__(self, fns: List[Func], memory: bytearray) -> None:
        self.fns = fns
        self.mem = memory
        self.locals: List[int] = []

    def call(self, idx: int, args: List[int]) -> int:
        fn = self.fns[idx]
        saved = self.locals
        self.locals = list(args) + [0] * (len(fn.local_types) - len(args))
        try:
            v = fn.body().ev(self)
        except Branch as b:
            assert b.depth == 0 and b.value is not None
            v = b.value
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
    scope, from the function outward, and the locals it may use."""

    def __init__(self, rng: random.Random, fn: Func, fidx: int, fns: List[Func]) -> None:
        self.rng, self.fn, self.fidx, self.fns = rng, fn, fidx, fns
        self.labels: List[Tuple[str, Optional[int]]] = [("func", fn.result)]
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
    fn = BIN[name][2]

    def ev(st: State) -> int:
        x = a.ev(st)
        y = b.ev(st)
        return fn(t, x, y)
    return Expr(t, a.code + b.code + opcode(BIN, name, t), ev)


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
    if name in DIVISIONS and ctx.rng.random() < 0.3:
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
    return Expr(t, a.code + b.code + c.code + SELECT, ev)


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


def gen_address(ctx: Ctx, depth: int) -> Expr:
    """A byte address, constant or dynamic, with 8 bytes and an offset of
    up to 13 in bounds. Dynamic addresses are often unaligned."""
    if ctx.rng.random() < 0.4:
        a = ctx.rng.randrange(0x400) if ctx.rng.random() < 0.7 else ctx.rng.randrange(ADDR_MASK)
        return konst(I32, a)
    k = ctx.rng.randrange(8) if ctx.rng.random() < 0.6 else 0
    e = binop("and", I32, gen_expr(ctx, I32, depth), konst(I32, ADDR_MASK))
    return binop("or", I32, e, konst(I32, k)) if k else e


def gen_load(ctx: Ctx, t: int, depth: int) -> Expr:
    op = ctx.rng.choice([o for o, (rt, n, s) in LOADS.items() if rt == t])
    _, n, signed = LOADS[op]
    offset = ctx.rng.choice([0, 0, 1, 4, 8, 13])
    a = gen_address(ctx, depth)

    def ev(st: State) -> int:
        addr = a.ev(st) + offset
        v = int.from_bytes(st.mem[addr:addr + n], "little")
        if signed and v >> (8 * n - 1):
            v -= 1 << (8 * n)
        return v & mask(t)
    return Expr(t, a.code + mem(op, offset), ev)


def gen_store(ctx: Ctx, depth: int) -> Stmt:
    op = ctx.rng.choice(list(STORES))
    t, n = STORES[op]
    offset = ctx.rng.choice([0, 0, 2, 4, 9])
    a, v = gen_address(ctx, depth), gen_expr(ctx, t, depth)

    def run(st: State) -> None:
        addr = a.ev(st) + offset
        x = v.ev(st)
        st.mem[addr:addr + n] = (x & ((1 << (8 * n)) - 1)).to_bytes(n, "little")
    return Stmt(a.code + v.code + mem(op, offset), run)


def gen_call(ctx: Ctx, t: int, depth: int) -> Expr:
    """A call of a later function, so that there is no recursion; a quarter
    of them through the table."""
    cands = [i for i, fn in enumerate(ctx.fns) if fn.result == t and i > ctx.fidx]
    if not cands:
        return gen_const(ctx, t, depth)
    idx = ctx.rng.choice(cands)
    fn = ctx.fns[idx]
    args = [gen_expr(ctx, pt, depth) for pt in fn.params]
    target = i32_const(idx - 1) + call_indirect(fn.type_idx) if ctx.rng.random() < 0.25 else call(idx)

    def ev(st: State) -> int:
        return st.call(idx, [a.ev(st) for a in args])
    return Expr(t, b"".join(a.code for a in args) + target, ev)


def catch(depth: int, value: Optional[int], levels: int) -> Optional[int]:
    """What a block that is levels labels deep makes of a branch that
    reached it: the value if the branch ends here, else it goes on."""
    if depth < levels:
        return value
    raise Branch(depth - levels, value)


def gen_if_expr(ctx: Ctx, t: int, depth: int) -> Expr:
    c = gen_condition(ctx, depth)
    ctx.labels.append(("if", t))
    then, els = gen_body(ctx, t, depth), gen_body(ctx, t, depth)
    ctx.labels.pop()

    def ev(st: State) -> int:
        z = c.ev(st)
        try:
            return (then if z else els).ev(st)
        except Branch as b:
            v = catch(b.depth, b.value, 1)
            assert v is not None
            return v
    return Expr(t, c.code + if_(t) + then.code + ELSE + els.code + END, ev)


def gen_block_expr(ctx: Ctx, t: int, depth: int) -> Expr:
    ctx.labels.append(("block", t))
    body = gen_body(ctx, t, depth)
    ctx.labels.pop()

    def ev(st: State) -> int:
        try:
            return body.ev(st)
        except Branch as b:
            v = catch(b.depth, b.value, 1)
            assert v is not None
            return v
    return Expr(t, block(t) + body.code + END, ev)


def gen_br_table_expr(ctx: Ctx, t: int, depth: int) -> Expr:
    """block (result i32) block (result i32) v i br_table 0 1 0 end
    i32.const c i32.add end: index 1 leaves v, every other index v + c."""
    if t != I32:
        return gen_block_expr(ctx, t, depth)
    ctx.labels += [("block", I32), ("block", I32)]
    v, i = gen_expr(ctx, I32, depth), gen_expr(ctx, I32, depth)
    ctx.labels[-2:] = []
    c = ctx.rng.randrange(1, 100)

    def ev(st: State) -> int:
        try:
            x = v.ev(st)
            inner = i.ev(st) != 1
        except Branch as b:
            if b.depth >= 2:
                raise Branch(b.depth - 2, b.value)
            assert b.value is not None
            x, inner = b.value, b.depth == 0
        return (x + c) & M32 if inner else x
    return Expr(I32, block(I32) + block(I32) + v.code + i.code + br_table([0, 1], 0) + END
                + i32_const(c) + ADD + END, ev)


EXPRS: List[Tuple[Callable[[Ctx, int, int], Expr], float]] = [
    (gen_local_get, 0.18), (gen_const, 0.10), (gen_binop, 0.25), (gen_cmp_value, 0.05),
    (gen_unop, 0.04), (gen_convert, 0.06), (gen_select, 0.05), (gen_load, 0.08),
    (gen_tee, 0.06), (gen_call, 0.05), (gen_if_expr, 0.04), (gen_block_expr, 0.02),
    (gen_br_table_expr, 0.02)]


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


def gen_br(ctx: Ctx, depth: int, unconditional: bool = False) -> Stmt:
    """br_if n, or br n, to a block, an if, or the function, with the value
    the label takes. Never to a loop, so that every loop ends."""
    cands = [n for n, (kind, lt) in enumerate(reversed(ctx.labels)) if kind != "loop"]
    n = ctx.rng.choice(cands)
    _, lt = ctx.labels[len(ctx.labels) - 1 - n]
    v = gen_expr(ctx, lt, depth) if lt is not None else None
    if unconditional:
        def run(st: State) -> None:
            raise Branch(n, v.ev(st) if v is not None else None)
        return Stmt((v.code if v is not None else b"") + br(n), run)
    c = gen_condition(ctx, depth)

    def run_if(st: State) -> None:
        x = v.ev(st) if v is not None else None
        if c.ev(st):
            raise Branch(n, x)
    code = (v.code if v is not None else b"") + c.code + br_if(n) + (DROP if v is not None else b"")
    return Stmt(code, run_if)


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
    ctx.labels.append(("loop", None))
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
                raise Branch(b.depth - 1, b.value)
            st.locals[ctr] = (st.locals[ctr] + 1) & M32
            if st.locals[ctr] >= k:
                return
    code = i32_const(0) + local_set(ctr) + loop() + b"".join(s.code for s in stmts)
    code += local_get(ctr) + i32_const(1) + ADD + local_tee(ctr) + i32_const(k) + LT_U + br_if(0) + END
    return Stmt(code, run)


def gen_if_stmt(ctx: Ctx, depth: int) -> Stmt:
    c = gen_condition(ctx, depth)
    ctx.labels.append(("if", None))
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
            catch(b.depth, b.value, 1)
    return Stmt(c.code + if_() + then.code + (ELSE + els.code if els is not None else b"") + END, run)


def gen_block_stmt(ctx: Ctx, depth: int) -> Stmt:
    ctx.labels.append(("block", None))
    body = gen_body(ctx, None, depth)
    ctx.labels.pop()

    def run(st: State) -> None:
        try:
            body.ev(st)
        except Branch as b:
            catch(b.depth, b.value, 1)
    return Stmt(block() + body.code + END, run)


def gen_drop(ctx: Ctx, depth: int) -> Stmt:
    e = gen_expr(ctx, ctx.rng.choice([I32, I64]), depth)

    def run(st: State) -> None:
        e.ev(st)
    return Stmt(e.code + DROP, run)


def gen_stmt(ctx: Ctx, depth: int) -> Stmt:
    r = ctx.rng.random()
    if depth <= 0:
        # Only statements that nest nothing.
        if r < 0.5:
            return gen_set(ctx, 1)
        if r < 0.75:
            return gen_store(ctx, 1)
        if r < 0.9:
            return gen_br(ctx, 1)
        return gen_drop(ctx, 1)
    if r < 0.40:
        return gen_set(ctx, depth)
    if r < 0.55:
        return gen_store(ctx, depth)
    if r < 0.65:
        return gen_loop(ctx, depth)
    if r < 0.75:
        return gen_if_stmt(ctx, depth)
    if r < 0.82:
        return gen_block_stmt(ctx, depth)
    if r < 0.92:
        return gen_br(ctx, depth)
    return gen_drop(ctx, depth)


def checksum(fn: Func) -> Expr:
    """main's result: a fold of every local and of 18 memory words."""
    def low(i: int) -> Expr:
        return Expr(I32, local_get(i) + WRAP, lambda st: st.locals[i] & M32)

    def high(i: int) -> Expr:
        return Expr(I32, local_get(i) + i64_const(32) + SHR_U64 + WRAP, lambda st: st.locals[i] >> 32)

    def word(a: int) -> Expr:
        return Expr(I32, i32_const(a) + mem(I32_LOAD), lambda st: int.from_bytes(st.mem[a:a + 4], "little"))

    parts: List[Expr] = []
    for i, t in enumerate(fn.local_types):
        parts += [get(I32, i)] if t == I32 else [low(i), high(i)]
    parts += [word(a) for a in range(0, 0x400, 0x3C)]
    code = i32_const(0)
    for p in parts:
        code += i32_const(31) + b"\x6c" + p.code + ADD

    def ev(st: State) -> int:
        acc = 0
        for p in parts:
            acc = (acc * 31 + p.ev(st)) & M32
        return acc
    return Expr(I32, code, ev)


def build(seed: int) -> Tuple[List[Func], bytes]:
    """The four functions, with random bodies, and the data segment."""
    rng = random.Random(seed)
    fns = [Func(0, [], I32, [I32] * 7 + [I64] * 3 + [I32, I32]),
           Func(1, [I32, I64, I32, I32], I32, [I32, I64, I32, I32] + [I32] * 3 + [I64] * 2 + [I32, I32]),
           Func(2, [I64, I32], I64, [I64, I32] + [I32] * 2 + [I64] * 2 + [I32, I32]),
           Func(3, [I32, I32], I32, [I32, I32] + [I32] * 6 + [I64] + [I32, I32])]
    for idx, fn in enumerate(fns):
        ctx = Ctx(rng, fn, idx, fns)
        count = rng.randrange(8, 20) if idx == 0 else rng.randrange(3, 10)
        fn.stmts = [gen_stmt(ctx, 3) for _ in range(count)]
        fn.value = checksum(fn) if idx == 0 else gen_expr(ctx, fn.result, 3)
    return fns, bytes(rng.getrandbits(8) for _ in range(DATA_SIZE))


def finish(fns: List[Func], segment: bytes) -> Tuple[bytes, int]:
    """The module, and the result the model gives for it."""
    mod = module(
        types(([], [I32]), ([I32, I64, I32, I32], [I32]), ([I64, I32], [I64]), ([I32, I32], [I32])),
        funcs(*[fn.type_idx for fn in fns]),
        table(3),
        memory(1),
        exports(("main", 0, 0)),
        elems((0, [1, 2, 3])),
        code(*[(fn.local_types[len(fn.params):], fn.body().code) for fn in fns]),
        data((DATA, segment)))
    memory_ = bytearray(65536)
    memory_[DATA:DATA + DATA_SIZE] = segment
    return mod, State(fns, memory_).call(0, [])


def run(cmd: List[str]) -> None:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(" ".join(cmd) + "\n" + p.stdout + p.stderr)


def pipeline(mod: bytes, tmp: str, nompu: bool, name: str) -> Tuple[Optional[int], bool, str]:
    """Translates, joins, assembles, and runs the module. Returns R1, whether
    the program halted with HALT, and the emulator's output."""
    wasm_file = os.path.join(tmp, name + ".wasm")
    with open(wasm_file, "wb") as f:
        f.write(mod)
    asm = os.path.join(tmp, name + ".nasm")
    run([sys.executable, NICEWASM, *(["--no-mpu"] if nompu else []), "-o", asm, wasm_file])
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
    return r1, p.returncode == 0 and "Halted (HALT)" in p.stdout, p.stdout


def check(seed: int, tmp: str, nompu: bool) -> Optional[str]:
    """Runs one seed. Returns a description of the failure, or None."""
    fns, segment = build(seed)
    mod, expected = finish(fns, segment)
    try:
        r1, ok, output = pipeline(mod, tmp, nompu, f"fuzz{seed}")
    except RuntimeError as e:
        return f"seed {seed}: " + str(e).replace("\n", "\n  ")
    if ok and r1 == expected:
        return None
    got = "none" if r1 is None else f"{r1:#010x}"
    first = output.splitlines()[0] if output else ""
    return f"seed {seed}: expected {expected:#010x}, got {got}\n  {first}"


def reduce(seed: int, tmp: str, nompu: bool) -> None:
    """Removes statements while the mismatch persists, and writes the
    reduced module and its translation to the current directory."""
    fns, segment = build(seed)

    def mismatch() -> bool:
        mod, expected = finish(fns, segment)
        try:
            r1, ok, _ = pipeline(mod, tmp, nompu, "reduce")
        except RuntimeError:
            return True
        return not ok or r1 != expected
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
    r1, ok, _ = pipeline(mod, tmp, nompu, "reduce")
    with open(f"fuzz_{seed}.wasm", "wb") as f:
        f.write(mod)
    shutil.move(os.path.join(tmp, "reduce.nasm"), f"fuzz_{seed}.nasm")
    got = "none" if r1 is None else f"{r1:#010x}"
    print(f"reduced to {[len(fn.stmts) for fn in fns]} statements: expected {expected:#010x}, "
          f"got {got}, halted {'normally' if ok else 'abnormally'}; see fuzz_{seed}.wasm and fuzz_{seed}.nasm")


def main() -> None:
    args = sys.argv[1:]
    nompu = "--no-mpu" in args
    do_reduce = "--reduce" in args
    numbers = [a for a in args if not a.startswith("--")]
    if len(numbers) != 2 or any(a not in ("--no-mpu", "--reduce") for a in args if a.startswith("--")):
        sys.exit(__doc__.split("\n\n")[1])
    first, count = int(numbers[0]), int(numbers[1])
    with tempfile.TemporaryDirectory() as tmp:
        if do_reduce:
            reduce(first, tmp, nompu)
            return
        failures = []
        for seed in range(first, first + count):
            problem = check(seed, tmp, nompu)
            if problem is not None:
                failures.append(problem)
                print("FAIL " + problem)
    suffix = ", --no-mpu" if nompu else ""
    print(f"{'FAIL' if failures else 'PASS'} fuzz ({count} cases{suffix})")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
