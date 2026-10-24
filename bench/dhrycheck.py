#!/usr/bin/env python3
"""Checks the output of Dhrystone 2.1 against the values it should print.

    ./dhrycheck.py [--runs N] FILE   check the output in FILE
    ./dhrycheck.py --test            check the checker on good and bad outputs

Dhrystone prints the final value of each of its variables, and under it
the line "should be:" with the value it should have. This checks the 22
pairs in order against a table of its own: the name, the value, and the
"should be" line. Arr_2_Glob[8][7] is the number of runs plus 10, and the
two Ptr_Comp values are one address, not 0. The number of runs is the one
of the "Execution starts" line, and with --runs N it must be N, the
number in dhrystone/dhry.input. The port's three result lines
(README.md, Dhrystone) must agree: the same number of runs, cycles above
0, the cycles of one run their quotient, and the Dhrystone MIPS per MHz
10^9 N / (1757 cycles) with three decimals. One line: PASS, or FAIL and
what was wrong.
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import List, Optional, Tuple

RUNS = re.compile(r"Execution starts, (\d+) runs through Dhrystone")
VALUE = re.compile(r"^\s*([^:]+):\s*(.*?)\s*$")
CYCLES = re.compile(r"^Cycles for (\d+) runs through Dhrystone: (\d+)$")
ONE_RUN = re.compile(r"^Cycles for one run through Dhrystone: +(\d+)$")
MIPS = re.compile(r"^Dhrystone MIPS per MHz: +(\d+\.\d{3})$")

# The 22 values in order: (name, value, "should be" line). RUNS_10 is the
# number of runs plus 10, and PTR an address, the same twice and not 0.
RUNS_10 = "Number_Of_Runs + 10"
PTR = "(implementation-dependent)"
PTR_SAME = "(implementation-dependent), same as above"
SOME = "DHRYSTONE PROGRAM, SOME STRING"
FIRST = "DHRYSTONE PROGRAM, 1'ST STRING"
SECOND = "DHRYSTONE PROGRAM, 2'ND STRING"
EXPECTED: List[Tuple[str, str, str]] = [
    ("Int_Glob", "5", "5"),
    ("Bool_Glob", "1", "1"),
    ("Ch_1_Glob", "A", "A"),
    ("Ch_2_Glob", "B", "B"),
    ("Arr_1_Glob[8]", "7", "7"),
    ("Arr_2_Glob[8][7]", RUNS_10, RUNS_10),
    ("Ptr_Comp", PTR, PTR),
    ("Discr", "0", "0"),
    ("Enum_Comp", "2", "2"),
    ("Int_Comp", "17", "17"),
    ("Str_Comp", SOME, SOME),
    ("Ptr_Comp", PTR, PTR_SAME),
    ("Discr", "0", "0"),
    ("Enum_Comp", "1", "1"),
    ("Int_Comp", "18", "18"),
    ("Str_Comp", SOME, SOME),
    ("Int_1_Loc", "5", "5"),
    ("Int_2_Loc", "13", "13"),
    ("Int_3_Loc", "7", "7"),
    ("Enum_Loc", "1", "1"),
    ("Str_1_Loc", FIRST, FIRST),
    ("Str_2_Loc", SECOND, SECOND),
]


def first(pattern: re.Pattern[str], lines: List[str]) -> Optional[re.Match[str]]:
    """The match of the first line that matches pattern, if any."""
    for line in lines:
        m = pattern.match(line)
        if m:
            return m
    return None


def check(text: str, runs: Optional[int] = None) -> List[str]:
    """The errors in Dhrystone's output text, none if it is right. With
    runs, the number of runs must be it."""
    lines = text.splitlines()
    m = RUNS.search(text)
    if not m:
        return ["no 'Execution starts' line"]
    n = int(m.group(1))
    errors: List[str] = []
    if runs is not None and n != runs:
        errors.append(f"{n} runs, expected {runs}")
    if n == 0:
        return errors + ["0 runs"]

    # The pairs, in order: (name, value, "should be" line).
    pairs: List[Tuple[str, str, str]] = []
    for i in range(1, len(lines)):
        m = VALUE.match(lines[i])
        if not m or m.group(1).strip() != "should be":
            continue
        v = VALUE.match(lines[i - 1])
        if not v:
            errors.append(f"line {i}: no value above 'should be'")
            continue
        pairs.append((v.group(1).strip(), v.group(2), m.group(2)))
    if len(pairs) != len(EXPECTED):
        errors.append(f"{len(pairs)} values, expected {len(EXPECTED)}")
    ptr = ""
    for k, ((name, got, said), (want_name, want, want_said)) in enumerate(zip(pairs, EXPECTED), 1):
        if name != want_name:
            errors.append(f"value {k} is {name}, expected {want_name}")
            continue
        if want == RUNS_10:
            want = str(n + 10)
        elif want == PTR:
            if not ptr:
                ptr = got
                if not re.fullmatch(r"[1-9]\d*", got):
                    errors.append(f"{name} is {got!r}, not an address")
            want = ptr
        if got != want:
            errors.append(f"{name} is {got!r}, should be {want!r}")
        if said != want_said:
            errors.append(f"{name}'s 'should be' is {said!r}, expected {want_said!r}")

    # The result lines of the port.
    cycles_m = first(CYCLES, lines)
    one_m = first(ONE_RUN, lines)
    mips_m = first(MIPS, lines)
    for what, found in (("the cycles", cycles_m), ("the cycles of one run", one_m),
                        ("the Dhrystone MIPS per MHz", mips_m)):
        if found is None:
            errors.append(f"no line with {what}")
    if cycles_m is None or one_m is None or mips_m is None:
        return errors
    if int(cycles_m.group(1)) != n:
        errors.append(f"the cycles are for {cycles_m.group(1)} runs, not {n}")
    cycles = int(cycles_m.group(2))
    if cycles == 0:
        return errors + ["0 cycles"]
    if int(one_m.group(1)) != cycles // n:
        errors.append(f"{one_m.group(1)} cycles for one run, expected {cycles // n}")
    milli = 10**9 * n // (1757 * cycles)
    want = f"{milli // 1000}.{milli % 1000:03d}"
    if mips_m.group(1) != want:
        errors.append(f"{mips_m.group(1)} Dhrystone MIPS per MHz, expected {want}")
    return errors


# --test: the emulator's output for 100 runs, from "Execution starts", and
# a mistake put into each part of it.
GOOD = """\
Execution starts, 100 runs through Dhrystone
Execution ends

Final values of the variables used in the benchmark:

Int_Glob:            5
        should be:   5
Bool_Glob:           1
        should be:   1
Ch_1_Glob:           A
        should be:   A
Ch_2_Glob:           B
        should be:   B
Arr_1_Glob[8]:       7
        should be:   7
Arr_2_Glob[8][7]:    110
        should be:   Number_Of_Runs + 10
Ptr_Glob->
  Ptr_Comp:          15816
        should be:   (implementation-dependent)
  Discr:             0
        should be:   0
  Enum_Comp:         2
        should be:   2
  Int_Comp:          17
        should be:   17
  Str_Comp:          DHRYSTONE PROGRAM, SOME STRING
        should be:   DHRYSTONE PROGRAM, SOME STRING
Next_Ptr_Glob->
  Ptr_Comp:          15816
        should be:   (implementation-dependent), same as above
  Discr:             0
        should be:   0
  Enum_Comp:         1
        should be:   1
  Int_Comp:          18
        should be:   18
  Str_Comp:          DHRYSTONE PROGRAM, SOME STRING
        should be:   DHRYSTONE PROGRAM, SOME STRING
Int_1_Loc:           5
        should be:   5
Int_2_Loc:           13
        should be:   13
Int_3_Loc:           7
        should be:   7
Enum_Loc:            1
        should be:   1
Str_1_Loc:           DHRYSTONE PROGRAM, 1'ST STRING
        should be:   DHRYSTONE PROGRAM, 1'ST STRING
Str_2_Loc:           DHRYSTONE PROGRAM, 2'ND STRING
        should be:   DHRYSTONE PROGRAM, 2'ND STRING

Cycles for 100 runs through Dhrystone: 155923
Cycles for one run through Dhrystone:      1559
Dhrystone MIPS per MHz:                    0.365
"""


def last(text: str, old: str, new: str) -> str:
    """text with the last old replaced by new."""
    i = text.rindex(old)
    return text[:i] + new + text[i + len(old):]


# (what is wrong, the output, --runs, an error that must be reported)
BAD: List[Tuple[str, str, Optional[int], str]] = [
    ("other runs", GOOD, 50, "100 runs, expected 50"),
    ("a value", GOOD.replace("Int_Glob:            5", "Int_Glob:            6"),
     100, "Int_Glob is '6', should be '5'"),
    ("a value and its should be", GOOD.replace("Int_Glob:            5\n        should be:   5",
                                               "Int_Glob:            6\n        should be:   6"),
     100, "Int_Glob's 'should be' is '6', expected '5'"),
    ("a should be", GOOD.replace("should be:   Number_Of_Runs + 10", "should be:   110"),
     100, "Arr_2_Glob[8][7]'s 'should be' is '110', expected 'Number_Of_Runs + 10'"),
    ("a name", GOOD.replace("Int_1_Loc:", "Foo:"), 100, "value 17 is Foo, expected Int_1_Loc"),
    ("a pair left out", GOOD.replace("Enum_Loc:            1\n        should be:   1\n", ""),
     100, "21 values, expected 22"),
    ("a null pointer", GOOD.replace("15816", "0"), 100, "Ptr_Comp is '0', not an address"),
    ("two pointers", last(GOOD, "15816", "15817"), 100, "Ptr_Comp is '15817', should be '15816'"),
    ("no cycles", GOOD.replace("Dhrystone: 155923", "Dhrystone: 0"), 100, "0 cycles"),
    ("the runs of the cycles", GOOD.replace("Cycles for 100 runs", "Cycles for 7 runs"),
     100, "the cycles are for 7 runs, not 100"),
    ("the cycles of one run", GOOD.replace("      1559", "      1558"),
     100, "1558 cycles for one run, expected 1559"),
    ("the MIPS", GOOD.replace("0.365", "0.364"), 100, "0.364 Dhrystone MIPS per MHz, expected 0.365"),
    ("no MIPS line", GOOD.replace("Dhrystone MIPS per MHz:                    0.365\n", ""),
     100, "no line with the Dhrystone MIPS per MHz"),
    ("no runs", GOOD.replace("Execution starts, 100 runs", "Execution starts, 0 runs"), None, "0 runs"),
]


def test() -> None:
    good = check(GOOD, 100)
    if good:
        sys.exit(f"FAIL dhrycheck.py --test: the good output: {good}")
    for what, text, runs, error in BAD:
        errors = check(text, runs)
        if error not in errors:
            sys.exit(f"FAIL dhrycheck.py --test: {what}: {errors}")
    print(f"PASS dhrycheck.py --test ({len(BAD) + 1} cases)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--runs", type=int, help="the number of runs the output must have")
    ap.add_argument("--test", action="store_true")
    args = ap.parse_args()
    if args.test:
        test()
        return
    if not args.file:
        ap.error("give a FILE or --test")
    with open(args.file) as f:
        errors = check(f.read(), args.runs)
    if errors:
        sys.exit("FAIL dhrystone: " + "; ".join(errors))
    print("PASS dhrystone")


if __name__ == "__main__":
    main()
