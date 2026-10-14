#!/usr/bin/env python3
"""Tests for niceasm that need no file of their own.

CASES are short programs that must fail with exit status 1, print the
expected error, and write no output file. GOOD are programs, some of them
generated, that must assemble to the expected output."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from typing import List, Tuple

NICEASM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "niceasm.py")

# (source, expected "line: error: message" from stderr)
CASES: List[Tuple[str, str]] = [
    # Symbols
    (" MOVE R1, X", "1: error: undefined symbol 'X'"),
    ("A HALT\nA HALT", "2: error: symbol 'A' is already defined on line 1"),
    ("A .EQU 1\nA .EQU 2", "2: error: symbol 'A' is already defined on line 1"),
    ("A .EQU 1\nA HALT", "2: error: symbol 'A' is already defined on line 1"),
    ("SP .EQU R13\nSP MOVE R1, R2", "2: error: symbol 'SP' is already defined on line 1"),
    ("A .EQU B\nB .EQU A", "2: error: 'B': .EQU definitions form a loop"),
    ("X .EQU X+1\n MOVE R1, X", "1: error: 'X': .EQU definitions form a loop"),
    ("R1 .EQU 5\n MOVE R1, R2", "1: error: 'R1' is a register name, not a symbol"),
    ("r16 .EQU 5", "1: error: 'r16' looks like a register and cannot be a symbol (the registers are R0 to R15)"),
    ("R16 .DAT 1", "1: error: 'R16' looks like a register and cannot be a symbol (the registers are R0 to R15)"),
    ("ADD .EQU 5", "1: error: 'ADD' is a mnemonic and cannot be a symbol"),
    ("X .EQU 0xZZ\n MOVE R1, X\n MOVE R2, X", "1: error: bad number '0xZZ'"),
    (" MOVE R1, R16", "1: error: 'R16' is not a register (the registers are R0 to R15)"),
    (" MOVE R1, R2+1", "1: error: 'R2' is a register where a number is expected"),
    ("X .EQU @R2\n MOVE R1, X+1", "2: error: 'X' stands for the operand '@R2', not a number"),
    # Addresses
    (" .ORG 0\n HALT\n .ORG 0\n HALT", "4: error: address 0x00000000 is already used by line 2"),
    (" .BLK 2\n .ORG 1\n HALT", "3: error: address 0x00000001 is already used by line 1"),
    (" .ORG later\nlater HALT", "1: error: 'later' must be defined before the .ORG"),
    (" .BLK n\nn .DAT 1", "1: error: 'n' must be defined before the .BLK"),
    (" .BLK -1", "1: error: .BLK count -1 is negative"),
    ("N .EQU -1\n .BLK N", "2: error: .BLK count -1 is negative"),
    (" .ORG 0xFFFFFFFF\n .BLK 2", "2: error: .BLK of 2 words at 0xffffffff runs past address 0xffffffff"),
    # Operand modes
    (" MOVE --R1, R2", "1: error: '--R1': pre-decrement is not a destination mode, use Rx--"),
    (" MOVE R1, R2--", "1: error: 'R2--': post-decrement is only a direct destination mode"),
    (" MOVE @R1--, R2", "1: error: '@R1--': post-decrement is only a direct destination mode"),
    ("X .EQU R2--\n MOVE R1, X", "2: error: 'X' (= 'R2--'): post-decrement is only a direct destination mode"),
    (" MOVE R1, 5[X]", "1: error: '5[X]': 'X' is not a register"),
    (" MOVE R1, @@R2", "1: error: '@@R2': there is only one level of '@'"),
    (" MOVE R1, 'A'", "1: error: a string ('A') is only allowed after .ASCII_L and .ASCII_B"),
    # Operand counts
    (" ONE", "1: error: ONE takes 1 operand, got 0"),
    (" MOVE R1", "1: error: MOVE takes 2 operands, got 1"),
    (" ADD R1, R2", "1: error: ADD takes 3 operands, got 2"),
    (" SHL R1, R2", "1: error: SHL takes 3 operands, got 2"),
    (" HALT R1", "1: error: HALT takes 0 operands, got 1"),
    (" INT", "1: error: INT takes 1 operand, got 0"),
    (" INT 256", "1: error: interrupt vector 256 is out of range 0..255"),
    (" INT -1", "1: error: interrupt vector -1 is out of range 0..255"),
    (" INT v\n .ORG 256\nv HALT", "1: error: interrupt vector 256 is out of range 0..255"),
    # Conditions and modifiers
    ("?Q MOVE R1, R2", "1: error: bad condition '?Q'"),
    ("?Z", "1: error: condition without an instruction"),
    (" MOVE[X] R1, R2", "1: error: 'MOVE[X]': bad modifier"),
    (" MOVE[MM] R1, R2", "1: error: 'MOVE[MM]': bad modifier"),
    (" SHL[C] R1, R2, R3", "1: error: [C] is only allowed on ALU instructions"),
    (" HALT[M]", "1: error: HALT takes no modifiers"),
    ("?Z .DAT 1", "1: error: a directive cannot have a condition"),
    ("?1 .DAT 1", "1: error: a directive cannot have a condition"),
    ("?1 .ORG 5", "1: error: a directive cannot have a condition"),
    (" MOVE [M] R1, R2", "1: error: 'MOVE [M]': write the modifier without a space, as MOVE[M]"),
    (" MOVE[M R1, R2", "1: error: 'MOVE[M': bad modifier, expected [M], [C] or [CM]"),
    # Mnemonics and directives
    (" MOV R1, R2", "1: error: unknown mnemonic 'MOV'"),
    ("LOOP MOV R1, R2", "1: error: unknown mnemonic 'MOV' ('LOOP' is read as a label)"),
    (" .DATA 1", "1: error: unknown directive '.DATA'"),
    (".DATA", "1: error: unknown directive '.DATA'"),
    ("X .DATA 1", "1: error: unknown directive '.DATA'"),
    (" .EQU 5", "1: error: .EQU needs a name"),
    (" .ORG", "1: error: .ORG takes one address"),
    (" .DAT", "1: error: .DAT takes at least one value"),
    (" .ASCII_L abc", "1: error: .ASCII_L takes one quoted string"),
    (" .ASCII_L 'it's'", "1: error: text after the string 'it': to put ' in a string, quote the string with \""),
    # Lexical
    (",MOVE R1, R2\n MOVE R3, R4", "1: error: unexpected ',' at the start of the line"),
    ("   'oops\n MOVE R3, R4", "1: error: unterminated string 'oops"),
    (" .ASCII_L 'oops", "1: error: unterminated string 'oops"),
    (" MOVE R1,,R2", "1: error: two commas with no operand between them"),
    (" MOVE R1, R2,", "1: error: ',' at the end of the line has no operand after it"),
    (" .DAT 0xZZ", "1: error: bad number '0xZZ'"),
    (" .DAT 1_000", "1: error: bad number '1_000'"),
    (" .DAT 0x1_0", "1: error: bad number '0x1_0'"),
    (" .DAT 0x100000000", "1: error: number too large: '0x100000000'"),
    (" .DAT 1+", "1: error: bad expression '1+'"),
    ("\xef\xbb\xbf MOVE R1, X", "1: error: undefined symbol 'X'"),
    # Second round of the review
    (" HALT\n .ORG 0\n .BLK 1", "3: error: address 0x00000000 is already used by line 1"),
    (" .BLK 3\n .ORG 1\n .BLK 1", "3: error: address 0x00000001 is already used by line 1"),
    ("X .EQU R1++\n MOVE R2, --X", "2: error: 'X' stands for 'R1++', not a register"),
    ("X .EQU 5\n MOVE R2, X++", "2: error: 'X' stands for '5', not a register"),
    (" MOVE[M] [C] R1, R2", "1: error: 'MOVE[M] [C]': write all modifiers in one bracket, as MOVE[MC]"),
    (" .ASCII_L 'abc' 'def'", "1: error: .ASCII_L takes one string, got 2"),
    ("A HALT\nA .EQU 1", "2: error: symbol 'A' is already defined on line 1"),
    ("A: HALT\nA: .EQU 1", "2: error: symbol 'A' is already defined on line 1"),
    (" MOVE , R1, R2", "1: error: ',' after 'MOVE': a comma only separates operands"),
    ("L , HALT", "1: error: ',' after 'L': a comma only separates operands"),
    ("?Z , HALT", "1: error: ',' after '?Z': a comma only separates operands"),
    ("X .EQU, 5", "1: error: ',' after '.EQU': a comma only separates operands"),
]


def chain(n: int, reverse: bool, step: str = "") -> str:
    """n .EQU names, A1 to An, each defined as the one before plus step,
    with A0 = 7, followed by .DAT An."""
    lines = [f"A{i} .EQU A{i - 1}{step}" for i in range(1, n + 1)]
    if reverse:
        lines.reverse()
    return "\n".join(["A0 .EQU 7"] + lines + [f" .DAT A{n}"])


# (source, expected output)
GOOD: List[Tuple[str, str]] = [
    ("X: .EQU 5\n .DAT X", "00000000 00000005\n"),
    (" ADD R1 R2, R3", "00000000 00604103\n"),
    (" .ORG 0xFFFFFFFE\n .BLK 2\n HALT",
     "00000000 0c000000\nfffffffe 00000000\nffffffff 00000000\n"),
    (chain(1200, False), "00000000 00000007\n"),
    (chain(1200, True), "00000000 00000007\n"),
    (chain(1200, False, "+1"), "00000000 000004b7\n"),
    (chain(1200, True, "+1"), "00000000 000004b7\n"),
]


def run_case(tmp: str, source: str, expected: str) -> List[str]:
    """Returns a list of failure descriptions, empty if the case passed."""
    src = os.path.join(tmp, "t.asm")
    out = os.path.join(tmp, "t.bin")
    with open(src, "w", encoding="latin-1") as f:
        f.write(source + "\n")
    if os.path.exists(out):
        os.remove(out)
    p = subprocess.run([sys.executable, NICEASM, src], capture_output=True, text=True)
    problems = []
    if p.returncode != 1:
        problems.append(f"exit status {p.returncode}, expected 1")
    if f"{src}:{expected}" not in p.stderr.splitlines():
        problems.append(f"expected '{expected}', got:\n{p.stderr}")
    if os.path.exists(out):
        problems.append("an output file was written")
    return problems


def run_good(tmp: str, source: str, expected: str) -> List[str]:
    """Returns a list of failure descriptions, empty if the case passed."""
    src = os.path.join(tmp, "t.asm")
    out = os.path.join(tmp, "t.bin")
    with open(src, "w", encoding="latin-1") as f:
        f.write(source + "\n")
    p = subprocess.run([sys.executable, NICEASM, src], capture_output=True, text=True)
    if p.returncode != 0:
        return [f"exit status {p.returncode}, expected 0:\n{p.stderr}"]
    with open(out) as f:
        got = f.read()
    return [] if got == expected else [f"expected:\n{expected}got:\n{got}"]


def main() -> None:
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        cases = [(run_case, s, e) for s, e in CASES] + [(run_good, s, e) for s, e in GOOD]
        for run, source, expected in cases:
            problems = run(tmp, source, expected)
            if problems:
                failed += 1
                print(f"FAIL {source[:60]!r}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))
        # The default output name must not overwrite the input.
        src = os.path.join(tmp, "prog.bin")
        with open(src, "w") as f:
            f.write(" HALT\n")
        p = subprocess.run([sys.executable, NICEASM, src], capture_output=True, text=True)
        with open(src) as f:
            kept = f.read() == " HALT\n"
        if p.returncode == 0 or not kept:
            failed += 1
            print("FAIL output overwrites the input")
    total = len(CASES) + len(GOOD) + 1
    print(f"PASS errors ({total} cases)" if not failed else f"FAIL errors ({failed} of {total})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
