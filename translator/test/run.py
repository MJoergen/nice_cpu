#!/usr/bin/env python3
"""Runs translated wasm modules in the emulator.

Each case is a module, either built here with wasm.py or compiled from a
test/X.c or test/X.zig source into test/X.wasm. It is translated and joined
with runtime/start_wasm.asm, any hand-written assembly the case needs, and
runtime/lib.asm, as ISA.md §9.3 describes. Then it is assembled and run.

The program must halt with HALT and main's result in R1. A case in TRAPS
must instead trap: halt at ___wasm_trap with the trap code in R1, and R2
pointing at the trap's MOVE R1 instruction. Its .bin file must
have fewer than 16384 words, so the memory, reserved with .RES, is not in it. R7-R12 must be 0
and SP must be 0xFFFFFF00 again, as the start-up code left them, because
every translated function must preserve them (ISA.md §9.3). The expected
results were worked out by hand from the sources."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from typing import Dict, List, Tuple, Union

from wasm import (ADD, ADD64, AND, AND64, DROP, EXTEND_S, EXTEND_U, I32, I64, MUL, NOP,
                  OR, OR64, RETURN, SUB, SUB64, UNREACHABLE, WRAP, XOR, XOR64, call,
                  code, exports, funcs, global_get, global_set, globals_, i32_const,
                  i64_const, imports, local_get, local_set, local_tee, memory, module,
                  names, start, typed_globals, types)

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.join(HERE, "..", "..")
NICEWASM = os.path.join(HERE, "..", "nicewasm.py")
NICEASM = os.path.join(TOP, "assembler", "niceasm.py")
NICEEMU = os.path.join(TOP, "emulator", "zig-out", "bin", "niceemu")
RUNTIME = os.path.join(TOP, "runtime")

MAIN_TYPE: Tuple[List[int], List[int]] = ([], [I32])  # () -> i32

# Hand-written env functions for the i64 cases. twice(x) = 2 * x for an i64
# in R1 and R2. high() reads the high word of the exported i64 global
# result, so it shows the order of the global's words.
I64_ASM = ("_twice ADD[M] R1, R1, R1\n ADD[C] R2, R2, R2\n MOVE R15, @R13++\n"
           "_high MOVE R1, @_result+1\n MOVE R15, @R13++\n")

# Cases that must trap rather than return.
TRAPS = {"unreachable"}

# Cases whose module is written to a file of another name. The newline
# must not end the comment that names the source.
FILE_NAMES = {"names": "names\n_main HALT.wasm"}

# (name, module bytes or the name of test/X.wasm, hand-written assembly, R1)
CASES: List[Tuple[str, Union[bytes, str], str, int]] = [
    # main returns 6 * 7, folded by zig. Zig's main(argc, argv) wrapper
    # calls the function.
    ("answer", "answer", "", 42),
    # get(i) returns i + 100, so sum5 is 101 + 102 - 103 + 104 * 105 =
    # 11020. The fifth argument goes on the stack, and * calls __mul.
    ("sum5", "sum5", "", 11020),
    # Declared locals start at 0. dirty sets its 3 locals to 0x55, and clean
    # gets the same frame words, so without zeroing it returns 0x55 * 3 + 7.
    ("locals", module(
        types(MAIN_TYPE),
        funcs(0, 0, 0),
        exports(("main", 0, 2)),
        code((3, i32_const(0x55) + local_set(0) + i32_const(0x55) + local_set(1)
              + i32_const(0x55) + local_set(2) + i32_const(0)),
             (3, local_get(0) + local_get(1) + ADD + local_get(2) + ADD + i32_const(7) + ADD),
             (0, call(0) + DROP + call(1)))), "", 7),
    # f(a, b, c, d, e, f) = a - b + c - d + e - f with e and f on the stack:
    # 1000 - 200 + 30 - 4 + 50000 - 600000 = -549174 = 0xFFF79ECA. Any two
    # arguments swapped give a different result.
    ("params", module(
        types(MAIN_TYPE, ([I32] * 6, [I32])),
        funcs(1, 0),
        exports(("main", 0, 1)),
        code((0, local_get(0) + local_get(1) + SUB + local_get(2) + ADD + local_get(3) + SUB
              + local_get(4) + ADD + local_get(5) + SUB),
             (0, i32_const(1000) + i32_const(200) + i32_const(30) + i32_const(4)
              + i32_const(50000) + i32_const(600000) + call(0)))), "", 0xFFF79ECA),
    # 5, tee keeps it on the stack: 5 + 5 = 10. set 3: 10 + 3 = 13. The
    # 99 is dropped, and nop does nothing.
    ("tee", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, i32_const(5) + local_tee(0) + local_get(0) + ADD + i32_const(3) + local_set(0)
              + local_get(0) + ADD + i32_const(99) + DROP + NOP))), "", 13),
    # return takes the top value, 4, and leaves the 9 under it. The code
    # after it is never run.
    ("return", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i32_const(9) + i32_const(4) + RETURN + i32_const(2) + DROP))), "", 4),
    # (0xF0F0 AND 0xFF00) = 0xF000, OR 0x000F = 0xF00F, XOR 0x0F0F = 0xFF00,
    # - 0x10000 = -0x100 = 0xFFFFFF00.
    ("logic", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i32_const(0xF0F0) + i32_const(0xFF00) + AND + i32_const(0xF) + OR
              + i32_const(0xF0F) + XOR + i32_const(0x10000) + SUB))), "", 0xFFFFFF00),
    # main passes f(a, b, c, d) = ((a + c) - b) XOR d, with b and d
    # extended, unsigned and signed, to i64. a is twice(result) =
    # twice(0x1_80000001) = 0x3_00000002, with a carry between the words.
    # a and b fill R1-R3, so c does not fit and goes on the stack, and d
    # follows it there although R4 is free. a + c = 0x3_00000002 +
    # 0x4_FFFFFFFF = 0x8_00000001, again with a carry. - 2 borrows:
    # 0x7_FFFFFFFF. XOR 0xFFFFFFFF_FFFFFFF0 = 0xFFFFFFF8_0000000F, which goes
    # in result. main returns its low word XOR high() = 0xF XOR 0xFFFFFFF8.
    ("i64", module(
        types(MAIN_TYPE, ([I64, I32, I64, I32], [I64]), ([I64], [I64])),
        imports(("env", "twice", 2), ("env", "high", 0)),
        funcs(1, 0),
        typed_globals((I64, True, 0x1_80000001)),
        exports(("main", 0, 3), ("result", 3, 0)),
        code(([I64], local_get(0) + local_get(2) + ADD64 + local_get(1) + EXTEND_U + SUB64
              + local_tee(4) + local_get(3) + EXTEND_S + XOR64),
             (0, global_get(0) + call(0) + i32_const(2) + i64_const(0x4_FFFFFFFF)
              + i32_const(-16) + call(2) + global_set(0) + global_get(0) + WRAP
              + call(1) + XOR))), I64_ASM, 0xFFFFFFF7),
    # result = NOT ((0x12345678_9ABCDEF0 AND 0x0F0F0F0F_F0F0F0F0) OR
    # 0x00000001_00000001), with NOT as XOR -1: NOT 0x02040609_90B0D0F1 =
    # 0xFDFBF9F6_6F4F2F0E. main returns low - high = 0x6F4F2F0E -
    # 0xFDFBF9F6 = 0x71533518.
    ("i64logic", module(
        types(MAIN_TYPE),
        imports(("env", "high", 0)),
        funcs(0),
        typed_globals((I64, True, 0)),
        exports(("main", 0, 1), ("result", 3, 0)),
        code((0, i64_const(0x123456789ABCDEF0) + i64_const(0x0F0F0F0FF0F0F0F0) + AND64
              + i64_const(0x100000001) + OR64 + i64_const(-1) + XOR64 + global_set(0)
              + global_get(0) + WRAP + call(0) + SUB))),
     I64_ASM, 0x71533518),
    # The most negative i64, MIN = 0x80000000_00000000, has only a 10-byte
    # encoding. It is the first constant and the global's initial value.
    # The other constants are padded to 10 bytes, which is valid too, as
    # LLVM's 5-byte i32 constants are. MIN + 3 = 0x80000000_00000003, XOR
    # -1 = 0x7FFFFFFF_FFFFFFFC, XOR MIN = 0xFFFFFFFF_FFFFFFFC, which goes in
    # result. main returns its low word - high() = 0xFFFFFFFC - 0xFFFFFFFF
    # = -3 = 0xFFFFFFFD.
    ("i64min", module(
        types(MAIN_TYPE),
        imports(("env", "high", 0)),
        funcs(0),
        typed_globals((I64, True, -2**63)),
        exports(("main", 0, 1), ("result", 3, 0)),
        code((0, i64_const(-2**63) + i64_const(3, 10) + ADD64 + i64_const(-1, 10) + XOR64
              + global_get(0) + XOR64 + global_set(0) + global_get(0) + WRAP + call(0)
              + SUB))),
     I64_ASM, 0xFFFFFFFD),
    # f traps with code 1. The code after unreachable is never translated.
    ("unreachable", module(
        types(MAIN_TYPE),
        funcs(0, 0),
        exports(("main", 0, 1)),
        code((0, i32_const(5) + UNREACHABLE + i64_const(1) + DROP),
             (0, call(0)))), "", 1),
    # The function's name and the file name contain a newline. If either
    # ended its comment, the rest would define _main a second time.
    ("names", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i32_const(3))),
        names({0: "f\n_main HALT"})), "", 3),
    # -2147483648 is 0x80000000, and XOR -1 inverts it to 0x7FFFFFFF.
    ("consts", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i32_const(-2147483648) + i32_const(-1) + XOR))), "", 0x7FFFFFFF),
    # Global 1 = global 0 - 3 = 4. It is exported as counter, so its label is
    # _counter, and the imported read_counter reads it from there. main is
    # also exported as _skip and a-b, which get no label: if _skip got one,
    # it would clash with the __skip defined here.
    ("globals", module(
        types(MAIN_TYPE),
        imports(("env", "read_counter", 0)),
        funcs(0),
        globals_(7, 0),
        exports(("main", 0, 1), ("_skip", 0, 1), ("a-b", 0, 1), ("counter", 3, 1)),
        code((0, global_get(0) + i32_const(3) + SUB + global_set(1) + call(0)))),
     "_read_counter MOVE R1, @_counter\n MOVE R15, @R13++\n__skip HALT\n", 4),
    # ___wasm_start sets the 16384 words of the memory to 0, and no other
    # word. main is hand-written: it sets the first and last words, calls
    # ___wasm_start again, and returns their sum + 6 * 7 = 42. __mul follows
    # the memory, so if the loop cleared one word too many, its first
    # instruction would be gone and 6 * 7 would not be 42.
    ("zero", module(types(MAIN_TYPE), memory(1)),
     "_main MOVE @___wasm_memory, 5\n"
     " MOVE @___wasm_memory+16383, 7\n"
     " ADD @--R13, 2, R15\n MOVE R15, ___wasm_start\n"
     " MOVE R1, 6\n MOVE R2, 7\n"
     " ADD @--R13, 2, R15\n MOVE R15, __mul\n"
     " ADD R1, R1, @___wasm_memory\n ADD R1, R1, @___wasm_memory+16383\n"
     " MOVE R15, @R13++\n", 42),
    # The start function sets g = g * 10 + 1, then __wasm_call_ctors sets
    # g = g * 10 + 2. In that order, g = 12.
    ("startup", module(
        types(MAIN_TYPE, ([], [])),
        funcs(1, 1, 0),
        globals_(0),
        exports(("__wasm_call_ctors", 0, 1), ("main", 0, 2)),
        start(0),
        code((0, global_get(0) + i32_const(10) + MUL + i32_const(1) + ADD + global_set(0)),
             (0, global_get(0) + i32_const(10) + MUL + i32_const(2) + ADD + global_set(0)),
             (0, global_get(0)))), "", 12),
]


def run(cmd: List[str]) -> str:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0 and not cmd[0].endswith("niceemu"):
        raise RuntimeError(f"{' '.join(cmd)} failed:\n{p.stderr}")
    return p.stdout + f"exit {p.returncode}\n"


def check(name: str, wasm_file: str, extra: str, expected: int, tmp: str) -> List[str]:
    trap = name in TRAPS
    asm = os.path.join(tmp, name + ".asm")
    run([sys.executable, NICEWASM, "-o", asm, wasm_file])
    hand = os.path.join(HERE, name + ".asm")
    if os.path.exists(hand):
        with open(hand) as f:
            extra += f.read()
    full = os.path.join(tmp, name + ".full.asm")
    with open(full, "w") as out:
        for part in [os.path.join(RUNTIME, "start_wasm.asm"), None, asm,
                     os.path.join(RUNTIME, "lib.asm")]:
            if part is None:
                out.write(extra)
            else:
                with open(part) as f:
                    out.write(f.read())
    binary = os.path.join(tmp, name + ".bin")
    run([sys.executable, NICEASM, "-o", binary, full])
    with open(binary) as f:
        image = {int(a, 16): int(w, 16) for a, w in (line.split() for line in f)}
    n_words = len(image)
    output = run([NICEEMU, binary])

    regs: Dict[str, int] = {}
    for line in output.splitlines()[1:5]:
        tok = line.split()
        for i in range(0, len(tok), 2):
            regs[tok[i]] = int(tok[i + 1], 16)
    wanted = {"R1": expected}
    wanted.update({f"R{i}": 0 for i in range(7, 12)})
    if not trap:
        # A trap leaves the frames as they were.
        wanted.update({"R12": 0, "R13": 0xFFFFFF00})
    problems = []
    if n_words >= 16384:
        problems.append(f"the .bin has {n_words} words, so it holds the memory")
    if trap:
        if (not output.startswith("Halted (reserved control instruction)")
                or not output.endswith("exit 2\n")):
            problems.append("did not halt at ___wasm_trap")
        # MOVE R1, code
        if image.get(regs.get("R2", 0)) != 0x5800 or image.get(regs.get("R2", 0) + 1) != expected:
            problems.append("R2 does not point at the trap's MOVE R1")
    elif not output.startswith("Halted (HALT)") or not output.endswith("exit 0\n"):
        problems.append("did not halt with HALT")
    for reg, value in wanted.items():
        if regs.get(reg) != value:
            problems.append(f"{reg} is {regs.get(reg, 0):08x}, expected {value:08x}")
    if problems:
        problems.append(output)
    return problems


def main() -> None:
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, wasm, extra, expected in CASES:
            if isinstance(wasm, bytes):
                wasm_file = os.path.join(tmp, FILE_NAMES.get(name, name + ".wasm"))
                with open(wasm_file, "wb") as f:
                    f.write(wasm)
            else:
                wasm_file = os.path.join(HERE, wasm + ".wasm")
            try:
                problems = check(name, wasm_file, extra, expected, tmp)
            except RuntimeError as e:
                problems = [str(e)]
            if problems:
                failed += 1
                print(f"FAIL {name}")
                for p in problems:
                    print("  " + p.rstrip().replace("\n", "\n  "))
            else:
                print(f"PASS {name}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
