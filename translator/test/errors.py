#!/usr/bin/env python3
"""Tests of nicewasm's errors. Each case is a module that must fail with exit
status 1, print the expected error, and write no output file."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from typing import List, Tuple

from wasm import (ADD, ADD64, DROP, ELSE, END, F32, I32, I64, SELECT, block, br,
                  br_table, call, code, exports, funcs, global_get, global_set, globals_,
                  i32_const, i64_const, if_, imports, local_get, memory, module, name,
                  section, start, types, u, vec)

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
    (module(MAIN, imports(("wasi", "fd_write", 0))),
     "import wasi.fd_write: functions may be imported only from 'env' and 'nice'"),
    (module(MAIN, imports(("nice", "peek", 0))), "import nice.peek is not supported yet"),
    (module(MAIN, imports(("nice", "load", 0))),
     "import nice.load: the module 'nice' has only peek and poke"),
    (module(MAIN, imports(("env", "a-b", 0))),
     "import env.a-b: the name is not a C identifier, so it has no label"),
    (module(types(([F32], [])), imports(("env", "f", 0))),
     "import env.f has type f32; only i32 and i64 are supported yet"),
    # Module contents
    (module(memory(1), memory(1)), "section 5 is out of order or repeated"),
    (module(section(5, vec([b"\0\1", b"\0\1"]))), "a module may have only one memory"),
    (module(section(5, vec([b"\x03\x01\x01"]))), "a shared or 64-bit memory is not supported"),
    (module(section(6, vec([bytes([F32, 1, 0x43, 0, 0, 0, 0, 0x0b])]))),
     "global 0 has type f32; only i32 and i64 are supported yet"),
    (module(section(6, vec([bytes([I32, 1, 0x23, 0, 0x0b])]))),
     "global 0: the initial value must be an i32.const"),
    (module(section(6, vec([bytes([I64, 1, 0x41, 0, 0x0b])]))),
     "global 0: the initial value must be an i64.const"),
    # extended-const: an expression is not supported.
    (module(section(6, vec([bytes([I32, 1]) + i32_const(1) + i32_const(2) + ADD + b"\x0b"]))),
     "global 0: the initial value must be an i32.const"),
    (module(section(9, vec([b"\0" + i32_const(0) + b"\x0b" + vec([u(0)])]))),
     "element segments are not supported yet"),
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
    (module(types(([F32], [])), funcs(0), code((0, b""))),
     "function 0 has type f32; only i32 and i64 are supported yet"),
    (module(MAIN, funcs(0), section(10, vec([u(6) + vec([u(1) + bytes([F32])]) + i32_const(0) + b"\x0b"]))),
     "function 0: a local has type f32; only i32 and i64 are supported yet"),
    (module(types(([], [I32, I32])), funcs(0), code((0, i32_const(1) + i32_const(2)))),
     "function 0: more than one result is not supported yet"),
    (one(i32_const(0) + b"\x2a\x02\x00"), "function 0: f32.load is not supported yet"),
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
    (one(i32_const(0) * 3 + b"\xfc\x0b\x00"), "function 0: memory.fill is not supported yet"),
    (one(b"\xfc\x63"), "function 0: opcode 0xfc 99 is not supported yet"),
    (one(i64_const(1)), "function 0: end expects i32, found i64"),
    (one(i64_const(1) + b"\x0f"), "function 0: return expects i32, found i64"),
    (one(i32_const(1) + i64_const(2) + ADD), "function 0: i32.add expects i32, found i64"),
    (one(i64_const(1) + i32_const(2) + ADD64), "function 0: i64.add expects i64, found i32"),
    (one(i32_const(1) + i32_const(2)), "function 0: values left on the operand stack at the end"),
    (module(MAIN, funcs(0), section(6, vec([bytes([I32, 0]) + i32_const(0) + b"\x0b"])),
            code((0, i32_const(1) + global_set(0) + i32_const(0)))),
     "function 0: global 0 is immutable"),
    (module(MAIN, funcs(0), section(6, vec([bytes([I64, 1]) + i64_const(0) + b"\x0b"])),
            code((0, i32_const(1) + global_set(0) + i32_const(0)))),
     "function 0: global.set expects i64, found i32"),
    (module(types(([], [I32]), ([I64], [])), funcs(0, 1), code((0, i32_const(1) + call(1) + i32_const(0)), (0, b""))),
     "function 0: call expects i64, found i32"),
    (one(i32_const(0) + b"\x11\x00\x00"), "function 0: call_indirect is not supported yet"),
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
    (one(b"\x02\x7d" + END + i32_const(0)),
     "function 0: a block has type f32; only i32 and i64 are supported yet"),
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


def main() -> None:
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "t.wasm")
        out = os.path.join(tmp, "t.asm")
        for wasm, expected in CASES:
            with open(src, "wb") as f:
                f.write(wasm)
            p = subprocess.run([sys.executable, NICEWASM, "-o", out, src],
                               capture_output=True, text=True)
            got = p.stderr.strip()
            ok = (p.returncode == 1 and got.startswith(src)
                  and got.endswith(f": error: {expected}") and not os.path.exists(out))
            if not ok:
                failed += 1
                print(f"FAIL: expected '{expected}'\n  got (exit {p.returncode}): {got}")
                if os.path.exists(out):
                    os.remove(out)
    print(f"{'FAIL' if failed else 'PASS'} errors ({len(CASES)} cases)")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
