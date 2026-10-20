#!/usr/bin/env python3
"""Runs translated wasm modules in the emulator.

Each case is a module, either built here with wasm.py or compiled from a
test/X.c, test/X.zig, or test/X.rs source into test/X.wasm. It is translated and joined
with runtime/start_wasm.nasm, any hand-written assembly the case needs,
runtime/lib.nasm, and runtime/muldiv_mpu.nasm, as ABI.md describes. If
it calls the float library, runtime/float.wasm translated as the library
module float follows. Then it is assembled and run. Each case runs twice:
as translated by default, with the math unit (SYSTEM.md §2), and with
--no-mpu and runtime/muldiv_soft.nasm.

The program must halt with HALT and main's result in R1, and print what
CONSOLE gives on the console, or nothing. A case in TRAPS
must instead trap: halt at ___wasm_trap with the trap code in R1, and R2
pointing at the first instruction of the code for the wasm instruction
that trapped, which TRAPS gives. The first page of its memory, reserved
with .RES, must not be in the program image. Unless it trapped, R7-R12
must be 0 and SP must be 0xFFFFFF00 again, as the start-up code left them,
because every translated function must preserve them (ABI.md). The expected
results were worked out by hand from the sources."""

from __future__ import annotations

import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Dict, List, Optional, Set, Tuple, Union

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
from wasm import name as wname, section, u, vec

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


def as_if(check: bytes) -> bytes:
    """The i32 that check leaves, 0 or 1, taken by an if."""
    return check + if_(I32) + i32_const(1) + ELSE + i32_const(0) + END


def as_br_if(check: bytes) -> bytes:
    """The same, taken by a br_if that carries a value out of a block."""
    return block(I32) + i32_const(1) + check + br_if(0) + DROP + i32_const(0) + END


def as_eqz_br_if(check: bytes) -> bytes:
    """The same, taken by eqz and a br_if that carries no value. Local 1
    holds the result."""
    return (i32_const(0) + local_set(1) + block() + check + EQZ + br_if(0)
            + i32_const(1) + local_set(1) + END + local_get(1))


def ld(op: int, addr: int, want: int, offset: int = 0) -> bytes:
    """A check that the load op at addr + offset gives want."""
    i64 = op in (I64_LOAD, I64_LOAD8_S, I64_LOAD8_U, I64_LOAD16_S, I64_LOAD32_S, I64_LOAD32_U)
    return (i32_const(addr) + mem(op, offset)
            + (i64_const(want) + EQ64 if i64 else i32_const(want) + EQ))


def ld_dyn(op: int, addr: int, want: int, offset: int = 0) -> bytes:
    """ld, with the address in local 1, so that it is not a constant."""
    return i32_const(addr) + local_tee(1) + ld(op, addr, want, offset)[len(i32_const(addr)):]


def st_dyn(op: int, addr: int, value: int, offset: int = 0) -> bytes:
    """st, with the address in local 1."""
    return i32_const(addr) + local_tee(1) + st(op, addr, value, offset)[len(i32_const(addr)):]


def fill(addr: int, value: int, n: int) -> bytes:
    return i32_const(addr) + i32_const(value) + i32_const(n) + MEMORY_FILL


def copy(dest: int, src: int, n: int) -> bytes:
    return i32_const(dest) + i32_const(src) + i32_const(n) + MEMORY_COPY


def st(op: int, addr: int, value: int, offset: int = 0) -> bytes:
    """Stores value at addr + offset."""
    i64 = op in (I64_STORE, I64_STORE8, I64_STORE16, I64_STORE32)
    return i32_const(addr) + (i64_const(value) if i64 else i32_const(value)) + mem(op, offset)


def st_self(op: int, addr: int, k: int) -> bytes:
    """Stores addr + k at addr, with addr in local 1, so that neither the
    address nor the value is a constant."""
    return i32_const(addr) + local_tee(1) + local_get(1) + i32_const(k) + ADD + mem(op)


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

# A library module whose elem(i) loads the word at (i << 2) + 32, which
# nicewasm folds into the word operand (README.md).
LIB_FOLD = module(
    types(([I32], [I32])),
    funcs(0),
    memory(1),
    exports(("elem", 0, 0)),
    code((0, local_get(0) + i32_const(2) + SHL + i32_const(32) + ADD + mem(I32_LOAD))))

# Hand-written assembly for the library cases: the program's ___wasm_start,
# which does nothing, and its main, which runs an instruction, calls a
# routine, and runs another instruction.
LIB_ASM = "___wasm_start MOVE R15, @R13++\n_main {}\n ADD @--R13, 2, R15\n MOVE R15, {}\n {}\n" \
          " MOVE R15, @R13++\n"


# Cases that must trap rather than return, and the first NICE instruction
# of the code for the wasm instruction that traps, which R2 points at.
# The operands of these instructions are constants, which take no
# registers until they must (README.md). {R2} stands for R2's value: code
# that only traps starts with MOVE R2 of its own address. A label of the
# program, such as ___wasm_memory, has its value in the program.
TRAPS = {"growtrap": "MOVE R1, 65536",
         "trunc_big": "MOVE R1, 0x4F000000",
         "trunc_small": "MOVE R2, 0x41E00000",
         "trunc_neg": "MOVE R2, 0x41F00000",
         "trunc_nan": "MOVE R1, 0x5F000000",
         "libtrap": "MOVE R1, 100",
         "safetrap": "MOVE R2, {R2}",
         "rusttrap": "MOVE R2, {R2}",
         "indirectoob": "SUB[M] R0, 4, 4",
         "indirectnull": "SUB[M] R0, 0, 4",
         "indirecttype": "SUB[M] R0, 1, 4",
         "filloob": "ADD[M] R1, 65533, 4",
         "copyoob": "ADD[M] R1, 0, 2",
         "divzero": "MOVE[M] R0, 0",
         "divzero64": "OR[M] R0, 0, 0",
         "overflow": "MOVE[M] R0, -1",
         "overflow64": "OR[M] R0, -1, -1",
         "unreachable": "MOVE R2, {R2}",
         "oob": "ADD[M] R1, 65532, 1",
         "oobcarry": "ADD[M] R1, -1, 1",
         "oobdyn": "SUB[M] R0, R1, 65532",
         "oobend": "ROR R1, R1, 2",
         "oobword": "ROR R1, R1, 2",
         "oobwordwrap": "ROR R1, R1, 2",
         "sharetrap3": "MOVE @___wasm_memory+3[R8], R1",
         "sharetrap3_grow": "ADD[M] R1, R8, 3",
         "sharetrap2": "MOVE R1, @___wasm_memory+2[R8]",
         "sharetrap2_grow": "ADD[M] R1, R8, 2",
         "sharetrap": "MOVE @___wasm_memory+3[R7], R1",
         "addrformtrap": "SUB[M] R0, R1, 16384",
         "oobbyte": "SHR R2, R3, 2",
         "oobhalf": "SHR R3, R2, 2",
         "oobbytecarry": "ADD R1, R2, 1",
         "oobword8": "ROR R2, R1, 2",
         "growdyntrap": "ROR R2, R1, 2",
         "nomemory": "MOVE R2, {R2}",
         "dispatchtrap": "SHR R5, R6, 2",
         "hoisttrap": "ROR R1, R5, 2",
         "hoistgrouptrap": "MOVE R1, @___wasm_memory+1[R9]",
         "hoiststoretrap": "ROR R1, R8, 2",
         "foldtrap": "SUB[M] R0, R1, 1",
         "foldtrap8": "SUB[M] R0, R2, 16383",
         "foldsharetrap": "MOVE @___wasm_memory+2121[R8], R1",
         "libfoldtrap": "SUB[M] R0, R1, 8",
         "foldteetrap": "MOVE @___wasm_memory+2121[R8], R1",
         "boundtrap": "SUB[M] R0, R1, 256",
         "divzero_dyn": "MOVE[M] R0, R2",
         "divzero64_dyn": "OR[M] R0, R3, R4",
         "overflow_dyn": "MOVE[M] R0, R2",
         "overflow64_dyn": "OR[M] R0, R3, R4",
         "trunc_u64_big": "MOVE R1, 0x5F800000",
         "trunc_u64_neg": "MOVE R2, 0x43F00000",
         "trunc_u32_neg": "MOVE R1, 0x4F800000",
         "trunc_s64_big": "MOVE R2, 0x43E00000",
         "fillzerooob": "ADD[M] R1, 65537, 0",
         "copyzerooob": "ADD[M] R1, 0, 0",
         "copydestzerooob": "ADD[M] R1, 65537, 0",
         "fillwrap": "ADD[M] R1, 16, -16",
         "bigoffbyte": "MOVE R2, {R2}",
         "bigoffword": "MOVE R2, {R2}",
         "elemnull": "SUB[M] R0, 2, 6",
         "elemneg": "SUB[M] R0, -1, 6",
         "growzerotrap": "SHR R2, R3, 2",
         "growzerotrap8": "ROR R2, R1, 2"}

# Cases whose translation, without its comment lines, must match a
# pattern, or must not: name -> (pattern, whether it must match). A word access that needs no compare
# has no SUB[M] (bound_case).
SHAPES = {"bound": (r"SUB\[M\]", False),
          "bound_over": (r"SUB\[M\] +R0, R\d+, 255$", True),
          "bound_load8": (r"SUB\[M\]", False),
          "bound_remu": (r"SUB\[M\]", False),
          "boundtrap": (r"SUB\[M\] +R0, R\d+, 256$", True),
          "bound64": (r"SUB\[M\]", False),
          "bound64_over": (r"SUB\[M\] +R0, R\d+, 510$", True),
          "bound_grow": (r"SUB\[M\] +R0, R\d+, @W.wlimit4$", True),
          "bound_unchecked": (r"0x3FFFFFFF|^ +ADD", False),
          "hoistagen": (r"^ +AND +(R\d+), R\d+, 255\n +ADD +R\d+, R\d+, 7\n"
                        r"(W\.f0\.L\d+\n)? +MOVE +R\d+, @___wasm_memory\+64\[\1\]$", True),
          "byte_bound": (r"SUB\[M\]", False),
          "byte_bound_over": (r"SUB\[M\] +R0, R\d+, 65536$", True),
          "half_bound": (r"SUB\[M\] +R0, R\d+, 65535$", False),
          "half_bound_over": (r"SUB\[M\] +R0, R\d+, 65535$", True),
          # A byte load: the word index and the rotation count come before
          # the compare, and fill_jump_slots moves neither to after the jump.
          "oobbyte": (r"^ +SHR +(R\d+), (R\d+), 2\n +SHL +(R\d+), \2, 3\n"
                      r" +SUB\[M\] +R0, \2, 65536\n +\?!C MOVE +R15, \S+\n"
                      r" +ROR +R\d+, @___wasm_memory\[\1\], \3$", True),
          # A byte store: the mask comes from a rotation, not a table.
          "oobbytecarry": (r"^ +ROL +(R\d+), -256, R\d+\n +AND +R\d+, \1, @___wasm_memory", True)}

# Options for nicewasm.
OPTIONS = {"unchecked": ["--no-bounds-checks"],
           "grow": ["--memory-pages", "3"],
           "growtrap": ["--memory-pages", "2"],
           "growdyn": ["--memory-pages", "2"],
           "growdyntrap": ["--memory-pages", "2"],
           "sharetrap2_grow": ["--memory-pages", "2"],
           "sharetrap3_grow": ["--memory-pages", "2"],
           "share_unchecked": ["--no-bounds-checks"],
           "memend_unchecked": ["--no-bounds-checks"],
           "narrow_unchecked": ["--no-bounds-checks"],
           "addrform_unchecked": ["--no-bounds-checks"],
           "addrform_grow": ["--memory-pages", "2"],
           "foldform_unchecked": ["--no-bounds-checks"],
           "foldform_grow": ["--memory-pages", "2"],
           "bound_grow": ["--memory-pages", "2"],
           "bound_unchecked": ["--no-bounds-checks"],
           "libfold": ["--library", "lib", "--library-memory", "64"],
           "libfoldtrap": ["--library", "lib", "--library-memory", "64"],
           "narrow_grow": ["--memory-pages", "2"],
           "memend_grow": ["--memory-pages", "2"],
           "library": ["--library", "lib"],
           "libtrap": ["--library", "lib"],
           "libmem": ["--library", "lib", "--library-memory", "128"],
           "bigoff_unchecked": ["--no-bounds-checks"],
           "growneg": ["--memory-pages", "2"],
           "bulk_unchecked": ["--no-bounds-checks"],
           "grow_unchecked": ["--no-bounds-checks", "--memory-pages", "3"],
           "library_unchecked": ["--library", "lib", "--no-bounds-checks"],
           "growzero": ["--memory-pages", "1"],
           "growzerotrap": ["--memory-pages", "1"],
           "growzerotrap8": ["--memory-pages", "1"]}

# What a case must print on the console (SYSTEM.md §1). Every other case
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


def memend_checks() -> List[bytes]:
    """Accesses of 4 and 8 bytes at the end of a memory of one page, at
    addresses in local 1. Words 16382 and 16383, the last two, get the
    bytes 55 66 77 88 | 11 22 33 44 at 65528 to 65535. Each check is one
    bit, and the last one fails."""
    return [
        st_dyn(I32_STORE, 65532, 0x44332211) + ld_dyn(I32_LOAD, 65532, 0x44332211),
        st_dyn(I32_STORE, 65528, 0x88776655 - 2**32) + ld_dyn(I64_LOAD, 65528, 0x44332211_88776655),
        ld_dyn(I32_LOAD, 65531, 0x33221188),                 # bytes 3 of 4 and 0 to 2
        ld_dyn(I32_LOAD, 65530, 0x22118877),
        ld_dyn(I32_LOAD, 65529, 0x11887766),
        ld_dyn(I32_LOAD, 65528, 0x44332211, offset=4),       # the last word
        ld_dyn(I32_LOAD, 65527, 0x33221188, offset=4),       # byte 65531
        # AA BB CC DD in bytes 65531 to 65534. Byte 65535 keeps its 44.
        st_dyn(I32_STORE, 65531, 0xDDCCBBAA - 2**32) + ld_dyn(I32_LOAD, 65532, 0x44DDCCBB),
        # Byte 65527 is 0.
        ld_dyn(I64_LOAD, 65527, 0xDDCCBBAA_77665500 - 2**64),
        ld_dyn(I32_LOAD, 65532, 0)]


def narrow_checks() -> List[bytes]:
    """Accesses of 1 and 2 bytes at addresses in local 1, at the ends of a
    memory of one page and with offsets. The last word gets the bytes 81
    F2 83 84 at 65532 to 65535. Each check is one bit, and the last one
    fails."""
    return [
        st_dyn(I32_STORE, 65532, 0x8483F281 - 2**32) + ld_dyn(I32_LOAD8_U, 65535, 0x84),
        ld_dyn(I32_LOAD8_S, 65535, 0x84 - 0x100),
        ld_dyn(I32_LOAD16_U, 65534, 0x8483),                 # the last 2 bytes
        ld_dyn(I32_LOAD16_S, 65533, 0x83F2 - 0x10000),
        ld_dyn(I32_LOAD8_U, 65531, 0x84, offset=4),
        ld_dyn(I32_LOAD8_U, 65532, 0xF2, offset=1),
        ld_dyn(I32_LOAD16_U, 65531, 0xF281, offset=1),
        ld_dyn(I32_LOAD8_S, 65528, 0x81 - 0x100, offset=4),
        # Byte 0, then FF in the last byte.
        st_dyn(I32_STORE8, 0, 0x1FE) + ld_dyn(I32_LOAD, 0, 0xFE),
        ld_dyn(I32_LOAD8_S, 0, -2),
        st_dyn(I32_STORE8, 65535, 0x7F) + ld_dyn(I32_LOAD, 65532, 0x7F83F281),
        # AA BB in bytes 7 and 8, which straddle two words.
        st_dyn(I32_STORE16, 3, 0xBBAA, offset=4) + ld_dyn(I32_LOAD, 4, 0xAA000000 - 2**32),
        ld_dyn(I32_LOAD, 8, 0xBB),
        ld_dyn(I32_LOAD16_S, 3, 0xBBAA - 0x10000, offset=4),
        ld_dyn(I32_LOAD16_U, 7, 0xBBAA),
        ld_dyn(I64_LOAD16_S, 7, 0xBBAA - 0x10000),
        ld_dyn(I64_LOAD8_U, 7, 0xAA),
        # Values that are not constants: 15 + 0x2200 = 0x220F at 15, 0F
        # 22 across two words, and the low byte of 18 + 0x300 at 18.
        st_self(I32_STORE16, 15, 0x2200) + ld_dyn(I32_LOAD, 12, 0x0F000000),
        ld_dyn(I32_LOAD, 16, 0x22),
        st_self(I32_STORE8, 18, 0x300) + ld_dyn(I32_LOAD, 16, 0x120022),
        st_self(I32_STORE16, 21, 0x7700) + ld_dyn(I32_LOAD, 20, 0x771500),
        # A byte 0, the low byte of 0x100, at 22, then at the constant 21.
        st_dyn(I32_STORE8, 22, 0x100) + ld_dyn(I32_LOAD, 20, 0x1500),
        st(I32_STORE8, 21, 0) + ld_dyn(I32_LOAD, 20, 0),
        ld_dyn(I32_LOAD8_U, 0, 0)]


def idx(i: int, sh: int, c: Optional[int], want: int, op: int = I32_LOAD,
        offset: int = 0) -> bytes:
    """A check that the load op at (i << sh) + c, plus offset, gives want,
    with i in local 1. Without c, the address is i << sh. Local 1 is i - 0,
    so that nicewasm does not know a bound on it, and the access keeps its
    compare."""
    i64 = op == I64_LOAD
    return (i32_const(i) + i32_const(0) + SUB + local_set(1) + local_get(1) + i32_const(sh) + SHL
            + (b"" if c is None else i32_const(c) + ADD) + mem(op, offset)
            + (i64_const(want) + EQ64 if i64 else i32_const(want) + EQ))


def addrform_checks() -> List[bytes]:
    """Loads and stores at addresses computed as i << 2 or i << 3, plus a
    constant, as clang computes those of array elements. The word at byte
    4k is 0x100 + k for k = 0 to 8. Each check is one bit, and the last
    one fails."""
    return [
        b"".join(st(I32_STORE, 4 * k, 0x100 + k) for k in range(9)) + idx(2, 2, 8, 0x104),
        idx(0x40000005, 2, 8, 0x107),                  # 0x1_00000014 + 8 wraps to 28
        idx(-1, 2, 4, 0x100),                          # -4 + 4 wraps to 0
        idx(3, 2, None, 0x103),
        idx(1, 3, 8, 0x105_00000104, I64_LOAD),
        idx(0x20000001, 3, None, 0x103_00000102, I64_LOAD),   # wraps to 8
        idx(1, 2, 4, 0x104, offset=8),
        idx(1, 2, 2, 0x01020000),                      # bytes 6 to 9: 00 00 02 01
        # A store at (2 << 2) + 4 = 12.
        i32_const(2) + local_set(1) + local_get(1) + i32_const(2) + SHL + i32_const(4) + ADD
        + i32_const(0x777) + mem(I32_STORE) + ld(I32_LOAD, 12, 0x777),
        # The address (5 << 2) + 8 = 28 is also a value, in local 2.
        i32_const(5) + local_set(1) + local_get(1) + i32_const(2) + SHL + i32_const(8) + ADD
        + local_tee(2) + mem(I32_LOAD) + i32_const(0x107) + EQ
        + local_get(2) + i32_const(28) + EQ + AND,
        # Local 1 changes from 2 to 3 between the shift and the add, so the
        # address is (2 << 2) + 8 = 16, not (3 << 2) + 8.
        i32_const(2) + local_set(1) + local_get(1) + i32_const(2) + SHL + i32_const(3)
        + local_set(1) + i32_const(8) + ADD + mem(I32_LOAD) + i32_const(0x104) + EQ,
        # Local 1 changes from 8 to 12 between two loads from it. The word
        # at 12 is 0x777 now, so the sum is 0x102 + 0x777.
        i32_const(8) + local_set(1) + local_get(1) + mem(I32_LOAD) + i32_const(12)
        + local_set(1) + local_get(1) + mem(I32_LOAD) + ADD + i32_const(0x879) + EQ,
        # ((1 << 3) + 8) + 4 = 20.
        i32_const(1) + local_set(1) + local_get(1) + i32_const(3) + SHL + i32_const(8) + ADD
        + i32_const(4) + ADD + mem(I32_LOAD) + i32_const(0x105) + EQ,
        idx(0, 2, None, 1)]


def fold_checks() -> List[bytes]:
    """Word accesses at (i << s) + c with a constant c of up to 65536,
    which nicewasm folds into the word operand (README.md), unless c / 4
    is at or past the limit of the compare. Each check is one bit, and the
    last one fails."""
    return [
        st(I32_STORE, 8516, 0x1234) + st(I64_STORE, 65528, 0x01020304_05060708)
        + st(I32_STORE, 20, 0x105)
        + idx(5, 2, 8476, 0x1234, offset=20),          # 20 + 8476 + 20 = 8516
        idx(-1, 2, 8520, 0x1234),                      # -4 + 8520 = 8516, in the stub
        idx(0x40000001, 2, 8508, 0x1234, offset=4),    # 4 + 8508 + 4, in the stub
        idx(-16379, 2, 65536, 0x105),                  # -65516 + 65536 = 20, c / 4 = 16384
        idx(0, 2, 65532, 0x01020304),                  # the last word: c / 4 = 16383
        idx(8190, 3, 8, 0x01020304_05060708, I64_LOAD),   # 65520 + 8, the last two words
        idx(0, 2, 65528, 0x01020304_05060708, I64_LOAD),  # c / 4 = 16382, the limit - 1
        idx(-2, 2, 65536, 0x01020304_05060708, I64_LOAD),  # c / 4 = 16384: not folded
        idx(5, 2, 8476, 0x1235, offset=20)]


def fold_loop(i0: int, end: int) -> bytes:
    """The module of the fold cases. main calls setup, then, for i from i0
    up to end - 1, signed, loads x from a = (i << 2) + 8480, adds x to s,
    stores s at 0, and stores x + 1 at a + 4. The two accesses share one
    compare of i, with 8480 / 4 = 2120 in their word operands (README.md).
    main returns s XOR the word at (end << 2) + 8480, shifted left by 8.
    The word at 8468 is 0x10."""
    a = local_get(0) + i32_const(2) + SHL + i32_const(8480) + ADD
    return module(
        types(MAIN_TYPE, ([], [])),
        imports(("env", "setup", 1)),
        funcs(0),
        memory(1),
        exports(("main", 0, 1)),
        code((3, call(0) + i32_const(i0) + local_set(0) + loop()
              + a + mem(I32_LOAD) + local_tee(1)
              + local_get(2) + ADD + local_set(2)
              + i32_const(0) + local_get(2) + mem(I32_STORE)
              + a + local_get(1) + i32_const(1) + ADD + mem(I32_STORE, 4)
              + local_get(0) + i32_const(1) + ADD + local_tee(0) + i32_const(end) + LT_S
              + br_if(0) + END
              + local_get(2) + i32_const(end << 2) + mem(I32_LOAD, 8480) + i32_const(8) + SHL
              + XOR)),
        data((8468, bytes([0x10, 0, 0, 0]))))


def fold_tee(i: int) -> bytes:
    """The module of the foldtee cases: main sets local 0 to i, from a
    global, so that nicewasm does not know a bound on it, then to a
    = (i << 2) + 8480 with local.tee, loads x from a, stores x + 1 at a +
    4, and returns the word at a + 4 plus a. The add writes the local
    that holds i, so a copy of i keeps it for the accesses (README.md).
    The word at 8492 is 0x20."""
    return module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        globals_(i),
        exports(("main", 0, 0)),
        code((2, global_get(0) + local_set(0)
              + local_get(0) + i32_const(2) + SHL + i32_const(8480) + ADD + local_tee(0)
              + mem(I32_LOAD) + local_set(1)
              + local_get(0) + local_get(1) + i32_const(1) + ADD + mem(I32_STORE, 4)
              + local_get(0) + mem(I32_LOAD, 4) + local_get(0) + ADD)),
        data((8492, bytes([0x20, 0, 0, 0]))))


def bound_case(index: bytes, c: int, at: int, value: int, i64: bool = False) -> bytes:
    """The module of the bound cases: main stores value at the constant
    address at, then loads from (i << s) + c, with s = 3 for an i64 and 2
    else, and i what the code index leaves, and returns the loaded i32, or
    the low word XOR the high word of the i64. The code may use the i32
    locals 0 and 1. nicewasm knows a bound on i from the code, and if
    every address it allows is in the memory, the load has no compare
    (README.md)."""
    if i64:
        load = (index + i32_const(3) + SHL + i32_const(c) + ADD + mem(I64_LOAD) + local_tee(2)
                + WRAP + local_get(2) + i64_const(32) + SHR_U64 + WRAP + XOR)
    else:
        load = index + i32_const(2) + SHL + i32_const(c) + ADD + mem(I32_LOAD)
    return module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code(([I32, I32, I64], st(I64_STORE if i64 else I32_STORE, at, value) + load)))


def byte_bound(op: int, c: int, value: int) -> bytes:
    """The module of the byte bound cases: main stores value at x + c with
    the store of op's size, x = 0x1234 & 0xFFF = 0x234, and loads it back
    with op from (0x1234 & 0xFFF) + c. All that nicewasm knows of the load's
    address is that it is at most 0xFFF + c."""
    store = I32_STORE8 if op == I32_LOAD8_U else I32_STORE16
    return module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, st(store, 0x234 + c, value) + i32_const(0x1234) + local_set(0)
              + local_get(0) + i32_const(0xFFF) + AND + i32_const(c) + ADD + mem(op))))


# x & 255 with x = 0x1234 in local 0: i = 0x34 = 52, but all nicewasm
# knows is i <= 255.
AND255 = i32_const(0x1234) + local_set(0) + local_get(0) + i32_const(255) + AND


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


def c32(x: int) -> bytes:
    """i32.const of x, taken modulo 2^32."""
    x &= 0xFFFFFFFF
    return i32_const(x - 2**32 if x >= 2**31 else x)


def c64(x: int) -> bytes:
    """i64.const of x, taken modulo 2^64."""
    x &= 2**64 - 1
    return i64_const(x - 2**64 if x >= 2**63 else x)


def dyn32(a: int, op: bytes, b: int, want: int) -> bytes:
    """op32, with a and b in the i32 locals 1 and 2, so that neither is a
    constant (DYN_LOCALS)."""
    return (c32(a) + local_set(1) + c32(b) + local_set(2) + local_get(1) + local_get(2) + op
            + c32(want) + EQ)


def dyn64(a: int, op: bytes, b: int, want: int) -> bytes:
    """op64, with a and b in the i64 locals 3 and 4."""
    return (c64(a) + local_set(3) + c64(b) + local_set(4) + local_get(3) + local_get(4) + op
            + c64(want) + EQ64)


# The locals of the cases that use dyn32 and dyn64: local 0 for bits().
DYN_LOCALS = [I32, I32, I32, I64, I64]


def main_of(body: bytes, mem: bool = False) -> bytes:
    """A module whose main has the locals DYN_LOCALS and the given body,
    with a memory of one page if mem."""
    return module(types(MAIN_TYPE), funcs(0), *([memory(1)] if mem else []),
                  exports(("main", 0, 0)), code((DYN_LOCALS, body)))


def div_trap(t: int, a: int, op: bytes, b: int) -> bytes:
    """A module whose main calls f(a, b) = a op b, so that the operands are
    f's parameters, in R1 and R2, or R1-R2 and R3-R4 for an i64."""
    k = c32 if t == I32 else c64
    return module(types(MAIN_TYPE, ([t, t], [t])), funcs(1, 0), exports(("main", 0, 1)),
                  code((0, local_get(0) + local_get(1) + op),
                       (0, k(a) + k(b) + call(0) + (WRAP if t == I64 else b""))))


def trunc_trap(code_: bytes) -> bytes:
    """A module whose main is code_, a conversion that traps."""
    return module(types(MAIN_TYPE), funcs(0), exports(("main", 0, 0)), code((0, code_)))


DIV_S, DIV_U, REM_S, REM_U = b"\x6d", b"\x6e", b"\x6f", b"\x70"
DIV_S64, DIV_U64, REM_S64, REM_U64 = b"\x7f", b"\x80", b"\x81", b"\x82"


# Element segments of every active and declarative form, for elem_case.
# Functions 1 and 2 are inc(x) = x + 1 and dbl(x) = 2x. Flags 2 names
# table 0 and puts inc at entry 0. Flags 6 names the table too, and its
# elements are expressions: dbl at 1, and a ref.null at 2. Flags 3 and 7
# are declarative, and change nothing. Flags 4 puts a ref.null at 3.
# Flags 0 puts dbl at 4, and the next segment inc over it. Entry 5 is
# not set. So the table is inc, dbl, null, null, inc, null.
ELEM_FORMS = [
    b"\x02" + u(0) + i32_const(0) + END + b"\x00" + vec([u(1)]),
    b"\x06" + u(0) + i32_const(1) + END + b"\x70" + vec([b"\xd2" + u(2) + END, b"\xd0\x70" + END]),
    b"\x03" + b"\x00" + vec([u(2)]),
    b"\x07" + b"\x70" + vec([b"\xd2" + u(2) + END]),
    b"\x04" + i32_const(3) + END + vec([b"\xd0\x70" + END]),
    b"\x00" + i32_const(4) + END + vec([u(2)]),
    b"\x00" + i32_const(4) + END + vec([u(1)]),
]


def elem_case(body: bytes) -> bytes:
    """A module with the table of ELEM_FORMS, whose main is body with one
    i32 local, and a data segment with the flags 2 and memory 0, which
    puts 42 at byte 0."""
    return module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(0, 1, 1),
        table(6),
        memory(1),
        exports(("main", 0, 0)),
        section(9, vec(ELEM_FORMS)),
        code((1, body), (0, local_get(0) + i32_const(1) + ADD),
             (0, local_get(0) + local_get(0) + ADD)),
        section(11, vec([b"\x02" + u(0) + i32_const(0) + END + vec([b"\x2a"])])))


# f(a, b, c, d, e, g, h, i, j, k) of manyparams: a, c, g, i, and k are
# i32, b, d, and h i64, e f64, and j f32.
MANY_TYPE: Tuple[List[int], List[int]] = ([I32, I64, I32, I64, F64, I32, I64, I32, F32, I32], [I64])


def op64_dyn(a: int, op: bytes, b: int, want: int) -> bytes:
    """op64, with the count in the i64 local 1, so that it is not a
    constant."""
    def c(x: int) -> bytes:
        return i64_const(x - 2**64 if x >= 2**63 else x)
    return c(a) + c(b) + local_tee(1) + op + c(want) + EQ64


def mul64_by(x: int, c: int, want: int, how: int) -> bytes:
    """A check that the i64 x, in local 1, times the constant c gives want.
    how 0 multiplies x by c, how 1 c by x, and how 2 writes x * c back to
    local 1, so the result goes to the registers of x."""
    def k(v: int) -> bytes:
        return i64_const(v - 2**64 if v >= 2**63 else v)
    out = k(x) + local_set(1)
    if how == 1:
        out += k(c) + local_get(1) + b"\x7e"
    else:
        out += local_get(1) + k(c) + b"\x7e"
    if how == 2:
        out += local_set(1) + local_get(1)
    return out + k(want) + EQ64


# setup() installs a trap handler that adds word {0} of the memory to
# the trap code in R1, and then traps as before, so that a case shows
# that a store before the trap was done.
SHARE_ASM = ("_setup MOVE @___wasm_trap_vector, _handler\n MOVE R15, @R13++\n"
             "_handler ADD R1, R1, @___wasm_memory+{0}\n MOVE R15, ___wasm_trap\n")


def share_trap(p: int, step: int) -> bytes:
    """The module of the sharetrap cases. main calls setup, then, from p
    on in steps, stores 7 at p, loads x from p + 8, and stores x + 1 at
    p + 12, until an access traps. The three accesses share one compare
    (README.md). With step 0, there is no loop, and they run once."""
    accesses = (local_get(0) + i32_const(7) + mem(I32_STORE)
                + local_get(0) + mem(I32_LOAD, 8) + local_set(1)
                + local_get(0) + local_get(1) + i32_const(1) + ADD + mem(I32_STORE, 12))
    if step:
        accesses = (loop() + accesses + local_get(0) + i32_const(step) + ADD + local_set(0)
                    + br(0) + END)
    return module(
        types(MAIN_TYPE, ([], [])),
        imports(("env", "setup", 1)),
        funcs(0),
        memory(1),
        exports(("main", 0, 1)),
        code((2, call(0) + i32_const(p) + local_set(0) + accesses + i32_const(0))))


def hoist_slot(p: int, end: int) -> bytes:
    """The module of the hoist cases. main calls setup, then, from p on
    in steps of 1, until p = end, loads x from p and adds 7 to k, adds x
    to s, and stores s at 0. It returns s XOR k. The data at p are the
    bytes 1 to 8. The ADD of k moves to between the compare of the load
    and the load (README.md), and its stub gets a copy."""
    return module(
        types(MAIN_TYPE, ([], [])),
        imports(("env", "setup", 1)),
        funcs(0),
        memory(1),
        exports(("main", 0, 1)),
        code((4, call(0) + i32_const(p) + local_set(0) + loop()
              + local_get(0) + mem(I32_LOAD)
              + local_get(1) + i32_const(7) + ADD + local_set(1)
              + local_get(2) + ADD + local_set(2)
              + i32_const(0) + local_get(2) + mem(I32_STORE)
              + local_get(0) + i32_const(1) + ADD + local_tee(0) + i32_const(end) + LT_U
              + br_if(0) + END
              + local_get(2) + local_get(1) + XOR)),
        data((p, bytes(range(1, 9)))))


def hoist_group(p: int, end: int) -> bytes:
    """The module of the hoistgroup cases: as hoist_slot, but each round
    also loads y from p + 4, and adds x + y to s. The two loads share a
    compare (README.md), and the ADD of k moves to between it and the
    first load. Their stub goes on in a copy of the code, which has its
    own ADD of k. The data at p are the bytes 1 to 12."""
    return module(
        types(MAIN_TYPE, ([], [])),
        imports(("env", "setup", 1)),
        funcs(0),
        memory(1),
        exports(("main", 0, 1)),
        code((4, call(0) + i32_const(p) + local_set(0) + loop()
              + local_get(0) + mem(I32_LOAD)
              + local_get(1) + i32_const(7) + ADD + local_set(1)
              + local_get(0) + mem(I32_LOAD, 4) + ADD
              + local_get(2) + ADD + local_set(2)
              + i32_const(0) + local_get(2) + mem(I32_STORE)
              + local_get(0) + i32_const(1) + ADD + local_tee(0) + i32_const(end) + LT_U
              + br_if(0) + END
              + local_get(2) + local_get(1) + XOR)),
        data((p, bytes(range(1, 13)))))


def hoist_store(q: int) -> bytes:
    """The module of the hoiststore cases. main calls setup, then copies
    three words, from 17, 21, and 25 to q, q + 4, and q + 8, and returns
    the sum of the words at 32, 36, and 40. The data at 16 are the bytes
    1 to 16. The ROR that starts each store moves, with the store's
    start, to between the compare of the load and the load (README.md),
    and the load's stub gets a copy of it."""
    return module(
        types(MAIN_TYPE, ([], [])),
        imports(("env", "setup", 1)),
        funcs(0),
        memory(1),
        exports(("main", 0, 1)),
        code((3, call(0) + i32_const(17) + local_set(0) + i32_const(q) + local_set(1) + loop()
              + local_get(1) + local_get(0) + mem(I32_LOAD) + mem(I32_STORE)
              + local_get(0) + i32_const(4) + ADD + local_set(0)
              + local_get(1) + i32_const(4) + ADD + local_set(1)
              + local_get(2) + i32_const(1) + ADD + local_tee(2) + i32_const(3) + LT_U
              + br_if(0) + END
              + i32_const(32) + mem(I32_LOAD) + i32_const(36) + mem(I32_LOAD) + ADD
              + i32_const(40) + mem(I32_LOAD) + ADD)),
        data((16, bytes(range(1, 17)))))


# The module of the hoistagen case. For i from 0 to 3, main loads x from
# word 64 + (i & 255) of the memory, which needs no compare, adds 7 to k,
# and adds x to s. It returns s XOR k = (1 + 2 + 3 + 4) XOR 28 = 0x16.
# The ADD of k moves to between the AND that computes the load's word
# index and the load (README.md).
HOIST_AGEN = module(
    types(MAIN_TYPE),
    funcs(0),
    memory(1),
    exports(("main", 0, 0)),
    code((3, loop()
          + local_get(0) + i32_const(255) + AND + i32_const(2) + SHL + i32_const(256) + ADD
          + mem(I32_LOAD)
          + local_get(1) + i32_const(7) + ADD + local_set(1)
          + local_get(2) + ADD + local_set(2)
          + local_get(0) + i32_const(1) + ADD + local_tee(0) + i32_const(4) + LT_U
          + br_if(0) + END
          + local_get(2) + local_get(1) + XOR)),
    data((256, bytes([1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0]))))


# The module of the share cases. In a loop that runs once, it stores at
# base 1, loads from base 1 + 4, and stores at base 1 + 8. These share one
# compare (README.md), which fails, since 1 is not a multiple of 4. Then
# main returns the loaded value XOR the words at 0, 4, 8, and 12.
SHARE_UNALIGNED = module(
    types(MAIN_TYPE),
    funcs(0),
    memory(1),
    exports(("main", 0, 0)),
    code((2, i32_const(5) + i32_const(0x0D0C0B0A) + mem(I32_STORE)
          + i32_const(1) + local_set(0) + loop()
          + local_get(0) + i32_const(0x44332211) + mem(I32_STORE)
          + local_get(0) + mem(I32_LOAD, 4) + local_set(1)
          + local_get(0) + i32_const(-0x778899AB) + mem(I32_STORE, 8) + END
          + local_get(1)
          + i32_const(0) + mem(I32_LOAD) + XOR + i32_const(4) + mem(I32_LOAD) + XOR
          + i32_const(8) + mem(I32_LOAD) + XOR + i32_const(12) + mem(I32_LOAD) + XOR)))


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
    # The sieve of Eratosthenes from clang, with get(i) = i + 100. There are
    # 168 primes up to get(900) = 1000.
    ("primes_c", "primes", "_get ADD R1, R1, 100\n MOVE R15, @R13++\n", 168),
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
    # Declared locals start at 0. dirty sets its 3 locals to 0x55, which
    # may leave it in the registers that clean gets, so without zeroing it
    # could return 0x55 * 3 + 7.
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
    # More values live across calls than there are registers that calls
    # preserve, so some are spilled to frame words. Local k is 1 << k.
    # inc(5) = 6, inc(7) through the table = 8, and g(locals 14 to 19) =
    # 2^14 - 2^15 + 2^16 - 2^17 + 2^18 - 2^19 = -344064, with the last two
    # arguments on the stack. Then each of the 20 locals that still has its
    # value adds 1: 6 + 8 - 344064 + 20 = -344030 = 0xFFFAC022.
    ("spills", module(
        types(MAIN_TYPE, ([I32], [I32]), ([I32] * 6, [I32])),
        funcs(1, 2, 0),
        table(1),
        exports(("main", 0, 2)),
        elems((0, [0])),
        code((0, local_get(0) + i32_const(1) + ADD),
             (0, local_get(0) + local_get(1) + SUB + local_get(2) + ADD + local_get(3) + SUB
              + local_get(4) + ADD + local_get(5) + SUB),
             (20, b"".join(i32_const(1 << k) + local_set(k) for k in range(20))
              + i32_const(5) + call(0) + i32_const(7) + i32_const(0) + call_indirect(1) + ADD
              + b"".join(local_get(k) for k in range(14, 20)) + call(1) + ADD
              + b"".join(local_get(k) + i32_const(1 << k) + EQ + ADD for k in range(20))))),
     "", 0xFFFAC022),
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
    # Each comparison with 0 of x in local 1, which tests x with MOVE[M]
    # for eq to ge_u, but not for gt and le, whose operands are swapped:
    # -5: 0110011001.
    # 0:  1000001111.
    # 7:  0100110011.
    # 01 1001 1001 1000 0011 1101 0011 0011 = 0x19983D33.
    ("cmpzero", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((2, bits(0, *[(i32_const(x) + local_set(1) if op == EQ else b"")
                           + local_get(1) + i32_const(0) + op
                           for x in (-5, 0, 7)
                           for op in [EQ, NE, LT_S, LT_U, GT_S, GT_U, LE_S, LE_U, GE_S,
                                      GE_U]])))), "", 0x19983D33),
    # The same for i64 eq and ne, with 0 on either side, which take the
    # other words as they are: x == 0, x != 0, 0 == x, and 0 != x, for x =
    # 0, 0x1_00000000, and 5: 1010 0101 0101 = 0xA55.
    ("cmpzero64", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code(([I32, I64], bits(0, *[
            (i64_const(x) + local_set(1) if k == 0 else b"")
            + (local_get(1) + i64_const(0) if k < 2 else i64_const(0) + local_get(1))
            + (EQ64 if k % 2 == 0 else NE64)
            for x in (0, 0x1_00000000, 5) for k in range(4)])))), "", 0xA55),
    # The same comparisons, each taken by if, by br_if, and by eqz and
    # br_if. nicewasm then jumps on the flags, and writes no 0 or 1.
    *[(f"cmp{bits_}_{how.__name__}", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((2, bits(0, *[how(c) for c in cmp_all(t, pairs)])))), "", want)
      for bits_, t, pairs, want in
      [("", I32, [(0x7FFFFFFF, -0x80000000), (-0x80000000, 1), (5, 5)], 0x5999983E),
       ("64", I64, [(2**63 - 1, -2**63), (0x1_00000000, 0xFFFFFFFF),
                    (0x5_00000007, 0x5_00000007)], 0x5993383E)]
      for how in (as_if, as_br_if, as_eqz_br_if)],
    # An operation whose result goes straight to a local, with the local's
    # old value still on the operand stack below it:
    # x = 5; x - (x = x + 1) = -1.
    # y = 60 by i32.mul, and local.tee y, then + y = 120.
    # z = 7; z - (z = f(z)) = -1, where f(z) = z + 1.
    # w = 3 << 2 by local.tee, then + w = 24.
    # -1 + 120 - 1 + 24 = 142.
    ("forward", module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(0, 1),
        exports(("main", 0, 0)),
        code((4, i32_const(5) + local_set(0)
              + local_get(0) + local_get(0) + i32_const(1) + ADD + local_set(0)
              + local_get(0) + SUB
              + local_get(0) + i32_const(10) + MUL + local_tee(1) + local_get(1) + ADD + ADD
              + i32_const(7) + local_set(2)
              + local_get(2) + local_get(2) + call(1) + local_set(2) + local_get(2) + SUB + ADD
              + i32_const(3) + local_set(3)
              + local_get(3) + i32_const(2) + SHL + local_tee(3) + local_get(3) + ADD + ADD),
             (0, local_get(0) + i32_const(1) + ADD))), "", 142),
    # More locals than registers, one an i64, in a loop that runs 3 times.
    # Local k of 1-6 grows by k each time, to 3k, and local 6 also by g(3)
    # = 1. g uses 6 locals of its own, which must not change main's. The
    # i64 grows by 0x1_00000001 to 0x3_00000003. 3 * 21 + 3 + 3 + 3 = 72.
    ("manylocals", module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(0, 1),
        exports(("main", 0, 0)),
        code(([I32] * 7 + [I64],
              loop()
              + b"".join(local_get(k) + i32_const(k) + ADD + local_set(k) for k in range(1, 7))
              + local_get(7) + i64_const(0x1_00000001) + ADD64 + local_set(7)
              + local_get(6) + i32_const(3) + call(1) + ADD + local_set(6)
              + local_get(0) + i32_const(1) + ADD + local_tee(0) + i32_const(3) + LT_S + br_if(0)
              + END
              + local_get(1) + b"".join(local_get(k) + ADD for k in range(2, 7))
              + local_get(7) + WRAP + ADD
              + local_get(7) + i64_const(32) + SHR_U64 + WRAP + ADD),
             (5, loop()
              + b"".join(local_get(0) + local_set(k) for k in range(1, 6))
              + local_get(0) + i32_const(1) + SUB + local_tee(0) + br_if(0)
              + END + local_get(1)))), "", 72),
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
    # Loops that end in a br_if back to their start, which nicewasm turns
    # into a jump out on the opposite condition and a jump back. The first
    # sums 1 to 10, 55, and leaves local 0 at 10. The second ends in a
    # br_if 1 out of a block, and adds 100 five times. The third is
    # followed by a br 1, so the two jumps swap targets, and the + 1000
    # after it never runs: the br_if 0 before the loop, which could reach
    # it, sees x = 0. x ends at 20, so main returns (555 + 20 + 5) XOR 7,
    # 0x244 XOR 7 = 0x243 = 579. That code is long enough that the br 1
    # stays a jump.
    ("backedge", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((3, loop()
              + local_get(0) + i32_const(1) + ADD + local_tee(0)
              + local_get(1) + ADD + local_set(1)
              + local_get(0) + i32_const(10) + LT_S + br_if(0) + END
              + i32_const(0) + local_set(0)
              + loop() + block()
              + local_get(0) + i32_const(1) + ADD + local_tee(0)
              + local_get(1) + i32_const(100) + ADD + local_set(1)
              + i32_const(5) + LT_S + br_if(1) + END + END
              + block() + block() + local_get(2) + br_if(0) + loop()
              + local_get(2) + i32_const(2) + ADD + local_tee(2)
              + i32_const(20) + LT_S + br_if(0) + END
              + br(1) + END
              + local_get(1) + i32_const(1000) + ADD + local_set(1) + END
              + local_get(1) + local_get(2) + ADD + local_get(0) + ADD
              + i32_const(7) + XOR))), "", 579),
    # A comparison's result in a local, then a call, then an if on the
    # local. The flags said the result before the call, but the call
    # changes them: function 1 compares 7 < 5, which clears C. So the if
    # must test the local, 5 < 7 = 1, and main returns 1.
    ("flagcall", module(
        types(MAIN_TYPE),
        funcs(0, 0),
        exports(("main", 0, 0)),
        code((2, i32_const(5) + local_set(1)
              + local_get(1) + i32_const(7) + LT_U + local_set(0)
              + call(1) + DROP
              + local_get(0) + if_(I32) + i32_const(1) + ELSE + i32_const(0) + END),
             (1, i32_const(7) + local_set(0) + local_get(0) + i32_const(5) + LT_U))), "", 1),
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
    # An interpreter's loop: next = pc + 1, then a br_table on the byte at
    # 16 + pc. Byte 0 adds 1 to acc and byte 1 multiplies it by 3, and
    # both set pc = next. Byte 2 adds 0x10000 to pc. Any other byte
    # returns acc. Each case ends with a br to the loop, which becomes a
    # copy of the code from the loop to the br_table (README.md). In the
    # copies, the ADD of next moves to just before the jump through the
    # table, since neither the trap nor the return uses next. The program
    # 0 0 1 0 1 3 gives ((1 + 1) * 3 + 1) * 3 = 21. In dispatchtrap, the
    # program 0 2 takes pc past the memory, so the load of the next byte,
    # in the copy at the end of case 2, traps. Its R2 points at the load's
    # code in the loop itself, which is the same.
    *[(name, module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((3, loop() + local_get(0) + i32_const(1) + ADD + local_set(2)
              + block() + block() + block() + block()
              + local_get(0) + i32_const(16) + ADD + mem(I32_LOAD8_U) + br_table([0, 1, 2], 3)
              + END + local_get(1) + i32_const(1) + ADD + local_set(1)
              + local_get(2) + local_set(0) + br(3) + END
              + local_get(1) + i32_const(3) + MUL + local_set(1)
              + local_get(2) + local_set(0) + br(2) + END
              + local_get(0) + i32_const(0x10000) + ADD + local_set(0) + br(1) + END
              + local_get(1) + RETURN + END + i32_const(0))),
        data((16, program))), "", want)
      for name, program, want in [("dispatch", bytes([0, 0, 1, 0, 1, 3]), 21),
                                  ("dispatchtrap", bytes([0, 2]), 2)]],
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
    # A select, br_if, if, or eqz on the result of an operation, whose
    # MOVE[M] R0, x the back end removes by giving the operation the M bit
    # (README.md), so that its flags must say whether x is 0. One bit each:
    # 0: -1 + 1 = 0, though the ADD[M] also sets C.
    # 1: 0x7FFFFFFF + 1 = 0x80000000, though it sets N and V.
    # 0: 5 - 5 = 0, by br_if.
    # 0: 0x80000000 << 1 = 0, by if.
    # 1: eqz (6 AND 9) = eqz 0 = 1. The AND's result is not used
    #    otherwise, so it goes to R0.
    # 1: 3 XOR 4 = 7, through local.tee: the XOR sets the flags, not the
    #    copy to the local. Adding the local, 7, and -7 keeps the bit.
    # 1: 1 - 2 = -1, though it borrows.
    # 0100111 = 0x27.
    ("flagops", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((2, bits(0,
                      i32_const(1) + i32_const(0) + i32_const(-1) + i32_const(1) + ADD + SELECT,
                      i32_const(1) + i32_const(0) + i32_const(0x7FFFFFFF) + i32_const(1) + ADD
                      + SELECT,
                      as_br_if(i32_const(5) + i32_const(5) + SUB),
                      as_if(i32_const(-0x80000000) + i32_const(1) + SHL),
                      i32_const(6) + i32_const(9) + AND + EQZ,
                      as_if(i32_const(3) + i32_const(4) + XOR + local_tee(1)) + local_get(1) + ADD
                      + i32_const(-7) + ADD,
                      i32_const(1) + i32_const(0) + i32_const(1) + i32_const(2) + SUB + SELECT)))),
     "", 0x27),
    # The flags still say whether a comparison's result is 0 after the
    # code that writes it, and whether a loaded i32 is 0 after the load,
    # so a select, br_if, or eqz on it uses them (README.md). One bit each:
    # 1: select(1, 0, c), with c = MIN < 1 signed, set by local.tee: MIN -
    #    1 overflows, N = 0 and V = 1, so c = 1.
    # 0: select(0, 1, c), c by local.get, with the flags left as they were.
    # 1: MAX > MIN signed, by select: MIN - MAX = 1 overflows too.
    # 0: select(1, 0, eqz (5 < 7 unsigned)) = select(1, 0, 0).
    # Loads at addresses in local 2, which br_if takes, after a store there:
    # 1: 0x100 at 5, which is not a multiple of 4, so the helpers do both.
    # 0: 0 at 9, the same way.
    # 1: -1 at 12, by the inline path.
    # 0: 0 at 16.
    # 10101010 = 0xAA.
    ("flagvals", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((3, bits(0,
                      i32_const(1) + i32_const(0) + i32_const(-0x80000000) + i32_const(1) + LT_S
                      + local_tee(1) + SELECT,
                      i32_const(0) + i32_const(1) + local_get(1) + SELECT,
                      i32_const(1) + i32_const(0) + i32_const(0x7FFFFFFF) + i32_const(-0x80000000)
                      + GT_S + SELECT,
                      i32_const(1) + i32_const(0) + i32_const(5) + i32_const(7) + LT_U + EQZ
                      + SELECT,
                      *[i32_const(a) + local_tee(2) + i32_const(v) + mem(I32_STORE)
                        + as_br_if(local_get(2) + mem(I32_LOAD))
                        for a, v in [(5, 0x100), (9, 0), (12, -1), (16, 0)]])))),
     "", 0xAA),
    # Multiplications by constants, which become shifts, additions, and
    # subtractions, and divisions by constants, which need no checks. x =
    # 0x12345679 is in local 1, and z = 0x12345678_9ABCDEF0 in local 3,
    # so that they are not constants. One bit each:
    # x * 0 = 0, x * 1 = x, x * 2 = 0x2468ACF2, 3 * x = 0x369D036B,
    # x * 31 = x * 32 - x = 0x468ACF20 - 0x12345679 = 0x345678A7,
    # x * 16777619 = 0x2164207B, x * -1 = 0xEDCBA987,
    # x * -3 = -0x369D036B = 0xC962FC95, x * 0x80000000 = 0x80000000 (x is odd),
    # x * 1000 = 0x1C71C8A8, x * 0x12345678 = 0x30292EB8, by the math unit,
    # x * -8 = -0x91A2B3C8 = 0x6E5D4C38,
    # x * 24 = 0xB4E81B58, by local.set to local 2,
    # x / 16 = 0x01234567 and x % 16 = 9, unsigned,
    # -x / 7 = -43631413 = 0xFD663CCB and -x % -7 = -6, signed,
    # z / 3 = 0x06117228_33944A50, unsigned,
    # and a check that fails, x * 3 = x * 2.
    # 111 1111 1111 1111 1110 = 0x7FFFE.
    ("constops", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code(([I32, I32, I32, I64],
              i32_const(0x12345679) + local_set(1) + i64_const(0x12345678_9ABCDEF0) + local_set(3)
              + bits(0,
                     *[local_get(1) + i32_const(c - 2**32 if c >= 2**31 else c) + MUL
                       + i32_const(want - 2**32 if want >= 2**31 else want) + EQ
                       for c, want in [(0, 0), (1, 0x12345679), (2, 0x2468ACF2)]],
                     i32_const(3) + local_get(1) + MUL + i32_const(0x369D036B) + EQ,
                     *[local_get(1) + i32_const(c - 2**32 if c >= 2**31 else c) + MUL
                       + i32_const(want - 2**32 if want >= 2**31 else want) + EQ
                       for c, want in [(31, 0x345678A7), (16777619, 0x2164207B),
                                       (2**32 - 1, 0xEDCBA987), (2**32 - 3, 0xC962FC95),
                                       (0x80000000, 0x80000000), (1000, 0x1C71C8A8),
                                       (0x12345678, 0x30292EB8), (2**32 - 8, 0x6E5D4C38)]],
                     local_get(1) + i32_const(24) + MUL + local_set(2) + local_get(2)
                     + i32_const(0xB4E81B58 - 2**32) + EQ,
                     local_get(1) + i32_const(16) + b"\x6e" + i32_const(0x01234567) + EQ,
                     local_get(1) + i32_const(16) + b"\x70" + i32_const(9) + EQ,
                     i32_const(0) + local_get(1) + SUB + i32_const(7) + b"\x6d"
                     + i32_const(0xFD663CCB - 2**32) + EQ,
                     i32_const(0) + local_get(1) + SUB + i32_const(-7) + b"\x6f"
                     + i32_const(-6) + EQ,
                     local_get(3) + i64_const(3) + b"\x80" + i64_const(0x06117228_33944A50)
                     + EQ64,
                     local_get(1) + i32_const(3) + MUL + local_get(1) + i32_const(2) + MUL
                     + EQ)))),
     "", 0x7FFFE),
    # An if whose code is short becomes conditional instructions, with no
    # jump over it (README.md). Local 1 is 0 and local 2 is 7, so that the
    # conditions are not constants. One bit each:
    # 1: y = 3, then y = 9 if local 1, leaves y = 3.
    # 1: the same if local 2 sets y = 9.
    # 1: if local 1 then 10 else local 2 + 1 gives 8.
    # 1: if local 2 then 10 else local 2 + 1 gives 10.
    # 1: if local 2, store 77 at byte 64. The word there is then 77.
    # 1: if local 1, store 55 at byte 68. The word there stays 0.
    # 0: a check that fails, 8 = 10.
    # 1111110 = 0x7E.
    ("ifconvert", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((4, i32_const(0) + local_set(1) + i32_const(7) + local_set(2) + bits(0,
            *[i32_const(3) + local_set(3) + local_get(c) + if_() + i32_const(9) + local_set(3)
              + END + local_get(3) + i32_const(want) + EQ for c, want in [(1, 3), (2, 9)]],
            *[local_get(c) + if_(I32) + i32_const(10) + ELSE + local_get(2) + i32_const(1) + ADD
              + END + i32_const(want) + EQ for c, want in [(1, 8), (2, 10)]],
            *[local_get(c) + if_() + i32_const(addr) + i32_const(v) + mem(I32_STORE) + END
              + i32_const(addr) + mem(I32_LOAD) + i32_const(want) + EQ
              for c, addr, v, want in [(2, 64, 77, 77), (1, 68, 55, 0)]],
            local_get(1) + if_(I32) + i32_const(10) + ELSE + local_get(2) + i32_const(1) + ADD
            + END + i32_const(10) + EQ)))), "", 0x7E),
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
    # The same with the address in a local, so that it is not a constant.
    # The check compares the base -1 with 65536 - 4 + 1 - 1, the first
    # base at which 4 bytes from base + 1 do not fit.
    ("oobdyn", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(-1) + local_set(0) + local_get(0) + i32_const(5)
              + mem(I32_STORE, offset=1) + i32_const(0)))),
     "", 2),
    # 65532 + 4 is the first byte past the memory, so the load traps.
    ("oobend", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(65532) + local_set(0) + local_get(0) + mem(I32_LOAD, offset=4)))),
     "", 2),
    # Loads and stores of 4 and 8 bytes at the end of the memory, at
    # addresses that are not constants (memend_checks). With bounds checks,
    # without them, and with a memory that may grow to 2 pages but has not.
    ("memend", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, bits(0, *memend_checks())))), "", 0x3FE),
    ("memend_unchecked", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, bits(0, *memend_checks())))), "", 0x3FE),
    ("memend_grow", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, bits(0, *memend_checks())))), "", 0x3FE),
    # An i32 at 65533 passes the end of the memory by a byte. The base is
    # not a multiple of 4, so the compare of base ROR 2 fails, and the stub
    # finds that the load is out of bounds.
    ("oobword", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(65533) + local_set(0) + local_get(0) + mem(I32_LOAD)))),
     "", 2),
    # 0xFFFFFFFC is a multiple of 4, but past the memory, so the compare of
    # base ROR 2 fails. In the stub, W.cload4 finds that base + 8 passes
    # 2^32, and traps with R2 at the start of the load.
    ("oobwordwrap", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(-4) + local_set(0) + local_get(0) + mem(I32_LOAD, offset=8)))),
     "", 2),
    # From 65516 in steps of 4, the third round stores 7 at 65524, word
    # 16381, which fails the shared compare. The first access's stub
    # stores it, then the copy loads 2 from 65532, and the store at 65536
    # traps. The handler adds the word at 65524, 7, to the code: 2 + 7 =
    # 9. R2 points at the store in the code, which has no compare of its
    # own. With a memory that can grow, each access has its own compare.
    ("sharetrap3", share_trap(65516, 4), SHARE_ASM.format(16381), 9),
    ("sharetrap3_grow", share_trap(65516, 4), SHARE_ASM.format(16381), 9),
    # The same from 65520 in steps of 8: the second round stores 7 at
    # 65528, word 16382, which fails the shared compare too, and the load
    # at 65536 traps. 2 + 7 = 9.
    ("sharetrap2", share_trap(65520, 8), SHARE_ASM.format(16382), 9),
    ("sharetrap2_grow", share_trap(65520, 8), SHARE_ASM.format(16382), 9),
    # The accesses of sharetrap3 at 65524, once. Outside a loop, they
    # share a compare too, since that makes the code smaller.
    ("sharetrap", share_trap(65524, 0), SHARE_ASM.format(16381), 9),
    # Before the loop, bytes 5 to 8 are 0A 0B 0C 0D. Then bytes 1 to 4
    # become 11 22 33 44, x is 0x0D0C0B0A, and bytes 9 to 12 become 55 66
    # 77 88. So the words at 0, 4, 8, and 12 are 0x33221100, 0x0C0B0A44,
    # 0x7766550D, and 0x88. Their XOR with x is 0x454345CB. The first
    # access's stub stores at 1, and the copy does the others through the
    # helpers. Without bounds checks, there is no compare to share.
    ("share", SHARE_UNALIGNED, "", 0x454345CB),
    ("share_unchecked", SHARE_UNALIGNED, "", 0x454345CB),
    # f(n, a) = a if n = 0, else f(n - 1, a + n) + n, so f(4, 10) = 20 +
    # 1 + 2 + 3 + 4 = 30. n lives across the call in a saved register, but
    # the test of n and the return of a come before the prologue
    # (README.md), so f(0, 20) saves nothing.
    ("earlyexit", module(
        types(MAIN_TYPE, ([I32, I32], [I32])),
        funcs(0, 1),
        exports(("main", 0, 0)),
        code((0, i32_const(4) + i32_const(10) + call(1)),
             (0, local_get(0) + EQZ + if_(I32) + local_get(1) + ELSE
              + local_get(0) + i32_const(1) + SUB + local_get(1) + local_get(0) + ADD + call(1)
              + local_get(0) + ADD + END))),
     "", 30),
    # The loads from 16 to 19 give 0x04030201, 0x05040302, 0x06050403,
    # and 0x07060504, whose sum s is 0x16120E0A, and k is 4 * 7 = 28 =
    # 0x1C. The last three are not at a multiple of 4, so their stub,
    # with the copy of the ADD of k, runs. s XOR k is 0x16120E16.
    ("hoist", hoist_slot(16, 20), SHARE_ASM.format(0), 0x16120E16),
    # From 65528, the loads up to 65532 add 0x16120E0A + 0x08070605 =
    # 0x1E19140F to s, which is stored at 0. The load from 65533 traps,
    # in the stub, so the trap handler gives 2 + 0x1E19140F = 0x1E191411.
    ("hoisttrap", hoist_slot(65528, 65540), SHARE_ASM.format(0), 0x1E191411),
    # From 16 to 19, the loads of x add 0x16120E0A to s, as in hoist, and
    # those of y from 20 to 23 add 0x08070605 + 0x09080706 + 0x0A090807 +
    # 0x0B0A0908 = 0x26221E1A, so s is 0x3C342C24. k is 0x1C, and s XOR k
    # is 0x3C342C38. The last three rounds run the stub and the copy.
    ("hoistgroup", hoist_group(16, 20), SHARE_ASM.format(0), 0x3C342C38),
    # From 65524, the rounds up to 65527 add 0x3C342C24 to s, as in
    # hoistgroup, and that at 65528 adds 0x08070605 + 0x0C0B0A09, which
    # makes 0x50463C32. At 65529, the load of y from 65533 traps, in the
    # copy, so the trap handler gives 2 + 0x50463C32 = 0x50463C34.
    ("hoistgrouptrap", hoist_group(65524, 65540), SHARE_ASM.format(0), 0x50463C34),
    # The loads from 17, 21, and 25, all through the stub, give
    # 0x05040302, 0x09080706, and 0x0D0C0B0A, whose sum is 0x1B181512.
    ("hoistagen", HOIST_AGEN, "", 0x16),
    ("hoiststore", hoist_store(32), SHARE_ASM.format(0), 0x1B181512),
    # The stores at 65528 and 65532 are done, and that at 65536 traps,
    # with R2 at its ROR, which is in the code of the load. The trap
    # handler gives 2 + the word at 65532, 0x09080706, so 0x09080708.
    ("hoiststoretrap", hoist_store(65528), SHARE_ASM.format(16383), 0x09080708),
    # f(a, p) = 42 if x = p + 1 is 0, else g(); x + p. x and p live
    # across the call in saved registers. The test of x comes before the
    # prologue, with ADD[M] R0, but the copy of p to its saved register
    # comes after it, so the test must add 1 to p where it came. So
    # f(0, -1) = 42 and f(0, 4) = 9, and main returns 100 * 42 + 9 = 4209.
    ("earlyexitcopy", module(
        types(MAIN_TYPE, ([I32, I32], [I32]), ([], [])),
        imports(("env", "g", 2)),
        funcs(0, 1),
        exports(("main", 0, 1)),
        code((0, i32_const(0) + i32_const(-1) + call(2) + i32_const(100) + MUL
              + i32_const(0) + i32_const(4) + call(2) + ADD),
             (1, i32_const(42) + local_get(1) + i32_const(1) + ADD + local_tee(2) + EQZ
              + br_if(0) + DROP + call(0) + local_get(2) + local_get(1) + ADD))),
     "_g MOVE R15, @R13++\n", 4209),
    # f(p) loops for ever if p = 0, as C's if (!p) for (;;); does, and
    # else calls g and returns p. The search for an early return
    # (README.md) follows the jump of the loop only once. f(5) = 5.
    ("earlyexitloop", module(
        types(MAIN_TYPE, ([I32], [I32]), ([], [])),
        imports(("env", "g", 2)),
        funcs(0, 1),
        exports(("main", 0, 1)),
        code((0, i32_const(5) + call(2)),
             (0, block() + local_get(0) + EQZ + br_if(0) + call(0) + local_get(0) + RETURN + END
              + loop() + br(0) + END + i32_const(0)))),
     "_g MOVE R15, @R13++\n", 5),
    # g(x) = h(x + h(x)), with h(v) = 2v + 1, so g(5) = h(5 + 11) = 33. x
    # lives across the first call in a saved register, which g restores
    # before it jumps to h for the second call, a tail call (README.md).
    # h then returns to main.
    ("tailcall", module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(0, 1, 1),
        exports(("main", 0, 0)),
        code((0, i32_const(5) + call(1)),
             (0, local_get(0) + local_get(0) + call(2) + ADD + call(2)),
             (0, local_get(0) + i32_const(2) + MUL + i32_const(1) + ADD))),
     "", 33),
    # f(x) is ((x + 7) XOR 9) - 2 if x != 0, the short arm, which moves to
    # the end of f (README.md), and (x + 3) * 5 + (x XOR 6) + 1 if x = 0,
    # the long one. f(0) = 15 + 6 + 1 = 22 and f(4) = (11 XOR 9) - 2 = 0.
    # main returns 100 f(0) + f(4) + 1 = 2201.
    ("swaparms", module(
        types(MAIN_TYPE, ([I32], [I32])),
        funcs(0, 1),
        exports(("main", 0, 0)),
        code((0, i32_const(0) + call(1) + i32_const(100) + MUL + i32_const(4) + call(1) + ADD
              + i32_const(1) + ADD),
             (1, block() + block() + local_get(0) + EQZ + br_if(0)
              + local_get(0) + i32_const(7) + ADD + i32_const(9) + XOR + i32_const(2) + SUB
              + local_set(1) + br(1) + END
              + local_get(0) + i32_const(3) + ADD + i32_const(5) + MUL
              + local_get(0) + i32_const(6) + XOR + ADD + i32_const(1) + ADD + local_set(1) + END
              + local_get(1)))),
     "", 2201),
    # An i64 at 65532, a multiple of 4, passes the end by 4 bytes.
    ("oobword8", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(65532) + local_set(0) + local_get(0) + mem(I64_LOAD) + WRAP))),
     "", 2),
    # Loads and stores of 1 and 2 bytes (narrow_checks), the same three
    # ways.
    ("narrow", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, bits(0, *narrow_checks())))), "", 0xFFFFFE),
    ("narrow_unchecked", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, bits(0, *narrow_checks())))), "", 0xFFFFFE),
    ("narrow_grow", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, bits(0, *narrow_checks())))), "", 0xFFFFFE),
    # A byte at 65536, just past the memory, a halfword at 65535, of which
    # one byte is past it, and a byte at -1 + 1, which passes 2^32.
    ("oobbyte", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(65536) + local_set(0) + local_get(0) + mem(I32_LOAD8_U)))),
     "", 2),
    ("oobhalf", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(65535) + local_set(0) + local_get(0) + mem(I32_LOAD16_S)))),
     "", 2),
    ("oobbytecarry", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(-1) + local_set(0) + local_get(0) + i32_const(7)
              + mem(I32_STORE8, offset=1) + i32_const(0)))),
     "", 2),
    # Addresses computed from an index (addrform_checks), the same three
    # ways.
    ("addrform", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((3, bits(0, *addrform_checks())))), "", 0x3FFE),
    ("addrform_unchecked", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((3, bits(0, *addrform_checks())))), "", 0x3FFE),
    ("addrform_grow", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((3, bits(0, *addrform_checks())))), "", 0x3FFE),
    # -1 << 2 is 0xFFFFFFFC, past the memory.
    ("addrformtrap", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(-1) + local_set(0) + local_get(0) + i32_const(2) + SHL
              + mem(I32_LOAD)))),
     "", 2),
    # Constant offsets folded into the word operand (fold_checks), the
    # same three ways.
    ("foldform", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((3, bits(0, *fold_checks())))), "", 0x1FE),
    ("foldform_unchecked", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((3, bits(0, *fold_checks())))), "", 0x1FE),
    ("foldform_grow", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((3, bits(0, *fold_checks())))), "", 0x1FE),
    # (1 << 2) + 65532 = 65536: c / 4 = 16383 is below the limit of 16384,
    # so the compare is of i = 1 with 1, which fails, and the stub calls
    # the checked helper, which traps. R2 is at the compare.
    ("foldtrap", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(1) + local_set(0) + local_get(0) + i32_const(2) + SHL
              + i32_const(65532) + ADD + mem(I32_LOAD)))),
     "", 2),
    # (0 << 2) + 65532 + 4: the 8 bytes from 65532 pass the memory. The
    # limit of an i64 access is 16383, so c / 4 = 16383 is not below it,
    # and the access is not folded: its compare is of t = 0 + 16383.
    ("foldtrap8", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(0) + local_set(0) + local_get(0) + i32_const(2) + SHL
              + i32_const(65532) + ADD + mem(I64_LOAD) + WRAP))),
     "", 2),
    # From i = 0 to 4, the loads give 0, 1, 2, 3, and 4, each the value
    # that the round before stored, and s is 10. The word at (5 << 2) +
    # 8480 is 5. So main returns 10 XOR 0x500 = 0x50A.
    ("fold", fold_loop(0, 5), SHARE_ASM.format(0), 0x50A),
    # From i = -3 to 1. For i = -3 to -1, a = 8468, 8472, and 8476: the
    # address wraps modulo 2^32, i fails the compare, and the stub and the
    # copy do the accesses through the checked helpers. The loads give
    # 0x10 to 0x14, so s is 0x5A, and the word at (2 << 2) + 8480 = 8488
    # is 0x15. 0x5A XOR 0x1500 is 0x155A.
    ("foldwrap", fold_loop(-3, 2), SHARE_ASM.format(0), 0x155A),
    # From i = 14260, a = 57040 + 8480 = 65520. The loads give 0, 1, 2,
    # and 3, so s is 6 when the store at 65532 + 4 = 65536 traps, for i =
    # 14263. That i fails the shared compare, with the limit 16383 - 2120
    # = 14263 of the store, so the load's stub does the load, and the copy
    # the store, which traps. The trap handler gives 2 + 6 = 8. R2 points
    # at the store in the code, which has no compare of its own.
    ("foldsharetrap", fold_loop(14260, 14300), SHARE_ASM.format(0), 8),
    # a = (3 << 2) + 8480 = 8492, x = 0x20, and main returns 0x21 + 8492
    # = 0x214D.
    ("foldtee", fold_tee(3), "", 0x214D),
    # a = (14263 << 2) + 8480 = 65532: the load is in bounds, and the store
    # at 65536 traps, in the copy. R2 points at the store in the code.
    ("foldteetrap", fold_tee(14263), "", 2),
    # Loads at (i << 2) + c with a bound on i (bound_case). The memory is
    # 16384 words. With c = 64512, d = c / 4 = 16128, and i <= 255, the
    # last word that i allows is 255 + 16128 = 16383, the last word of the
    # memory, so the load has no compare. i = 52 gives 64512 + 208 =
    # 64720.
    ("bound", bound_case(AND255, 64512, 64720, 0x11223344), "", 0x11223344),
    # The same, but c = 64516 and d = 16129: i = 255 would be past the
    # memory, so the compare of i with 16384 - 16129 = 255 stays. i = 52
    # gives 64516 + 208 = 64724.
    ("bound_over", bound_case(AND255, 64516, 64724, 0x55667788), "", 0x55667788),
    # i is the byte at 100, 200 = 0xC8, so i <= 255, and c = 64512 as for
    # bound: 64512 + 800 = 65312.
    ("bound_load8", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, st(I32_STORE, 65312, 0x0BADF00D) + i32_const(100) + mem(I32_LOAD8_U)
              + i32_const(2) + SHL + i32_const(64512) + ADD + mem(I32_LOAD))),
        data((100, bytes([0xC8])))), "", 0x0BADF00D),
    # i = 0x1234 rem_u 100 = 4660 % 100 = 60, so i <= 99. With c = 65136,
    # d = 16284, and 99 + 16284 = 16383 is the last word. 65136 + 240 =
    # 65376.
    ("bound_remu", bound_case(i32_const(0x1234) + local_set(0) + local_get(0)
                              + i32_const(100) + b"\x70", 65136, 65376, 0x600D),
     "", 0x600D),
    # i = x & 255 in local 1, and then local 1 is set to local 0 - 0 =
    # 0x4034, whose bound nicewasm does not know, before the shift. So the
    # compare stays, and the address 0x4034 * 4 + 64512 = 130256 traps.
    ("boundtrap", bound_case(AND255 + local_set(1) + i32_const(0x4034) + i32_const(0) + SUB
                             + local_set(0) + local_get(0) + local_set(1) + local_get(1),
                             64512, 64720, 0x77), "", 2),
    # An i64 at (i << 3) + 63488, with i = -1 & 255 = 255: the word index
    # is 2i + 15872 <= 16382, so both words, 16382 and 16383, are in the
    # memory, and there is no compare. 63488 + 2040 = 65528, the last 8
    # bytes, and the result is 0x01020304 XOR 0x50607080.
    ("bound64", bound_case(i32_const(-1) + local_set(0) + local_get(0) + i32_const(255) + AND,
                           63488, 65528, 0x50607080_01020304, True), "", 0x51627384),
    # The same with c = 63492: 2 * 255 + 15873 = 16383 is the last word,
    # but the second word would be past it, so the compare of 2i with
    # 16383 - 15873 = 510 stays. i = (254 - 0) & 255 = 254, of which
    # nicewasm knows only i <= 255, gives 63492 + 2032 = 65524.
    ("bound64_over", bound_case(i32_const(254) + i32_const(0) + SUB + local_set(0)
                                + local_get(0) + i32_const(255) + AND, 63492, 65524,
                                0x50607080_01020304, True), "", 0x51627384),
    # bound with a memory that can grow: the compare with the limit that
    # memory.grow keeps stays.
    ("bound_grow", bound_case(AND255, 64512, 64720, 0x11223344), "", 0x11223344),
    # bound without bounds checks: i + 16128 is the word index, below
    # 2^30, so it needs no AND with 0x3FFFFFFF.
    ("bound_unchecked", bound_case(AND255, 64512, 64720, 0x11223344), "", 0x11223344),
    # Byte loads at a bounded address (byte_bound). 0xFFF + 0xF000 =
    # 65535 is the last byte, so the load has no compare. It is at
    # 0x234 + 0xF000 = 62004.
    ("byte_bound", byte_bound(I32_LOAD8_U, 0xF000, 0xAB), "", 0xAB),
    # 0xFFF + 0xF001 = 65536 is past the memory, so the compare of the
    # address with 65536 stays. The load is at 62005.
    ("byte_bound_over", byte_bound(I32_LOAD8_U, 0xF001, 0xCD), "", 0xCD),
    # Two bytes: 0xFFF + 0xEFFF = 65534, and 65534 + 1 is the last byte,
    # so there is no compare with 65535. The load is at 62003, and its
    # two bytes straddle two words.
    ("half_bound", byte_bound(I32_LOAD16_U, 0xEFFF, 0xBEEF), "", 0xBEEF),
    # 0xFFF + 0xF000 = 65535, and its second byte is past the memory, so
    # the compare with 65535 stays. The load is at 62004.
    ("half_bound_over", byte_bound(I32_LOAD16_U, 0xF000, 0xBEEF), "", 0xBEEF),
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
    # number. The routines are in runtime/lib.nasm.
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
    # i64.mul by constants, which nicewasm makes inline with the math unit
    # and shifts and additions, unless it finds no plan for either word of
    # the constant. c = 0x2545F4914F6CDD1D, xorshift64*'s, has a plan for
    # both words: 12 steps for the high word and 16 for the low. -1 * c is
    # ~c + 1. 0xA6CECC1B has no plan in 16 steps, so with x = 2^32 + 1,
    # x * c is c + (c << 32): the low word of c, and below it the sum of
    # its words. Each of the 8 rows is checked three ways, so 24 ones,
    # then a check that fails.
    ("mul64", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code(([I32, I64], bits(0, *[mul64_by(*row, how) for how in range(3) for row in [
            # 3 * 0x80000001_80000001 = 0x1_80000004_80000003.
            (0x80000001_80000001, 3, 0x80000004_80000003),
            # Times 2^32, and times 2^32 + 1: the low word of c is 0 or 1.
            (0x12345678_9ABCDEF0, 0x1_00000000, 0x9ABCDEF0_00000000),
            (0x12345678_9ABCDEF0, 0x1_00000001, 0xACF13568_9ABCDEF0),
            (2**64 - 1, 0x2545F491_4F6CDD1D, 0xDABA0B6E_B09322E3),
            (0x1_00000001, 0x2545F491_4F6CDD1D, 0x74B2D1AE_4F6CDD1D),
            # The low word has no plan, the high word does (3), and the
            # other way round with a low word of 1, and neither.
            (0x1_00000001, 0x3_A6CECC1B, 0xA6CECC1E_A6CECC1B),
            (0x1_00000001, 0xA6CECC1B_00000001, 0xA6CECC1C_00000001),
            (0x1_00000001, 0xA6CECC1B_A6CECC1B, 0x4D9D9836_A6CECC1B)]]
            + [mul64_by(3, 5, 16, 0)])))), "", 0x1FFFFFE),
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
    # 0x169 prints i. A peek whose result is dropped is still performed:
    # main pokes 0 into the emulator's read counter at 0xFFFFFF01 (-255),
    # peeks it and drops the result, then returns peek of the word plus a
    # second peek of the counter, which is 1 only if the first peek was
    # made: 41 + 1 = 42.
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
              + i32_const(-255) + i32_const(0) + call(1)
              + i32_const(-255) + call(0) + DROP
              + local_get(0) + call(0) + i32_const(-255) + call(0) + ADD))),
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
    # With 64 bytes reserved, elem(7) reads the last word, at 60, which is
    # 0, and elem(8) traps. The compare is of i with 16 - 8 = 8: the limit
    # of the library's memory, less 32 / 4.
    ("libfold", LIB_FOLD, LIB_ASM.format("MOVE R1, 7", "_elem", "ADD R1, R1, 5"), 5),
    ("libfoldtrap", LIB_FOLD, LIB_ASM.format("MOVE R1, 8", "_elem", "MOVE R0, R0"), 2),
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
    # The same with addresses in local 1, after memory.grow 1. The word at
    # 131068 is the last one of page 1. 77 is 0x4D.
    ("growdyn", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((2, bits(0,
            i32_const(1) + MEMORY_GROW + i32_const(1) + EQ,
            st_dyn(I32_STORE, 131068, 77) + ld_dyn(I32_LOAD, 131068, 77),
            ld_dyn(I64_LOAD, 131064, 77 << 32),
            ld_dyn(I32_LOAD, 131064, 77, offset=4),
            ld_dyn(I32_LOAD, 131067, 77 << 8),
            ld_dyn(I32_LOAD, 131068, 0))))),
     "", 0x3E),
    # Before memory.grow, the load at 65532 + 4, in page 1, traps. The base
    # is in a local, so the check compares base ROR 2 + 1 with W.wlimit4.
    ("growdyntrap", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, i32_const(65532) + local_set(0) + local_get(0) + mem(I32_LOAD, offset=4)))),
     "", 2),
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
    # Division and remainder with both operands in locals, so that
    # nicewasm checks the divisor when the code runs (README.md), one bit
    # each. MIN is the most negative number. Rounding is toward 0, and a
    # remainder has the sign of the dividend:
    ("divdyn", main_of(bits(0,
        dyn32(-7, DIV_S, -1, 7),                            # by -1, not MIN: no trap
        dyn32(-7, REM_S, -1, 0),
        dyn32(0x80000000, REM_S, -1, 0),                    # MIN % -1 = 0
        dyn32(-7, DIV_U, -1, 0),                            # 0xFFFFFFF9 / 0xFFFFFFFF
        dyn32(-7, REM_U, -1, -7),
        dyn32(7, DIV_S, -2, -3),
        dyn32(7, REM_S, -2, 1),
        dyn32(-7, REM_S, -2, -1),
        dyn32(-7, DIV_S, -2, 3),
        dyn32(0x80000000, DIV_S, 1, 0x80000000),
        dyn32(0x80000000, DIV_S, 2, 0xC0000000),            # -2^30
        dyn32(0xFFFFFFFF, DIV_U, 0x80000000, 1),
        dyn32(0xFFFFFFFF, REM_U, 0x80000000, 0x7FFFFFFF),
        # x = 0x12345678_9ABCDEF0: x / -1 = -x.
        dyn64(0x12345678_9ABCDEF0, DIV_S64, -1, 0xEDCBA987_65432110),
        dyn64(0x12345678_9ABCDEF0, REM_S64, -1, 0),
        dyn64(2**63, REM_S64, -1, 0),                       # MIN % -1 = 0
        # -1 in the low word alone: MIN / (2^32 - 1) = -2^31 rem -2^31,
        # as (2^32 - 1) * 2^31 = 2^63 - 2^31.
        dyn64(2**63, DIV_S64, 0xFFFFFFFF, 0xFFFFFFFF_80000000),
        dyn64(2**63, REM_S64, 0xFFFFFFFF, 0xFFFFFFFF_80000000),
        # -1 in the high word alone: MIN / -2^32 = 2^31.
        dyn64(2**63, DIV_S64, 0xFFFFFFFF_00000000, 0x80000000),
        # A divisor whose low word is 0 is not 0.
        dyn64(0x5_00000007, DIV_U64, 0x1_00000000, 5),
        dyn64(0x5_00000007, REM_U64, 0x1_00000000, 7),
        dyn64(-7, REM_S64, 2, -1),
        dyn64(7, REM_S64, -2, 1),
        dyn64(0x12345678_9ABCDEF0, DIV_U64, -1, 0),
        dyn64(0x12345678_9ABCDEF0, REM_U64, -1, 0x12345678_9ABCDEF0),
        dyn64(-1, DIV_U64, -1, 1),
        dyn64(-1, DIV_S64, 0x1_00000000, 0),                # -1 / 2^32 rounds to 0
        dyn64(-1, REM_S64, 0x1_00000000, -1),
        # A check that fails. 28 ones, then 0.
        dyn32(7, DIV_U, 2, 4))), "", 0x1FFFFFFE),
    # The traps of divdyn's checks, with the operands in f's parameters:
    # 5 % 0, 5 / 0 for an i64, and MIN / -1 for both. R2 points at the
    # first check, of the divisor in R2, or R3 and R4.
    ("divzero_dyn", div_trap(I32, 5, REM_S, 0), "", 3),
    ("divzero64_dyn", div_trap(I64, 5, DIV_U64, 0), "", 3),
    ("overflow_dyn", div_trap(I32, 0x80000000, DIV_S, -1), "", 4),
    ("overflow64_dyn", div_trap(I64, 2**63, DIV_S64, -1), "", 4),
    # The conversions that floatconv does not reach, one bit each. Some
    # bits: 1e10 as an f64 is 0x4202A05F20000000, 1e20 as an f32
    # 0x60AD78EC, 4.5e9 as an f32 0x4F861C46, 3.9 as an f64
    # 0x400F333333333333, -3.7 as an f32 0xC06CCCCD.
    ("floatconv2", main_of(bits(0,
        bits32(c64(-1) + fop(0xB4), 0xBF800000),                       # f32.convert_i64_s -1
        bits32(c64(2**63 - 1) + fop(0xB4), 0x5F000000),                # rounds to 2^63
        bits32(c64(2**63) + fop(0xB4), 0xDF000000),                    # -2^63
        bits32(c64(-1) + fop(0xB5), 0x5F800000),                       # f32.convert_i64_u: 2^64
        # 2^63 + 2^39 + 1 is more than half an f32 step, 2^40, above 2^63,
        # so it rounds up. Rounded to an f64 first, it would lose the 1,
        # become a tie, and round to the even 2^63.
        bits32(c64(0x80000080_00000001) + fop(0xB5), 0x5F000001),
        bits32(c64(2**24 + 1) + fop(0xB5), 0x4B800000),                # a tie, to the even 2^24
        bits64(c32(0xFFFFFFFF) + fop(0xB8), 0x41EFFFFFFFE00000),       # f64.convert_i32_u
        bits64(c32(0x80000000) + fop(0xB8), 0x41E0000000000000),       # 2^31
        f64(0x3FF0000000000000) + f64(0x3FF0000000000000) + fop(0x61),  # f64.eq: 1 == 1
        f64(0x7FF8000000000000) + f64(0x7FF8000000000000) + fop(0x61) + EQZ,  # NaN == NaN is 0
        f64(0x8000000000000000) + f64(0) + fop(0x61),                   # -0 == 0
        f64(0x4008000000000000) + f64(0x4000000000000000) + fop(0x64),  # f64.gt: 3 > 2
        f64(0x7FF8000000000000) + f64(0x3FF0000000000000) + fop(0x64) + EQZ,  # NaN > 1 is 0
        bits64(c64(0x7FF8000000000001) + fop(0xBF), 0x7FF8000000000001),  # f64.reinterpret_i64
        f64(0xC202A05F20000000) + fop(0x102) + c32(0x80000000) + EQ,   # i32.trunc_sat_f64_s -1e10
        f64(0x4202A05F20000000) + fop(0x102) + c32(0x7FFFFFFF) + EQ,   # 1e10
        f64(0x7FF8000000000000) + fop(0x102) + EQZ,                    # NaN
        f64(0xC004000000000000) + fop(0x102) + c32(-2) + EQ,           # -2.5
        f64(0xBFF0000000000000) + fop(0x103) + EQZ,                    # i32.trunc_sat_f64_u -1
        f64(0x4202A05F20000000) + fop(0x103) + c32(0xFFFFFFFF) + EQ,   # 1e10
        f64(0x41EFFFFFFFE00000) + fop(0x103) + c32(0xFFFFFFFF) + EQ,   # 2^32 - 1 fits
        f64(0x400F333333333333) + fop(0x103) + c32(3) + EQ,            # 3.9
        f32(0x4F861C46) + fop(0x101) + c32(0xFFFFFFFF) + EQ,           # i32.trunc_sat_f32_u 4.5e9
        f32(0x5F000000) + fop(0xAF) + c64(2**63) + EQ64,               # i64.trunc_f32_u 2^63
        # A check that fails. 24 ones, then 0.
        bits32(c64(-1) + fop(0xB4), 0x3F800000))), "", 0x1FFFFFE),
    ("floatconv3", main_of(bits(0,
        f32(0xBF000000) + fop(0xAF) + EQZ64,                           # -0.5 fits, as 0
        f32(0x3FC00000) + fop(0xAF) + c64(1) + EQ64,                   # 1.5
        # 2^64 - 2^11, the largest f64 below 2^64.
        f64(0x43EFFFFFFFFFFFFF) + fop(0xB1) + c64(0xFFFFFFFF_FFFFF800) + EQ64,  # i64.trunc_f64_u
        f64(0xBFECCCCCCCCCCCCD) + fop(0xB1) + EQZ64,                   # -0.9 fits, as 0
        f32(0xDF000000) + fop(0xAE) + c64(2**63) + EQ64,               # i64.trunc_f32_s: -2^63 fits
        f32(0x60AD78EC) + fop(0x104) + c64(2**63 - 1) + EQ64,          # i64.trunc_sat_f32_s 1e20
        f32(0xFF800000) + fop(0x104) + c64(2**63) + EQ64,              # -inf
        f32(0x7FC00000) + fop(0x104) + EQZ64,                          # NaN
        f32(0xC06CCCCD) + fop(0x104) + c64(-3) + EQ64,                 # -3.7
        f32(0xC0A00000) + fop(0x105) + EQZ64,                          # i64.trunc_sat_f32_u -5
        f32(0x7F800000) + fop(0x105) + c64(-1) + EQ64,                 # +inf
        f64(0x43F0000000000000) + fop(0x107) + c64(-1) + EQ64,         # i64.trunc_sat_f64_u 2^64
        f64(0x3FF8000000000000) + fop(0x107) + c64(1) + EQ64,          # 1.5
        f64(0x7FF8000000000000) + fop(0x107) + EQZ64,                  # NaN
        f64(0x43E0000000000000) + fop(0x106) + c64(2**63 - 1) + EQ64,  # i64.trunc_sat_f64_s 2^63
        # select without a type, on an f32 and on an f64.
        bits32(f32(0x3F800000) + f32(0x40000000) + i32_const(0) + SELECT, 0x40000000),
        bits64(f64(0x3FF0000000000000) + f64(0x4000000000000000) + i32_const(1) + SELECT,
               0x3FF0000000000000),
        # A check that fails. 17 ones, then 0.
        f32(0x3FC00000) + fop(0xAF) + c64(2) + EQ64)), "", 0x3FFFE),
    # trunc traps with code 5 for 2^64 as an unsigned i64, -1 as an
    # unsigned i64 and i32, and 2^63 as a signed i64. Each trunc's code
    # starts with the move of its limit for a positive value (TRUNC_OPS),
    # 0x5F800000, 0x43F00000_00000000, 0x4F800000, and 0x43E00000_00000000.
    ("trunc_u64_big", trunc_trap(f32(0x5F800000) + fop(0xAF) + WRAP), "", 5),
    ("trunc_u64_neg", trunc_trap(f64(0xBFF0000000000000) + fop(0xB1) + WRAP), "", 5),
    ("trunc_u32_neg", trunc_trap(f32(0xBF800000) + fop(0xA9)), "", 5),
    ("trunc_s64_big", trunc_trap(f64(0x43E0000000000000) + fop(0xB0) + WRAP), "", 5),
    # Blocks with several results and with parameters, one bit each. Type
    # 1 is () -> (i32, i64), 2 (i32, i64) -> (i64, i32), 3 (i32, i32) ->
    # (i32, i32), and 4 () -> (f64, i32). L is 0x5_00000007.
    ("multivalue", module(
        types(MAIN_TYPE, ([], [I32, I64]), ([I32, I64], [I64, I32]), ([I32, I32], [I32, I32]),
              ([], [F64, I32])),
        funcs(0),
        exports(("main", 0, 0)),
        code((DYN_LOCALS, bits(0,
            # 3 and L at the end of the block, then through a br from above 99.
            block(typeidx(1)) + i32_const(3) + c64(0x5_00000007) + END
            + c64(0x5_00000007) + EQ64 + local_set(2) + i32_const(3) + EQ + local_get(2) + AND,
            block(typeidx(1)) + i32_const(99) + i32_const(3) + c64(0x5_00000007) + br(0) + END
            + c64(0x5_00000007) + EQ64 + local_set(2) + i32_const(3) + EQ + local_get(2) + AND,
            # A br_if that is taken carries 4 and 0x6_00000008, one that
            # is not leaves them, and the block ends with 6 and
            # 0x9_0000000A instead.
            block(typeidx(1)) + i32_const(4) + c64(0x6_00000008) + i32_const(1) + br_if(0)
            + DROP + DROP + i32_const(0) + c64(0) + END
            + c64(0x6_00000008) + EQ64 + local_set(2) + i32_const(4) + EQ + local_get(2) + AND,
            block(typeidx(1)) + i32_const(4) + c64(0x6_00000008) + i32_const(0) + br_if(0)
            + DROP + DROP + i32_const(6) + c64(0x9_0000000A) + END
            + c64(0x9_0000000A) + EQ64 + local_set(2) + i32_const(6) + EQ + local_get(2) + AND,
            # An if of type 2 on 10 and 20: taken, it gives 21 and 12,
            # else 7 and 8.
            *[i32_const(10) + c64(20) + i32_const(cond) + if_(typeidx(2))
              + local_set(3) + local_set(1) + local_get(3) + c64(1) + ADD64
              + local_get(1) + i32_const(2) + ADD
              + ELSE + DROP + DROP + c64(7) + i32_const(8) + END
              + i32_const(w32) + EQ + local_set(2) + c64(w64) + EQ64 + local_get(2) + AND
              for cond, w64, w32 in [(1, 21, 12), (0, 7, 8)]],
            # A loop of type 3 takes the count and the sum, and its br_if
            # carries both back: 5 rounds give 5 and 1 + ... + 5 = 15.
            i32_const(0) + i32_const(0) + loop(typeidx(3))
            + local_set(2) + local_set(1) + local_get(1) + i32_const(1) + ADD + local_tee(1)
            + local_get(2) + local_get(1) + ADD + local_get(1) + i32_const(5) + LT_U + br_if(0)
            + END + i32_const(15) + EQ + local_set(2) + i32_const(5) + EQ + local_get(2) + AND,
            # br_table carries 5 and 0x1_00000002 to the inner block,
            # which adds 100, for index 0, else to the outer one.
            *[block(typeidx(1)) + block(typeidx(1)) + i32_const(5) + c64(0x1_00000002)
              + i32_const(index) + br_table([0], 1) + END
              + local_set(3) + i32_const(100) + ADD + local_get(3) + END
              + c64(0x1_00000002) + EQ64 + local_set(2) + i32_const(want) + EQ + local_get(2) + AND
              for index, want in [(0, 105), (1, 5), (7, 5)]],
            # A block of type 2 swaps its parameters, 1 and 2, by a br.
            i32_const(1) + c64(2) + block(typeidx(2)) + local_set(3) + local_set(1)
            + local_get(3) + local_get(1) + br(0) + END
            + i32_const(1) + EQ + local_set(2) + c64(2) + EQ64 + local_get(2) + AND,
            # An f64 below an i32.
            block(typeidx(4)) + f64(0x4000000000000000) + i32_const(9) + END
            + i32_const(9) + EQ + local_set(2)
            + I64_REINTERPRET_F64 + c64(0x4000000000000000) + EQ64 + local_get(2) + AND,
            # A check that fails. 12 ones, then 0.
            i32_const(0))))), "", 0x1FFE),
    # Blocks whose parameter is a local's value, which the block then
    # changes: the parameter keeps the old value, 3, so each gives 3 +
    # 100 = 103. An if without else of type (i32, i32) -> (i32, i32)
    # passes 3 and 4 on, 3 + 10 * 4 = 43, or swaps them, 4 + 10 * 3 =
    # 34. 5 ones, then a check that fails.
    ("blockparams", module(
        types(MAIN_TYPE, ([I32], [I32]), ([I32, I32], [I32, I32])),
        funcs(0),
        exports(("main", 0, 0)),
        code((DYN_LOCALS, bits(0,
            *[i32_const(3) + local_set(1) + local_get(1) + kind(typeidx(1))
              + i32_const(100) + local_set(1) + local_get(1) + ADD + END + i32_const(103) + EQ
              for kind in (block, loop)],
            i32_const(3) + local_set(1) + local_get(1) + i32_const(1) + if_(typeidx(1))
            + i32_const(100) + local_set(1) + local_get(1) + ADD + ELSE + i32_const(1) + ADD
            + END + i32_const(103) + EQ,
            *[i32_const(3) + local_set(1) + i32_const(4) + local_set(2) + local_get(1)
              + local_get(2) + i32_const(cond) + if_(typeidx(2)) + local_set(1) + local_set(2)
              + local_get(1) + local_get(2) + END + i32_const(10) + MUL + ADD + i32_const(want) + EQ
              for cond, want in [(0, 43), (1, 34)]],
            i32_const(0))))), "", 0x3E),
    # A range of 0 bytes past the end of the memory traps too: wasm traps
    # if d + n is past the end, for d, and for s of memory.copy. So do 16
    # + 0xFFFFFFF0 bytes, whose end passes 2^32. R2 points at the ADD of
    # the first check.
    ("fillzerooob", main_of(fill(65537, 0, 0) + i32_const(0), True), "", 2),
    ("copyzerooob", main_of(copy(0, 65537, 0) + i32_const(0), True), "", 2),
    ("copydestzerooob", main_of(copy(65537, 0, 0) + i32_const(0), True), "", 2),
    ("fillwrap", main_of(fill(16, 0, -16) + i32_const(0), True), "", 2),
    # An offset of 65536 puts every access past the end of one page, so
    # the code of a byte load and of a word load at a base in a local only
    # traps.
    ("bigoffbyte", main_of(i32_const(0) + local_set(1) + local_get(1) + mem(I32_LOAD8_U, 65536),
                           True), "", 2),
    ("bigoffword", main_of(i32_const(0) + local_set(1) + local_get(1) + mem(I32_LOAD, 65536),
                           True), "", 2),
    # Without bounds checks, base + offset wraps modulo 2^32 (WASM.md).
    # Bytes 4 to 15 are 11 22 ... CC, from three stores. The bases are in
    # local 1, so they are not constants. One bit each:
    ("bigoff_unchecked", main_of(
        st(I32_STORE, 4, 0x44332211) + st(I32_STORE, 8, 0x88776655 - 2**32)
        + st(I32_STORE, 12, 0xCCBBAA99 - 2**32) + bits(0,
            i32_const(8) + local_tee(1) + mem(I32_LOAD, 0xFFFFFFFC) + c32(0x44332211) + EQ,  # 4
            local_get(1) + mem(I32_LOAD8_U, 0xFFFFFFFD) + i32_const(0x22) + EQ,              # 5
            local_get(1) + mem(I32_LOAD16_U, 0xFFFFFFFE) + i32_const(0x4433) + EQ,           # 6
            local_get(1) + mem(I32_LOAD, 0xFFFFFFFD) + c32(0x55443322) + EQ,                 # 5
            i32_const(16) + local_tee(1) + mem(I64_LOAD, 0xFFFFFFF8)
            + c64(0xCCBBAA99_88776655) + EQ64,                                               # 8
            i32_const(20) + local_tee(1) + c32(0x12345678) + mem(I32_STORE, 0xFFFFFFFC)      # 16
            + ld(I32_LOAD, 16, 0x12345678),
            i32_const(30) + local_tee(1) + i32_const(0xAB) + mem(I32_STORE8, 0xFFFFFFFF)     # 29
            + ld(I32_LOAD8_U, 29, 0xAB),
            # A check that fails. 7 ones, then 0.
            i32_const(0)), True), "", 0xFE),
    # i32 shifts and rotates by counts in a local, which nicewasm masks
    # with an AND, one bit each. The count is taken modulo 32. 11 ones,
    # then a check that fails.
    ("dynshift", main_of(bits(0, *[dyn32(*row) for row in [
        (0x80000001, SHL, 32, 0x80000001),
        (1, SHL, 33, 2),
        (0x80000000, SHR_U, 63, 1),
        (0x80000000, SHR_S, 63, 0xFFFFFFFF),
        (0x80000000, SHR_S, 0xFFFFFFFF, 0xFFFFFFFF),
        (0x40000000, SHR_S, 32, 0x40000000),
        (0x80000001, ROTL, 33, 3),
        (0x80000001, ROTR, 0xFFFFFFFF, 3),                  # rotr 31 = rotl 1
        (0x12345678, ROTL, 0, 0x12345678),
        (0x12345678, ROTR, 32, 0x12345678),
        (0x12345678, ROTR, 4, 0x81234567),
        (1, SHL, 1, 1)]])), "", 0xFFE),
    # The bit counts at their edges, and the extensions and wrap of a
    # local, one bit each. 22 ones, then a check that fails.
    ("bitcounts", main_of(bits(0,
        un32(0x68, 0, 32),                                  # ctz
        un32(0x69, 0, 0),                                   # popcnt
        un32(0x69, 0xFFFFFFFF, 32),
        un32(0x67, 0xFFFFFFFF, 0),                          # clz
        un32(0x67, 0x00008000, 16),
        un64(0x79, 0, 64),                                  # clz
        un64(0x79, 1, 63),
        un64(0x79, 0x10000, 47),
        un64(0x79, 2**64 - 1, 0),
        un64(0x7A, 0, 64),                                  # ctz
        un64(0x7A, 2**63, 63),
        un64(0x7A, 0x10, 4),
        un64(0x7B, 0, 0),                                   # popcnt
        un64(0x7B, 0x80000001_00000001, 3),
        c32(0x00F00000) + local_tee(1) + b"\x67" + i32_const(8) + EQ,
        c64(0x00000100_00000000) + local_tee(3) + b"\x7a" + c64(40) + EQ64,
        local_get(3) + b"\x79" + c64(23) + EQ64,
        c32(-1) + local_set(1) + local_get(1) + EXTEND_U + c64(0xFFFFFFFF) + EQ64,
        local_get(1) + EXTEND_S + c64(-1) + EQ64,
        c32(0x7FFFFFFF) + local_set(1) + local_get(1) + EXTEND_S + c64(0x7FFFFFFF) + EQ64,
        c64(0xFFFFFFFF_00000001) + local_set(3) + local_get(3) + WRAP + i32_const(1) + EQ,
        c64(0x12345678_87654321) + local_set(3) + local_get(3) + b"\xc4"
        + c64(0xFFFFFFFF_87654321) + EQ64,
        un32(0x69, 1, 0))), "", 0x7FFFFE),
    # 40 i32 values, each local 0 + k, and 10 i64 values, each local 1 + k,
    # on the operand stack across a call of f, which returns 1000, so that
    # most are spilled to frame words. Then all are added: 40 * 3 + (0 +
    # ... + 39) = 900, and 1000. The i64s sum to 10 * 0x1_00000001 + 45 =
    # 0xA_00000037, whose words add 0x37 + 0xA = 65. 900 + 1000 + 65 =
    # 1965.
    ("deepstack", module(
        types(MAIN_TYPE),
        funcs(0, 0),
        exports(("main", 0, 1)),
        code((0, i32_const(1000)),
             ([I32, I64], i32_const(3) + local_set(0) + c64(0x1_00000001) + local_set(1)
              + b"".join(local_get(0) + i32_const(k) + ADD for k in range(40))
              + b"".join(local_get(1) + c64(k) + ADD64 for k in range(10))
              + call(0) + local_set(0)
              + ADD64 * 9 + local_tee(1) + WRAP + local_get(1) + c64(32) + SHR_U64 + WRAP + ADD
              + local_get(0) + ADD + ADD * 40))), "", 1965),
    # f(a, b, c, d, e, g, h, i, j, k) of MANY_TYPE: a, b, and c fill
    # R1-R4, d would need R4 and R5, so it and all after it go on the
    # stack (ABI.md). f first sets k = k + 1, a stack parameter, then
    # returns b + 2d + 4h + (a + 8c + 16g + 32i + 64k) + 128 bits(e) +
    # 256 bits(j). wrap passes its parameters on to f through the table,
    # and adds 1. main calls wrap with 1, 2^40, 2, 2^41, 1.0, 3, 3 * 2^40,
    # 4, 2.0, and 5: 17 * 2^40 + (1 + 16 + 48 + 128 + 384) + 128 *
    # 0x3FF00000_00000000 + 256 * 0x40000000 + 1. 128 * 0x3FF << 52 is
    # 31 << 59 modulo 2^64, so that is 0xF8000000_00000000 +
    # 0x1100_00000000 + 0x40_00000000 + 578 = 0xF8001140_00000242. main
    # returns whether it got that.
    ("manyparams", module(
        types(MAIN_TYPE, MANY_TYPE),
        funcs(1, 1, 0),
        table(1),
        exports(("main", 0, 2)),
        elems((0, [0])),
        code((0, local_get(9) + i32_const(1) + ADD + local_set(9)
              + local_get(1) + local_get(3) + c64(2) + b"\x7e" + ADD64
              + local_get(6) + c64(4) + b"\x7e" + ADD64
              + local_get(0) + local_get(2) + i32_const(8) + MUL + ADD
              + local_get(5) + i32_const(16) + MUL + ADD + local_get(7) + i32_const(32) + MUL + ADD
              + local_get(9) + i32_const(64) + MUL + ADD + EXTEND_U + ADD64
              + local_get(4) + I64_REINTERPRET_F64 + c64(128) + b"\x7e" + ADD64
              + local_get(8) + I32_REINTERPRET_F32 + EXTEND_U + c64(256) + b"\x7e" + ADD64),
             (0, b"".join(local_get(n) for n in range(10)) + i32_const(0) + call_indirect(1)
              + c64(1) + ADD64),
             (0, i32_const(1) + c64(2**40) + i32_const(2) + c64(2**41) + f64(0x3FF0000000000000)
              + i32_const(3) + c64(3 * 2**40) + i32_const(4) + f32(0x40000000) + i32_const(5)
              + call(1) + c64(0xF8001140_00000242) + EQ64))), "", 1),
    # rsum(n, a, b, c, d, e) = a + b + c + d + e if n = 0, else rsum(n - 1,
    # b, c, d, e, a + n), with d and e on the stack. Each call adds n to
    # the sum, so rsum(10, 1, 2, 3, 4, 5) = 15 + 55 = 70. fib(n) = n if n
    # < 2, else fib(n - 1) + fib(n - 2), so fib(20) = 6765. 70 + 6765 =
    # 6835.
    ("recursion", module(
        types(MAIN_TYPE, ([I32] * 6, [I32]), ([I32], [I32])),
        funcs(1, 2, 0),
        exports(("main", 0, 2)),
        code((0, local_get(0) + EQZ + if_(I32)
              + local_get(1) + local_get(2) + ADD + local_get(3) + ADD + local_get(4) + ADD
              + local_get(5) + ADD
              + ELSE + local_get(0) + i32_const(1) + SUB + local_get(2) + local_get(3)
              + local_get(4) + local_get(5) + local_get(1) + local_get(0) + ADD + call(0) + END),
             (0, local_get(0) + i32_const(2) + LT_U + if_(I32) + local_get(0)
              + ELSE + local_get(0) + i32_const(1) + SUB + call(1)
              + local_get(0) + i32_const(2) + SUB + call(1) + ADD + END),
             (0, i32_const(10) + i32_const(1) + i32_const(2) + i32_const(3) + i32_const(4)
              + i32_const(5) + call(0) + i32_const(20) + call(1) + ADD))), "", 6835),
    # find(x) returns the first i with i * i >= x, by a return from inside
    # a loop, a block, and an if, with 77 below on the operand stack and i
    # live across a call of id(x) = x. find(50) = 8, find(1) = 1, and
    # find(0) = 0. g(x) returns 0x7_00000000 + x from two loops deep, with
    # an i64 and an i32 below. 8 * 100 + 1 * 10 + 0 + the low word of g(5),
    # 5, is 815.
    ("retloop", module(
        types(MAIN_TYPE, ([I32], [I32]), ([I32], [I64])),
        funcs(1, 1, 2, 0),
        exports(("main", 0, 3)),
        code((0, local_get(0)),
             ([I32], i32_const(77) + loop() + block() + local_get(1) + call(0) + local_tee(1)
              + local_get(1) + MUL + local_get(0) + GE_U + if_() + local_get(1) + RETURN + END
              + END + local_get(1) + i32_const(1) + ADD + local_set(1) + br(0) + END),
             (0, c64(1) + i32_const(2) + loop() + loop(I64) + local_get(0) + EXTEND_U
              + c64(0x7_00000000) + ADD64 + RETURN + END + DROP + END + DROP + DROP + c64(0)),
             (0, i32_const(50) + call(1) + i32_const(100) + MUL + i32_const(1) + call(1)
              + i32_const(10) + MUL + ADD + i32_const(0) + call(1) + ADD + i32_const(5) + call(2)
              + WRAP + ADD))), "", 815),
    # The table of ELEM_FORMS, one bit each: entry 0 is inc, inc(5) = 6,
    # entry 1 dbl, 10, entry 4 inc, which overwrote dbl, 6, and the data
    # segment put 42 at byte 0. 1111, then a check that fails. Entry 2
    # holds a ref.null, and -1 is past the end of the table, so both
    # trap with code 6.
    ("elemforms", elem_case(bits(0,
        i32_const(5) + i32_const(0) + call_indirect(1) + i32_const(6) + EQ,
        i32_const(5) + i32_const(1) + call_indirect(1) + i32_const(10) + EQ,
        i32_const(5) + i32_const(4) + call_indirect(1) + i32_const(6) + EQ,
        i32_const(0) + mem(I32_LOAD8_U) + i32_const(42) + EQ,
        i32_const(0))), "", 0x1E),
    ("elemnull", elem_case(i32_const(5) + i32_const(2) + call_indirect(1)), "", 6),
    ("elemneg", elem_case(i32_const(5) + i32_const(-1) + call_indirect(1)), "", 6),
    # memory.grow with up to 2 pages, one bit each: growing by -1 or by
    # 2^31 pages fails, and must not wrap the size, which stays 1. Growing
    # by 2 fails, as only 1 page is left. Growing by 1 returns the old
    # size, 1, and the size is then 2. 111111, then a check that fails.
    ("growneg", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(1),
        exports(("main", 0, 0)),
        code((1, bits(0,
            i32_const(-1) + MEMORY_GROW + i32_const(-1) + EQ,
            MEMORY_SIZE + i32_const(1) + EQ,
            c32(0x80000000) + MEMORY_GROW + i32_const(-1) + EQ,
            i32_const(2) + MEMORY_GROW + i32_const(-1) + EQ,
            i32_const(1) + MEMORY_GROW + i32_const(1) + EQ,
            MEMORY_SIZE + i32_const(2) + EQ,
            i32_const(0))))), "", 0x7E),
    # Imports with stack arguments: sum6(a, b, c, d, e, f) = a + b + c +
    # d + e - f, with e and f on the stack, and mix(x, y, z) = x + y - z
    # of three i64s, with y in R3 and R4 and z on the stack (ABI.md).
    # sum6(1, 2, 3, 4, 50, 600) = -540, and mix(0x1_00000001,
    # 0x2_00000002, 4) = 0x2_FFFFFFFF. 11, then a check that fails.
    ("importargs", module(
        types(MAIN_TYPE, ([I32] * 6, [I32]), ([I64] * 3, [I64])),
        imports(("env", "sum6", 1), ("env", "mix", 2)),
        funcs(0),
        exports(("main", 0, 2)),
        code((1, bits(0,
            b"".join(i32_const(v) for v in (1, 2, 3, 4, 50, 600)) + call(0) + c32(-540) + EQ,
            c64(0x1_00000001) + c64(0x2_00000002) + c64(4) + call(1) + c64(0x2_FFFFFFFF) + EQ64,
            i32_const(0))))),
     "_sum6 ADD R1, R1, R2\n ADD R1, R1, R3\n ADD R1, R1, R4\n ADD R1, R1, @1[R13]\n"
     " SUB R1, R1, @2[R13]\n MOVE R15, @R13++\n"
     "_mix ADD[M] R1, R1, R3\n ADD[C] R2, R2, R4\n SUB[M] R1, R1, @1[R13]\n"
     " SUB[C] R2, R2, @2[R13]\n MOVE R15, @R13++\n", 6),
    # main is hand-written and calls the exported f(a, b, c, d) = b + d - a
    # - c, of the types i32, i64, i32, and i64, with a in R1, b in R2-R3, c
    # in R4, and d on the stack, low word first (ABI.md). f(3,
    # 0x2_00000050, 5, 0x7_00000100) = 0x9_00000148, and main returns its
    # low word less its high one: 0x148 - 9 = 319.
    ("exportabi", module(
        types(([I32, I64, I32, I64], [I64])),
        funcs(0),
        exports(("f", 0, 0)),
        code((0, local_get(1) + local_get(3) + ADD64 + local_get(0) + EXTEND_U + SUB64
              + local_get(2) + EXTEND_U + SUB64))),
     "_main MOVE @--R13, 7\n MOVE @--R13, 0x100\n MOVE R1, 3\n MOVE R2, 0x50\n MOVE R3, 2\n"
     " MOVE R4, 5\n ADD @--R13, 2, R15\n MOVE R15, _f\n ADD R13, R13, 2\n SUB R1, R1, R2\n"
     " MOVE R15, @R13++\n", 319),
    # An immutable i32 global, 41, and mutable i64 and f32 globals, set to
    # 0x1_00000002 + 0x2_00000003 = 0x3_00000005 and to 2.0. 111, then a
    # check that fails.
    ("globals2", module(
        types(MAIN_TYPE),
        funcs(0),
        typed_globals((I32, False, 41), (I64, True, 0x1_00000002), (F32, True, 0x3F800000)),
        exports(("main", 0, 0), ("ro", 3, 0)),
        code((1, global_get(1) + c64(0x2_00000003) + ADD64 + global_set(1)
              + i32_const(0x40000000) + F32_REINTERPRET_I32 + global_set(2)
              + bits(0,
                     global_get(0) + i32_const(41) + EQ,
                     global_get(1) + c64(0x3_00000005) + EQ64,
                     global_get(2) + I32_REINTERPRET_F32 + i32_const(0x40000000) + EQ,
                     i32_const(0))))), "", 0xE),
    # The start function reads a byte that a data segment sets, after
    # ___wasm_start has set the memory to 0, so g = 1 + 42 = 43.
    ("startdata", module(
        types(MAIN_TYPE, ([], [])),
        funcs(1, 0),
        memory(1),
        globals_(1),
        exports(("main", 0, 1)),
        start(0),
        code((0, global_get(0) + i32_const(100) + mem(I32_LOAD8_U) + ADD + global_set(0)),
             (0, global_get(0))),
        data((100, b"\x2a"))), "", 43),
    # The start function is an import, init, which sets the exported
    # global flag to 5.
    ("startimport", module(
        types(MAIN_TYPE, ([], [])),
        imports(("env", "init", 1)),
        funcs(0),
        globals_(0),
        exports(("main", 0, 1), ("flag", 3, 0)),
        start(0),
        code((0, global_get(0)))), "_init MOVE @_flag, 5\n MOVE R15, @R13++\n", 5),
    # A name section that ends in the middle of a name is ignored, since a
    # custom section must not make a module invalid.
    ("badnames", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((0, i32_const(3))),
        section(0, wname("name") + b"\x01\x05\x01\x00\x09ab")), "", 3),
    # An i64.mul by a constant whose result goes to a local by local.tee
    # and stays on the stack: x = 5, x * 3 = 15, plus the local: 30.
    ("multee", main_of(c64(5) + local_set(3) + local_get(3) + c64(3) + b"\x7e" + local_tee(4)
                       + local_get(4) + ADD64 + WRAP), "", 30),
    # bulk, memsize's grow, and the library without bounds checks, which
    # give the same results.
    ("library_unchecked", LIB_MODULE, LIB_ASM.format("MOVE R1, 21", "___twice", "MOVE R0, R0"), 42),
    # The flags say what a comparison's result in a local is, until the
    # local is written (README.md). x = 5, and local 1 = x < 7 = 1, one
    # bit each, by an if:
    # 0: local 1 is then set to 0.
    # 1: local 3 is a copy of local 1, which is then set to 0.
    # 0: the same, and local 3 is then set to 0 too.
    # 1: local 1 = x < 7 by local.tee, then local 1 = x, 5.
    # 01010 = 0xA, the last a check that fails.
    ("flagstale", module(
        types(MAIN_TYPE),
        funcs(0),
        exports(("main", 0, 0)),
        code((4, bits(0,
            as_if(i32_const(5) + local_set(2) + local_get(2) + i32_const(7) + LT_U + local_set(1)
                  + i32_const(0) + local_set(1) + local_get(1)),
            as_if(local_get(2) + i32_const(7) + LT_U + local_set(1) + local_get(1) + local_set(3)
                  + i32_const(0) + local_set(1) + local_get(3)),
            as_if(local_get(2) + i32_const(7) + LT_U + local_set(1) + local_get(1) + local_set(3)
                  + i32_const(0) + local_set(1) + i32_const(0) + local_set(3) + local_get(3)),
            as_if(local_get(2) + i32_const(7) + LT_U + local_tee(1) + DROP + local_get(2)
                  + local_set(1) + local_get(1)),
            i32_const(0))))), "", 0xA),
    # A memory of 0 pages that may grow to 1, one bit each: its size is 0,
    # memory.grow 1 returns 0, and the size is then 1. An i64 at the last 8
    # bytes, and the byte at 65535, the high byte of the i64's high word,
    # 0x01234567, work, with the bases in local 1. 11111, then a check
    # that fails. Before memory.grow, every limit of the checks is 0, so
    # a byte load and an i64 load at 0 trap with code 2.
    ("growzero", module(
        types(MAIN_TYPE),
        funcs(0),
        memory(0),
        exports(("main", 0, 0)),
        code((DYN_LOCALS, bits(0,
            MEMORY_SIZE + EQZ,
            i32_const(1) + MEMORY_GROW + EQZ,
            MEMORY_SIZE + i32_const(1) + EQ,
            i32_const(65528) + local_tee(1) + c64(0x01234567_89ABCDEF) + mem(I64_STORE)
            + local_get(1) + mem(I64_LOAD) + c64(0x01234567_89ABCDEF) + EQ64,
            i32_const(65535) + local_tee(1) + mem(I32_LOAD8_U) + i32_const(0x01) + EQ,
            i32_const(0))))), "", 0x3E),
    *[(name, module(
        types(MAIN_TYPE),
        funcs(0),
        memory(0),
        exports(("main", 0, 0)),
        code((DYN_LOCALS, i32_const(0) + local_set(1) + local_get(1) + load))), "", 2)
      for name, load in [("growzerotrap", mem(I32_LOAD8_U)),
                         ("growzerotrap8", mem(I64_LOAD) + WRAP)]],
]
# bulk and grow again without bounds checks, which give the same results.
CASES += [(name + "_unchecked", wasm, extra, expected) for name, wasm, extra, expected in CASES
          if name in ("bulk", "grow")]


def run(cmd: List[str]) -> str:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0 and not cmd[0].endswith("niceemu"):
        raise RuntimeError(f"{' '.join(cmd)} failed:\n{p.stderr}")
    return p.stdout + f"exit {p.returncode}\n"


def assemble(line: str, tmp: str, labels: Dict[str, int]) -> List[int]:
    """The words of one instruction. A label of the program that it names
    has its value in the program, from labels."""
    src = os.path.join(tmp, "line.nasm")
    with open(src, "w") as f:
        for name in sorted(set(re.findall(r"[A-Za-z_][\w.]*", line)) & labels.keys()):
            f.write(f"{name} .EQU {labels[name]}\n")
        f.write(f" {line}\n")
    run([sys.executable, NICEASM, "-o", src + ".bin", src])
    with open(src + ".bin") as f:
        return [int(line.split()[1], 16) for line in f]


def float_library(tmp: str, mpu: bool) -> Tuple[str, Set[str]]:
    """Translates the float library, and returns its file and the labels
    of its routines."""
    asm = os.path.join(tmp, "float.nasm" if mpu else "float_soft.nasm")
    run([sys.executable, NICEWASM, "--library", "float", *([] if mpu else ["--no-mpu"]),
         "-o", asm, os.path.join(RUNTIME, "float.wasm")])
    with open(asm) as f:
        labels = {line.strip() for line in f if line.startswith("__")}
    return asm, labels


def check(name: str, wasm_file: str, extra: str, expected: int, tmp: str,
          floats: Tuple[str, Set[str]], mpu: bool, keep: Optional[str]) -> List[str]:
    trap = name in TRAPS
    asm = os.path.join(tmp, name + ".nasm")
    run([sys.executable, NICEWASM, *OPTIONS.get(name, []), *([] if mpu else ["--no-mpu"]),
         "-o", asm, wasm_file])
    hand = os.path.join(HERE, name + ".nasm")
    if os.path.exists(hand):
        with open(hand) as f:
            extra += f.read()
    with open(asm) as f:
        text = f.read()
    parts = [os.path.join(RUNTIME, "start_wasm.nasm"), None, asm, os.path.join(RUNTIME, "lib.nasm"),
             os.path.join(RUNTIME, "muldiv_mpu.nasm" if mpu else "muldiv_soft.nasm")]
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
    errors = assembler.run(lines, name + ".full.nasm")
    if errors:
        raise RuntimeError("\n".join(errors))
    image = dict(assembler.output())
    binary = os.path.join(tmp, name + ".bin")
    with open(binary, "w") as f:
        f.writelines(f"{a:08x} {w:08x}\n" for a, w in sorted(image.items()))
    if keep is not None:
        shutil.copy(binary, os.path.join(keep, name + ("" if mpu else "_soft") + ".bin"))
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
    if not trap:
        # A trap leaves the frames, and the locals in R7-R11, as they were.
        wanted.update({f"R{i}": 0 for i in range(7, 12)})
        wanted.update({"R12": 0, "R13": 0xFFFFFF00})
    problems = []
    if name in SHAPES:
        pattern, must = SHAPES[name]
        bare = "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith(";"))
        if bool(re.search(pattern, bare, re.M)) != must:
            problems.append(f"the code {'does not match' if must else 'matches'} {pattern}")
    if console != CONSOLE.get(name, ""):
        problems.append(f"printed {console!r}, expected {CONSOLE.get(name, '')!r}")
    mem = assembler.labels.get("___wasm_memory")
    if mem is not None and all(a in image for a in range(mem, mem + 16384)):
        problems.append("the memory is in the program image")
    if trap:
        if (not output.startswith("Halted (reserved control instruction)")
                or not output.endswith("exit 2\n")):
            problems.append("did not halt at ___wasm_trap")
        r2 = regs.get("R2", 0)
        first = assemble(TRAPS[name].format(R2=r2), tmp, assembler.labels)
        if not first or [image.get(r2 + i) for i in range(len(first))] != first:
            problems.append(f"R2 does not point at {TRAPS[name].format(R2=hex(r2))}")
    elif not output.startswith("Halted (HALT)") or not output.endswith("exit 0\n"):
        problems.append("did not halt with HALT")
    for reg, value in wanted.items():
        if regs.get(reg) != value:
            problems.append(f"{reg} is {regs.get(reg, 0):08x}, expected {value:08x}")
    if problems:
        problems.append(output)
    return problems


def run_case(tmp: str, keep: Optional[str], index: int, name: str, wasm: Union[bytes, str], extra: str,
             expected: int, floats: Tuple[str, Set[str]], mpu: bool) -> List[str]:
    """Runs one case in a directory of its own under tmp, so that the
    cases can go in parallel. Returns the problems, as check does."""
    work = os.path.join(tmp, f"{'mpu' if mpu else 'soft'}{index}")
    os.mkdir(work)
    if isinstance(wasm, bytes):
        wasm_file = os.path.join(work, FILE_NAMES.get(name, name + ".wasm"))
        with open(wasm_file, "wb") as f:
            f.write(wasm)
    else:
        wasm_file = os.path.join(HERE, wasm + ".wasm")
    try:
        return check(name, wasm_file, extra, expected, work, floats, mpu, keep)
    except RuntimeError as e:
        return [str(e)]


def main() -> None:
    # --keep DIR copies each program to DIR/X.bin, or DIR/X_soft.bin with
    # --no-mpu, for the tests of the FPGA core in hdl/.
    keep = None
    if sys.argv[1:2] == ["--keep"] and len(sys.argv) == 3:
        keep = sys.argv[2]
        os.makedirs(keep, exist_ok=True)
    elif len(sys.argv) != 1:
        sys.exit("usage: run.py [--keep DIR]")
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        jobs: List[Tuple[int, str, Union[bytes, str], str, int, Tuple[str, Set[str]], bool]] = []
        for mpu in (True, False):
            floats = float_library(tmp, mpu)
            for index, (name, wasm, extra, expected) in enumerate(CASES):
                jobs.append((index, name, wasm, extra, expected, floats, mpu))
        # The cases run in parallel, and are reported in order.
        with concurrent.futures.ThreadPoolExecutor(os.cpu_count()) as pool:
            results = pool.map(lambda job: run_case(tmp, keep, *job), jobs)
            for (_, name, _, _, _, _, mpu), problems in zip(jobs, results):
                suffix = "" if mpu else " (--no-mpu)"
                if problems:
                    failed += 1
                    print(f"FAIL {name}{suffix}")
                    for p in problems:
                        print("  " + p.rstrip().replace("\n", "\n  "))
                else:
                    print(f"PASS {name}{suffix}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
