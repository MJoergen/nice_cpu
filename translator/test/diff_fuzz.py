#!/usr/bin/env python3
"""A random test of nicewasm against an older version of itself.

Usage: diff_fuzz.py [--old REV] [--trap] [--no-mpu] [--grow] [--unchecked]
                    [--library] [--floats] [--inline-fpu] FIRST COUNT

Each case is a module that both versions translate. The two programs are
joined with the runtime, assembled, and run, and they must agree on the
console output, the halt reason, the exit status, R1, R7 to R13 after a
normal halt, and every word of the linear memory. A trap's R2 may differ
between versions, so it is not compared. REV is a git revision whose
nicewasm.py is the older version, main by default, or the path of a
nicewasm.py. Seeds FIRST to FIRST + COUNT - 1 are tried, in parallel, a
process for each CPU, and reported in order.

The modules are those of fuzz.py without its tail calls, which a
version before them rejects. Without --trap, the new
translation's R1, or its trap code, is also checked against fuzz.py's
model. With --trap, each module gets a few more statements that may trap,
which the model does not know: loads and stores out of bounds, at constant addresses,
through locals, and as (i << s) + c with masked and with huge indices;
groups of word accesses from one local near the end of the memory;
divisions and remainders by zero and by masked divisors, and of the most
negative value by -1; call_indirect with a bad index or a bad type;
memory.fill and memory.copy past the end and wrapping; a conditional
unreachable; with --grow, memory.grow and accesses to the new page; and
with floats, trunc of a NaN or of a value out of range, and float loads
and stores among the others. So the trap paths are compared too, which
fuzz.py cannot check.

With --floats, every module has the floats of fuzz.py's odd seeds, and
a program that calls the float library is joined with it, as fuzz.py
joins it: float_fpu.nasm, or with --no-mpu float.wasm translated with
--no-mpu. Both versions run with the same library, so a NaN's bits are
the same in both, and are compared too.

--no-mpu, --grow (--memory-pages 2), --unchecked (--no-bounds-checks),
--library (--library lib --memory-bytes 65536), and --inline-fpu, which
implies --floats, are the modes of nicewasm that both versions run in.
--library takes no floats, as a library module may not call the float
library (WASM.md). A module whose translations differ
is written to diff_SEED.wasm in the current directory.

make diff runs a few hundred modules against OLD, main by default. This
test found no difference between the translator of 2026-10-15 and that
of 2026-10-19 on 1300 modules; it is for the next change."""

from __future__ import annotations

import concurrent.futures
import functools
import os
import random
import subprocess
import sys
import tempfile
from typing import Dict, List, Optional, Tuple

import fuzz
from wasm import (ADD, END, F32, F64, I32, I64, MEMORY_COPY, MEMORY_FILL, MEMORY_GROW, MEMORY_SIZE, SHL,
                  UNREACHABLE, call_indirect, if_, local_get, local_set, local_tee, mem)
from wasm import i32_const as _i32_const
from wasm import i64_const as _i64_const

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(TOP, "assembler"))
import niceasm  # noqa: E402

NEW = os.path.join(HERE, "..", "nicewasm.py")
RUNTIME = os.path.join(TOP, "runtime")
NICEEMU = os.path.join(TOP, "emulator", "zig-out", "bin", "niceemu")
PAGE = 0x10000


def i32_const(v: int) -> bytes:
    return _i32_const(fuzz.s32(v))


def i64_const(v: int) -> bytes:
    return _i64_const(fuzz.s64(v))


DIV_OPS32 = {"div_s": 0x6D, "div_u": 0x6E, "rem_s": 0x6F, "rem_u": 0x70}
DIV_OPS64 = {"div_s": 0x7F, "div_u": 0x80, "rem_s": 0x81, "rem_u": 0x82}
AND32, AND64, OR32, OR64 = b"\x71", b"\x83", b"\x72", b"\x84"


def nop(st: fuzz.State) -> None:
    """The model's part of a statement that may trap: nothing, since the
    model is not used in trap mode."""


def trap_stmt(ctx: fuzz.Ctx, rng: random.Random, grow: bool) -> fuzz.Stmt:
    """A statement that may trap."""
    kinds = ["load", "store", "load", "store", "div", "divmin", "indirect", "fill", "copy",
             "unreachable", "group"]
    if grow:
        kinds += ["grow", "grow", "growload"]
    if ctx.floats:
        kinds += ["trunc", "trunc"]
    kind = rng.choice(kinds)
    top = 2 * PAGE if grow else PAGE

    def addr_expr() -> bytes:
        r = rng.random()
        if r < 0.25:
            a = rng.choice([top - 1, top - 2, top - 3, top - 4, top - 5, top - 7, top - 8,
                            top - 9, top, top + 1, top + 4, 0xFFFFFFFF, 0xFFFFFFFC, 0xFFFFFFF0,
                            0x80000000, 0x7FFFFFFF, rng.randrange(top - 64, top + 64)])
            return i32_const(a)
        if r < 0.55:
            # The address in a local.
            a = rng.choice([top - 1, top - 2, top - 4, top - 8, top, top + 4, 0xFFFFFFFC,
                            0xFFFFFFF0, rng.randrange(top - 64, top + 64), rng.randrange(0, top)])
            return i32_const(a) + local_tee(rng.choice(ctx.locals_of(I32)))
        if r < 0.8:
            # (i << s) + c near or past the end, with the index in a local,
            # maybe masked.
            s = rng.choice([2, 2, 3])
            i_val = rng.choice([0, 1, 2, 3, 7, 0x3FFF, 0x4000, 0x40000000, 0xFFFFFFFF,
                                rng.randrange(0, PAGE)])
            c = rng.choice([top - (i_val << s) - rng.randrange(0, 16),
                            top - 4, top, top + 4, rng.randrange(-0x40, 0x40) * 4,
                            rng.randrange(-0x40, 0x40) * 4 + rng.randrange(1, 4)]) & 0xFFFFFFFF
            e = i32_const(i_val) + local_tee(rng.choice(ctx.locals_of(I32)))
            if rng.random() < 0.5:
                e += i32_const(rng.choice([3, 0xFF, 0x3FFF, 0xFFFF, 0x7FFFFFFF])) + AND32
            return e + i32_const(s) + SHL + i32_const(fuzz.s32(c)) + ADD
        # Any expression of the generator, which may be out of bounds.
        return fuzz.gen_expr(ctx, I32, 2).code

    if kind in ("load", "store"):
        offset = rng.choice([0, 0, 1, 4, 8, 13, 0xFFFC, PAGE, 0xFFFFFFF0])
        loads = fuzz.ALL_LOADS if ctx.floats else fuzz.LOADS
        stores = fuzz.ALL_STORES if ctx.floats else fuzz.STORES
        if kind == "load":
            op = rng.choice(list(loads))
            j = rng.choice(ctx.locals_of(loads[op][0]))
            return fuzz.Stmt(addr_expr() + mem(op, offset) + local_set(j), nop)
        op = rng.choice(list(stores))
        v = fuzz.gen_expr(ctx, stores[op][0], 2)
        return fuzz.Stmt(addr_expr() + v.code + mem(op, offset), nop)
    if kind == "group":
        # Several word accesses from one local, as share_checks groups them.
        base = rng.choice(ctx.locals_of(I32))
        start = rng.choice([top - 4, top - 8, top - 12, top - 16, top - 9, top - 6, top, 0xFFFFFFF8,
                            rng.randrange(top - 32, top)])
        code = i32_const(start) + local_set(base)
        for _ in range(rng.randrange(2, 5)):
            offset = rng.choice([0, 4, 8, 12])
            if rng.random() < 0.5:
                op = rng.choice([0x28, 0x29, 0x34, 0x35])
                j = rng.choice([x for x in ctx.locals_of(fuzz.LOADS[op][0]) if x != base])
                code += local_get(base) + mem(op, offset) + local_set(j)
            else:
                op = rng.choice([0x36, 0x37, 0x3E])
                code += local_get(base) + fuzz.gen_expr(ctx, fuzz.STORES[op][0], 1).code + mem(op, offset)
            if rng.random() < 0.3:
                code += fuzz.gen_set(ctx, 1).code
        return fuzz.Stmt(code, nop)
    if kind == "div":
        t = rng.choice([I32, I64])
        op = (DIV_OPS32 if t == I32 else DIV_OPS64)[rng.choice(list(DIV_OPS32))]
        konst = i32_const if t == I32 else i64_const
        num = fuzz.gen_expr(ctx, t, 2).code
        r = rng.random()
        if r < 0.4:
            den = konst(0)
        elif r < 0.7:
            den = fuzz.gen_expr(ctx, t, 2).code + konst(rng.choice([0, 1, 3])) + (AND32 if t == I32 else AND64)
        else:
            den = fuzz.gen_expr(ctx, t, 2).code
        return fuzz.Stmt(num + den + bytes([op]) + local_set(rng.choice(ctx.locals_of(t))), nop)
    if kind == "divmin":
        t = rng.choice([I32, I64])
        op = (DIV_OPS32 if t == I32 else DIV_OPS64)[rng.choice(["div_s", "rem_s"])]
        konst = i32_const if t == I32 else i64_const
        least = -(1 << (fuzz.bits(t) - 1))
        num = konst(least) if rng.random() < 0.7 else fuzz.gen_expr(ctx, t, 2).code
        if rng.random() < 0.5:
            num += local_tee(rng.choice(ctx.locals_of(t)))
        if rng.random() < 0.5:
            den = konst(-1)
        else:
            den = fuzz.gen_expr(ctx, t, 2).code + konst(-1) + (OR32 if t == I32 else OR64)
        return fuzz.Stmt(num + den + bytes([op]) + local_set(rng.choice(ctx.locals_of(t))), nop)
    if kind == "indirect":
        # The table has entries 0 to 2, functions 1 to 3. Only a later
        # function, so that nothing recurses, or an index past the table.
        idx = rng.choice(list(range(ctx.fidx, 3)) + [3, 4, 100, 0xFFFFFFFF, 0x80000000])
        type_idx = rng.choice([1, 2, 3])
        fn_types = {1: ([I32, I64, I32, I32], I32), 2: ([I64, I32], I64), 3: ([I32, I32], I32)}
        params, result = fn_types[type_idx]
        args = b"".join(fuzz.gen_expr(ctx, p, 1).code for p in params)
        ie = i32_const(idx)
        if rng.random() < 0.5:
            ie += local_tee(rng.choice(ctx.locals_of(I32)))
        return fuzz.Stmt(args + ie + call_indirect(type_idx) + local_set(rng.choice(ctx.locals_of(result))),
                         nop)
    if kind in ("fill", "copy"):
        d = rng.choice([0, 100, top - 16, top - 4, top - 1, top, 0xFFFFFFFF, 0xFFFFFFF0])
        n = rng.choice([0, 1, 3, 4, 5, 16, 17, PAGE, 0xFFFFFFFF])
        if kind == "fill":
            return fuzz.Stmt(i32_const(d) + fuzz.gen_expr(ctx, I32, 1).code + i32_const(n) + MEMORY_FILL, nop)
        s2 = rng.choice([0, 7, top - 16, top - 5, top, 0xFFFFFFFE])
        return fuzz.Stmt(i32_const(d) + i32_const(s2) + i32_const(n) + MEMORY_COPY, nop)
    if kind == "trunc":
        # trunc of a value at the edges of the conversions or of any value,
        # which traps for a NaN or a value out of range.
        t, ft, signed = rng.choice([I32, I64]), rng.choice([F32, F64]), rng.random() < 0.5
        a = (fuzz.konst(ft, rng.choice(fuzz.float_specials(ft))) if rng.random() < 0.5
             else fuzz.gen_expr(ctx, ft, 2))
        conv = fuzz.trunc_expr(t, ft, signed, a, False)
        return fuzz.Stmt(conv.code + local_set(rng.choice(ctx.locals_of(t))), nop)
    if kind == "unreachable":
        return fuzz.Stmt(fuzz.gen_condition(ctx, 2).code + if_() + UNREACHABLE + END, nop)
    if kind == "grow":
        e = i32_const(rng.choice([0, 1, 1, 2, 3, 0xFFFFFFFF])) + MEMORY_GROW
        e += local_set(rng.choice(ctx.locals_of(I32)))
        if rng.random() < 0.5:
            e += MEMORY_SIZE + local_set(rng.choice(ctx.locals_of(I32)))
        return fuzz.Stmt(e, nop)
    # growload: an access in page 1, which traps before the grow and not after.
    addr = rng.choice([PAGE, PAGE + 4, 2 * PAGE - 4, 2 * PAGE - 8, 2 * PAGE - 3, PAGE - 2])
    op = rng.choice([0x28, 0x29, 0x2D, 0x2F])
    i = rng.choice(ctx.locals_of(I32))
    e = i32_const(addr) + local_tee(i) + mem(op, rng.choice([0, 4, 8]))
    e += local_set(rng.choice(ctx.locals_of(fuzz.LOADS[op][0])))
    if rng.random() < 0.5:
        e += local_get(i) + fuzz.gen_expr(ctx, I32, 1).code + mem(0x36, 0)
    return fuzz.Stmt(e, nop)


def trap_module(seed: int, grow: bool, floats: bool) -> bytes:
    """fuzz.py's module for the seed, with statements that may trap put
    into its functions."""
    fns, segment = fuzz.build(seed, tails=False, floats=floats)
    rng = random.Random(seed * 7919 + 1)
    for idx, fn in enumerate(fns):
        ctx = fuzz.Ctx(rng, fn, idx, fns, floats=floats)
        for _ in range(rng.randrange(1, 4) if idx == 0 else rng.randrange(0, 3)):
            # Sometimes under a condition, so that some paths do not trap.
            # Its label is in scope while the statement is made, so that a
            # branch in the statement counts it.
            cond = fuzz.gen_condition(ctx, 2) if rng.random() < 0.4 else None
            if cond is not None:
                ctx.labels.append(("if", []))
            st = trap_stmt(ctx, rng, grow)
            if cond is not None:
                ctx.labels.pop()
                st = fuzz.Stmt(cond.code + if_() + st.code + END, st.run)
            fn.stmts.insert(rng.randrange(0, len(fn.stmts) + 1), st)
    mod, _, _ = fuzz.finish(fns, segment, floats)
    return mod


def translate(tool: str, wasm_file: str, asm: str, opts: List[str]) -> Optional[str]:
    """Runs a translator. Returns its message if it failed."""
    p = subprocess.run([sys.executable, tool, *opts, "-o", asm, wasm_file],
                       capture_output=True, text=True)
    return None if p.returncode == 0 else p.stdout + p.stderr


class Run:
    """What a program did: the console output, the halt line, the
    registers, the words of the linear memory, and the exit status."""

    def __init__(self, console: str, halt: str, regs: Dict[str, int], words: List[int],
                 status: int) -> None:
        self.console, self.halt, self.regs, self.words, self.status = console, halt, regs, words, status


def build_and_run(asm: str, name: str, tmp: str, nompu: bool, pages: int, library: bool,
                  floats: fuzz.Library) -> Run:
    """Joins a translation with the runtime as run.py does, and with the
    float library if it calls it, assembles it, and runs it with the
    linear memory dumped."""
    parts = [os.path.join(RUNTIME, "start.nasm" if library else "start_wasm.nasm"), asm,
             os.path.join(RUNTIME, "lib.nasm"),
             os.path.join(RUNTIME, "muldiv_soft.nasm" if nompu else "muldiv_mpu.nasm")]
    with open(asm) as f:
        text = f.read()
    if any(label in text for label in floats[1]):
        parts.append(floats[0])
    lines: List[str] = []
    for part in parts:
        with open(part) as f:
            lines += f.readlines()
    assembler = niceasm.Assembler()
    errors = assembler.run(lines, name + ".full.nasm")
    if errors:
        raise RuntimeError("\n".join(errors))
    binary = os.path.join(tmp, name + ".bin")
    with open(binary, "w") as f:
        f.writelines(f"{a:08x} {w:08x}\n" for a, w in sorted(dict(assembler.output()).items()))
    membase = assembler.labels["WL.lib.memory" if library else "___wasm_memory"]
    p = subprocess.run([NICEEMU, "-n", "30000000", "-d", f"{membase}:{pages * PAGE // 4}", binary],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True)
    out = p.stdout
    at = out.find("Halted (")
    if at < 0:
        return Run(out, "no halt", {}, [], p.returncode)
    rest = out[at:].splitlines()
    regs: Dict[str, int] = {}
    for line in rest[1:5]:
        tok = line.split()
        for i in range(0, len(tok) - 1, 2):
            regs[tok[i]] = int(tok[i + 1], 16)
    words: List[int] = []
    for line in rest[5:]:
        tok = line.replace(":", " ").split()
        if tok and all(len(t) == 8 for t in tok):
            words += [int(t, 16) for t in tok[1:]]  # the first is the address
    return Run(out[:at], rest[0].split(" after ")[0], regs, words, p.returncode)


def compare(seed: int, mod: bytes, old: str, tmp: str, nompu: bool, opts: List[str], pages: int,
            expected: Optional[fuzz.Outcome], floats: fuzz.Library) -> Tuple[Optional[str], Optional[Run]]:
    """Translates the module with both versions and compares the runs.
    Returns what differs, or None, and the new translation's run."""
    wasm_file = os.path.join(tmp, f"m{seed}.wasm")
    with open(wasm_file, "wb") as f:
        f.write(mod)
    runs: Dict[str, Run] = {}
    for tag, tool in (("old", old), ("new", NEW)):
        asm = os.path.join(tmp, f"m{seed}_{tag}.nasm")
        err = translate(tool, wasm_file, asm, (["--no-mpu"] if nompu else []) + own(tool, opts))
        if err is not None:
            return f"seed {seed}: the {tag} translator: {err.strip()}", None
        try:
            runs[tag] = build_and_run(asm, f"m{seed}_{tag}", tmp, nompu, pages, "--library" in opts, floats)
        except RuntimeError as e:
            return f"seed {seed}: the {tag} translation: {e}", None
    o, n = runs["old"], runs["new"]
    problems = []
    if o.console != n.console:
        problems.append(f"console old {o.console!r} new {n.console!r}")
    if o.halt != n.halt:
        problems.append(f"halt old {o.halt!r} new {n.halt!r}")
    if o.status != n.status:
        problems.append(f"exit old {o.status} new {n.status}")
    if o.regs.get("R1") != n.regs.get("R1"):
        problems.append(f"R1 old {o.regs.get('R1', -1):#x} new {n.regs.get('R1', -1):#x}")
    if n.halt.startswith("Halted (HALT)"):
        for r in ["R7", "R8", "R9", "R10", "R11", "R12", "R13"]:
            if o.regs.get(r) != n.regs.get(r):
                problems.append(f"{r} old {o.regs.get(r, -1):#x} new {n.regs.get(r, -1):#x}")
    if expected is not None:
        got: Optional[fuzz.Outcome] = None
        if "R1" in n.regs and n.halt.startswith("Halted (HALT)"):
            got = ("value", n.regs["R1"])
        elif "R1" in n.regs and n.halt.startswith("Halted (reserved control instruction)"):
            got = ("trap", n.regs["R1"])
        if got != expected:
            problems.append(f"the model expected {fuzz.show(expected)}, the new translation gave "
                            f"{fuzz.show(got)}")
    if len(o.words) != len(n.words):
        problems.append(f"memory words old {len(o.words)} new {len(n.words)}")
    else:
        diffs = [(i, a, b) for i, (a, b) in enumerate(zip(o.words, n.words)) if a != b]
        if diffs:
            problems.append(f"the memory differs in {len(diffs)} words, first {diffs[:3]}")
    if not n.words:
        problems.append("no memory dump")
    if problems:
        keep = f"diff_{seed}.wasm"
        with open(keep, "wb") as f:
            f.write(mod)
        return f"seed {seed} ({n.halt}): " + "; ".join(problems) + f", kept as {keep}", n
    return None, n


def own(tool: str, opts: List[str]) -> List[str]:
    """The options in the names that the translator in the file tool
    takes: one from before --memory-bytes took --library-memory."""
    with open(tool) as f:
        if "--memory-bytes" in f.read():
            return opts
    return ["--library-memory" if o == "--memory-bytes" else o for o in opts]


def old_translator(rev: str, tmp: str) -> str:
    """The older nicewasm.py: a file, or the one of a git revision."""
    if os.path.exists(rev):
        return rev
    p = subprocess.run(["git", "-C", TOP, "show", f"{rev}:translator/nicewasm.py"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"diff_fuzz.py: no nicewasm.py at {rev}: {p.stderr.strip()}")
    path = os.path.join(tmp, "nicewasm_old.py")
    with open(path, "w") as f:
        f.write(p.stdout)
    return path


def one(seed: int, args: List[str], tool: str, tmp: str, opts: List[str], pages: int,
        library: fuzz.Library) -> Tuple[Optional[str], Optional[str]]:
    """Builds and compares the module of one seed, in a process of its own.
    Returns what differs, or None, and how the new translation's run
    ended, or None."""
    trap, nompu, grow = "--trap" in args, "--no-mpu" in args, "--grow" in args
    floats = "--floats" in args or "--inline-fpu" in args
    if trap:
        mod, expected = trap_module(seed, grow, floats), None
    else:
        fns, segment = fuzz.build(seed, "--unchecked" not in args, tails=False, floats=floats)
        mod, expected, _ = fuzz.finish(fns, segment, floats)
    problem, run = compare(seed, mod, tool, tmp, nompu, opts, pages, expected, library)
    if run is None:
        return problem, None
    return problem, run.halt if not run.halt.startswith("Halted (reserved") else f"trap {run.regs.get('R1')}"


def main() -> None:
    args = sys.argv[1:]
    flags = {"--trap", "--no-mpu", "--grow", "--unchecked", "--library", "--floats", "--inline-fpu"}
    old = "main"
    if "--old" in args:
        k = args.index("--old")
        if k + 1 >= len(args):
            sys.exit("diff_fuzz.py: --old needs a revision")
        old = args[k + 1]
        del args[k:k + 2]
    numbers = [a for a in args if not a.startswith("--")]
    if len(numbers) != 2 or any(a not in flags for a in args if a.startswith("--")):
        sys.exit(__doc__.split("\n\n")[1])
    first, count = int(numbers[0]), int(numbers[1])
    nompu, grow = "--no-mpu" in args, "--grow" in args
    floats = "--floats" in args or "--inline-fpu" in args
    if floats and "--library" in args:
        sys.exit("diff_fuzz.py: --library takes no floats: a library module may not call the float library")
    opts: List[str] = []
    pages = 1
    if grow:
        opts += ["--memory-pages", "2"]
        pages = 2
    if "--unchecked" in args:
        opts += ["--no-bounds-checks"]
    if "--library" in args:
        opts += ["--library", "lib", "--memory-bytes", str(PAGE)]
    if "--inline-fpu" in args:
        opts += ["--inline-fpu"]
    halts: Dict[str, int] = {}
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        tool = old_translator(old, tmp)
        library = fuzz.float_library(tmp, ["--no-mpu"] if nompu else [])
        # The seeds run in processes of their own, as they build and assemble
        # in Python, each with files of its own name, and report in order.
        work = functools.partial(one, args=args, tool=tool, tmp=tmp, opts=opts, pages=pages, library=library)
        with concurrent.futures.ProcessPoolExecutor(os.cpu_count()) as pool:
            for problem, key in pool.map(work, range(first, first + count)):
                if problem is not None:
                    failures += 1
                    print("FAIL " + problem, flush=True)
                if key is not None:
                    halts[key] = halts.get(key, 0) + 1
    modes = " ".join(a for a in args if a.startswith("--"))
    ends = ", ".join(f"{v} {k}" for k, v in sorted(halts.items()))
    print(f"{'FAIL' if failures else 'PASS'} diff_fuzz against {old} ({count} cases{', ' + modes if modes else ''}): "
          f"{ends}")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
