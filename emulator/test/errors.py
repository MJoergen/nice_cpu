#!/usr/bin/env python3
"""Tests of niceemu's command line and loader.

CASES are command lines, some with a .bin file, that must fail with exit
status 1 and print the expected message on stderr. RUNS are programs that
run and stop, each with its exit status and lines of its output."""

from __future__ import annotations

import os
import pty
import select
import subprocess
import sys
import tempfile
from typing import List, Optional, Tuple

NICEASM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assembler", "niceasm.py")
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

# Runs that succeed: (contents of the .bin file, arguments before it, exit
# status, lines that stdout must have, or must not have if they start with
# "!"). 0c000000 is HALT, 0c200000 RTI, 0c400001 INT 1, and 0c600000 a
# reserved control word.
RUNS: List[Tuple[str, List[str], int, List[str]]] = [
    ("00000000 0c000000", [], 0, ["Halted (HALT) after 1 steps, PC=00000001"]),
    # RTI outside an interrupt routine, a reserved word, and INT inside the
    # routine of INT 1, which starts at word 2.
    ("00000000 0c200000", [], 2, ["Halted (RTI outside an interrupt routine) after 1 steps, PC=00000001"]),
    ("00000000 0c600000", [], 2, ["Halted (reserved control instruction) after 1 steps, PC=00000001"]),
    ("00000000 0c400001\n00000001 00000002\n00000002 0c400001", [], 2,
     ["Halted (INT inside an interrupt routine) after 2 steps, PC=00000003"]),
    ("00000000 00000000", ["-n", "5", "--no-cycle-counter"], 3,
     ["Stopped at the step limit after 5 steps, PC=00000005"]),
    # -n 0 runs nothing. A HALT at the step limit still counts as a halt.
    ("00000000 0c000000", ["-n", "0"], 3, ["Stopped at the step limit after 0 steps, PC=00000000"]),
    ("00000000 0c000000", ["-n", "1"], 0, ["Halted (HALT) after 1 steps, PC=00000001"]),
    # An interrupt entry is a step: -n 1 stops right after the NMI's entry,
    # at the routine at 0x10, with I set.
    ("00000000 0c000000\n00000003 00000010", ["-n", "1", "--nmi", "0:3"], 3,
     ["Stopped at the step limit after 1 steps, PC=00000010",
      "R12 00000000 R13 00000000 R14 81000000 R15 00000010", "!Pending"]),
    # A request still pending at the step limit, with E = 0, and one for a
    # step after the halt, which is never raised.
    ("00000000 00000000", ["-n", "2", "--irq", "1:5"], 3,
     ["Stopped at the step limit after 2 steps, PC=00000002", "Pending: IRQ 05"]),
    ("00000000 0c000000", ["--nmi", "1:5", "--irq", "1:6"], 0, ["!Pending"]),
    # MOVE @TIMER_PERIOD, P; HALT. With P = 1 the timer raises a request at
    # the end of step 0, which is pending, with E = 0, at the end. With
    # P = 2 the only request comes at the end of the HALT's step, the last
    # one, and it is not listed (README.md, Memory map).
    ("00000000 000c1800\n00000001 ffffff10\n00000002 00000001\n00000003 0c000000", [], 0,
     ["Halted (HALT) after 2 steps, PC=00000004", "Pending: IRQ 00"]),
    ("00000000 000c1800\n00000001 ffffff10\n00000002 00000002\n00000003 0c000000", [], 0,
     ["Halted (HALT) after 2 steps, PC=00000004", "!Pending"]),
    # A dump that wraps from 0xFFFFFFFF to 0 stays on one line, and a dump
    # of no words prints nothing.
    ("00000000 0c000000", ["-d", "0xfffffffe:3", "-d", "5:0"], 0,
     ["fffffffe: 00000000 00000000 0c000000", "!00000005:"]),
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

        # The exit status of each way to stop, and lines the output must
        # have, or must not have when they start with "!".
        for text, args, status, lines in RUNS:
            p = run(tmp, args + ["BIN"], text)
            out = p.stdout.splitlines()
            problems = []
            if p.returncode != status:
                problems.append(f"exit status {p.returncode}, expected {status}")
            for line in lines:
                if line.startswith("!"):
                    if any(o.startswith(line[1:]) for o in out):
                        problems.append(f"unexpected '{line[1:]}'")
                elif line not in out:
                    problems.append(f"expected '{line}'")
            if p.stderr:
                problems.append(f"unexpected stderr:\n{p.stderr}")
            if problems:
                failed += 1
                print(f"FAIL {args} {text!r}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))

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

        # Before a console read waits for input, the output so far is
        # flushed, so that a prompt shows. The program prints "?", reads a
        # byte, and echoes it. The byte is sent only once the "?" has come.
        with open(path, "w") as f:
            f.write("00000000 001c1800\n00000001 ffffff00\n00000002 0000003f\n"
                    "00000003 00007800\n00000004 ffffff00\n"
                    "00000005 001c0080\n00000006 ffffff00\n00000007 0c000000\n")
        prompt = subprocess.Popen([NICEEMU, path], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE)
        assert prompt.stdout is not None
        ready, _, _ = select.select([prompt.stdout], [], [], 5)
        first = os.read(prompt.stdout.fileno(), 1) if ready else b""
        rest, err_b = prompt.communicate(b"x", timeout=10)
        if first != b"?" or not rest.startswith(b"xHalted (HALT) after 4 steps") or err_b:
            failed += 1
            print(f"FAIL prompt: {first!r} first, then {rest[:40]!r}, stderr {err_b!r}")

        # On a terminal, the console output shows at once, so that it is not
        # lost when the user stops a program that loops. The program prints
        # "A" and loops. The "A" must come within 5 seconds, long before the
        # default step limit ends the run.
        loop_asm = os.path.join(tmp, "loop.nasm")
        loop_bin = os.path.join(tmp, "loop.bin")
        with open(loop_asm, "w") as f:
            f.write(" MOVE @0xFFFFFF00, 0x41\nloop MOVE R15, loop\n")
        subprocess.run([sys.executable, NICEASM, "-o", loop_bin, loop_asm], check=True)
        master, slave = pty.openpty()
        tty = subprocess.Popen([NICEEMU, "-n", "1000000000000", loop_bin], stdin=subprocess.DEVNULL,
                               stdout=slave, stderr=subprocess.PIPE)
        os.close(slave)
        with open(master, "rb", buffering=0) as screen:
            ready, _, _ = select.select([screen], [], [], 5)
            shown = screen.read(1) if ready else b""
            tty.kill()
            tty.communicate()
        if shown != b"A":
            failed += 1
            print(f"FAIL terminal output: {shown!r}, expected b'A' within 5 seconds")
    total = len(CASES) + len(RUNS) + 4
    print(f"PASS errors ({total} cases)" if not failed else f"FAIL errors ({failed} of {total})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
