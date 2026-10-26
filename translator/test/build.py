#!/usr/bin/env python3
"""Tests of nicebuild.py. It builds a program in each language whose compiler
is installed, runs it on the emulator, and checks the output, the trap
report, the files of --keep, and the .sym file of --symbols. A language
whose compiler is missing is skipped, and the PASS line says so. The
mistakes in the options need no compiler."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
NICEBUILD = os.path.join(HERE, "..", "nicebuild.py")
NICEEMU = os.path.join(ROOT, "emulator", "zig-out", "bin", "niceemu")
LIBC_TEST = os.path.join(ROOT, "runtime", "libc", "test")

# Mistakes in the options, found before any compiler runs: (arguments,
# the message on stderr). The files need not exist.
ERRORS: List[Tuple[List[str], str]] = [
    (["prog.txt"], "nicebuild: prog.txt: unknown extension; expected .c, .zig, or .rs"),
    (["a.c", "b.zig"], "nicebuild: the inputs are in more than one language"),
    (["a.zig", "b.zig"], "nicebuild: zig takes one source file, the root of the program"),
    (["-I", "inc", "a.rs"], "nicebuild: -I and -D are for C only"),
]

failed = 0


def fail(what: str, detail: str = "") -> None:
    global failed
    failed += 1
    print(f"FAIL build.py: {what}")
    if detail:
        print("    " + detail.rstrip().replace("\n", "\n    "))


def build(args: List[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, NICEBUILD] + args, capture_output=True, text=True)


def run(program: str, sym: Optional[str] = None) -> subprocess.CompletedProcess[str]:
    """Runs a .bin file on the emulator with no input, with its .sym file if given."""
    cmd = [NICEEMU] + (["--symbols", sym] if sym else []) + [program]
    return subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True)


def check_run(what: str, p: subprocess.CompletedProcess[str], status: int, lines: List[str]) -> None:
    """The run must exit with status and print each of the lines: one that
    starts with "~" is a regular expression that some line must match, and
    one that starts with "!" is a start that no line may have."""
    out = p.stdout.splitlines()
    problems = []
    if p.returncode != status:
        problems.append(f"exit status {p.returncode}, expected {status}")
    for line in lines:
        if line.startswith("!"):
            if any(o.startswith(line[1:]) for o in out):
                problems.append(f"unexpected '{line[1:]}'")
        elif line.startswith("~"):
            if not any(re.fullmatch(line[1:], o) for o in out):
                problems.append(f"no line like '{line[1:]}'")
        elif line not in out:
            problems.append(f"expected '{line}'")
    if p.stderr:
        problems.append(f"unexpected stderr: {p.stderr}")
    if problems:
        fail(what, "\n".join(problems) + "\noutput:\n" + p.stdout)


def unnamed(sym: str) -> List[str]:
    """The labels W.fN in a .sym file: functions that have no name."""
    with open(sym) as f:
        labels = [line.split()[1] for line in f if line.strip()]
    return [label for label in labels if re.fullmatch(r"W\.f\d+", label)]


def check_build(what: str, args: List[str], output: str) -> bool:
    """Builds with the arguments, which name the output, and says whether it
    worked. The output must come into being, and only then."""
    p = build(args)
    if p.returncode != 0 or not os.path.exists(output) or p.stderr:
        fail(what, f"exit status {p.returncode}\n{p.stdout}{p.stderr}")
        return False
    return True


def check_symbols(what: str, sym: str) -> None:
    """A .sym file of --symbols must name every function."""
    if not os.path.exists(sym):
        fail(what, f"no {sym}")
    elif unnamed(sym):
        fail(what, f"functions without a name in {sym}: {' '.join(unnamed(sym))}")


def test_c(tmp: str) -> None:
    """abort.c of the C library's tests prints "before" and traps with
    code 1. With the trap report and --symbols, the report names the trap
    and the emulator names the function; with --no-trap-report, the
    program halts with no report. --keep leaves the intermediate files."""
    source = os.path.join(LIBC_TEST, "abort.c")
    out = os.path.join(tmp, "abort.bin")
    if check_build("C build", ["--symbols", "--keep", "-o", out, source], out):
        for ext in (".wasm", ".nasm", ".full.nasm"):
            if not os.path.exists(out[:-4] + ext):
                fail(f"--keep left no {os.path.basename(out[:-4] + ext)}")
        check_symbols("C --symbols", out[:-4] + ".sym")
        check_run("C with the trap report", run(out, out[:-4] + ".sym"), 2,
                  ["before", "~trap 1: unreachable at [0-9a-f]{8}", "At ___wasm_trap",
                   "Trap 1 (unreachable) at abort"])
    quiet = os.path.join(tmp, "quiet.bin")
    if check_build("C build without the trap report", ["--no-trap-report", "-o", quiet, source], quiet):
        if os.path.exists(quiet[:-4] + ".sym"):
            fail("a .sym file without --symbols")
        check_run("C without the trap report", run(quiet), 2, ["before", "!trap 1:"])


def test_zig(tmp: str) -> None:
    """hello.zig greets and returns 0. --symbols names every function, so it
    keeps the wasm's names, and the .bin is the same with and without it."""
    source = os.path.join(HERE, "hello.zig")
    out = os.path.join(tmp, "hello.bin")
    plain = os.path.join(tmp, "plain.bin")
    if check_build("Zig build", ["--symbols", "-o", out, source], out):
        check_symbols("Zig --symbols", out[:-4] + ".sym")
        check_run("Zig", run(out, out[:-4] + ".sym"), 0, ["Hello, NICE!"])
    if check_build("Zig build without --symbols", ["-o", plain, source], plain):
        with open(out, "rb") as f, open(plain, "rb") as g:
            if f.read() != g.read():
                fail("--symbols changed the Zig program")


def test_rust(tmp: str) -> None:
    """hellors.rs greets and returns 0, and --symbols names every function."""
    source = os.path.join(HERE, "hellors.rs")
    out = os.path.join(tmp, "hellors.bin")
    if check_build("Rust build", ["--symbols", "-o", out, source], out):
        check_symbols("Rust --symbols", out[:-4] + ".sym")
        check_run("Rust", run(out, out[:-4] + ".sym"), 0, ["Hello, Rust!"])


def compiler(variable: str, default: str) -> Optional[str]:
    """The compiler that nicebuild.py would run, if it is installed."""
    return shutil.which(os.environ.get(variable, default))


def clang_for_wasm32(clang: str) -> bool:
    """Whether clang has the wasm32 target and finds wasm-ld and llvm-ar."""
    p = subprocess.run([clang, "--target=wasm32", "-x", "c", "-c", "-o", os.devnull, "-"],
                       input="int x;\n", capture_output=True, text=True)
    ld = subprocess.run([clang, "--target=wasm32", "-print-prog-name=wasm-ld"], capture_output=True, text=True)
    return p.returncode == 0 and os.path.isabs(ld.stdout.strip()) and compiler("AR", "llvm-ar") is not None


def rustc_for_wasm32(rustc: str) -> bool:
    """Whether rustc has the wasm32-unknown-unknown target installed."""
    p = subprocess.run([rustc, "--print", "sysroot"], capture_output=True, text=True)
    return p.returncode == 0 and os.path.isdir(
        os.path.join(p.stdout.strip(), "lib", "rustlib", "wasm32-unknown-unknown"))


def main() -> None:
    for args, message in ERRORS:
        p = build(args)
        if p.returncode != 1 or message not in p.stderr.splitlines() or p.stdout:
            fail(" ".join(args), f"exit status {p.returncode}\n{p.stdout}{p.stderr}")
    for var, name, ext in [("CLANG", "clang", "c"), ("ZIG", "zig", "zig"), ("RUSTC", "rustc", "rs")]:
        env = dict(os.environ, **{var: "no-such-compiler"})
        p = subprocess.run([sys.executable, NICEBUILD, f"a.{ext}"], env=env, capture_output=True, text=True)
        message = f"nicebuild: no-such-compiler: not found; install it or set {var}"
        if p.returncode != 1 or message not in p.stderr.splitlines() or p.stdout:
            fail(f"missing {name}", f"exit status {p.returncode}\n{p.stdout}{p.stderr}")
    ran = ["errors"]
    skipped = []
    with tempfile.TemporaryDirectory() as tmp:
        clang = compiler("CLANG", "clang")
        if clang and clang_for_wasm32(clang):
            test_c(tmp)
            ran.append("C")
        else:
            skipped.append("C (no clang, wasm-ld, or llvm-ar for wasm32)")
        if compiler("ZIG", "zig"):
            test_zig(tmp)
            ran.append("Zig")
        else:
            skipped.append("Zig (no zig)")
        rustc = compiler("RUSTC", "rustc")
        if rustc and rustc_for_wasm32(rustc):
            test_rust(tmp)
            ran.append("Rust")
        else:
            skipped.append("Rust (no rustc for wasm32)")
    note = f"; skipped {', '.join(skipped)}" if skipped else ""
    if failed:
        sys.exit(f"FAIL build.py ({failed} failures{note})")
    print(f"PASS build.py ({', '.join(ran)}{note})")


if __name__ == "__main__":
    main()
