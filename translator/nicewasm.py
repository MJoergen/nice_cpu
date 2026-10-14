#!/usr/bin/env python3
"""nicewasm - translates a WebAssembly module into NICE assembly.

Implements the WebAssembly mapping of doc/ISA.md section 9.4. The output is
one assembly file, to be joined with the start-up code, the program's other
files, and the runtime library as section 9.3 describes.

Usage: nicewasm.py [-o output.asm] [--no-bounds-checks] input.wasm

This is a first version: it supports control flow, memory accesses, and
some integer instructions, and only the i32 and i64 types. README.md lists
what it supports. Anything else is rejected with an error, never
translated wrongly.

Each function keeps its locals and its wasm operand stack in its frame on
the NICE stack, addressed from FP (R12). An i32 takes one word and an i64
two, low word first. The operand stack holds the type of each value, so
every value has a fixed place in the frame, and every instruction is a few
NICE instructions on frame words.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple, Union

I32, I64, F32, F64 = 0x7F, 0x7E, 0x7D, 0x7C
TYPE_NAMES = {I32: "i32", I64: "i64", F32: "f32", F64: "f64", 0x7B: "v128",
              0x70: "funcref", 0x6F: "externref"}

SIZES = {I32: 1, I64: 2}  # words per value of each supported type

WORDS_PER_PAGE = 16384  # 65536 bytes, four to a word
ZERO_UNROLL = 16        # words cleared per pass of ___wasm_start's loops

# Section ids in the order a module must give them. Custom sections (0) may
# come anywhere.
SECTION_ORDER = [1, 2, 3, 4, 5, 13, 6, 7, 8, 9, 12, 10, 11]

C_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
PRINTABLE = re.compile(r"[ -~]*\Z")  # text that may go in a comment

# Opcode names, for comments in the output and for error messages.
OPCODES: Dict[int, str] = {
    0x00: "unreachable", 0x01: "nop", 0x02: "block", 0x03: "loop", 0x04: "if",
    0x05: "else", 0x0B: "end", 0x0C: "br", 0x0D: "br_if", 0x0E: "br_table",
    0x0F: "return", 0x10: "call", 0x11: "call_indirect", 0x12: "return_call",
    0x13: "return_call_indirect", 0x1A: "drop", 0x1B: "select", 0x1C: "select",
    0x20: "local.get", 0x21: "local.set", 0x22: "local.tee",
    0x23: "global.get", 0x24: "global.set", 0x25: "table.get", 0x26: "table.set",
    0xD0: "ref.null", 0xD1: "ref.is_null", 0xD2: "ref.func",
}
for _first, _names in [
    (0x28, "i32.load i64.load f32.load f64.load i32.load8_s i32.load8_u"
           " i32.load16_s i32.load16_u i64.load8_s i64.load8_u i64.load16_s"
           " i64.load16_u i64.load32_s i64.load32_u i32.store i64.store"
           " f32.store f64.store i32.store8 i32.store16 i64.store8 i64.store16"
           " i64.store32 memory.size memory.grow i32.const i64.const f32.const"
           " f64.const"
           " i32.eqz i32.eq i32.ne i32.lt_s i32.lt_u i32.gt_s i32.gt_u i32.le_s"
           " i32.le_u i32.ge_s i32.ge_u"
           " i64.eqz i64.eq i64.ne i64.lt_s i64.lt_u i64.gt_s i64.gt_u i64.le_s"
           " i64.le_u i64.ge_s i64.ge_u"
           " f32.eq f32.ne f32.lt f32.gt f32.le f32.ge"
           " f64.eq f64.ne f64.lt f64.gt f64.le f64.ge"
           " i32.clz i32.ctz i32.popcnt i32.add i32.sub i32.mul i32.div_s"
           " i32.div_u i32.rem_s i32.rem_u i32.and i32.or i32.xor i32.shl"
           " i32.shr_s i32.shr_u i32.rotl i32.rotr"
           " i64.clz i64.ctz i64.popcnt i64.add i64.sub i64.mul i64.div_s"
           " i64.div_u i64.rem_s i64.rem_u i64.and i64.or i64.xor i64.shl"
           " i64.shr_s i64.shr_u i64.rotl i64.rotr"
           " f32.abs f32.neg f32.ceil f32.floor f32.trunc f32.nearest f32.sqrt"
           " f32.add f32.sub f32.mul f32.div f32.min f32.max f32.copysign"
           " f64.abs f64.neg f64.ceil f64.floor f64.trunc f64.nearest f64.sqrt"
           " f64.add f64.sub f64.mul f64.div f64.min f64.max f64.copysign"
           " i32.wrap_i64 i32.trunc_f32_s i32.trunc_f32_u i32.trunc_f64_s"
           " i32.trunc_f64_u i64.extend_i32_s i64.extend_i32_u i64.trunc_f32_s"
           " i64.trunc_f32_u i64.trunc_f64_s i64.trunc_f64_u f32.convert_i32_s"
           " f32.convert_i32_u f32.convert_i64_s f32.convert_i64_u"
           " f32.demote_f64 f64.convert_i32_s f64.convert_i32_u"
           " f64.convert_i64_s f64.convert_i64_u f64.promote_f32"
           " i32.reinterpret_f32 i64.reinterpret_f64 f32.reinterpret_i32"
           " f64.reinterpret_i64 i32.extend8_s i32.extend16_s i64.extend8_s"
           " i64.extend16_s i64.extend32_s"),
]:
    for _i, _name in enumerate(_names.split()):
        OPCODES[_first + _i] = _name

# The instructions after the 0xFC prefix, by their second opcode.
FC_OPCODES = dict(enumerate(
    "i32.trunc_sat_f32_s i32.trunc_sat_f32_u i32.trunc_sat_f64_s"
    " i32.trunc_sat_f64_u i64.trunc_sat_f32_s i64.trunc_sat_f32_u"
    " i64.trunc_sat_f64_s i64.trunc_sat_f64_u memory.init data.drop memory.copy"
    " memory.fill table.init elem.drop table.copy table.grow table.size"
    " table.fill".split()))

# The i32 operations that are one NICE instruction: wasm opcode -> mnemonic.
ALU_OPS = {0x6A: "ADD", 0x6B: "SUB", 0x71: "AND", 0x72: "OR", 0x73: "XOR"}

# The same for i64, with the mnemonics for the low and the high word. The
# carry or borrow passes from the low word to the high word (§5.1).
ALU64_OPS = {0x7C: ("ADD[M]", "ADD[C]"), 0x7D: ("SUB[M]", "SUB[C]"),
             0x83: ("AND", "AND"), 0x84: ("OR", "OR"), 0x85: ("XOR", "XOR")}

# The i32 comparisons, from eq to ge_u: wasm opcode -> (swap the operands,
# test). gt and le are lt and ge with the operands swapped. The i64
# comparisons are the same, 11 opcodes further on.
CMP_OPS = {0x46: (False, "eq"), 0x47: (False, "ne"), 0x48: (False, "lt_s"),
           0x49: (False, "lt_u"), 0x4A: (True, "lt_s"), 0x4B: (True, "lt_u"),
           0x4C: (True, "ge_s"), 0x4D: (True, "ge_u"), 0x4E: (False, "ge_s"),
           0x4F: (False, "ge_u")}
CMP64_OPS = {op + 11: v for op, v in CMP_OPS.items()}

# The shifts and rotates: wasm opcode -> operation. The i64 ones are 18
# opcodes further on.
SHIFT_OPS = {0x74: "shl", 0x75: "shr_s", 0x76: "shr_u", 0x77: "rotl", 0x78: "rotr"}
SHIFT64_OPS = {op + 18: v for op, v in SHIFT_OPS.items()}

# Divisions and remainders: wasm opcode -> (type, operation).
DIV_OPS = {0x6D: (I32, "div_s"), 0x6E: (I32, "div_u"), 0x6F: (I32, "rem_s"),
           0x70: (I32, "rem_u"), 0x7F: (I64, "div_s"), 0x80: (I64, "div_u"),
           0x81: (I64, "rem_s"), 0x82: (I64, "rem_u")}

# Operations that are a call to the runtime library (§9.3): wasm opcode ->
# (routine, its type).
LIB_OPS = {0x67: ("__clz", ([I32], [I32])), 0x68: ("__ctz", ([I32], [I32])),
           0x69: ("__popcnt", ([I32], [I32])), 0x6C: ("__mul", ([I32, I32], [I32])),
           0x79: ("__clz64", ([I64], [I64])), 0x7A: ("__ctz64", ([I64], [I64])),
           0x7B: ("__popcnt64", ([I64], [I64])), 0x7E: ("__mul64", ([I64, I64], [I64]))}

# The sign extensions: wasm opcode -> (type, bits extended from).
EXTEND_OPS = {0xC0: (I32, 8), 0xC1: (I32, 16), 0xC2: (I64, 8), 0xC3: (I64, 16),
              0xC4: (I64, 32)}

BLOCK, LOOP, IF = 0x02, 0x03, 0x04

# The loads: wasm opcode -> (type, bytes, signed). And the stores: wasm
# opcode -> (type, bytes).
LOADS = {0x28: (I32, 4, False), 0x29: (I64, 8, False), 0x2C: (I32, 1, True),
         0x2D: (I32, 1, False), 0x2E: (I32, 2, True), 0x2F: (I32, 2, False),
         0x30: (I64, 1, True), 0x31: (I64, 1, False), 0x32: (I64, 2, True),
         0x33: (I64, 2, False), 0x34: (I64, 4, True), 0x35: (I64, 4, False)}
STORES = {0x36: (I32, 4), 0x37: (I64, 8), 0x3A: (I32, 1), 0x3B: (I32, 2),
          0x3C: (I64, 1), 0x3D: (I64, 2), 0x3E: (I64, 4)}


class WasmError(Exception):
    def __init__(self, msg: str, offset: Optional[int] = None) -> None:
        super().__init__(msg)
        self.offset = offset


@dataclass
class FuncType:
    params: List[int]
    results: List[int]


# The imports from the module nice and their types (§9.4). A call to one
# is replaced by the access it performs.
NICE_TYPES = {"peek": FuncType([I32], [I32]), "poke": FuncType([I32, I32], [])}


@dataclass
class Frame:
    """A block, loop, or if, or the function itself, on the control stack."""
    op: int                           # BLOCK, LOOP, IF, or 0 for the function
    ft: FuncType                      # its parameters and results
    height: int                       # values on the operand stack below the parameters
    words: int                        # the words they take
    label: str                        # where a branch to it goes
    else_label: Optional[str] = None  # an if's false branch, until its else

    def label_types(self) -> List[int]:
        """The values that a branch to it takes."""
        return self.ft.params if self.op == LOOP else self.ft.results


@dataclass
class Import:
    module: str
    name: str
    type_idx: int


@dataclass
class Global:
    type: int
    mutable: bool
    init: int


@dataclass
class Data:
    """An active data segment."""
    offset: int         # byte address in the memory
    data: bytes
    at: int             # offset of the segment in the file


@dataclass
class Elem:
    """An active element segment of table 0."""
    offset: int                     # first entry
    funcs: List[Optional[int]]      # function index of each entry, or None for ref.null
    at: int                         # offset of the segment in the file


@dataclass
class Code:
    locals: List[int]   # the declared locals, not the parameters
    start: int          # offset of the first instruction in the file
    end: int            # offset after the function's final end


@dataclass
class Module:
    types: List[FuncType] = field(default_factory=list)
    imports: List[Import] = field(default_factory=list)
    funcs: List[int] = field(default_factory=list)     # type index of each defined function
    memory_pages: Optional[int] = None                 # initial size, if there is a memory
    globals: List[Global] = field(default_factory=list)
    exports: List[Tuple[str, int, int]] = field(default_factory=list)  # name, kind, index
    start: Optional[int] = None
    codes: List[Code] = field(default_factory=list)
    data: List[Data] = field(default_factory=list)
    table_size: Optional[int] = None                   # initial size, if there is a table
    elems: List[Elem] = field(default_factory=list)
    data_count: Optional[int] = None                   # from the data count section
    names: Dict[int, str] = field(default_factory=dict)  # function names from the name section


class Reader:
    """Reads the binary format: bytes, LEB128 numbers, and names."""

    def __init__(self, data: bytes, pos: int = 0, end: Optional[int] = None) -> None:
        self.data = data
        self.pos = pos
        self.end = len(data) if end is None else end

    def at_end(self) -> bool:
        return self.pos >= self.end

    def byte(self) -> int:
        if self.pos >= self.end:
            raise WasmError("unexpected end of data", self.pos)
        b = self.data[self.pos]
        self.pos += 1
        return b

    def bytes(self, n: int) -> bytes:
        if n > self.end - self.pos:
            raise WasmError("unexpected end of data", self.pos)
        b = self.data[self.pos:self.pos + n]
        self.pos += n
        return b

    def leb(self, bits: int, signed: bool) -> int:
        start = self.pos
        result = shift = 0
        while True:
            b = self.byte()
            result |= (b & 0x7F) << shift
            shift += 7
            if b < 0x80:
                break
            if shift >= bits:
                raise WasmError("integer too long", start)
        if signed and b & 0x40:
            result -= 1 << shift
        lo, hi = (-(1 << (bits - 1)), 1 << (bits - 1)) if signed else (0, 1 << bits)
        if not lo <= result < hi:
            raise WasmError("integer too large", start)
        return result

    def u32(self) -> int:
        return self.leb(32, False)

    def s32(self) -> int:
        return self.leb(32, True)

    def name(self) -> str:
        start = self.pos
        try:
            return self.bytes(self.u32()).decode("utf-8")
        except UnicodeDecodeError:
            raise WasmError("name is not valid UTF-8", start) from None


def type_name(t: int) -> str:
    return TYPE_NAMES.get(t, f"0x{t:02x}")


def check_types(types: List[int], what: str, offset: int) -> None:
    for t in types:
        if t not in SIZES:
            raise WasmError(f"{what} has type {type_name(t)}; only i32 and i64 are supported yet",
                            offset)


def words(value: int, t: int) -> List[str]:
    """A constant of type t as its words, low word first, each a signed
    32-bit number."""
    out = []
    for i in range(SIZES[t]):
        w = (value >> (32 * i)) & 0xFFFFFFFF
        out.append(str(w - (1 << 32) if w & 0x80000000 else w))
    return out


def assign_args(params: List[int]) -> Tuple[List[Tuple[bool, int]], int]:
    """Where §9.3 puts each argument of a function that is not variadic:
    (True, first register) or (False, first stack word). Also returns the
    number of stack words."""
    locs: List[Tuple[bool, int]] = []
    reg = 1
    stack = 0
    for t in params:
        n = SIZES[t]
        if stack == 0 and reg + n - 1 <= 4:
            locs.append((True, reg))
            reg += n
        else:
            locs.append((False, stack))
            stack += n
    return locs, stack


def printable(text: str) -> Optional[str]:
    """text, if it may go in a comment. A newline in a name from the module
    would otherwise end the comment and make the rest of the name code."""
    return text if PRINTABLE.match(text) else None


def parse(data: bytes) -> Module:
    r = Reader(data)
    if r.bytes(4) != b"\0asm":
        raise WasmError("not a wasm module (no '\\0asm' at the start)", 0)
    if r.bytes(4) != b"\1\0\0\0":
        raise WasmError("unsupported wasm version (only version 1 is supported)", 4)
    m = Module()
    last_rank = -1
    while not r.at_end():
        sec_start = r.pos
        sec_id = r.byte()
        size = r.u32()
        if size > r.end - r.pos:
            raise WasmError(f"section {sec_id} runs past the end of the file", sec_start)
        s = Reader(data, r.pos, r.pos + size)
        r.pos += size
        if sec_id != 0:
            if sec_id not in SECTION_ORDER:
                raise WasmError(f"unknown section {sec_id}", sec_start)
            rank = SECTION_ORDER.index(sec_id)
            if rank <= last_rank:
                raise WasmError(f"section {sec_id} is out of order or repeated", sec_start)
            last_rank = rank
        parse_section(m, sec_id, s, sec_start)
        if sec_id != 0 and not s.at_end():
            raise WasmError(f"section {sec_id} has {s.end - s.pos} bytes left over", s.pos)
    if len(m.codes) != len(m.funcs):
        raise WasmError(f"the function and code sections differ in length"
                        f" ({len(m.funcs)} and {len(m.codes)})")
    return m


def parse_limits(s: Reader, what: str) -> int:
    """Reads limits and returns the minimum. The maximum is not used."""
    at = s.pos
    flags = s.byte()
    if flags not in (0, 1):
        raise WasmError(f"a shared or 64-bit {what} is not supported", at)
    minimum = s.u32()
    if flags == 1:
        s.u32()
    return minimum


def parse_section(m: Module, sec_id: int, s: Reader, sec_start: int) -> None:
    if sec_id == 0:
        parse_custom(m, s)
    elif sec_id == 1:
        for _ in range(s.u32()):
            at = s.pos
            if s.byte() != 0x60:
                raise WasmError("expected a function type (0x60)", at)
            params = [s.byte() for _ in range(s.u32())]
            results = [s.byte() for _ in range(s.u32())]
            m.types.append(FuncType(params, results))
    elif sec_id == 2:
        for _ in range(s.u32()):
            at = s.pos
            module, name = s.name(), s.name()
            kind = s.byte()
            what = f"import {module}.{name}"
            if kind != 0:
                kinds = {1: "table", 2: "memory", 3: "global", 4: "tag"}
                raise WasmError(f"{what} is a {kinds.get(kind, 'thing')}; only functions"
                                " may be imported", at)
            type_idx = func_type_idx(m, s)
            if module == "nice":
                if name not in NICE_TYPES:
                    raise WasmError(f"{what}: the module 'nice' has only peek and poke", at)
                if m.types[type_idx] != NICE_TYPES[name]:
                    want = NICE_TYPES[name]
                    raise WasmError(f"{what} must have the type ({', '.join(map(type_name, want.params))})"
                                    f" -> ({', '.join(map(type_name, want.results))})", at)
                m.imports.append(Import(module, name, type_idx))
                continue
            if module != "env":
                raise WasmError(f"{what}: functions may be imported only from 'env' and 'nice'", at)
            if not C_IDENT.match(name):
                raise WasmError(f"{what}: the name is not a C identifier, so it has no label", at)
            ft = m.types[type_idx]
            check_types(ft.params + ft.results, what, at)
            if len(ft.results) > 1:
                raise WasmError(f"{what}: more than one result is not supported yet", at)
            m.imports.append(Import(module, name, type_idx))
    elif sec_id == 3:
        for _ in range(s.u32()):
            m.funcs.append(func_type_idx(m, s))
    elif sec_id == 4:
        count = s.u32()
        if count > 1:
            raise WasmError("a module may have only one table", sec_start)
        if count == 1:
            at = s.pos
            t = s.byte()
            if t != 0x70:
                raise WasmError(f"table 0 holds {type_name(t)}; only funcref is supported", at)
            m.table_size = parse_limits(s, "table")
    elif sec_id == 5:
        count = s.u32()
        if count > 1:
            raise WasmError("a module may have only one memory", sec_start)
        if count == 1:
            m.memory_pages = parse_limits(s, "memory")
    elif sec_id == 6:
        for i in range(s.u32()):
            at = s.pos
            t = s.byte()
            check_types([t], f"global {i}", at)
            mutable = s.byte() == 1
            at = s.pos
            # The constant instruction of the type, then end. extended-const
            # allows expressions, which are not supported.
            const, bits = (0x41, 32) if t == I32 else (0x42, 64)
            what = f"global {i}: the initial value must be an {type_name(t)}.const"
            if s.byte() != const:
                raise WasmError(what, at)
            init = s.leb(bits, True)
            if s.byte() != 0x0B:
                raise WasmError(what, at)
            m.globals.append(Global(t, mutable, init))
    elif sec_id == 7:
        for _ in range(s.u32()):
            name = s.name()
            kind = s.byte()
            m.exports.append((name, kind, s.u32()))
    elif sec_id == 8:
        m.start = s.u32()
    elif sec_id == 9:
        for i in range(s.u32()):
            parse_elem(m, s, i)
    elif sec_id == 10:
        for _ in range(s.u32()):
            size = s.u32()
            body = Reader(s.data, s.pos, s.pos + size)
            if size > s.end - s.pos:
                raise WasmError("function body runs past the end of the section", s.pos)
            s.pos += size
            local_types: List[int] = []
            for _ in range(body.u32()):
                at = body.pos
                n = body.u32()
                if len(local_types) + n > 50000:
                    raise WasmError("too many locals", at)
                local_types += [body.byte()] * n
            m.codes.append(Code(local_types, body.pos, body.end))
    elif sec_id == 11:
        count = s.u32()
        if m.data_count is not None and count != m.data_count:
            raise WasmError(f"the data count section says {m.data_count} segments, but there"
                            f" are {count}", sec_start)
        for i in range(count):
            at = s.pos
            flags = s.u32()
            if flags == 1:
                raise WasmError(f"data segment {i} is passive; memory.init is not supported yet",
                                at)
            if flags == 2:
                mem_at = s.pos
                mem = s.u32()
                if mem != 0:
                    raise WasmError(f"data segment {i}: memory {mem} does not exist", mem_at)
            elif flags != 0:
                raise WasmError(f"data segment {i} has unknown flags {flags}", at)
            # The offset is an i32.const, then end. extended-const allows
            # expressions, which are not supported.
            off_at = s.pos
            what = f"data segment {i}: the offset must be an i32.const"
            if s.byte() != 0x41:
                raise WasmError(what, off_at)
            offset = s.s32() & 0xFFFFFFFF
            if s.byte() != 0x0B:
                raise WasmError(what, off_at)
            m.data.append(Data(offset, s.bytes(s.u32()), at))
    elif sec_id == 12:
        m.data_count = s.u32()
    elif sec_id == 13:
        raise WasmError("exception tags are not supported", sec_start)


def parse_elem(m: Module, s: Reader, i: int) -> None:
    """Reads element segment i. Bit 0 of its flags is set for a passive or
    declarative segment, bit 1 for an explicit table index or element
    kind, and bit 2 for elements that are expressions, not function
    indices."""
    at = s.pos
    flags = s.u32()
    if flags > 7:
        raise WasmError(f"element segment {i} has unknown flags {flags}", at)
    active = not flags & 1
    if flags in (1, 5):
        raise WasmError(f"element segment {i} is passive; table.init is not supported yet", at)
    offset = 0
    if active:
        if flags & 2:
            t_at = s.pos
            table = s.u32()
            if table != 0:
                raise WasmError(f"element segment {i}: table {table} does not exist", t_at)
        # The offset is an i32.const, then end.
        off_at = s.pos
        what = f"element segment {i}: the offset must be an i32.const"
        if s.byte() != 0x41:
            raise WasmError(what, off_at)
        offset = s.s32() & 0xFFFFFFFF
        if s.byte() != 0x0B:
            raise WasmError(what, off_at)
    if flags & 3:
        # The element kind: 0 (functions) for indices, funcref for expressions.
        k_at = s.pos
        if s.byte() != (0x70 if flags & 4 else 0x00):
            raise WasmError(f"element segment {i}: only functions are supported", k_at)
    funcs: List[Optional[int]] = []
    for _ in range(s.u32()):
        if not flags & 4:
            funcs.append(s.u32())
            continue
        e_at = s.pos
        op = s.byte()
        if op == 0xD2:      # ref.func
            funcs.append(s.u32())
        elif op == 0xD0 and s.byte() == 0x70:  # ref.null funcref
            funcs.append(None)
        else:
            raise WasmError(f"element segment {i}: an element must be ref.func or ref.null", e_at)
        if s.byte() != 0x0B:
            raise WasmError(f"element segment {i}: an element must be ref.func or ref.null", e_at)
    # A declarative segment only declares functions for ref.func, which
    # is not supported, so it has no effect.
    if active:
        m.elems.append(Elem(offset, funcs, at))


def func_type_idx(m: Module, s: Reader) -> int:
    at = s.pos
    idx = s.u32()
    if idx >= len(m.types):
        raise WasmError(f"type index {idx} is out of range", at)
    return idx


def parse_custom(m: Module, s: Reader) -> None:
    """Reads the function names from the name section, for comments. A
    custom section must not make a module invalid, so errors are ignored."""
    try:
        if s.name() != "name":
            return
        while not s.at_end():
            sub_id = s.byte()
            size = s.u32()
            sub = Reader(s.data, s.pos, s.pos + size)
            s.pos = sub.end
            if sub_id == 1:
                for _ in range(sub.u32()):
                    idx = sub.u32()
                    m.names[idx] = sub.name()
    except WasmError:
        pass


def operand(offset: int) -> str:
    """The frame word at FP + offset."""
    return f"@{offset}[R12]"


def instr(mnemonic: str, *operands: str) -> str:
    return f"        {mnemonic + ' ':<8}{', '.join(operands)}".rstrip()


def byte_copy() -> List[str]:
    """Copies the byte at byte address R2 to byte address R1. Uses R4-R6."""
    mem = "@___wasm_memory"
    return [instr("SHR", "R4", "R2", "2"),
            instr("AND", "R5", "R2", "3"),
            instr("SHL", "R5", "R5", "3"),
            instr("SHR", "R4", f"{mem}[R4]", "R5"),
            instr("AND", "R4", "R4", "0xFF"),            # the byte
            instr("SHR", "R5", "R1", "2"),
            instr("AND", "R6", "R1", "3"),
            instr("SHL", "R6", "R6", "3"),
            instr("SHL", "R4", "R4", "R6"),
            instr("SHL", "R6", "0xFF", "R6"),            # its place in the word
            instr("IAND", "R6", "R6", f"{mem}[R5]"),
            instr("OR", f"{mem}[R5]", "R6", "R4")]


# Functions that memory.fill and memory.copy call, emitted once each if a
# function uses them. They take byte addresses and a byte count, which the
# caller has checked. Each byte or whole word is a pass of a loop: a word
# when the addresses are at a multiple of 4 and 4 or more bytes are left.
HELPERS: Dict[str, List[str]] = {
    "W.fill": [
        "; W.fill: sets the R3 bytes from byte address R1 to the low byte of R2.",
        "W.fill",
        instr("AND", "R2", "R2", "0xFF"),
        instr("SHL", "R4", "R2", "8"),
        instr("OR", "R2", "R2", "R4"),
        instr("SHL", "R4", "R2", "16"),
        instr("OR", "R2", "R2", "R4"),                   # the byte in all four places
        "W.fill.loop",
        instr("MOVE[M]", "R0", "R3"),
        instr("?Z MOVE", "R15", "@R13++"),
        instr("AND[M]", "R0", "R1", "3"),
        instr("?!Z MOVE", "R15", "W.fill.byte"),
        instr("SUB[M]", "R0", "R3", "4"),
        instr("?C MOVE", "R15", "W.fill.byte"),
        instr("SHR", "R4", "R1", "2"),
        instr("MOVE", "@___wasm_memory[R4]", "R2"),
        instr("ADD", "R1", "R1", "4"),
        instr("SUB", "R3", "R3", "4"),
        instr("MOVE", "R15", "W.fill.loop"),
        "W.fill.byte",
        instr("SHR", "R4", "R1", "2"),
        instr("AND", "R5", "R1", "3"),
        instr("SHL", "R5", "R5", "3"),
        instr("SHL", "R5", "0xFF", "R5"),                # the byte's place in the word
        instr("IAND", "R6", "R5", "@___wasm_memory[R4]"),
        instr("AND", "R5", "R5", "R2"),
        instr("OR", "@___wasm_memory[R4]", "R6", "R5"),
        instr("ADD", "R1", "R1", "1"),
        instr("SUB", "R3", "R3", "1"),
        instr("MOVE", "R15", "W.fill.loop"),
    ],
    "W.copy": [
        "; W.copy: copies the R3 bytes from byte address R2 to byte address R1.",
        "; The ranges may overlap, so it copies from the end down if R2 < R1.",
        "W.copy",
        instr("SUB[M]", "R0", "R2", "R1"),
        instr("?C MOVE", "R15", "W.copy.back"),
        "W.copy.loop",
        instr("MOVE[M]", "R0", "R3"),
        instr("?Z MOVE", "R15", "@R13++"),
        instr("XOR", "R4", "R1", "R2"),
        instr("OR", "R4", "R4", "R1"),
        instr("AND[M]", "R0", "R4", "3"),                # Z = both at a multiple of 4
        instr("?!Z MOVE", "R15", "W.copy.byte"),
        instr("SUB[M]", "R0", "R3", "4"),
        instr("?C MOVE", "R15", "W.copy.byte"),
        instr("SHR", "R4", "R2", "2"),
        instr("SHR", "R5", "R1", "2"),
        instr("MOVE", "@___wasm_memory[R5]", "@___wasm_memory[R4]"),
        instr("ADD", "R1", "R1", "4"),
        instr("ADD", "R2", "R2", "4"),
        instr("SUB", "R3", "R3", "4"),
        instr("MOVE", "R15", "W.copy.loop"),
        "W.copy.byte",
        *byte_copy(),
        instr("ADD", "R1", "R1", "1"),
        instr("ADD", "R2", "R2", "1"),
        instr("SUB", "R3", "R3", "1"),
        instr("MOVE", "R15", "W.copy.loop"),
        "W.copy.back",
        instr("ADD", "R1", "R1", "R3"),                  # one past each range
        instr("ADD", "R2", "R2", "R3"),
        "W.copy.bloop",
        instr("MOVE[M]", "R0", "R3"),
        instr("?Z MOVE", "R15", "@R13++"),
        instr("XOR", "R4", "R1", "R2"),
        instr("OR", "R4", "R4", "R1"),
        instr("AND[M]", "R0", "R4", "3"),
        instr("?!Z MOVE", "R15", "W.copy.bbyte"),
        instr("SUB[M]", "R0", "R3", "4"),
        instr("?C MOVE", "R15", "W.copy.bbyte"),
        instr("SUB", "R1", "R1", "4"),
        instr("SUB", "R2", "R2", "4"),
        instr("SUB", "R3", "R3", "4"),
        instr("SHR", "R4", "R2", "2"),
        instr("SHR", "R5", "R1", "2"),
        instr("MOVE", "@___wasm_memory[R5]", "@___wasm_memory[R4]"),
        instr("MOVE", "R15", "W.copy.bloop"),
        "W.copy.bbyte",
        instr("SUB", "R1", "R1", "1"),
        instr("SUB", "R2", "R2", "1"),
        instr("SUB", "R3", "R3", "1"),
        *byte_copy(),
        instr("MOVE", "R15", "W.copy.bloop"),
    ],
}


class Translator:
    def __init__(self, m: Module, data: bytes, checks: bool = True) -> None:
        self.m = m
        self.data = data
        self.checks = checks  # bounds checks on memory accesses
        self.helpers: set[str] = set()  # the HELPERS that functions call
        self.labels: Dict[int, List[str]] = {}         # function index -> export labels
        self.global_labels: Dict[int, List[str]] = {}  # global index -> export labels
        self.ctors: Optional[int] = None
        n_imports = len(m.imports)
        seen = set()
        for name, kind, idx in m.exports:
            if name in seen:
                raise WasmError(f"export {name}: the name is exported twice")
            seen.add(name)
            if kind == 0:
                if idx >= n_imports + len(m.funcs):
                    raise WasmError(f"export {name}: function {idx} does not exist")
                if idx < n_imports:
                    raise WasmError(f"export {name}: exporting an imported function is not supported")
                if name == "__wasm_call_ctors":
                    self.ctors = idx
            elif kind == 3 and idx >= len(m.globals):
                raise WasmError(f"export {name}: global {idx} does not exist")
            # Names that start with _ are reserved for the runtime library.
            if kind in (0, 3) and C_IDENT.match(name) and not name.startswith("_"):
                (self.labels if kind == 0 else self.global_labels).setdefault(idx, []).append(f"_{name}")
        if m.start is not None:
            if m.start >= n_imports + len(m.funcs):
                raise WasmError(f"start function {m.start} does not exist")
            if self.func_type(m.start).params or self.func_type(m.start).results:
                raise WasmError("the start function must have no parameters and no results")
        if self.ctors is not None:
            if self.func_type(self.ctors).params or self.func_type(self.ctors).results:
                raise WasmError("__wasm_call_ctors must have no parameters and no results")

    def func_type(self, idx: int) -> FuncType:
        n_imports = len(self.m.imports)
        if idx < n_imports:
            return self.m.types[self.m.imports[idx].type_idx]
        return self.m.types[self.m.funcs[idx - n_imports]]

    def func_label(self, idx: int) -> str:
        if idx < len(self.m.imports):
            return f"_{self.m.imports[idx].name}"
        return f"W.f{idx}"

    def run(self, source: str) -> List[str]:
        source = "".join(c if PRINTABLE.match(c) else "?" for c in source)
        out = [f"; Translated from {source} by nicewasm (doc/ISA.md §9.4).", ""]
        out.append("; Sets the memory to 0, then calls the start function and")
        out.append("; __wasm_call_ctors, if the module has them.")
        out.append("___wasm_start")
        # The words that data segments set are in the program image. The
        # rest of the memory is reserved with .RES, so it is not, and is
        # set to 0 here. Each pass of a loop clears ZERO_UNROLL words.
        runs = self.memory_runs()
        gaps = 0
        for start, values in runs:
            if isinstance(values, list):
                continue
            out.append(instr("MOVE", "R5", "___wasm_memory" + (f"+{start}" if start else "")))
            if values >= ZERO_UNROLL:
                out.append(instr("MOVE", "R6", str(values // ZERO_UNROLL)))
                out.append(f"W.zero{gaps}")
                out += [instr("MOVE", "@R5++", "R0")] * ZERO_UNROLL
                out.append(instr("DEC[M]", "R6", "R6"))
                out.append(f"        ?!Z MOVE R15, W.zero{gaps}")
                gaps += 1
            out += [instr("MOVE", "@R5++", "R0")] * (values % ZERO_UNROLL)
        for idx in (self.m.start, self.ctors):
            if idx is not None:
                out.append(instr("ADD", "@--R13", "2", "R15"))
                out.append(instr("MOVE", "R15", self.func_label(idx)))
        out.append(instr("MOVE", "R15", "@R13++"))
        n_imports = len(self.m.imports)
        for i, code in enumerate(self.m.codes):
            out.append("")
            out += FunctionTranslator(self, n_imports + i, code).run()
        for name in sorted(self.helpers):
            out += [""] + HELPERS[name]
        out += self.table()
        if self.m.globals:
            out += ["", "; Globals"]
            for i, g in enumerate(self.m.globals):
                out += self.global_labels.get(i, [])
                out.append(f"W.g{i}")
                out += [instr(".DAT", w) for w in words(g.init, g.type)]
        if self.m.memory_pages is not None:
            pages = self.m.memory_pages
            out += ["", f"; Linear memory: {pages} page{'' if pages == 1 else 's'}",
                    "___wasm_memory"]
            for start, values in runs:
                if isinstance(values, list):
                    last = start + len(values) - 1
                    where = f"word {start}" if last == start else f"words {start} to {last}"
                    out.append(f"        ; {where}: data segments")
                    for i in range(0, len(values), 8):
                        out.append(instr(".DAT", *(f"0x{w:08X}" for w in values[i:i + 8])))
                else:
                    out.append(instr(".RES", str(values)))
        return out

    def type_number(self, idx: int) -> int:
        """The number of a function type in the table: the index of the
        first type with the same parameters and results (§9.4)."""
        return self.m.types.index(self.m.types[idx])

    def table(self) -> List[str]:
        """Table 0, two words to an entry: the address of a function and
        the number of its type, or 0 and 0 for an empty entry (§9.4). A
        later element segment overwrites an earlier one, as in wasm."""
        if self.m.table_size is None:
            if self.m.elems:
                raise WasmError("element segment 0: the module has no table", self.m.elems[0].at)
            return []
        n_funcs = len(self.m.imports) + len(self.m.funcs)
        entries: List[Optional[int]] = [None] * self.m.table_size
        for i, seg in enumerate(self.m.elems):
            if seg.offset + len(seg.funcs) > self.m.table_size:
                raise WasmError(f"element segment {i} does not fit in the table", seg.at)
            for k, f in enumerate(seg.funcs):
                if f is not None and f >= n_funcs:
                    raise WasmError(f"element segment {i}: function {f} does not exist", seg.at)
                if f is not None and f < len(self.m.imports) and self.m.imports[f].module == "nice":
                    raise WasmError(f"element segment {i}: nice.{self.m.imports[f].name} has no"
                                    " address, so it cannot be in a table", seg.at)
                entries[seg.offset + k] = f
        size = self.m.table_size
        out = ["", f"; Table 0: {size} entr{'y' if size == 1 else 'ies'}, each a function's"
               " address and its type number", "W.table"]
        for f in entries:
            if f is None:
                out.append(instr(".DAT", "0", "0"))
            else:
                n_imports = len(self.m.imports)
                type_idx = (self.m.imports[f].type_idx if f < n_imports
                            else self.m.funcs[f - n_imports])
                out.append(instr(".DAT", self.func_label(f), str(self.type_number(type_idx))))
        return out

    def memory_runs(self) -> List[Tuple[int, Union[int, List[int]]]]:
        """The memory in runs of words, in address order: (first word, the
        values of the words that data segments set) or (first word, the
        number of words that are 0). A word that a segment sets only part
        of is in the image, its other bytes 0. A later segment overwrites
        an earlier one, as in wasm."""
        if self.m.memory_pages is None:
            if self.m.data:
                raise WasmError("data segment 0: the module has no memory", self.m.data[0].at)
            return []
        size = self.m.memory_pages * WORDS_PER_PAGE * 4
        init: Dict[int, int] = {}
        for i, seg in enumerate(self.m.data):
            if seg.offset + len(seg.data) > size:
                raise WasmError(f"data segment {i} does not fit in the memory", seg.at)
            for k, b in enumerate(seg.data):
                addr = seg.offset + k
                shift = 8 * (addr % 4)
                w = init.get(addr // 4, 0)
                init[addr // 4] = (w & ~(0xFF << shift)) | (b << shift)
        runs: List[Tuple[int, Union[int, List[int]]]] = []
        w = 0
        for i in sorted(init):
            if i > w:
                runs.append((w, i - w))
            if runs and isinstance(runs[-1][1], list) and i == w:
                runs[-1][1].append(init[i])
            else:
                runs.append((i, [init[i]]))
            w = i + 1
        if size // 4 > w:
            runs.append((w, size // 4 - w))
        return runs


class FunctionTranslator:
    """Translates one function. Local i starts at the frame word FP +
    local[i]. The operand stack starts at FP - n_slots and grows down: a
    value whose first word is stack word w, and which takes n words, starts
    at FP - n_slots - w - n. A value's low word is at the lower address."""

    def __init__(self, t: Translator, idx: int, code: Code) -> None:
        self.t = t
        self.idx = idx
        self.code = code
        self.ftype = t.func_type(idx)
        what = f"function {idx}"
        check_types(self.ftype.params + self.ftype.results, what, code.start)
        check_types(code.locals, f"{what}: a local", code.start)
        if len(self.ftype.results) > 1:
            raise WasmError(f"{what}: more than one result is not supported yet", code.start)
        # Parameters in registers and declared locals get frame words below
        # FP. Parameters on the stack stay where the caller put them.
        self.local_types = self.ftype.params + code.locals
        self.args, _ = assign_args(self.ftype.params)
        self.local: List[int] = []
        self.n_slots = 0
        for i, lt in enumerate(self.local_types):
            if i < len(self.args) and not self.args[i][0]:
                self.local.append(2 + self.args[i][1])
            else:
                self.n_slots += SIZES[lt]
                self.local.append(-self.n_slots)
        self.stack: List[int] = []  # the type of each value on the operand stack
        self.words = 0              # the words they take
        self.max_words = 0
        self.n_traps = 0
        self.n_labels = 0
        self.body: List[str] = []
        self.stubs: List[str] = []  # code after the epilogue, out of the way
        self.ret_label = f"W.f{idx}.ret"
        self.ctrl = [Frame(0, self.ftype, 0, 0, self.ret_label)]

    def push(self, t: int) -> List[str]:
        """Pushes a value of type t and returns its words."""
        self.stack.append(t)
        self.words += SIZES[t]
        self.max_words = max(self.max_words, self.words)
        return self.top()

    def top(self) -> List[str]:
        """The words of the value on top of the operand stack."""
        n = SIZES[self.stack[-1]]
        start = -self.n_slots - self.words
        return [operand(start + i) for i in range(n)]

    def pop(self, types: List[Optional[int]], at: int, what: str) -> List[List[str]]:
        """Pops values of the given types, the last one from the top, and
        returns their words. None accepts any type. Only the values pushed
        inside the innermost block can be popped."""
        if len(self.stack) - self.ctrl[-1].height < len(types):
            raise WasmError(f"function {self.idx}: operand stack underflow", at)
        out: List[List[str]] = []
        for want in reversed(types):
            got = self.stack[-1]
            if want is not None and got != want:
                raise WasmError(f"function {self.idx}: {what} expects {type_name(want)},"
                                f" found {type_name(got)}", at)
            out.append(self.top())
            self.words -= SIZES[got]
            self.stack.pop()
        return out[::-1]

    def emit(self, mnemonic: str, *operands: str) -> None:
        self.body.append(instr(mnemonic, *operands))

    def move(self, dest: List[str], src: List[str]) -> None:
        for d, s in zip(dest, src):
            self.emit("MOVE", d, s)

    def call(self, label: str, ft: FuncType, at: int, what: str) -> None:
        """Calls label with the arguments on top of the operand stack, by
        the rules of §9.3, and pushes the result. A label that is a
        register is called through it."""
        args = self.pop(list(ft.params), at, what)
        locs, stack_words = assign_args(ft.params)
        # Stack arguments go last to first, each high word first, so that
        # the first word ends up at the lowest address.
        for i in reversed(range(len(args))):
            if not locs[i][0]:
                for w in reversed(args[i]):
                    self.emit("MOVE", "@--R13", w)
        for i, (in_reg, first) in enumerate(locs):
            if in_reg:
                self.move([f"R{first + k}" for k in range(len(args[i]))], args[i])
        if label.startswith("R"):
            self.emit("ADD", "@--R13", "1", "R15")
        else:
            self.emit("ADD", "@--R13", "2", "R15")
        self.emit("MOVE", "R15", label)
        if stack_words:
            self.emit("ADD", "R13", "R13", str(stack_words))
        for rt in ft.results:
            self.move(self.push(rt), [f"R{k + 1}" for k in range(SIZES[rt])])

    def local_operand(self, i: int, at: int) -> Tuple[int, List[str]]:
        if i >= len(self.local):
            raise WasmError(f"function {self.idx}: local {i} does not exist", at)
        t = self.local_types[i]
        return t, [operand(self.local[i] + k) for k in range(SIZES[t])]

    def global_operand(self, i: int, at: int) -> Tuple[int, List[str]]:
        if i >= len(self.t.m.globals):
            raise WasmError(f"function {self.idx}: global {i} does not exist", at)
        t = self.t.m.globals[i].type
        return t, [f"@W.g{i}" + (f"+{k}" if k else "") for k in range(SIZES[t])]

    def trap(self, code: int) -> None:
        """Jumps through ___wasm_trap_vector with the code in R1 and the
        address of this code in R2 (§9.4)."""
        label = f"W.f{self.idx}.t{self.n_traps}"
        self.n_traps += 1
        self.body.append(label)
        self.emit("MOVE", "R1", str(code))
        self.emit("MOVE", "R2", label)
        self.emit("MOVE", "R15", "@___wasm_trap_vector")

    def new_label(self) -> str:
        label = f"W.f{self.idx}.L{self.n_labels}"
        self.n_labels += 1
        return label

    def slots(self, types: List[int], words: int) -> List[List[str]]:
        """The words of values of the given types, placed on the operand
        stack above the given number of words."""
        out = []
        for t in types:
            n = SIZES[t]
            out.append([operand(-self.n_slots - words - n + k) for k in range(n)])
            words += n
        return out

    def reset(self, f: Frame, types: List[int]) -> None:
        """Leaves only the values below f and then values of the given
        types on the operand stack."""
        del self.stack[f.height:]
        self.words = f.words
        for t in types:
            self.push(t)

    def frame(self, depth: int, at: int) -> Frame:
        if depth >= len(self.ctrl):
            raise WasmError(f"function {self.idx}: label {depth} does not exist", at)
        return self.ctrl[-1 - depth]

    def block_type(self, r: Reader) -> FuncType:
        at = r.pos
        b = r.byte()
        if b == 0x40:
            return FuncType([], [])
        if b in TYPE_NAMES:
            ft = FuncType([], [b])
        else:
            r.pos = at
            idx = r.leb(33, True)
            if not 0 <= idx < len(self.t.m.types):
                raise WasmError(f"type index {idx} is out of range", at)
            ft = self.t.m.types[idx]
        check_types(ft.params + ft.results, f"function {self.idx}: a block", at)
        return ft

    def branch_moves(self, f: Frame, at: int, what: str) -> List[Tuple[str, str]]:
        """Checks the values that a branch to f takes, which are on top of
        the operand stack, and returns the moves that put them where f
        expects them: in its slots, or for the function in R1 and up."""
        types = f.label_types()
        values = self.pop(list(types), at, what)
        for t in types:
            self.push(t)
        if f.op == 0:
            regs = [f"R{k + 1}" for k in range(sum(SIZES[t] for t in types))]
            return list(zip(regs, [w for v in values for w in v]))
        # The slots are at the same height or below. Moving the deepest
        # word first never overwrites a word that is still to be read.
        moves = []
        for dest, src in zip(self.slots(types, f.words), values):
            for k in reversed(range(len(dest))):
                if dest[k] != src[k]:
                    moves.append((dest[k], src[k]))
        return moves

    def end_block(self, f: Frame, at: int, what: str) -> None:
        """Checks that the operand stack holds exactly f's results, at else
        and at end."""
        self.pop(list(f.ft.results), at, what)
        if len(self.stack) != f.height:
            raise WasmError(f"function {self.idx}: values left on the operand stack at the {what}",
                            at)

    def compare(self, t: int, swap: bool, test: str, at: int, what: str) -> None:
        """An i32 or i64 comparison. It sets the flags, then the i32
        result: 1 if the test holds, else 0."""
        a, b = self.pop([t, t], at, what)
        if swap:
            a, b = b, a
        d = self.push(I32)[0]
        if t == I32:
            self.emit("SUB[M]", "R0", a[0], b[0])
        elif test in ("eq", "ne"):
            self.emit("XOR", "R1", a[0], b[0])
            self.emit("XOR", "R2", a[1], b[1])
            self.emit("OR[M]", "R0", "R1", "R2")
        else:
            self.emit("SUB[M]", "R0", a[0], b[0])
            self.emit("SUB[CM]", "R0", a[1], b[1])
        if test in ("eq", "ne"):
            self.emit("MOVE", d, "0")
            self.emit("?Z MOVE" if test == "eq" else "?!Z MOVE", d, "1")
        elif test == "lt_u":
            self.emit("ADD[C]", d, "R0", "R0")  # C, the borrow
        elif test == "ge_u":
            self.emit("SUB[C]", d, "1", "R0")   # 1 - C
        else:
            # a < b signed is N XOR V (§9.2).
            self.emit("MOVE", d, "0" if test == "lt_s" else "1")
            self.emit("?N XOR", d, d, "1")
            self.emit("?V XOR", d, d, "1")

    def address(self, base: str, offset: int, n: int) -> None:
        """Puts the byte address base + offset in R1. With bounds checks,
        traps with code 2 unless all n bytes there are in the memory. A
        trap's R2 is the start of this code, the first instruction of the
        access (§9.4)."""
        start = self.new_label()
        self.body.append(start)
        if not self.t.checks:
            # The address wraps modulo 2^32 (§9.4).
            if offset:
                self.emit("ADD", "R1", base, words(offset, I32)[0])
            else:
                self.emit("MOVE", "R1", base)
            return
        trap = self.trap_stub(2, start)
        if offset:
            self.emit("ADD[M]", "R1", base, words(offset, I32)[0])
            self.emit("?C MOVE", "R15", trap)  # base + offset passes 2^32
        else:
            self.emit("MOVE", "R1", base)
        # The first address at which n bytes do not fit.
        assert self.t.m.memory_pages is not None
        limit = self.t.m.memory_pages * WORDS_PER_PAGE * 4 - n + 1
        if limit <= 0:
            self.emit("MOVE", "R15", trap)
        elif limit < 1 << 32:
            self.emit("SUB[M]", "R0", "R1", words(limit, I32)[0])
            self.emit("?!C MOVE", "R15", trap)

    def call_indirect(self, type_idx: int, at: int, what: str) -> None:
        """Calls the function in the table entry whose index is on top of
        the operand stack (§9.4). An index past the end of the table and an
        empty entry trap with code 6, and an entry of another type with
        code 7. R5 holds the address, as R1-R4 hold arguments."""
        ft = self.t.m.types[type_idx]
        check_types(ft.params + ft.results, f"function {self.idx}: {what}", at)
        if len(ft.results) > 1:
            raise WasmError(f"function {self.idx}: {what}: more than one result is not supported"
                            " yet", at)
        (index,) = self.pop([I32], at, what)
        assert self.t.m.table_size is not None
        start = self.new_label()
        self.body.append(start)
        self.emit("MOVE", "R5", index[0])
        self.emit("SUB[M]", "R0", "R5", str(self.t.m.table_size))
        self.emit("?!C MOVE", "R15", self.trap_stub(6, start))    # index >= size
        self.emit("ADD", "R5", "R5", "R5")                         # two words an entry
        self.emit("MOVE[M]", "R0", "@W.table[R5]")
        self.emit("?Z MOVE", "R15", self.trap_stub(6, start))     # empty
        self.emit("SUB[M]", "R0", "@W.table+1[R5]", str(self.t.type_number(type_idx)))
        self.emit("?!Z MOVE", "R15", self.trap_stub(7, start))
        self.emit("MOVE", "R5", "@W.table[R5]")
        self.call("R5", ft, at, what)

    def range_check(self, addr: str, n: str, trap: str) -> None:
        """Jumps to trap unless the n bytes from byte address addr are all
        in the memory. n may be 0, even at the end of the memory."""
        assert self.t.m.memory_pages is not None
        size = self.t.m.memory_pages * WORDS_PER_PAGE * 4
        self.emit("ADD[M]", "R1", addr, n)
        self.emit("?C MOVE", "R15", trap)          # addr + n passes 2^32
        if size < 1 << 32:
            self.emit("SUB[M]", "R0", "R1", words(size + 1, I32)[0])
            self.emit("?!C MOVE", "R15", trap)

    def bulk(self, helper: str, at: int, what: str) -> None:
        """memory.fill or memory.copy. Both take (address, value or source
        address, n). With bounds checks, the ranges are checked before any
        byte is written, and a range out of bounds traps with code 2. Then
        the helper does the work."""
        d, x, n = self.pop([I32, I32, I32], at, what)
        for _ in range(3):
            self.push(I32)
        start = self.new_label()
        self.body.append(start)
        if self.t.checks:
            trap = self.trap_stub(2, start)
            self.range_check(d[0], n[0], trap)
            if helper == "W.copy":
                self.range_check(x[0], n[0], trap)
        self.t.helpers.add(helper)
        self.call(helper, FuncType([I32, I32, I32], []), at, what)

    def trap_stub(self, code: int, start: str) -> str:
        """A stub after the epilogue that traps with the given code, and
        with R2 = start, the first instruction of the code for the wasm
        instruction that traps (§9.4). Returns its label."""
        label = self.new_label()
        self.stubs += [label, instr("MOVE", "R1", str(code)), instr("MOVE", "R2", start),
                       instr("MOVE", "R15", "@___wasm_trap_vector")]
        return label

    def divide(self, t: int, op: str, at: int, what: str) -> None:
        """A division or remainder, by a call to the runtime library. First
        come the cases that wasm defines but C does not (§9.4): division by
        0 traps with code 3, and div_s of the most negative number by -1
        traps with code 4. rem_s by -1 is 0, without the call."""
        a, b = self.pop([t, t], at, what)
        self.push(t)
        self.push(t)
        start = self.new_label()
        self.body.append(start)
        if t == I32:
            self.emit("MOVE[M]", "R0", b[0])
        else:
            self.emit("OR[M]", "R0", b[0], b[1])
        self.emit("?Z MOVE", "R15", self.trap_stub(3, start))
        if op in ("div_s", "rem_s"):
            # Z = b is -1, all ones.
            if t == I32:
                self.emit("ADD[M]", "R0", b[0], "1")
            else:
                self.emit("AND", "R1", b[0], b[1])
                self.emit("ADD[M]", "R0", "R1", "1")
        done = ""
        if op == "div_s":
            ok = self.new_label()
            self.emit("?!Z MOVE", "R15", ok)
            # Z = a is the most negative number.
            if t == I32:
                self.emit("SUB[M]", "R0", a[0], "-2147483648")
            else:
                self.emit("XOR", "R1", a[1], "-2147483648")
                self.emit("OR[M]", "R0", "R1", a[0])
            self.emit("?Z MOVE", "R15", self.trap_stub(4, start))
            self.body.append(ok)
        elif op == "rem_s":
            # The result goes where a is.
            done = self.new_label()
            for w in a:
                self.emit("?Z MOVE", w, "0")
            self.emit("?Z MOVE", "R15", done)
        routine = {"div_s": "__div", "div_u": "__udiv", "rem_s": "__mod", "rem_u": "__umod"}[op]
        self.call(routine + ("64" if t == I64 else ""), FuncType([t, t], [t]), at, what)
        if done:
            self.body.append(done)

    def memarg(self, n: int, align: int, at: int, what: str) -> None:
        """Checks a load's or store's memory and alignment."""
        if self.t.m.memory_pages is None:
            raise WasmError(f"function {self.idx}: {what} needs a memory, and the module has"
                            " none", at)
        if 1 << align > n:
            raise WasmError(f"function {self.idx}: {what}: the alignment is larger than"
                            " natural", at)

    def load(self, t: int, n: int, signed: bool, offset: int, at: int, what: str) -> None:
        """Loads n bytes into a value of type t. A word of the memory holds
        four bytes, the lowest address in the low byte (§9.4). An access
        that is not at a multiple of 4 may need bytes from the next word,
        which is read only then."""
        (base,) = self.pop([I32], at, what)
        dest = self.push(t)
        self.address(base[0], offset, n)
        mem = "@___wasm_memory"
        self.emit("SHR", "R2", "R1", "2")                  # word index
        if n == 8:
            lo, hi = dest
            done = self.new_label()
            self.emit("AND[M]", "R3", "R1", "3")           # byte in the word
            self.emit("MOVE", lo, f"{mem}[R2]")
            self.emit("MOVE", hi, f"{mem}+1[R2]")
            self.emit("?Z MOVE", "R15", done)
            self.emit("SHL", "R3", "R3", "3")              # s = 8 * byte
            self.emit("SUB", "R4", "32", "R3")             # 32 - s
            self.emit("SHR", lo, lo, "R3")
            self.emit("SHL", "R1", hi, "R4")
            self.emit("OR", lo, lo, "R1")
            self.emit("SHR", hi, hi, "R3")
            self.emit("SHL", "R1", f"{mem}+2[R2]", "R4")
            self.emit("OR", hi, hi, "R1")
            self.body.append(done)
            return
        # The n bytes go to the low bytes of R4, with other bytes above.
        if n == 4:
            self.emit("AND[M]", "R3", "R1", "3")
            self.emit("MOVE", "R4", f"{mem}[R2]")
            self.emit("?!Z SHL", "R3", "R3", "3")
            self.emit("?!Z SHR", "R4", "R4", "R3")
            self.emit("?!Z SUB", "R3", "32", "R3")
            self.emit("?!Z SHL", "R1", f"{mem}+1[R2]", "R3")
            self.emit("?!Z OR", "R4", "R4", "R1")
        else:
            self.emit("AND", "R3", "R1", "3")
            self.emit("SHL", "R3", "R3", "3")
            self.emit("SHR", "R4", f"{mem}[R2]", "R3")
            if n == 2:
                # Byte 3 of a word: the second byte is in the next word.
                self.emit("SUB[M]", "R0", "R3", "24")
                self.emit("?Z SHL", "R1", f"{mem}+1[R2]", "8")
                self.emit("?Z OR", "R4", "R4", "R1")
        # Extend to 32 bits, setting N for an i64's high word.
        if n == 4:
            self.emit("MOVE[M]" if signed else "MOVE", dest[0], "R4")
        elif signed:
            # (x XOR sign) - sign extends the sign bit of x.
            sign = str(1 << (8 * n - 1))
            self.emit("AND", "R4", "R4", str((1 << (8 * n)) - 1))
            self.emit("XOR", "R4", "R4", sign)
            self.emit("SUB[M]", dest[0], "R4", sign)
        else:
            self.emit("AND", dest[0], "R4", str((1 << (8 * n)) - 1))
        if t == I64:
            self.emit("MOVE", dest[1], "0")
            if signed:
                self.emit("?N MOVE", dest[1], "-1")

    def store(self, t: int, n: int, offset: int, at: int, what: str) -> None:
        """Stores the low n bytes of a value of type t. A store that does
        not fill whole words reads each partial word, changes its bytes,
        and writes it back (§9.4)."""
        base, value = self.pop([I32, t], at, what)
        v = value[0]
        self.address(base[0], offset, n)
        mem = "@___wasm_memory"
        self.emit("SHR", "R2", "R1", "2")                  # word index
        if n >= 4:
            done = self.new_label()
            self.emit("AND[M]", "R3", "R1", "3")           # byte in the word
            self.emit("?Z MOVE", f"{mem}[R2]", v)
            if n == 8:
                self.emit("?Z MOVE", f"{mem}+1[R2]", value[1])
            self.emit("?Z MOVE", "R15", done)
            self.emit("SHL", "R3", "R3", "3")              # s = 8 * byte
            # The first word keeps its low s bits.
            self.emit("SHL", "R4", "-1", "R3")
            self.emit("IAND", "R4", "R4", f"{mem}[R2]")
            self.emit("SHL", "R1", v, "R3")
            self.emit("OR", f"{mem}[R2]", "R4", "R1")
            self.emit("SUB", "R4", "32", "R3")             # 32 - s
            last = f"{mem}+1[R2]"
            if n == 8:
                # The middle word is all new.
                self.emit("SHR", "R1", v, "R4")
                self.emit("SHL", "R3", value[1], "R3")
                self.emit("OR", f"{mem}+1[R2]", "R1", "R3")
                v = value[1]
                last = f"{mem}+2[R2]"
            # The last word keeps all but its low s bits.
            self.emit("SHR", "R3", "-1", "R4")
            self.emit("IAND", "R3", "R3", last)
            self.emit("SHR", "R1", v, "R4")
            self.emit("OR", last, "R3", "R1")
            self.body.append(done)
            return
        mask = str((1 << (8 * n)) - 1)
        self.emit("AND", "R3", "R1", "3")
        self.emit("SHL", "R3", "R3", "3")                  # s = 8 * byte
        self.emit("SHL", "R4", mask, "R3")
        self.emit("IAND", "R4", "R4", f"{mem}[R2]")
        self.emit("AND", "R1", v, mask)
        self.emit("SHL", "R1", "R1", "R3")
        self.emit("OR", f"{mem}[R2]", "R4", "R1")
        if n == 2:
            # Byte 3 of a word: the second byte goes in the next word.
            self.emit("SUB[M]", "R0", "R3", "24")
            self.emit("?Z AND", "R4", f"{mem}+1[R2]", "0xFFFFFF00")
            self.emit("?Z SHR", "R1", v, "8")
            self.emit("?Z AND", "R1", "R1", "0xFF")
            self.emit("?Z OR", f"{mem}+1[R2]", "R4", "R1")

    def shift64(self, op: str, at: int, what: str) -> None:
        """An i64 shift or rotate. The count is the low word of the second
        operand, modulo 64. A NICE shift uses its full count, so a count of
        32 or more, or a "negative" one like 32 - n for n > 32, shifts out
        every bit (§5.2). That makes the logical shifts branch-free."""
        a, b = self.pop([I64, I64], at, what)
        lo, hi = self.push(I64)  # the same words as a
        if op in ("shl", "shr_u"):
            # shl: hi' = hi << n | lo >> (32 - n) | lo << (n - 32), lo' = lo << n.
            # shr_u is the mirror image, with the words swapped.
            near, far = (lo, hi) if op == "shl" else (hi, lo)
            fwd, back = ("SHL", "SHR") if op == "shl" else ("SHR", "SHL")
            self.emit("AND", "R1", b[0], "63")                 # n
            self.emit("SUB", "R2", "32", "R1")
            self.emit("SUB", "R3", "R1", "32")
            self.emit(back, "R4", near, "R2")
            self.emit(fwd, "R2", near, "R3")
            self.emit("OR", "R4", "R4", "R2")
            self.emit(fwd, "R2", far, "R1")
            self.emit("OR", far, "R4", "R2")
            self.emit(fwd, near, near, "R1")
        elif op == "shr_s":
            # hi' = hi >>s n, which is all sign bits for n >= 32. lo' is
            # hi >>s (n - 32) for n >= 32, else lo >> n | hi << (32 - n).
            self.emit("AND", "R1", b[0], "63")                 # n
            self.emit("SUB", "R2", "R1", "32")
            self.emit("C<0[M]", "R0", hi, "1")                 # C = the sign bit
            self.emit("C>0", "R3", hi, "R2")
            self.emit("C>0", "R4", hi, "R1")
            self.emit("SUB[M]", "R0", "R1", "32")              # C = n < 32
            self.emit("?C SUB", "R2", "32", "R1")
            self.emit("?C SHR", "R3", lo, "R1")
            self.emit("?C SHL", "R2", hi, "R2")
            self.emit("?C OR", "R3", "R3", "R2")
            self.emit("MOVE", lo, "R3")
            self.emit("MOVE", hi, "R4")
        else:
            # A rotate by n >= 32 is a rotate of the swapped words by
            # n - 32. rotr by n is rotl by -n.
            count = b[0]
            if op == "rotr":
                self.emit("SUB", "R1", "0", b[0])
                count = "R1"
            self.emit("AND[M]", "R0", count, "32")             # Z = (n mod 64) < 32
            self.emit("AND", "R1", count, "31")                # k
            self.emit("MOVE", "R2", lo)                        # x
            self.emit("MOVE", "R3", hi)                        # y
            self.emit("?!Z MOVE", "R2", hi)
            self.emit("?!Z MOVE", "R3", lo)
            self.emit("SUB", "R4", "32", "R1")
            # lo' = x << k | y >> (32 - k), hi' = y << k | x >> (32 - k).
            self.emit("SHL", lo, "R2", "R1")
            self.emit("SHR", hi, "R3", "R4")
            self.emit("OR", lo, lo, hi)
            self.emit("SHL", hi, "R3", "R1")
            self.emit("SHR", "R4", "R2", "R4")
            self.emit("OR", hi, hi, "R4")

    def run(self) -> List[str]:
        r = Reader(self.t.data, self.code.start, self.code.end)
        reachable = True
        dead_blocks = 0  # blocks opened in code that cannot be reached
        while True:
            at = r.pos
            op = r.byte()
            name = OPCODES.get(op, f"opcode 0x{op:02x}")
            if op == 0xFC:
                sub = r.u32()
                name = FC_OPCODES.get(sub, f"opcode 0xfc {sub}")
                if sub not in (10, 11):  # memory.copy, memory.fill
                    raise WasmError(f"function {self.idx}: {name} is not supported yet", at)
                for _ in range(2 if sub == 10 else 1):
                    mem_at = r.pos
                    mem = r.u32()
                    if mem != 0 or self.t.m.memory_pages is None:
                        raise WasmError(f"function {self.idx}: memory {mem} does not exist",
                                        mem_at)
                op = 0x100 + sub
            imm: Optional[int] = None
            ft = FuncType([], [])
            targets: List[int] = []
            sel_type: Optional[int] = None
            align = 0
            if op in (0x0C, 0x0D, 0x10, 0x20, 0x21, 0x22, 0x23, 0x24):
                imm = r.u32()
            elif op == 0x11:  # call_indirect: a type index, then a table index
                type_at = r.pos
                imm = r.u32()
                if imm >= len(self.t.m.types):
                    raise WasmError(f"type index {imm} is out of range", type_at)
                table_at = r.pos
                table_idx = r.u32()
                if table_idx != 0 or self.t.m.table_size is None:
                    raise WasmError(f"function {self.idx}: table {table_idx} does not exist",
                                    table_at)
            elif op == 0x41:
                imm = r.s32()
            elif op == 0x42:
                imm = r.leb(64, True)
            elif op in (BLOCK, LOOP, IF):
                ft = self.block_type(r)
            elif op in LOADS or op in STORES:
                align = r.u32()
                imm = r.u32()  # the offset
            elif op in (0x3F, 0x40):  # memory.size, memory.grow
                mem_at = r.pos
                mem = r.u32()
                if mem != 0 or self.t.m.memory_pages is None:
                    raise WasmError(f"function {self.idx}: memory {mem} does not exist", mem_at)
            elif op == 0x0E:
                targets = [r.u32() for _ in range(r.u32() + 1)]
            elif op == 0x1C:
                types = [r.byte() for _ in range(r.u32())]
                if len(types) != 1:
                    raise WasmError(f"function {self.idx}: select must name one type", at)
                check_types(types, f"function {self.idx}: select", at)
                sel_type = types[0]
            elif not (op in (0x00, 0x01, 0x05, 0x0B, 0x0F, 0x1A, 0x1B, 0x45, 0x50, 0xA7,
                             0xAC, 0xAD, 0x10A, 0x10B, 0x11)
                      or op in DIV_OPS or op in LIB_OPS or op in EXTEND_OPS
                      or op in ALU_OPS or op in ALU64_OPS or op in CMP_OPS or op in CMP64_OPS
                      or op in SHIFT_OPS or op in SHIFT64_OPS):
                raise WasmError(f"function {self.idx}: {name} is not supported yet", at)
            if not reachable:
                # Skip to the else or end that makes the code reachable again.
                if op in (BLOCK, LOOP, IF):
                    dead_blocks += 1
                    continue
                if op == 0x0B and dead_blocks:
                    dead_blocks -= 1
                    continue
                if op not in (0x05, 0x0B) or dead_blocks:
                    continue
            comment = f"        ; {name}"
            if imm is not None:
                comment += f" {imm}"
            elif targets:
                comment += " " + " ".join(map(str, targets))
            self.body.append(comment)
            if op == 0x0B:  # end
                f = self.ctrl[-1]
                if f.op == 0:
                    if not r.at_end():
                        raise WasmError(f"function {self.idx}: code after the function's end", r.pos)
                    if reachable:
                        self.ret(at, name)
                        if self.stack:
                            raise WasmError(f"function {self.idx}: values left on the operand"
                                            " stack at the end", at)
                    break
                if reachable:
                    self.end_block(f, at, name)
                if f.else_label is not None:
                    # An if without else passes its parameters on as its
                    # results.
                    if f.ft.params != f.ft.results:
                        raise WasmError(f"function {self.idx}: an if without else must have"
                                        " the same parameters and results", at)
                    self.body.append(f.else_label)
                if f.op != LOOP:
                    self.body.append(f.label)
                self.ctrl.pop()
                self.reset(f, f.ft.results)
                reachable = True
            elif op == 0x05:  # else
                f = self.ctrl[-1]
                if f.else_label is None:
                    raise WasmError(f"function {self.idx}: else without if", at)
                if reachable:
                    self.end_block(f, at, name)
                    self.emit("MOVE", "R15", f.label)
                self.body.append(f.else_label)
                f.else_label = None
                self.reset(f, f.ft.params)
                reachable = True
            elif op == 0x00:  # unreachable
                self.trap(1)
                reachable = False
            elif op == 0x01:  # nop
                pass
            elif op in (BLOCK, LOOP, IF):
                cond_word = self.pop([I32], at, name)[0][0] if op == IF else ""
                self.pop(list(ft.params), at, name)
                f = Frame(op, ft, len(self.stack), self.words, self.new_label())
                for t in ft.params:
                    self.push(t)
                self.ctrl.append(f)
                if op == LOOP:
                    self.body.append(f.label)
                if op == IF:
                    f.else_label = self.new_label()
                    self.emit("MOVE[M]", "R0", cond_word)
                    self.emit("?Z MOVE", "R15", f.else_label)
            elif op == 0x0C:  # br
                assert imm is not None
                f = self.frame(imm, at)
                for to, frm in self.branch_moves(f, at, name):
                    self.emit("MOVE", to, frm)
                self.emit("MOVE", "R15", f.label)
                reachable = False
            elif op == 0x0D:  # br_if
                assert imm is not None
                (cond,) = self.pop([I32], at, name)
                f = self.frame(imm, at)
                moves = self.branch_moves(f, at, name)
                self.emit("MOVE[M]", "R0", cond[0])
                if moves:
                    skip = self.new_label()
                    self.emit("?Z MOVE", "R15", skip)
                    for to, frm in moves:
                        self.emit("MOVE", to, frm)
                    self.emit("MOVE", "R15", f.label)
                    self.body.append(skip)
                else:
                    self.emit("?!Z MOVE", "R15", f.label)
            elif op == 0x0E:  # br_table
                (index,) = self.pop([I32], at, name)
                frames = [self.frame(d, at) for d in targets]
                default = frames[-1]
                for f in frames:
                    if f.label_types() != default.label_types():
                        raise WasmError(f"function {self.idx}: the labels of br_table take"
                                        " different values", at)
                # A label whose values must be moved first gets a stub that
                # moves them and then branches.
                target: Dict[int, str] = {}  # label depth -> address
                stubs: List[str] = []
                for depth, f in zip(targets, frames):
                    if depth in target:
                        continue
                    moves = self.branch_moves(f, at, name)
                    if not moves:
                        target[depth] = f.label
                        continue
                    target[depth] = self.new_label()
                    stubs.append(target[depth])
                    stubs += [instr("MOVE", to, frm) for to, frm in moves]
                    stubs.append(instr("MOVE", "R15", f.label))
                table = self.new_label()
                n = len(targets) - 1
                self.emit("MOVE", "R1", index[0])
                self.emit("SUB[M]", "R0", "R1", str(n))
                self.emit("?!C MOVE", "R15", target[targets[-1]])  # index >= n, unsigned
                self.emit("MOVE", "R15", f"@{table}[R1]")
                self.body.append(table)
                self.body += [instr(".DAT", target[depth]) for depth in targets[:-1]]
                self.body += stubs
                reachable = False
            elif op == 0x1A:  # drop
                self.pop([None], at, name)
            elif op in (0x1B, 0x1C):  # select
                (cond,) = self.pop([I32], at, name)
                if sel_type is None and len(self.stack) > self.ctrl[-1].height:
                    sel_type = self.stack[-1]
                a, b = self.pop([sel_type, sel_type], at, name)  # underflow if None
                assert sel_type is not None
                # The result goes where the first value already is.
                self.emit("MOVE[M]", "R0", cond[0])
                for k in range(len(a)):
                    self.emit("?Z MOVE", a[k], b[k])
                self.push(sel_type)
            elif op == 0x0F:  # return
                self.ret(at, name)
                self.emit("MOVE", "R15", self.ret_label)
                reachable = False
            elif op == 0x10:  # call
                assert imm is not None
                if imm >= len(self.t.m.imports) + len(self.t.m.funcs):
                    raise WasmError(f"function {self.idx}: function {imm} does not exist", at)
                if imm < len(self.t.m.imports) and self.t.m.imports[imm].module == "nice":
                    # One access, even if a peek's result is not used (§9.4).
                    if self.t.m.imports[imm].name == "peek":
                        (addr,) = self.pop([I32], at, "nice.peek")
                        self.emit("MOVE", "R1", addr[0])
                        self.emit("MOVE", self.push(I32)[0], "@R1")
                    else:
                        addr, value = self.pop([I32, I32], at, "nice.poke")
                        self.emit("MOVE", "R1", addr[0])
                        self.emit("MOVE", "@R1", value[0])
                else:
                    self.call(self.t.func_label(imm), self.t.func_type(imm), at, name)
            elif op == 0x11:  # call_indirect
                assert imm is not None
                self.call_indirect(imm, at, name)
            elif op == 0x20:  # local.get
                assert imm is not None
                t, src = self.local_operand(imm, at)
                self.move(self.push(t), src)
            elif op in (0x21, 0x22):  # local.set, local.tee
                assert imm is not None
                t, dest = self.local_operand(imm, at)
                (src,) = self.pop([t], at, name)
                self.move(dest, src)
                if op == 0x22:
                    self.push(t)
            elif op == 0x23:  # global.get
                assert imm is not None
                t, src = self.global_operand(imm, at)
                self.move(self.push(t), src)
            elif op == 0x24:  # global.set
                assert imm is not None
                t, dest = self.global_operand(imm, at)
                if not self.t.m.globals[imm].mutable:
                    raise WasmError(f"function {self.idx}: global {imm} is immutable", at)
                (src,) = self.pop([t], at, name)
                self.move(dest, src)
            elif op in (0x41, 0x42):  # i32.const, i64.const
                assert imm is not None
                t = I32 if op == 0x41 else I64
                for d, w in zip(self.push(t), words(imm, t)):
                    self.emit("MOVE", d, w)
            elif op in (0x45, 0x50):  # i32.eqz, i64.eqz
                t = I32 if op == 0x45 else I64
                (a,) = self.pop([t], at, name)
                if t == I32:
                    self.emit("MOVE[M]", "R0", a[0])
                else:
                    self.emit("OR[M]", "R0", a[0], a[1])
                d = self.push(I32)[0]
                self.emit("MOVE", d, "0")
                self.emit("?Z MOVE", d, "1")
            elif op in LOADS:
                assert imm is not None
                t, n, signed = LOADS[op]
                self.memarg(n, align, at, name)
                self.load(t, n, signed, imm, at, name)
            elif op in STORES:
                assert imm is not None
                t, n = STORES[op]
                self.memarg(n, align, at, name)
                self.store(t, n, imm, at, name)
            elif op == 0x3F:  # memory.size
                assert self.t.m.memory_pages is not None
                self.emit("MOVE", self.push(I32)[0], str(self.t.m.memory_pages))
            elif op == 0x40:  # memory.grow
                # The memory cannot grow yet, so only growing by 0 pages
                # succeeds. It returns the size, and anything else -1.
                assert self.t.m.memory_pages is not None
                (delta,) = self.pop([I32], at, name)
                d = self.push(I32)[0]
                self.emit("MOVE[M]", "R0", delta[0])
                self.emit("MOVE", d, "-1")
                self.emit("?Z MOVE", d, str(self.t.m.memory_pages))
            elif op in SHIFT_OPS:
                a, b = self.pop([I32, I32], at, name)
                d = self.push(I32)[0]
                shift = SHIFT_OPS[op]
                if shift in ("rotl", "rotr"):
                    # Only the count modulo 32 matters to a rotation (§5.2).
                    self.emit("ROL" if shift == "rotl" else "ROR", d, a[0], b[0])
                else:
                    # Wasm takes the count modulo 32 (§9.4).
                    self.emit("AND", "R1", b[0], "31")
                    if shift == "shr_s":
                        self.emit("C<0[M]", "R0", a[0], "1")   # C = the sign bit (§5.2)
                    self.emit({"shl": "SHL", "shr_u": "SHR", "shr_s": "C>0"}[shift], d, a[0], "R1")
            elif op in SHIFT64_OPS:
                self.shift64(SHIFT64_OPS[op], at, name)
            elif op in CMP_OPS:
                self.compare(I32, *CMP_OPS[op], at, name)
            elif op in CMP64_OPS:
                self.compare(I64, *CMP64_OPS[op], at, name)
            elif op in ALU_OPS:
                a, b = self.pop([I32, I32], at, name)
                self.emit(ALU_OPS[op], self.push(I32)[0], a[0], b[0])
            elif op in ALU64_OPS:
                a, b = self.pop([I64, I64], at, name)
                dest = self.push(I64)
                for k, mnemonic in enumerate(ALU64_OPS[op]):
                    self.emit(mnemonic, dest[k], a[k], b[k])
            elif op in (0x10A, 0x10B):  # memory.copy, memory.fill
                self.bulk("W.copy" if op == 0x10A else "W.fill", at, name)
            elif op in LIB_OPS:
                routine, (params, results) = LIB_OPS[op]
                self.call(routine, FuncType(params, results), at, name)
            elif op in DIV_OPS:
                self.divide(*DIV_OPS[op], at, name)
            elif op in EXTEND_OPS:
                t, bits = EXTEND_OPS[op]
                (a,) = self.pop([t], at, name)
                ext = self.push(t)  # the same words as a
                if bits == 32:
                    self.emit("MOVE[M]", ext[0], a[0])
                else:
                    # (x XOR sign) - sign extends the sign bit of x. SUB[M]
                    # sets N for an i64's high word.
                    sign = str(1 << (bits - 1))
                    self.emit("AND", "R1", a[0], str((1 << bits) - 1))
                    self.emit("XOR", "R1", "R1", sign)
                    self.emit("SUB[M]" if t == I64 else "SUB", ext[0], "R1", sign)
                if t == I64:
                    self.emit("MOVE", ext[1], "0")
                    self.emit("?N MOVE", ext[1], "-1")
            elif op == 0xA7:  # i32.wrap_i64
                (a,) = self.pop([I64], at, name)
                self.emit("MOVE", self.push(I32)[0], a[0])
            elif op in (0xAC, 0xAD):  # i64.extend_i32_s, i64.extend_i32_u
                # The i32 is in the word that becomes the high word, so the
                # low word is written first.
                (a,) = self.pop([I32], at, name)
                lo, hi = self.push(I64)
                self.emit("MOVE" if op == 0xAD else "MOVE[M]", lo, a[0])
                self.emit("MOVE", hi, "0")
                if op == 0xAC:
                    self.emit("?N MOVE", hi, "-1")
        return self.wrap()

    def ret(self, at: int, what: str) -> None:
        """Moves the result into R1, or R1 and R2, for return and for the
        final end. The values below it are dropped."""
        results = self.pop(list(self.ftype.results), at, what)
        for rt, src in zip(self.ftype.results, results):
            self.move([f"R{k + 1}" for k in range(SIZES[rt])], src)

    def wrap(self) -> List[str]:
        """Adds the prologue and the epilogue, which build and drop the
        §9.3 frame."""
        name = printable(self.t.m.names.get(self.idx, ""))
        out = [f"; Function {self.idx}" + (f": {name}" if name else "")]
        out += self.t.labels.get(self.idx, [])
        out.append(f"W.f{self.idx}")
        out.append(instr("MOVE", "@--R13", "R12"))
        out.append(instr("MOVE", "R12", "R13"))
        size = self.n_slots + self.max_words
        if size:
            out.append(instr("SUB", "R13", "R13", str(size)))
        for i, (in_reg, first) in enumerate(self.args):
            if in_reg:
                for k in range(SIZES[self.local_types[i]]):
                    out.append(instr("MOVE", operand(self.local[i] + k), f"R{first + k}"))
        for i in range(len(self.args), len(self.local)):
            for k in range(SIZES[self.local_types[i]]):
                out.append(instr("MOVE", operand(self.local[i] + k), "0"))  # wasm zeroes locals
        out += self.body
        out.append(self.ret_label)
        out.append(instr("MOVE", "R13", "R12"))
        out.append(instr("MOVE", "R12", "@R13++"))
        out.append(instr("MOVE", "R15", "@R13++"))
        out += self.stubs
        return out


def translate(data: bytes, source: str, checks: bool = True) -> List[str]:
    return Translator(parse(data), data, checks).run(source)


def main() -> None:
    ap = argparse.ArgumentParser(description="Translates a WebAssembly module into NICE assembly.")
    ap.add_argument("input", help="wasm module (.wasm)")
    ap.add_argument("-o", dest="output",
                    help="output file (default: input with .asm extension)")
    ap.add_argument("--no-bounds-checks", action="store_true",
                    help="do not check that memory accesses are in bounds")
    args = ap.parse_args()

    out = args.output or os.path.splitext(args.input)[0] + ".asm"
    try:
        with open(args.input, "rb") as f:
            data = f.read()
        if os.path.exists(out) and os.path.samefile(out, args.input):
            sys.exit(f"{args.input}: the output file would overwrite the input; use -o")
    except OSError as e:
        sys.exit(f"{e.filename}: {e.strerror}")

    try:
        lines = translate(data, os.path.basename(args.input), not args.no_bounds_checks)
    except WasmError as e:
        where = "" if e.offset is None else f":0x{e.offset:x}"
        print(f"{args.input}{where}: error: {e}", file=sys.stderr)
        sys.exit(1)

    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
