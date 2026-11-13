#!/usr/bin/env python3
"""Checks float_fpu.nasm against float.nasm, the float library in software.

Usage: float_fpu.py [--seed N] [--count N] [--keep DIR]

One program calls every routine of the float library on special operands,
each with each, and on random ones: values near the integers, the ties of
the rounding, and the limits of the conversions. It runs twice, joined
with float.nasm and then with float_fpu.nasm, which uses the FPU of
SYSTEM.md §11. The results must be the same, but that a NaN may be any
NaN: float.nasm passes the payload of a NaN on, and the FPU gives the
canonical NaN, which wasm allows. After the calls, the program reads the
FPU's STATUS, whose depth must be 0 with float_fpu.nasm: a routine leaves
the stack as it found it.

It runs a third time with the float operations that nicewasm's
--inline-fpu writes inline: a wasm module has a function for each
routine, which does the wasm instruction that calls it, trunc_sat for a
conversion to an integer, translated with --inline-fpu, and the program
calls those functions instead. A comparison gives 0 or 1 there, which
must be the test of the routine's result. With --keep DIR, the program with float_fpu.nasm
is left in DIR/float_fpu.bin for the tests of the FPGA cores.
"""

import argparse
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
from typing import Dict, List, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME = os.path.dirname(HERE)
ROOT = os.path.dirname(RUNTIME)
NICEASM = os.path.join(ROOT, "assembler", "niceasm.py")
NICEEMU = os.environ.get("NICEEMU", os.path.join(ROOT, "emulator", "zig-out", "bin", "niceemu"))
NICEWASM = os.path.join(ROOT, "translator", "nicewasm.py")
sys.path.insert(0, os.path.join(ROOT, "translator"))
sys.path.insert(0, os.path.join(ROOT, "translator", "test"))
import nicewasm  # noqa: E402
import wasm  # noqa: E402

# The routines: label -> (the types of the operands, the type of the
# result). f is an f32, d an f64, i a word, and l a long long.
ROUTINES: Dict[str, Tuple[str, str]] = {}
for _s, _t in (("sf", "f"), ("df", "d")):
    for _n in ("add", "sub", "mul", "div"):
        ROUTINES[f"___{_n}{_s}3"] = (_t + _t, _t)
    for _n in ("min", "max"):
        ROUTINES[f"___{_n}{_s}"] = (_t + _t, _t)
    for _n in ("sqrt", "ceil", "floor", "trunc", "nearest"):
        ROUTINES[f"___{_n}{_s}"] = (_t, _t)
    for _n in ("eq", "ne", "lt", "le", "gt", "ge"):
        ROUTINES[f"___{_n}{_s}2"] = (_t + _t, "i")
    for _from, _int, _i in (("si", "si", "i"), ("unsi", "unssi", "i"), ("di", "di", "l"),
                            ("undi", "unsdi", "l")):
        ROUTINES[f"___float{_from}{_s}"] = (_i, _t)
        _u = "uns" if "uns" in _int else ""
        ROUTINES[f"___fix{_u}{_s}{_int[-2:]}"] = (_t, _i)
ROUTINES["___extendsfdf2"] = ("f", "d")
ROUTINES["___truncdfsf2"] = ("d", "f")
WORDS = {"f": 1, "i": 1, "d": 2, "l": 2}

F32_SPECIALS = [0x00000000, 0x80000000, 0x00000001, 0x80000001, 0x007FFFFF, 0x00800000,
                0x7F7FFFFF, 0xFF7FFFFF, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000,
                0x7F800001, 0x7FC12345, 0x3F800000, 0xBF800000, 0x3FC00000, 0xC0200000,
                0x3F000000, 0x40400000, 0x4B000001, 0x4EFFFFFF, 0x4F000000, 0xCF000000,
                0xCF000001, 0x4F800000, 0x5F000000, 0xDF000000, 0x5F800000, 0xBF7FFFFF]
F64_SPECIALS = [0x0000000000000000, 0x8000000000000000, 0x0000000000000001, 0x8000000000000001,
                0x000FFFFFFFFFFFFF, 0x0010000000000000, 0x7FEFFFFFFFFFFFFF, 0xFFEFFFFFFFFFFFFF,
                0x7FF0000000000000, 0xFFF0000000000000, 0x7FF8000000000000, 0xFFF8000000000000,
                0x7FF0000000000001, 0x7FF8000012345678, 0x3FF0000000000000, 0xBFF0000000000000,
                0x3FF8000000000000, 0xC004000000000000, 0x3FE0000000000000, 0x4330000000000001,
                0x41DFFFFFFFC00000, 0x41E0000000000000, 0xC1E0000000000000, 0xC1E0000000200000,
                0x41EFFFFFFFE00000, 0x41F0000000000000, 0x43E0000000000000, 0xC3E0000000000000,
                0x43F0000000000000, 0x36A0000000000000, 0x47EFFFFFE0000000, 0x47EFFFFFF0000000,
                0x3810000000000000, 0x380FFFFFF0000000]
I64_SPECIALS = [0, 1, (1 << 64) - 1, 1 << 63, (1 << 63) - 1, (1 << 24) + 1, (1 << 53) - 1,
                1 << 53, (1 << 53) + 1, (1 << 54) + 3, 0x7FFFFF8000000000, 0x7FFFFFC000000000,
                0xFFFFFF8000000000, 0xFFFFFF7FFFFFFFFF, (1 << 64) - (1 << 53) - 1, 0x00FFFFFF80000001,
                0x0000000100000000, 0xFFFFFFFF00000000, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
                0xFFFFFFFF80000000,
                # Above 2^53, a tie of the rounding to binary32 with a 1 in
                # bit 0, which a conversion through binary64 loses: kept
                # part even, which rounds down without the sticky bit, odd,
                # and their negatives.
                (1 << 60) | (1 << 36) | 1, (1 << 60) | (3 << 36) | 1,
                (1 << 63) | (1 << 39) | 1, (1 << 54) | (1 << 30) | 1,
                -((1 << 60) | (1 << 36) | 1) & ((1 << 64) - 1),
                -((1 << 62) | (1 << 38) | 1) & ((1 << 64) - 1),
                (1 << 60) | (1 << 36) | (1 << 10), (1 << 60) | (1 << 36) - 1]


def random_f32(r: random.Random) -> int:
    k = r.randrange(6)
    if k == 0:
        return r.getrandbits(32)
    if k == 1:  # a small integer, or a half
        v = r.randrange(-300, 300) / r.choice([1, 2, 4])
        return int.from_bytes(struct.pack(">f", v), "big")
    if k == 2:  # near the limits of the conversions and the integers
        return (r.choice([0x4B, 0x4E, 0x4F, 0x5E, 0x5F, 0xCE, 0xCF, 0xDE, 0xDF, 0x4A, 0x3F, 0xBF]) << 24
                | r.getrandbits(24))
    if k == 3:  # a subnormal or near one
        return r.getrandbits(1) << 31 | r.randrange(0, 0x01000000)
    return r.getrandbits(1) << 31 | r.randrange(0x30000000, 0x50000000)


def random_f64(r: random.Random) -> int:
    k = r.randrange(6)
    if k == 0:
        return r.getrandbits(64)
    if k == 1:
        v = r.randrange(-3000, 3000) / r.choice([1, 2, 4, 8])
        return int.from_bytes(struct.pack(">d", v), "big")
    if k == 2:
        return (r.choice([0x433, 0x41D, 0x41E, 0x41F, 0x43D, 0x43E, 0x43F, 0xC1E, 0xC3E, 0x432, 0x3FF,
                          0x47E, 0x380, 0x381, 0x36A, 0x369]) << 52 | r.getrandbits(52))
    if k == 3:
        return r.getrandbits(1) << 63 | r.randrange(0, 1 << 54)
    if k == 4:  # a binary32 value, exact, or one ulp of binary32 and a half away
        b = int.from_bytes(struct.pack(">d", struct.unpack(">f", random_f32(
            r).to_bytes(4, "big"))[0]), "big")
        return (b + r.choice([0, 1 << 28, (1 << 28) - 1, (1 << 28) + 1, -(1 << 28)])) & ((1 << 64) - 1)
    return r.getrandbits(1) << 63 | r.randrange(0x3C00000000000000, 0x4400000000000000)


def random_i64(r: random.Random) -> int:
    k = r.randrange(5)
    if k == 0:
        return r.getrandbits(64)
    if k == 1:
        return r.randrange(-(1 << 31), 1 << 31) & ((1 << 64) - 1)
    if k == 2:  # near a tie of the rounding to binary32 or binary64
        s = r.randrange(25, 64)
        m = r.getrandbits(s)
        keep = r.choice([24, 53])
        if s <= keep:
            return m
        low = s - keep
        m = (m >> low << low) | (1 << (low - 1)) + r.choice([-1, 0, 0, 1])
        return (m if r.getrandbits(1) else -m) & ((1 << 64) - 1)
    if k == 3:
        return r.getrandbits(r.randrange(1, 64))
    return (-r.getrandbits(r.randrange(1, 64))) & ((1 << 64) - 1)


def operands(r: random.Random, t: str) -> int:
    if t == "f":
        return random_f32(r)
    if t == "d":
        return random_f64(r)
    v = random_i64(r)
    return v & 0xFFFFFFFF if t == "i" else v


def specials(t: str) -> List[int]:
    if t == "f":
        return F32_SPECIALS
    if t == "d":
        return F64_SPECIALS
    if t == "i":
        return sorted({v & 0xFFFFFFFF for v in I64_SPECIALS} | {0x4B000001, 0x01000001, 0xFF000001})
    return I64_SPECIALS


def cases(r: random.Random, args: str, count: int) -> List[Tuple[int, ...]]:
    """The operands of a routine: the specials, each with each, and random
    ones."""
    out: List[Tuple[int, ...]] = []
    if len(args) == 1:
        out += [(v,) for v in specials(args)]
    else:
        out += [(a, b) for a in specials(args[0]) for b in specials(args[1])]
    for _ in range(count):
        a = operands(r, args[0])
        if len(args) == 1:
            out.append((a,))
        elif r.randrange(4) == 0:  # close to a, for the cancellation
            out.append((a, a ^ r.getrandbits(r.randrange(1, 30)) ^ (r.getrandbits(1) << (WORDS[args[0]] * 32 - 1))))
        else:
            out.append((a, operands(r, args[1])))
    return out


def words(args: str, values: Tuple[int, ...]) -> List[int]:
    """The four words of R1 to R4 for the operands (ABI.md)."""
    out: List[int] = []
    for t, v in zip(args, values):
        out += [v & 0xFFFFFFFF] + ([v >> 32] if WORDS[t] == 2 else [])
    return out + [0] * (4 - len(out))


def program(calls: List[Tuple[str, List[int]]]) -> str:
    """The test's main: for each call, R1 to R4 from the table, the call,
    and R1 and R2 to the results; then STATUS."""
    lines = ["_main          MOVE    R10, TABLE",
             "                MOVE    R11, RESULTS",
             f"                MOVE    R9, {len(calls)}",
             ":               MOVE    R1, @R10++",
             "                MOVE    R2, @R10++",
             "                MOVE    R3, @R10++",
             "                MOVE    R4, @R10++",
             "                MOVE    R8, @R10++",
             "                CALL    R8",
             "                MOVE    @R11++, R1",
             "                MOVE    @R11++, R2",
             "                DEC[M]  R9, R9",
             "        ?!Z     JMP     :-",
             "                MOVE    @R11++, @0xFFFFFF8D  ; STATUS",
             "                MOVE    R1, R0",
             "                RET",
             "TABLE"]
    for label, w in calls:
        lines.append("                .DAT    " + ", ".join(f"0x{x:08X}" for x in w) + f", {label}")
    lines.append("RESULTS         .RES    " + str(2 * len(calls) + 1))
    return "\n".join(lines) + "\n"


# The wasm instruction of each routine, and for a comparison its test.
WASM_TYPES = {"f": wasm.F32, "d": wasm.F64, "i": wasm.I32, "l": wasm.I64}
OPCODES: Dict[str, bytes] = {}
TESTS: Dict[str, str] = {}
for _op, (_routine, _params, _result) in nicewasm.FLOAT_OPS.items():
    OPCODES["_" + _routine] = bytes([_op])
for _sat, _op in nicewasm.TRUNC_SAT_OPS.items():
    OPCODES["_" + nicewasm.TRUNC_OPS[_op][0]] = b"\xfc" + wasm.u(_sat - 0x100)
for _op, (_ctype, _routine, _test) in nicewasm.FLOAT_CMP_OPS.items():
    OPCODES["_" + _routine] = bytes([_op])
    TESTS["_" + _routine] = _test


def inline_module() -> bytes:
    """A wasm module with the function t_X for each routine ___X, which
    does the routine's wasm instruction on its parameters."""
    labels = sorted(ROUTINES)
    fts = []
    for label in labels:
        args, result = ROUTINES[label]
        res = "i" if label in TESTS else result
        fts.append(([WASM_TYPES[t] for t in args], [WASM_TYPES[res]]))
    bodies = []
    for label in labels:
        args, _ = ROUTINES[label]
        body = b"".join(wasm.local_get(i) for i in range(len(args))) + OPCODES[label]
        bodies.append((0, body))
    return wasm.module(wasm.types(*fts), wasm.funcs(*range(len(labels))),
                       wasm.exports(*[("t_" + label[3:], 0, i) for i, label in enumerate(labels)]),
                       wasm.code(*bodies))


def is_nan(t: str, v: int) -> bool:
    if t == "f":
        return (v & 0x7FFFFFFF) > 0x7F800000
    return t == "d" and (v & 0x7FFFFFFFFFFFFFFF) > 0x7FF0000000000000


def run(tmp: str, main: str, library: str, module: str = "") -> Tuple[List[int], int]:
    """Joins, assembles, and runs the program with the library, and the
    translated module if given, and returns the results and the address of
    RESULTS."""
    src = os.path.join(tmp, "prog.nasm")
    with open(src, "w") as f:
        for part in ["start_wasm.nasm" if module else "start.nasm", None, "lib.nasm",
                     "muldiv_mpu.nasm", library]:
            if part is None:
                f.write(main + module)
            else:
                with open(os.path.join(RUNTIME, part)) as p:
                    f.write(p.read())
    binary = os.path.join(tmp, library + (".inline" if module else "") + ".bin")
    subprocess.run([sys.executable, NICEASM, "-o", binary, "--symbols", os.path.join(tmp, "prog.sym"), src],
                   check=True)
    with open(os.path.join(tmp, "prog.sym")) as f:
        sym = dict((p[1], int(p[0], 16)) for p in (line.split() for line in f) if len(p) == 2)
    count = main.count(".DAT")
    base = sym["RESULTS"]
    proc = subprocess.run([NICEEMU, "-n", "200000000", "-d", f"0x{base:x}:{2 * count + 1}", binary],
                          capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if proc.returncode != 0:
        raise RuntimeError(f"{library}: exit {proc.returncode}\n{proc.stdout[-2000:]}{proc.stderr}")
    out: List[int] = []
    for line in proc.stdout.splitlines():
        head, _, rest = line.partition(":")
        if rest and len(head) == 8 and int(head, 16) >= base:
            out += [int(w, 16) for w in rest.split()]
    return out, base


def main() -> None:
    ap = argparse.ArgumentParser(description="float_fpu.nasm against float.nasm")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=300, help="random cases for each routine")
    ap.add_argument("--keep", help="leave the program with float_fpu.nasm in DIR/float_fpu.bin")
    args = ap.parse_args()
    r = random.Random(args.seed)
    calls: List[Tuple[str, List[int]]] = []
    meta: List[Tuple[str, str, Tuple[int, ...]]] = []
    for label in sorted(ROUTINES):
        types, result = ROUTINES[label]
        for values in cases(r, types, args.count):
            calls.append((label, words(types, values)))
            meta.append((label, result, values))
    main_text = program(calls)
    with tempfile.TemporaryDirectory() as tmp:
        soft, _ = run(tmp, main_text, "float.nasm")
        fpu, _ = run(tmp, main_text, "float_fpu.nasm")
        mod = os.path.join(tmp, "inline.wasm")
        with open(mod, "wb") as wf:
            wf.write(inline_module())
        subprocess.run([sys.executable, NICEWASM, "--inline-fpu", "-o", mod + ".nasm", mod], check=True)
        with open(mod + ".nasm") as nf:
            module_text = nf.read()
        inline_text = program([("_t_" + label[3:], w) for label, w in calls])
        inline, _ = run(tmp, inline_text, "float_fpu.nasm", module_text)
        if args.keep:
            os.makedirs(args.keep, exist_ok=True)
            shutil.copy(os.path.join(tmp, "float_fpu.nasm.bin"), os.path.join(args.keep, "float_fpu.bin"))
    failures: List[str] = []
    for i, (label, result, values) in enumerate(meta):
        if WORDS[result] == 2:
            a = soft[2 * i] | soft[2 * i + 1] << 32
            b = fpu[2 * i] | fpu[2 * i + 1] << 32
        else:
            a, b = soft[2 * i], fpu[2 * i]
        if a != b and not (is_nan(result, a) and is_nan(result, b)):
            ops = ", ".join(f"0x{v:X}" for v in values)
            failures.append(f"{label}({ops}): float.nasm 0x{a:X}, float_fpu.nasm 0x{b:X}")
        c = inline[2 * i] | (inline[2 * i + 1] << 32 if WORDS[result] == 2 and label not in TESTS else 0)
        if label in TESTS:
            signed = a - (1 << 32) if a >> 31 else a
            want = int({"==": signed == 0, "!=": signed != 0, "<": signed < 0, "<=": signed <= 0,
                        ">": signed > 0, ">=": signed >= 0}[TESTS[label]])
            if c != want:
                ops = ", ".join(f"0x{v:X}" for v in values)
                failures.append(f"{label}({ops}) inline: {c}, the routine's test {want}")
        elif a != c and not (is_nan(result, a) and is_nan(result, c)):
            ops = ", ".join(f"0x{v:X}" for v in values)
            failures.append(f"{label}({ops}): float.nasm 0x{a:X}, inline 0x{c:X}")
    for status, what in ((fpu[-1], "float_fpu.nasm"), (inline[-1], "inline")):
        if status & 0x1F != 0:
            failures.append(f"{what}: the FPU's depth after the calls is {status & 0x1F},"
                            f" STATUS 0x{status:08X}")
    for f in failures[:30]:
        print(f)
    if failures:
        print(f"FAIL float_fpu: {len(failures)} of {len(meta)} calls")
        sys.exit(1)
    print(f"PASS float_fpu ({len(meta)} calls of {len(ROUTINES)} routines, and inline)")


if __name__ == "__main__":
    main()
