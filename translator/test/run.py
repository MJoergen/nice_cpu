#!/usr/bin/env python3
"""Runs translated wasm modules in the emulator.

Each case is a module, either built here with wasm.py or compiled from a
test/X.c or test/X.zig source into test/X.wasm. It is translated and joined
with runtime/start_wasm.asm, any hand-written assembly the case needs, and
runtime/lib.asm, as ISA.md §9.3 describes. Then it is assembled and run.

The program must halt with HALT and main's result in R1. A case in TRAPS
must instead trap: halt at ___wasm_trap with the trap code in R1, and R2
pointing at the first instruction of the code for the wasm instruction
that trapped, which TRAPS gives. Its .bin file must
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

from wasm import (ADD, ADD64, AND, AND64, DROP, ELSE, END, EQ, EQ64, EQZ, EQZ64,
                  EXTEND_S, EXTEND_U, GE_S, GE_S64, GE_U, GE_U64, GT_S, GT_S64, GT_U,
                  GT_U64, I32, I64, LE_S, LE_S64, LE_U, LE_U64, LT_S, LT_S64, LT_U,
                  LT_U64, MUL, NE, NE64, NOP, OR, OR64, RETURN, SELECT, SUB, SUB64,
                  UNREACHABLE, WRAP, XOR, XOR64, block, br, br_if, br_table, call, code,
                  exports, funcs, global_get, global_set, globals_, i32_const, i64_const,
                  if_, imports, local_get, local_set, local_tee, loop, memory, module,
                  names, select_t, start, typed_globals, typeidx, types)
from wasm import (I32_LOAD, I32_LOAD8_S, I32_LOAD8_U, I32_LOAD16_S, I32_LOAD16_U, I32_STORE,
                  I32_STORE8, I32_STORE16, I64_LOAD, I64_LOAD8_S, I64_LOAD8_U, I64_LOAD16_S,
                  I64_LOAD32_S, I64_LOAD32_U, I64_STORE, I64_STORE8, I64_STORE16,
                  I64_STORE32, MEMORY_GROW, MEMORY_SIZE, data, mem)

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



def bits(r: int, *checks: bytes) -> bytes:
    """Code that leaves 2 * r + c on the stack for each check c in turn, an
    i32 that is 0 or 1, starting with r = 0. So the first check gives the
    highest bit. r is an i32 local that the code uses."""
    out = i32_const(0)
    for c in checks:
        out += local_tee(r) + local_get(r) + ADD + c + ADD
    return out


def cmp_all(t: int, pairs: List[Tuple[int, int]]) -> List[bytes]:
    """Each comparison from eq to ge_u on each pair, then eqz on 0 and on
    0x1_00000000 (an i32 sees only the low word of that, 0)."""
    const = i32_const if t == I32 else i64_const
    ops = ([EQ, NE, LT_S, LT_U, GT_S, GT_U, LE_S, LE_U, GE_S, GE_U] if t == I32 else
           [EQ64, NE64, LT_S64, LT_U64, GT_S64, GT_U64, LE_S64, LE_U64, GE_S64, GE_U64])
    out = [const(a) + const(b) + op for a, b in pairs for op in ops]
    eqz = EQZ if t == I32 else EQZ64
    return out + [const(0) + eqz, const(-0x80000000 if t == I32 else 0x1_00000000) + eqz]


def ld(op: int, addr: int, want: int, offset: int = 0) -> bytes:
    """A check that the load op at addr + offset gives want."""
    i64 = op in (I64_LOAD, I64_LOAD8_S, I64_LOAD8_U, I64_LOAD16_S, I64_LOAD32_S, I64_LOAD32_U)
    return (i32_const(addr) + mem(op, offset)
            + (i64_const(want) + EQ64 if i64 else i32_const(want) + EQ))


def st(op: int, addr: int, value: int) -> bytes:
    """Stores value at addr."""
    i64 = op in (I64_STORE, I64_STORE8, I64_STORE16, I64_STORE32)
    return i32_const(addr) + (i64_const(value) if i64 else i32_const(value)) + mem(op)


# Cases that must trap rather than return, and the first NICE instruction
# of the code for the wasm instruction that traps, which R2 points at.
# In main, an operand on the stack with nothing below it is at FP - 1.
TRAPS = {"unreachable": "MOVE R1, 1",
         "oob": "ADD[M] R1, @-1[R12], 1",
         "oobcarry": "ADD[M] R1, @-1[R12], 1",
         "nomemory": "MOVE R1, @-1[R12]"}

# Options for nicewasm.
OPTIONS = {"unchecked": ["--no-bounds-checks"]}

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
    # Loops, ifs, and a switch from clang, with get(i) = i + 100:
    # gcd(1071, 462) = 21, as 1071 = 2 * 462 + 147, 462 = 3 * 147 + 21, and
    # 147 = 7 * 21. The switch gives sw(0, 1) = get(1) = 101, sw(1, 20) =
    # 20 - get(3) = -83, sw(2, 0x0F) = 0x0F XOR 0x55 = 0x5A = 90, sw(4, 9)
    # = gcd(9, 6) = 3, and by default sw(-3, 30) = 30 - 3 = 27: 138 in all.
    # fib(60) = 1548008755920 = 0x168_6C8312D0 adds 1000. 21 + 138 + 1000
    # = 1159.
    ("control", "control", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 1159),
    # Byte, 16-bit, and unaligned 32-bit accesses from clang, with get(i) =
    # i + 100. fill sets buf[i] = 10 + i, so sum is 10 + ... + 49 = 59 * 20
    # = 1180 = 0x49C. word_at(buf + 5) reads the bytes 15, 16, 17, 18:
    # 0x1211100F, and XOR 0x49C gives 0x12111493. Each short is -200 - 100
    # = -300, and 8 of them sum to -2400 = -0x960. 0x12111493 - 0x960 =
    # 0x12110B33.
    ("memory_c", "memory", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 0x12110B33),
    # Initialized data from clang, with get(i) = i + 100. text is "Hello,
    # NICE!", so char_at(0) + char_at(7) = 'H' + 'N' = 72 + 78 = 150. table[2]
    # is 4, and bumping it by get(0) twice gives 104 + 204 = 308. counter is
    # 0, not in a data segment, and bumps to 100. 150 + 308 + 100 = 558.
    ("data_c", "data", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 558),
    # The same from Zig, which puts its stack first and the data after it,
    # so ___wasm_start clears the words below and above the data. primes[5]
    # = 13, and state = 0x12345678 + 100 = 0x123456DC. 13 + 0x56DC = 0x56E9.
    ("data_zig", "datazig", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 0x56E9),
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
    # Each comparison on three pairs, ten bits each, eq first:
    # MAX, MIN: 0101100110. MAX - MIN overflows to a negative number, so
    #           lt_s is N XOR V = 1 XOR 1 = 0.
    # MIN, 1:   0110011001. MIN - 1 overflows the other way: N = 0, V = 1.
    # 5, 5:     1000001111.
    # eqz 0 is 1, and eqz 0x80000000 is 0: 10.
    # 0101 1001 1001 1001 1001 1000 0011 1110 = 0x5999983E.
    ("cmp", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0, *cmp_all(I32, [(0x7FFFFFFF, -0x80000000), (-0x80000000, 1),
                                        (5, 5)]))))), "", 0x5999983E),
    # The same for i64:
    # MAX, MIN: 0101100110 again.
    # 0x1_00000000, 0x0_FFFFFFFF: a > b both ways, though the low words
    # compare the other way, so the borrow must reach the high words:
    # 0100110011.
    # 0x5_00000007, 0x5_00000007: 1000001111.
    # eqz 0 is 1, and eqz 0x1_00000000 is 0, so eqz sees the high word: 10.
    # 0101 1001 1001 0011 0011 1000 0011 1110 = 0x5993383E.
    ("cmp64", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0, *cmp_all(I64, [(2**63 - 1, -2**63), (0x1_00000000, 0xFFFFFFFF),
                                        (0x5_00000007, 0x5_00000007)]))))), "", 0x5993383E),
    # Sum 1 to 10 = 55: a loop inside a block. br_if 1 leaves the block
    # when i > 10, and br 0 goes back to the start of the loop.
    ("loop", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((2, i32_const(1) + local_set(0)
              + block() + loop()
              + local_get(0) + i32_const(10) + GT_S + br_if(1)
              + local_get(1) + local_get(0) + ADD + local_set(1)
              + local_get(0) + i32_const(1) + ADD + local_set(0)
              + br(0) + END + END
              + local_get(1)))), "", 55),
    # abs(x) is an if with an else and a result: abs(-7) + abs(5) = 12.
    # Then two ifs without else, of type (i32) -> (i32), on 30: the first
    # adds 2, the second is not taken. 12 + 32 + 30 = 74.
    ("if", module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(1, 0),
        exports(("main", 0, 1)),
        code((0, local_get(0) + i32_const(0) + LT_S
              + if_(I32) + i32_const(0) + local_get(0) + SUB + ELSE + local_get(0) + END),
             (0, i32_const(-7) + call(0) + i32_const(5) + call(0) + ADD
              + i32_const(30) + i32_const(1) + if_(typeidx(1)) + i32_const(2) + ADD + END + ADD
              + i32_const(30) + i32_const(0) + if_(typeidx(1)) + i32_const(2) + ADD + END
              + ADD))), "", 74),
    # Branches that carry values, from above the slots that they go to.
    # Each line of main is one check, in bits():
    # 1: br 0 carries the 3 of 1, 2, 3 out of the block.
    # 1: br 0 carries an i64 one word down, over an i32. Moving its low
    #    word first would overwrite its high word.
    # 1: a taken br_if carries 60 of 50, 60 out; the code after it is not
    #    run.
    # 1: a br_if that is not taken leaves 70, 80; drop leaves 70.
    # 1: br 1 carries 11 of 4, 11 out of two blocks. The 99 is not run.
    # 1: br 1 in f is a return from inside a block: f returns 42.
    # 1: a loop of type (i32) -> (i32) counts from 0 to 10. Each br_if 0
    #    carries the count from above 99 and a copy of itself back to the
    #    loop's slot.
    # 0: the same loop, but from 3 to 10, does not give 11.
    ("brvalues", module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(0, 0),
        exports(("main", 0, 1)),
        code((0, block() + i32_const(5) + i32_const(42) + br(1) + END + i32_const(0)),
             ([I32, I32], bits(0,
                block(I32) + i32_const(1) + i32_const(2) + i32_const(3) + br(0) + END
                + i32_const(3) + EQ,
                block(I64) + i32_const(9) + i64_const(0x7_00000005) + br(0) + END
                + i64_const(0x7_00000005) + EQ64,
                block(I32) + i32_const(50) + i32_const(60) + i32_const(1) + br_if(0)
                + DROP + DROP + i32_const(0) + END + i32_const(60) + EQ,
                block(I32) + i32_const(70) + i32_const(80) + i32_const(0) + br_if(0) + DROP + END
                + i32_const(70) + EQ,
                block(I32) + block() + i32_const(4) + i32_const(11) + br(1) + END
                + i32_const(99) + END + i32_const(11) + EQ,
                call(0) + i32_const(42) + EQ,
                i32_const(0) + loop(typeidx(1)) + i32_const(1) + ADD + local_tee(1)
                + i32_const(99) + local_get(1) + local_get(1) + i32_const(10) + LT_U + br_if(0)
                + DROP + DROP + END + i32_const(10) + EQ,
                i32_const(3) + loop(typeidx(1)) + i32_const(1) + ADD + local_tee(1)
                + i32_const(99) + local_get(1) + local_get(1) + i32_const(10) + LT_U + br_if(0)
                + DROP + DROP + END + i32_const(11) + EQ)))), "", 0xFE),
    # f(i) is a switch: br_table 0 1 2 3 on i in four blocks returns 100 +
    # the depth it leaves by. g(i) is br_table 0 1 1 in two blocks of
    # result i32, from above a 1, so each target needs a move: g(0) is
    # 7 + 20 from the inner block, and g(i) for i >= 1 is 7 from the outer
    # one. h() has a br_table with only a default, and returns 55.
    # Checks: f(0) to f(3) are 100 to 103, f(-1) is 103, as -1 is unsigned
    # 0xFFFFFFFF, f(2) is not 101, g(0) = 27, g(1) = 7, g(5) = 7, h() = 55:
    # 1 1111 0111 1 = 0x3EF.
    ("brtable", module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(1, 1, 0, 0),
        exports(("main", 0, 3)),
        code((0, block() + block() + block() + block()
              + local_get(0) + br_table([0, 1, 2], 3)
              + END + i32_const(100) + RETURN
              + END + i32_const(101) + RETURN
              + END + i32_const(102) + RETURN
              + END + i32_const(103)),
             (0, block(I32) + block(I32) + i32_const(1) + i32_const(7) + local_get(0)
              + br_table([0], 1) + END + i32_const(20) + ADD + END),
             (0, block() + i32_const(3) + br_table([], 0) + END + i32_const(55)),
             (1, bits(0, *[i32_const(i) + call(0) + i32_const(v) + EQ for i, v in
                           [(0, 100), (1, 101), (2, 102), (3, 103), (-1, 103), (2, 101)]],
                      *[i32_const(i) + call(1) + i32_const(v) + EQ for i, v in
                        [(0, 27), (1, 7), (5, 7)]],
                      call(2) + i32_const(55) + EQ)))), "", 0x3EF),
    # select picks the first value if the condition is not 0:
    # 1: select(10, 20, 1) = 10.
    # 1: select(10, 20, 0) = 20.
    # 1: typed select on i64: select(0x1_00000002, 0x3_00000004, 0) is the second.
    # 1: select(0x1_00000002, 0x3_00000004, 7) is the first.
    # 0: i64.eq 0x1_00000007, 0x2_00000007 is 0, though the low words are equal.
    # 11110 = 0x1E.
    ("select", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0,
                      i32_const(10) + i32_const(20) + i32_const(1) + SELECT + i32_const(10) + EQ,
                      i32_const(10) + i32_const(20) + i32_const(0) + SELECT + i32_const(20) + EQ,
                      i64_const(0x1_00000002) + i64_const(0x3_00000004) + i32_const(0)
                      + select_t(I64) + i64_const(0x3_00000004) + EQ64,
                      i64_const(0x1_00000002) + i64_const(0x3_00000004) + i32_const(7)
                      + select_t(I64) + i64_const(0x1_00000002) + EQ64,
                      i64_const(0x1_00000007) + i64_const(0x2_00000007) + EQ64)))), "", 0x1E),
    # Code that cannot be reached is skipped up to its block's end or
    # else, including nested blocks in it, which are not even valid: the
    # if has no condition, and the add no operands. 8 + 9 = 17.
    ("dead", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, block(I32) + i32_const(8) + br(0)
              + block() + loop(I64) + if_() + ELSE + END + END + END + ADD + END
              + i32_const(0) + if_(I32) + UNREACHABLE + ADD + ELSE + i32_const(9) + END
              + ADD))), "", 17),
    # Loads, on the bytes 81 82 83 84 | 85 86 87 88 | 09 0A 0B 0C at 0 to
    # 11, put there by aligned i32 stores. The words are little-endian, so
    # the word at 0 is 0x84838281. Each line is one bit:
    ("memory", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, bits(0,
            st(I32_STORE, 0, 0x84838281 - 2**32) + st(I32_STORE, 4, 0x88878685 - 2**32)
            + st(I32_STORE, 8, 0x0C0B0A09)
            + ld(I32_LOAD8_U, 1, 0x82),
            ld(I32_LOAD8_S, 2, 0x83 - 0x100),                   # -125
            ld(I32_LOAD16_U, 3, 0x8584),                        # bytes 3 and 4: two words
            ld(I32_LOAD16_U, 7, 0x0988),
            ld(I32_LOAD16_S, 1, 0x8382 - 0x10000),
            ld(I32_LOAD, 2, 0x86858483 - 2**32),
            ld(I32_LOAD, 4, 0x88878685 - 2**32),
            ld(I32_LOAD, 1, 0x09888786, offset=4),              # byte 5
            ld(I64_LOAD, 3, 0x0B0A0988_87868584),              # three words
            ld(I64_LOAD, 0, 0x88878685_84838281 - 2**64),
            ld(I64_LOAD32_S, 1, 0x85848382 - 2**32),
            ld(I64_LOAD32_U, 1, 0x85848382),
            ld(I64_LOAD8_S, 8, 9),
            ld(I64_LOAD16_S, 6, 0x8887 - 0x10000),
            ld(I64_LOAD8_U, 7, 0x88),
            # Stores, from 16 on, which is 0. Bytes 16 to 23 are 00 11 22 33
            # 44 55 66 77 after an aligned i64 store.
            st(I64_STORE, 16, 0x77665544_33221100) + ld(I64_LOAD, 16, 0x77665544_33221100),
            # Only the low 16 bits are stored, CD AB in bytes 19 and 20.
            st(I32_STORE16, 19, 0x5ABCD) + ld(I64_LOAD, 16, 0x776655AB_CD221100),
            # EF BE AD DE in bytes 21 to 24.
            st(I32_STORE, 21, 0xDEADBEEF - 2**32) + ld(I64_LOAD, 16, 0xADBEEFAB_CD221100 - 2**64),
            ld(I32_LOAD, 24, 0xDE),
            # 08 07 06 05 04 03 02 01 in bytes 26 to 33.
            st(I64_STORE, 26, 0x01020304_05060708) + ld(I32_LOAD, 24, 0x070800DE),
            ld(I32_LOAD, 28, 0x03040506),
            ld(I32_LOAD, 32, 0x0102),
            # AA in byte 25.
            st(I64_STORE8, 25, 0x1_000000AA) + ld(I32_LOAD, 24, 0x0708AADE),
            # CC BB in bytes 31 and 32.
            st(I64_STORE16, 31, 0x12345678_9ABCBBCC) + ld(I32_LOAD, 28, 0xCC040506 - 2**32),
            ld(I32_LOAD, 32, 0x01BB),
            # 44 33 22 11 in bytes 29 to 32.
            st(I64_STORE32, 29, 0x99_11223344) + ld(I32_LOAD, 28, 0x22334406),
            ld(I32_LOAD, 32, 0x0111),
            # FF in byte 35, and byte 36 is untouched.
            st(I32_STORE8, 35, 0x1FF) + ld(I32_LOAD, 32, 0xFF000111 - 2**32),
            ld(I32_LOAD, 36, 0),
            # A check that fails: byte 0 is 0x81.
            ld(I32_LOAD8_U, 0, 0x82))))), "", 0x3FFFFFFE),
    # Two pages: memory.size is 2, memory.grow 0 returns 2, and the memory
    # cannot grow, so memory.grow 1 returns -1. The last word and the last
    # 8 bytes are in bounds. 11111 = 0x1F.
    ("memsize", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(2),
        exports(("main", 0, 0)),
        code((1, bits(0,
            MEMORY_SIZE + i32_const(2) + EQ,
            i32_const(0) + MEMORY_GROW + i32_const(2) + EQ,
            i32_const(1) + MEMORY_GROW + i32_const(-1) + EQ,
            st(I32_STORE, 131068, 77) + ld(I32_LOAD, 131068, 77),
            st(I64_STORE, 131064, 0x5_00000006) + ld(I64_LOAD, 131064, 0x5_00000006))))),
     "", 0x1F),
    # The last 4 bytes of one page are at 65532, so a load there works, but
    # one at 65532 + 1 traps with code 2.
    ("oob", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((0, i32_const(65532) + mem(I32_LOAD) + DROP
              + i32_const(65532) + mem(I32_LOAD, offset=1)))), "", 2),
    # -1 + 1 passes 2^32, so the store traps, though the address wraps to
    # 0, which is in bounds.
    ("oobcarry", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((0, i32_const(-1) + i32_const(5) + mem(I32_STORE, offset=1) + i32_const(0)))),
     "", 2),
    # A memory of 0 pages: every access traps.
    ("nomemory", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(0),
        exports(("main", 0, 0)),
        code((0, i32_const(0) + mem(I32_LOAD8_U)))), "", 2),
    # Without bounds checks, the address -4 + 8 wraps to 4, so the load
    # finds the 1234 stored there. With them, it would trap.
    ("unchecked", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((0, st(I32_STORE, 4, 1234) + i32_const(-4) + mem(I32_LOAD, offset=8)))), "", 1234),
    # Data segments: 11 22 33 at byte 5, "ABCDEFGHI" at 8, EE at 9 over the
    # B, 77 88 at 65534, the last two bytes, and nothing at 65536. Bytes
    # that no segment sets are 0, so the words are:
    #   word 1 (bytes 4-7):  00 11 22 33 = 0x33221100
    #   word 2 (8-11):       41 EE 43 44 = 0x4443EE41
    #   word 3 (12-15):      45 46 47 48 = 0x48474645
    #   word 4 (16-19):      49 00 00 00 = 0x00000049
    #   word 16383:          00 00 77 88 = 0x88770000
    # main writes -1 to word 0, word 5, and word 16382, next to the data,
    # then calls restart, which runs ___wasm_start again. It must set them
    # to 0 and leave the data alone. The words above are each one bit,
    # 0 for words 0, 5, and 16382, then a check that fails: 111111110 = 0x1FE.
    ("data", module(
        types(MAIN_TYPE, ([], [])),
        imports(("env", "restart", 1)),
        funcs(0),
        memory(1),
        exports(("main", 0, 1)),
        code((1, st(I32_STORE, 0, -1) + st(I32_STORE, 20, -1) + st(I32_STORE, 65528, -1)
              + call(0)
              + bits(0, ld(I32_LOAD, 0, 0), ld(I32_LOAD, 4, 0x33221100),
                     ld(I32_LOAD, 8, 0x4443EE41), ld(I32_LOAD, 12, 0x48474645),
                     ld(I32_LOAD, 16, 0x49), ld(I32_LOAD, 20, 0), ld(I32_LOAD, 65528, 0),
                     ld(I32_LOAD, 65532, 0x88770000 - 2**32), ld(I32_LOAD, 4, 0)))),
        data((5, b"\x11\x22\x33"), (8, b"ABCDEFGHI"), (9, b"\xEE"), (65534, b"\x77\x88"),
             (65536, b""))),
     "_restart ADD @--R13, 2, R15\n MOVE R15, ___wasm_start\n MOVE R15, @R13++\n", 0x1FE),
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


def assemble(line: str, tmp: str) -> List[int]:
    """The words of one instruction."""
    src = os.path.join(tmp, "line.asm")
    with open(src, "w") as f:
        f.write(f" {line}\n")
    run([sys.executable, NICEASM, "-o", src + ".bin", src])
    with open(src + ".bin") as f:
        return [int(line.split()[1], 16) for line in f]


def check(name: str, wasm_file: str, extra: str, expected: int, tmp: str) -> List[str]:
    trap = name in TRAPS
    asm = os.path.join(tmp, name + ".asm")
    run([sys.executable, NICEWASM, *OPTIONS.get(name, []), "-o", asm, wasm_file])
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
        first = assemble(TRAPS[name], tmp)
        r2 = regs.get("R2", 0)
        if [image.get(r2 + i) for i in range(len(first))] != first:
            problems.append(f"R2 does not point at {TRAPS[name]}")
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
