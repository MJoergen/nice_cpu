#!/usr/bin/env python3
"""Tests of niceemu --window, doc/SYSTEM.md §1, on a build with -Dwindow.

SDL's dummy video driver runs the window without a display, so no key can
be typed and the window cannot be closed. Each test reads the report,
which comes at the halt, and then ends niceemu with SIGTERM."""

from __future__ import annotations

import os
import select
import signal
import subprocess
import sys
import tempfile
import time
from typing import List, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
NICEASM = os.path.join(HERE, "..", "..", "assembler", "niceasm.py")
NICEEMU = os.path.join(HERE, "..", "zig-out", "bin", "niceemu")
ENV = dict(os.environ, SDL_VIDEODRIVER="dummy")

# Reads the console three times, into R1, R2, and R3.
POLL = """
CONSOLE         .EQU    0xFFFFFF00
                MOVE    R1, @CONSOLE
                MOVE    R2, @CONSOLE
                MOVE    R3, @CONSOLE
                HALT
"""

# Counts in R2, and never halts.
COUNT = """
loop            ADD     R2, R2, 1
                MOVE    R15, loop
"""


def assemble(tmp: str, name: str, text: str) -> str:
    src = os.path.join(tmp, name + ".nasm")
    with open(src, "w") as f:
        f.write(text)
    subprocess.run([sys.executable, NICEASM, src], check=True)
    return os.path.join(tmp, name + ".bin")


def start(args: List[str], stdin: Optional[int] = subprocess.DEVNULL) -> subprocess.Popen[bytes]:
    return subprocess.Popen([NICEEMU, "--window"] + args, stdin=stdin, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=ENV)


def read_lines(p: subprocess.Popen[bytes], n: int, timeout: float = 10.0) -> List[str]:
    """The first n lines of stdout, or fail after `timeout` seconds."""
    assert p.stdout is not None
    data = b""
    end = time.monotonic() + timeout
    while data.count(b"\n") < n:
        left = end - time.monotonic()
        if left <= 0 or not select.select([p.stdout], [], [], left)[0]:
            fail(f"timeout, got {data!r}")
        chunk = os.read(p.stdout.fileno(), 4096)
        if not chunk:
            assert p.stderr is not None
            fail(f"end of output, got {data!r}, stderr {p.stderr.read()!r}")
        data += chunk
    return data.decode().split("\n")[:n]


def stop(p: subprocess.Popen[bytes]) -> None:
    """End niceemu with SIGTERM, which it dies of, as without the window."""
    p.send_signal(signal.SIGTERM)
    if p.wait(timeout=10) != -signal.SIGTERM:
        fail(f"exit status {p.returncode} after SIGTERM")


def fail(msg: str) -> None:
    sys.exit(f"FAIL window: {msg}")


def expect(what: str, got: object, want: object) -> None:
    if got != want:
        fail(f"{what}: got {got!r}, want {want!r}")


def test_screen() -> None:
    """The report comes at the halt, with --color, while the window stays."""
    with open(os.path.join(HERE, "screencolor.expected")) as f:
        want = f.read().split("\n")[:7]
    p = start(["--color", os.path.join(HERE, "screencolor.bin")])
    expect("screencolor", read_lines(p, 7), want)
    stop(p)


def test_poll(tmp: str) -> None:
    """--input, then the keys: none is typed, so the reads after the file
    return 0, not 0x200. Without --input, stdin is not read."""
    poll = assemble(tmp, "poll", POLL)
    data = os.path.join(tmp, "a.txt")
    with open(data, "w") as f:
        f.write("A")
    p = start(["-i", data, poll])
    lines = read_lines(p, 2)
    expect("first line", lines[0], "Halted (HALT) after 4 steps, PC=00000007")
    expect("registers", lines[1], "R0  00000000 R1  00000141 R2  00000000 R3  00000000")
    stop(p)
    p = start([poll], stdin=subprocess.PIPE)
    assert p.stdin is not None
    p.stdin.write(b"B")
    p.stdin.flush()
    expect("registers", read_lines(p, 2)[1], "R0  00000000 R1  00000000 R2  00000000 R3  00000000")
    stop(p)


def test_speed(tmp: str) -> None:
    """300000 steps take at least 0.3 s at the default speed, one step per
    microsecond, and --speed 0 is faster than that."""
    count = assemble(tmp, "count", COUNT)
    times = []
    for extra in ([], ["--speed", "0"]):
        t = time.monotonic()
        p = start(["-n", "300000"] + extra + [count])
        expect("first line", read_lines(p, 1)[0], "Stopped at the step limit after 300000 steps, PC=00000000")
        times.append(time.monotonic() - t)
        stop(p)
    if times[0] < 0.3 or times[1] >= times[0]:
        fail(f"times {times[0]:.3f} s and {times[1]:.3f} s")


def test_signal(tmp: str) -> None:
    """A signal ends a run that has not halted, with no report."""
    count = assemble(tmp, "count", COUNT)
    p = start([count])
    time.sleep(0.3)
    stop(p)
    assert p.stdout is not None
    expect("output", p.stdout.read(), b"")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        test_screen()
        test_poll(tmp)
        test_speed(tmp)
        test_signal(tmp)
    print("PASS window (4 tests)")


if __name__ == "__main__":
    main()
