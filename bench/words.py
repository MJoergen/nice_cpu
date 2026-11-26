#!/usr/bin/env python3
"""The size in words of wasm modules translated by nicewasm.

    ./words.py [--options OPTIONS] FILE.wasm...   translate and count each module
    ./words.py --minus BASE.wasm FILE.wasm...     the same, less the words of BASE
    ./words.py --test                             check the count on a snippet

Each module is translated with ../translator/nicewasm.py, and assembled
on its own. A FILE.nasm, such as the float library, is not translated,
and is counted as it is. OPTIONS are options for nicewasm, in one argument, such as
"--trust-alignment --byte-windows". The labels it uses but does not define, such as the runtime's
routines, are defined as 0 with .EQU first. A constant takes a whole word
whatever its value (ISA.md §2.3),
so that changes no size. The count is the words the assembler emits for
the module, its instructions and data. The words that .RES reserves, such
as the linear memory, are not counted. One line per module: its name and
its words, and then OPTIONS, if given. With --minus, the words are those
of the module less those of BASE, translated with the same OPTIONS, and the
line ends with "less" and BASE's name.
"""

import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
from typing import List

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "assembler"))
import niceasm  # noqa: E402

UNDEFINED = re.compile(r"undefined symbol '([^']+)'")


def words(lines: List[str], name: str) -> int:
    """The words the assembler emits for lines, with the labels they use
    but do not define taken as 0."""
    defined: List[str] = []
    while True:
        a = niceasm.Assembler()
        errors = a.run([f"{label} .EQU 0" for label in defined] + lines, name)
        missing = sorted({m.group(1) for e in errors for m in [UNDEFINED.search(e)] if m})
        if not missing:
            if errors:
                sys.exit("\n".join(errors))
            return len(a.words)
        defined += missing


def translate(wasm: str, tmp: str, options: List[str]) -> List[str]:
    out = os.path.join(tmp, "module.nasm")
    subprocess.run([sys.executable, os.path.join(HERE, "..", "translator", "nicewasm.py"),
                    *options, "-o", out, wasm], check=True)
    with open(out) as f:
        return f.readlines()


# --test: a snippet whose words are counted by hand. An instruction is one
# word, and each constant one more (ISA.md §2.3): MOVE R1, 0x1234 is 2, and
# the CALL of the undefined label is 1, the distance in the instruction
# word (ISA.md §5.3). .RES emits nothing, and .DAT one word. So 4 words.
TEST = """                MOVE    R1, 0x1234
                CALL    __helper
                .RES    10
x               .DAT    7
"""


def test() -> None:
    n = words(TEST.splitlines(keepends=True), "test")
    if n != 4:
        sys.exit(f"FAIL words.py --test: {n} words, expected 4")
    print("PASS words.py --test")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="*", metavar="FILE.wasm", help="a wasm module, or a .nasm file, counted as it is")
    ap.add_argument("--test", action="store_true")
    ap.add_argument("--options", default="", help="options for nicewasm, in one argument")
    ap.add_argument("--minus", metavar="BASE.wasm", help="count each module less the words of BASE")
    a = ap.parse_args()
    if a.test:
        test()
        return
    if not a.files:
        ap.error("no FILE.wasm")
    options = shlex.split(a.options)
    with tempfile.TemporaryDirectory() as tmp:
        base = words(translate(a.minus, tmp, options), a.minus) if a.minus else 0
        less = f" less {os.path.splitext(os.path.basename(a.minus))[0]}" if a.minus else ""
        for wasm in a.files:
            name = os.path.splitext(os.path.basename(wasm))[0]
            if wasm.endswith(".nasm"):
                with open(wasm) as f:
                    print(f"{name} {words(f.readlines(), wasm)}")
                continue
            n = words(translate(wasm, tmp, options), wasm) - base
            print(f"{name} {n} {a.options}".rstrip() + less)


if __name__ == "__main__":
    main()
