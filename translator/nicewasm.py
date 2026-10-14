#!/usr/bin/env python3
"""nicewasm - translates a WebAssembly module into NICE assembly.

Implements the WebAssembly mapping of doc/ISA.md section 9.4. The output is
one assembly file, to be joined with the start-up code, the program's other
files, and the runtime library as section 9.3 describes.

Usage: nicewasm.py [-o output.asm] input.wasm

This is a first version: it supports only a few instructions and only the
i32 type. README.md lists what it supports. Anything else is rejected with an
error, never translated wrongly.

Each function keeps its locals and its wasm operand stack in its frame on
the NICE stack, one word per value, addressed from FP (R12). Operand stack
depth d is one fixed word, so every instruction is a few NICE instructions
on frame words.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

I32, I64, F32, F64 = 0x7F, 0x7E, 0x7D, 0x7C
TYPE_NAMES = {I32: "i32", I64: "i64", F32: "f32", F64: "f64", 0x7B: "v128",
              0x70: "funcref", 0x6F: "externref"}

WORDS_PER_PAGE = 16384  # 65536 bytes, four to a word
ZERO_UNROLL = 16        # words cleared per pass of ___wasm_start's loop; divides a page

# Section ids in the order a module must give them. Custom sections (0) may
# come anywhere.
SECTION_ORDER = [1, 2, 3, 4, 5, 13, 6, 7, 8, 9, 12, 10, 11]

C_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")

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

# The i32 operations that are one NICE instruction: wasm opcode -> mnemonic.
ALU_OPS = {0x6A: "ADD", 0x6B: "SUB", 0x71: "AND", 0x72: "OR", 0x73: "XOR"}


class WasmError(Exception):
    def __init__(self, msg: str, offset: Optional[int] = None) -> None:
        super().__init__(msg)
        self.offset = offset


@dataclass
class FuncType:
    params: List[int]
    results: List[int]


@dataclass
class Import:
    module: str
    name: str
    type_idx: int


@dataclass
class Global:
    mutable: bool
    init: int


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
        if signed and b & 0x40 and shift < 64:
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
        if t != I32:
            raise WasmError(f"{what} has type {type_name(t)}; only i32 is supported yet", offset)


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
                if name in ("peek", "poke"):
                    raise WasmError(f"{what} is not supported yet", at)
                raise WasmError(f"{what}: the module 'nice' has only peek and poke", at)
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
        # Tables matter only to call_indirect, which is not supported yet.
        for _ in range(s.u32()):
            s.byte()
            parse_limits(s, "table")
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
            if s.byte() != 0x41:
                raise WasmError(f"global {i}: the initial value must be an i32.const", at)
            init = s.s32()
            if s.byte() != 0x0B:
                raise WasmError(f"global {i}: the initial value must be an i32.const", at)
            m.globals.append(Global(mutable, init))
    elif sec_id == 7:
        for _ in range(s.u32()):
            name = s.name()
            kind = s.byte()
            m.exports.append((name, kind, s.u32()))
    elif sec_id == 8:
        m.start = s.u32()
    elif sec_id == 9:
        if s.u32():
            raise WasmError("element segments are not supported yet", sec_start)
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
        if s.u32():
            raise WasmError("data segments are not supported yet", sec_start)
    elif sec_id == 12:
        s.u32()
    elif sec_id == 13:
        raise WasmError("exception tags are not supported", sec_start)


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
    return f"        {mnemonic:<8}{', '.join(operands)}".rstrip()


class Translator:
    def __init__(self, m: Module, data: bytes) -> None:
        self.m = m
        self.data = data
        self.labels: Dict[int, List[str]] = {}         # function index -> export labels
        self.global_labels: Dict[int, List[str]] = {}  # global index -> export labels
        self.ctors: Optional[int] = None
        n_imports = len(m.imports)
        for name, kind, idx in m.exports:
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
        out = [f"; Translated from {source} by nicewasm (doc/ISA.md §9.4).", ""]
        out.append("; Sets the memory to 0, then calls the start function and")
        out.append("; __wasm_call_ctors, if the module has them.")
        out.append("___wasm_start")
        if self.m.memory_pages:
            # The memory is reserved with .RES, so it is not in the program
            # image. Each pass of the loop clears ZERO_UNROLL words.
            out.append(instr("MOVE", "R5", "___wasm_memory"))
            out.append(instr("MOVE", "R6", str(self.m.memory_pages * WORDS_PER_PAGE // ZERO_UNROLL)))
            out.append("W.zero")
            out += [instr("MOVE", "@R5++", "R0")] * ZERO_UNROLL
            out.append(instr("DEC[M]", "R6", "R6"))
            out.append("        ?!Z MOVE R15, W.zero")
        for idx in (self.m.start, self.ctors):
            if idx is not None:
                out.append(instr("ADD", "@--R13", "2", "R15"))
                out.append(instr("MOVE", "R15", self.func_label(idx)))
        out.append(instr("MOVE", "R15", "@R13++"))
        n_imports = len(self.m.imports)
        for i, code in enumerate(self.m.codes):
            out.append("")
            out += FunctionTranslator(self, n_imports + i, code).run()
        if self.m.globals:
            out += ["", "; Globals"]
            for i, g in enumerate(self.m.globals):
                out += self.global_labels.get(i, [])
                out.append(f"W.g{i}")
                out.append(instr(".DAT", str(g.init)))
        if self.m.memory_pages is not None:
            pages = self.m.memory_pages
            out += ["", f"; Linear memory: {pages} page{'' if pages == 1 else 's'}",
                    "___wasm_memory", instr(".RES", str(pages * WORDS_PER_PAGE))]
        return out


class FunctionTranslator:
    """Translates one function. Local i is the frame word at FP + local[i].
    Operand stack depth d is the frame word at FP - 1 - n_slots - d."""

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
        self.local: List[int] = []
        self.n_slots = 0
        for i in range(len(self.ftype.params)):
            if i < 4:
                self.n_slots += 1
                self.local.append(-self.n_slots)
            else:
                self.local.append(2 + i - 4)
        for _ in code.locals:
            self.n_slots += 1
            self.local.append(-self.n_slots)
        self.depth = 0
        self.max_depth = 0
        self.body: List[str] = []
        self.ret_label = f"W.f{idx}.ret"

    def slot(self, d: int) -> str:
        return operand(-1 - self.n_slots - d)

    def top(self, n: int = 1) -> str:
        """The nth value from the top of the operand stack."""
        return self.slot(self.depth - n)

    def pop(self, n: int, at: int) -> None:
        if self.depth < n:
            raise WasmError(f"function {self.idx}: operand stack underflow", at)
        self.depth -= n

    def push(self) -> str:
        self.depth += 1
        self.max_depth = max(self.max_depth, self.depth)
        return self.top()

    def emit(self, mnemonic: str, *operands: str) -> None:
        self.body.append(instr(mnemonic, *operands))

    def call(self, label: str, ft: FuncType, at: int) -> None:
        """Calls label with the arguments on top of the operand stack, by
        the rules of §9.3 for i32 arguments, and pushes the result."""
        n = len(ft.params)
        self.pop(n, at)
        args = [self.slot(self.depth + i) for i in range(n)]
        for i in reversed(range(4, n)):
            self.emit("MOVE", "@--R13", args[i])
        for i in range(min(n, 4)):
            self.emit("MOVE", f"R{i + 1}", args[i])
        self.emit("ADD", "@--R13", "2", "R15")
        self.emit("MOVE", "R15", label)
        if n > 4:
            self.emit("ADD", "R13", "R13", str(n - 4))
        if ft.results:
            self.emit("MOVE", self.push(), "R1")

    def local_operand(self, i: int, at: int) -> str:
        if i >= len(self.local):
            raise WasmError(f"function {self.idx}: local {i} does not exist", at)
        return operand(self.local[i])

    def global_operand(self, i: int, at: int) -> str:
        if i >= len(self.t.m.globals):
            raise WasmError(f"function {self.idx}: global {i} does not exist", at)
        return f"@W.g{i}"

    def run(self) -> List[str]:
        r = Reader(self.t.data, self.code.start, self.code.end)
        reachable = True
        while True:
            at = r.pos
            op = r.byte()
            name = OPCODES.get(op, f"opcode 0x{op:02x}")
            if op in (0x10, 0x20, 0x21, 0x22, 0x23, 0x24):
                imm: Optional[int] = r.u32()
            elif op == 0x41:
                imm = r.s32()
            elif op in (0x00, 0x01, 0x0B, 0x0F, 0x1A, 0x6C) or op in ALU_OPS:
                imm = None
            else:
                raise WasmError(f"function {self.idx}: {name} is not supported yet", at)
            if op == 0x0B:
                # Without blocks, the only end is the function's own.
                if not r.at_end():
                    raise WasmError(f"function {self.idx}: code after the function's end", r.pos)
                if reachable:
                    self.body.append("        ; end")
                    self.ret(at)
                break
            if not reachable:
                continue
            self.body.append(f"        ; {name}" + ("" if imm is None else f" {imm}"))
            if op == 0x01:  # nop
                pass
            elif op == 0x1A:  # drop
                self.pop(1, at)
            elif op == 0x0F:  # return
                self.ret(at)
                self.emit("MOVE", "R15", self.ret_label)
                reachable = False
            elif op == 0x10:  # call
                assert imm is not None
                if imm >= len(self.t.m.imports) + len(self.t.m.funcs):
                    raise WasmError(f"function {self.idx}: function {imm} does not exist", at)
                self.call(self.t.func_label(imm), self.t.func_type(imm), at)
            elif op == 0x20:  # local.get
                assert imm is not None
                src = self.local_operand(imm, at)
                self.emit("MOVE", self.push(), src)
            elif op in (0x21, 0x22):  # local.set, local.tee
                assert imm is not None
                dest = self.local_operand(imm, at)
                self.pop(1, at)
                self.emit("MOVE", dest, self.slot(self.depth))
                if op == 0x22:
                    self.depth += 1
            elif op == 0x23:  # global.get
                assert imm is not None
                src = self.global_operand(imm, at)
                self.emit("MOVE", self.push(), src)
            elif op == 0x24:  # global.set
                assert imm is not None
                dest = self.global_operand(imm, at)
                self.pop(1, at)
                self.emit("MOVE", dest, self.slot(self.depth))
            elif op == 0x41:  # i32.const
                assert imm is not None
                self.emit("MOVE", self.push(), str(imm))
            elif op in ALU_OPS:
                self.pop(2, at)
                a, b = self.slot(self.depth), self.slot(self.depth + 1)
                self.emit(ALU_OPS[op], self.push(), a, b)
            elif op == 0x6C:  # i32.mul
                self.call("__mul", FuncType([I32, I32], [I32]), at)
            elif op == 0x00:
                raise WasmError(f"function {self.idx}: unreachable is not supported yet", at)
        return self.wrap()

    def ret(self, at: int) -> None:
        """Moves the result into R1, for return and for the final end."""
        n = len(self.ftype.results)
        if self.depth < n:
            raise WasmError(f"function {self.idx}: operand stack underflow", at)
        if n:
            self.emit("MOVE", "R1", self.top())

    def wrap(self) -> List[str]:
        """Adds the prologue and the epilogue, which build and drop the
        §9.3 frame."""
        name = self.t.m.names.get(self.idx)
        out = [f"; Function {self.idx}" + (f": {name}" if name else "")]
        out += self.t.labels.get(self.idx, [])
        out.append(f"W.f{self.idx}")
        out.append(instr("MOVE", "@--R13", "R12"))
        out.append(instr("MOVE", "R12", "R13"))
        size = self.n_slots + self.max_depth
        if size:
            out.append(instr("SUB", "R13", "R13", str(size)))
        for i in range(min(len(self.ftype.params), 4)):
            out.append(instr("MOVE", operand(self.local[i]), f"R{i + 1}"))
        for i in range(len(self.ftype.params), len(self.local)):
            out.append(instr("MOVE", operand(self.local[i]), "0"))  # wasm zeroes locals
        out += self.body
        out.append(self.ret_label)
        out.append(instr("MOVE", "R13", "R12"))
        out.append(instr("MOVE", "R12", "@R13++"))
        out.append(instr("MOVE", "R15", "@R13++"))
        return out


def translate(data: bytes, source: str) -> List[str]:
    return Translator(parse(data), data).run(source)


def main() -> None:
    ap = argparse.ArgumentParser(description="Translates a WebAssembly module into NICE assembly.")
    ap.add_argument("input", help="wasm module (.wasm)")
    ap.add_argument("-o", dest="output",
                    help="output file (default: input with .asm extension)")
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
        lines = translate(data, os.path.basename(args.input))
    except WasmError as e:
        where = "" if e.offset is None else f":0x{e.offset:x}"
        print(f"{args.input}{where}: error: {e}", file=sys.stderr)
        sys.exit(1)

    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
