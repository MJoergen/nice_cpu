#!/usr/bin/env python3
"""The size in words of wasm modules translated by nicewasm.

    ./words.py [--library NAME] FILE.wasm...    translate and count each module
    ./words.py --test                           check the count on a snippet

Each module is translated with ../translator/nicewasm.py, with --library
NAME for a library module, and assembled on its own. The labels it uses
but does not define, such as the runtime's routines, are defined as 0 with
.EQU first. A constant takes a whole word whatever its value (ISA.md §3),
so that changes no size. The count is the words the assembler emits for
the module, its instructions and data. The words that .RES reserves, such
as the linear memory, are not counted. One line per module: its name and
its words.
"""

import argparse
import os
import re
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


def translate(wasm: str, library: str, tmp: str) -> List[str]:
    out = os.path.join(tmp, "module.nasm")
    opts = ["--library", library] if library else []
    subprocess.run([sys.executable, os.path.join(HERE, "..", "translator", "nicewasm.py"),
                    *opts, "-o", out, wasm], check=True)
    with open(out) as f:
        return f.readlines()


# --test: a snippet whose words are counted by hand. An instruction is one
# word, and each constant one more (ISA.md §3): MOVE R1, 0x1234 is 2, the
# call's ADD with its constant 2 is 2, and the jump to the undefined label
# is 2. .RES emits nothing, and .DAT one word. So 7 words.
TEST = """        MOVE R1, 0x1234
        ADD @--R13, 2, R15
        MOVE R15, __helper
        .RES 10
x       .DAT 7
"""


def test() -> None:
    n = words(TEST.splitlines(keepends=True), "test")
    if n != 7:
        sys.exit(f"FAIL words.py --test: {n} words, expected 7")
    print("PASS words.py --test")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="*", metavar="FILE.wasm")
    ap.add_argument("--library", metavar="NAME", default="", help="translate as a library module")
    ap.add_argument("--test", action="store_true")
    a = ap.parse_args()
    if a.test:
        test()
        return
    if not a.files:
        ap.error("no FILE.wasm")
    with tempfile.TemporaryDirectory() as tmp:
        for wasm in a.files:
            name = os.path.splitext(os.path.basename(wasm))[0]
            print(f"{name} {words(translate(wasm, a.library, tmp), wasm)}")


if __name__ == "__main__":
    main()
