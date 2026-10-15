#!/usr/bin/env python3
"""A random test of the C library's printf family against a model of C's
printf.

Usage: fuzz_printf.py SEED COUNT

It writes a C program with COUNT random calls: a quarter of them
snprintf into a buffer of a random size, whose return value and contents
are then printed, the rest printf. Each format has one to three
conversions from d i u o x X c s %, with random flags from - + space # 0,
a width and a precision that may be numbers or *, and a length modifier
from hh h l ll z t j. The arguments have the matching C types and are
random, with the limits of each type among them. The flag combinations
that C leaves undefined are not used: + and space with an unsigned
conversion, # with d i u, and 0 or # with c and s. The program is compiled
with clang and the library, with a 64 KB stack put first, translated,
assembled, and run, and its console output is compared line by line with
what the model gives. The model follows C17 7.21.6.1 for these
conversions; it has no float conversions, as the library has none.

Needs clang with the wasm32 target, and ../libc.a from make -C .. libc.a.
The same seed always gives the same program."""

from __future__ import annotations

import os
import random
import subprocess
import sys
import tempfile
from typing import List, Optional, Tuple, Union

HERE = os.path.dirname(os.path.abspath(__file__))
LIBC = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(LIBC))
RUNTIME = os.path.join(REPO, "runtime")
NICEWASM = os.path.join(REPO, "translator", "nicewasm.py")
NICEASM = os.path.join(REPO, "assembler", "niceasm.py")
NICEEMU = os.path.join(REPO, "emulator", "zig-out", "bin", "niceemu")

CFLAGS = ["--target=wasm32", "-mbulk-memory", "-O2", "-ffreestanding", "-nostdlibinc",
          "-isystem", os.path.join(LIBC, "include"), "-Wall"]
LDFLAGS = ["-nostdlib", "-Wl,--no-entry", "-Wl,--export=main", "-Wl,--stack-first",
           "-Wl,-z,stack-size=65536", "-Wl,--initial-memory=262144"]
PAGES = "4"

# The bits of each length modifier on wasm32, where int and long are 32 bits.
BITS = {"hh": 8, "h": 16, "": 32, "l": 32, "z": 32, "t": 32, "ll": 64, "j": 64}
SIGNED_TYPES = {"hh": "int", "h": "int", "": "int", "l": "long", "z": "int", "t": "ptrdiff_t",
                "ll": "long long", "j": "intmax_t"}
UNSIGNED_TYPES = {"hh": "unsigned", "h": "unsigned", "": "unsigned", "l": "unsigned long",
                  "z": "size_t", "t": "unsigned long", "ll": "unsigned long long", "j": "uintmax_t"}

Arg = Union[int, str, None]


def trunc(v: int, nbits: int, signed: bool) -> int:
    """The value as the conversion's type sees it."""
    v &= (1 << nbits) - 1
    if signed and v >> (nbits - 1):
        v -= 1 << nbits
    return v


def cfmt(conv: str, flags: str, width: Optional[int], prec: Optional[int], length: str, arg: Arg) -> str:
    """One conversion, as C's printf formats it. A negative width means
    left adjustment, and a negative precision is taken as omitted."""
    left, plus, space, alt, zero = ("-" in flags, "+" in flags, " " in flags, "#" in flags, "0" in flags)
    if width is not None and width < 0:
        left, width = True, -width
    if left:
        zero = False
    if prec is not None and prec < 0:
        prec = None
    if conv == "%":
        return "%"
    if conv in "di":
        assert isinstance(arg, int)
        v = trunc(arg, BITS[length], True)
        digits = "" if prec == 0 and v == 0 else str(abs(v))
        if prec is not None:
            zero = False
            digits = digits.rjust(prec, "0")
        head, body = "-" if v < 0 else "+" if plus else " " if space else "", digits
    elif conv in "uoxX":
        assert isinstance(arg, int)
        v = trunc(arg, BITS[length], False)
        digits = {"u": str(v), "o": format(v, "o"), "x": format(v, "x"), "X": format(v, "X")}[conv]
        if prec == 0 and v == 0:
            digits = ""
        if prec is not None:
            zero = False
            digits = digits.rjust(prec, "0")
        head = "0" + conv if alt and conv in "xX" and v != 0 else ""
        if alt and conv == "o" and not digits.startswith("0"):
            digits = "0" + digits
        body = digits
    elif conv == "c":
        assert isinstance(arg, int)
        head, body, zero = "", chr(arg), False
    else:
        assert conv == "s" and isinstance(arg, str)
        head, body, zero = "", arg if prec is None else arg[:prec], False
    s = head + body
    if width is not None and len(s) < width:
        if left:
            s = s.ljust(width)
        elif zero:
            s = head + body.rjust(width - len(head), "0")
        else:
            s = s.rjust(width)
    return s


def c_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def gen_case(rng: random.Random) -> Tuple[str, List[str], str]:
    """A format, its arguments as C text, and the output C defines."""
    fmt, args, out = "", [], ""
    for _ in range(rng.randrange(1, 4)):
        literal = "".join(rng.choice("abcXYZ,:=()[]_") for _ in range(rng.randrange(0, 4)))
        fmt += literal
        out += literal
        conv = rng.choice("ddiuuooxxXXcs%")
        flags = "".join(rng.sample("-+ #0", rng.randrange(0, 3)))
        if conv in "cs":
            flags = flags.replace("#", "").replace("0", "")
        if conv in "uoxX":
            flags = flags.replace("+", "").replace(" ", "")
        if conv in "diu":
            flags = flags.replace("#", "")
        length = rng.choice(["", "", "", "hh", "h", "l", "ll", "z", "t", "j"]) if conv in "diuoxX" else ""
        spec = "%" + flags
        width: Optional[int] = None
        prec: Optional[int] = None
        r = rng.random()
        if r < 0.25:
            width = rng.randrange(-12, 14)
            spec += "*"
            args.append(str(width))
        elif r < 0.5:
            width = rng.randrange(0, 14)
            spec += str(width)
        r = rng.random()
        if conv not in "c%":
            if r < 0.2:
                prec = rng.randrange(-4, 9)
                spec += ".*"
                args.append(str(prec))
            elif r < 0.45:
                prec = rng.randrange(0, 9)
                spec += "." + str(prec)
        spec += length + conv
        fmt += spec
        arg: Arg = None
        if conv in "di":
            n = BITS[length]
            arg = rng.choice([0, 1, -1, rng.randrange(-100, 100), rng.randrange(-(1 << (n - 1)), 1 << (n - 1)),
                              -(1 << (n - 1)), (1 << (n - 1)) - 1])
            if arg == -(1 << (n - 1)):
                text = f"(-{(1 << (n - 1)) - 1}{'LL' if n == 64 else ''} - 1)"  # no literal for it
            else:
                text = f"({SIGNED_TYPES[length]}){arg}{'LL' if n == 64 else ''}"
            args.append(text)
        elif conv in "uoxX":
            n = BITS[length]
            arg = rng.choice([0, 1, rng.randrange(0, 1000), rng.getrandbits(n), (1 << n) - 1])
            args.append(f"({UNSIGNED_TYPES[length]}){arg}{'ULL' if n == 64 else 'u'}")
        elif conv == "c":
            arg = rng.randrange(0x21, 0x7F)
            args.append(str(arg))
        elif conv == "s":
            arg = "".join(rng.choice("abcdefgh") for _ in range(rng.randrange(0, 7)))
            args.append(c_string(arg))
        out += cfmt(conv, flags, width, prec, length, arg)
    return fmt, args, out


def program(rng: random.Random, count: int) -> Tuple[str, List[str]]:
    """The C program and the lines it must print."""
    lines, expected = [], []
    for _ in range(count):
        fmt, args, out = gen_case(rng)
        call = ", ".join([c_string(fmt)] + args)
        if rng.random() < 0.25:
            size = rng.randrange(1, 24)
            lines.append(f'    n = snprintf(buf, {size}, {call}); printf("%d [%s]\\n", n, buf);')
            expected.append(f"{len(out)} [{out[:size - 1]}]")
        else:
            lines.append(f"    printf({call}); putchar('\\n');")
            expected.append(out)
    text = "#include <stddef.h>\n#include <stdint.h>\n#include <stdio.h>\n\nint main(void)\n{\n"
    text += "    char buf[32];\n    int n;\n" + "\n".join(lines) + "\n    return 0;\n}\n"
    return text, expected


def run(cmd: List[str]) -> None:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(" ".join(cmd) + "\n" + p.stdout + p.stderr)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__.split("\n\n")[1])
    seed, count = int(sys.argv[1]), int(sys.argv[2])
    text, expected = program(random.Random(seed), count)
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "fuzz.c")
        with open(src, "w") as f:
            f.write(text)
        wasm = os.path.join(tmp, "fuzz.wasm")
        run(["clang", *CFLAGS, *LDFLAGS, "-o", wasm, src, os.path.join(LIBC, "libc.a")])
        asm = os.path.join(tmp, "fuzz.nasm")
        run([sys.executable, NICEWASM, "--memory-pages", PAGES, "-o", asm, wasm])
        full = os.path.join(tmp, "fuzz.full.nasm")
        with open(full, "w") as out:
            for part in ["start_wasm.nasm", asm, "lib.nasm", "muldiv_mpu.nasm"]:
                with open(part if os.path.isabs(part) else os.path.join(RUNTIME, part)) as f:
                    out.write(f.read() + "\n")
        binary = os.path.join(tmp, "fuzz.bin")
        run([sys.executable, NICEASM, "-o", binary, full])
        p = subprocess.run([NICEEMU, "-n", "200000000", binary], capture_output=True)
    output = p.stdout.decode("latin-1")
    console = output[:output.index("Halted")] if "Halted" in output else output
    got = console.splitlines()
    bad = 0
    for i, (g, w) in enumerate(zip(got, expected)):
        if g != w:
            bad += 1
            if bad <= 20:
                print(f"MISMATCH in call {i}:\n  got  {g!r}\n  want {w!r}")
    if len(got) != len(expected) or p.returncode != 0:
        bad += 1
        print(f"{len(got)} lines instead of {len(expected)}, exit status {p.returncode}:\n"
              + "\n".join(output.splitlines()[-5:]))
    print(f"{'FAIL' if bad else 'PASS'} printf fuzz (seed {seed}, {count} calls)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
