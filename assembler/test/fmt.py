#!/usr/bin/env python3
"""Tests for nicefmt: the layout of single lines, and the exit status and
the --write option of the command."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from typing import List, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
NICEFMT = os.path.join(HERE, "..", "nicefmt.py")
sys.path.insert(0, os.path.join(HERE, ".."))

import nicefmt  # noqa: E402

# (a line, the lines it becomes)
CASES: List[Tuple[str, List[str]]] = [
    ("", [""]),
    ("   ", [""]),
    ("; a comment", ["; a comment"]),
    ("    ; indented", [" " * 16 + "; indented"]),
    ("* a star comment", ["* a star comment"]),
    ("move r1, r2", [" " * 16 + "move    r1, r2"]),
    ("\tMOVE\tR1, R2\t; tabs", [" " * 16 + "MOVE    R1, R2" + " " * 10 + "; tabs"]),
    ("    ?!Z MOVE PC, LOOP", [" " * 8 + "?!Z     MOVE    PC, LOOP"]),
    ("loop MOVE R1, R2", ["loop            MOVE    R1, R2"]),
    ("loop ?Z MOVE R1, R2", ["loop    ?Z      MOVE    R1, R2"]),
    ("a_long_label MOVE R1, R2", ["a_long_label", " " * 16 + "MOVE    R1, R2"]),
    ("a_long_label", ["a_long_label"]),
    ("X .EQU 5", ["X               .EQU    5"]),
    ("a_very_long_name_here .EQU 5", ["a_very_long_name_here .EQU 5"]),
    ("HALT   ; end", [" " * 16 + "HALT" + " " * 20 + "; end"]),
    ("    .ASCII_L 'a;b' ; text", [" " * 16 + ".ASCII_L 'a;b'" + " " * 10 + "; text"]),
    ("MOVE R1, 0xEDCBA9A8 ; long enough to push the comment", [
        " " * 16 + "MOVE    R1, 0xEDCBA9A8  ; long enough to push the comment"]),
]


def run(args: List[str]) -> "subprocess.CompletedProcess[str]":
    return subprocess.run([sys.executable, NICEFMT] + args, capture_output=True, text=True)


def main() -> None:
    failed = 0
    for line, want in CASES:
        got = nicefmt.format_line(line)
        if got != want:
            print(f"FAIL {line!r}\n  got  {got}\n  want {want}")
            failed += 1
        elif nicefmt.format_line(want[-1]) != [want[-1]]:
            print(f"FAIL {line!r}: the result is not stable")
            failed += 1
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "x.nasm")
        with open(path, "w") as f:
            f.write("loop MOVE R1, 0\n\tHALT\n")
        r = run([path])
        if r.returncode != 1 or f"{path}:1:" not in r.stderr:
            print(f"FAIL check of a file out of layout: {r.returncode} {r.stderr!r}")
            failed += 1
        r = run(["--write", path])
        with open(path) as f:
            text = f.read()
        if r.returncode != 0 or text != "loop            MOVE    R1, 0\n                HALT\n":
            print(f"FAIL --write: {r.returncode} {text!r}")
            failed += 1
        r = run([path])
        if r.returncode != 0 or r.stderr:
            print(f"FAIL check after --write: {r.returncode} {r.stderr!r}")
            failed += 1
    if failed:
        print(f"FAIL fmt.py: {failed} cases")
        sys.exit(1)
    print(f"PASS fmt.py ({len(CASES)} cases)")


main()
