#!/usr/bin/env python3
"""Tests for nicedis.

- The round trip: every .bin file of the repository is disassembled and
  reassembled to the same words, without symbols and, where its .nasm file
  gives them, with them. Every listing is in the layout of nicefmt.
- LISTINGS: hand-checked listings, of count.bin and of disedge.bin, which
  has the cases no assembled program has.
- API: disassemble(), as other tools import it.
- ERRORS: bad input files and command lines."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from typing import Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
NICEASM = os.path.join(HERE, "..", "niceasm.py")
NICEDIS = os.path.join(HERE, "..", "nicedis.py")
sys.path.insert(0, os.path.join(HERE, ".."))

import nicedis  # noqa: E402
import nicefmt  # noqa: E402

# (.bin, .sym or None, options, expected listing), paths relative to HERE
LISTINGS: List[Tuple[str, Optional[str], List[str], str]] = [
    ("count.bin", "count.nasm", [], "count.lst"),
    ("disedge.bin", "disedge.sym", [], "disedge.lst"),
]

# (words at 0.., symbols, expected result of disassemble(0, ...))
API: List[Tuple[List[Optional[int]], Dict[int, str], Tuple[str, int]]] = [
    ([0x00005800, 0x10], {0x10: "foo::bar"}, ("MOVE R1, foo::bar", 2)),
    ([0x00005800, 0x02], {0x02: "low"}, ("MOVE R1, 0x2", 2)),
    ([0x08005830, 0x10, 0x10], {0x10: "x"}, ("SHL R1, x, 0x10", 3)),
    ([0xB003D800, 0x04], {}, ("?!Z MOVE R15, 0x4", 2)),
    ([0x0C400021], {}, ("INT 33", 1)),
    ([0x8C000000], {}, ("?!1 HALT", 1)),
    ([0x0C600000], {}, (".DAT 0x0c600000 ; reserved control word", 1)),
    ([0x00005800, None], {}, (".DAT 0x00005800 ; MOVE R1, ? (cut off)", 1)),
    ([0x00004130, 0x05], {}, (".DAT 0x00004130, 0x00000005 ; MOVE R1, R2 (s1: 0x5)", 2)),
    ([0x5 << 21 | 0x01 << 14 | 0x12 << 7], {}, ("DEC R1, --R2", 1)),
    ([0x00000000 | 0x11 << 14 | 0x5D << 7], {}, ("MOVE R1--, @--R13", 1)),
]

# (.bin text, .sym text or None, options, expected stderr, exit status)
ERRORS: List[Tuple[str, Optional[str], List[str], str, int]] = [
    ("0 1\nx\n", None, [], "x.bin:2: error: expected an address and a word in hex", 1),
    ("0x0 1\n", None, [], "x.bin:1: error: expected an address and a word in hex", 1),
    ("0 1\n00000000 2\n", None, [], "x.bin:2: error: address 0x00000000 appears twice", 1),
    ("\n\n", None, [], "x.bin: error: no words", 1),
    ("0 0\n", "0 start\n", [], "x.sym:1: error: expected an 8-digit hex address, a space, and a name", 1),
    ("0 0\n", "00000000  start\n", [], "x.sym:1: error: expected an 8-digit hex address, a space, and a name", 1),
    ("0 0\n", None, ["--start", "x"], "error: argument --start: bad address 'x'", 2),
    ("0 0\n", None, ["--end", "0x100000001"], "error: argument --end: address '0x100000001' is out of range", 2),
]


def run(args: List[str]) -> "subprocess.CompletedProcess[str]":
    return subprocess.run([sys.executable] + args, capture_output=True, text=True,
                          encoding="latin-1")


def round_trip(path: str, sym: Optional[str], d: str) -> Optional[str]:
    """Disassembles and reassembles path. Returns an error, or None."""
    r = run([NICEDIS, path] + (["--symbols", sym] if sym else []))
    if r.returncode:
        return f"nicedis failed: {r.stderr.strip()}"
    if nicefmt.format_source(r.stdout) != r.stdout:
        return "the listing is not in the layout"
    src, out = os.path.join(d, "x.nasm"), os.path.join(d, "x.bin")
    with open(src, "w", encoding="latin-1") as f:
        f.write(r.stdout)
    r = run([NICEASM, "-o", out, src])
    if r.returncode:
        return f"niceasm failed: {r.stderr.strip()}"
    if nicedis.read_bin(out) != nicedis.read_bin(path):
        return "the words differ"
    return None


def symbols_of(path: str, d: str) -> Optional[str]:
    """The symbols file of path: its .sym, or one from its .nasm if that
    assembles to the same words."""
    base = os.path.splitext(path)[0]
    if os.path.exists(base + ".sym"):
        return base + ".sym"
    if not os.path.exists(base + ".nasm"):
        return None
    sym, out = os.path.join(d, "s.sym"), os.path.join(d, "s.bin")
    r = run([NICEASM, "-o", out, "--symbols", sym, base + ".nasm"])
    if r.returncode or nicedis.read_bin(out) != nicedis.read_bin(path):
        return None
    return sym


def bin_files() -> List[str]:
    """The tracked .bin files, or outside a checkout those of the tree but for
    the build directories. In a checkout, the files that the tests of other
    directories write and remove while make test runs in parallel stay out."""
    if os.path.isdir(os.path.join(ROOT, ".git")):
        return subprocess.run(["git", "ls-files", "*.bin"], cwd=ROOT, capture_output=True,
                              text=True, check=True).stdout.split()
    skip = {"build", "zig-out", ".zig-cache"}
    files = []
    for top, dirs, names in os.walk(ROOT):
        dirs[:] = sorted(n for n in dirs if n not in skip)
        files += [os.path.relpath(os.path.join(top, n), ROOT) for n in sorted(names) if n.endswith(".bin")]
    return files


def main() -> None:
    failed = 0
    files = bin_files()
    with tempfile.TemporaryDirectory() as d:
        n_sym = 0
        for name in files:
            path = os.path.join(ROOT, name)
            sym = symbols_of(path, d)
            n_sym += sym is not None
            for s in [None] + ([sym] if sym else []):
                err = round_trip(path, s, d)
                if err:
                    print(f"FAIL round trip of {name}{' with symbols' if s else ''}: {err}")
                    failed += 1
        print(f"PASS round trip of {len(files)} .bin files, {n_sym} also with symbols")

        for b, s, opts, want in LISTINGS:
            sym = None
            if s is not None and s.endswith(".nasm"):
                sym = os.path.join(d, "l.sym")
                run([NICEASM, "-o", os.path.join(d, "l.bin"), "--symbols", sym,
                     os.path.join(HERE, s)])
            elif s is not None:
                sym = os.path.join(HERE, s)
            r = run([NICEDIS, os.path.join(HERE, b)] + (["--symbols", sym] if sym else []) + opts)
            with open(os.path.join(HERE, want), encoding="latin-1") as f:
                expected = f.read()
            if r.returncode or r.stdout != expected:
                print(f"FAIL listing of {b}: {r.stderr.strip()}")
                print("".join(f"  {line}\n" for line in r.stdout.splitlines()))
                failed += 1
        print(f"PASS {len(LISTINGS)} listings")

        # The range of --start and --end, with a label outside it.
        r = run([NICEDIS, os.path.join(HERE, "disedge.bin"), "--symbols",
                 os.path.join(HERE, "disedge.sym"), "--start", "0x15", "--end", "0x17"])
        want = ("far             .EQU    0x00000040\n"
                "                .ORG    0x00000015\n"
                "                MOVE    R1, far         ; far = 0x00000040\n")
        if r.stdout != want:
            print(f"FAIL --start and --end:\n{r.stdout}")
            failed += 1

        for words, syms, result in API:
            got = nicedis.disassemble(0, lambda a: words[a] if a < len(words) else None, syms)
            if got != result:
                print(f"FAIL disassemble of {words}: got {got}, want {result}")
                failed += 1
        print(f"PASS {len(API)} calls of disassemble()")

        for text, sym_text, opts, msg, status in ERRORS:
            path, sym = os.path.join(d, "x.bin"), os.path.join(d, "x.sym")
            with open(path, "w") as f:
                f.write(text)
            if sym_text is not None:
                with open(sym, "w") as f:
                    f.write(sym_text)
            r = run([NICEDIS, path] + (["--symbols", sym] if sym_text is not None else []) + opts)
            err = r.stderr.replace(d + os.sep, "")
            if r.returncode != status or msg not in err or r.stdout:
                print(f"FAIL {text!r} {opts}: status {r.returncode}, {err.strip()!r}")
                failed += 1
        r = run([NICEDIS, os.path.join(d, "none.bin")])
        if r.returncode != 1 or "none.bin: No such file or directory" not in r.stderr:
            print(f"FAIL a missing file: status {r.returncode}, {r.stderr.strip()!r}")
            failed += 1
        print(f"PASS {len(ERRORS) + 1} errors")

    if failed:
        print(f"{failed} failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
