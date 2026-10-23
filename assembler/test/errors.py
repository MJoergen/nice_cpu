#!/usr/bin/env python3
"""Tests for niceasm that need no file of their own.

CASES are short programs that must fail with exit status 1, print the
expected error, and write no output file. GOOD are programs, some of them
generated, that must assemble to the expected output. WARN are programs
that assemble and print a warning."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import time
from typing import List, Tuple

NICEASM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "niceasm.py")

# (source, expected "line: error: message" from stderr)
CASES: List[Tuple[str, str]] = [
    # Symbols
    (" MOVE R1, X", "1: error: undefined symbol 'X'"),
    # An undefined symbol in an .EQU value, also one that nothing uses
    ("X .EQU nowhere\n HALT", "1: error: undefined symbol 'nowhere'"),
    ("X .EQU 5\nY .EQU nowhere+X\n HALT", "2: error: undefined symbol 'nowhere'"),
    ("X .EQU @foo[R1]\n HALT", "1: error: undefined symbol 'foo'"),
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
    (" .RES", "1: error: .RES takes one count"),
    (" .RES n\nn .DAT 1", "1: error: 'n' must be defined before the .RES"),
    (" .RES -1", "1: error: .RES count -1 is negative"),
    (" .ORG 0xFFFFFFFF\n .RES 2", "2: error: .RES of 2 words at 0xffffffff runs past address 0xffffffff"),
    (" .RES 2\n .ORG 1\n HALT", "3: error: address 0x00000001 is already used by line 1"),
    (" .RES 3\n .ORG 1\n .BLK 1", "3: error: address 0x00000001 is already used by line 1"),
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
    # INT takes the value before it wraps (ISA.md section 10.2).
    (" INT 0xFFFFFFFF+1", "1: error: interrupt vector 4294967296 is out of range 0..255"),
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
    (" MOVE[M R1, R2", "1: error: 'MOVE[M': bad modifier, expected [M], [C], or [CM]"),
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
    # Third round of the review
    ("SP .EQU R13\nX .EQU 5[SP]\n .DAT X", "3: error: 'X' stands for the operand '5[SP]', not a number"),
    ("SP .EQU R13\nX .EQU 5[SP]\n MOVE R1, X+1", "3: error: 'X' stands for the operand '5[SP]', not a number"),
    ("SP .EQU R13\nX .EQU 5[SP]\n INT X", "3: error: 'X' stands for the operand '5[SP]', not a number"),
    ("SP .EQU R13\nX .EQU 5[SP]\nY .EQU X+1\n .DAT Y", "3: error: 'X' stands for the operand '5[SP]', not a number"),
    ("SP .EQU R13\nY .EQU SP+1\n .DAT Y", "2: error: 'SP' is a register where a number is expected"),
    (" MOVE[M] [M] R1, R2", "1: error: 'MOVE[M] [M]': write each modifier once, in one bracket after the mnemonic"),
    # Coverage audit: symbols
    ("1X HALT", "1: error: bad symbol name '1X'"),
    ("L:: HALT", "1: error: bad symbol name 'L:'"),
    ("R00 HALT", "1: error: 'R00' is a register name, not a symbol"),
    ("HALT: HALT", "1: error: 'HALT' is a mnemonic and cannot be a symbol"),
    ("add HALT", "1: error: ADD takes 3 operands, got 1"),
    ("X .EQU", "1: error: .EQU takes one value"),
    ("X .EQU 1 2", "1: error: .EQU takes one value"),
    ("S .EQU 'ab'", "1: error: a string ('ab') is only allowed after .ASCII_L and .ASCII_B"),
    ("A .EQU R1\n .DAT A", "2: error: 'A' is a register where a number is expected"),
    ("A .EQU R1\n .ORG A", "2: error: 'A' is a register where a number is expected"),
    ("A .EQU R1\n INT A", "2: error: 'A' is a register where a number is expected"),
    ("A .EQU R1\n MOVE --A, 1", "2: error: '--A': pre-decrement is not a destination mode, use Rx--"),
    ("X .EQU --R2\n MOVE X, R1", "2: error: 'X' (= '--R2'): pre-decrement is not a destination mode, use Rx--"),
    ("X .EQU @R2\n MOVE R1, @X", "2: error: '@X' (= '@@R2'): there is only one level of '@'"),
    (" MOVE X--, R1\nX .EQU 3", "1: error: 'X' stands for '3', not a register"),
    ("X .EQU L\n .ORG X\nL HALT", "2: error: 'L' must be defined before the .ORG"),
    # Coverage audit: numbers and expressions
    (" MOVE R1, $10", "1: error: expected a number or a symbol at '$10'"),
    (" MOVE R1, #5", "1: error: expected a number or a symbol at '#5'"),
    (" INT @5", "1: error: expected a number or a symbol at '@5'"),
    (" INT R1", "1: error: 'R1' is a register where a number is expected"),
    (" .DAT 'a'", "1: error: a string ('a') is only allowed after .ASCII_L and .ASCII_B"),
    (" .DAT 4294967296", "1: error: number too large: '4294967296'"),
    (" .DAT 0x", "1: error: bad number '0x'"),
    (" .DAT 0b2", "1: error: bad number '0b2'"),
    (" .DAT 1a", "1: error: bad number '1a'"),
    (" .DAT --1", "1: error: bad expression '--1'"),
    (" .DAT +-1", "1: error: bad expression '+-1'"),
    (" .DAT 1++1", "1: error: bad expression '1++1'"),
    (" .DAT -", "1: error: bad expression '-'"),
    # Coverage audit: operand modes
    (" MOVE R1, --5", "1: error: bad expression '--5'"),
    (" MOVE R1, 5++", "1: error: bad expression '5++'"),
    (" MOVE R1, 5[R2]x", "1: error: '5[R2]x': bad index, expected c[Rx]"),
    (" MOVE R1, [R2]", "1: error: '[R2]': missing constant"),
    (" MOVE R1, R015", "1: error: 'R015' is not a register (the registers are R0 to R15)"),
    # Coverage audit: a '*' inside a word does not start a comment
    (" MOVE R1, R2*c", "1: error: expected a number or a symbol at 'R2*c'"),
    # Coverage audit: operand counts, conditions, and modifiers
    (" RTI 1", "1: error: RTI takes 0 operands, got 1"),
    (" INT 1, 2", "1: error: INT takes 1 operand, got 2"),
    (" ONE R1, R2", "1: error: ONE takes 1 operand, got 2"),
    (" DBL R1, R2, R3", "1: error: DBL takes 2 operands, got 3"),
    (" 0<0 R1, R2, R3, R4", "1: error: 0<0 takes 3 operands, got 4"),
    (" RTI[M]", "1: error: RTI takes no modifiers"),
    (" INT[C] 1", "1: error: INT takes no modifiers"),
    (" SHL[CM] R1, R2, R3", "1: error: [C] is only allowed on ALU instructions"),
    (" MOVE[] R1, R2", "1: error: 'MOVE[]': bad modifier"),
    (" MOVE[CMC] R1, R2", "1: error: 'MOVE[CMC]': bad modifier"),
    ("? HALT", "1: error: bad condition '?'"),
    ("?!! HALT", "1: error: bad condition '?!!'"),
    ("?ZZ HALT", "1: error: bad condition '?ZZ'"),
    ("?Z ?C HALT", "1: error: unknown mnemonic '?C'"),
    ("?Z L HALT", "1: error: unknown mnemonic 'L'"),
    ("?Z MOV R1, R2", "1: error: unknown mnemonic 'MOV'"),
    # Coverage audit: directives
    (" .ORG 1 2", "1: error: .ORG takes one address"),
    (" .BLK", "1: error: .BLK takes one count"),
    (" .ASCII_B", "1: error: .ASCII_B takes one quoted string"),
    (" .ASCII_L x'ab'", "1: error: .ASCII_L takes one quoted string"),
    (' .ASCII_L "ab"x', "1: error: text after the string \"ab\": to put \" in a string, quote the string with '"),
    (" .ORG 0xFFFFFFFF\n MOVE R1, 5\n .ORG 0\n HALT", "4: error: address 0x00000000 is already used by line 2"),
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
    (" .ORG 0xFFFFFFFE\n .RES 2\n HALT", "00000000 0c000000\n"),
    (chain(1200, False), "00000000 00000007\n"),
    (chain(1200, True), "00000000 00000007\n"),
    (chain(1200, False, "+1"), "00000000 000004b7\n"),
    (chain(1200, True, "+1"), "00000000 000004b7\n"),
    # Coverage audit
    (" .ORG -1\n HALT", "ffffffff 0c000000\n"),
    (" .ORG 0xFFFFFFFF+2\n HALT", "00000001 0c000000\n"),
    (" .ORG 5\n HALT\n .ORG 2\n HALT", "00000002 0c000000\n00000005 0c000000\n"),
    (" .ORG 0xFFFFFFFF\n .DAT 1, 2", "00000000 00000002\nffffffff 00000001\n"),
    (" .DAT 1 2,3", "00000000 00000001\n00000001 00000002\n00000002 00000003\n"),
    # Symbols are case-sensitive.
    ("x .EQU 1\nX .EQU 2\n .DAT x, X", "00000000 00000001\n00000001 00000002\n"),
    # One word that is not a mnemonic is a label, even when indented (with
    # a warning, see WARN).
    (" HLT\n .DAT HLT", "00000000 00000000\n"),
    # The source is read byte by byte: UTF-8 'e acute' is two characters.
    (' .ASCII_L "\xc3\xa9"', "00000000 000000c3\n00000001 000000a9\n00000002 00000000\n"),
    ("\t\n   \n* only comments\n; and blank lines", ""),
]

# (exact file contents, expected output): GOOD cases that need the input
# without the newline that run_good() adds.
RAW: List[Tuple[str, str]] = [
    ("", ""),
    (" HALT", "00000000 0c000000\n"),
]

# (source, expected stderr, exactly): the format of several errors, in line
# order, and their count. Line 2 is found before pass 1, line 1 in pass 1.
STDERR: List[Tuple[str, str]] = [
    (" MOV R1, R2\nX .EQU @@R1\n HALT",
     "{src}:1: error: unknown mnemonic 'MOV'\n"
     "{src}:2: error: '@@R1': there is only one level of '@'\n"
     "2 errors\n"),
    # An undefined symbol in a used .EQU is reported once, where it is defined.
    ("X .EQU nowhere\n MOVE R1, X\n .DAT X+1\n HALT",
     "{src}:1: error: undefined symbol 'nowhere'\n"
     "1 error\n"),
    # A warning is printed with the errors.
    (" HLT\n MOV R1, R2",
     "{src}:1: warning: 'HLT' alone on an indented line is read as a label; "
     "write 'HLT:' if one is meant\n"
     "{src}:2: error: unknown mnemonic 'MOV'\n"
     "1 error\n"),
]

# (source, expected output, expected stderr, exactly): programs that
# assemble with exit status 0 and print warnings, or none.
WARN: List[Tuple[str, str, str]] = [
    (" HLT\n .DAT HLT",
     "00000000 00000000\n",
     "{src}:1: warning: 'HLT' alone on an indented line is read as a label; "
     "write 'HLT:' if one is meant\n"),
    ("\tRIT\n HALT",
     "00000000 0c000000\n",
     "{src}:1: warning: 'RIT' alone on an indented line is read as a label; "
     "write 'RIT:' if one is meant\n"),
    # No warning for a label at the start of a line, or with ':'
    ("loop\n  done:\n HALT", "00000000 0c000000\n", ""),
]


def run_case(tmp: str, source: str, expected: str) -> List[str]:
    """Returns a list of failure descriptions, empty if the case passed."""
    src = os.path.join(tmp, "t.nasm")
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


def run_good(tmp: str, source: str, expected: str, newline: str = "\n") -> List[str]:
    """Returns a list of failure descriptions, empty if the case passed."""
    src = os.path.join(tmp, "t.nasm")
    out = os.path.join(tmp, "t.bin")
    with open(src, "w", encoding="latin-1") as f:
        f.write(source + newline)
    p = subprocess.run([sys.executable, NICEASM, src], capture_output=True, text=True)
    if p.returncode != 0:
        return [f"exit status {p.returncode}, expected 0:\n{p.stderr}"]
    with open(out) as f:
        got = f.read()
    return [] if got == expected else [f"expected:\n{expected}got:\n{got}"]


def run_raw(tmp: str, source: str, expected: str) -> List[str]:
    return run_good(tmp, source, expected, "")


def run_stderr(tmp: str, source: str, expected: str) -> List[str]:
    """Returns a list of failure descriptions, empty if the case passed."""
    src = os.path.join(tmp, "t.nasm")
    with open(src, "w", encoding="latin-1") as f:
        f.write(source + "\n")
    p = subprocess.run([sys.executable, NICEASM, src], capture_output=True, text=True)
    want = expected.format(src=src)
    if p.returncode != 1 or p.stderr != want:
        return [f"exit status {p.returncode}, expected 1; expected:\n{want}got:\n{p.stderr}"]
    return []


def run_warn(tmp: str, source: str, expected: str, stderr: str) -> List[str]:
    """Returns a list of failure descriptions, empty if the case passed."""
    src = os.path.join(tmp, "t.nasm")
    out = os.path.join(tmp, "t.bin")
    with open(src, "w", encoding="latin-1") as f:
        f.write(source + "\n")
    p = subprocess.run([sys.executable, NICEASM, src], capture_output=True, text=True)
    want = stderr.format(src=src)
    if p.returncode != 0 or p.stderr != want:
        return [f"exit status {p.returncode}, expected 0; expected:\n{want}got:\n{p.stderr}"]
    with open(out) as f:
        got = f.read()
    return [] if got == expected else [f"expected:\n{expected}got:\n{got}"]


def run_cli(tmp: str, args: List[str], status: int, message: str) -> List[str]:
    """Runs niceasm with args, in tmp, and checks the exit status and that
    the last line of stderr is message. Returns failure descriptions."""
    p = subprocess.run([sys.executable, NICEASM] + args, capture_output=True, text=True,
                       cwd=tmp)
    lines = p.stderr.splitlines()
    problems = []
    if p.returncode != status:
        problems.append(f"exit status {p.returncode}, expected {status}")
    if not lines or lines[-1] != message or "Traceback" in p.stderr:
        problems.append(f"expected '{message}', got:\n{p.stderr}")
    return problems


# (arguments, exit status, last line of stderr), run in a directory that
# holds ok.nasm (" HALT") and an empty directory dir.
CLI: List[Tuple[List[str], int, str]] = [
    (["missing.nasm"], 1, "missing.nasm: No such file or directory"),
    (["dir"], 1, "dir: Is a directory"),
    (["-o", "ok.nasm", "ok.nasm"], 1, "ok.nasm: the output file would overwrite the input; use -o"),
    (["-o", "nodir/ok.bin", "ok.nasm"], 1, "nodir/ok.bin: No such file or directory"),
    (["-o", "dir", "ok.nasm"], 1, "dir: Is a directory"),
    ([], 2, "niceasm.py: error: the following arguments are required: input"),
    (["ok.nasm", "x.nasm"], 2, "niceasm.py: error: unrecognized arguments: x.nasm"),
]


def main() -> None:
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        cases = ([(run_case, s, e) for s, e in CASES] + [(run_good, s, e) for s, e in GOOD]
                 + [(run_raw, s, e) for s, e in RAW] + [(run_stderr, s, e) for s, e in STDERR])
        for run, source, expected in cases:
            problems = run(tmp, source, expected)
            if problems:
                failed += 1
                print(f"FAIL {source[:60]!r}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))
        for source, expected, stderr in WARN:
            problems = run_warn(tmp, source, expected, stderr)
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
        # An operand of 50,000 "[" and no "]" is rejected at once, not in quadratic time.
        slow = os.path.join(tmp, "slow.nasm")
        with open(slow, "w") as f:
            f.write(" MOVE R1, 5" + "[" * 50000 + "\n")
        t0 = time.monotonic()
        p = subprocess.run([sys.executable, NICEASM, "-o", os.path.join(tmp, "slow.bin"), slow],
                           capture_output=True, text=True)
        if p.returncode != 1 or "bad index" not in p.stderr or time.monotonic() - t0 > 5:
            failed += 1
            print("FAIL a long run of [ in an operand")
        # The command line and file errors.
        cli = os.path.join(tmp, "cli")
        os.makedirs(os.path.join(cli, "dir"))
        with open(os.path.join(cli, "ok.nasm"), "w") as f:
            f.write(" HALT\n")
        for args, status, message in CLI:
            problems = run_cli(cli, args, status, message)
            if problems:
                failed += 1
                print(f"FAIL niceasm.py {' '.join(args)}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))
        # -o writes there, and not to the default output name.
        p = subprocess.run([sys.executable, NICEASM, "-o", "out.txt", "ok.nasm"], cwd=cli,
                           capture_output=True, text=True)
        with open(os.path.join(cli, "out.txt")) as f:
            got = f.read()
        if (p.returncode != 0 or got != "00000000 0c000000\n"
                or os.path.exists(os.path.join(cli, "ok.bin"))):
            failed += 1
            print("FAIL -o out.txt")
        # --symbols writes the labels, sorted by address and then by name.
        with open(os.path.join(cli, "sym.nasm"), "w") as f:
            f.write("a MOVE R1, 1\nb\nc HALT\n.ORG 0x10\nd HALT\n")
        p = subprocess.run([sys.executable, NICEASM, "--symbols", "sym.txt", "sym.nasm"], cwd=cli,
                           capture_output=True, text=True)
        with open(os.path.join(cli, "sym.txt")) as f:
            got = f.read()
        if p.returncode != 0 or got != "00000000 a\n00000002 b\n00000002 c\n00000010 d\n":
            failed += 1
            print("FAIL --symbols sym.txt")
    total = len(CASES) + len(GOOD) + len(RAW) + len(STDERR) + len(WARN) + len(CLI) + 4
    print(f"PASS errors ({total} cases)" if not failed else f"FAIL errors ({failed} of {total})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
