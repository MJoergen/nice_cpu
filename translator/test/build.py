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
NICEASM = os.path.join(ROOT, "assembler", "niceasm.py")
MONITOR = os.path.join(ROOT, "runtime", "test", "monitor.nasm")
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
    (["--memory-bytes", "-4", "a.c"],
     "nicebuild: --memory-bytes must be auto or a number of bytes, not -4"),
    (["--memory-bytes", "16", "--memory-pages", "2", "a.c"],
     "nicebuild: --memory-bytes and --memory-pages do not go together: a memory reserved only"
     " in part cannot grow"),
    (["--ram", "0xFFFFF000", "--monitor", "a.c"],
     "nicebuild: --ram and --monitor do not go together: a monitor loads a program into RAM"),
    (["--ram", "0xFFFFF000", "--memory-pages", "2", "a.c"],
     "nicebuild: --ram and --memory-pages do not go together: the memory of code in a ROM"
     " cannot grow"),
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


def run(program: str, sym: Optional[str] = None,
        options: Optional[List[str]] = None) -> subprocess.CompletedProcess[str]:
    """Runs a .bin file on the emulator with no input, with its .sym file if
    given, and the emulator's options."""
    cmd = [NICEEMU] + (options or []) + (["--symbols", sym] if sym else []) + [program]
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
TWICE_NASM = "_twice          ADD     R1, R1, R1\n                MOVE    R15, @R13++\n"


def test_c_options(tmp: str) -> None:
    """-D, -I, two C files, --asm, --stack, --memory, the float library,
    --no-mpu, and --memory-bytes give the same program; a compiler that fails, and an output
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
                        ("no mpu", ["--no-mpu"]),
                        ("inline fpu", ["--inline-fpu"]),
                        ("trusted alignment", ["--no-bounds-checks", "--trust-alignment"]),
                        ("byte windows", ["--trust-alignment", "--byte-windows"]),
                        ("small memory", ["--memory-bytes", "auto"])):
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


# Deep recursion by tail calls: down(n) returns sp(), the SP less 1 in
# the hand-written routine, after n tail calls. With tail calls, the
# frames do not pile up, so down(0) and down(100000) see the same SP, and
# main returns 0. In C, down and its twin call each other, so that clang
# cannot make a loop of them.
SP_NASM = "_sp             MOVE    R1, R13\n                MOVE    R15, @R13++\n"
TAIL_C = """unsigned sp(void);
unsigned twin(unsigned n);

__attribute__((noinline)) unsigned down(unsigned n) {
    if (n == 0)
        return sp();
    [[clang::musttail]] return twin(n - 1);
}

__attribute__((noinline)) unsigned twin(unsigned n) {
    if (n == 0)
        return sp();
    [[clang::musttail]] return down(n - 1);
}

int main(void) { return down(0) != down(100000); }
"""
TAIL_ZIG = """extern fn sp() u32;

fn down(n: u32) u32 {
    if (n == 0) return sp();
    return @call(.always_tail, down, .{n - 1});
}

export fn main() i32 {
    return @intFromBool(down(0) != down(100000));
}
"""


def test_tail(tmp: str, lang: str) -> None:
    """A tail call that the language guarantees, clang's musttail or Zig's
    always_tail, needs nicebuild's tail-call option, and nicewasm turns
    it into a jump."""
    src = os.path.join(tmp, "tail")
    os.makedirs(src, exist_ok=True)
    source = os.path.join(src, "tail." + lang)
    with open(source, "w") as f:
        f.write(TAIL_C if lang == "c" else TAIL_ZIG)
    asm = os.path.join(src, "sp.nasm")
    with open(asm, "w") as f:
        f.write(SP_NASM)
    out = os.path.join(tmp, f"tail_{lang}.bin")
    what = f"{'C' if lang == 'c' else 'Zig'} tail calls"
    if check_build(what, ["--asm", asm, "-o", out, source], out):
        check_run(what, run(out), 0, [])


def after_standin(tmp: str, program: str) -> str:
    """The program of --monitor after the runtime's stand-in for a monitor,
    in one .bin file, as a monitor's image and a program's concatenate. The
    stand-in is assembled on its own, once."""
    monitor = os.path.join(tmp, "standin.bin")
    if not os.path.exists(monitor):
        subprocess.run([sys.executable, NICEASM, "-o", monitor, MONITOR], check=True)
    with open(program) as f:
        first = f.readline().split()[0]
    if first != "00008000":
        fail(os.path.basename(program), f"the program starts at {first}, not 00008000")
    full = program[:-4] + ".full.bin"
    with open(full, "w") as f, open(monitor) as m, open(program) as p:
        f.write(m.read() + p.read())
    return full


def test_c_monitor(tmp: str) -> None:
    """exit.c built with --monitor is a program for a monitor in ROM, at
    0x8000 (ABI.md, "Programs under a monitor"). It runs after the runtime's
    stand-in for a monitor. It prints through the stand-in's putc routine,
    and exit returns to the stand-in, which halts with the status in R1 and
    the 11 bytes written in R2. With --no-trap-report the other start-up
    file is used, and the program runs the same."""
    source = os.path.join(LIBC_TEST, "exit.c")
    for name, extra in (("under a monitor", []), ("under a monitor without the trap report", ["--no-trap-report"])):
        out = os.path.join(tmp, name.replace(" ", "_") + ".bin")
        if check_build("C " + name, ["--monitor", "-o", out] + extra + [source], out):
            check_run("C " + name, run(after_standin(tmp, out)), 0,
                      ["before", "0 1", "~R0  00000000 R1  00000003 R2  0000000b R3  [0-9a-f]{8}"])


# A Zig program that prints through nice.zig, so through nice_putc and the
# putc vector, for the build with --monitor.
HI_ZIG = """const nice = @import("nice");
export fn main() i32 {
    nice.write("Hi\\n");
    return 5;
}
"""


def test_zig_monitor(tmp: str) -> None:
    """A Zig program built with --monitor prints through the stand-in's putc
    routine, as nice.zig's output goes through nice_putc, and returns to the
    stand-in with main's result: R1 = 5, and the 3 bytes written in R2."""
    source = os.path.join(tmp, "hi.zig")
    with open(source, "w") as f:
        f.write(HI_ZIG)
    out = os.path.join(tmp, "hi_mon.bin")
    if check_build("Zig under a monitor", ["--monitor", "-o", out, source], out):
        check_run("Zig under a monitor", run(after_standin(tmp, out)), 0,
                  ["Hi", "~R0  00000000 R1  00000005 R2  00000003 R3  [0-9a-f]{8}"])


def image_changes(program: str) -> List[int]:
    """Runs a .bin file and dumps its image after the halt. Returns the
    addresses of the words of the image that the run changed."""
    image = {}
    with open(program) as f:
        for line in f:
            addr, word = line.split()
            image[int(addr, 16)] = int(word, 16)
    p = subprocess.run([NICEEMU, "-d", f"0:{max(image) + 1}", program], stdin=subprocess.DEVNULL,
                       capture_output=True, text=True)
    after = {}
    for line in p.stdout.splitlines():
        m = re.fullmatch(r"([0-9a-f]{8}):((?: [0-9a-f]{8})+)", line)
        if m:
            for i, w in enumerate(m.group(2).split()):
                after[int(m.group(1), 16) + i] = int(w, 16)
    return [a for a in sorted(image) if after.get(a) != image[a]]


# A C program for code in a ROM, with a data segment, static data that is
# 0 at the start, the C library's printf, and a stack, which printf's
# buffer is on. counter is 0 plus table[2] = 3.
ROM_C = """#include <stdio.h>
static int counter;
static int table[3] = {1, 2, 3};
int main(void) {
    counter += table[2];
    printf("rom %d\\n", counter);
    return counter;
}
"""
FLOAT_C = "int main(void) { volatile float f = 3; return (int)(f * 1.5f); }\n"


def test_rom(tmp: str, lang: str) -> None:
    """A program built with --ram, for code that runs from a ROM, runs
    from the image at 0 with its words in RAM at 0xFFFFF000, below the
    stack, and leaves every word of the image as it was. In C, so does a
    program that uses floats, whose library uses the FPU."""
    what = {"c": "C", "zig": "Zig", "rs": "Rust"}[lang] + " for a ROM"
    if lang == "c":
        source = os.path.join(tmp, "rom.c")
        with open(source, "w") as f:
            f.write(ROM_C)
        lines = ["rom 3", "~R0  00000000 R1  00000003 .*"]
    else:
        source = os.path.join(HERE, "hello.zig" if lang == "zig" else "hellors.rs")
        lines = ["Hello, " + ("NICE!" if lang == "zig" else "Rust!")]
    out = os.path.join(tmp, f"rom_{lang}.bin")
    if check_build(what, ["--ram", "0xFFFFF000", "-o", out, source], out):
        check_run(what, run(out), 0, lines)
        changed = image_changes(out)
        if changed:
            fail(what, f"{len(changed)} words of the image changed, the first at {changed[0]:08x}")
    if lang == "c":
        source = os.path.join(tmp, "float.c")
        with open(source, "w") as f:
            f.write(FLOAT_C)
        out = os.path.join(tmp, "float_rom.bin")
        if check_build("C with floats for a ROM", ["--ram", "0xFFFFF000", "-o", out, source], out):
            check_run("C with floats for a ROM", run(out), 0, ["~R0  00000000 R1  00000004 .*"])
            changed = image_changes(out)
            if changed:
                fail("C with floats for a ROM", f"{len(changed)} words of the image changed")


# A program with floats in each language: 3 * 3 * 1.5, through memory
# that the compiler must read, so that the arithmetic is the program's,
# rounded toward zero, 13.
FLOATS = {
    "c": "int main(void) { volatile float f = 3; return (int)(f * f * 1.5f); }\n",
    "zig": """export fn main() i32 {
    var f: f32 = 3;
    const p: *volatile f32 = &f;
    return @intFromFloat(p.* * p.* * 1.5);
}
""",
    "rs": """#![no_std]

#[no_mangle]
pub extern "C" fn main() -> i32 {
    let f = 3.0f32;
    let v = unsafe { core::ptr::read_volatile(&f) };
    (v * v * 1.5) as i32
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}
""",
}
FLOATS_RESULT = "~R0  00000000 R1  0000000d .*"


def reserved_words(nasm: str) -> Optional[int]:
    """The words that the translated module reserves for its linear memory."""
    with open(nasm) as f:
        m = re.search(r"^___wasm_memory\n +\.RES +(\d+)$", f.read(), re.M)
    return int(m.group(1)) if m else None


def test_floats(tmp: str, lang: str) -> None:
    """A program with floats gives its result when built by default, which
    joins the float library of the FPU, and with --inline-fpu, whose module
    writes the FPU's CMD itself. The module of --memory-bytes reserves the
    bytes given, rounded up to a word."""
    what = {"c": "C", "zig": "Zig", "rs": "Rust"}[lang] + " with floats"
    source = os.path.join(tmp, f"floats.{lang}")
    with open(source, "w") as f:
        f.write(FLOATS[lang])
    for i, (name, extra) in enumerate((("", []), (", --inline-fpu", ["--inline-fpu"]),
                                       (", --memory-bytes 8190", ["--memory-bytes", "8190"]))):
        out = os.path.join(tmp, f"floats_{lang}_{i}.bin")
        if not check_build(what + name, ["--keep", "-o", out] + extra + [source], out):
            continue
        check_run(what + name, run(out), 0, [FLOATS_RESULT])
        with open(out[:-4] + ".nasm") as f:
            inline = "@__fpu.cmd," in f.read()
        if inline != (extra == ["--inline-fpu"]):
            fail(what + name, f"the module {'writes' if inline else 'does not write'} the FPU's CMD")
        words = reserved_words(out[:-4] + ".nasm")
        if "--memory-bytes" in extra and words != 2048:
            fail(what + name, f"the module reserves {words} words for its memory, not 2048")


# Programs without floats that export a function with the name of a routine
# of the float library, log in Zig and round in C, whose labels, _log and
# _round, the library defines too. Each returns 3 * 5.
OWN_NAMES = {
    "zig": """var a: i32 = 5;
export fn log(x: i32) i32 {
    return x * 3;
}
export fn main() i32 {
    const p: *volatile i32 = &a;
    return log(p.*);
}
""",
    "c": """volatile int a = 5;
__attribute__((export_name("round"))) int round_(int x) { return x * 3; }
int main(void) { return round_(a); }
""",
}
# The same C program with a float operation, which needs the library.
OWN_NAME_FLOAT_C = """volatile int a = 5;
volatile float f = 1.5f;
__attribute__((export_name("round"))) int round_(int x) { return x * 3; }
int main(void) { return round_(a) + (int)(f * f); }
"""


def test_own_names(tmp: str, lang: str) -> None:
    """A program that defines a label of the float library and uses none of
    them is built without the library, and runs: the label is the
    program's own. With a float operation, the library is joined, and the
    label is then defined twice, which the assembler reports (runtime
    README, Float library)."""
    what = {"c": "C", "zig": "Zig"}[lang] + " with a function named as one of the float library's"
    source = os.path.join(tmp, f"own.{lang}")
    with open(source, "w") as f:
        f.write(OWN_NAMES[lang])
    out = os.path.join(tmp, f"own_{lang}.bin")
    if check_build(what, ["-o", out, source], out):
        check_run(what, run(out), 0, ["~R0  00000000 R1  0000000f .*"])
    if lang != "c":
        return
    source = os.path.join(tmp, "own_float.c")
    with open(source, "w") as f:
        f.write(OWN_NAME_FLOAT_C)
    out = os.path.join(tmp, "own_float.bin")
    p = build(["-o", out, source])
    lines = p.stderr.splitlines()
    if (p.returncode != 1 or "nicebuild: niceasm.py failed with status 1" not in lines
            or not any(re.fullmatch(r".*: error: symbol '_round' is already defined on line \d+", line)
                       for line in lines)):
        fail(what + ", and a float", f"exit status {p.returncode}\n{p.stdout}{p.stderr}")
    if os.path.exists(out):
        fail(what + ", and a float", "a .bin file of a program that does not assemble")


# A C program whose only use of the float library is pow, a function of
# math.h, with no float operation of its own. 2^10 is 1024, whose bits are
# 0x4090000000000000, and main returns the high 12, 0x409.
POW_C = """#include <math.h>
#include <string.h>
volatile double base = 2, exponent = 10;
int main(void) {
    double r = pow(base, exponent);
    unsigned long long bits;
    memcpy(&bits, &r, sizeof bits);
    return (int)(bits >> 52);
}
"""


def test_pow(tmp: str) -> None:
    """A program that names only a function of math.h, _pow, and no
    routine of a float operation, is joined with the float library, and
    runs. Without the FPU it traps with code 9 at its start, and the
    trap report names the code."""
    what = "C with pow as its only float"
    source = os.path.join(tmp, "pow.c")
    with open(source, "w") as f:
        f.write(POW_C)
    out = os.path.join(tmp, "pow.bin")
    if not check_build(what, ["--keep", "-o", out, source], out):
        return
    with open(os.path.join(ROOT, "runtime", "float_fpu.nasm")) as f:
        operations = set(re.findall(r"^(__[A-Za-z0-9_.]+)", f.read(), re.M))
    with open(out[:-4] + ".nasm") as f:
        named = operations & set(re.findall(r"[A-Za-z0-9_.]+", f.read()))
    if named:
        fail(what, f"the program also names {' '.join(sorted(named))}")
    check_run(what, run(out), 0, ["~R0  00000000 R1  00000409 .*"])
    check_run(what + ", without the FPU", run(out, options=["--no-fpu"]), 2,
              ["~trap 9: no FPU at [0-9a-f]{8}", "~R0  00000000 R1  00000009 .*"])


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
            test_c_monitor(tmp)
            test_rom(tmp, "c")
            test_tail(tmp, "c")
            test_floats(tmp, "c")
            test_own_names(tmp, "c")
            test_pow(tmp)
            ran.append("C")
        else:
            skipped.append("C (no clang, wasm-ld, or llvm-ar for wasm32)")
        if compiler("ZIG", "zig"):
            test_zig(tmp)
            test_zig_monitor(tmp)
            test_rom(tmp, "zig")
            test_tail(tmp, "zig")
            test_floats(tmp, "zig")
            test_own_names(tmp, "zig")
            ran.append("Zig")
        else:
            skipped.append("Zig (no zig)")
        rustc = compiler("RUSTC", "rustc")
        if rustc and rustc_for_wasm32(rustc):
            test_rust(tmp)
            test_rom(tmp, "rs")
            test_floats(tmp, "rs")
            ran.append("Rust")
        else:
            skipped.append("Rust (no rustc for wasm32)")
    note = f"; skipped {', '.join(skipped)}" if skipped else ""
    if failed:
        sys.exit(f"FAIL build.py ({failed} failures{note})")
    print(f"PASS build.py ({', '.join(ran)}{note})")


if __name__ == "__main__":
    main()
