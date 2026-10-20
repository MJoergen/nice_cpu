#!/usr/bin/env python3
"""Tests of nicewasm's errors. Each case is a module that must fail with exit
status 1, print the expected error, and write no output file."""

from __future__ import annotations

import concurrent.futures
import os
import subprocess
import sys
import tempfile
from typing import List, Optional, Tuple

from wasm import call_indirect, table
V128 = 0x7B  # a type nicewasm does not support
from wasm import (ADD, ADD64, DROP, ELSE, END, F32, I32, I64, SELECT, block, br,
                  br_table, call, code, exports, funcs, global_get, global_set, globals_,
                  i32_const, i64_const, if_, imports, local_get, local_set, local_tee, memory, module,
                  name, section, start, types, u, vec)

NICEWASM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "nicewasm.py")

MAIN = types(([], [I32]))


def one(body: bytes, n_locals: int = 0) -> bytes:
    """A module with one function, () -> i32."""
    return module(MAIN, funcs(0), code((n_locals, body)))


# (module, expected error message)
CASES: List[Tuple[bytes, str]] = [
    # The file
    (b"junk", "not a wasm module (no '\\0asm' at the start)"),
    (b"\0asm\2\0\0\0", "unsupported wasm version (only version 1 is supported)"),
    (module(MAIN)[:-1], "section 1 runs past the end of the file"),
    (module(funcs(), MAIN), "section 1 is out of order or repeated"),
    (module(MAIN, MAIN), "section 1 is out of order or repeated"),
    (module(section(14, b"")), "unknown section 14"),
    (module(section(1, b"\x01")), "unexpected end of data"),
    (module(section(7, b"\x01\x05ab")), "unexpected end of data"),
    (module(section(7, b"\x01\x01\xff\x00\x00")), "name is not valid UTF-8"),
    (module(section(1, b"\x01\x50\x00\x00")), "expected a function type (0x60)"),
    (module(MAIN, funcs(0), section(10, b"\x01\x05\x00\x0b")),
     "function body runs past the end of the section"),
    # 50001 locals of type i32.
    (module(MAIN, funcs(0), section(10, vec([u(6) + b"\x01" + u(50001) + b"\x7f\x0b"]))),
     "too many locals"),
    (module(section(1, b"\x01\x60\x00\x00\x00")), "section 1 has 1 bytes left over"),
    (module(MAIN, funcs(0)), "the function and code sections differ in length (1 and 0)"),
    (module(MAIN, funcs(3)), "type index 3 is out of range"),
    # LEB128: the unused bits of the last byte must repeat the sign, and an
    # i64 takes at most 10 bytes.
    (one(b"\x41\x80\x80\x80\x80\x70"), "integer too large"),
    (one(b"\x42" + b"\x80" * 9 + b"\x01"), "integer too large"),
    (one(b"\x42" + b"\x80" * 10), "integer too long"),
    # Imports
    (module(section(2, vec([name("env") + name("mem") + b"\x02\x00\x01"]))),
     "import env.mem is a memory; only functions may be imported"),
    (module(section(2, vec([name("env") + name("sp") + b"\x03\x7f\x01"]))),
     "import env.sp is a global; only functions may be imported"),
    (module(section(2, vec([name("env") + name("t") + b"\x01\x70\x00\x01"]))),
     "import env.t is a table; only functions may be imported"),
    (module(types(([], [I32, I32])), imports(("env", "f", 0))),
     "import env.f: more than one result is not supported yet"),
    (module(MAIN, imports(("wasi", "fd_write", 0))),
     "import wasi.fd_write: functions may be imported only from 'env' and 'nice'"),
    (module(MAIN, imports(("nice", "peek", 0))),
     "import nice.peek must have the type (i32) -> (i32)"),
    (module(types(([I32], [I32])), imports(("nice", "poke", 0))),
     "import nice.poke must have the type (i32, i32) -> ()"),
    (module(types(([I32], [I32])), imports(("nice", "peek", 0)), table(1),
            section(9, vec([b"\0" + i32_const(0) + b"\x0b" + vec([u(0)])]))),
     "element segment 0: nice.peek has no address, so it cannot be in a table"),
    (module(MAIN, imports(("nice", "load", 0))),
     "import nice.load: the module 'nice' has only peek and poke"),
    (module(MAIN, imports(("env", "a-b", 0))),
     "import env.a-b: the name is not a C identifier, so it has no label"),
    (module(MAIN, imports(("env", "__multi3", 0))),
     "import env.__multi3: names that start with _ are reserved for the runtime library,"
     " which has no routines for C's long double and __int128"),
    (module(types(([V128], [])), imports(("env", "f", 0))),
     "import env.f has type v128; only i32, i64, f32, and f64 are supported"),
    # Module contents
    (module(section(4, vec([b"\x70\x04" + u(1)]))), "a shared or 64-bit table is not supported"),
    (module(section(6, vec([bytes([I32, 2]) + i32_const(0) + b"\x0b"]))),
     "global 0: the mutability must be 0 or 1, not 2"),
    (module(MAIN, funcs(0), exports(("memory", 2, 0)), code((0, i32_const(0)))),
     "export memory: memory 0 does not exist"),
    (module(MAIN, funcs(0), table(1), exports(("t", 1, 1)), code((0, i32_const(0)))),
     "export t: table 1 does not exist"),
    (module(MAIN, funcs(0), exports(("e", 4, 0)), code((0, i32_const(0)))),
     "export e: only functions, tables, memories, and globals can be exported"),
    # The import is called at _f, so the export would take its label.
    (module(MAIN, imports(("env", "f", 0)), funcs(0), exports(("f", 0, 1)),
            code((0, i32_const(0)))),
     "export f: the import env.f has the same label _f"),
    (module(types(([], [I32]), ([], [I32, I32])), funcs(0), table(1),
            code((0, i32_const(0) + call_indirect(1) + DROP))),
     "function 0: call_indirect: more than one result is not supported yet"),
    (module(memory(1), memory(1)), "section 5 is out of order or repeated"),
    (module(section(5, vec([b"\0\1", b"\0\1"]))), "a module may have only one memory"),
    (module(section(5, vec([b"\x03\x01\x01"]))), "a shared or 64-bit memory is not supported"),
    (module(section(6, vec([bytes([V128, 1, 0xfd, 0x0c] + [0] * 16 + [0x0b])]))),
     "global 0 has type v128; only i32, i64, f32, and f64 are supported"),
    (module(section(6, vec([bytes([F32, 1, 0x41, 0, 0x0b])]))),
     "global 0: the initial value must be an f32.const"),
    (module(section(6, vec([bytes([I32, 1, 0x23, 0, 0x0b])]))),
     "global 0: the initial value must be an i32.const"),
    (module(section(6, vec([bytes([I64, 1, 0x41, 0, 0x0b])]))),
     "global 0: the initial value must be an i64.const"),
    # extended-const: an expression is not supported.
    (module(section(6, vec([bytes([I32, 1]) + i32_const(1) + i32_const(2) + ADD + b"\x0b"]))),
     "global 0: the initial value must be an i32.const"),
    # Tables and element segments
    (module(section(9, vec([b"\0" + i32_const(0) + b"\x0b" + vec([u(0)])]))),
     "element segment 0: the module has no table"),
    (module(section(4, vec([b"\x70\x00\x01", b"\x70\x00\x01"]))), "a module may have only one table"),
    (module(section(4, vec([b"\x6f\x00\x01"]))), "table 0 holds externref; only funcref is supported"),
    (module(MAIN, funcs(0), table(1), section(9, vec([b"\0" + i32_const(0) + b"\x0b" + vec([u(0), u(0)])])),
            code((0, i32_const(0)))),
     "element segment 0 does not fit in the table"),
    (module(MAIN, funcs(0), table(1), section(9, vec([b"\0" + i32_const(0) + b"\x0b" + vec([u(1)])])),
            code((0, i32_const(0)))),
     "element segment 0: function 1 does not exist"),
    (module(table(1), section(9, vec([b"\x01\x00" + vec([u(0)])]))),
     "element segment 0 is passive; table.init is not supported yet"),
    (module(table(1), section(9, vec([b"\x02\x01" + i32_const(0) + b"\x0b\x00" + vec([u(0)])]))),
     "element segment 0: table 1 does not exist"),
    (module(table(1), section(9, vec([b"\0" + global_get(0) + b"\x0b" + vec([u(0)])]))),
     "element segment 0: the offset must be an i32.const"),
    # The offset's constant must be followed by end.
    (module(table(1), section(9, vec([b"\0" + i32_const(0) + b"\x01" + vec([u(0)])]))),
     "element segment 0: the offset must be an i32.const"),
    (module(table(1), section(9, vec([b"\x06\x00" + i32_const(0) + b"\x0b\x6f" + vec([b"\xd0\x6f\x0b"])]))),
     "element segment 0: only functions are supported"),
    (module(table(1), section(9, vec([b"\x04" + i32_const(0) + b"\x0b" + vec([i32_const(0) + b"\x0b"])]))),
     "element segment 0: an element must be ref.func or ref.null"),
    # A ref.func must be followed by end.
    (module(table(1), section(9, vec([b"\x04" + i32_const(0) + b"\x0b" + vec([b"\xd2\x00\x01"])]))),
     "element segment 0: an element must be ref.func or ref.null"),
    (module(table(1), section(9, vec([b"\x08"]))), "element segment 0 has unknown flags 8"),
    # Data segments
    (module(section(11, vec([b"\0" + i32_const(0) + b"\x0b" + vec([b"x"])]))),
     "data segment 0: the module has no memory"),
    (module(memory(1), section(11, vec([b"\0" + i32_const(65535) + b"\x0b" + vec([b"x", b"y"])]))),
     "data segment 0 does not fit in the memory"),
    (module(memory(1), section(11, vec([b"\0" + i32_const(-1) + b"\x0b" + vec([b"x"])]))),
     "data segment 0 does not fit in the memory"),
    (module(memory(0), section(11, vec([b"\0" + i32_const(0) + b"\x0b" + vec([b"x"])]))),
     "data segment 0 does not fit in the memory"),
    (module(memory(1), section(11, vec([b"\x01" + vec([b"x"])]))),
     "data segment 0 is passive; memory.init is not supported yet"),
    (module(memory(1), section(11, vec([b"\x02\x01" + i32_const(0) + b"\x0b" + vec([b"x"])]))),
     "data segment 0: memory 1 does not exist"),
    (module(memory(1), section(11, vec([b"\x03"]))), "data segment 0 has unknown flags 3"),
    (module(memory(1), section(11, vec([b"\0" + global_get(0) + b"\x0b" + vec([b"x"])]))),
     "data segment 0: the offset must be an i32.const"),
    (module(memory(1), section(11, vec([b"\0" + i32_const(0) + i32_const(0) + ADD + b"\x0b"
                                        + vec([b"x"])]))),
     "data segment 0: the offset must be an i32.const"),
    (module(memory(1), section(12, u(2)), section(11, vec([b"\0" + i32_const(0) + b"\x0b"
                                                         + vec([b"x"])]))),
     "the data count section says 2 segments, but there are 1"),
    (module(section(13, vec([b"\0\0"]))), "exception tags are not supported"),
    (module(MAIN, imports(("env", "f", 0)), exports(("f", 0, 0))),
     "export f: exporting an imported function is not supported"),
    (module(MAIN, exports(("f", 0, 0))), "export f: function 0 does not exist"),
    (module(MAIN, exports(("g", 3, 0))), "export g: global 0 does not exist"),
    (module(MAIN, funcs(0), exports(("f", 0, 0), ("f", 0, 0)), code((0, i32_const(0)))),
     "export f: the name is exported twice"),
    (module(types(([I32], [])), funcs(0), exports(("__wasm_call_ctors", 0, 0)), code((0, b""))),
     "__wasm_call_ctors must have no parameters and no results"),
    (module(MAIN, funcs(0), start(0), code((0, i32_const(0)))),
     "the start function must have no parameters and no results"),
    (module(MAIN, start(1)), "start function 1 does not exist"),
    # Functions
    (module(types(([V128], [])), funcs(0), code((0, b""))),
     "function 0 has type v128; only i32, i64, f32, and f64 are supported"),
    (module(MAIN, funcs(0), section(10, vec([u(6) + vec([u(1) + bytes([V128])]) + i32_const(0) + b"\x0b"]))),
     "function 0: a local has type v128; only i32, i64, f32, and f64 are supported"),
    (module(types(([], [I32, I32])), funcs(0), code((0, i32_const(1) + i32_const(2)))),
     "function 0: more than one result is not supported yet"),
    (one(i32_const(0) + b"\x25\x00"), "function 0: table.get is not supported yet"),
    # Memory
    (one(i32_const(0) + b"\x28\x02\x00"),
     "function 0: i32.load needs a memory, and the module has none"),
    (module(MAIN, funcs(0), memory(1), code((0, i32_const(0) + b"\x28\x03\x00"))),
     "function 0: i32.load: the alignment is larger than natural"),
    (module(MAIN, funcs(0), memory(1), code((0, i32_const(0) + i32_const(0) + b"\x3a\x01\x00"
                                              + i32_const(0)))),
     "function 0: i32.store8: the alignment is larger than natural"),
    (module(MAIN, funcs(0), memory(1), code((0, b"\x3f\x01"))), "function 0: memory 1 does not exist"),
    (one(b"\x3f\x00"), "function 0: memory 0 does not exist"),
    (module(MAIN, funcs(0), memory(1), code((0, i64_const(0) + b"\x28\x02\x00"))),
     "function 0: i32.load expects i32, found i64"),
    (module(MAIN, funcs(0), memory(1), code((0, i32_const(0) + i32_const(0) + b"\x37\x03\x00"
                                              + i32_const(0)))),
     "function 0: i64.store expects i64, found i32"),
    (one(i32_const(0) * 3 + b"\xfc\x08\x00\x00"), "function 0: memory.init is not supported yet"),
    (one(i32_const(0) * 3 + b"\xfc\x0b\x00"), "function 0: memory 0 does not exist"),
    (module(MAIN, funcs(0), memory(1), code((0, i32_const(0) * 3 + b"\xfc\x0a\x00\x01"
                                              + i32_const(0)))),
     "function 0: memory 1 does not exist"),
    (module(MAIN, funcs(0), memory(1), code((0, i32_const(0) * 2 + i64_const(0)
                                              + b"\xfc\x0b\x00" + i32_const(0)))),
     "function 0: memory.fill expects i32, found i64"),
    (one(b"\xfc\x63"), "function 0: opcode 0xfc 99 is not supported yet"),
    (one(i64_const(1)), "function 0: end expects i32, found i64"),
    (one(i64_const(1) + b"\x0f"), "function 0: return expects i32, found i64"),
    (one(i32_const(1) + i64_const(2) + ADD), "function 0: i32.add expects i32, found i64"),
    (one(i64_const(1) + i32_const(2) + ADD64), "function 0: i64.add expects i64, found i32"),
    (one(i32_const(1) + i64_const(2) + b"\x74"), "function 0: i32.shl expects i32, found i64"),
    (one(i32_const(1) + i64_const(2) + b"\x6d"), "function 0: i32.div_s expects i32, found i64"),
    (one(i32_const(1) + b"\xc4" + b"\xa7"), "function 0: i64.extend32_s expects i64, found i32"),
    (one(i64_const(1) + i32_const(2) + b"\x86" + b"\xa7"),
     "function 0: i64.shl expects i64, found i32"),
    (one(i32_const(1) + i32_const(2)), "function 0: values left on the operand stack at the end"),
    (module(MAIN, funcs(0), section(6, vec([bytes([I32, 0]) + i32_const(0) + b"\x0b"])),
            code((0, i32_const(1) + global_set(0) + i32_const(0)))),
     "function 0: global 0 is immutable"),
    (module(MAIN, funcs(0), section(6, vec([bytes([I64, 1]) + i64_const(0) + b"\x0b"])),
            code((0, i32_const(1) + global_set(0) + i32_const(0)))),
     "function 0: global.set expects i64, found i32"),
    # An i32.add whose result would go straight to the local (README.md,
    # How functions are translated), when the local has another type or
    # does not exist.
    (module(MAIN, funcs(0), code(([I64], i32_const(1) + i32_const(2) + ADD + local_set(0)
                                  + i32_const(0)))),
     "function 0: local.set expects i64, found i32"),
    (module(MAIN, funcs(0), code(([I64], i32_const(1) + i32_const(2) + ADD + local_tee(5)))),
     "function 0: local 5 does not exist"),
    (module(types(([], [I32]), ([I64], [])), funcs(0, 1), code((0, i32_const(1) + call(1) + i32_const(0)), (0, b""))),
     "function 0: call expects i64, found i32"),
    (one(i32_const(0) + b"\x12\x00"), "function 0: return_call is not supported yet"),
    # call_indirect
    (one(i32_const(0) + b"\x11\x00\x00"), "function 0: table 0 does not exist"),
    (module(MAIN, funcs(0), table(1), code((0, i32_const(0) + b"\x11\x05\x00"))),
     "type index 5 is out of range"),
    (module(MAIN, funcs(0), table(1), code((0, i32_const(0) + b"\x11\x00\x01"))),
     "function 0: table 1 does not exist"),
    (module(MAIN, funcs(0), table(1), code((0, i64_const(0) + b"\x11\x00\x00"))),
     "function 0: call_indirect expects i32, found i64"),
    (module(types(([], [I32]), ([I32], [])), funcs(0), table(1),
            code((0, i64_const(0) + i32_const(0) + b"\x11\x01\x00" + i32_const(0)))),
     "function 0: call_indirect expects i32, found i64"),
    # Blocks and branches
    (one(block() + br(2) + END + i32_const(0)), "function 0: label 2 does not exist"),
    (one(block() + ELSE + END + i32_const(0)), "function 0: else without if"),
    (one(i32_const(1) + if_() + ELSE + ELSE + END + i32_const(0)), "function 0: else without if"),
    (one(i32_const(1) + if_(I32) + i32_const(2) + END),
     "function 0: an if without else must have the same parameters and results"),
    (one(i64_const(1) + if_() + END + i32_const(0)), "function 0: if expects i32, found i64"),
    (one(block(I32) + i64_const(1) + END), "function 0: end expects i32, found i64"),
    (one(i32_const(1) + if_(I32) + i64_const(1) + ELSE + i32_const(2) + END),
     "function 0: else expects i32, found i64"),
    (one(block() + i32_const(1) + END + i32_const(0)),
     "function 0: values left on the operand stack at the end"),
    (one(i32_const(1) + if_() + i32_const(1) + ELSE + END + i32_const(0)),
     "function 0: values left on the operand stack at the else"),
    # Only the block's own values can be popped inside it.
    (one(i32_const(1) + block() + DROP + END), "function 0: operand stack underflow"),
    (one(block(I32) + i64_const(1) + br(0) + END), "function 0: br expects i32, found i64"),
    (one(block(I32) + block() + i32_const(0) + br_table([0], 1) + END + i32_const(0) + END),
     "function 0: the labels of br_table take different values"),
    (one(b"\x02\x05" + END + i32_const(0)), "type index 5 is out of range"),
    (one(b"\x02\x7b" + END + i32_const(0)),
     "function 0: a block has type v128; only i32, i64, f32, and f64 are supported"),
    (one(i32_const(1) + i64_const(2) + i32_const(0) + SELECT),
     "function 0: select expects i64, found i32"),
    (one(i32_const(1) + i32_const(2) + i32_const(0) + b"\x1c\x02\x7f\x7f"),
     "function 0: select must name one type"),
    (one(b"\xfe"), "function 0: opcode 0xfe is not supported yet"),
    (one(ADD), "function 0: operand stack underflow"),
    (one(b""), "function 0: operand stack underflow"),
    (one(local_get(3), n_locals=2), "function 0: local 3 does not exist"),
    (one(call(5)), "function 0: function 5 does not exist"),
    (one(global_get(0)), "function 0: global 0 does not exist"),
    (one(i32_const(0) + b"\x0b\x01"), "function 0: code after the function's end"),
    (module(MAIN, imports(("env", "f", 0)), funcs(0), globals_(0), code((0, b""))),
     "function 1: operand stack underflow"),
]


LIB = ["--library", "lib"]

# Errors with options: (options, module, expected error message).
OPTION_CASES: List[Tuple[List[str], bytes, str]] = [
    (LIB, module(MAIN, funcs(0), start(0), code((0, i32_const(0)))),
     "a library module may not have a start function"),
    # Nothing would call it.
    (LIB, module(types(([], [])), funcs(0), exports(("__wasm_call_ctors", 0, 0)), code((0, b""))),
     "a library module may not export __wasm_call_ctors"),
    # Float arithmetic calls the float library, which must not call itself.
    (LIB, module(types(([], [F32])), funcs(0), code((0, b"\x43\0\0\0\0" * 2 + b"\x92"))),
     "function 0: a library module may not use f32.add"),
    (LIB, module(MAIN, funcs(0), code((0, b"\x43\0\0\0\0" + b"\xfc\x00"))),
     "function 0: a library module may not use i32.trunc_sat_f32_s"),
    (LIB, module(MAIN, funcs(0), code((0, b"\x43\0\0\0\0" * 2 + b"\x5b"))),
     "function 0: a library module may not use f32.eq"),
    (LIB, module(MAIN, funcs(0), code((0, b"\x43\0\0\0\0" + b"\xa8"))),
     "function 0: a library module may not use i32.trunc_f32_s"),
    (LIB, module(MAIN, funcs(0), memory(1), code((0, b"\x3f\x00"))),
     "function 0: a library module may not use memory.size"),
    (LIB, module(MAIN, funcs(0), memory(1), code((0, i32_const(0) + b"\x40\x00"))),
     "function 0: a library module may not use memory.grow"),
    (LIB + ["--library-memory", "70000"], module(memory(1)),
     "the library memory of 70000 bytes is larger than the module's memory of 65536"),
    (LIB + ["--library-memory", "16"], module(MAIN), "--library-memory: the module has no memory"),
    # Only the reserved part of the memory is there for data.
    (LIB + ["--library-memory", "8"],
     module(memory(1), section(11, vec([b"\0" + i32_const(8) + b"\x0b" + vec([b"x"])]))),
     "data segment 0 does not fit in the memory"),
]

# Errors with options: (options, module, expected error message).
OPTION_CASES += [
    (["--memory-pages", "0"], module(memory(1)), "--memory-pages: 0 is below the memory's initial size, 1"),
    (["--memory-pages", "3"], module(section(5, vec([b"\x01\x01\x02"]))),
     "--memory-pages: 3 is above the memory's maximum size, 2"),
    (["--memory-pages", "2"], module(MAIN), "--memory-pages: the module has no memory"),
    (["--memory-pages", "65536"], module(memory(1)), "--memory-pages: the memory must be below 65536 pages"),
]

# Errors in the command line: (options, expected message). The module is
# a valid one.
COMMAND_CASES: List[Tuple[List[str], str]] = [
    (["--library", "1x"], "--library: '1x' is not a C identifier"),
    (["--library-memory", "16"], "--library-memory: only a library module (--library) takes it"),
    (["--library", "lib", "--memory-pages", "2"],
     "--memory-pages: a library module (--library) cannot grow its memory"),
]


def check(tmp: str, index: int, options: List[str], wasm: bytes, expected: str) -> Optional[str]:
    """Translates one module that has an error, in a directory of its own
    under tmp, so that the cases can go in parallel. Returns the failure,
    or None."""
    work = os.path.join(tmp, str(index))
    os.mkdir(work)
    src = os.path.join(work, "t.wasm")
    out = os.path.join(work, "t.nasm")
    with open(src, "wb") as f:
        f.write(wasm)
    p = subprocess.run([sys.executable, NICEWASM, *options, "-o", out, src],
                       capture_output=True, text=True)
    got = p.stderr.strip()
    ok = (p.returncode == 1 and got.startswith(src)
          and got.endswith(f": error: {expected}") and not os.path.exists(out))
    return None if ok else f"FAIL: expected '{expected}'\n  got (exit {p.returncode}): {got}"


def main() -> None:
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "t.wasm")
        out = os.path.join(tmp, "t.nasm")
        cases: List[Tuple[List[str], bytes, str]] = [([], wasm, expected) for wasm, expected in CASES]
        cases += OPTION_CASES
        with concurrent.futures.ThreadPoolExecutor(os.cpu_count()) as pool:
            for problem in pool.map(lambda c: check(tmp, c[0], *c[1]), enumerate(cases)):
                if problem is not None:
                    failed += 1
                    print(problem)
        with open(src, "wb") as f:
            f.write(module(MAIN))
        for options, expected in COMMAND_CASES:
            p = subprocess.run([sys.executable, NICEWASM, *options, "-o", out, src],
                               capture_output=True, text=True)
            got = p.stderr.strip()
            if p.returncode != 1 or got != expected or os.path.exists(out):
                failed += 1
                print(f"FAIL: expected '{expected}'\n  got (exit {p.returncode}): {got}")
                if os.path.exists(out):
                    os.remove(out)
        # Without -o, the output of t.nasm would be t.nasm itself.
        with open(out, "wb") as f:
            f.write(module(MAIN))
        p =subprocess.run([sys.executable, NICEWASM, out], capture_output=True, text=True)
        expected = f"{out}: the output file would overwrite the input; use -o"
        with open(out, "rb") as f:
            unchanged = f.read() == module(MAIN)
        if p.returncode != 1 or p.stderr.strip() != expected or not unchanged:
            failed += 1
            print(f"FAIL: expected '{expected}'\n  got (exit {p.returncode}): {p.stderr.strip()}")
        # An input file that cannot be read.
        missing = os.path.join(tmp, "missing.wasm")
        p = subprocess.run([sys.executable, NICEWASM, "-o", out + "2", missing],
                           capture_output=True, text=True)
        expected = f"{missing}: No such file or directory"
        if p.returncode != 1 or p.stderr.strip() != expected or os.path.exists(out + "2"):
            failed += 1
            print(f"FAIL: expected '{expected}'\n  got (exit {p.returncode}): {p.stderr.strip()}")
    n = len(CASES) + len(OPTION_CASES) + len(COMMAND_CASES) + 2
    print(f"{'FAIL' if failed else 'PASS'} errors ({n} cases)")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
