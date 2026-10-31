#!/usr/bin/env python3
"""Tests of niceemu --window, doc/SYSTEM.md §1, on a build with -Dwindow.

SDL's dummy video driver runs the window without a display, so no key can
be typed and the window cannot be closed. Each test reads the report,
which comes at the halt, and then ends niceemu with SIGTERM. The close of
the window is tested through NICEEMU_CLOSE_AFTER=N in the environment, a
hook of niceemu for this file: the window counts as closed once a run has
made N steps. test_link and test_close_link run --window with --link, with
the host of link.py."""

from __future__ import annotations

import os
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time
from typing import List, Optional

import link

HERE = os.path.dirname(os.path.abspath(__file__))
NICEASM = os.path.join(HERE, "..", "..", "assembler", "niceasm.py")
NICEEMU = os.path.join(HERE, "..", "zig-out", "bin", "niceemu")
# Also for the niceemu that link.Emu starts.
os.environ["SDL_VIDEODRIVER"] = "dummy"
ENV = dict(os.environ)

# Reads the console three times, into R1, R2, and R3.
POLL = """
CONSOLE         .EQU    0xFFFFFF00
                MOVE    R1, @CONSOLE
                MOVE    R2, @CONSOLE
                MOVE    R3, @CONSOLE
                HALT
"""

# Reads the console until a byte or the end comes, and counts the reads in
# R2.
WAIT = """
CONSOLE         .EQU    0xFFFFFF00
loop            MOVE    R1, @CONSOLE
                ADD     R2, R2, 1
                AND[M]  R0, R1, 0x300
        ?Z      MOVE    R15, loop
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


def start(args: List[str], stdin: Optional[int] = subprocess.DEVNULL,
          close_after: Optional[int] = None) -> subprocess.Popen[bytes]:
    """niceemu --window with the arguments, and with the window counting as
    closed after `close_after` steps if that is given."""
    env = dict(ENV, NICEEMU_CLOSE_AFTER=str(close_after)) if close_after is not None else ENV
    return subprocess.Popen([NICEEMU, "--window"] + args, stdin=stdin, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env)


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


def stop(p: subprocess.Popen[bytes], sig: signal.Signals = signal.SIGTERM) -> None:
    """End niceemu with the signal, which it dies of, as without the window."""
    p.send_signal(sig)
    if p.wait(timeout=10) != -sig:
        fail(f"exit status {p.returncode} after {sig.name}")


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
    """SIGINT, SIGTERM, and SIGHUP each end a run that has not halted, with
    no report."""
    count = assemble(tmp, "count", COUNT)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        p = start([count])
        time.sleep(0.3)
        stop(p, sig)
        assert p.stdout is not None
        expect(f"output after {sig.name}", p.stdout.read(), b"")


def test_close(tmp: str) -> None:
    """Closing the window before the halt ends the run: the report says so,
    and the exit status is 4. Closing it after the halt ends niceemu with
    the halt's status. The chunk between two looks at the window is 1000
    steps at the default speed, so the first run is closed at step 1000."""
    count = assemble(tmp, "count", COUNT)
    p = start([count], close_after=1000)
    expect("closed while running", read_lines(p, 1)[0],
           "Stopped when the window was closed after 1000 steps, PC=00000000")
    expect("exit status when closed", p.wait(timeout=10), 4)
    poll = assemble(tmp, "poll", POLL)
    p = start([poll], close_after=4)
    expect("closed after the halt", read_lines(p, 1)[0], "Halted (HALT) after 4 steps, PC=00000007")
    expect("exit status after the halt", p.wait(timeout=10), 0)


def test_no_display(tmp: str) -> None:
    """When no window can be opened, niceemu prints SDL's error and exits
    with status 1 before the run."""
    poll = assemble(tmp, "poll", POLL)
    p = subprocess.run([NICEEMU, "--window", poll], stdin=subprocess.DEVNULL, capture_output=True,
                       env=dict(ENV, SDL_VIDEODRIVER="nonexistent"), timeout=10)
    expect("exit status without a display", p.returncode, 1)
    expect("output without a display", p.stdout, b"")
    if not p.stderr.startswith(b"niceemu: SDL_Init: "):
        fail(f"stderr without a display: {p.stderr!r}")


def test_close_link(tmp: str) -> None:
    """With --link, closing the window ends niceemu with status 0, as a
    signal does, also while a program runs."""
    count = link.assemble(tmp, "count", COUNT)
    os.environ["NICEEMU_CLOSE_AFTER"] = "50000"
    try:
        e = link.Emu(["--window"])
    finally:
        del os.environ["NICEEMU_CLOSE_AFTER"]
    e.expect("hello", link.HELLO)
    e.send(link.write(0, count))
    e.expect("load", link.ok(0, len(count)))
    e.send(link.write(link.CONTROL, [0x8]))
    e.expect("start", link.ok(link.CONTROL, 1))
    out, err = e.proc.communicate(timeout=10)
    expect("exit status when closed with --link", e.proc.returncode, 0)
    expect("stdout when closed with --link", out, b"")
    expect("stderr when closed with --link", err, b"")
    if link.failures:
        fail("; ".join(link.failures))


def test_link(tmp: str) -> None:
    """With --link, a console read returns 0 while no byte waits, and the
    run is paced. The end of the input still reads 0x200."""
    words = link.assemble(tmp, "wait", WAIT)
    halt = b"\xffh01#C9"
    e = link.Emu(["--window"])
    e.expect("hello", link.HELLO)
    e.send(link.write(0, words))
    e.expect("load", link.ok(0, len(words)))
    e.send(link.write(link.CONTROL, [0x8]))
    e.expect("start", link.ok(link.CONTROL, 1))
    time.sleep(0.2)
    e.send(b"A")
    e.expect("halt at a byte", halt)
    expect("R1 at a byte", link.word(e, 0xFFFFFFE1), 0x141)
    # About 50000 reads in 0.2 s at one step per microsecond, 4 steps each.
    reads = link.word(e, 0xFFFFFFE2)
    if not 1000 < reads < 200000:
        fail(f"{reads} reads in 0.2 s")
    # Hold, start again, and end the input with a half-close.
    e.send(link.write(link.CONTROL, [0x9]))
    e.expect("hold", link.ok(link.CONTROL, 1))
    e.send(link.write(link.CONTROL, [0x8]))
    e.expect("start again", link.ok(link.CONTROL, 1))
    e.sock.shutdown(socket.SHUT_WR)
    e.expect("halt at the end", halt)
    e.sock.close()
    e.sock = e.connect()
    e.buf = b""
    e.expect("hello again", link.HELLO)
    expect("R1 at the end", link.word(e, 0xFFFFFFE1), 0x200)
    status, out, err = e.stop()
    expect("exit status", status, 0)
    expect("stdout", out, b"")
    if err.count(b"Halted (HALT)") != 2:
        fail(f"stderr {err!r}")
    if link.failures:
        fail("; ".join(link.failures))


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        test_screen()
        test_poll(tmp)
        test_speed(tmp)
        test_signal(tmp)
        test_close(tmp)
        test_no_display(tmp)
        test_link(tmp)
        test_close_link(tmp)
    print("PASS window (8 tests)")


if __name__ == "__main__":
    main()
