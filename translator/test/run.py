#!/usr/bin/env python3
"""Runs translated wasm modules in the emulator.

Each case is a module, either built here with wasm.py or compiled from a
test/X.c, test/X.zig, or test/X.rs source into test/X.wasm. It is translated and joined
with runtime/start_wasm.asm, any hand-written assembly the case needs, and
runtime/lib.asm, as ISA.md §9.3 describes. If it calls the float library,
runtime/float.wasm translated as the library module float follows. Then it
is assembled and run.

The program must halt with HALT and main's result in R1, and print what
CONSOLE gives on the console, or nothing. A case in TRAPS
must instead trap: halt at ___wasm_trap with the trap code in R1, and R2
pointing at the first instruction of the code for the wasm instruction
that trapped, which TRAPS gives. The first page of its memory, reserved
with .RES, must not be in the program image. R7-R12 must be 0
and SP must be 0xFFFFFF00 again, as the start-up code left them, because
every translated function must preserve them (ISA.md §9.3). The expected
results were worked out by hand from the sources."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from typing import Dict, List, Set, Tuple, Union

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
from wasm import MEMORY_COPY, MEMORY_FILL, call_indirect, elems, table
from wasm import (F32, F32_ABS, F32_COPYSIGN, F32_LOAD, F32_NEG, F32_REINTERPRET_I32, F32_STORE,
                  F64, F64_ABS, F64_COPYSIGN, F64_LOAD, F64_NEG, F64_REINTERPRET_I64, F64_STORE,
                  I32_REINTERPRET_F32, I64_REINTERPRET_F64, const)
from wasm import ROTL, ROTL64, ROTR, ROTR64, SHL, SHL64, SHR_S, SHR_S64, SHR_U, SHR_U64

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.join(HERE, "..", "..")
NICEWASM = os.path.join(HERE, "..", "nicewasm.py")
NICEASM = os.path.join(TOP, "assembler", "niceasm.py")
sys.path.insert(0, os.path.join(TOP, "assembler"))
import niceasm  # noqa: E402
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


def ld_dyn(op: int, addr: int, want: int, offset: int = 0) -> bytes:
    """ld, with the address in local 1, so that it is not a constant."""
    return i32_const(addr) + local_tee(1) + ld(op, addr, want, offset)[len(i32_const(addr)):]


def st_dyn(op: int, addr: int, value: int) -> bytes:
    """st, with the address in local 1."""
    return i32_const(addr) + local_tee(1) + st(op, addr, value)[len(i32_const(addr)):]


def fill(addr: int, value: int, n: int) -> bytes:
    return i32_const(addr) + i32_const(value) + i32_const(n) + MEMORY_FILL


def copy(dest: int, src: int, n: int) -> bytes:
    return i32_const(dest) + i32_const(src) + i32_const(n) + MEMORY_COPY


def st(op: int, addr: int, value: int) -> bytes:
    """Stores value at addr."""
    i64 = op in (I64_STORE, I64_STORE8, I64_STORE16, I64_STORE32)
    return i32_const(addr) + (i64_const(value) if i64 else i32_const(value)) + mem(op)


def op32(a: int, op: bytes, b: int, want: int) -> bytes:
    """A check that a op b gives want, all as unsigned i32 numbers."""
    def c(x: int) -> bytes:
        return i32_const(x - 2**32 if x >= 2**31 else x)
    return c(a) + c(b) + op + c(want) + EQ


def op64(a: int, op: bytes, b: int, want: int) -> bytes:
    """The same for i64."""
    def c(x: int) -> bytes:
        return i64_const(x - 2**64 if x >= 2**63 else x)
    return c(a) + c(b) + op + c(want) + EQ64


def un32(op: int, a: int, want: int) -> bytes:
    """A check that the i32 operation op on a gives want."""
    def c(x: int) -> bytes:
        return i32_const(x - 2**32 if x >= 2**31 else x)
    return c(a) + bytes([op]) + c(want) + EQ


def un64(op: int, a: int, want: int) -> bytes:
    """The same for i64."""
    def c(x: int) -> bytes:
        return i64_const(x - 2**64 if x >= 2**63 else x)
    return c(a) + bytes([op]) + c(want) + EQ64


def i64_un(op: int, a: int, want: int) -> bytes:
    """A check that op on the i64 a gives the i32 want."""
    return i64_const(a - 2**64 if a >= 2**63 else a) + bytes([op]) + i32_const(want) + EQ


def bits32(code: bytes, want: int) -> bytes:
    """A check that code leaves an f32 whose bits are want."""
    return code + I32_REINTERPRET_F32 + const(I32, want - 2**32 if want >= 2**31 else want) + EQ


def bits64(code: bytes, want: int) -> bytes:
    """The same for an f64."""
    return code + I64_REINTERPRET_F64 + const(I64, want - 2**64 if want >= 2**63 else want) + EQ64


def f32(x: int) -> bytes:
    return const(F32, x)


def fop(op: int) -> bytes:
    """A float instruction by its opcode, or by 0x100 + n for 0xFC n."""
    return bytes([op]) if op < 0x100 else b"\xfc" + bytes([op - 0x100])


def is_nan32(code: bytes) -> bytes:
    """A check that code leaves an f32 NaN: its magnitude is above that of
    infinity, 0x7F800000."""
    return code + I32_REINTERPRET_F32 + i32_const(0x7FFFFFFF) + AND + i32_const(0x7F800000) + GT_U


def f64(x: int) -> bytes:
    return const(F64, x)


# A library module, lib, for the library cases. Global 0 is its stack
# pointer, 64, so nicewasm reserves 64 bytes of its memory. __twice(x)
# stores x on its stack and returns the sum of two loads of it.
# peek100() loads byte address 100, past the reserved part.
LIB_MODULE = module(
    types(([I32], [I32]), ([], [I32])),
    funcs(0, 1),
    memory(1),
    globals_(64),
    exports(("__twice", 0, 0), ("peek100", 0, 1)),
    code(([I32, I32], global_get(0) + i32_const(16) + SUB + local_tee(1) + global_set(0)
          + local_get(1) + local_get(0) + mem(I32_STORE)
          + local_get(1) + mem(I32_LOAD) + local_get(1) + mem(I32_LOAD) + ADD + local_set(2)
          + local_get(1) + i32_const(16) + ADD + global_set(0) + local_get(2)),
         (0, i32_const(100) + mem(I32_LOAD))))

# Hand-written assembly for the library cases: the program's ___wasm_start,
# which does nothing, and its main, which runs an instruction, calls a
# routine, and runs another instruction.
LIB_ASM = "___wasm_start MOVE R15, @R13++\n_main {}\n ADD @--R13, 2, R15\n MOVE R15, {}\n {}\n" \
          " MOVE R15, @R13++\n"


# Cases that must trap rather than return, and the first NICE instruction
# of the code for the wasm instruction that traps, which R2 points at.
# The operands of these instructions are constants, which take no frame
# words until they must (README.md).
TRAPS = {"growtrap": "MOVE R1, 65536",
         "trunc_big": "MOVE R2, 0x4F000000",
         "trunc_small": "MOVE R2, 0x41E00000",
         "trunc_neg": "MOVE R2, 0x41F00000",
         "trunc_nan": "MOVE R2, 0x5F000000",
         "libtrap": "MOVE R1, 100",
         "safetrap": "MOVE R1, 1",
         "rusttrap": "MOVE R1, 1",
         "indirectoob": "MOVE R5, 4",
         "indirectnull": "MOVE R5, 0",
         "indirecttype": "MOVE R5, 1",
         "filloob": "ADD[M] R1, 65533, 4",
         "copyoob": "ADD[M] R1, 0, 2",
         "divzero": "MOVE[M] R0, 0",
         "divzero64": "OR[M] R0, 0, 0",
         "overflow": "MOVE[M] R0, -1",
         "overflow64": "OR[M] R0, -1, -1",
         "unreachable": "MOVE R1, 1",
         "oob": "ADD[M] R1, 65532, 1",
         "oobcarry": "ADD[M] R1, -1, 1",
         "nomemory": "MOVE R1, 0"}

# Options for nicewasm.
OPTIONS = {"unchecked": ["--no-bounds-checks"],
           "grow": ["--memory-pages", "3"],
           "growtrap": ["--memory-pages", "2"],
           "library": ["--library", "lib"],
           "libtrap": ["--library", "lib"],
           "libmem": ["--library", "lib", "--library-memory", "128"]}

# What a case must print on the console (ISA.md §8.3). Every other case
# must print nothing.
CONSOLE = {"peekpoke": "Hi\n", "hello": "Hello, NICE!\n", "hello_rs": "Hello, Rust!\n"}

# Cases whose module is written to a file of another name. The newline
# must not end the comment that names the source.
FILE_NAMES = {"names": "names\n_main HALT.wasm"}

def memory_checks(dyn: bool) -> List[bytes]:
    """The checks of the memory cases. With dyn, each address is the value of
    the local 1, not a constant, so it is known only when the code runs."""
    ld_, st_ = (ld_dyn, st_dyn) if dyn else (ld, st)
    return [
        st_(I32_STORE, 0, 0x84838281 - 2**32) + st_(I32_STORE, 4, 0x88878685 - 2**32)
        + st_(I32_STORE, 8, 0x0C0B0A09)
        + ld_(I32_LOAD8_U, 1, 0x82),
        ld_(I32_LOAD8_S, 2, 0x83 - 0x100),                   # -125
        ld_(I32_LOAD16_U, 3, 0x8584),                        # bytes 3 and 4: two words
        ld_(I32_LOAD16_U, 7, 0x0988),
        ld_(I32_LOAD16_S, 1, 0x8382 - 0x10000),
        ld_(I32_LOAD, 2, 0x86858483 - 2**32),
        ld_(I32_LOAD, 4, 0x88878685 - 2**32),
        ld_(I32_LOAD, 1, 0x09888786, offset=4),              # byte 5
        ld_(I64_LOAD, 3, 0x0B0A0988_87868584),              # three words
        ld_(I64_LOAD, 0, 0x88878685_84838281 - 2**64),
        ld_(I64_LOAD32_S, 1, 0x85848382 - 2**32),
        ld_(I64_LOAD32_U, 1, 0x85848382),
        ld_(I64_LOAD8_S, 8, 9),
        ld_(I64_LOAD16_S, 6, 0x8887 - 0x10000),
        ld_(I64_LOAD8_U, 7, 0x88),
        # Stores, from 16 on, which is 0. Bytes 16 to 23 are 00 11 22 33
        # 44 55 66 77 after an aligned i64 store.
        st_(I64_STORE, 16, 0x77665544_33221100) + ld_(I64_LOAD, 16, 0x77665544_33221100),
        # Only the low 16 bits are stored, CD AB in bytes 19 and 20.
        st_(I32_STORE16, 19, 0x5ABCD) + ld_(I64_LOAD, 16, 0x776655AB_CD221100),
        # EF BE AD DE in bytes 21 to 24.
        st_(I32_STORE, 21, 0xDEADBEEF - 2**32) + ld_(I64_LOAD, 16, 0xADBEEFAB_CD221100 - 2**64),
        ld_(I32_LOAD, 24, 0xDE),
        # 08 07 06 05 04 03 02 01 in bytes 26 to 33.
        st_(I64_STORE, 26, 0x01020304_05060708) + ld_(I32_LOAD, 24, 0x070800DE),
        ld_(I32_LOAD, 28, 0x03040506),
        ld_(I32_LOAD, 32, 0x0102),
        # AA in byte 25.
        st_(I64_STORE8, 25, 0x1_000000AA) + ld_(I32_LOAD, 24, 0x0708AADE),
        # CC BB in bytes 31 and 32.
        st_(I64_STORE16, 31, 0x12345678_9ABCBBCC) + ld_(I32_LOAD, 28, 0xCC040506 - 2**32),
        ld_(I32_LOAD, 32, 0x01BB),
        # 44 33 22 11 in bytes 29 to 32.
        st_(I64_STORE32, 29, 0x99_11223344) + ld_(I32_LOAD, 28, 0x22334406),
        ld_(I32_LOAD, 32, 0x0111),
        # FF in byte 35, and byte 36 is untouched.
        st_(I32_STORE8, 35, 0x1FF) + ld_(I32_LOAD, 32, 0xFF000111 - 2**32),
        ld_(I32_LOAD, 36, 0),
        # A check that fails: byte 0 is 0x81.
        ld_(I32_LOAD8_U, 0, 0x82)]


# i64 shifts and rotates: (a, operation, count, result). V is
# 0x80000001_00000003.
SHIFT64_ROWS: List[Tuple[int, bytes, int, int]] = [
    # V << 4: hi = 0x80000001 << 4, nothing comes up from lo.
    (0x80000001_00000003, SHL64, 4, 0x00000010_00000030),
    # V << 31: bit 1 of lo goes to bit 0 of hi.
    (0x80000001_00000003, SHL64, 31, 0x80000001_80000000),
    (0x80000001_00000003, SHL64, 32, 0x00000003_00000000),
    (0x80000001_00000003, SHL64, 36, 0x00000030_00000000),
    (0x80000001_00000003, SHL64, 64, 0x80000001_00000003),
    (0x80000001_00000003, SHL64, 0, 0x80000001_00000003),
    # Only the low word of the count matters: 4.
    (0x80000001_00000003, SHL64, 0xFFFFFFFF_00000004, 0x00000010_00000030),
    # V >> 4: the low 4 bits of hi, 0001, go to the top of lo.
    (0x80000001_00000003, SHR_U64, 4, 0x08000000_10000000),
    (0x80000001_00000003, SHR_U64, 32, 0x00000000_80000001),
    (0x80000001_00000003, SHR_U64, 63, 1),
    (0x80000001_00000003, SHR_S64, 4, 0xF8000000_10000000),
    (0x80000001_00000003, SHR_S64, 32, 0xFFFFFFFF_80000001),
    (0x80000001_00000003, SHR_S64, 36, 0xFFFFFFFF_F8000000),
    (0x80000001_00000003, SHR_S64, 63, 0xFFFFFFFF_FFFFFFFF),
    (0x40000000_00000000, SHR_S64, 62, 1),
    # rotl 4: the top 4 bits of hi, 1000, go to the bottom of lo.
    (0x80000001_00000003, ROTL64, 4, 0x00000010_00000038),
    # rotl 36 is rotl 4 of the swapped words, 0x00000003_80000001.
    (0x80000001_00000003, ROTL64, 36, 0x00000038_00000010),
    (0x80000001_00000003, ROTL64, 32, 0x00000003_80000001),
    # rotr 4: the bottom 4 bits of lo, 0011, go to the top of hi.
    (0x80000001_00000003, ROTR64, 4, 0x38000000_10000000),
    (0x80000001_00000003, ROTR64, 0, 0x80000001_00000003),
]

# More counts at the edges: 0, 1, 31, 36, and 63, and rotates by 36 and 64.
SHIFT64_EDGES: List[Tuple[int, bytes, int, int]] = [
    (0x80000001_00000003, SHL64, 63, 0x80000000_00000000),
    (0x80000001_00000003, SHL64, 2**64 - 1, 0x80000000_00000000),          # 63
    (0x80000001_00000003, SHR_U64, 0, 0x80000001_00000003),
    (0x80000001_00000003, SHR_U64, 1, 0x40000000_80000001),
    (0x80000001_00000003, SHR_U64, 36, 0x00000000_08000000),
    (0x80000001_00000003, SHR_S64, 0, 0x80000001_00000003),
    (0x80000001_00000003, SHR_S64, 31, 0xFFFFFFFF_00000002),
    # rotr 36 is rotr 4 of the swapped words, 0x00000003_80000001.
    (0x80000001_00000003, ROTR64, 36, 0x10000000_38000000),
    (0x80000001_00000003, ROTL64, 64, 0x80000001_00000003),
]


def op64_dyn(a: int, op: bytes, b: int, want: int) -> bytes:
    """op64, with the count in the i64 local 1, so that it is not a
    constant."""
    def c(x: int) -> bytes:
        return i64_const(x - 2**64 if x >= 2**63 else x)
    return c(a) + c(b) + local_tee(1) + op + c(want) + EQ64


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
    # 0, not in a data segment, and bumps to 100. lookup reads a table in a
    # data segment: lookup(3) + lookup(2) = 1000 - 5 = 995, and lookup(6),
    # past the table, is 0. 150 + 308 + 100 + 995 = 1553.
    ("data_c", "data", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 1553),
    # The same from Zig, which puts its stack first and the data after it,
    # so ___wasm_start clears the words below and above the data. primes[5]
    # = 13, and state = 0x12345678 + 100 = 0x123456DC. 13 + 0x56DC = 0x56E9.
    ("data_zig", "datazig", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 0x56E9),
    # Shifts from clang, with get(i) = i + 100. The CRC-32 of "123456789" is
    # the standard check value 0xCBF43926. XOR (1 rotl 31) = 0x80000000
    # gives 0x4BF43926. 1 << 40 >> 37 = 8, and -1 << 40 >> 40 = -1, so the
    # sum is 0x4BF43926 + 8 - 1 = 0x4BF4392D.
    ("shifts_c", "shifts", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 0x4BF4392D),
    # Division, long long, and bit counts from clang, with get(i) = i + 100.
    # gcd(2071, 1271) = 1: 2071 - 1271 = 800, then 471, 329, 142, 45, 7, 3,
    # and 1. (2^64 - 1) / 3 = 6148914691236517205, whose digits sum to 80.
    # -1000 * 7 / 3 = -2333. clz(1) + ctz(2^40) = 31 + 40 = 71.
    # popcount(255) = 8. (signed char)128 = -128. 1 + 80 - 2333 + 71 + 8 -
    # 128 = -2301 = 0xFFFFF703.
    ("intops_c", "intops", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 0xFFFFF703),
    # @memcpy, @memset, and @memmove from Zig, with get(i) = i + 100. buf
    # holds 0 to 39. buf[40..50] gets 3 to 12, which sum to 75, and
    # buf[50..60] ten 7s, 70. Then 0 to 19 move up by one, which overlaps,
    # so buf[20] = 19. 75 + 70 + 1000 * 19 = 19145.
    ("bulk_zig", "bulk", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 19145),
    # Zig with ReleaseSafe, which uses a table and call_indirect. Even x
    # from 0 to 9 are squared and odd ones incremented: 0 + 4 + 16 + 36 +
    # 64 = 120, and 2 + 4 + 6 + 8 + 10 = 30. 120 + 30 = 150.
    ("safe", "safe", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 150),
    # buf[4] is past the end of buf, so Zig panics, which traps with code 1.
    ("safetrap", "safetrap", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 1),
    # Hello world from Zig, through nice.poke to the console. 13 bytes.
    ("hello", "hello", "", 13),
    # Rust, with get(i) = i + 100. The calls through &dyn Shape use a
    # table and call_indirect. shapes[1..] is a 3 x 5 rectangle and a 3 x
    # 3 square: 15 + 9 = 24. The primes p with p % 4 == 1 are 5, 13, and
    # 17: 35. buf[j] = 7 * j, so after reverse buf[0] = 7 * 31 = 217.
    # 99 * 2^40 = 108851651149824, and / 1000000007 gives 108851, which %
    # 1000 is 851. 24 + 35 + 217 + 851 = 1127.
    ("rust", "rust", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 1127),
    # BUF[4] is past the end of BUF, so Rust panics, and the panic handler
    # traps with code 1.
    ("rusttrap", "rusttrap", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 1),
    # Hello world from Rust, through nice.poke. 13 bytes.
    ("hello_rs", "hellors", "", 13),
    # float and double from clang, with get(i) = i + 100, through the
    # float library. (1.5 * 1.5 + 0.5) * 1000 = 2750, sqrt(144) = 12, the
    # mean of 1.5, 2.5, 4, and 8 is 4, and Newton's method from 25 reaches
    # 5 exactly, as 0.5 * (5 + 25 / 5) = 5, so 500. -7.9 < -8 is 0.
    # 2750 + 12 + 4 + 500 = 3266.
    ("floats_c", "floats", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 3266),
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
    # Deferred values (README.md): a local.get leaves its local on the stack
    # until it must be written to its frame word. x = 5, then x is set to 7
    # with the old 5 still on the stack, then teed to 100 with the 7 still
    # there: 5 - (7 - 100) + 100 = 198. Then x = 3 and y = 4 are swapped
    # through the stack, x is set to itself, and y teed to itself: 198 +
    # (4 << 8) + (3 << 4) = 1270. The low word of the i64 local L, 5, is
    # still on the stack when L is set to 9: 1270 + 5 - 9 = 1266.
    ("defer_set", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code(([I32, I32, I64],
              i32_const(5) + local_set(0) + local_get(0) + i32_const(7) + local_set(0)
              + local_get(0) + i32_const(100) + local_tee(0) + SUB + SUB + local_get(0) + ADD
              + i32_const(3) + local_set(0) + i32_const(4) + local_set(1)
              + local_get(0) + local_get(1) + local_set(0) + local_set(1)
              + local_get(0) + local_set(0) + local_get(0) + i32_const(8) + SHL + ADD
              + local_get(1) + local_tee(1) + i32_const(4) + SHL + ADD
              + i64_const(0x1_00000005) + local_set(2) + local_get(2) + WRAP
              + i64_const(9) + local_set(2) + local_get(2) + WRAP + SUB + ADD))), "", 1266),
    # Deferred values and blocks. The 1000 stays on the stack, a constant,
    # until the end. a = 1 is below a block that sets a = 10: 1 + 10 = 11.
    # a is below a block that does not set it: + 10 = 21. br carries a, +
    # 10 = 31. br_if carries a, is not taken, and a = 20 follows with the
    # 10 still on the stack: + 10 = 41. A taken br_if carries 100: 141.
    # br_table carries a to the outer block, past the inner block's + 7:
    # 161. if and else give a (20), then 300: 481. An if without else
    # passes a on (501), or adds 2000 to it (2521). A loop adds 1 to a
    # three times: + 23 = 2544. + 1000 = 3544.
    ("defer_blocks", module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(0),
        exports(("main", 0, 0)),
        code((3, i32_const(1000)
              + i32_const(1) + local_set(0) + local_get(0)
              + block() + i32_const(1) + if_() + i32_const(10) + local_set(0) + END + END
              + local_get(0) + ADD
              + local_get(0) + block() + i32_const(0) + if_() + i32_const(30) + local_set(0)
              + END + END + ADD
              + block(I32) + local_get(0) + br(0) + END + ADD
              + i32_const(0) + local_set(1)
              + block(I32) + local_get(0) + local_get(1) + br_if(0)
              + i32_const(20) + local_set(0) + END + ADD
              + block(I32) + i32_const(100) + i32_const(1) + br_if(0) + DROP + i32_const(5)
              + END + ADD
              + block(I32) + block(I32) + local_get(0) + i32_const(1) + br_table([0, 1], 0)
              + END + i32_const(7) + ADD + END + ADD
              + i32_const(1) + if_(I32) + local_get(0) + ELSE + i32_const(3) + END + ADD
              + i32_const(0) + if_(I32) + local_get(0) + ELSE + i32_const(300) + END + ADD
              + local_get(0) + i32_const(0) + if_(typeidx(1)) + i32_const(2000) + ADD + END + ADD
              + local_get(0) + i32_const(1) + if_(typeidx(1)) + i32_const(2000) + ADD + END + ADD
              + i32_const(0) + local_set(2)
              + local_get(0) + loop(typeidx(1)) + local_get(2) + i32_const(1) + ADD
              + local_set(2) + i32_const(1) + ADD + local_get(2) + i32_const(3) + LT_U
              + br_if(0) + END + ADD
              + ADD))), "", 3544),
    # Deferred values as the arguments of a call, and across it. g(a, b, c,
    # d) = (a - wrap(b)) + (wrap(c) - d) + the high words of b and c, with a
    # and b in R1-R3, and c and d on the stack. main passes 1000, its local
    # L = 0x7_00000064, the constant 0x30_00002710, and its local x = 3:
    # 900 + 9997 + 7 + 48 = 10952. x is also on the stack below the call,
    # and is set to 77 after it: 3 + 10952 + 77 = 11032.
    ("defer_call", module(
        types(MAIN_TYPE, ([I32, I64, I64, I32], [I32])),
        funcs(1, 0),
        exports(("main", 0, 1)),
        code((0, local_get(0) + local_get(1) + WRAP + SUB + local_get(2) + WRAP + local_get(3)
              + SUB + ADD + local_get(1) + i64_const(32) + SHR_U64 + WRAP + ADD
              + local_get(2) + i64_const(32) + SHR_U64 + WRAP + ADD),
             ([I32, I64],
              i32_const(3) + local_set(0) + i64_const(0x7_00000064) + local_set(1)
              + local_get(0)
              + i32_const(1000) + local_get(1) + i64_const(0x30_00002710) + local_get(0) + call(0)
              + i32_const(77) + local_set(0) + ADD + local_get(0) + ADD))), "", 11032),
    # Instructions that write their result where their first operand would
    # be, with deferred operands. x = 5, L = 0x12345678_9ABCDEF0, and F has
    # the bits 0x40000000_00000001. One bit each, so 23 ones:
    ("defer_ops", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code(([I32, I32, I64, F64],
              i32_const(5) + local_set(0) + i64_const(0x123456789ABCDEF0) + local_set(2)
              + const(F64, 0x4000000000000001) + local_set(3)
              + bits(1,
                     # select, and x and L are unchanged
                     local_get(0) + i32_const(9) + i32_const(0) + SELECT + i32_const(9) + EQ,
                     local_get(0) + i32_const(9) + i32_const(1) + SELECT + i32_const(5) + EQ,
                     local_get(2) + i64_const(7) + i32_const(1) + select_t(I64)
                     + i64_const(0x123456789ABCDEF0) + EQ64,
                     i64_const(7) + local_get(2) + i32_const(0) + select_t(I64)
                     + i64_const(0x123456789ABCDEF0) + EQ64,
                     local_get(0) + i32_const(5) + EQ,
                     # neg, abs, and copysign, and F is unchanged
                     local_get(3) + F64_NEG + I64_REINTERPRET_F64
                     + i64_const(0xC000000000000001 - 2**64) + EQ64,
                     local_get(3) + I64_REINTERPRET_F64 + i64_const(0x4000000000000001) + EQ64,
                     const(F64, 0xC008000000000000) + F64_ABS + I64_REINTERPRET_F64
                     + i64_const(0x4008000000000000) + EQ64,
                     local_get(3) + const(F64, 0xBFF0000000000000) + F64_COPYSIGN
                     + I64_REINTERPRET_F64 + i64_const(0xC000000000000001 - 2**64) + EQ64,
                     # i64 shifts and rotates
                     local_get(2) + i64_const(4) + SHL64 + i64_const(0x23456789ABCDEF00) + EQ64,
                     local_get(2) + i64_const(36) + SHR_U64 + i64_const(0x01234567) + EQ64,
                     i64_const(-2**63) + i64_const(4) + SHR_S64
                     + i64_const(0xF800000000000000 - 2**64) + EQ64,
                     local_get(2) + i64_const(8) + ROTL64 + i64_const(0x3456789ABCDEF012) + EQ64,
                     local_get(2) + i64_const(8) + ROTR64
                     + i64_const(0xF0123456789ABCDE - 2**64) + EQ64,
                     # rem_s by -1, rem_s, div_u, and shl
                     i32_const(7) + i32_const(-1) + b"\x6f" + i32_const(0) + EQ,
                     local_get(0) + i32_const(3) + b"\x6f" + i32_const(2) + EQ,
                     local_get(0) + i32_const(2) + b"\x6e" + i32_const(2) + EQ,
                     local_get(0) + i32_const(33) + SHL + i32_const(10) + EQ,
                     # extensions, wrap, and reinterpret
                     i32_const(-2) + EXTEND_S + i64_const(-2) + EQ64,
                     local_get(2) + WRAP + i32_const(0x9ABCDEF0 - 2**32) + EQ,
                     local_get(2) + b"\xc2" + i64_const(-16) + EQ64,
                     const(F32, 0x3F800000) + I32_REINTERPRET_F32 + i32_const(0x3F800000) + EQ,
                     # L is still on the stack when it is set to 0
                     local_get(2) + i64_const(0) + local_set(2)
                     + i64_const(0x123456789ABCDEF0) + EQ64)))), "", 0x7FFFFF),
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
    # the word at 0 is 0x84838281. Each check is one bit (memory_checks).
    # The addresses are constants, so nicewasm knows them, and the aligned
    # accesses of 4 and 8 bytes are a MOVE each.
    ("memory", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, bits(0, *memory_checks(False))))), "", 0x3FFFFFFE),
    # The same with addresses that are known only when the code runs, which
    # take the inline path for an aligned access and the helpers otherwise.
    ("memory_dyn", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, bits(0, *memory_checks(True))))), "", 0x3FFFFFFE),
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
    # Shifts and rotates, one bit each. Wasm takes the count modulo 32 or
    # 64. V is 0x80000001_00000003.
    ("shifts", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0,
            op32(0x80000001, SHL, 1, 2),
            op32(0x80000001, SHL, 33, 2),                       # 33 mod 32 = 1
            op32(1, SHL, 0xFFFFFFFF, 0x80000000),               # count 31
            op32(0x80000001, SHR_U, 31, 1),
            op32(0x80000001, SHR_S, 4, 0xF8000000),
            op32(0x40000000, SHR_S, 30, 1),
            op32(0x80000001, SHR_S, 32, 0x80000001),            # count 0
            op32(0x80000001, ROTL, 1, 3),
            op32(0x80000001, ROTR, 1, 0xC0000000),
            op32(0x12345678, ROTL, 36, 0x23456781),             # by 4
            *[op64(*row) for row in SHIFT64_ROWS],
            # A check that fails.
            op32(1, SHL, 1, 1))))), "", 0x7FFFFFFE),
    # The edge counts, as constants, which nicewasm turns into a few
    # instructions inline. One bit each, so 9 ones.
    ("shift64_edges", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0, *[op64(*row) for row in SHIFT64_EDGES])))), "", 0x1FF),
    # All the i64 shifts and rotates again, with counts that are known only
    # when the code runs, which call the helpers. 29 ones.
    ("shift64_dyn", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code(([I32, I64], bits(0, *[op64_dyn(*row) for row in SHIFT64_ROWS + SHIFT64_EDGES])))),
     "", 0x1FFFFFFF),
    # The other integer operations, one bit each. MIN is the most negative
    # number. The routines are in runtime/lib.asm.
    ("intops", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0,
            un32(0x67, 0, 32),                                  # clz
            un32(0x67, 1, 31),
            un32(0x68, 0x80000000, 31),                         # ctz
            un32(0x69, 0xF0F0, 8),                              # popcnt
            un64(0x79, 0x1_00000000, 31),                       # clz
            un64(0x7A, 0x1_00000000, 32),                       # ctz
            un64(0x7B, 2**64 - 1, 64),                          # popcnt
            # mul: (2^32 - 1)^2 = 2^64 - 2^33 + 1, and -3 * 5 = -15.
            op64(0xFFFFFFFF, b"\x7e", 0xFFFFFFFF, 0xFFFFFFFE_00000001),
            op64(2**64 - 3, b"\x7e", 5, 2**64 - 15),
            # -7 / 2 = -3 rem -1, rounding toward 0. Unsigned, -7 is
            # 4294967289 = 2 * 2147483644 + 1.
            op32(2**32 - 7, b"\x6d", 2, 2**32 - 3),
            op32(2**32 - 7, b"\x6f", 2, 2**32 - 1),
            op32(2**32 - 7, b"\x6e", 2, 0x7FFFFFFC),
            op32(2**32 - 7, b"\x70", 2, 1),
            # rem_s by -1 is 0, even for MIN, where C leaves it undefined.
            op32(0x80000000, b"\x6f", 2**32 - 1, 0),
            op32(5, b"\x6f", 2**32 - 1, 0),
            # MIN / 1 does not trap.
            op32(0x80000000, b"\x6d", 1, 0x80000000),
            op64(2**64 - 7, b"\x7f", 2, 2**64 - 3),
            op64(2**64 - 7, b"\x81", 2, 2**64 - 1),
            # 2^32 / 3 = 0x55555555 rem 1.
            op64(2**32, b"\x80", 3, 0x55555555),
            op64(2**32, b"\x82", 3, 1),
            op64(2**63, b"\x81", 2**64 - 1, 0),
            # -1 in the low word alone is not -1, so this does not trap.
            # 2^63 = (2^32 - 1) * 2^31 + 2^31, so MIN / (2^32 - 1) = -2^31.
            op64(2**63, b"\x7f", 0xFFFFFFFF, 0xFFFFFFFF_80000000),
            un32(0xC0, 0x80, 2**32 - 128),                      # extend8_s
            un32(0xC0, 0x17F, 0x7F),
            un32(0xC1, 0x8000, 2**32 - 32768),                  # extend16_s
            un64(0xC2, 0xFF, 2**64 - 1),
            un64(0xC3, 0x7FFF, 0x7FFF),
            un64(0xC4, 0x80000000, 2**64 - 2**31),              # extend32_s
            un64(0xC4, 0x1_7FFFFFFF, 0x7FFFFFFF),
            # A check that fails.
            op32(7, b"\x6e", 2, 4))))), "", 0x3FFFFFFE),
    # Division by 0 traps with code 3, and MIN / -1 with code 4.
    ("divzero", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i32_const(5) + i32_const(0) + b"\x6e"))), "", 3),
    ("divzero64", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i64_const(5) + i64_const(0) + b"\x81" + WRAP))), "", 3),
    ("overflow", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i32_const(-2**31) + i32_const(-1) + b"\x6d"))), "", 4),
    ("overflow64", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i64_const(-2**63) + i64_const(-1) + b"\x7f" + WRAP))), "", 4),
    # memory.fill and memory.copy. The memory starts at 0. Each line is one
    # bit. Little-endian, so bytes 00 AB AB AB are the word 0xABABAB00.
    ("bulk", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, bits(0,
            # AB, the low byte of 0x1AB, in bytes 1-6.
            fill(1, 0x1AB, 6) + ld(I32_LOAD, 0, 0xABABAB00 - 2**32),
            ld(I32_LOAD, 4, 0x00ABABAB),
            ld(I32_LOAD8_U, 7, 0),
            # 5A in bytes 9-21: three bytes, two whole words, two bytes.
            fill(9, 0x5A, 13) + ld(I32_LOAD, 8, 0x5A5A5A00),
            ld(I32_LOAD, 12, 0x5A5A5A5A),
            ld(I32_LOAD, 16, 0x5A5A5A5A),
            ld(I32_LOAD, 20, 0x00005A5A),
            # 0 bytes: nothing.
            fill(30, 7, 0) + ld(I32_LOAD, 28, 0),
            # Bytes 64-75 are 11 22 ... CC. Copying bytes 65-74 to 129-138,
            # at the same place in a word: three bytes, a word, three bytes.
            st(I32_STORE, 64, 0x44332211) + st(I32_STORE, 68, 0x88776655 - 2**32)
            + st(I32_STORE, 72, 0xCCBBAA99 - 2**32)
            + copy(129, 65, 10) + ld(I32_LOAD, 128, 0x44332200),
            ld(I32_LOAD, 132, 0x88776655 - 2**32),
            ld(I32_LOAD, 136, 0x00BBAA99),
            # Bytes 65-69 to 194-198, at another place in a word.
            copy(194, 65, 5) + ld(I32_LOAD, 192, 0x33220000),
            ld(I32_LOAD, 196, 0x00665544),
            # Overlapping, down: bytes 259-266 to 257-264 in 11 22 ... CC at
            # 256. Copied from the start, so each byte is read before it is
            # overwritten: 11 44 55 66 77 88 99 AA BB AA BB CC.
            st(I32_STORE, 256, 0x44332211) + st(I32_STORE, 260, 0x88776655 - 2**32)
            + st(I32_STORE, 264, 0xCCBBAA99 - 2**32)
            + copy(257, 259, 8) + ld(I32_LOAD, 256, 0x66554411),
            ld(I32_LOAD, 260, 0xAA998877 - 2**32),
            ld(I32_LOAD, 264, 0xCCBBAABB - 2**32),
            # Overlapping, up: bytes 321-329 to 325-333 in 11 22 ... FF 00 at
            # 320. Copied from the end: two bytes, a word, three bytes. The
            # result is 11 22 33 44 55 22 33 44 55 66 77 88 99 AA FF 00.
            st(I32_STORE, 320, 0x44332211) + st(I32_STORE, 324, 0x88776655 - 2**32)
            + st(I32_STORE, 328, 0xCCBBAA99 - 2**32) + st(I32_STORE, 332, 0x00FFEEDD)
            + copy(325, 321, 9) + ld(I32_LOAD, 324, 0x44332255),
            ld(I32_LOAD, 328, 0x88776655 - 2**32),
            ld(I32_LOAD, 332, 0x00FFAA99),
            # The last 4 bytes, and 0 bytes at the end of the memory, which
            # do not trap.
            fill(65532, 0xEE, 4) + fill(65536, 1, 0) + copy(65536, 65536, 0)
            + ld(I32_LOAD, 65532, 0xEEEEEEEE - 2**32),
            # A check that fails.
            ld(I32_LOAD, 28, 1))))), "", 0x1FFFFE),
    # 4 bytes from 65533 pass the end of the memory, and so does a source of
    # 2 bytes from 65535. Both trap with code 2.
    ("filloob", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((0, fill(65533, 0, 4) + i32_const(0)))), "", 2),
    ("copyoob", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((0, copy(0, 65535, 2) + i32_const(0)))), "", 2),
    # call_indirect. Function 0 is the import ext(x) = x + 1000, and 1-4 are
    # double(x) = 2x, sub(a, b) = a - b, neg(x) = -x, and dbl64(x) = 2x
    # for an i64. Types 1 and 3 are both (i32) -> (i32), so they match.
    # The segments fill table entries 1-5 with functions 1, 2, 3, 0, 4, entry
    # 6 with 1, and entry 7, with a ref.func, with 2. Entry 0 is empty.
    # Each line is one bit:
    ("indirect", module(
        types(MAIN_TYPE, ([I32], [I32]), ([I32, I32], [I32]), ([I32], [I32]), ([I64], [I64])),
        imports(("env", "ext", 1)),
        funcs(1, 2, 3, 4, 0),
        table(8),
        exports(("main", 0, 5)),
        elems((1, [1, 2, 3, 0, 4]), (6, [1]), exprs=[(7, [2])]),
        code((0, local_get(0) + local_get(0) + ADD),
             (0, local_get(0) + local_get(1) + SUB),
             (0, i32_const(0) + local_get(0) + SUB),
             (0, local_get(0) + local_get(0) + ADD64),
             (1, bits(0,
                i32_const(21) + i32_const(1) + call_indirect(1) + i32_const(42) + EQ,
                # Type 3 matches double's type 1.
                i32_const(7) + i32_const(1) + call_indirect(3) + i32_const(14) + EQ,
                i32_const(50) + i32_const(8) + i32_const(2) + call_indirect(2) + i32_const(42) + EQ,
                i32_const(5) + i32_const(3) + call_indirect(1) + i32_const(-5) + EQ,
                i32_const(5) + i32_const(4) + call_indirect(1) + i32_const(1005) + EQ,
                i64_const(0x1_00000001) + i32_const(5) + call_indirect(4)
                + i64_const(0x2_00000002) + EQ64,
                i32_const(9) + i32_const(6) + call_indirect(1) + i32_const(18) + EQ,
                i32_const(9) + i32_const(4) + i32_const(7) + call_indirect(2) + i32_const(5) + EQ,
                # A check that fails.
                i32_const(9) + i32_const(6) + call_indirect(1) + i32_const(9) + EQ)))),
     "_ext ADD R1, R1, 1000\n MOVE R15, @R13++\n", 0x1FE),
    # Index 4 is past the end of a table of 4, and entry 0 is empty: both
    # trap with code 6. Entry 1 holds a function of type 1, so a call of
    # type 2 traps with code 7.
    ("indirectoob", module(
        types(MAIN_TYPE, ([I32], [I32]), ([I32, I32], [I32])),
        funcs(1, 0),
        table(4),
        exports(("main", 0, 1)),
        elems((1, [0])),
        code((0, local_get(0)),
             (0, i32_const(1) + i32_const(4) + call_indirect(1)))), "", 6),
    ("indirectnull", module(
        types(MAIN_TYPE, ([I32], [I32]), ([I32, I32], [I32])),
        funcs(1, 0),
        table(4),
        exports(("main", 0, 1)),
        elems((1, [0])),
        code((0, local_get(0)),
             (0, i32_const(1) + i32_const(0) + call_indirect(1)))), "", 6),
    ("indirecttype", module(
        types(MAIN_TYPE, ([I32], [I32]), ([I32, I32], [I32])),
        funcs(1, 0),
        table(4),
        exports(("main", 0, 1)),
        elems((1, [0])),
        code((0, local_get(0)),
             (0, i32_const(1) + i32_const(2) + i32_const(1) + call_indirect(2)))), "", 7),
    # nice.peek and nice.poke. cell() returns the address of a word that
    # starts as 7. main pokes 41 into it, then prints H, i, and a newline
    # on the console at 0xFFFFFF00, which prints bits 7..0 of each word, so
    # 0x169 prints i. A peek whose result is dropped is still performed.
    # peek of the word + 1 = 42.
    ("peekpoke", module(
        types(MAIN_TYPE, ([I32], [I32]), ([I32, I32], [])),
        imports(("nice", "peek", 1), ("nice", "poke", 2), ("env", "cell", 0)),
        funcs(0),
        exports(("main", 0, 3)),
        code((1, call(2) + local_set(0)
              + local_get(0) + i32_const(41) + call(1)
              + i32_const(-256) + i32_const(ord("H")) + call(1)
              + i32_const(-256) + i32_const(0x169) + call(1)
              + i32_const(-256) + i32_const(10) + call(1)
              + local_get(0) + call(0) + DROP
              + local_get(0) + call(0) + i32_const(1) + ADD))),
     "_cell MOVE R1, cell\n MOVE R15, @R13++\ncell .DAT 7\n", 42),
    # f32 and f64 values as bits, one bit each. 1.5 is 0x3FC00000, 2.0
    # 0x40000000, 3.0 0x40400000, and 1.0 as an f64 0x3FF0000000000000.
    # f0 to f3 take (f32 a, f64 b, f32 c, f64 d) = (1.0, 2.0, 3.0, 4.0),
    # which go in R1, R2:R3, R4, and on the stack, and return b, d, c, and a.
    ("floatdata", module(
        types(MAIN_TYPE, ([F32, F64, F32, F64], [F64]), ([F32, F64, F32, F64], [F32])),
        funcs(1, 1, 2, 2, 0),
        memory(1),
        typed_globals((F32, False, 0x40490FDB), (F64, True, 0x4005BF0A8B145769)),
        exports(("main", 0, 4)),
        code((0, local_get(1)), (0, local_get(3)), (0, local_get(2)), (0, local_get(0)),
             (1, bits(0,
                bits32(f32(0x3FC00000), 0x3FC00000),
                bits32(f32(0x3FC00000) + F32_NEG, 0xBFC00000),
                bits32(f32(0xC0000000) + F32_ABS, 0x40000000),
                bits32(f32(0x40400000) + f32(0x80000000) + F32_COPYSIGN, 0xC0400000),
                bits32(f32(0xC0400000) + f32(0x3F800000) + F32_COPYSIGN, 0x40400000),
                bits64(f64(0x3FF0000000000000) + F64_NEG, 0xBFF0000000000000),
                bits64(f64(0x8000000000000000) + F64_ABS, 0),
                bits64(f64(0x4000000000000000) + f64(0xBFF0000000000000) + F64_COPYSIGN,
                       0xC000000000000000),
                # A NaN keeps its bits.
                bits32(i32_const(0x7FC00001) + F32_REINTERPRET_I32, 0x7FC00001),
                # An f64 at byte 3, across three words, and back.
                i32_const(3) + f64(0x0123456789ABCDEF) + mem(F64_STORE)
                + i32_const(3) + mem(I64_LOAD) + i64_const(0x0123456789ABCDEF) + EQ64,
                bits64(i32_const(3) + mem(F64_LOAD), 0x0123456789ABCDEF),
                bits32(i32_const(0) + f32(0x40490FDB) + mem(F32_STORE) + i32_const(0)
                       + mem(F32_LOAD), 0x40490FDB),
                bits32(global_get(0), 0x40490FDB),                   # pi
                bits64(global_get(1), 0x4005BF0A8B145769),           # e
                bits64(f32(0x3F800000) + f64(0x4000000000000000) + f32(0x40400000)
                       + f64(0x4010000000000000) + call(0), 0x4000000000000000),
                bits64(f32(0x3F800000) + f64(0x4000000000000000) + f32(0x40400000)
                       + f64(0x4010000000000000) + call(1), 0x4010000000000000),
                bits32(f32(0x3F800000) + f64(0x4000000000000000) + f32(0x40400000)
                       + f64(0x4010000000000000) + call(2), 0x40400000),
                bits32(f32(0x3F800000) + f64(0x4000000000000000) + f32(0x40400000)
                       + f64(0x4010000000000000) + call(3), 0x3F800000),
                bits64(f64(1) + f64(2) + i32_const(0) + select_t(F64), 2),
                # A check that fails.
                bits32(f32(0x3FC00000), 0x3FC00001))))), "", 0xFFFFE),
    # f32 arithmetic through the float library, one bit each. Some bits:
    # 1.0 = 0x3F800000, 1.5 = 0x3FC00000, 2.0 = 0x40000000, 2.5 = 0x40200000,
    # 3.0 = 0x40400000, 3.5 = 0x40600000, 0.5 = 0x3F000000, 0.75 = 0x3F400000,
    # 0.1 = 0x3DCCCCCD, 0.2 = 0x3E4CCCCD, NaN = 0x7FC00000, -0.0 = 0x80000000.
    ("float32", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0,
            bits32(f32(0x3F800000) + f32(0x40000000) + fop(0x92), 0x40400000),      # 1 + 2 = 3
            bits32(f32(0x3DCCCCCD) + f32(0x3E4CCCCD) + fop(0x92), 0x3E99999A),      # 0.1 + 0.2 = 0.3
            bits32(f32(0x3F800000) + f32(0x40400000) + fop(0x93), 0xC0000000),      # 1 - 3 = -2
            bits32(f32(0x3FC00000) + f32(0x3FC00000) + fop(0x94), 0x40100000),      # 2.25
            bits32(f32(0x3F800000) + f32(0x40400000) + fop(0x95), 0x3EAAAAAB),      # 1/3
            bits32(f32(0x40000000) + fop(0x91), 0x3FB504F3),                        # sqrt 2
            bits32(f32(0x40800000) + fop(0x91), 0x40000000),                        # sqrt 4 = 2
            is_nan32(f32(0xBF800000) + fop(0x91)),                                  # sqrt -1
            bits32(f32(0x80000000) + fop(0x91), 0x80000000),                        # sqrt -0 = -0
            bits32(f32(0x3FC00000) + fop(0x8D), 0x40000000),                        # ceil 1.5 = 2
            bits32(f32(0xBF000000) + fop(0x8D), 0x80000000),                        # ceil -0.5 = -0
            bits32(f32(0xBFC00000) + fop(0x8E), 0xC0000000),                        # floor -1.5 = -2
            bits32(f32(0x3F000000) + fop(0x8E), 0),                                 # floor 0.5 = 0
            bits32(f32(0xBFD9999A) + fop(0x8F), 0xBF800000),                        # trunc -1.7 = -1
            bits32(f32(0x40200000) + fop(0x90), 0x40000000),                        # nearest 2.5 = 2
            bits32(f32(0x40600000) + fop(0x90), 0x40800000),                        # nearest 3.5 = 4
            bits32(f32(0xBF000000) + fop(0x90), 0x80000000),                        # nearest -0.5 = -0
            bits32(f32(0x3F400000) + fop(0x90), 0x3F800000),                        # nearest 0.75 = 1
            bits32(f32(0x80000000) + f32(0) + fop(0x96), 0x80000000),               # min(-0, 0) = -0
            bits32(f32(0x80000000) + f32(0) + fop(0x97), 0),                        # max(-0, 0) = 0
            is_nan32(f32(0x3F800000) + f32(0x7FC00000) + fop(0x96)),                # min(1, NaN)
            f32(0x3F800000) + f32(0x40000000) + fop(0x5D),                          # 1 < 2
            f32(0x7FC00000) + f32(0x7FC00000) + fop(0x5B) + EQZ,                    # NaN == NaN is 0
            f32(0x7FC00000) + f32(0x7FC00000) + fop(0x5C),                          # NaN != NaN
            f32(0x80000000) + f32(0) + fop(0x5B),                                   # -0 == 0
            f32(0x40000000) + f32(0x40000000) + fop(0x5F),                          # 2 <= 2
            f32(0x7FC00000) + f32(0x3F800000) + fop(0x60) + EQZ,                    # NaN >= 1 is 0
            f32(0x40400000) + f32(0x40000000) + fop(0x5E),                          # 3 > 2
            f32(0x7FC00000) + f32(0x3F800000) + fop(0x5D) + EQZ,                    # NaN < 1 is 0
            # Quotients near the subnormals: (2^-126)(2 - 2^-23) / 2 rounds
            # up to the smallest normal, 2^-126, and 2^-126 / 2 = 2^-127.
            bits32(f32(0x00FFFFFF) + f32(0x40000000) + fop(0x95), 0x00800000),
            bits32(f32(0x00800000) + f32(0x40000000) + fop(0x95), 0x00400000),
            # A check that fails.
            bits32(f32(0x3F800000) + f32(0x40000000) + fop(0x92), 0x40000000))))), "", 0xFFFFFFFE),
    # The same for f64. 0.1 = 0x3FB999999999999A, 0.2 = 0x3FC999999999999A,
    # 1e10 = 0x4202A05F20000000, 1/3 = 0x3FD5555555555555.
    ("float64", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0,
            # 0.1 + 0.2 = 0.30000000000000004.
            bits64(f64(0x3FB999999999999A) + f64(0x3FC999999999999A) + fop(0xA0),
                   0x3FD3333333333334),
            bits64(f64(0x3FF0000000000000) + f64(0x4008000000000000) + fop(0xA1),
                   0xC000000000000000),                                             # 1 - 3 = -2
            # 1e10 * 1e10 = 1e20 = 2^20 * 5^20 exactly.
            bits64(f64(0x4202A05F20000000) + f64(0x4202A05F20000000) + fop(0xA2),
                   0x4415AF1D78B58C40),
            bits64(f64(0x3FF0000000000000) + f64(0x4008000000000000) + fop(0xA3),
                   0x3FD5555555555555),                                             # 1/3
            bits64(f64(0x4000000000000000) + fop(0x9F), 0x3FF6A09E667F3BCD),        # sqrt 2
            bits64(f64(0x4022000000000000) + fop(0x9F), 0x4008000000000000),        # sqrt 9 = 3
            bits64(f64(0xC004000000000000) + fop(0x9E), 0xC000000000000000),        # nearest -2.5 = -2
            bits64(f64(0x8000000000000000) + fop(0x9C), 0x8000000000000000),        # floor -0 = -0
            bits64(f64(0x3FF8000000000000) + fop(0x9B), 0x4000000000000000),        # ceil 1.5 = 2
            bits64(f64(0xBFF8000000000000) + fop(0x9D), 0xBFF0000000000000),        # trunc -1.5 = -1
            bits64(f64(0x4000000000000000) + f64(0x4008000000000000) + fop(0xA5),
                   0x4008000000000000),                                             # max(2, 3) = 3
            bits64(f64(0x4000000000000000) + f64(0x4008000000000000) + fop(0xA4),
                   0x4000000000000000),                                             # min(2, 3) = 2
            f64(0x3FF0000000000000) + f64(0x4000000000000000) + fop(0x63),          # 1 < 2
            f64(0x7FF8000000000000) + f64(0x7FF8000000000000) + fop(0x62),          # NaN != NaN
            f64(0x7FF8000000000000) + f64(0x3FF0000000000000) + fop(0x65) + EQZ,    # NaN <= 1 is 0
            f64(0x4000000000000000) + f64(0x4000000000000000) + fop(0x66),          # 2 >= 2
            # Subnormal quotients: 1 / DBL_MAX = 2^-1024 (1 + 2^-53 + ...),
            # which is 2^-1024 after rounding, and 3 * 2^-1074 / 2 = 1.5 *
            # 2^-1074, a tie that goes to the even 2 * 2^-1074.
            bits64(f64(0x3FF0000000000000) + f64(0x7FEFFFFFFFFFFFFF) + fop(0xA3),
                   0x0004000000000000),
            bits64(f64(3) + f64(0x4000000000000000) + fop(0xA3), 2),
            # A check that fails.
            bits64(f64(0x4000000000000000) + fop(0x9F), 0x3FF6A09E667F3BCE))))), "", 0x7FFFE),
    # Conversions, one bit each. MIN is -2^31.
    ("floatconv", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((1, bits(0,
            f32(0xC039999A) + fop(0xA8) + i32_const(-2) + EQ,                       # trunc -2.9 = -2
            f32(0x4F32D05E) + fop(0xA9) + i32_const(3000000000 - 2**32) + EQ,       # 3e9, unsigned
            f32(0xCF000000) + fop(0xA8) + i32_const(-2**31) + EQ,                   # -2^31 fits
            f64(0xC1E00000001CCCCD) + fop(0xAA) + i32_const(-2**31) + EQ,           # -2147483648.9
            f64(0xBFECCCCCCCCCCCCD) + fop(0xAB) + EQZ,                              # -0.9 unsigned = 0
            f64(0xC3ABC16D674EC800) + fop(0xB0) + i64_const(-10**18) + EQ64,        # -1e18
            f64(0xC3E0000000000000) + fop(0xB0) + i64_const(-2**63) + EQ64,         # -2^63 fits
            bits32(i32_const(-5) + fop(0xB2), 0xC0A00000),                          # -5.0
            bits32(i32_const(-1) + fop(0xB3), 0x4F800000),                          # 2^32 - 1 rounds to 2^32
            bits64(i64_const(-1) + fop(0xB9), 0xBFF0000000000000),                  # -1.0
            bits64(i64_const(-1) + fop(0xBA), 0x43F0000000000000),                  # 2^64 - 1 rounds to 2^64
            bits64(f32(0x3DCCCCCD) + fop(0xBB), 0x3FB99999A0000000),                # promote 0.1f
            bits32(f64(0x3FB999999999999A) + fop(0xB6), 0x3DCCCCCD),                # demote 0.1
            # trunc_sat saturates, and gives 0 for a NaN.
            f32(0x501502F9) + fop(0x100) + i32_const(0x7FFFFFFF) + EQ,              # 1e10
            f32(0x7FC00000) + fop(0x100) + EQZ,                                     # NaN
            f32(0xBF800000) + fop(0x101) + EQZ,                                     # -1.0 unsigned
            f64(0xC3E0000000000001) + fop(0x106) + i64_const(-2**63) + EQ64,        # below -2^63
            # A check that fails.
            f32(0xC039999A) + fop(0xA8) + i32_const(-3) + EQ)))), "", 0x3FFFE),
    # trunc traps with code 5 if the integer part does not fit: 2^31 as an
    # i32, -2^31 - 1 as an i32, -1 as an unsigned i32, and a NaN.
    ("trunc_big", module(types(MAIN_TYPE), funcs(0), exports(("main", 0, 0)),
                         code((0, f32(0x4F000000) + fop(0xA8))), ), "", 5),
    ("trunc_small", module(types(MAIN_TYPE), funcs(0), exports(("main", 0, 0)),
                           code((0, f64(0xC1E0000000200000) + fop(0xAA))), ), "", 5),
    ("trunc_neg", module(types(MAIN_TYPE), funcs(0), exports(("main", 0, 0)),
                         code((0, f64(0xBFF0000000000000) + fop(0xAB))), ), "", 5),
    ("trunc_nan", module(types(MAIN_TYPE), funcs(0), exports(("main", 0, 0)),
                         code((0, f32(0x7FC00000) + fop(0xAE) + WRAP)), ), "", 5),
    # A library module: main calls its __twice, labelled ___twice, which
    # uses the module's own stack and memory. 2 * 21 = 42.
    ("library", LIB_MODULE, LIB_ASM.format("MOVE R1, 21", "___twice", "MOVE R0, R0"), 42),
    # peek100 reads past the 64 bytes that are reserved, so it traps with
    # code 2.
    ("libtrap", LIB_MODULE, LIB_ASM.format("MOVE R0, R0", "_peek100", "MOVE R0, R0"), 2),
    # With 128 bytes reserved, it reads 0.
    ("libmem", LIB_MODULE, LIB_ASM.format("MOVE R0, R0", "_peek100", "ADD R1, R1, 5"), 5),
    # memory.grow, with up to 3 pages. dirty() writes 77 in the first word of
    # page 1 and 99 in the last word of page 2, which are not in the memory
    # yet. memory.grow must set them to 0. One bit each:
    ("grow", module(
        types(MAIN_TYPE, ([], [])),
        imports(("env", "dirty", 1)),
        funcs(0),
        memory(1),
        exports(("main", 0, 1)),
        code((1, bits(0,
            MEMORY_SIZE + i32_const(1) + EQ,
            call(0) + i32_const(1) + MEMORY_GROW + i32_const(1) + EQ,       # returns the old size
            MEMORY_SIZE + i32_const(2) + EQ,
            ld(I32_LOAD, 65536, 0),                                          # 77 is gone
            st(I32_STORE, 131068, 77) + ld(I32_LOAD, 131068, 77),            # page 1 works
            i32_const(5) + MEMORY_GROW + i32_const(-1) + EQ,                 # only 1 page left
            i32_const(1) + MEMORY_GROW + i32_const(2) + EQ,
            i32_const(1) + MEMORY_GROW + i32_const(-1) + EQ,                 # at the cap
            i32_const(0) + MEMORY_GROW + i32_const(3) + EQ,
            ld(I32_LOAD, 196604, 0),                                         # 99 is gone
            ld(I64_LOAD, 196600, 0),                                         # the last 8 bytes
            fill(196600, 0xAB, 8) + ld(I32_LOAD, 196600, 0xABABABAB - 2**32),
            # A check that fails.
            MEMORY_SIZE + i32_const(2) + EQ)))),
     "_dirty MOVE @___wasm_memory+16384, 77\n MOVE @___wasm_memory+49151, 99\n"
     " MOVE R15, @R13++\n", 0x1FFE),
    # Page 1 is reserved, but not part of the memory until it grows, so a
    # load from it traps.
    ("growtrap", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((0, i32_const(65536) + mem(I32_LOAD)))), "", 2),
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


def float_library(tmp: str) -> Tuple[str, Set[str]]:
    """Translates the float library, and returns its file and the labels
    of its routines."""
    asm = os.path.join(tmp, "float.asm")
    run([sys.executable, NICEWASM, "--library", "float", "-o", asm,
         os.path.join(RUNTIME, "float.wasm")])
    with open(asm) as f:
        labels = {line.strip() for line in f if line.startswith("__")}
    return asm, labels


def check(name: str, wasm_file: str, extra: str, expected: int, tmp: str,
          floats: Tuple[str, Set[str]]) -> List[str]:
    trap = name in TRAPS
    asm = os.path.join(tmp, name + ".asm")
    run([sys.executable, NICEWASM, *OPTIONS.get(name, []), "-o", asm, wasm_file])
    hand = os.path.join(HERE, name + ".asm")
    if os.path.exists(hand):
        with open(hand) as f:
            extra += f.read()
    with open(asm) as f:
        text = f.read()
    parts = [os.path.join(RUNTIME, "start_wasm.asm"), None, asm, os.path.join(RUNTIME, "lib.asm")]
    if any(label in text for label in floats[1]):
        parts.append(floats[0])
    lines: List[str] = []
    for part in parts:
        if part is None:
            lines += extra.splitlines(keepends=True)
        else:
            with open(part) as f:
                lines += f.readlines()
    assembler = niceasm.Assembler()
    errors = assembler.run(lines, name + ".full.asm")
    if errors:
        raise RuntimeError("\n".join(errors))
    image = dict(assembler.output())
    binary = os.path.join(tmp, name + ".bin")
    with open(binary, "w") as f:
        f.writelines(f"{a:08x} {w:08x}\n" for a, w in sorted(image.items()))
    output = run([NICEEMU, binary])
    # The console output comes before the line that says why it halted.
    at = output.find("Halted (")
    console, output = output[:max(at, 0)], output[max(at, 0):]

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
    if console != CONSOLE.get(name, ""):
        problems.append(f"printed {console!r}, expected {CONSOLE.get(name, '')!r}")
    mem = assembler.labels.get("___wasm_memory")
    if mem is not None and all(a in image for a in range(mem, mem + 16384)):
        problems.append("the memory is in the program image")
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
        floats = float_library(tmp)
        for name, wasm, extra, expected in CASES:
            if isinstance(wasm, bytes):
                wasm_file = os.path.join(tmp, FILE_NAMES.get(name, name + ".wasm"))
                with open(wasm_file, "wb") as f:
                    f.write(wasm)
            else:
                wasm_file = os.path.join(HERE, wasm + ".wasm")
            try:
                problems = check(name, wasm_file, extra, expected, tmp, floats)
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
