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
    (["--stack", "0", "a.c"], "nicebuild: --stack must be positive, not 0"),
    (["--stack", "-5", "a.c"], "nicebuild: --stack must be positive, not -5"),
    (["--memory", "0", "a.c"], "nicebuild: --memory must be positive, not 0"),
    (["--asm", "missing.nasm", "a.c"], "nicebuild: missing.nasm: No such file or directory"),
    (["-o", "/nonexistent/x.bin", "a.c"], "nicebuild: /nonexistent/x.bin: No such file or directory"),
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


# A C program of two files, a header, a macro, a function in assembly, and a
# float, to build with the options that the other tests leave out.
MAIN_C = """#include <stdio.h>
#include "val.h"
extern int twice(int);
int helper(int);
int main(void) {
    volatile float f = 3;
    printf("%d %d %s %d\\n", twice(21), helper(SCALE), NAME, (int)(f * 1.5f));
    return 0;
}
"""
HELPER_C = "int helper(int x) { return x + 1; }\n"
TWICE_NASM = "_twice  ADD     R1, R1, R1\n        MOVE    R15, @R13++\n"


def test_c_options(tmp: str) -> None:
    """-D, -I, two C files, --asm, --stack, --memory, the float library, and
    --no-mpu give the same program; a compiler that fails, and an output
    that cannot be written, are reported."""
    src = os.path.join(tmp, "opts")
    os.makedirs(os.path.join(src, "inc"))
    for name, text in (("main.c", MAIN_C), ("helper.c", HELPER_C), ("twice.nasm", TWICE_NASM),
                       (os.path.join("inc", "val.h"), "#define SCALE 5\n")):
        with open(os.path.join(src, name), "w") as f:
            f.write(text)
    base = ["-I", os.path.join(src, "inc"), "-D", 'NAME="hi"', "--asm", os.path.join(src, "twice.nasm"),
            os.path.join(src, "main.c"), os.path.join(src, "helper.c")]
    for name, extra in (("default", []), ("big stack", ["--stack", "8192", "--memory", "131072"]),
                        ("no mpu", ["--no-mpu"])):
        out = os.path.join(tmp, name.replace(" ", "_") + ".bin")
        if check_build("C options, " + name, ["-o", out] + extra + base, out):
            check_run("C options, " + name, run(out), 0, ["42 6 hi 4"])
    bad = os.path.join(src, "bad.c")
    with open(bad, "w") as f:
        f.write("int main(void) { return }\n")
    p = build(["-o", os.path.join(tmp, "bad.bin"), bad])
    if p.returncode != 1 or "nicebuild: clang failed with status 1" not in p.stderr.splitlines():
        fail("a C file that does not compile", f"exit status {p.returncode}\n{p.stderr}")
    if os.path.exists(os.path.join(tmp, "bad.bin")):
        fail("a .bin file of a C file that does not compile")


def test_unwritable(tmp: str) -> None:
    """An output directory without write permission is found before the build.
    Root writes anywhere, so the test is skipped for root."""
    if os.geteuid() == 0:
        return
    locked = os.path.join(tmp, "locked")
    os.makedirs(locked)
    os.chmod(locked, 0o500)
    out = os.path.join(locked, "x.bin")
    p = build(["-o", out, "a.c"])
    if p.returncode != 1 or f"nicebuild: {out}: Permission denied" not in p.stderr.splitlines():
        fail("an output directory without write permission", f"exit status {p.returncode}\n{p.stderr}")
    os.chmod(locked, 0o700)


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
    with tempfile.TemporaryDirectory() as tmp:
        test_unwritable(tmp)
    ran = ["errors"]
    skipped = []
    with tempfile.TemporaryDirectory() as tmp:
        clang = compiler("CLANG", "clang")
        if clang and clang_for_wasm32(clang):
            test_c(tmp)
            test_c_options(tmp)
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
