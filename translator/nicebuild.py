#!/usr/bin/env python3
"""nicebuild - builds C, Zig, or Rust sources into a NICE .bin file.

Runs the steps of README.md: clang, zig, or rustc to wasm, nicewasm.py,
joining with the runtime, and niceasm.py. The language comes from the
extension of the inputs: .c, .zig, or .rs. C is linked with the C library of
runtime/libc, and Zig gets runtime/nice.zig as the module nice. Zig and Rust
take one source file, the root of the program.

Usage: nicebuild.py [-o output.bin] [-O LEVEL] [-I DIR] [-D MACRO[=VALUE]]
                    [--stack BYTES] [--memory BYTES] [--no-mpu] [--no-bounds-checks]
                    [--memory-pages N] [--keep] input.c... | input.zig | input.rs
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import List, Set

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RUNTIME = os.path.join(ROOT, "runtime")
LIBC = os.path.join(RUNTIME, "libc")


def run(cmd: List[str]) -> None:
    """Runs a command, and exits with its status if it fails."""
    try:
        status = subprocess.run(cmd).returncode
    except OSError as e:
        sys.exit(f"nicebuild: {cmd[0]}: {e.strerror}")
    if status != 0:
        sys.exit(f"nicebuild: {os.path.basename(cmd[0])} failed with status {status}")


def read(path: str) -> str:
    with open(path, encoding="latin-1") as f:
        return f.read()


LANGUAGES = {".c": "c", ".zig": "zig", ".rs": "rust"}


def language(inputs: List[str]) -> str:
    """The language of the inputs, from their extensions."""
    found = set()
    for path in inputs:
        ext = os.path.splitext(path)[1].lower()
        if ext not in LANGUAGES:
            sys.exit(f"nicebuild: {path}: unknown extension; expected .c, .zig, or .rs")
        found.add(LANGUAGES[ext])
    if len(found) > 1:
        sys.exit("nicebuild: the inputs are in more than one language")
    lang = found.pop()
    if lang != "c" and len(inputs) > 1:
        sys.exit(f"nicebuild: {lang} takes one source file, the root of the program")
    return lang


def float_labels(float_nasm: str) -> Set[str]:
    """The routines that float.nasm defines for a program to call."""
    return set(re.findall(r"^(__[A-Za-z0-9_]+)", float_nasm, re.M))


def write_symbols(sym: str, program: str, output: str) -> None:
    """Writes the labels of the assembler's file sym to output, but with the
    name of each wasm function, from the comment before it in program, in
    place of its label W.fN, and without the labels inside the functions."""
    names = {f"W.f{n}": name for n, name in re.findall(r"^; Function (\d+): (\S+)$", program, re.M)}
    lines = []
    for line in read(sym).splitlines():
        addr, label = line.split(" ", 1)
        if re.match(r"W\.f\d+\.", label):
            continue
        lines.append(f"{addr} {names.get(label, label)}")
    with open(output, "w", encoding="latin-1", newline="") as f:
        f.write("\n".join(lines) + "\n")


def compile_wasm(lang: str, args: argparse.Namespace, wasm: str) -> None:
    """Compiles the inputs to the wasm module in the file wasm."""
    if lang == "c":
        run([os.environ.get("CLANG", "clang"), "--target=wasm32", "-mbulk-memory",
             f"-O{args.opt or '2'}", "-ffreestanding",
             "-nostdlibinc", "-isystem", os.path.join(LIBC, "include"),
             *[f"-I{d}" for d in args.includes], *[f"-D{d}" for d in args.defines],
             "-nostdlib", "-Wl,--no-entry", "-Wl,--export=main", "-Wl,--stack-first",
             f"-Wl,-z,stack-size={args.stack or 4096}", f"-Wl,--initial-memory={args.memory}",
             "-o", wasm, *args.inputs, os.path.join(LIBC, "libc.a")])
    elif lang == "zig":
        mode = args.opt or "ReleaseSmall"
        stack = args.stack or (16384 if mode in ("Debug", "ReleaseSafe") else 4096)
        # --symbols needs the names of the functions, which ReleaseSmall and
        # -fstrip leave out of the wasm. nicewasm reads nothing else of what
        # -fno-strip keeps, so the .bin is the same either way.
        strip = "-fno-strip" if args.symbols else "-fstrip"
        run([os.environ.get("ZIG", "zig"), "build-exe", "-target", "wasm32-freestanding",
             "-fno-entry", "-rdynamic", "-O", mode, strip, "--stack", str(stack),
             f"--initial-memory={args.memory}", "--dep", "nice",
             f"-Mroot={args.inputs[0]}", f"-Mnice={os.path.join(RUNTIME, 'nice.zig')}",
             f"-femit-bin={wasm}"])
    else:
        run([os.environ.get("RUSTC", "rustc"), "--target", "wasm32-unknown-unknown",
             "--crate-type", "cdylib", "-C", f"opt-level={args.opt or 's'}", "-C", "panic=abort",
             "-C", "strip=debuginfo", "-C", f"link-arg=-zstack-size={args.stack or 4096}",
             "-C", f"link-arg=--initial-memory={args.memory}", "-o", wasm, args.inputs[0]])


def main() -> None:
    ap = argparse.ArgumentParser(description="Builds C, Zig, or Rust sources into a NICE .bin file.")
    ap.add_argument("inputs", nargs="+", metavar="input", help="C, Zig, or Rust source files")
    ap.add_argument("-o", dest="output",
                    help="output file (default: the first input with .bin extension)")
    ap.add_argument("-O", dest="opt", metavar="LEVEL",
                    help="optimization: a clang level (default 2), a Zig mode such as ReleaseSafe "
                    "(default ReleaseSmall), or a rustc opt-level (default s)")
    ap.add_argument("-I", dest="includes", action="append", default=[], metavar="DIR",
                    help="add DIR to the include path (C)")
    ap.add_argument("-D", dest="defines", action="append", default=[], metavar="MACRO[=VALUE]",
                    help="define a macro (C)")
    ap.add_argument("--stack", type=int, metavar="BYTES",
                    help="size of the program's stack in linear memory (default 4096, "
                    "16384 for Zig in Debug or ReleaseSafe)")
    ap.add_argument("--memory", type=int, default=65536, metavar="BYTES",
                    help="initial linear memory (default 65536, one page)")
    ap.add_argument("--no-mpu", action="store_true", help="translate for a system without the math unit")
    ap.add_argument("--no-bounds-checks", action="store_true", help="pass --no-bounds-checks to nicewasm")
    ap.add_argument("--memory-pages", type=int, metavar="N", help="pass --memory-pages to nicewasm")
    ap.add_argument("--no-trap-report", action="store_true",
                    help="halt silently at a wasm trap, as the default handler does, "
                    "without the message of runtime/trapmsg.nasm")
    ap.add_argument("--symbols", action="store_true",
                    help="write the labels to a .sym file next to the output, with the "
                    "functions of the program by name, for niceemu --symbols")
    ap.add_argument("--keep", action="store_true",
                    help="keep the intermediate .wasm, .nasm, and joined .nasm files next to the output")
    args = ap.parse_args()

    lang = language(args.inputs)
    if lang != "c" and (args.includes or args.defines):
        sys.exit("nicebuild: -I and -D are for C only")
    out = args.output or os.path.splitext(args.inputs[0])[0] + ".bin"
    base = os.path.splitext(out)[0]
    python = sys.executable

    if lang == "c":
        run(["make", "-s", "-C", LIBC, "libc.a"])
    run(["make", "-s", "-C", RUNTIME, "float.nasm"])

    with tempfile.TemporaryDirectory() as tmp:
        wasm = os.path.join(tmp, "prog.wasm")
        compile_wasm(lang, args, wasm)

        prog = os.path.join(tmp, "prog.nasm")
        cmd = [python, os.path.join(HERE, "nicewasm.py"), "-o", prog]
        if args.no_mpu:
            cmd.append("--no-mpu")
        if args.no_bounds_checks:
            cmd.append("--no-bounds-checks")
        if args.memory_pages is not None:
            cmd += ["--memory-pages", str(args.memory_pages)]
        run(cmd + [wasm])

        # The order of ABI.md: start-up, program, runtime, muldiv, and float
        # if the program calls it.
        program = read(prog)
        start = "start_wasm.nasm" if args.no_trap_report else "start_wasm_trap.nasm"
        parts = [read(os.path.join(RUNTIME, start)), program,
                 read(os.path.join(RUNTIME, "lib.nasm")),
                 read(os.path.join(RUNTIME, "muldiv_soft.nasm" if args.no_mpu else "muldiv_mpu.nasm"))]
        float_nasm = read(os.path.join(RUNTIME, "float.nasm"))
        if float_labels(float_nasm) & set(re.findall(r"[A-Za-z0-9_.]+", program)):
            parts.append(float_nasm)
        if not args.no_trap_report:
            parts.append(read(os.path.join(RUNTIME, "trapmsg.nasm")))
        full = os.path.join(tmp, "full.nasm")
        with open(full, "w", encoding="latin-1", newline="") as f:
            f.write("".join(p if p.endswith("\n") else p + "\n" for p in parts))

        sym = os.path.join(tmp, "full.sym")
        run([python, os.path.join(ROOT, "assembler", "niceasm.py"), "-o", out,
             *(["--symbols", sym] if args.symbols else []), full])
        if args.symbols:
            write_symbols(sym, program, base + ".sym")

        if args.keep:
            shutil.copy(wasm, base + ".wasm")
            shutil.copy(prog, base + ".nasm")
            shutil.copy(full, base + ".full.nasm")


if __name__ == "__main__":
    main()
