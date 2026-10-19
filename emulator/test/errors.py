#!/usr/bin/env python3
"""Tests of niceemu's command line and loader.

CASES are command lines, some with a .bin file, that must fail with exit
status 1 and print the expected message on stderr."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from typing import List, Optional, Tuple

NICEEMU = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "zig-out", "bin", "niceemu")

# (arguments, contents of the .bin file or None, expected stderr line). In
# the arguments and the message, BIN stands for the .bin file's path.
CASES: List[Tuple[List[str], Optional[str], str]] = [
    # Command line
    ([], None, "niceemu: no program given"),
    (["BIN", "BIN"], "00000000 0c000000", "niceemu: more than one program given"),
    (["-x", "BIN"], "00000000 0c000000", "niceemu: unknown option '-x'"),
    (["--mem-size", "5", "BIN"], "00000000 0c000000", "niceemu: unknown option '--mem-size'"),
    (["BIN", "-n"], "00000000 0c000000", "niceemu: -n needs a value"),
    (["-n", "abc", "BIN"], "00000000 0c000000", "niceemu: -n: bad number 'abc'"),
    (["--max-steps", "-1", "BIN"], "00000000 0c000000", "niceemu: --max-steps: bad number '-1'"),
    (["-n", "0x10000000000000000", "BIN"], "00000000 0c000000",
     "niceemu: -n: '0x10000000000000000' is larger than 18446744073709551615"),
    (["-d", "10", "BIN"], "00000000 0c000000", "niceemu: -d wants ADDR:N, not '10'"),
    (["--dump", "10", "BIN"], "00000000 0c000000", "niceemu: --dump wants ADDR:N, not '10'"),
    (["-d", ":5", "BIN"], "00000000 0c000000", "niceemu: -d: bad number ''"),
    (["-d", "0:0x100000000", "BIN"], "00000000 0c000000", "niceemu: -d: '0x100000000' is larger than 4294967295"),
    (["BIN", "--irq"], "00000000 0c000000", "niceemu: --irq needs a value"),
    (["--irq", "5", "BIN"], "00000000 0c000000", "niceemu: --irq wants STEP:VEC, not '5'"),
    (["--nmi", "5", "BIN"], "00000000 0c000000", "niceemu: --nmi wants STEP:VEC, not '5'"),
    (["--irq", "x:1", "BIN"], "00000000 0c000000", "niceemu: --irq: bad number 'x'"),
    (["--nmi", "-1:1", "BIN"], "00000000 0c000000", "niceemu: --nmi: bad number '-1'"),
    (["--irq", "0:256", "BIN"], "00000000 0c000000", "niceemu: --irq: '256' is larger than 255"),
    (["--nmi", "0:", "BIN"], "00000000 0c000000", "niceemu: --nmi: bad number ''"),
    (["--irq", "0:+5", "BIN"], "00000000 0c000000", "niceemu: --irq: bad number '+5'"),
    (["--irq", "0:1_0", "BIN"], "00000000 0c000000", "niceemu: --irq: bad number '1_0'"),
    (["-n", "0b11", "BIN"], "00000000 0c000000", "niceemu: -n: bad number '0b11'"),
    (["-d", "0x:1", "BIN"], "00000000 0c000000", "niceemu: -d: bad number '0x'"),
    (["-d", "0xg:1", "BIN"], "00000000 0c000000", "niceemu: -d: bad number '0xg'"),
    (["does-not-exist.bin"], None, "niceemu: cannot read does-not-exist.bin: FileNotFound"),
    (["BIN", "--input"], "00000000 0c000000", "niceemu: --input needs a value"),
    (["-i", "does-not-exist.txt", "BIN"], "00000000 0c000000",
     "niceemu: cannot read does-not-exist.txt: FileNotFound"),
    (["-i", ".", "BIN"], "00000000 0c000000", "niceemu: cannot read .: IsDir"),
    # Loader
    (["BIN"], "", "BIN: error: no words to load"),
    (["BIN"], "\n  \n", "BIN: error: no words to load"),
    (["BIN"], "hello world", "BIN:1: error: 'hello' is not a hex number"),
    (["BIN"], "00000000", "BIN:1: error: expected 'address word', found only '00000000'"),
    (["BIN"], "00000000 0c000000 extra", "BIN:1: error: unexpected 'extra' after the word"),
    (["BIN"], "100000000 0c000000", "BIN:1: error: '100000000' has more than 8 hex digits"),
    (["BIN"], "00000000 0c00_0000", "BIN:1: error: '0c00_0000' is not a hex number"),
    (["BIN"], "+1 +5", "BIN:1: error: '+1' is not a hex number"),
    (["BIN"], "0x0 0c000000", "BIN:1: error: '0x0' is not a hex number"),
    (["BIN"], "00000000 0c000000\n\n00000000 0c000000",
     "BIN:3: error: address 00000000 is already loaded by line 1"),
]


def run(tmp: str, args: List[str], text: Optional[str]) -> subprocess.CompletedProcess[str]:
    path = os.path.join(tmp, "t.bin")
    if text is not None:
        with open(path, "w") as f:
            f.write(text + "\n" if text else "")
    args = [path if a == "BIN" else a for a in args]
    return subprocess.run([NICEEMU] + args, capture_output=True, text=True, cwd=tmp)


def main() -> None:
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "t.bin")
        for args, text, expected in CASES:
            expected = expected.replace("BIN", path)
            p = run(tmp, args, text)
            problems = []
            if p.returncode != 1:
                problems.append(f"exit status {p.returncode}, expected 1")
            if expected not in p.stderr.splitlines():
                problems.append(f"expected '{expected}', got:\n{p.stderr}")
            if p.stdout:
                problems.append(f"unexpected output:\n{p.stdout}")
            if problems:
                failed += 1
                print(f"FAIL {args} {text!r}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))

        # Help goes to stdout, with exit status 0.
        p = run(tmp, ["-h"], None)
        if p.returncode != 0 or not p.stdout.startswith("Usage: niceemu") or p.stderr:
            failed += 1
            print("FAIL -h")

        # The exit status of each way to stop: HALT, any other halt, the step
        # limit. 0c200000 is RTI outside an interrupt routine.
        for text, args, status in [("00000000 0c000000", [], 0), ("00000000 0c200000", [], 2),
                                   ("00000000 00000000", ["-n", "5", "--no-cycle-counter"], 3)]:
            p = run(tmp, args + ["BIN"], text)
            if p.returncode != status:
                failed += 1
                print(f"FAIL {text!r}: exit status {p.returncode}, expected {status}")

        # A pipe closed early ends the trace quietly, with status 141.
        with open(path, "w") as f:
            f.write("00000000 00000000\n")
        proc = subprocess.Popen([NICEEMU, "-t", path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert proc.stdout is not None and proc.stderr is not None
        proc.stdout.readline()
        proc.stdout.close()
        err = proc.stderr.read()
        if proc.wait() != 141 or err:
            failed += 1
            print(f"FAIL closed pipe: exit status {proc.returncode}, stderr {err!r}")
    total = len(CASES) + 5
    print(f"PASS errors ({total} cases)" if not failed else f"FAIL errors ({failed} of {total})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
