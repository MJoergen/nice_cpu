#!/usr/bin/env python3
"""nicewasm - translates a WebAssembly module into NICE assembly.

Implements the WebAssembly mapping of doc/ISA.md section 9.4. The output is
one assembly file, to be joined with the start-up code, the program's other
files, and the runtime library as section 9.3 describes.

Usage: nicewasm.py [-o output.nasm] [--no-bounds-checks] [--memory-pages N]
                   [--library NAME [--library-memory BYTES]] [--no-mpu] input.wasm

README.md lists the wasm features it supports. Anything else is rejected
with an error, never translated wrongly.

Each function is translated in two steps. The front end
(FunctionTranslator) turns each wasm instruction into a few NICE
instructions on virtual registers, one for each word of each local and of
each value on the wasm operand stack. An i32 or f32 takes one word, and an
i64 or f64 two, low word first. A constant or the value of a local is
copied to registers of its own only when it must be; until then, the
instructions that use it take the constant or the local as their operand.
The back end (Allocator) colours the virtual registers with R1-R12 by
iterated register coalescing, and puts the values that do not fit in frame
words, addressed from SP. There is no frame pointer.
"""

from __future__ import annotations

import argparse
import functools
import heapq
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, FrozenSet, List, Optional, Tuple, Union

I32, I64, F32, F64 = 0x7F, 0x7E, 0x7D, 0x7C
TYPE_NAMES = {I32: "i32", I64: "i64", F32: "f32", F64: "f64", 0x7B: "v128",
              0x70: "funcref", 0x6F: "externref"}

SIZES = {I32: 1, I64: 2, F32: 1, F64: 2}  # words per value of each supported type

# The registers that the allocator gives to values. A call may change
# CALLER_SAVED, and a function saves the CALLEE_SAVED ones that it uses
# (§9.3). There is no frame pointer, so R12 is one of them.
ALLOC_REGS = [f"R{k}" for k in range(1, 13)]
CALLER_SAVED = frozenset(f"R{k}" for k in range(1, 7))
CALLEE_SAVED = [f"R{k}" for k in range(7, 13)]

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

# The float operations that are a call to the float library (runtime/
# float.nasm): wasm opcode -> (routine, parameter types, result type).
FLOAT_OPS: Dict[int, Tuple[str, List[int], int]] = {}
for _t, _first, _suffix in [(F32, 0x8D, "sf"), (F64, 0x9B, "df")]:
    for _i, _name in enumerate("ceil floor trunc nearest sqrt".split()):
        FLOAT_OPS[_first + _i] = (f"__{_name}{_suffix}", [_t], _t)
    for _i, _name in enumerate(f"add{_suffix}3 sub{_suffix}3 mul{_suffix}3 div{_suffix}3 min{_suffix}"
                               f" max{_suffix}".split()):
        FLOAT_OPS[_first + 5 + _i] = (f"__{_name}", [_t, _t], _t)
FLOAT_OPS.update({
    0xB2: ("__floatsisf", [I32], F32), 0xB3: ("__floatunsisf", [I32], F32),
    0xB4: ("__floatdisf", [I64], F32), 0xB5: ("__floatundisf", [I64], F32),
    0xB6: ("__truncdfsf2", [F64], F32),
    0xB7: ("__floatsidf", [I32], F64), 0xB8: ("__floatunsidf", [I32], F64),
    0xB9: ("__floatdidf", [I64], F64), 0xBA: ("__floatundidf", [I64], F64),
    0xBB: ("__extendsfdf2", [F32], F64)})

# The conversions from float to integer. Those of the library saturate and
# give 0 for a NaN, as trunc_sat does. trunc must trap instead (§9.4), if
# the value is a NaN or its integer part does not fit. That is the case
# when its magnitude, its bits without the sign, is not below a limit,
# one for each sign. wasm opcode -> (routine, from, to, limit for +, for -).
TRUNC_OPS: Dict[int, Tuple[str, int, int, int, int]] = {
    0xA8: ("__fixsfsi", F32, I32, 0x4F000000, 0x4F000001),           # 2^31; -2^31 fits
    0xA9: ("__fixunssfsi", F32, I32, 0x4F800000, 0x3F800000),        # 2^32; above -1
    0xAA: ("__fixdfsi", F64, I32, 0x41E00000_00000000, 0x41E00000_00200000),  # -(2^31 + 1)
    0xAB: ("__fixunsdfsi", F64, I32, 0x41F00000_00000000, 0x3FF00000_00000000),
    0xAE: ("__fixsfdi", F32, I64, 0x5F000000, 0x5F000001),           # 2^63; -2^63 fits
    0xAF: ("__fixunssfdi", F32, I64, 0x5F800000, 0x3F800000),        # 2^64
    0xB0: ("__fixdfdi", F64, I64, 0x43E00000_00000000, 0x43E00000_00000001),
    0xB1: ("__fixunsdfdi", F64, I64, 0x43F00000_00000000, 0x3FF00000_00000000),
}
# trunc_sat: the instructions after 0xFC with the second opcodes 0 to 7, in
# the same order as the trunc opcodes.
TRUNC_SAT_OPS = {0x100 + _i: _op for _i, _op in enumerate(sorted(TRUNC_OPS))}

# The float comparisons call the libgcc-style routines, whose result is
# below 0, 0, or above 0, and for a NaN the value that makes the test fail.
# wasm opcode -> (type, routine, the test of the result).
FLOAT_CMP_OPS: Dict[int, Tuple[int, str, str]] = {}
for _t, _first, _suffix in [(F32, 0x5B, "sf"), (F64, 0x61, "df")]:
    for _i, (_name, _test) in enumerate([("eq", "=="), ("ne", "!="), ("lt", "<"), ("gt", ">"),
                                         ("le", "<="), ("ge", ">=")]):
        FLOAT_CMP_OPS[_first + _i] = (_t, f"__{_name}{_suffix}2", _test)

# The constant instruction of each type.
CONST_OPS = {I32: 0x41, I64: 0x42, F32: 0x43, F64: 0x44}

# The reinterpretations: wasm opcode -> (from, to). The bits stay as they
# are, so they need no code.
REINTERPRET_OPS = {0xBC: (F32, I32), 0xBD: (F64, I64), 0xBE: (I32, F32), 0xBF: (I64, F64)}

# abs, neg, and copysign change only the sign bit, the top bit of the
# value's last word: wasm opcode -> (type, operation).
SIGN_OPS = {0x8B: (F32, "abs"), 0x8C: (F32, "neg"), 0x98: (F32, "copysign"),
            0x99: (F64, "abs"), 0x9A: (F64, "neg"), 0xA6: (F64, "copysign")}

# The loads: wasm opcode -> (type, bytes, signed). And the stores: wasm
# opcode -> (type, bytes).
LOADS = {0x28: (I32, 4, False), 0x29: (I64, 8, False), 0x2A: (F32, 4, False),
         0x2B: (F64, 8, False), 0x2C: (I32, 1, True),
         0x2D: (I32, 1, False), 0x2E: (I32, 2, True), 0x2F: (I32, 2, False),
         0x30: (I64, 1, True), 0x31: (I64, 1, False), 0x32: (I64, 2, True),
         0x33: (I64, 2, False), 0x34: (I64, 4, True), 0x35: (I64, 4, False)}
STORES = {0x36: (I32, 4), 0x37: (I64, 8), 0x38: (F32, 4), 0x39: (F64, 8), 0x3A: (I32, 1),
          0x3B: (I32, 2),
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
    label: str                        # where a branch to it goes
    params_v: List[List[str]]         # the registers of its parameters
    results_v: List[List[str]]        # and of its results, which every path to its end writes
    else_label: Optional[str] = None  # an if's false branch, until its else

    def label_types(self) -> List[int]:
        """The values that a branch to it takes."""
        return self.ft.params if self.op == LOOP else self.ft.results


@dataclass
class Deferred:
    """A value on the operand stack that is not in registers of its own: a
    constant, or the value that a local holds."""
    words: List[str]       # its words as source operands
    local: Optional[int]   # the local whose value it is, or None for a constant


@dataclass
class Label:
    """A label in a function's code."""
    name: str


@dataclass(eq=False)
class Ins:
    """One NICE instruction in a function's code. Its operands are text, as
    in the output, dest first. A jump (MOVE R15, x) also says where it may
    go, so that later passes can follow the control flow: a jump to a label
    names it in targets, a call goes on to the next instruction, and an
    exit leaves the function. A call or an exit also names the registers
    that the code it reaches reads (uses) and, for a call, changes (defs)."""
    op: str                    # the mnemonic with its flags, such as ADD[M]
    ops: List[str]             # the operands, dest first
    cond: str = ""             # the condition, such as Z or !Z, or "" for always
    kind: str = ""             # "jump", "call", "exit", or "" for an instruction that goes on
    targets: List[str] = field(default_factory=list)
    uses: FrozenSet[str] = frozenset()
    defs: FrozenSet[str] = frozenset()
    depth: int = 0             # the loops around it, which weigh its registers' spill costs
    back: bool = False         # a conditional jump back to the start of a loop, at its end

    def text(self) -> str:
        return instr((f"?{self.cond} " if self.cond else "") + self.op, *self.ops)


# The code of a function: instructions, labels, and other lines, such as
# comments and .DAT directives, as text.
Item = Union[Ins, Label, str]


def make_ins(mnemonic: str, *operands: str) -> Ins:
    """An instruction from its mnemonic, which may start with a condition
    such as ?Z, and its operands. A jump to a label or through the trap
    vector says so."""
    cond = ""
    if mnemonic.startswith("?"):
        cond, mnemonic = mnemonic[1:].split(" ", 1)
    ins = Ins(mnemonic, list(operands), cond)
    if mnemonic == "MOVE" and operands[0] == "R15":
        if operands[1] == "@___wasm_trap_vector":
            ins.kind, ins.uses = "exit", frozenset({"R1", "R2"})
        elif re.match(r"[A-Za-z_.][\w.]*\Z", operands[1]):
            ins.kind, ins.targets = "jump", [operands[1]]
    return ins


def render(items: List[Item]) -> List[str]:
    """The lines of the output for a function's code."""
    return [it.text() if isinstance(it, Ins) else it.name if isinstance(it, Label) else it
            for it in items]


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
    memory_max: Optional[int] = None                   # its maximum size, if it has one
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


def read_const(s: Reader, t: int) -> int:
    """The immediate of a t.const: a signed LEB128 number for the integer
    types, and the bits of the number, little-endian, for the float types."""
    if t == I32:
        return s.s32()
    if t == I64:
        return s.leb(64, True)
    return int.from_bytes(s.bytes(4 if t == F32 else 8), "little")


def check_types(types: List[int], what: str, offset: int) -> None:
    for t in types:
        if t not in SIZES:
            raise WasmError(f"{what} has type {type_name(t)}; only i32, i64, f32, and f64 are"
                            " supported", offset)


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


def parse_limits(s: Reader, what: str) -> Tuple[int, Optional[int]]:
    """Reads limits: the minimum, and the maximum if there is one."""
    at = s.pos
    flags = s.byte()
    if flags not in (0, 1):
        raise WasmError(f"a shared or 64-bit {what} is not supported", at)
    minimum = s.u32()
    return minimum, (s.u32() if flags == 1 else None)


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
            if name.startswith("_"):
                # Clang imports such names for routines that the runtime
                # library does not have (§9.4), for example __multi3 for
                # __int128 and __addtf3 for long double.
                raise WasmError(f"{what}: names that start with _ are reserved for the runtime"
                                " library, which has no routines for C's long double and __int128", at)
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
            m.table_size = parse_limits(s, "table")[0]
    elif sec_id == 5:
        count = s.u32()
        if count > 1:
            raise WasmError("a module may have only one memory", sec_start)
        if count == 1:
            m.memory_pages, m.memory_max = parse_limits(s, "memory")
    elif sec_id == 6:
        for i in range(s.u32()):
            at = s.pos
            t = s.byte()
            check_types([t], f"global {i}", at)
            at = s.pos
            mut = s.byte()
            if mut not in (0, 1):
                raise WasmError(f"global {i}: the mutability must be 0 or 1, not {mut}", at)
            mutable = mut == 1
            at = s.pos
            # The constant instruction of the type, then end. extended-const
            # allows expressions, which are not supported.
            what = f"global {i}: the initial value must be an {type_name(t)}.const"
            if s.byte() != CONST_OPS[t]:
                raise WasmError(what, at)
            init = read_const(s, t)
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


def negate(cond: str) -> str:
    """The opposite of a condition such as Z or !Z (§3)."""
    return cond[1:] if cond.startswith("!") else "!" + cond


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


def load_helper(n: int) -> List[str]:
    """W.load4 or W.load8: loads the n bytes at byte address R1, which is
    in the memory, into R1, or for n = 8 into R1 and R2, low word first.
    Uses R2-R6. A word of the memory holds four bytes, the lowest address
    in the low byte (§9.4). The inline code takes the accesses at a
    multiple of 4, and these the others."""
    mem = "@___wasm_memory"
    name = f"W.load{n}"
    out = [f"; {name}: loads {n} bytes from byte address R1.", name]
    if n == 8:
        return out + [
            instr("SHR", "R5", "R1", "2"),               # word index
            instr("AND[M]", "R3", "R1", "3"),            # byte in the word
            instr("MOVE", "R1", f"{mem}[R5]"),
            instr("MOVE", "R2", f"{mem}+1[R5]"),
            instr("?Z MOVE", "R15", "@R13++"),
            instr("SHL", "R3", "R3", "3"),               # s = 8 * byte
            instr("SUB", "R4", "32", "R3"),              # 32 - s
            instr("SHR", "R1", "R1", "R3"),
            instr("SHL", "R6", "R2", "R4"),
            instr("OR", "R1", "R1", "R6"),
            instr("SHR", "R2", "R2", "R3"),
            instr("SHL", "R6", f"{mem}+2[R5]", "R4"),
            instr("OR", "R2", "R2", "R6"),
            instr("MOVE", "R15", "@R13++")]
    return out + [
        instr("SHR", "R2", "R1", "2"),
        instr("AND[M]", "R3", "R1", "3"),
        instr("MOVE", "R1", f"{mem}[R2]"),
        instr("?Z MOVE", "R15", "@R13++"),
        instr("SHL", "R3", "R3", "3"),
        instr("SHR", "R1", "R1", "R3"),
        instr("SUB", "R3", "32", "R3"),
        instr("SHL", "R4", f"{mem}+1[R2]", "R3"),
        instr("OR", "R1", "R1", "R4"),
        instr("MOVE", "R15", "@R13++")]


def store_helper(n: int) -> List[str]:
    """W.store4 or W.store8: stores R2, or for n = 8 R2 and R3, at byte
    address R1, which is in the memory. Uses R1-R6. A word that the store
    fills only in part is read, changed, and written back once."""
    mem = "@___wasm_memory"
    name = f"W.store{n}"
    out = [f"; {name}: stores {n} bytes at byte address R1.", name,
           instr("SHR", "R4", "R1", "2")]                # word index
    if n == 8:
        return out + [
            instr("AND[M]", "R1", "R1", "3"),            # byte in the word
            instr("?Z MOVE", f"{mem}[R4]", "R2"),
            instr("?Z MOVE", f"{mem}+1[R4]", "R3"),
            instr("?Z MOVE", "R15", "@R13++"),
            instr("SHL", "R1", "R1", "3"),               # s = 8 * byte
            # The first word keeps its low s bits.
            instr("SHL", "R5", "-1", "R1"),
            instr("IAND", "R5", "R5", f"{mem}[R4]"),
            instr("SHL", "R6", "R2", "R1"),
            instr("OR", f"{mem}[R4]", "R5", "R6"),
            # The middle word is all new.
            instr("SUB", "R5", "32", "R1"),              # 32 - s
            instr("SHR", "R2", "R2", "R5"),
            instr("SHL", "R6", "R3", "R1"),
            instr("OR", f"{mem}+1[R4]", "R2", "R6"),
            # The last word keeps all but its low s bits.
            instr("SHR", "R3", "R3", "R5"),
            instr("SHR", "R6", "-1", "R5"),
            instr("IAND", "R6", "R6", f"{mem}+2[R4]"),
            instr("OR", f"{mem}+2[R4]", "R6", "R3"),
            instr("MOVE", "R15", "@R13++")]
    return out + [
        instr("AND[M]", "R3", "R1", "3"),
        instr("?Z MOVE", f"{mem}[R4]", "R2"),
        instr("?Z MOVE", "R15", "@R13++"),
        instr("SHL", "R3", "R3", "3"),
        instr("SHL", "R5", "-1", "R3"),
        instr("IAND", "R5", "R5", f"{mem}[R4]"),
        instr("SHL", "R6", "R2", "R3"),
        instr("OR", f"{mem}[R4]", "R5", "R6"),
        instr("SUB", "R3", "32", "R3"),
        instr("SHR", "R5", "-1", "R3"),
        instr("IAND", "R5", "R5", f"{mem}+1[R4]"),
        instr("SHR", "R6", "R2", "R3"),
        instr("OR", f"{mem}+1[R4]", "R5", "R6"),
        instr("MOVE", "R15", "@R13++")]


def rotl64_body() -> List[str]:
    """Rotates R1 (low) and R2 (high) left by R3. A rotate by n >= 32 is a
    rotate of the swapped words by n - 32."""
    return [instr("AND[M]", "R0", "R3", "32"),               # Z = (n mod 64) < 32
            instr("AND", "R3", "R3", "31"),                  # k
            instr("MOVE", "R4", "R1"),                       # x
            instr("MOVE", "R5", "R2"),                       # y
            instr("?!Z MOVE", "R4", "R2"),
            instr("?!Z MOVE", "R5", "R1"),
            instr("SUB", "R6", "32", "R3"),
            # lo' = x << k | y >> (32 - k), hi' = y << k | x >> (32 - k).
            instr("SHL", "R1", "R4", "R3"),
            instr("SHR", "R2", "R5", "R6"),
            instr("OR", "R1", "R1", "R2"),
            instr("SHL", "R2", "R5", "R3"),
            instr("SHR", "R6", "R4", "R6"),
            instr("OR", "R2", "R2", "R6"),
            instr("MOVE", "R15", "@R13++")]


def shift64_helper(op: str) -> List[str]:
    """W.shl64, W.shr_u64, W.shr_s64, W.rotl64, or W.rotr64: shifts or
    rotates the i64 in R1 (low) and R2 (high) by R3 modulo 64, and returns
    it in R1 and R2. Uses R3-R6. A NICE shift uses its full count, so a
    count of 32 or more, or a "negative" one like 32 - n for n > 32,
    shifts out every bit (§5.2). That makes the logical shifts
    branch-free."""
    name = f"W.{op}64"
    out = [f"; {name}: i64.{op} of R1 and R2 by R3.", name]
    if op in ("shl", "shr_u"):
        # shl: hi' = hi << n | lo >> (32 - n) | lo << (n - 32), lo' = lo << n.
        # shr_u is the mirror image, with the words swapped.
        near, far = ("R1", "R2") if op == "shl" else ("R2", "R1")
        fwd, back = ("SHL", "SHR") if op == "shl" else ("SHR", "SHL")
        return out + [
            instr("AND", "R3", "R3", "63"),                  # n
            instr("SUB", "R4", "32", "R3"),
            instr("SUB", "R5", "R3", "32"),
            instr(back, "R6", near, "R4"),
            instr(fwd, "R4", near, "R5"),
            instr("OR", "R6", "R6", "R4"),
            instr(fwd, "R4", far, "R3"),
            instr("OR", far, "R6", "R4"),
            instr(fwd, near, near, "R3"),
            instr("MOVE", "R15", "@R13++")]
    if op == "shr_s":
        # hi' = hi >>s n, which is all sign bits for n >= 32. lo' is
        # hi >>s (n - 32) for n >= 32, else lo >> n | hi << (32 - n).
        return out + [
            instr("AND", "R3", "R3", "63"),                  # n
            instr("SUB", "R4", "R3", "32"),
            instr("C<0[M]", "R0", "R2", "1"),                # C = the sign bit
            instr("C>0", "R5", "R2", "R4"),
            instr("C>0", "R6", "R2", "R3"),
            instr("SUB[M]", "R0", "R3", "32"),               # C = n < 32
            instr("?C SUB", "R4", "32", "R3"),
            instr("?C SHR", "R5", "R1", "R3"),
            instr("?C SHL", "R4", "R2", "R4"),
            instr("?C OR", "R5", "R5", "R4"),
            instr("MOVE", "R1", "R5"),
            instr("MOVE", "R2", "R6"),
            instr("MOVE", "R15", "@R13++")]
    if op == "rotr":
        out.append(instr("SUB", "R3", "0", "R3"))            # rotr by n is rotl by -n
    return out + rotl64_body()


# Functions that memory.fill and memory.copy call, emitted once each if a
# function uses them. They take byte addresses and a byte count, which the
# caller has checked. Each byte or whole word is a pass of a loop: a word
# when the addresses are at a multiple of 4 and 4 or more bytes are left.
HELPERS: Dict[str, List[str]] = {
    "W.grow": [
        "; W.grow: memory.grow. Grows the memory by R1 pages, if that stays within",
        "; the cap, sets the new pages to 0, and returns the old size in R1. Else",
        "; it returns -1.",
        "W.grow",
        instr("MOVE[M]", "R0", "R1"),
        instr("?Z MOVE", "R1", "@W.pages"),                # growing by 0
        instr("?Z MOVE", "R15", "@R13++"),
        instr("MOVE", "R2", "W.CAP"),
        instr("SUB", "R2", "R2", "@W.pages"),              # pages left
        instr("SUB[M]", "R0", "R2", "R1"),                 # C = R2 < R1
        instr("?C MOVE", "R1", "-1"),
        instr("?C MOVE", "R15", "@R13++"),
        instr("MOVE", "R3", "@W.pages"),                   # the old size
        instr("ADD", "@W.pages", "R3", "R1"),
        instr("SHL", "R4", "R3", "14"),                    # 16384 words a page
        instr("ADD", "R4", "R4", "___wasm_memory"),
        instr("SHL", "R5", "R1", "10"),                    # 1024 passes of 16 words a page
        "W.grow.zero",
        *[instr("MOVE", "@R4++", "R0")] * ZERO_UNROLL,
        instr("DEC[M]", "R5", "R5"),
        instr("?!Z MOVE", "R15", "W.grow.zero"),
        instr("MOVE", "R2", "@W.pages"),
        instr("SHL", "R2", "R2", "16"),                    # the new size in bytes
        instr("ADD", "@W.limit0", "R2", "1"),
        instr("MOVE", "@W.limit1", "R2"),
        instr("SUB", "@W.limit2", "R2", "1"),
        instr("SUB", "@W.limit4", "R2", "3"),
        instr("SUB", "@W.limit8", "R2", "7"),
        instr("SHR", "R4", "R2", "2"),                     # the new size in words
        instr("MOVE", "@W.wlimit4", "R4"),
        instr("SUB", "@W.wlimit8", "R4", "1"),
        instr("MOVE", "R1", "R3"),
        instr("MOVE", "R15", "@R13++"),
    ],
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
for _op in ("shl", "shr_u", "shr_s", "rotl", "rotr"):
    HELPERS[f"W.{_op}64"] = shift64_helper(_op)
for _n in (4, 8):
    HELPERS[f"W.store{_n}"] = store_helper(_n)
    HELPERS[f"W.load{_n}"] = load_helper(_n)
for _code in range(1, 8):
    HELPERS[f"W.trap{_code}"] = [f"; W.trap{_code}: traps with code {_code}, and R2 as it is.",
                                 f"W.trap{_code}", instr("MOVE", "R1", str(_code)),
                                 instr("MOVE", "R15", "@___wasm_trap_vector")]

# The registers that each helper may change. It reads its arguments from R1
# up. None uses R7 or above, so values in those survive a call of it.
HELPER_REGS = {name: frozenset(re.findall(r"\bR(?:1[0-2]|[1-9])\b", "\n".join(lines)))
               for name, lines in HELPERS.items()}
assert all(r in CALLER_SAVED for regs in HELPER_REGS.values() for r in regs)

# Tables that the inline code of the loads and stores of 1 and 2 bytes
# index by the byte p of the address in its word, emitted once each if a
# function uses them: name -> (what entry p is, the entries).
TABLES: Dict[str, Tuple[str, List[int]]] = {
    "bshift": ("the shift that brings byte p of a word down to bit 0", [0, 8, 16, 24]),
    "bshl": ("the shift that brings byte p of a word up to bit 24", [24, 16, 8, 0]),
    "bmask": ("the bits of byte p", [0xFF, 0xFF00, 0xFF0000, 0xFF000000]),
    "hmask": ("the bits of bytes p and p + 1", [0xFFFF, 0xFFFF00, 0xFFFF0000]),
}


# A register name in an operand: R0 to R15, or a virtual register %vN.
REG_NAME = r"(?:R1[0-5]|R[0-9]|%v\d+)"
OPERAND_RE = re.compile(rf"@?(?:--({REG_NAME})|({REG_NAME})(?:\+\+|--)|({REG_NAME})|.*\[({REG_NAME})\])\Z")
VREG_RE = re.compile(r"%v\d+")


def operand_reg(op: str) -> Tuple[str, Optional[str]]:
    """The register in an operand, and how the operand uses it (§4): "reg"
    for the register itself, "mem" when it only gives an address, or
    "side" when the operand also increments or decrements it. An operand
    without a register, a constant or @constant, gives ("", None)."""
    m = OPERAND_RE.match(op)
    if not m:
        return "", None
    pre, post, plain, base = m.groups()
    if pre or post:
        return "side", pre or post
    if plain:
        return ("mem" if op.startswith("@") else "reg"), plain
    return "mem", base


def has_word(op: str) -> bool:
    """Whether an operand takes a constant word (§2.3): c, @c, c[Rx], and
    @c[Rx] do."""
    kind, _ = operand_reg(op)
    return kind == "" or "[" in op


def sets_flags(ins: Ins) -> bool:
    """Whether an instruction has the M bit, as in ADD[M] or SUB[CM]."""
    return "[" in ins.op and "M" in ins.op.split("[", 1)[1]


def with_m(op: str) -> str:
    """The mnemonic op with the M bit added: ADD gives ADD[M], ADD[C] gives
    ADD[CM]."""
    return op[:-1] + "M]" if op.endswith("]") else op + "[M]"


# The flags of §6 that instructions set and test.
FLAGS = frozenset("XCZNV")

# The shifts whose fill bit is C, which they read (§5.2). A shift whose
# bit shifted out goes to C reads it too when the count is 0, so every
# shift with C in its name counts as a reader.
SHIFT_NAMES = frozenset(["0<0", "0<1", "0<C", "C<0", "C<1", "C<C", "<<<", "C<<", "0>0", "1>0",
                         "C>0", "0>C", "1>C", "C>C", ">>>", ">>C", "SHL", "ROL", "BPL", "SHR",
                         "ROR", "BPR"])

# The operations whose M bit sets C and V to 0, as MOVE[M] does: the
# logic operations (§5.1), and the shifts whose bit shifted out is
# discarded (§5.2). With M, any of them sets the flags from its result
# exactly as a MOVE[M] of the result would.
LIKE_MOVE = frozenset(["MOVE", "NOT", "NOR", "IAND", "NAND", "XOR", "IOR", "XNOR", "AND", "ONE",
                       "OR", "0<0", "0<1", "0<C", "<<<", "0>0", "1>0", "C>0", ">>>", "SHL", "ROL",
                       "SHR", "ROR"])

# The operations that may get the M bit: those of LIKE_MOVE, and the
# arithmetic ones, which set C and V from the operation.
ALU_NAMES = frozenset(["MOVE", "SUB", "MDBL", "ADD", "DBL", "DEC", "NOT", "NOR", "IAND", "NAND",
                       "XOR", "IOR", "XNOR", "AND", "ONE", "OR"])


def flag_use_def(ins: Ins) -> Tuple[FrozenSet[str], FrozenSet[str]]:
    """The flags (§6) that an instruction reads, and those that it surely
    writes. A conditional instruction may not write them, so its writes do
    not count. A call changes them all (§9.3). An operand that reads R14
    reads them all."""
    uses: set[str] = set()
    cond = ins.cond.lstrip("!")
    if cond in FLAGS:
        uses.add(cond)
    base, _, mods = ins.op.partition("[")
    if "C" in mods or (base in SHIFT_NAMES and "C" in base):
        uses.add("C")
    for k, o in enumerate(ins.ops):
        kind, r = operand_reg(o)
        if r == "R14" and (k > 0 or kind != "reg"):
            uses |= FLAGS
    if ins.kind == "call":
        return frozenset(uses), FLAGS
    if ins.cond or ins.kind:
        return frozenset(uses), frozenset()
    dest = ins.ops[0] if ins.ops else ""
    if dest in ("R14", "R14++", "R14--") or sets_flags(ins):
        return frozenset(uses), FLAGS
    return frozenset(uses), frozenset()


# The most instructions that a multiplication by a constant may take as
# shifts, additions, and subtractions (mul_plan). The math unit takes
# three instructions, but its product comes some 35 cycles after the
# operands on the FPGA core (ISA.md §8.4, doc/MICROARCH.md), while each of
# these takes one. Eight cover the FNV prime 16777619 = 2^24 + 13 * 31,
# and any constant with up to four bits set.
MUL_STEPS = 8

# The most steps for the product of a word with a word of an i64 constant
# (mul64_const). These run while the math unit computes another product,
# which takes some 35 cycles, so they cost little up to about that many.
MUL64_STEPS = 16

# A step of a multiplication by a constant: ("shl", a, k) is value a
# shifted left by k, ("add", a, b) and ("sub", a, b) are a + b and a - b.
# Value 0 is the number multiplied, value -1 is 0, and value i + 1 is the
# result of step i.
Step = Tuple[str, int, int]


@functools.lru_cache(maxsize=None)
def mul_plan(c: int, budget: int) -> Optional[Tuple[Step, ...]]:
    """The fewest steps, at most budget, that multiply a number x by c,
    modulo 2^32, or None if there are none. A search over the ways to make
    c from a smaller m: c = m * 2^k, m + 1, m - 1, 1 - m, -m, m * (2^k +
    1), m * (2^k - 1), 2^k + m, and 2^k - m, each of which takes one or
    two steps after those that make m. c = 1 takes none."""
    c &= 0xFFFFFFFF
    if c == 1:
        return ()
    if budget <= 0 or c == 0:
        return None
    # (m, how c comes from m * x, a shift count).
    ways: List[Tuple[int, str, int]] = []
    if c >> 31:
        ways.append((-c, "neg", 0))
    if c % 2 == 0:
        tz = (c & -c).bit_length() - 1
        ways.append((c >> tz, "shl", tz))
    elif c >> 31:
        ways.append((1 - c, "x-y", 0))
    else:
        ways.append((c - 1, "y+x", 0))
        ways.append((c + 1, "y-x", 0))
        for k in range(1, 31):
            for f, how in (((1 << k) + 1, "y*(2^k+1)"), ((1 << k) - 1, "y*(2^k-1)")):
                if 1 < f < c and c % f == 0:
                    ways.append((c // f, how, k))
        k = c.bit_length() - 1
        ways.append((c - (1 << k), "2^k+y", k))
        ways.append(((2 << k) - c, "2^k-y", k + 1))
    best: Optional[Tuple[Step, ...]] = None
    for m, how, k in ways:
        n = 2 if "^" in how else 1
        limit = budget - n if best is None else min(budget, len(best) - 1) - n
        sub = mul_plan(m & 0xFFFFFFFF, limit) if limit >= 0 else None
        if sub is None:
            continue
        y = len(sub)  # the index of m * x
        after: List[Step] = {
            "neg": [("sub", -1, y)], "shl": [("shl", y, k)], "x-y": [("sub", 0, y)],
            "y+x": [("add", y, 0)], "y-x": [("sub", y, 0)],
            "y*(2^k+1)": [("shl", y, k), ("add", y + 1, y)],
            "y*(2^k-1)": [("shl", y, k), ("sub", y + 1, y)],
            "2^k+y": [("shl", 0, k), ("add", y + 1, y)],
            "2^k-y": [("shl", 0, k), ("sub", y + 1, y)]}[how]
        best = sub + tuple(after)
    return best


class Allocator:
    """Gives the virtual registers of a function's code physical registers
    or frame words, by iterated register coalescing (George and Appel,
    "Iterated register coalescing", 1996): Chaitin-Briggs graph colouring,
    with conservative coalescing of moves by the Briggs and George tests,
    also with the physical registers that calls and the ABI demand.

    The code is a list of items. An instruction's register uses and defs
    come from its operands (operand_reg), and for a call or an exit also
    from the registers it names. A conditional instruction may leave its
    destination as it was, so it also uses it. A virtual register that
    gets no colour is spilled to a frame word, %sN, which becomes
    @k[R13] when the frame is laid out (frame_words). NICE takes a memory
    operand almost anywhere, so a spilled register is usually used in
    place. Only where it is an address, or changed by a side effect, does
    a short-lived temporary take its place, and the colouring runs again.

    Spill costs weight each use and def by 10 for each loop around it, so
    the registers go to the values used in the inner loops."""

    def __init__(self, items: List[Item], regs: List[str], callee_saved: List[str],
                 n_vregs: int) -> None:
        self.items = items
        self.regs = regs                   # the allocatable registers, in order of preference
        self.callee_saved = callee_saved   # those that the function must save if it uses them
        self.k = len(regs)
        self.precolored = set(regs)
        self.n_slots = 0                   # frame words for spilled registers, %s0 up
        self.temps: set[str] = set()       # temporaries of spill code, which must not spill
        self.n_vregs = n_vregs             # the virtual registers so far, %v0 up

    def tracked(self, r: str) -> bool:
        return r.startswith("%") or r in self.precolored

    def use_def(self, ins: Ins) -> Tuple[set[str], set[str]]:
        """The registers that an instruction reads and writes."""
        uses = set(ins.uses)
        defs = set(ins.defs)
        for i, o in enumerate(ins.ops):
            kind, r = operand_reg(o)
            if r is None or not self.tracked(r):
                continue
            if kind == "side":
                uses.add(r)
                defs.add(r)
            elif kind == "mem" or i > 0:
                uses.add(r)
            else:
                defs.add(r)
        if ins.cond:
            uses |= defs  # a def that may not happen keeps the old value
        return uses, defs

    def is_move(self, ins: Ins) -> bool:
        """Whether an instruction is a copy of one register to another,
        which coalescing may remove."""
        if ins.op != "MOVE" or ins.cond or len(ins.ops) != 2:
            return False
        a, b = (operand_reg(o) for o in ins.ops)
        return (a[0] == "reg" and b[0] == "reg" and a[1] is not None and b[1] is not None
                and self.tracked(a[1]) and self.tracked(b[1]))

    # Control flow and liveness.

    def flow(self) -> None:
        """Finds the instructions, their successors, and the basic blocks."""
        self.code = [it for it in self.items if isinstance(it, Ins)]
        label_at: Dict[str, int] = {}
        n = 0
        for it in self.items:
            if isinstance(it, Label):
                label_at[it.name] = n
            elif isinstance(it, Ins):
                n += 1
        self.ud = [self.use_def(ins) for ins in self.code]
        leaders = {0} | set(label_at.values())
        self.succ: List[List[int]] = []
        for i, ins in enumerate(self.code):
            s: List[int] = []
            if ins.kind == "jump":
                s = [label_at[t] for t in ins.targets]
            elif ins.ops and ins.ops[0] == "R15" and ins.kind == "":
                raise AssertionError(f"a jump that goes nowhere known: {ins.text()}")
            if ins.kind in ("jump", "exit"):
                leaders.add(i + 1)
                if ins.cond:
                    s.append(i + 1)
            else:
                s.append(i + 1)
            self.succ.append([j for j in s if j < len(self.code)])
        starts = sorted(x for x in leaders if x < len(self.code))
        self.blocks = [(a, b) for a, b in zip(starts, starts[1:] + [len(self.code)])]
        block_of = {a: k for k, (a, _) in enumerate(self.blocks)}
        self.bsucc = [sorted({block_of[j] for j in self.succ[b - 1]}) for _, b in self.blocks]

    def liveness(self) -> None:
        """live_out of each block, by iterating to a fixed point."""
        gen: List[set[str]] = []
        kill: List[set[str]] = []
        for a, b in self.blocks:
            g: set[str] = set()
            killed: set[str] = set()
            for i in reversed(range(a, b)):
                uses, defs = self.ud[i]
                g = (g - defs) | uses
                killed |= defs
            gen.append(g)
            kill.append(killed)
        n = len(self.blocks)
        self.live_in: List[set[str]] = [set() for _ in range(n)]
        self.live_out: List[set[str]] = [set() for _ in range(n)]
        changed = True
        while changed:
            changed = False
            for k in reversed(range(n)):
                out: set[str] = set()
                for s in self.bsucc[k]:
                    out |= self.live_in[s]
                inn = gen[k] | (out - kill[k])
                if len(out) != len(self.live_out[k]) or len(inn) != len(self.live_in[k]):
                    self.live_out[k], self.live_in[k] = out, inn
                    changed = True

    def flag_liveness(self) -> None:
        """The flags that may be read after each instruction before they
        are written again (flag_use_def), in flags_after."""
        fud = [flag_use_def(ins) for ins in self.code]
        n = len(self.blocks)
        live_in: List[FrozenSet[str]] = [frozenset()] * n
        changed = True
        while changed:
            changed = False
            for k in reversed(range(n)):
                a, b = self.blocks[k]
                live: FrozenSet[str] = frozenset().union(*(live_in[s] for s in self.bsucc[k]))
                for i in reversed(range(a, b)):
                    uses, defs = fud[i]
                    live = (live - defs) | uses
                if live != live_in[k]:
                    live_in[k] = live
                    changed = True
        self.flags_after: List[FrozenSet[str]] = [frozenset()] * len(self.code)
        for k, (a, b) in enumerate(self.blocks):
            live = frozenset().union(*(live_in[s] for s in self.bsucc[k]))
            for i in reversed(range(a, b)):
                self.flags_after[i] = live
                uses, defs = fud[i]
                live = (live - defs) | uses
        self.flag_ud = fud

    def flags_from_results(self) -> bool:
        """Removes a MOVE[M] R0, x that only tests x, by giving the M bit to
        the instruction that computed x instead: x = a + b, MOVE[M] R0, x
        becomes ADD[M] x, a, b. That instruction must be the last to write x
        before the test, in the same basic block, with x as its register
        destination, and no instruction between them may read or write the
        flags. An operation of LIKE_MOVE then sets the flags exactly as the
        MOVE[M] did. An arithmetic one sets C and V from the operation, so
        it qualifies only if neither is read before the next write.
        Returns whether it changed any."""
        self.flag_liveness()
        gone: set[int] = set()
        for a, b in self.blocks:
            for j in range(a, b):
                test = self.code[j]
                if test.op != "MOVE[M]" or test.cond or test.ops[0] != "R0":
                    continue
                kind, x = operand_reg(test.ops[1])
                if kind != "reg" or x is None or not self.tracked(x):
                    continue
                found: Optional[Ins] = None
                i = j - 1
                while True:
                    while i >= a and x not in self.ud[i][1] and not any(self.flag_ud[i]):
                        i -= 1
                    if i < a or x not in self.ud[i][1]:
                        break
                    ins = self.code[i]
                    base, _, mods = ins.op.partition("[")
                    if (ins.cond or ins.kind or "M" in mods or ins.ops[0] != x
                            or any(operand_reg(o)[0] == "side" for o in ins.ops)
                            or not (base in ALU_NAMES or base in SHIFT_NAMES)
                            or (base not in LIKE_MOVE and self.flags_after[j] & {"C", "V"})):
                        break
                    found = ins
                    # For a copy x = y, the instruction that computed y
                    # may set the flags instead, so that the copy can go.
                    kind, y = operand_reg(ins.ops[1]) if ins.op == "MOVE" else ("", None)
                    if kind != "reg" or y is None or not self.tracked(y):
                        break
                    x = y
                    i -= 1
                if found is not None:
                    found.op = with_m(found.op)
                    gone.add(j)
        if gone:
            drop = {id(self.code[j]) for j in gone}
            self.items = [it for it in self.items if id(it) not in drop]
        return bool(gone)

    def dead_code(self) -> bool:
        """Removes instructions whose only effect is to write a register
        that is not read afterwards, such as the zeroing of a local that
        is always set before it is used. An instruction that reads memory
        stays, since the read may be a device's (§8.3), and so does one
        that sets the flags, but the latter then writes R0 instead.
        Returns whether it changed any."""
        dead: set[int] = set()
        to_r0 = False
        for k, (a, b) in enumerate(self.blocks):
            live = set(self.live_out[k])
            for i in reversed(range(a, b)):
                ins = self.code[i]
                uses, defs = self.ud[i]
                if ins.kind == "" and len(defs) == 1 and not (defs & live):
                    if not sets_flags(ins) and self.removable(ins):
                        dead.add(i)
                        continue
                    if (sets_flags(ins) and not ins.cond
                            and operand_reg(ins.ops[0]) == ("reg", next(iter(defs)))):
                        ins.ops[0] = "R0"
                        to_r0 = True
                        defs = set()
                live = (live - defs) | uses
        if dead:
            gone = {id(self.code[i]) for i in dead}
            self.items = [it for it in self.items if id(it) not in gone]
        return bool(dead) or to_r0

    def removable(self, ins: Ins) -> bool:
        kind, r = operand_reg(ins.ops[0]) if ins.ops else ("", None)
        if kind != "reg" or r is None or not self.tracked(r):
            return False
        # A read of the math unit has no side effect (§8.4).
        return all(operand_reg(o)[0] in ("reg", "") and not o.startswith("@")
                   or o.startswith("@__mpu.") for o in ins.ops[1:])

    def webs(self) -> None:
        """Splits each virtual register into webs: the sets of its defs
        that reach a common use, with those uses. A local that the wasm
        code uses for unrelated values thus becomes several registers, each
        of which may get its own colour. A def that may leave the old
        value, by its condition or a side effect, joins the webs of the
        defs that reach it."""
        sites: List[Tuple[int, str]] = []    # each def of a virtual register: (instruction, register)
        site_at: Dict[Tuple[int, str], int] = {}
        by_reg: Dict[str, List[int]] = {}
        for i, (_, defs) in enumerate(self.ud):
            for r in sorted(defs):
                if r.startswith("%"):
                    site_at[(i, r)] = len(sites)
                    by_reg.setdefault(r, []).append(len(sites))
                    sites.append((i, r))
        if not any(len(v) > 1 for v in by_reg.values()):
            return
        # Reaching definitions, as sets of sites, by iterating to a fixed point.
        gen: List[set[int]] = []
        kill: List[set[int]] = []
        for a, b in self.blocks:
            g: Dict[str, int] = {}
            for i in range(a, b):
                for r in self.ud[i][1]:
                    if r.startswith("%"):
                        g[r] = site_at[(i, r)]
            gen.append(set(g.values()))
            kill.append({x for r in g for x in by_reg[r]})
        n = len(self.blocks)
        preds: List[List[int]] = [[] for _ in range(n)]
        for k in range(n):
            for s in self.bsucc[k]:
                preds[s].append(k)
        r_in: List[set[int]] = [set() for _ in range(n)]
        r_out: List[set[int]] = [set(g) for g in gen]
        changed = True
        while changed:
            changed = False
            for k in range(n):
                inn: set[int] = set()
                for p in preds[k]:
                    inn |= r_out[p]
                if len(inn) != len(r_in[k]):
                    r_in[k] = inn
                    out = gen[k] | (inn - kill[k])
                    if len(out) != len(r_out[k]):
                        r_out[k] = out
                        changed = True
        # Join the sites that reach a common use.
        parent = list(range(len(sites)))

        def find(x: int) -> int:
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        use_web: Dict[Tuple[int, str], int] = {}  # (instruction, register) -> a site
        for k, (a, b) in enumerate(self.blocks):
            cur: Dict[str, List[int]] = {}
            for x in sorted(r_in[k]):
                cur.setdefault(sites[x][1], []).append(x)
            for i in range(a, b):
                uses, defs = self.ud[i]
                ins = self.code[i]
                for r in uses:
                    if r.startswith("%") and cur.get(r):
                        first = cur[r][0]
                        for x in cur[r][1:]:
                            parent[find(x)] = find(first)
                        use_web[(i, r)] = first
                        if r in defs and (ins.cond or any(
                                kind == "side" and reg == r
                                for kind, reg in map(operand_reg, ins.ops))):
                            parent[find(site_at[(i, r)])] = find(first)
                for r in defs:
                    if r.startswith("%"):
                        cur[r] = [site_at[(i, r)]]
        # Rename every web but the first of each register.
        name: Dict[int, str] = {}
        for r, xs in by_reg.items():
            roots = sorted({find(x) for x in xs})
            for j, root in enumerate(roots):
                name[root] = r if j == 0 else self.new_vreg()
        for i, ins in enumerate(self.code):
            ops = []
            for pos, o in enumerate(ins.ops):
                kind, reg = operand_reg(o)
                if reg is not None and reg.startswith("%"):
                    r = reg
                    if pos == 0 and kind == "reg" and (i, r) in site_at:
                        new = name[find(site_at[(i, r)])]
                    elif (i, r) in use_web:
                        new = name[find(use_web[(i, r)])]
                    elif (i, r) in site_at:
                        new = name[find(site_at[(i, r)])]
                    else:
                        new = r  # read before any def, as by MOVE[M] R0 of a dead value
                    o = VREG_RE.sub(new, o)
                ops.append(o)
            ins.ops = ops

    # The colouring (George and Appel's names).

    def build(self) -> None:
        self.adj_set: set[Tuple[str, str]] = set()
        self.adj_list: Dict[str, set[str]] = {}
        self.degree: Dict[str, int] = {}
        self.move_list: Dict[str, set[int]] = {}
        self.moves: List[Tuple[str, str]] = []    # move i: (dest, src)
        self.worklist_moves: set[int] = set()
        self.cost: Dict[str, float] = {}
        for r in self.precolored:
            self.degree[r] = 1 << 30
        for i, ins in enumerate(self.code):
            uses, defs = self.ud[i]
            w = 10.0 ** min(ins.depth, 8)
            for r in uses | defs:
                if r.startswith("%"):
                    if r not in self.adj_list:
                        self.adj_list[r] = set()
                        self.degree[r] = 0
                        self.move_list[r] = set()
                    self.cost[r] = self.cost.get(r, 0.0) + (float("inf") if r in self.temps else w)
        for k, (a, b) in enumerate(self.blocks):
            live = set(self.live_out[k])
            for i in reversed(range(a, b)):
                ins = self.code[i]
                uses, defs = self.ud[i]
                if self.is_move(ins):
                    live -= uses
                    m = len(self.moves)
                    self.moves.append((ins.ops[0], ins.ops[1]))
                    for r in (ins.ops[0], ins.ops[1]):
                        self.move_list.setdefault(r, set()).add(m)
                    self.worklist_moves.add(m)
                live |= defs
                for d in defs:
                    for v in live:
                        self.add_edge(v, d)
                live = uses | (live - defs)
        self.adj0 = {n: set(s) for n, s in self.adj_list.items()}

    def add_edge(self, u: str, v: str) -> None:
        if u != v and (u, v) not in self.adj_set:
            self.adj_set.add((u, v))
            self.adj_set.add((v, u))
            if u not in self.precolored:
                self.adj_list[u].add(v)
                self.degree[u] += 1
            if v not in self.precolored:
                self.adj_list[v].add(u)
                self.degree[v] += 1

    def color_graph(self) -> None:
        self.simplify_wl: set[str] = set()
        self.freeze_wl: set[str] = set()
        self.simplify_heap: List[int] = []
        self.freeze_heap: List[int] = []
        self.moves_heap = sorted(self.worklist_moves)
        self.spill_wl: set[str] = set()
        self.spilled: set[str] = set()
        self.coalesced: set[str] = set()
        self.colored: set[str] = set()
        self.select: List[str] = []
        self.on_stack: set[str] = set()
        self.alias: Dict[str, str] = {}
        self.color: Dict[str, str] = {r: r for r in self.precolored}
        self.coalesced_moves: set[int] = set()
        self.constrained_moves: set[int] = set()
        self.frozen_moves: set[int] = set()
        self.active_moves: set[int] = set()
        for n in sorted(self.adj_list, key=lambda v: int(v[2:])):
            if self.degree[n] >= self.k:
                self.spill_wl.add(n)
            elif self.move_related(n):
                self.to_freeze(n)
            else:
                self.to_simplify(n)
        while True:
            if self.simplify_wl:
                self.simplify()
            elif self.worklist_moves:
                self.coalesce()
            elif self.freeze_wl:
                self.freeze()
            elif self.spill_wl:
                self.select_spill()
            else:
                break
        self.assign_colors()

    def adjacent(self, n: str) -> set[str]:
        return {m for m in self.adj_list[n] if m not in self.on_stack and m not in self.coalesced}

    def node_moves(self, n: str) -> set[int]:
        return {m for m in self.move_list.get(n, set())
                if m in self.active_moves or m in self.worklist_moves}

    def move_related(self, n: str) -> bool:
        return bool(self.node_moves(n))

    def to_simplify(self, n: str) -> None:
        if n not in self.simplify_wl:
            self.simplify_wl.add(n)
            heapq.heappush(self.simplify_heap, int(n[2:]))

    def to_freeze(self, n: str) -> None:
        if n not in self.freeze_wl:
            self.freeze_wl.add(n)
            heapq.heappush(self.freeze_heap, int(n[2:]))

    def to_coalesce(self, m: int) -> None:
        if m not in self.worklist_moves:
            self.worklist_moves.add(m)
            heapq.heappush(self.moves_heap, m)

    @staticmethod
    def first(heap: List[int], members: Union[set[str], set[int]], prefix: str) -> Any:
        """The lowest-numbered member of a worklist. The heap holds every
        number added to it, also those that have left the worklist since,
        so that the choice does not depend on the order of a set."""
        while True:
            x = heap[0] if not prefix else f"{prefix}{heap[0]}"
            if x in members:
                return x
            heapq.heappop(heap)

    def simplify(self) -> None:
        n = self.first(self.simplify_heap, self.simplify_wl, "%v")
        self.simplify_wl.remove(n)
        self.select.append(n)
        self.on_stack.add(n)
        for m in self.adjacent(n):
            self.decrement_degree(m)

    def decrement_degree(self, m: str) -> None:
        if m in self.precolored:
            return
        d = self.degree[m]
        self.degree[m] = d - 1
        if d == self.k:
            self.enable_moves({m} | self.adjacent(m))
            self.spill_wl.discard(m)
            if self.move_related(m):
                self.to_freeze(m)
            else:
                self.to_simplify(m)

    def enable_moves(self, nodes: set[str]) -> None:
        for n in nodes:
            for m in self.node_moves(n):
                if m in self.active_moves:
                    self.active_moves.remove(m)
                    self.to_coalesce(m)

    def get_alias(self, n: str) -> str:
        while n in self.coalesced:
            n = self.alias[n]
        return n

    def add_worklist(self, u: str) -> None:
        if u not in self.precolored and not self.move_related(u) and self.degree[u] < self.k:
            self.freeze_wl.discard(u)
            self.to_simplify(u)

    def ok(self, t: str, r: str) -> bool:
        return self.degree[t] < self.k or t in self.precolored or (t, r) in self.adj_set

    def conservative(self, nodes: set[str]) -> bool:
        return sum(1 for n in nodes if self.degree[n] >= self.k) < self.k

    def coalesce(self) -> None:
        m = self.first(self.moves_heap, self.worklist_moves, "")
        self.worklist_moves.remove(m)
        x, y = (self.get_alias(r) for r in self.moves[m])
        u, v = (y, x) if y in self.precolored else (x, y)
        if u == v:
            self.coalesced_moves.add(m)
            self.add_worklist(u)
        elif v in self.precolored or (u, v) in self.adj_set:
            self.constrained_moves.add(m)
            self.add_worklist(u)
            self.add_worklist(v)
        elif (all(self.ok(t, u) for t in self.adjacent(v))
              or (u not in self.precolored
                  and (self.conservative(self.adjacent(u) | self.adjacent(v))
                       or all(self.ok(t, v) for t in self.adjacent(u))))):
            self.coalesced_moves.add(m)
            self.combine(u, v)
            self.add_worklist(u)
        else:
            self.active_moves.add(m)

    def combine(self, u: str, v: str) -> None:
        if v in self.freeze_wl:
            self.freeze_wl.remove(v)
        else:
            self.spill_wl.discard(v)
        self.coalesced.add(v)
        self.alias[v] = u
        self.move_list.setdefault(u, set()).update(self.move_list[v])
        if u not in self.precolored:
            self.cost[u] += self.cost[v]
        self.enable_moves({v})
        for t in self.adjacent(v):
            self.add_edge(t, u)
            self.decrement_degree(t)
        if u not in self.precolored and self.degree[u] >= self.k and u in self.freeze_wl:
            self.freeze_wl.remove(u)
            self.spill_wl.add(u)

    def freeze(self) -> None:
        u = self.first(self.freeze_heap, self.freeze_wl, "%v")
        self.freeze_wl.remove(u)
        self.to_simplify(u)
        self.freeze_moves(u)

    def freeze_moves(self, u: str) -> None:
        for m in self.node_moves(u):
            x, y = self.moves[m]
            v = self.get_alias(x) if self.get_alias(y) == self.get_alias(u) else self.get_alias(y)
            self.active_moves.discard(m)
            self.frozen_moves.add(m)
            if v in self.freeze_wl and not self.node_moves(v) and self.degree[v] < self.k:
                self.freeze_wl.remove(v)
                self.to_simplify(v)

    def select_spill(self) -> None:
        m = min(self.spill_wl, key=lambda v: (self.cost[v] / max(self.degree[v], 1), int(v[2:])))
        self.spill_wl.remove(m)
        self.to_simplify(m)
        self.freeze_moves(m)

    def assign_colors(self) -> None:
        used: set[str] = set()  # the colours given so far
        while self.select:
            n = self.select.pop()
            self.on_stack.discard(n)
            ok = set(self.regs)
            for w in self.adj_list[n]:
                a = self.get_alias(w)
                if a in self.colored or a in self.precolored:
                    ok.discard(self.color[a])
            if not ok:
                self.spilled.add(n)
                continue
            # A colour that a move partner has makes the move go away.
            partners = []
            for m in sorted(self.move_list.get(n, set())):
                for r in self.moves[m]:
                    a = self.get_alias(r)
                    if a != n and (a in self.colored or a in self.precolored):
                        partners.append(self.color[a])
            choice = next((c for c in partners if c in ok), None)
            if choice is None:
                order = ([r for r in self.regs if r not in self.callee_saved]
                         + [r for r in self.callee_saved if r in used]
                         + self.callee_saved)
                choice = next(r for r in order if r in ok)
            self.colored.add(n)
            self.color[n] = choice
            used.add(choice)
        for n in self.coalesced:
            a = self.get_alias(n)
            if a in self.color and a not in self.spilled:
                self.color[n] = self.color[a]

    # Spilling.

    def new_vreg(self) -> str:
        self.n_vregs += 1
        return f"%v{self.n_vregs - 1}"

    def new_temp(self) -> str:
        t = self.new_vreg()
        self.temps.add(t)
        return t

    def spill(self) -> None:
        """Gives each spilled register, with the registers coalesced into
        it, a frame word. Groups that do not interfere share one. Then
        rewrites the code to use the frame words."""
        groups: Dict[str, List[str]] = {n: [n] for n in sorted(self.spilled)}
        for n in self.coalesced:
            a = self.get_alias(n)
            if a in groups:
                groups[a].append(n)
        slot_of: Dict[str, int] = {}
        slot_members: List[set[str]] = []
        first = self.n_slots
        for rep, members in groups.items():
            near: set[str] = set()
            for n in members:
                near |= self.adj0.get(n, set())
            for k, ms in enumerate(slot_members):
                if not (ms & near):
                    break
            else:
                k = len(slot_members)
                slot_members.append(set())
            slot_members[k].update(members)
            for n in members:
                slot_of[n] = first + k
        self.n_slots += len(slot_members)
        out: List[Item] = []
        for it in self.items:
            if not isinstance(it, Ins):
                out.append(it)
                continue
            regs = [operand_reg(o) for o in it.ops]
            need = {r for kind, r in regs if r in slot_of and kind in ("mem", "side")}
            temps = {r: self.new_temp() for r in sorted(need)}
            uses, defs = self.use_def(it)
            before = [Ins("MOVE", [t, f"@%s{slot_of[r]}"], depth=it.depth)
                      for r, t in temps.items() if r in uses]
            after = [Ins("MOVE", [f"@%s{slot_of[r]}", t], depth=it.depth)
                     for r, t in temps.items() if r in defs]
            assert not (before and it.kind == "call"), it.text()
            assert not (after and it.kind), it.text()
            ops = []
            for o, (kind, r) in zip(it.ops, regs):
                if r in temps:
                    o = VREG_RE.sub(lambda mo: temps.get(mo.group(), mo.group()), o)
                elif r in slot_of:
                    assert kind == "reg"
                    o = f"@%s{slot_of[r]}"
                ops.append(o)
            it.ops = ops
            out += before
            out.append(it)
            out += after
        self.items = out

    def run(self) -> List[Item]:
        """Allocates the registers, and returns the code with physical
        registers and frame words %sN in place of the virtual registers."""
        self.flow()
        if self.flags_from_results():
            self.flow()
        self.webs()
        while True:
            self.flow()
            self.liveness()
            if self.dead_code():
                continue
            self.build()
            self.color_graph()
            if not self.spilled:
                break
            self.spill()
        self.used: set[str] = set()  # the physical registers that the code uses
        for it in self.items:
            if isinstance(it, Ins):
                it.ops = [VREG_RE.sub(lambda mo: self.color[mo.group()], o) for o in it.ops]
                for o in it.ops:
                    self.used.update(re.findall(r"\bR1[0-2]\b|\bR[1-9]\b", o))
        return self.items


FRAME_WORD = re.compile(r"@%([sa])(\d+)")  # a spill slot or a stack argument, before the frame


def tidy(items: List[Item]) -> List[Item]:
    """Removes what the allocation leaves useless: a MOVE of a register or
    frame word to itself, and a jump to the label that follows it."""
    def self_move(it: Item) -> bool:
        return (isinstance(it, Ins) and it.op == "MOVE" and len(it.ops) == 2
                and it.ops[0] == it.ops[1] and re.match(r"(R\d+|@%s\d+)\Z", it.ops[0]) is not None)

    def falls_to(k: int, label: str) -> bool:
        """Whether the code from item k on reaches label before any
        instruction or data."""
        while k < len(items) and not isinstance(items[k], Ins):
            nxt = items[k]
            if isinstance(nxt, Label) and nxt.name == label:
                return True
            if isinstance(nxt, str) and not nxt.lstrip().startswith(";"):
                return False
            k += 1
        return False

    items = [it for it in items if not self_move(it)]
    return [it for i, it in enumerate(items)
            if not (isinstance(it, Ins) and it.kind == "jump" and it.ops[1:] == it.targets
                    and falls_to(i + 1, it.targets[0]))]


# The most instructions that a conditional jump may skip and still become
# conditional instructions (if_convert), and the most that may come
# before a jump to the end of an if.
IF_CONVERT = 4
IF_CONVERT_ELSE = 2


def if_convert(items: List[Item]) -> List[Item]:
    """Turns a conditional jump over a few instructions into those
    instructions with the opposite condition: ?Z MOVE R15, L, then x and y,
    then L, becomes ?!Z x and ?!Z y. On the FPGA core a taken conditional
    jump costs some five cycles, and a skipped instruction one (doc/
    MICROARCH.md). A skipped instruction makes no access (§3), so the
    instructions may access memory. None of them may write the flags or
    be conditional already, and no label may come between the jump and L,
    which the jump must reach first. A jump that ends the skipped code,
    to the end of an if with an else, becomes conditional too, if the
    skipped code is shorter."""
    def ins_at(k: int) -> Optional[int]:
        """The next instruction or label from item k on, past comments."""
        while k < len(items):
            it = items[k]
            if not isinstance(it, str):
                return k
            if not it.lstrip().startswith(";"):
                return None
            k += 1
        return None

    out = list(items)
    for i, it in enumerate(items):
        if not (isinstance(it, Ins) and it.kind == "jump" and it.cond and len(it.targets) == 1
                and it.ops[1:] == it.targets):
            continue
        body: List[Ins] = []
        k = ins_at(i + 1)
        while k is not None and isinstance(items[k], Ins) and len(body) <= IF_CONVERT:
            body.append(items[k])  # type: ignore[arg-type]
            k = ins_at(k + 1)
        if k is None or items[k] != Label(it.targets[0]):
            continue
        end = body[-1] if body else None
        if (end is not None and end.kind == "jump" and not end.cond
                and len(body) - 1 <= IF_CONVERT_ELSE):
            body = body[:-1]
        elif len(body) > IF_CONVERT:
            continue
        else:
            end = None
        if not all(b.kind == "" and not b.cond and not flag_use_def(b)[1]
                   and "R14" not in (operand_reg(o)[1] for o in b.ops) for b in body):
            continue
        for b in body + ([end] if end is not None else []):
            b.cond = negate(it.cond)
        out[i] = ""
    return [x for x in out if x != ""]


# The most instructions of the code that a jump goes to, which then takes
# the jump's place (duplicate_tails), and the most if that code ends in
# the jump of a br_table.
TAIL_COPY = 3
TAIL_COPY_TABLE = 12


def label_refs(items: List[Item]) -> Dict[str, int]:
    """How often each label is named: as a jump's target, in an operand,
    or in a line of text such as .DAT."""
    refs: Dict[str, int] = {}
    for it in items:
        text = ""
        if isinstance(it, Ins):
            text = " ".join(it.ops)
        elif isinstance(it, str) and not it.lstrip().startswith(";"):
            text = it
        for name in re.findall(r"[A-Za-z_][\w.]*", text):
            refs[name] = refs.get(name, 0) + 1
    return refs


def duplicate_tails(items: List[Item], ret_size: int) -> List[Item]:
    """Replaces an unconditional jump to short code that ends in a jump or
    a return by a copy of that code. The copy saves the jump, which costs
    two cycles or more on the FPGA core (doc/MICROARCH.md), and an
    interpreter's dispatch by br_table thus gets a copy at the end of each
    case. The code may have labels in it, which a jump in it, or a trap's
    R2, may name: the copy then goes on in the original, which does the
    same. It may not call. The epilogue, RET, counts as ret_size
    instructions. Two rounds, so that a copy that ends in a jump may get
    a copy too. Then the code that no jump reaches any more goes."""
    for _ in range(2):
        at = {it.name: k for k, it in enumerate(items) if isinstance(it, Label)}
        out: List[Item] = []
        for it in items:
            if not (isinstance(it, Ins) and it.kind == "jump" and not it.cond
                    and len(it.targets) == 1 and it.ops[1:] == it.targets):
                out.append(it)
                continue
            code: List[Ins] = []
            k = at[it.targets[0]] + 1
            while k < len(items):
                x = items[k]
                k += 1
                if isinstance(x, Label) or (isinstance(x, str) and x.lstrip().startswith(";")):
                    continue
                if isinstance(x, str) or x.kind == "call" or x is it:
                    code = []
                    break
                code.append(x)
                if x.kind in ("jump", "exit") and not x.cond:
                    break
            else:
                code = []
            size = sum(ret_size if x.op == "RET" else 1 for x in code)
            table = bool(code) and len(code[-1].targets) > 1
            if not code or size > (TAIL_COPY_TABLE if table else TAIL_COPY):
                out.append(it)
                continue
            out += [Ins(x.op, list(x.ops), x.cond, x.kind, list(x.targets), x.uses, x.defs, x.depth)
                    for x in code]
        items = out
    # Remove the code that no jump reaches: after an unconditional jump or
    # exit, up to the next label that something names.
    refs = label_refs(items)
    out = []
    dead = False
    for it in items:
        if isinstance(it, Label) and refs.get(it.name):
            dead = False
        if dead and not isinstance(it, str):
            continue
        out.append(it)
        if isinstance(it, Ins) and it.kind in ("jump", "exit") and not it.cond:
            dead = True
    return out


def invert_back_edges(items: List[Item], prefix: str) -> List[Item]:
    """Turns the conditional jump back to the start of a loop at its end
    into a conditional jump on the opposite condition to the code after
    it, and an unconditional jump back. On the FPGA core a taken
    conditional jump costs some five cycles more than a skipped one, and
    an unconditional jump to a label two (doc/MICROARCH.md). So each
    round of a loop saves two cycles, and leaving it costs five more.
    If an unconditional jump follows, the two jumps swap their targets
    instead. The new labels are prefix and a number."""
    out: List[Item] = []
    n = 0
    for i, it in enumerate(items):
        if not (isinstance(it, Ins) and it.back and it.kind == "jump" and it.cond
                and len(it.targets) == 1 and it.ops[1:] == it.targets):
            out.append(it)
            continue
        k = i + 1
        while k < len(items) and isinstance(items[k], str) and str(items[k]).lstrip().startswith(";"):
            k += 1
        nxt = items[k] if k < len(items) else None
        back = Ins("MOVE", ["R15", it.targets[0]], "", "jump", [it.targets[0]], depth=it.depth)
        if (isinstance(nxt, Ins) and nxt.kind == "jump" and not nxt.cond and len(nxt.targets) == 1
                and nxt.ops[1:] == nxt.targets):
            out.append(Ins(it.op, ["R15", nxt.targets[0]], negate(it.cond), "jump",
                           [nxt.targets[0]], depth=it.depth))
            items[k] = back
            continue
        name = f"{prefix}{n}"
        n += 1
        out += [Ins(it.op, ["R15", name], negate(it.cond), "jump", [name], depth=it.depth),
                back, Label(name)]
    return out


def reads_memory(ins: Ins) -> bool:
    """Whether an instruction reads memory: a source operand in memory (§4.1)."""
    return any(o.startswith("@") for o in ins.ops[1:])


def fill_jump_slots(items: List[Item]) -> List[Item]:
    """On the FPGA core, a data read waits for a conditional jump just
    before it that is not taken (doc/MICROARCH.md §5.3). If an earlier
    instruction in the same straight-line code can wait instead, it moves
    to between them. It must compute a register from registers only, with
    no flags, and be unconditional. The code it passes must neither read
    nor write that register, nor write its sources, and the register must
    not be live where any jump it passes goes, since it no longer runs
    before those jumps. Nor may the read use the register as its address,
    which would wait for it instead."""
    alloc = Allocator(items, ALLOC_REGS, CALLEE_SAVED, 0)
    alloc.flow()
    alloc.liveness()
    index = {id(ins): i for i, ins in enumerate(alloc.code)}
    block_of = {a: k for k, (a, _) in enumerate(alloc.blocks)}
    live_at: Dict[str, set[str]] = {}
    n = 0
    for it in items:
        if isinstance(it, Label):
            live_at[it.name] = alloc.live_in[block_of[n]] if n in block_of else set()
        elif isinstance(it, Ins):
            n += 1

    def next_item(k: int, step: int) -> int:
        k += step
        while 0 <= k < len(items) and isinstance(items[k], str) and str(items[k]).lstrip().startswith(";"):
            k += step
        return k

    def pure(ins: Ins) -> bool:
        kind, d = operand_reg(ins.ops[0]) if ins.ops else ("", None)
        return (ins.kind == "" and not ins.cond and kind == "reg" and d in alloc.precolored
                and not any(o.startswith("@") for o in ins.ops) and not any(flag_use_def(ins))
                and all(operand_reg(o)[0] in ("reg", "") for o in ins.ops[1:]))

    def fills(k: int) -> bool:
        """Whether items[k] already sits between a jump and a read."""
        a, b = next_item(k, -1), next_item(k, 1)
        return (0 <= a and b < len(items) and isinstance(items[a], Ins) and isinstance(items[b], Ins)
                and items[a].kind == "jump" and bool(items[a].cond)  # type: ignore[union-attr]
                and reads_memory(items[b]))  # type: ignore[arg-type]

    p = 0
    while p < len(items):
        jump, q = items[p], next_item(p, 1)
        p += 1
        if not (isinstance(jump, Ins) and jump.kind == "jump" and jump.cond and q < len(items)):
            continue
        read = items[q]
        if not (isinstance(read, Ins) and reads_memory(read)):
            continue
        bases = {r for kind, r in map(operand_reg, read.ops) if kind in ("mem", "side")}
        used: set[str] = set()     # by the code between the candidate and the read
        written: set[str] = set()
        exits: set[str] = set()    # live where the jumps passed go
        k = p - 1
        while k >= 0:
            it = items[k]
            if isinstance(it, Label) or (isinstance(it, str) and not it.lstrip().startswith(";")):
                break
            if isinstance(it, Ins):
                if it.kind in ("call", "exit"):
                    break
                if it.kind == "jump":
                    for t in it.targets:
                        exits |= live_at.get(t, set(ALLOC_REGS))
                elif pure(it) and not fills(k):
                    d = it.ops[0]
                    srcs = {r for _, r in map(operand_reg, it.ops[1:]) if r is not None}
                    if not ({d} & (exits | bases | used | written)) and not (srcs & written):
                        del items[k]
                        items.insert(q - 1, it)
                        break
                uses, defs = alloc.ud[index[id(it)]]
                used |= uses
                written |= defs
            k -= 1
    return items


def frame_words(items: List[Item], n_slots: int, n_saved: int) -> None:
    """Replaces the frame words %sN of spilled registers and %aN of stack
    arguments by operands relative to SP. The frame has no frame pointer.
    From SP up, after the prologue, it holds the n_slots frame words, the
    n_saved callee-saved registers, the return address, and the stack
    arguments (§9.3). SP moves only in a call sequence: a push of a stack
    argument or of the return address takes it down a word, and the
    return and the ADD R13, R13, n after the call take it back up. depth
    counts the words pushed so far. All sources of an instruction see SP
    as it was before the instruction (§5), so MOVE @--R13, @%s0 reads the
    frame word at the old SP."""
    depth = 0

    def word(mo: re.Match[str]) -> str:
        k = int(mo.group(2))
        if mo.group(1) == "a":
            k += n_slots + n_saved + 1
        return f"@{k + depth}[R13]"

    for it in items:
        if isinstance(it, Label):
            assert depth == 0, it.name
        if not isinstance(it, Ins):
            continue
        it.ops = [FRAME_WORD.sub(word, o) for o in it.ops]
        if it.op == "ADD" and it.ops[:2] == ["R13", "R13"]:
            depth -= int(it.ops[2])
            continue
        for o in it.ops:
            if o == "@--R13":
                depth += 1
            elif "R13" in o:
                assert operand_reg(o)[0] in ("mem", ""), it.text()
        if it.kind == "call":
            depth -= 1  # the return pops the return address
        elif it.op == "RET":
            assert depth == 0
        assert depth >= 0, it.text()


def fix_calls(items: List[Item]) -> None:
    """Sets what each call's ADD @--R13, n, R15 adds to the address after
    it: the size in words of the jump that follows (§9.3), which depends
    on the jump's operand."""
    prev: Optional[Ins] = None
    for it in items:
        if isinstance(it, Ins):
            if it.kind == "call":
                assert prev is not None and prev.op == "ADD" and prev.ops[0] == "@--R13", it.text()
                prev.ops[1] = str(1 + sum(has_word(o) for o in it.ops))
            prev = it
        elif isinstance(it, Label):
            prev = None


class Translator:
    def __init__(self, m: Module, data: bytes, checks: bool = True,
                 library: Optional[str] = None, library_memory: Optional[int] = None,
                 memory_pages: Optional[int] = None, mpu: bool = True) -> None:
        self.m = m
        self.data = data
        self.checks = checks  # bounds checks on memory accesses
        self.mpu = mpu  # use the math unit of §8.4 for i32 mul, and div and rem
        self.library = library  # the name of a library module (§9.4), or None
        self.prefix = f"WL.{library}." if library else "W."  # of the labels made here
        self.mem = f"WL.{library}.memory" if library else "___wasm_memory"
        # The bytes of the memory that are reserved: all of the initial
        # pages for a program, and only the start for a library (§9.4).
        self.mem_bytes: Optional[int] = None
        if m.memory_pages is not None:
            self.mem_bytes = m.memory_pages * WORDS_PER_PAGE * 4
            if library:
                if library_memory is None:
                    # As much as the data and the stack need. A stack
                    # pointer is a mutable i32 global whose initial value
                    # is the top of the stack.
                    ends = [d.offset + len(d.data) for d in m.data]
                    ends += [g.init & 0xFFFFFFFF for g in m.globals if g.type == I32 and g.mutable]
                    library_memory = max(ends, default=0)
                library_memory = (library_memory + 3) // 4 * 4
                if library_memory > self.mem_bytes:
                    raise WasmError(f"the library memory of {library_memory} bytes is larger than"
                                    f" the module's memory of {self.mem_bytes}")
                self.mem_bytes = library_memory
        elif library_memory is not None:
            raise WasmError("--library-memory: the module has no memory")
        # The cap: memory.grow may grow the memory up to it (§9.4). Unless
        # it is above the initial size, the size is a constant.
        self.cap = m.memory_pages
        if memory_pages is not None:
            if m.memory_pages is None:
                raise WasmError("--memory-pages: the module has no memory")
            if memory_pages < m.memory_pages:
                raise WasmError(f"--memory-pages: {memory_pages} is below the memory's initial"
                                f" size, {m.memory_pages}")
            if m.memory_max is not None and memory_pages > m.memory_max:
                raise WasmError(f"--memory-pages: {memory_pages} is above the memory's maximum"
                                f" size, {m.memory_max}")
            if memory_pages >= 65536:
                raise WasmError("--memory-pages: the memory must be below 65536 pages")
            self.cap = memory_pages
        self.growable = self.cap != m.memory_pages
        self.helpers: set[str] = set()  # the HELPERS that functions call
        self.tables: set[str] = set()   # the TABLES that functions use
        self.labels: Dict[int, List[str]] = {}         # function index -> export labels
        self.global_labels: Dict[int, List[str]] = {}  # global index -> export labels
        self.ctors: Optional[int] = None
        n_imports = len(m.imports)
        seen = set()
        # An import from env is called at its label _name (§9.4), so an
        # export may not take the same label.
        imported = {imp.name for imp in m.imports if imp.module == "env"}
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
                    if library:
                        raise WasmError("a library module may not export __wasm_call_ctors")
                    self.ctors = idx
            elif kind == 1 and (idx != 0 or m.table_size is None):
                raise WasmError(f"export {name}: table {idx} does not exist")
            elif kind == 2 and (idx != 0 or m.memory_pages is None):
                raise WasmError(f"export {name}: memory {idx} does not exist")
            elif kind == 3 and idx >= len(m.globals):
                raise WasmError(f"export {name}: global {idx} does not exist")
            elif kind > 3:
                raise WasmError(f"export {name}: only functions, tables, memories, and globals"
                                " can be exported")
            # Names that start with _ are reserved for the runtime library,
            # so only a library module gives them labels (§9.4).
            # Memory and table exports get no label: the memory is at
            # ___wasm_memory, and a function pointer is a table index.
            if kind in (0, 3) and C_IDENT.match(name) and (library or not name.startswith("_")):
                if name in imported:
                    raise WasmError(f"export {name}: the import env.{name} has the same label"
                                    f" _{name}")
                (self.labels if kind == 0 else self.global_labels).setdefault(idx, []).append(f"_{name}")
        if m.start is not None and library:
            raise WasmError("a library module may not have a start function")
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
        return f"{self.prefix}f{idx}"

    def run(self, source: str) -> List[str]:
        source = "".join(c if PRINTABLE.match(c) else "?" for c in source)
        out = [f"; Translated from {source} by nicewasm (doc/ISA.md §9.4)."]
        if self.library:
            out.append(f"; Library module {self.library}.")
        runs = self.memory_runs()
        if not self.library:
            out += self.start(runs)
        n_imports = len(self.m.imports)
        for i, code in enumerate(self.m.codes):
            out.append("")
            out += FunctionTranslator(self, n_imports + i, code).run()
        for name in sorted(self.helpers):
            out += [""] + [line.replace("W.CAP", str(self.cap)).replace("W.", self.prefix)
                           .replace("___wasm_memory", self.mem) for line in HELPERS[name]]
        for name, (what, entries) in TABLES.items():
            if name in self.tables:
                out += ["", f"; {self.prefix}{name}: for p = 0 to {len(entries) - 1}, {what}.",
                        f"{self.prefix}{name}", instr(".DAT", *(f"0x{v:X}" for v in entries))]
        out += self.table()
        if self.m.globals:
            out += ["", "; Globals"]
            for i, g in enumerate(self.m.globals):
                out += self.global_labels.get(i, [])
                out.append(f"{self.prefix}g{i}")
                out += [instr(".DAT", w) for w in words(g.init, g.type)]
        if self.growable:
            assert self.m.memory_pages is not None
            out += ["", "; The memory's size in pages, for each n the first byte address at",
                    "; which n bytes do not fit, or 0 if none do, and for 4 and 8 the same",
                    "; as a word index. W.grow keeps them up to date.",
                    "W.pages", instr(".DAT", str(self.m.memory_pages))]
            for name, v in self.limits(self.m.memory_pages):
                out += [f"W.{name}", instr(".DAT", str(v))]
        if self.m.memory_pages is not None:
            pages = self.m.memory_pages
            if self.library:
                out += ["", f"; Linear memory: the first {self.mem_bytes} bytes of"
                        f" {pages} page{'' if pages == 1 else 's'}"]
            else:
                out += ["", f"; Linear memory: {pages} page{'' if pages == 1 else 's'}"]
            out.append(self.mem)
            for start, values in runs:
                if isinstance(values, list):
                    last = start + len(values) - 1
                    where = f"word {start}" if last == start else f"words {start} to {last}"
                    out.append(f"        ; {where}: data segments")
                    for i in range(0, len(values), 8):
                        out.append(instr(".DAT", *(f"0x{w:08X}" for w in values[i:i + 8])))
                else:
                    # A library's memory is small, so it is in the image.
                    out.append(instr(".BLK" if self.library else ".RES", str(values)))
            if self.growable:
                assert self.cap is not None
                out.append(f"        ; pages {pages} to {self.cap - 1}, for memory.grow")
                out.append(instr(".RES", str((self.cap - pages) * WORDS_PER_PAGE)))
        return out

    @staticmethod
    def limits(pages: int) -> List[Tuple[str, int]]:
        """The words that the bounds checks compare with when the memory
        can grow, and their values for a memory of the given pages. For n
        = 0 (memory.fill and memory.copy, which check the end of a range),
        1, 2, 4, and 8, limitN is the first byte address at which n bytes
        do not fit, or 0 if none do. For n = 4 and 8, wlimitN is the same
        as a word index: the first word at which n bytes do not fit."""
        size = pages * WORDS_PER_PAGE * 4
        return ([(f"limit{n}", max(size - n + 1, 0)) for n in (0, 1, 2, 4, 8)]
                + [(f"wlimit{n}", max((size - n) // 4 + 1, 0)) for n in (4, 8)])

    def start(self, runs: List[Tuple[int, Union[int, List[int]]]]) -> List[str]:
        """___wasm_start, which a program's module always has (§9.4)."""
        out = ["", "; Sets the memory to 0, then calls the start function and",
               "; __wasm_call_ctors, if the module has them.", "___wasm_start"]
        # The words that data segments set are in the program image. The
        # rest of the memory is reserved with .RES, so it is not, and is
        # set to 0 here. Each pass of a loop clears ZERO_UNROLL words.
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
        if self.growable:
            # Back to the initial size, in case the program starts again.
            assert self.m.memory_pages is not None
            out.append(instr("MOVE", "@W.pages", str(self.m.memory_pages)))
            out += [instr("MOVE", f"@W.{name}", str(v))
                    for name, v in self.limits(self.m.memory_pages)]
        for idx in (self.m.start, self.ctors):
            if idx is not None:
                out.append(instr("ADD", "@--R13", "2", "R15"))
                out.append(instr("MOVE", "R15", self.func_label(idx)))
        out.append(instr("MOVE", "R15", "@R13++"))
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
               " address and its type number", f"{self.prefix}table"]
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
        assert self.mem_bytes is not None
        size = self.mem_bytes
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
    """Translates one function, in two steps.

    The front end, run(), turns each wasm instruction into NICE
    instructions on virtual registers, %v0 and up. Each local has one
    virtual register, or two for an i64 or f64, low word first. So does
    each value on the operand stack, a new one for each value pushed,
    except that the values that a block, loop, or if takes and gives have
    fixed registers in its Frame, which every path to them writes.
    Physical registers appear only where §9.3 or a helper demands them:
    the arguments and results of calls, the results of the function, and
    the code and address of a trap.

    A value on the operand stack may be deferred: a constant, or the value
    of a local, that is not in its own registers yet. pop() gives such a
    value's words as the constant or the local's registers, so the
    instruction that uses it takes it directly. A deferred value is copied
    to its own registers when it must be (settle()): before a local.set or
    local.tee changes its local, at the start of a block for the values
    that the block takes and for every value of a local, and at an else or
    end for the results. A deferred constant below a block stays deferred
    through the block, because nothing inside it can change the constant
    or reach the value. So the values below a block are the same on every
    path through it.

    The back end, finish(), gives the virtual registers physical registers
    or frame words (Allocator), and adds the prologue and the epilogue."""

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
        self.local_types = self.ftype.params + code.locals
        self.args, _ = assign_args(self.ftype.params)
        self.n_vregs = 0
        self.locals = [self.new_vregs(lt) for lt in self.local_types]
        self.stack: List[int] = []                      # the type of each value on the operand stack
        self.vals: List[List[str]] = []                 # its words as source operands
        self.deferred: List[Optional[Deferred]] = []    # and what it is, if it is deferred
        self.loops = 0                                  # the loops around the current instruction
        self.n_traps = 0
        self.n_labels = 0
        self.body: List[Item] = []
        self.stubs: List[Item] = []  # code after the epilogue, out of the way
        self.ret_label = f"{t.prefix}f{idx}.ret"
        self.ctrl = [Frame(0, self.ftype, 0, self.ret_label, [], [])]
        # What the straight-line code so far knows of some virtual
        # registers, until one of the registers involved is written or a
        # label that a jump may reach comes: a byte address -> (t,
        # aligned), where t is a word index, the address ROR 2 if not
        # aligned. If aligned, the address is 4 * t modulo 2^32, so it is
        # a multiple of 4 and its word is t modulo 2^30.
        self.word_index: Dict[str, Tuple[str, bool]] = {}
        # What the flags say about an i32 value, until an instruction
        # changes the flags or a label comes: the virtual registers that
        # hold the value, the condition under which it is not 0, and the
        # instructions that must get the M bit first for the flags to say
        # so. While that list is not empty, an instruction that reads the
        # flags ends it too.
        self.flag_val: Optional[Tuple[set[str], str, List[Ins]]] = None

    def new_vreg(self) -> str:
        self.n_vregs += 1
        return f"%v{self.n_vregs - 1}"

    def new_vregs(self, t: int) -> List[str]:
        return [self.new_vreg() for _ in range(SIZES[t])]

    def push(self, t: int, deferred: Optional[Deferred] = None,
             words: Optional[List[str]] = None) -> List[str]:
        """Pushes a value of type t and returns its words: those of a
        deferred value, the given registers, or new ones."""
        v = deferred.words if deferred is not None else words or self.new_vregs(t)
        self.stack.append(t)
        self.vals.append(v)
        self.deferred.append(deferred)
        return v

    def top(self) -> List[str]:
        """The words of the value on top of the operand stack."""
        return self.vals[-1]

    def pop(self, types: List[Optional[int]], at: int, what: str,
            keep: bool = False) -> List[List[str]]:
        """Pops values of the given types, the last one from the top, and
        returns their words as source operands. None accepts any type. Only
        the values pushed inside the innermost block can be popped. With
        keep, the values stay on the operand stack."""
        n = len(types)
        if len(self.stack) - self.ctrl[-1].height < n:
            raise WasmError(f"function {self.idx}: operand stack underflow", at)
        out: List[List[str]] = []
        for k, want in enumerate(types):
            i = len(self.stack) - n + k
            got = self.stack[i]
            if want is not None and got != want:
                raise WasmError(f"function {self.idx}: {what} expects {type_name(want)},"
                                f" found {type_name(got)}", at)
            out.append(self.vals[i])
        if not keep and n:
            del self.stack[-n:]
            del self.vals[-n:]
            del self.deferred[-n:]
        return out

    def settle(self, i: int) -> None:
        """Copies value i on the operand stack to registers of its own, if
        it is deferred."""
        d = self.deferred[i]
        if d is not None:
            v = self.new_vregs(self.stack[i])
            self.move(v, d.words)
            self.vals[i] = v
            self.deferred[i] = None

    def settle_top(self, types: List[int], at: int, what: str) -> None:
        """Checks that the values on top of the operand stack have the
        given types, and copies the deferred ones to their own registers."""
        self.pop(list(types), at, what, keep=True)
        for i in range(len(self.stack) - len(types), len(self.stack)):
            self.settle(i)

    def settle_locals(self, local: Optional[int] = None) -> None:
        """Copies the values of the given local, or of every local, to
        their own registers."""
        for i, d in enumerate(self.deferred):
            if d is not None and d.local is not None and local in (None, d.local):
                self.settle(i)

    def emit(self, mnemonic: str, *operands: str, stub: bool = False) -> Ins:
        """Adds an instruction to the body, or with stub to the code after
        the epilogue, which runs rarely."""
        ins = make_ins(mnemonic, *operands)
        if stub:
            self.stubs.append(ins)
        else:
            ins.depth = self.loops
            self.body.append(ins)
            if self.word_index:
                self.forget(ins)
            if self.flag_val is not None:
                self.track_flags(ins)
        return ins

    @staticmethod
    def written(ins: Ins) -> set[str]:
        """The registers that an instruction writes."""
        defs = set()
        for k, o in enumerate(ins.ops):
            kind, r = operand_reg(o)
            if r is not None and (kind == "side" or (k == 0 and kind == "reg")):
                defs.add(r)
        return defs

    def forget(self, ins: Ins) -> None:
        """Drops what word_index knows of the virtual registers that an
        instruction writes."""
        defs = self.written(ins)
        for x, (t, _) in list(self.word_index.items()):
            if x in defs or t in defs:
                del self.word_index[x]

    def track_flags(self, ins: Ins) -> None:
        """Keeps flag_val up to date after an instruction: it ends if the
        instruction writes the flags, and the instruction's destination is
        dropped from its registers, or added if it is a copy of one."""
        assert self.flag_val is not None
        regs, cond, todo = self.flag_val
        uses, defs = flag_use_def(ins)
        written = self.written(ins)
        if defs or "R14" in written or (todo and uses):
            self.flag_val = None
            return
        regs -= written
        kind, src = operand_reg(ins.ops[1]) if ins.op == "MOVE" and len(ins.ops) == 2 else ("", None)
        if not ins.cond and kind == "reg" and src in regs and operand_reg(ins.ops[0])[0] == "reg":
            regs.add(ins.ops[0])
        if not regs:
            self.flag_val = None

    def flags_of(self, v: str) -> Optional[str]:
        """The condition under which the i32 in the register or operand v
        is not 0, if the flags say it, or else None. The instructions that
        must set the flags for that get the M bit now."""
        if self.flag_val is None or v not in self.flag_val[0]:
            return None
        regs, cond, todo = self.flag_val
        for ins in todo:
            ins.op = with_m(ins.op)
        self.flag_val = (regs, cond, [])
        return cond

    def label(self, name: str, stub: bool = False, keep: bool = False) -> None:
        """Adds a label. One that a jump may reach, unless keep says that
        none does, ends the straight-line code that word_index is about."""
        (self.stubs if stub else self.body).append(Label(name))
        if not stub:
            self.flag_val = None
            if not keep:
                self.word_index.clear()

    def move(self, dest: List[str], src: List[str], stub: bool = False) -> None:
        for d, s in zip(dest, src):
            if d != s:
                self.emit("MOVE", d, s, stub=stub)

    def moves(self, pairs: List[Tuple[str, str]]) -> None:
        """Moves that happen at once: if a destination is also a source,
        the sources go through new registers first."""
        pairs = [(d, s) for d, s in pairs if d != s]
        if {d for d, _ in pairs} & {s for _, s in pairs}:
            temps = [self.new_vreg() for _ in pairs]
            for tmp, (_, s) in zip(temps, pairs):
                self.emit("MOVE", tmp, s)
            pairs = [(d, tmp) for tmp, (d, _) in zip(temps, pairs)]
        for d, s in pairs:
            self.emit("MOVE", d, s)

    def call_jump(self, target: str, uses: List[str], defs: FrozenSet[str],
                  stub: bool = False) -> None:
        """The call sequence of §9.3, to a label or through a register. The
        call reads the registers uses, and changes defs. The back end
        sets the 2 that the return address adds to the jump's size."""
        self.emit("ADD", "@--R13", "2", "R15", stub=stub)
        j = self.emit("MOVE", "R15", target, stub=stub)
        j.kind, j.targets, j.uses, j.defs = "call", [], frozenset(uses), defs
        if not stub:
            self.flag_val = None  # the call changes the flags (§9.3)

    def call(self, label: str, ft: FuncType, at: int, what: str,
             fwd: Optional[Tuple[List[str], Optional[Deferred]]] = None,
             dest: Optional[List[str]] = None) -> None:
        """Calls label with the arguments on top of the operand stack, by
        the rules of §9.3, and pushes the result, in dest if given. A label
        that is a register is called through it. With fwd, from forward(),
        the result goes to a local instead."""
        args = self.pop(list(ft.params), at, what)
        locs, stack_words = assign_args(ft.params)
        # Stack arguments go last to first, each high word first, so that
        # the first word ends up at the lowest address.
        for i in reversed(range(len(args))):
            if not locs[i][0]:
                for w in reversed(args[i]):
                    self.emit("MOVE", "@--R13", w)
        regs = []
        for i, (in_reg, first) in enumerate(locs):
            if in_reg:
                for k, w in enumerate(args[i]):
                    regs.append(f"R{first + k}")
                    self.emit("MOVE", regs[-1], w)
        self.call_jump(label, regs, CALLER_SAVED)
        if stack_words:
            self.emit("ADD", "R13", "R13", str(stack_words))
        if fwd is not None:
            self.move(fwd[0], [f"R{k + 1}" for k in range(len(fwd[0]))])
            if fwd[1] is not None:
                self.push(ft.results[0], fwd[1])
            return
        for rt in ft.results:
            v = dest or self.new_vregs(rt)
            self.move(v, [f"R{k + 1}" for k in range(SIZES[rt])])
            self.push(rt, words=v)

    def call_helper(self, name: str, args: List[str], results: int, stub: bool = False) -> None:
        """Calls one of the HELPERS, which is then emitted once, with
        the given arguments in R1 and up. Its results are in R1 and up."""
        self.t.helpers.add(name)
        regs = [f"R{k + 1}" for k in range(len(args))]
        self.move(regs, args, stub=stub)
        self.call_jump(self.t.prefix + name[2:], regs, HELPER_REGS[name], stub=stub)

    def local_operand(self, i: int, at: int) -> Tuple[int, List[str]]:
        if i >= len(self.locals):
            raise WasmError(f"function {self.idx}: local {i} does not exist", at)
        return self.local_types[i], list(self.locals[i])

    def global_operand(self, i: int, at: int) -> Tuple[int, List[str]]:
        if i >= len(self.t.m.globals):
            raise WasmError(f"function {self.idx}: global {i} does not exist", at)
        t = self.t.m.globals[i].type
        return t, [f"@{self.t.prefix}g{i}" + (f"+{k}" if k else "") for k in range(SIZES[t])]

    def trap(self, code: int) -> None:
        """Jumps through ___wasm_trap_vector with the code in R1 and the
        address of this code in R2 (§9.4)."""
        label = f"{self.t.prefix}f{self.idx}.t{self.n_traps}"
        self.n_traps += 1
        self.label(label)
        self.trap_jump(code, label)

    def trap_jump(self, code: int, start: str, stub: bool = False) -> None:
        """Traps with the given code and R2 = start (§9.4): sets R2 and
        jumps to W.trapN, a helper for code N that sets R1 and jumps
        through ___wasm_trap_vector."""
        self.emit("MOVE", "R2", start, stub=stub)
        name = f"W.trap{code}"
        self.t.helpers.add(name)
        j = self.emit("MOVE", "R15", self.t.prefix + name[2:], stub=stub)
        j.kind, j.targets, j.uses = "exit", [], frozenset({"R2"})

    def new_label(self) -> str:
        label = f"{self.t.prefix}f{self.idx}.L{self.n_labels}"
        self.n_labels += 1
        return label

    def reset(self, f: Frame, words: List[List[str]], types: List[int]) -> None:
        """Leaves only the values below f and then values of the given
        types, in the given registers, on the operand stack."""
        del self.stack[f.height:]
        del self.vals[f.height:]
        del self.deferred[f.height:]
        for t, w in zip(types, words):
            self.push(t, words=w)

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
        expects them: in its registers, or for the function in R1 and up."""
        types = f.label_types()
        values = self.pop(list(types), at, what, keep=True)
        if f.op == 0:
            dest = [f"R{k + 1}" for k in range(sum(SIZES[t] for t in types))]
        else:
            dest = [w for v in (f.params_v if f.op == LOOP else f.results_v) for w in v]
        return list(zip(dest, [w for v in values for w in v]))

    def end_block(self, f: Frame, at: int, what: str) -> None:
        """Checks that the operand stack holds exactly f's results, at else
        and at end, and moves them to f's registers."""
        values = self.pop(list(f.ft.results), at, what, keep=True)
        if len(self.stack) - len(values) != f.height:
            raise WasmError(f"function {self.idx}: values left on the operand stack at the {what}",
                            at)
        self.moves(list(zip([w for v in f.results_v for w in v], [w for v in values for w in v])))
        self.pop(list(f.ft.results), at, what)

    def fuses(self, r: Reader) -> bool:
        """Whether the i32 that the current instruction pushes is only a
        condition for the next ones: they are br_if or if, maybe after
        i32.eqz."""
        pos = r.pos
        if pos < r.end and self.t.data[pos] == 0x45:
            pos += 1
        return pos < r.end and self.t.data[pos] in (0x0D, IF)

    def compare(self, t: int, swap: bool, test: str, at: int, what: str,
                fuse: bool) -> Optional[str]:
        """An i32 or i64 comparison. It sets the flags, then the i32
        result: 1 if the test holds, else 0. With fuse, it only sets the
        flags, and returns the condition under which the test holds. The
        result is then not written."""
        a, b = self.pop([t, t], at, what)
        if swap:
            a, b = b, a
        d = self.push(I32)[0]
        if t == I32 and b[0] == "0":
            # The same flags as SUB[M] R0, a, 0, with C and V 0.
            self.emit("MOVE[M]", "R0", a[0])
        elif t == I32:
            self.emit("SUB[M]", "R0", a[0], b[0])
        elif test in ("eq", "ne"):
            # a XOR b is 0 in both words. A word XOR 0 is the word itself.
            parts = []
            for x, y in zip(a, b):
                if y == "0" or x == "0":
                    parts.append(x if y == "0" else y)
                else:
                    parts.append(self.new_vreg())
                    self.emit("XOR", parts[-1], x, y)
            self.emit("OR[M]", "R0", *parts)
        else:
            self.emit("SUB[M]", "R0", a[0], b[0])
            self.emit("SUB[CM]", "R0", a[1], b[1])
        if test in ("lt_s", "ge_s") and not (t == I32 and b[0] == "0"):
            # a < b signed is N XOR V. Flipping N when V is set leaves it
            # in N (§9.2).
            self.emit("?V XOR", "R14", "R14", "0x10000000")
        cond = {"eq": "Z", "ne": "!Z", "lt_u": "C", "ge_u": "!C", "lt_s": "N", "ge_s": "!N"}[test]
        if fuse:
            return cond
        if test == "lt_u":
            self.emit("ADD[C]", d, "R0", "R0")  # C, the borrow
        elif test == "ge_u":
            self.emit("SUB[C]", d, "1", "R0")   # 1 - C
        else:
            self.emit("MOVE", d, "0")
            self.emit(f"?{cond} MOVE", d, "1")
        # The flags still say whether d is 1, for a select or a branch on it.
        self.flag_val = ({d}, cond, [])
        return None

    def forward(self, r: Reader, at: int, t: int,
                n: int) -> Optional[Tuple[List[str], Optional[Deferred]]]:
        """For an operation that takes n values and gives one of type t,
        and whose next instruction is a local.set or local.tee of a local
        of type t: skips that instruction and returns the local's
        registers, where the operation writes its result, and for
        local.tee, the value it leaves on the operand stack. Every other
        copy of the local's old value is settled first. The operation
        reads its operands before it writes, so they may be the local
        itself."""
        if (r.pos >= r.end or self.t.data[r.pos] not in (0x21, 0x22)
                or len(self.stack) - self.ctrl[-1].height < n):
            return None
        nxt = Reader(self.t.data, r.pos + 1, r.end)
        i = nxt.u32()
        if i >= len(self.locals) or self.local_types[i] != t:
            return None
        tee = self.t.data[r.pos] == 0x22
        _, dest = self.local_operand(i, at)
        for k in range(len(self.stack) - n):
            d = self.deferred[k]
            if d is not None and d.local == i:
                self.settle(k)
        self.body.append(f"        ; {'local.tee' if tee else 'local.set'} {i}")
        r.pos = nxt.pos
        return dest, Deferred(dest, i) if tee else None

    def const_value(self, i: int, t: int = I32) -> Optional[int]:
        """The value of the i32, or with t the value of type t, on the
        operand stack i values from the top, if it is a deferred constant,
        as an unsigned number."""
        if len(self.stack) - self.ctrl[-1].height < i:
            return None
        d = self.deferred[-i]
        if d is None or d.local is not None or self.stack[-i] != t:
            return None
        return sum((int(w) & 0xFFFFFFFF) << (32 * k) for k, w in enumerate(d.words))

    def address(self, base: str, offset: int, n: int, const: Optional[int],
                fold: bool = False) -> Tuple[Optional[int], str, int]:
        """The byte address base + offset, as an operand a and a number of
        words k: the address is a + 4 * k. With bounds checks, traps with
        code 2 unless all n bytes there are in the memory. A trap's R2 is
        the start of this code, the first instruction of the access
        (§9.4). If base is the constant const, and the n bytes are in the
        initial memory or there are no bounds checks, returns the address
        and emits no code. With fold, an offset that is a multiple of 4 may
        come back in k, which is otherwise 0."""
        if const is not None:
            addr = const + offset
            if not self.t.checks:
                return addr & 0xFFFFFFFF, "", 0  # the address wraps modulo 2^32 (§9.4)
            assert self.t.mem_bytes is not None
            if addr + n <= self.t.mem_bytes:
                return addr, "", 0
        start = self.new_label()
        self.label(start, keep=True)
        a = base
        if const is not None and not offset:
            # A constant address that may be out of bounds, which is rare.
            # The trap's R2 points at the MOVE that puts it in a register.
            a = self.new_vreg()
            self.emit("MOVE", a, base)
        if not self.t.checks:
            # The address wraps modulo 2^32 (§9.4).
            if offset:
                a = self.new_vreg()
                self.emit("ADD", a, base, words(offset, I32)[0])
            return None, a, 0
        assert self.t.mem_bytes is not None
        limit = self.t.mem_bytes - n + 1
        if limit <= 0 and not self.t.growable:
            # No n bytes fit in the memory.
            self.trap_jump(2, start)
            return None, a, 0
        trap = self.trap_stub(2, start)
        if self.t.growable or const is not None:
            if offset:
                a = self.new_vreg()
                self.emit("ADD[M]", a, base, words(offset, I32)[0])
                self.emit("?C MOVE", "R15", trap)  # base + offset passes 2^32
            # The first address at which n bytes do not fit, which
            # memory.grow keeps up to date if the memory can grow.
            self.emit("SUB[M]", "R0", a, f"@W.limit{n}" if self.t.growable else words(limit, I32)[0])
            self.emit("?!C MOVE", "R15", trap)
            return None, a, 0
        # The first base at which n bytes from base + offset do not fit.
        # Below it, base + offset does not pass 2^32 either.
        if limit <= offset:
            self.emit("MOVE", "R15", trap)
            return None, a, 0
        self.emit("SUB[M]", "R0", base, words(limit - offset, I32)[0])
        self.emit("?!C MOVE", "R15", trap)
        if fold and offset % 4 == 0:
            return None, base, offset // 4
        if offset:
            a = self.new_vreg()
            self.emit("ADD", a, base, words(offset, I32)[0])
        return None, a, 0

    def index_of_sum(self, a: str, b: str, ca: Optional[int], cb: Optional[int]) -> str:
        """For an i32.add of a and b, the constants ca and cb if they are
        ones: if one is an address x at a multiple of 4 whose word index
        t_x word_index knows, and the other a constant c that is a multiple
        of 4, the sum is an address at a multiple of 4 too. Emits t = t_x
        + c / 4, which is the sum / 4 modulo 2^30 since the sum wraps
        modulo 2^32, and returns it, or else "". If no access uses t, the
        allocator removes it."""
        x, c = (a, cb) if cb is not None else (b, ca)
        t_x, aligned = self.word_index.get(x, ("", False))
        if c is None or not aligned or c % 4:
            return ""
        t = self.new_vreg()
        self.emit("ADD", t, t_x, words(c // 4, I32)[0])
        return t

    def mem_word(self, k: int, index: Optional[str] = None) -> str:
        """The operand for word k of the memory, plus the word index in the
        register index, if given."""
        return f"@{self.t.mem}" + (f"+{k}" if k else "") + (f"[{index}]" if index else "")

    @staticmethod
    def expand(aligned: List[Tuple[str, ...]], word: Callable[[int], str]) -> List[Tuple[str, ...]]:
        """The aligned instructions of an access, with %0 and %1 in their
        operands replaced by the operands of its first and second word."""
        return [tuple(o.replace("%0", word(0)).replace("%1", word(1)) for o in ins)
                for ins in aligned]

    def fast_path(self, helper: str, a: str, args: List[str], results: List[str],
                  aligned: List[Tuple[str, ...]]) -> None:
        """The access of 4 or 8 bytes at the byte address a. If a is at a
        multiple of 4, the aligned instructions do it, with %0 and %1 in
        their operands for its words. Else a stub after the epilogue calls
        the helper with a in R1 and args from R2 up, moves its results from
        R1 up, and jumps back."""
        stub, back = self.new_label(), self.new_label()
        self.emit("AND[M]", "R0", a, "3")
        self.emit("?!Z MOVE", "R15", stub)
        w = self.new_vreg()
        self.emit("SHR", w, a, "2")                       # word index
        for mnemonic, *ops in self.expand(aligned, lambda k: self.mem_word(k, w)):
            self.emit(mnemonic, *ops)
        self.label(back, keep=True)
        self.label(stub, stub=True)
        self.call_helper(helper, [a] + args, len(results), stub=True)
        self.move(results, [f"R{j + 1}" for j in range(len(results))], stub=True)
        self.emit("MOVE", "R15", back, stub=True)

    def word_access(self, base: str, offset: int, n: int, helper: str, args: List[str],
                    results: List[str], aligned: List[Tuple[str, ...]]) -> List[Ins]:
        """The access of 4 or 8 bytes at base + offset, where base is not a
        constant and offset is a multiple of 4, with bounds checks or with
        base known to be at a multiple of 4. The word index t = base ROR 2
        is base / 4 if base is a multiple of 4, and 2^30 or more if it is
        not, which is past every word of the memory. So one unsigned
        compare of t checks both the bounds and the alignment, and the
        aligned instructions (fast_path) do the access with the word index
        in t. If the compare fails, a stub after the epilogue gets base
        back from t, traps with code 2 if the access is out of bounds, and
        else calls the helper, as fast_path does. The t of a base that
        word_index knows serves too: a t that may have bits above the word
        index fails the compare. Without bounds checks, an aligned base
        needs no check, but its t must be taken modulo 2^30, since the
        address wraps modulo 2^32 (§9.4). Returns the instructions that
        write the last result on each path, if there are results."""
        assert self.t.mem_bytes is not None
        start, slow, back = self.new_label(), self.new_label(), self.new_label()
        self.label(start, keep=True)
        if not self.t.checks:
            t = self.word_index[base][0]
            if offset:
                u = self.new_vreg()
                self.emit("ADD", u, t, words(offset // 4, I32)[0])
                t = u
            u = self.new_vreg()
            self.emit("AND", u, t, "0x3FFFFFFF")
            last = [self.emit(mnemonic, *ops)
                    for mnemonic, *ops in self.expand(aligned, lambda j: self.mem_word(j, u))][-1:]
            return last if results else []
        limit = (self.t.mem_bytes - offset - n) // 4 + 1  # the first t at which n bytes do not fit
        if limit <= 0 and not self.t.growable:
            # No n bytes fit there.
            self.trap_jump(2, start)
            return []
        t, aligned_t = self.word_index.get(base, ("", False))
        if not t:
            t = self.new_vreg()
            self.emit("ROR", t, base, "2")
            if VREG_RE.fullmatch(base):
                self.word_index[base] = (t, False)
        k = offset // 4
        u = t
        if self.t.growable:
            # Words that memory.grow keeps up to date. With k, t + k
            # passes 2^32 only if base is not a multiple of 4.
            if k:
                u = self.new_vreg()
                self.emit("ADD[M]", u, t, str(k))
                self.emit("?C MOVE", "R15", slow)
                k = 0
            self.emit("SUB[M]", "R0", u, f"@W.wlimit{n}")
        else:
            self.emit("SUB[M]", "R0", u, str(limit))
        self.emit("?!C MOVE", "R15", slow)
        last = [self.emit(mnemonic, *ops)
                for mnemonic, *ops in self.expand(aligned, lambda j: self.mem_word(k + j, u))][-1:]
        self.label(back, keep=True)
        trap = self.trap_stub(2, start)
        self.label(slow, stub=True)
        a = self.new_vreg()
        self.emit("SHL" if aligned_t else "ROL", a, t, "2", stub=True)  # base
        if offset:
            a2 = self.new_vreg()
            self.emit("ADD[M]", a2, a, words(offset, I32)[0], stub=True)
            self.emit("?C MOVE", "R15", trap, stub=True)  # base + offset passes 2^32
            a = a2
        size_limit = f"@W.limit{n}" if self.t.growable else str(self.t.mem_bytes - n + 1)
        self.emit("SUB[M]", "R0", a, size_limit, stub=True)
        self.emit("?!C MOVE", "R15", trap, stub=True)
        self.call_helper(helper, [a] + args, len(results), stub=True)
        moves = [self.emit("MOVE", w, f"R{j + 1}", stub=True) for j, w in enumerate(results)]
        self.emit("MOVE", "R15", back, stub=True)
        return last + moves[-1:] if results else []

    def table(self, name: str, p: str, k: int = 0) -> str:
        """The operand for entry p + k of one of the TABLES."""
        self.t.tables.add(name)
        return f"@{self.t.prefix}{name}" + (f"+{k}" if k else "") + f"[{p}]"

    def narrow(self, base: str, offset: int, n: int, const: Optional[int],
               access: Callable[[Callable[[int], str], Union[int, str], bool], None]) -> None:
        """An access of 1 or 2 bytes at base + offset, after the bounds
        check (address). The word index w and the byte p of the address in
        its word come from a shift and an AND, unless the address is a
        constant. access(word, p, stub) emits the code, with word(j) the
        operand of word j from w and p a number or a register. Bytes p and
        p + 1 of a word hold 2 bytes unless p = 3, when they straddle two
        words. A register p is then checked, and access runs again in a
        stub after the epilogue for p = 3."""
        fold = const is None and self.t.checks and not self.t.growable
        addr, a, k = self.address(base, offset, n, const, fold)
        if addr is not None:
            access(lambda j: self.mem_word(addr // 4 + j), addr % 4, False)
            return
        w, p = self.new_vreg(), self.new_vreg()
        self.emit("SHR", w, a, "2")
        self.emit("AND", p, a, "3")
        if n == 1:
            access(lambda j: self.mem_word(k + j, w), p, False)
            return
        slow, back = self.new_label(), self.new_label()
        self.emit("SUB[M]", "R0", p, "3")
        self.emit("?Z MOVE", "R15", slow)
        access(lambda j: self.mem_word(k + j, w), p, False)
        self.label(back, keep=True)
        self.label(slow, stub=True)
        access(lambda j: self.mem_word(k + j, w), 3, True)
        self.emit("MOVE", "R15", back, stub=True)

    def load_narrow(self, n: int, signed: bool, word: Callable[[int], str], p: Union[int, str],
                    d: str, stub: bool) -> None:
        """Loads the n = 1 or 2 bytes from byte p of word(0) into d, with
        the sign for signed. For n = 2 and p = 3, the second byte is the
        low byte of word(1). A sign comes down from bit 31 with C<0 and C>0
        (§5.2)."""
        if n == 2 and p == 3:
            x = self.new_vreg()
            self.emit("SHR", d, word(0), "24", stub=stub)
            self.emit("SHL", x, word(1), "24" if signed else "8", stub=stub)
            if signed:
                self.emit("C<0[M]", "R0", x, "1", stub=stub)
                self.emit("C>0", x, x, "16", stub=stub)
            self.emit("OR", d, d, x, stub=stub)
            if not signed:
                self.emit("AND", d, d, "0xFFFF", stub=stub)
            return
        if signed:
            # The bytes up to bit 31, then down with the sign.
            up = str(32 - 8 * n - 8 * p) if isinstance(p, int) else self.table("bshl", p, n - 1)
            self.emit("SHL", d, word(0), up, stub=stub)
            self.emit("C<0[M]", "R0", d, "1", stub=stub)
            self.emit("C>0", d, d, str(32 - 8 * n), stub=stub)
        else:
            down = str(8 * p) if isinstance(p, int) else self.table("bshift", p)
            self.emit("SHR", d, word(0), down, stub=stub)
            self.emit("AND", d, d, "0xFF" if n == 1 else "0xFFFF", stub=stub)

    def store_narrow(self, n: int, v: str, word: Callable[[int], str], p: Union[int, str],
                     stub: bool) -> None:
        """Stores the low n = 1 or 2 bytes of v at byte p of word(0): reads
        the word, clears the bytes, ORs in the new ones, and writes it back.
        For n = 2 and p = 3, the second byte goes to the low byte of
        word(1)."""
        mask = (1 << (8 * n)) - 1
        const = int(v) & mask if re.match(r"-?\d+\Z", v) else None
        m, x = self.new_vreg(), self.new_vreg()
        if n == 2 and p == 3:
            self.emit("AND", m, word(0), "0x00FFFFFF", stub=stub)
            if const is None:
                self.emit("SHL", x, v, "24", stub=stub)
            self.emit("OR", word(0), m, x if const is None else words(const << 24, I32)[0],
                      stub=stub)
            m, x = self.new_vreg(), self.new_vreg()
            self.emit("AND", m, word(1), "0xFFFFFF00", stub=stub)
            if const is None:
                self.emit("SHR", x, v, "8", stub=stub)
                self.emit("AND", x, x, "0xFF", stub=stub)
            self.emit("OR", word(1), m, x if const is None else str(const >> 8), stub=stub)
            return
        if isinstance(p, int):
            self.emit("AND", m, word(0), words(~(mask << (8 * p)), I32)[0], stub=stub)
            if const is not None:
                self.emit("OR", word(0), m, words(const << (8 * p), I32)[0], stub=stub)
                return
            self.emit("AND", x, v, str(mask), stub=stub)
            if p:
                self.emit("SHL", x, x, str(8 * p), stub=stub)
        else:
            self.emit("IAND", m, self.table("bmask" if n == 1 else "hmask", p), word(0),
                      stub=stub)
            if const is None:
                self.emit("AND", x, v, str(mask), stub=stub)
            self.emit("SHL", x, x if const is None else str(const), self.table("bshift", p),
                      stub=stub)
        self.emit("OR", word(0), m, x, stub=stub)

    def trunc_check(self, src_t: int, dst_t: int, pos_limit: int, neg_limit: int, at: int,
                    what: str) -> None:
        """Traps with code 5 unless the float on top of the operand stack,
        which stays there, has a magnitude below the limit for its sign
        (TRUNC_OPS). A NaN or an infinity is above every limit."""
        (v,) = self.pop([src_t], at, what, keep=True)
        start = self.new_label()
        self.label(start, keep=True)
        hi = v[-1]  # the word with the sign
        mag, lim = self.new_vreg(), self.new_vreg()
        if src_t == F32:
            self.emit("MOVE", lim, words(pos_limit, I32)[0])
            self.emit("MOVE[M]", "R0", hi)
            self.emit("?N MOVE", lim, words(neg_limit, I32)[0])
            self.emit("AND", mag, hi, "0x7FFFFFFF")
            self.emit("SUB[M]", "R0", mag, lim)            # C = mag < lim, unsigned
        else:
            pos, neg = words(pos_limit, I64), words(neg_limit, I64)
            lim_lo = self.new_vreg()
            self.emit("MOVE", lim, pos[1])
            self.emit("MOVE", lim_lo, pos[0])
            self.emit("MOVE[M]", "R0", hi)
            self.emit("?N MOVE", lim, neg[1])
            self.emit("?N MOVE", lim_lo, neg[0])
            self.emit("AND", mag, hi, "0x7FFFFFFF")
            self.emit("SUB[M]", "R0", v[0], lim_lo)
            self.emit("SUB[CM]", "R0", mag, lim)           # C = mag:v[0] < lim:lim_lo
        self.emit("?!C MOVE", "R15", self.trap_stub(5, start))

    def call_indirect(self, type_idx: int, at: int, what: str) -> None:
        """Calls the function in the table entry whose index is on top of
        the operand stack (§9.4). An index past the end of the table and an
        empty entry trap with code 6, and an entry of another type with
        code 7."""
        ft = self.t.m.types[type_idx]
        check_types(ft.params + ft.results, f"function {self.idx}: {what}", at)
        if len(ft.results) > 1:
            raise WasmError(f"function {self.idx}: {what}: more than one result is not supported"
                            " yet", at)
        (index,) = self.pop([I32], at, what)
        assert self.t.m.table_size is not None
        start = self.new_label()
        self.label(start, keep=True)
        entry, func = self.new_vreg(), self.new_vreg()
        self.emit("SUB[M]", "R0", index[0], str(self.t.m.table_size))
        self.emit("?!C MOVE", "R15", self.trap_stub(6, start))    # index >= size
        self.emit("ADD", entry, index[0], index[0])               # two words an entry
        table = f"{self.t.prefix}table"
        self.emit("MOVE[M]", func, f"@{table}[{entry}]")
        self.emit("?Z MOVE", "R15", self.trap_stub(6, start))     # empty
        self.emit("SUB[M]", "R0", f"@{table}+1[{entry}]", str(self.t.type_number(type_idx)))
        self.emit("?!Z MOVE", "R15", self.trap_stub(7, start))
        self.call(func, ft, at, what)

    def range_check(self, addr: str, n: str, trap: str) -> None:
        """Jumps to trap unless the n bytes from byte address addr are all
        in the memory. n may be 0, even at the end of the memory."""
        assert self.t.mem_bytes is not None
        size = self.t.mem_bytes
        end = self.new_vreg()
        self.emit("ADD[M]", end, addr, n)
        self.emit("?C MOVE", "R15", trap)          # addr + n passes 2^32
        if self.t.growable:
            self.emit("SUB[M]", "R0", end, "@W.limit0")
            self.emit("?!C MOVE", "R15", trap)
        elif size < 1 << 32:
            self.emit("SUB[M]", "R0", end, words(size + 1, I32)[0])
            self.emit("?!C MOVE", "R15", trap)

    def bulk(self, helper: str, at: int, what: str) -> None:
        """memory.fill or memory.copy. Both take (address, value or source
        address, n). With bounds checks, the ranges are checked before any
        byte is written, and a range out of bounds traps with code 2. Then
        the helper does the work."""
        d, x, n = self.pop([I32, I32, I32], at, what, keep=True)
        start = self.new_label()
        self.label(start, keep=True)
        if self.t.checks:
            trap = self.trap_stub(2, start)
            self.range_check(d[0], n[0], trap)
            if helper == "copy":
                self.range_check(x[0], n[0], trap)
        self.t.helpers.add(f"W.{helper}")
        self.call(f"{self.t.prefix}{helper}", FuncType([I32, I32, I32], []), at, what)

    def trap_stub(self, code: int, start: str) -> str:
        """A stub after the epilogue that traps with the given code, and
        with R2 = start, the first instruction of the code for the wasm
        instruction that traps (§9.4). Returns its label."""
        label = self.new_label()
        self.label(label, stub=True)
        self.trap_jump(code, start, stub=True)
        return label

    def mpu_op(self, word: str, t: int, at: int, what: str,
               dest: Optional[List[str]] = None) -> None:
        """Pops a and b, writes them to the math unit (§8.4), A and B for
        an i32 and C and D for an i64, and pushes the given result, in
        dest if given. The labels __mpu.* are in runtime/muldiv_mpu.nasm."""
        a, b = self.pop([t, t], at, what)
        dest = self.push(t, words=dest)
        if t == I32:
            self.emit("MOVE", "@__mpu.a", a[0])
            self.emit("MOVE", "@__mpu.b", b[0])
            self.emit("MOVE", dest[0], f"@__mpu.{word}")
        else:
            self.emit("MOVE", "@__mpu.c_lo", a[0])
            self.emit("MOVE", "@__mpu.c_hi", a[1])
            self.emit("MOVE", "@__mpu.d_lo", b[0])
            self.emit("MOVE", "@__mpu.d_hi", b[1])
            self.emit("MOVE", dest[0], f"@__mpu.{word}")
            self.emit("MOVE", dest[1], f"@__mpu.{word}+1")

    def mul_const(self, r: Reader, at: int, what: str) -> bool:
        """An i32.mul by a constant as at most MUL_STEPS shifts, additions,
        and subtractions (mul_plan), if it can be. Its result may go
        straight to a local. Returns whether it was."""
        consts = self.const_value(2), self.const_value(1)
        c = consts[1] if consts[1] is not None else consts[0]
        if c is None:
            return False
        plan = mul_plan(c, MUL_STEPS) if c else ()
        if plan is None:
            return False
        fwd = self.forward(r, at, I32, 2)
        a, b = self.pop([I32, I32], at, what)
        vals = [a[0] if consts[1] is not None else b[0]]
        d = self.push(I32)[0] if fwd is None else fwd[0][0]
        if not c:
            self.emit("MOVE", d, "0")
        elif not plan:
            self.move([d], vals)
        for k, (step, i, j) in enumerate(plan):
            dest = d if k == len(plan) - 1 else self.new_vreg()
            if step == "shl":
                self.emit("SHL", dest, vals[i], str(j))
            else:
                self.emit(step.upper(), dest, "R0" if i < 0 else vals[i], vals[j])
            vals.append(dest)
        if fwd is not None and fwd[1] is not None:
            self.push(I32, fwd[1])
        return True

    def mul64_const(self, r: Reader, at: int, what: str) -> bool:
        """An i64.mul by a constant c = 2^32 * ch + cl, inline with the math
        unit, if it is used and if a product of a word with ch or cl can be
        made of at most MUL64_STEPS shifts, additions, and subtractions
        (mul_plan). Returns whether it was. With x = 2^32 * xh + xl, the
        product modulo 2^64 is xl * cl + 2^32 * (xl * ch + xh * cl), and
        only the low words of the last two products count. The math unit
        computes xl * cl, all 64 bits, while the shifts and additions
        compute the others, so the wait for the math unit overlaps them.
        A product that has no such plan uses the math unit after the first.
        Its result may go straight to a local."""
        if not self.t.mpu:
            return False
        consts = self.const_value(2, I64), self.const_value(1, I64)
        c = consts[1] if consts[1] is not None else consts[0]
        if c is None:
            return False
        cl, ch = c & 0xFFFFFFFF, c >> 32
        # The products of the high word: (operand word, constant word, plan).
        cross = [(0, ch, mul_plan(ch, MUL64_STEPS) if ch else ()),
                 (1, cl, mul_plan(cl, MUL64_STEPS) if cl else ())]
        if all(plan is None for _, _, plan in cross):
            return False
        fwd = self.forward(r, at, I64, 2)
        a, b = self.pop([I64, I64], at, what)
        x = a if consts[1] is not None else b
        d = self.push(I64)[:] if fwd is None else fwd[0]
        if cl > 1:
            self.emit("MOVE", "@__mpu.a", x[0])
            self.emit("MOVE", "@__mpu.b", str(cl))
        terms = []
        for k, cw, plan in cross:
            if cw == 0 or plan is None:
                continue
            vals = [x[k]]
            for step, i, j in plan:
                v = self.new_vreg()
                if step == "shl":
                    self.emit("SHL", v, vals[i], str(j))
                else:
                    self.emit(step.upper(), v, "R0" if i < 0 else vals[i], vals[j])
                vals.append(v)
            terms.append(vals[-1])
        # The high word sums the terms, and reads each result of the math
        # unit as late as it can, but before the next operand is written.
        reads: List[Tuple[str, str]] = []  # (the word for A, the constant for B)
        for k, cw, plan in cross:
            if cw and plan is None:
                reads.append((x[k], str(cw)))
        hi = terms.pop(0) if terms else "0"
        n = len(terms) + (cl > 1) + len(reads)
        lo = x[0] if cl == 1 else "0"
        for v in terms + (["@__mpu.umul_hi"] if cl > 1 else []):
            if v.startswith("@"):
                lo = self.new_vreg()
                self.emit("MOVE", lo, "@__mpu.umul_lo")
            n -= 1
            dest = d[1] if n == 0 else self.new_vreg()
            self.emit("ADD", dest, hi, v)
            hi = dest
        mpu_a = x[0] if cl > 1 else None  # what A holds
        for word, factor in reads:
            if mpu_a != word:
                self.emit("MOVE", "@__mpu.a", word)
                mpu_a = word
            self.emit("MOVE", "@__mpu.b", factor)
            n -= 1
            dest = d[1] if n == 0 else self.new_vreg()
            self.emit("ADD", dest, hi, "@__mpu.umul_lo")
            hi = dest
        self.moves([(d[0], lo), (d[1], hi)])  # lo or hi may be a word of x, and x d
        if fwd is not None and fwd[1] is not None:
            self.push(I64, fwd[1])
        return True

    def divide(self, t: int, op: str, at: int, what: str) -> None:
        """A division or remainder, by the math unit for i32 unless it is
        turned off, else by a call to the runtime library. First
        come the cases that wasm defines but C does not (§9.4): division by
        0 traps with code 3, and div_s of the most negative number by -1
        traps with code 4. rem_s by -1 is 0, without the call. A constant
        divisor other than 0 and -1 needs none of these checks, and an
        unsigned i32 division or remainder by a power of 2 is a shift or
        an AND."""
        d = self.deferred[-1] if len(self.stack) > self.ctrl[-1].height else None
        a, b = self.pop([t, t], at, what, keep=True)
        result = self.new_vregs(t)
        if d is not None and d.local is None:
            c = sum((int(w) & 0xFFFFFFFF) << (32 * k) for k, w in enumerate(d.words))
            if t == I32 and c & (c - 1) == 0 and c and op in ("div_u", "rem_u"):
                self.pop([t, t], at, what)
                dest = self.push(t, words=result)[0]
                if op == "div_u":
                    self.emit("SHR", dest, a[0], str(c.bit_length() - 1))
                else:
                    self.emit("AND", dest, a[0], str(c - 1))
                return
            if c not in (0, (1 << (32 * len(b))) - 1):
                self.divide_op(t, op, at, what, result)
                return
        start = self.new_label()
        self.label(start, keep=True)
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
                x = self.new_vreg()
                self.emit("AND", x, b[0], b[1])
                self.emit("ADD[M]", "R0", x, "1")
        done = ""
        if op == "div_s":
            ok = self.new_label()
            self.emit("?!Z MOVE", "R15", ok)
            # Z = a is the most negative number.
            if t == I32:
                self.emit("SUB[M]", "R0", a[0], "-2147483648")
            else:
                x = self.new_vreg()
                self.emit("XOR", x, a[1], "-2147483648")
                self.emit("OR[M]", "R0", x, a[0])
            self.emit("?Z MOVE", "R15", self.trap_stub(4, start))
            self.label(ok)
        elif op == "rem_s":
            # The result is 0 by -1. A MOVE leaves the flags as they are.
            done = self.new_label()
            for w in result:
                self.emit("MOVE", w, "0")
            self.emit("?Z MOVE", "R15", done)
        self.divide_op(t, op, at, what, result)
        if done:
            self.label(done)

    def divide_op(self, t: int, op: str, at: int, what: str, result: List[str]) -> None:
        """The division or remainder itself, by the math unit or by a call,
        with the result in the registers result."""
        if self.t.mpu:
            word = {"div_s": "sdiv_q", "div_u": "udiv_q", "rem_s": "sdiv_r", "rem_u": "udiv_r"}[op]
            if t == I64:
                word = word.replace("_", "64_")
            self.mpu_op(word, t, at, what, result)
        else:
            routine = {"div_s": "__div", "div_u": "__udiv", "rem_s": "__mod",
                       "rem_u": "__umod"}[op]
            self.call(routine + ("64" if t == I64 else ""), FuncType([t, t], [t]), at, what,
                      dest=result)

    def memarg(self, n: int, align: int, at: int, what: str) -> None:
        """Checks a load's or store's memory and alignment."""
        if self.t.m.memory_pages is None:
            raise WasmError(f"function {self.idx}: {what} needs a memory, and the module has"
                            " none", at)
        if 1 << align > n:
            raise WasmError(f"function {self.idx}: {what}: the alignment is larger than"
                            " natural", at)

    def load(self, t: int, n: int, signed: bool, offset: int, at: int, what: str) -> None:
        """Loads n bytes into a value of type t. An access of 4 or 8 bytes
        at a multiple of 4 reads whole words inline. Others call a helper
        (load_helper), which leaves the value in R1, and R2 for n = 8."""
        const = self.const_value(1)
        (base,) = self.pop([I32], at, what)
        dest = self.push(t)
        helper = f"W.load{n}" + ("" if n >= 4 else "s" if signed else "u")
        res = dest if n == 8 else [dest[0] if len(dest) == 1 else self.new_vreg()]
        aligned: List[Tuple[str, ...]] = [("MOVE", w, f"%{k}") for k, w in enumerate(res)]
        if n >= 4 and const is None and offset % 4 == 0 and (
                self.t.checks or self.word_index.get(base[0], ("", False))[1]):
            last = self.word_access(base[0], offset, n, helper, [], res, aligned)
            if len(dest) == 2 and n == 4:
                self.extend(dest, res[0], signed)
            elif n == 4 and last:
                # The flags can say whether the i32 is 0, for a branch on
                # it, if each path sets them as it loads it.
                self.flag_val = ({res[0]}, "!Z", last)
            return
        if n < 4:
            self.narrow(base[0], offset, n, const,
                        lambda word, p, stub: self.load_narrow(n, signed, word, p, res[0], stub))
            if len(dest) == 2:
                self.extend(dest, res[0], signed)
            return
        addr, a, _ = self.address(base[0], offset, n, const)
        mem = f"@{self.t.mem}"
        if addr is not None and n >= 4 and addr % 4 == 0:
            # A known address in the memory, at a multiple of 4.
            word = f"{mem}+{addr // 4}"
            if n == 8:
                self.emit("MOVE", dest[0], word)
                self.emit("MOVE", dest[1], f"{mem}+{addr // 4 + 1}")
                return
            src = word
        else:
            if addr is not None:
                a = str(addr)
            if addr is None and n >= 4:
                self.fast_path(helper, a, [], res, aligned)
            else:
                self.call_helper(helper, [a], len(res))
                self.move(res, [f"R{k + 1}" for k in range(len(res))])
            if n == 8 or len(dest) == 1:
                return
            src = res[0]
        if len(dest) == 1:
            self.emit("MOVE", dest[0], src)
            return
        self.extend(dest, src, signed)

    def extend(self, dest: List[str], src: str, signed: bool) -> None:
        """Extends the 32-bit value src to the i64 in dest. A helper extends
        a value of 1 or 2 bytes to 32."""
        self.emit("MOVE[M]" if signed else "MOVE", dest[0], src)
        self.emit("MOVE", dest[1], "0")
        if signed:
            self.emit("?N MOVE", dest[1], "-1")

    def store(self, t: int, n: int, offset: int, at: int, what: str) -> None:
        """Stores the low n bytes of a value of type t. An access of 4 or 8
        bytes at a multiple of 4 writes whole words inline. Others call a
        helper (store_helper) with the value in R2, and R3 for n = 8."""
        const = self.const_value(2)
        base, value = self.pop([I32, t], at, what)
        words_n = 2 if n == 8 else 1
        aligned: List[Tuple[str, ...]] = [("MOVE", f"%{k}", value[k]) for k in range(words_n)]
        if n >= 4 and const is None and offset % 4 == 0 and (
                self.t.checks or self.word_index.get(base[0], ("", False))[1]):
            self.word_access(base[0], offset, n, f"W.store{n}", value[:words_n], [], aligned)
            return
        if n < 4:
            self.narrow(base[0], offset, n, const,
                        lambda word, p, stub: self.store_narrow(n, value[0], word, p, stub))
            return
        addr, a, _ = self.address(base[0], offset, n, const)
        mem = f"@{self.t.mem}"
        if addr is not None and n >= 4 and addr % 4 == 0:
            for k in range(words_n):
                self.emit("MOVE", f"{mem}+{addr // 4 + k}", value[k])
            return
        if addr is None and n >= 4:
            self.fast_path(f"W.store{n}", a, value[:words_n], [], aligned)
            return
        if addr is not None:
            a = str(addr)
        self.call_helper(f"W.store{n}", [a] + value[:words_n], 0)

    def shift64(self, op: str, at: int, what: str) -> None:
        """An i64 shift or rotate. The count is the low word of the second
        operand, modulo 64. A shift by a constant is a few instructions
        inline. Any other calls a helper (shift64_helper)."""
        count = self.deferred[-1] if len(self.stack) > self.ctrl[-1].height else None
        a, b = self.pop([I64, I64], at, what)
        lo, hi = self.push(I64)
        a_lo, a_hi = a           # a itself, which may be deferred
        if count is None or count.local is not None or op in ("rotl", "rotr"):
            self.call_helper(f"W.{op}64", [a_lo, a_hi, b[0]], 2)
            self.move([lo, hi], ["R1", "R2"])
            return
        n = int(count.words[0]) & 63
        x, y = self.new_vreg(), self.new_vreg()
        if n == 0:
            self.move([lo, hi], a)
        elif op in ("shl", "shr_u"):
            # shl: hi' = hi << n | lo >> (32 - n), lo' = lo << n, or for
            # n >= 32, hi' = lo << (n - 32) and lo' = 0. shr_u is the
            # mirror image, with the words swapped.
            near, far = (lo, hi) if op == "shl" else (hi, lo)
            a_near, a_far = (a_lo, a_hi) if op == "shl" else (a_hi, a_lo)
            fwd, back = ("SHL", "SHR") if op == "shl" else ("SHR", "SHL")
            if n < 32:
                self.emit(back, x, a_near, str(32 - n))
                self.emit(fwd, y, a_far, str(n))
                self.emit("OR", far, x, y)
                self.emit(fwd, near, a_near, str(n))
            else:
                if n == 32:
                    self.emit("MOVE", far, a_near)
                else:
                    self.emit(fwd, far, a_near, str(n - 32))
                self.emit("MOVE", near, "0")
        elif n < 32:
            # shr_s: lo' = lo >> n | hi << (32 - n), hi' = hi >>s n. C>0
            # shifts in C, the sign bit (§5.2).
            self.emit("SHL", x, a_hi, str(32 - n))
            self.emit("SHR", y, a_lo, str(n))
            self.emit("OR", lo, x, y)
            self.emit("C<0[M]", "R0", a_hi, "1")
            self.emit("C>0", hi, a_hi, str(n))
        else:
            # lo' = hi >>s (n - 32), and hi' is all sign bits.
            self.emit("C<0[M]", "R0", a_hi, "1")
            if n == 32:
                self.emit("MOVE", lo, a_hi)
            else:
                self.emit("C>0", lo, a_hi, str(n - 32))
            self.emit("C>0", hi, a_hi, "32")

    def run(self) -> List[str]:
        r = Reader(self.t.data, self.code.start, self.code.end)
        reachable = True
        dead_blocks = 0  # blocks opened in code that cannot be reached
        # The condition under which the i32 on top of the operand stack is
        # not 0, when the flags hold it and its register does not.
        pending: Optional[str] = None
        while True:
            at = r.pos
            op = r.byte()
            flags, pending = pending, None
            name = OPCODES.get(op, f"opcode 0x{op:02x}")
            if op == 0xFC:
                sub = r.u32()
                name = FC_OPCODES.get(sub, f"opcode 0xfc {sub}")
                if sub not in (10, 11) and 0x100 + sub not in TRUNC_SAT_OPS:
                    raise WasmError(f"function {self.idx}: {name} is not supported yet", at)
                for _ in range(2 if sub == 10 else 1 if sub == 11 else 0):
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
            elif op in (0x41, 0x42, 0x43, 0x44):  # the constants
                imm = read_const(r, {0x41: I32, 0x42: I64, 0x43: F32, 0x44: F64}[op])
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
                if self.t.library:
                    raise WasmError(f"function {self.idx}: a library module may not use {name}",
                                    at)
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
                      or op in REINTERPRET_OPS or op in SIGN_OPS or op in FLOAT_OPS
                      or op in TRUNC_OPS or op in TRUNC_SAT_OPS or op in FLOAT_CMP_OPS
                      or op in DIV_OPS or op in LIB_OPS or op in EXTEND_OPS
                      or op in ALU_OPS or op in ALU64_OPS or op in CMP_OPS or op in CMP64_OPS
                      or op in SHIFT_OPS or op in SHIFT64_OPS):
                raise WasmError(f"function {self.idx}: {name} is not supported yet", at)
            if self.t.library and (op in FLOAT_OPS or op in TRUNC_OPS or op in TRUNC_SAT_OPS
                                   or op in FLOAT_CMP_OPS):
                # These call the float library, which would then call itself.
                raise WasmError(f"function {self.idx}: a library module may not use {name}", at)
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
            if op in (0x43, 0x44):
                comment += f" 0x{imm:0{8 if op == 0x43 else 16}X}"  # the bits
            elif imm is not None:
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
                    if f.ft.params and reachable:
                        self.emit("MOVE", "R15", f.label)
                    self.label(f.else_label)
                    self.moves(list(zip([w for v in f.results_v for w in v],
                                        [w for v in f.params_v for w in v])))
                if f.op != LOOP:
                    self.label(f.label)
                else:
                    self.loops -= 1
                self.ctrl.pop()
                self.reset(f, f.results_v, f.ft.results)
                reachable = True
            elif op == 0x05:  # else
                f = self.ctrl[-1]
                if f.else_label is None:
                    raise WasmError(f"function {self.idx}: else without if", at)
                if reachable:
                    self.end_block(f, at, name)
                    self.emit("MOVE", "R15", f.label)
                self.label(f.else_label)
                f.else_label = None
                self.reset(f, f.params_v, f.ft.params)
                reachable = True
            elif op == 0x00:  # unreachable
                self.trap(1)
                reachable = False
            elif op == 0x01:  # nop
                pass
            elif op in (BLOCK, LOOP, IF):
                cond_word = self.pop([I32], at, name)[0][0] if op == IF else ""
                if op == IF and flags is None:
                    flags = self.flags_of(cond_word)
                # The values below the block are the same on every path
                # through it, and its parameters are in registers of their
                # own. A loop's are new ones, which a branch to it writes.
                self.settle_locals()
                self.settle_top(ft.params, at, name)
                params_v = self.pop(list(ft.params), at, name)
                if op == LOOP:
                    entry, params_v = params_v, [self.new_vregs(t) for t in ft.params]
                    for dest, src in zip(params_v, entry):
                        self.move(dest, src)
                f = Frame(op, ft, len(self.stack), self.new_label(), params_v,
                          [self.new_vregs(t) for t in ft.results])
                for t, w in zip(ft.params, params_v):
                    self.push(t, words=w)
                self.ctrl.append(f)
                if op == LOOP:
                    self.loops += 1
                    self.label(f.label)
                if op == IF:
                    f.else_label = self.new_label()
                    if flags is None:
                        self.emit("MOVE[M]", "R0", cond_word)
                    self.emit(f"?{negate(flags or '!Z')} MOVE", "R15", f.else_label)
            elif op == 0x0C:  # br
                assert imm is not None
                f = self.frame(imm, at)
                self.moves(self.branch_moves(f, at, name))
                self.emit("MOVE", "R15", f.label)
                reachable = False
            elif op == 0x0D:  # br_if
                assert imm is not None
                (cond,) = self.pop([I32], at, name)
                f = self.frame(imm, at)
                moves = [(d, s) for d, s in self.branch_moves(f, at, name) if d != s]
                if flags is None:
                    flags = self.flags_of(cond[0])
                if flags is None:
                    self.emit("MOVE[M]", "R0", cond[0])
                    flags = "!Z"
                if moves:
                    skip = self.new_label()
                    self.emit(f"?{negate(flags)} MOVE", "R15", skip)
                    self.moves(moves)
                    self.emit("MOVE", "R15", f.label)
                    self.label(skip)
                else:
                    j = self.emit(f"?{flags} MOVE", "R15", f.label)
                    # The jump back at the end of a loop, which is usually
                    # taken: the next instructions end the blocks up to it.
                    j.back = (f.op == LOOP and r.pos + imm < r.end
                              and self.t.data[r.pos:r.pos + imm + 1] == b"\x0b" * (imm + 1))
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
                stubs: List[Tuple[str, List[Tuple[str, str]], str]] = []
                for depth, f in zip(targets, frames):
                    if depth in target:
                        continue
                    moves = [(d, s) for d, s in self.branch_moves(f, at, name) if d != s]
                    if not moves:
                        target[depth] = f.label
                        continue
                    target[depth] = self.new_label()
                    stubs.append((target[depth], moves, f.label))
                table = self.new_label()
                n = len(targets) - 1
                x = self.new_vreg()
                self.emit("MOVE", x, index[0])
                self.emit("SUB[M]", "R0", x, str(n))
                self.emit("?!C MOVE", "R15", target[targets[-1]])  # index >= n, unsigned
                jump = self.emit("MOVE", "R15", f"@{table}[{x}]")
                jump.kind, jump.targets = "jump", sorted(set(target.values()))
                self.label(table)
                self.body += [instr(".DAT", target[depth]) for depth in targets[:-1]]
                for label, moves, to in stubs:
                    self.label(label)
                    self.moves(moves)
                    self.emit("MOVE", "R15", to)
                reachable = False
            elif op == 0x1A:  # drop
                self.pop([None], at, name)
            elif op in (0x1B, 0x1C):  # select
                (cond,) = self.pop([I32], at, name)
                if sel_type is None and len(self.stack) > self.ctrl[-1].height:
                    sel_type = self.stack[-1]
                a, b = self.pop([sel_type, sel_type], at, name)  # underflow if None
                assert sel_type is not None
                # The result goes where the first value is, or would be.
                dest = self.push(sel_type)
                flags = self.flags_of(cond[0])
                self.move(dest, a)
                if flags is None:
                    self.emit("MOVE[M]", "R0", cond[0])
                    flags = "!Z"
                for k in range(len(a)):
                    self.emit(f"?{negate(flags)} MOVE", dest[k], b[k])
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
                    p = self.new_vreg()
                    if self.t.m.imports[imm].name == "peek":
                        (addr,) = self.pop([I32], at, "nice.peek")
                        self.emit("MOVE", p, addr[0])
                        self.emit("MOVE", self.push(I32)[0], f"@{p}")
                    else:
                        addr, value = self.pop([I32, I32], at, "nice.poke")
                        self.emit("MOVE", p, addr[0])
                        self.emit("MOVE", f"@{p}", value[0])
                else:
                    ft = self.t.func_type(imm)
                    fwd = (self.forward(r, at, ft.results[0], len(ft.params))
                           if len(ft.results) == 1 else None)
                    self.call(self.t.func_label(imm), ft, at, name, fwd)
            elif op == 0x11:  # call_indirect
                assert imm is not None
                self.call_indirect(imm, at, name)
            elif op == 0x20:  # local.get
                assert imm is not None
                t, src = self.local_operand(imm, at)
                self.push(t, Deferred(src, imm))
            elif op in (0x21, 0x22):  # local.set, local.tee
                assert imm is not None
                t, dest = self.local_operand(imm, at)
                (src,) = self.pop([t], at, name)
                # The local's old value, wherever it is still on the stack.
                self.settle_locals(imm)
                self.move(dest, src)
                if op == 0x22:
                    self.push(t, Deferred(dest, imm))
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
            elif op in (0x41, 0x42, 0x43, 0x44):  # the constants
                assert imm is not None
                t = {0x41: I32, 0x42: I64, 0x43: F32, 0x44: F64}[op]
                self.push(t, Deferred(words(imm, t), None))
            elif op in (0x45, 0x50):  # i32.eqz, i64.eqz
                t = I32 if op == 0x45 else I64
                (a,) = self.pop([t], at, name)
                fused = flags is not None  # by a comparison, for a br_if or if after this
                if flags is None:
                    flags = self.flags_of(a[0]) if t == I32 else None
                if flags is None:
                    if t == I32:
                        self.emit("MOVE[M]", "R0", a[0])
                    else:
                        self.emit("OR[M]", "R0", a[0], a[1])
                    flags = "!Z"
                zero = negate(flags)  # the condition that a is 0
                d = self.push(I32)[0]
                if fused or self.fuses(r):
                    pending = zero
                else:
                    self.emit("MOVE", d, "0")
                    self.emit(f"?{zero} MOVE", d, "1")
                    self.flag_val = ({d}, zero, [])
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
                size = "@W.pages" if self.t.growable else str(self.t.m.memory_pages)
                self.emit("MOVE", self.push(I32)[0], size)
            elif op == 0x40:  # memory.grow
                assert self.t.m.memory_pages is not None
                if self.t.growable:
                    self.t.helpers.add("W.grow")
                    self.call("W.grow", FuncType([I32], [I32]), at, name)
                else:
                    # The memory is at its cap, so only growing by 0 pages
                    # succeeds. It returns the size, and anything else -1.
                    (delta,) = self.pop([I32], at, name)
                    d = self.push(I32)[0]
                    self.emit("MOVE[M]", "R0", delta[0])
                    self.emit("MOVE", d, "-1")
                    self.emit("?Z MOVE", d, str(self.t.m.memory_pages))
            elif op in SHIFT_OPS:
                count = self.const_value(1)
                fwd = self.forward(r, at, I32, 2)
                a, b = self.pop([I32, I32], at, name)
                d = self.push(I32)[0] if fwd is None else fwd[0][0]
                shift = SHIFT_OPS[op]
                if shift in ("rotl", "rotr"):
                    # Only the count modulo 32 matters to a rotation (§5.2).
                    self.emit("ROL" if shift == "rotl" else "ROR", d, a[0], b[0])
                else:
                    # Wasm takes the count modulo 32 (§9.4).
                    if count is not None:
                        c = str(count & 31)
                    else:
                        c = self.new_vreg()
                        self.emit("AND", c, b[0], "31")
                    if shift == "shr_s":
                        self.emit("C<0[M]", "R0", a[0], "1")   # C = the sign bit (§5.2)
                    widx = ""
                    if shift == "shl" and count is not None and count & 31 > 2:
                        # A word index for an address d, in case one is
                        # needed. If none is, the allocator removes it.
                        widx = self.new_vreg()
                        self.emit("SHL", widx, a[0], str((count & 31) - 2))
                    self.emit({"shl": "SHL", "shr_u": "SHR", "shr_s": "C>0"}[shift], d, a[0], c)
                    if widx or (shift == "shl" and count is not None and count & 31 == 2
                                and VREG_RE.fullmatch(a[0]) and a[0] != d):
                        self.word_index[d] = (widx or a[0], True)
                if fwd is not None and fwd[1] is not None:
                    self.push(I32, fwd[1])
            elif op in SHIFT64_OPS:
                self.shift64(SHIFT64_OPS[op], at, name)
            elif op in CMP_OPS:
                pending = self.compare(I32, *CMP_OPS[op], at, name, self.fuses(r))
            elif op in CMP64_OPS:
                pending = self.compare(I64, *CMP64_OPS[op], at, name, self.fuses(r))
            elif op in ALU_OPS:
                consts = self.const_value(2), self.const_value(1)
                fwd = self.forward(r, at, I32, 2)
                a, b = self.pop([I32, I32], at, name)
                widx = self.index_of_sum(a[0], b[0], *consts) if op == 0x6A else ""
                if fwd is None:
                    d = self.push(I32)[0]
                    self.emit(ALU_OPS[op], d, a[0], b[0])
                else:
                    d = fwd[0][0]
                    self.emit(ALU_OPS[op], d, a[0], b[0])
                    if fwd[1] is not None:
                        self.push(I32, fwd[1])
                if widx:
                    self.word_index[d] = (widx, True)
            elif op in ALU64_OPS:
                a, b = self.pop([I64, I64], at, name)
                dest = self.push(I64)
                for k, mnemonic in enumerate(ALU64_OPS[op]):
                    self.emit(mnemonic, dest[k], a[k], b[k])
            elif op in (0x10A, 0x10B):  # memory.copy, memory.fill
                self.bulk("copy" if op == 0x10A else "fill", at, name)
            elif op in FLOAT_OPS:
                routine, params, result = FLOAT_OPS[op]
                self.call(f"_{routine}", FuncType(params, [result]), at, name)
            elif op in TRUNC_OPS or op in TRUNC_SAT_OPS:
                if op in TRUNC_OPS:
                    self.trunc_check(*TRUNC_OPS[op][1:], at, name)
                routine, src_t, dst_t, _, _ = TRUNC_OPS[TRUNC_SAT_OPS.get(op, op)]
                self.call(f"_{routine}", FuncType([src_t], [dst_t]), at, name)
            elif op in FLOAT_CMP_OPS:
                t, routine, test = FLOAT_CMP_OPS[op]
                self.call(f"_{routine}", FuncType([t, t], [I32]), at, name)
                (res,) = self.pop([I32], at, name)
                d = self.push(I32)[0]
                self.emit("MOVE[M]", "R0", res[0])
                # The flags of the routine's result in R1 give the answer.
                if test in ("==", "!="):
                    self.emit("MOVE", d, "0")
                    self.emit("?Z MOVE" if test == "==" else "?!Z MOVE", d, "1")
                elif test in ("<", "<="):
                    self.emit("MOVE", d, "0")
                    self.emit("?N MOVE", d, "1")
                    if test == "<=":
                        self.emit("?Z MOVE", d, "1")
                else:
                    self.emit("MOVE", d, "1")
                    self.emit("?N MOVE", d, "0")
                    if test == ">":
                        self.emit("?Z MOVE", d, "0")
            elif op in REINTERPRET_OPS:
                src_t, dst_t = REINTERPRET_OPS[op]
                deferred = self.deferred[-1] if len(self.stack) > self.ctrl[-1].height else None
                (a,) = self.pop([src_t], at, name)
                self.push(dst_t, deferred, a)  # the same words, unchanged
            elif op in SIGN_OPS:
                t, sign_op = SIGN_OPS[op]
                values = self.pop([t, t] if sign_op == "copysign" else [t], at, name)
                dest = self.push(t)  # where the first value is, or would be
                a = values[0]
                self.move(dest[:-1], a[:-1])
                top, a_top = dest[-1], a[-1]  # the word with the sign bit
                if sign_op == "abs":
                    self.emit("AND", top, a_top, "0x7FFFFFFF")
                elif sign_op == "neg":
                    self.emit("XOR", top, a_top, "0x80000000")
                else:
                    x = self.new_vreg()
                    self.emit("AND", x, values[1][-1], "0x80000000")
                    self.emit("AND", top, a_top, "0x7FFFFFFF")
                    self.emit("OR", top, top, x)
            elif op == 0x6C and self.mul_const(r, at, name):
                pass
            elif op == 0x7E and self.mul64_const(r, at, name):
                pass
            elif op == 0x6C and self.t.mpu:
                self.mpu_op("umul_lo", I32, at, name)
            elif op in LIB_OPS:
                routine, (params, results) = LIB_OPS[op]
                fwd = self.forward(r, at, results[0], len(params))
                self.call(routine, FuncType(params, results), at, name, fwd)
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
                    x = self.new_vreg()
                    self.emit("AND", x, a[0], str((1 << bits) - 1))
                    self.emit("XOR", x, x, sign)
                    self.emit("SUB[M]" if t == I64 else "SUB", ext[0], x, sign)
                if t == I64:
                    self.emit("MOVE", ext[1], "0")
                    self.emit("?N MOVE", ext[1], "-1")
            elif op == 0xA7:  # i32.wrap_i64
                deferred = self.deferred[-1] if len(self.stack) > self.ctrl[-1].height else None
                (a,) = self.pop([I64], at, name)
                if deferred is not None:
                    # The low word of the constant or the local.
                    self.push(I32, Deferred(a[:1], deferred.local))
                else:
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
        return self.finish()

    def ret(self, at: int, what: str) -> None:
        """Moves the result into R1, or R1 and R2, for return and for the
        final end. The values below it are dropped."""
        results = self.pop(list(self.ftype.results), at, what)
        for rt, src in zip(self.ftype.results, results):
            self.move([f"R{k + 1}" for k in range(SIZES[rt])], src)

    def finish(self) -> List[str]:
        """The back end: copies the parameters to their registers and sets
        the other locals to 0, allocates the registers, and adds the
        prologue and the epilogue, which build and drop the §9.3 frame."""
        entry: List[Item] = []
        for i, (in_reg, first) in enumerate(self.args):
            for k, v in enumerate(self.locals[i]):
                entry.append(Ins("MOVE", [v, f"R{first + k}" if in_reg else f"@%a{first + k}"]))
        for i in range(len(self.args), len(self.locals)):
            for v in self.locals[i]:
                entry.append(Ins("MOVE", [v, "0"]))  # wasm zeroes locals
        n_results = sum(SIZES[t] for t in self.ftype.results)
        exit_ins = Ins("RET", [], kind="exit",
                       uses=frozenset(f"R{k + 1}" for k in range(n_results)))
        alloc = Allocator(entry + self.body + [Label(self.ret_label), exit_ins] + self.stubs,
                          ALLOC_REGS, CALLEE_SAVED, self.n_vregs)
        items = if_convert(tidy(alloc.run()))
        saved = [r for r in CALLEE_SAVED if r in alloc.used]
        n_slots = alloc.n_slots
        items = tidy(duplicate_tails(items, len(saved) + 1 + (n_slots > 0)))
        items = fill_jump_slots(invert_back_edges(items, f"{self.t.prefix}f{self.idx}.B"))
        name = printable(self.t.m.names.get(self.idx, ""))
        out = [f"; Function {self.idx}" + (f": {name}" if name else "")]
        out += self.t.labels.get(self.idx, [])
        out.append(f"{self.t.prefix}f{self.idx}")
        for r in saved:
            out.append(instr("MOVE", "@--R13", r))
        if n_slots:
            out.append(instr("SUB", "R13", "R13", str(n_slots)))
        frame_words(items, n_slots, len(saved))
        fix_calls(items)
        for it in items:
            if not (isinstance(it, Ins) and it.op == "RET"):
                out += render([it])
                continue
            if n_slots:
                out.append(instr("ADD", "R13", "R13", str(n_slots)))
            for r in reversed(saved):
                out.append(instr("MOVE", r, "@R13++"))  # last saved first
            out.append(instr("MOVE", "R15", "@R13++"))
        return out


def translate(data: bytes, source: str, checks: bool = True, library: Optional[str] = None,
              library_memory: Optional[int] = None,
              memory_pages: Optional[int] = None, mpu: bool = True) -> List[str]:
    return Translator(parse(data), data, checks, library, library_memory,
                      memory_pages, mpu).run(source)


def main() -> None:
    ap = argparse.ArgumentParser(description="Translates a WebAssembly module into NICE assembly.")
    ap.add_argument("input", help="wasm module (.wasm)")
    ap.add_argument("-o", dest="output",
                    help="output file (default: input with .nasm extension)")
    ap.add_argument("--no-bounds-checks", action="store_true",
                    help="do not check that memory accesses are in bounds")
    ap.add_argument("--memory-pages", metavar="N", type=int,
                    help="pages up to which memory.grow may grow the memory"
                         " (default: its initial size)")
    ap.add_argument("--library", metavar="NAME",
                    help="translate a library module (ISA.md §9.4) with this name")
    ap.add_argument("--library-memory", metavar="BYTES", type=int,
                    help="bytes of a library module's memory to reserve"
                         " (default: as much as its data and stack need)")
    ap.add_argument("--no-mpu", action="store_true",
                    help="call the runtime library for i32 mul, and for div and rem, instead of"
                         " using the math unit")
    args = ap.parse_args()

    out = args.output or os.path.splitext(args.input)[0] + ".nasm"
    try:
        with open(args.input, "rb") as f:
            data = f.read()
        if os.path.exists(out) and os.path.samefile(out, args.input):
            sys.exit(f"{args.input}: the output file would overwrite the input; use -o")
    except OSError as e:
        sys.exit(f"{e.filename}: {e.strerror}")

    try:
        if args.library is not None and not C_IDENT.match(args.library):
            sys.exit(f"--library: {args.library!r} is not a C identifier")
        if args.library_memory is not None and args.library is None:
            sys.exit("--library-memory: only a library module (--library) takes it")
        if args.memory_pages is not None and args.library is not None:
            sys.exit("--memory-pages: a library module (--library) cannot grow its memory")
        lines = translate(data, os.path.basename(args.input), not args.no_bounds_checks,
                          args.library, args.library_memory, args.memory_pages,
                          not args.no_mpu)
    except WasmError as e:
        where = "" if e.offset is None else f":0x{e.offset:x}"
        print(f"{args.input}{where}: error: {e}", file=sys.stderr)
        sys.exit(1)

    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
