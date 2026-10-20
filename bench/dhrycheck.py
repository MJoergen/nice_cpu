#!/usr/bin/env python3
"""Checks the output of Dhrystone 2.1 against the values it should print.

    ./dhrycheck.py FILE     check the output in FILE
    ./dhrycheck.py --test   check the checker on a good and a bad output

Dhrystone prints the final value of each of its variables, and under it
the line "should be:" with the value it should have. This checks every
pair. "Number_Of_Runs + 10" is the number of runs of the "Execution
starts" line plus 10, "(implementation-dependent)" is any value, and
"(implementation-dependent), same as above" is the value of the pointer
before it. It also checks that the port's result lines are there
(README.md, Dhrystone). One line: PASS or FAIL, and what was wrong.
"""

import argparse
import re
import sys
from typing import List

RUNS = re.compile(r"Execution starts, (\d+) runs through Dhrystone")
VALUE = re.compile(r"^\s*([^:]+):\s*(.*?)\s*$")
RESULTS = [
    re.compile(r"^Cycles for \d+ runs through Dhrystone: \d+$"),
    re.compile(r"^Cycles for one run through Dhrystone: +\d+$"),
    re.compile(r"^Dhrystone MIPS per MHz: +\d+\.\d{3}$"),
]


def check(text: str) -> List[str]:
    """The errors in Dhrystone's output text, none if it is right."""
    lines = text.splitlines()
    m = RUNS.search(text)
    if not m:
        return ["no 'Execution starts' line"]
    runs = int(m.group(1))
    errors: List[str] = []
    pairs = 0
    previous = ""
    for i in range(1, len(lines)):
        m = VALUE.match(lines[i])
        if not m or m.group(1) != "should be":
            continue
        v = VALUE.match(lines[i - 1])
        if not v:
            errors.append(f"line {i}: no value above 'should be'")
            continue
        name, got, want = v.group(1), v.group(2), m.group(2)
        pairs += 1
        if want == "Number_Of_Runs + 10":
            want = str(runs + 10)
        elif want == "(implementation-dependent)":
            previous = got
            continue
        elif want == "(implementation-dependent), same as above":
            want = previous
        if got != want:
            errors.append(f"{name.strip()} is {got!r}, should be {want!r}")
    if pairs != 22:
        errors.append(f"{pairs} values, expected 22")
    for r in RESULTS:
        if not any(r.match(line) for line in lines):
            errors.append(f"no line like {r.pattern!r}")
    return errors


# --test: an output cut down to two of the 22 values is wrong, and a value
# changed in it is reported.
TAIL = """\
Execution starts, 4 runs through Dhrystone
Arr_2_Glob[8][7]:    14
        should be:   Number_Of_Runs + 10
Ptr_Glob->
  Ptr_Comp:          100
        should be:   (implementation-dependent)
"""


def test() -> None:
    short = check(TAIL)
    if short != ["2 values, expected 22"] + [f"no line like {r.pattern!r}" for r in RESULTS]:
        sys.exit(f"FAIL dhrycheck.py --test: {short}")
    bad = check(TAIL.replace("14", "15"))
    if "Arr_2_Glob[8][7] is '15', should be '14'" not in bad:
        sys.exit(f"FAIL dhrycheck.py --test: {bad}")
    print("PASS dhrycheck.py --test")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--test", action="store_true")
    args = ap.parse_args()
    if args.test:
        test()
        return
    if not args.file:
        ap.error("give a FILE or --test")
    with open(args.file) as f:
        errors = check(f.read())
    if errors:
        sys.exit("FAIL dhrystone: " + "; ".join(errors))
    print("PASS dhrystone")


if __name__ == "__main__":
    main()
