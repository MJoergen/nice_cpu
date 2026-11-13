#!/usr/bin/env python3
"""Tests of niceemu --window, doc/DEVICES.md §1, on a build with -Dwindow.

SDL's dummy video driver runs the window without a display, so no key can
be typed and the window cannot be closed. Each test reads the report,
which comes at the halt, and then ends niceemu with SIGTERM. The close of
the window is tested through NICEEMU_CLOSE_AFTER=N in the environment, a
hook of niceemu for this file: the window counts as closed once a run has
made N steps. test_link and test_close_link run --window with --link, with
the host of link.py."""

from __future__ import annotations

import os
import resource
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
# NICEEMU in the environment names another build, such as one of make dist.
NICEEMU = os.environ.get("NICEEMU") or os.path.join(HERE, "..", "zig-out", "bin", "niceemu")
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

# Waits for a byte or the end with WAIT and the console's receive
# interrupt (DEVICES.md §1.9), whose routine is only RTI, and counts the
# waits in R2.
WAIT_IRQ = """
CONSOLE         .EQU    0xFFFFFF00
CONSOLE_IRQ     .EQU    0xFFFFFF02
                MOVE    @CONSOLE_IRQ, 0x142
:               AND     R14, R14, 0xBFFFFFFF
                MOVE    R1, @CONSOLE
                AND[M]  R0, R1, 0x300
        ?!Z     MOVE    R15, :+
                ADD     R2, R2, 1
                WAIT
                OR      R14, R14, 0x40000000
                MOVE    R15, :-
:               HALT
                .ORG    0x42
                .DAT    on_irq
on_irq          RTI
"""

# A WAIT that no request can end (DEVICES.md §1.6).
WAITS = """
                WAIT
                HALT
"""

# A WAIT for the timer's first request, 10^9 steps from its write.
WAITS_LONG = """
                MOVE    @0xFFFFFF10, 1000000000
                WAIT
                HALT
"""

# Counts in R2, and never halts.
COUNT = """
loop            ADD     R2, R2, 1
                MOVE    R15, loop
"""

# Reads TIME_LO forever, and counts the reads in R2.
TIMED = """
TIME_LO         .EQU    0xFFFFFF44
loop            MOVE    R1, @TIME_LO
                ADD     R2, R2, 1
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
    """300000 steps take at least 0.3 s at --speed 1000000, one step per
    microsecond, and the default, as fast as the host can, is faster than
    that."""
    count = assemble(tmp, "count", COUNT)
    times = []
    for extra in (["--speed", "1000000"], []):
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
    the halt's status. The chunk between two looks at the window is 65536
    steps without a pace and 1000 steps at --speed 1000000, so the first
    run is closed at step 65536 and the second at step 1000."""
    count = assemble(tmp, "count", COUNT)
    p = start([count], close_after=1000)
    expect("closed while running", read_lines(p, 1)[0],
           "Stopped when the window was closed after 65536 steps, PC=00000000")
    expect("exit status when closed", p.wait(timeout=10), 4)
    p = start(["--speed", "1000000", count], close_after=1000)
    expect("closed while running at a pace", read_lines(p, 1)[0],
           "Stopped when the window was closed after 1000 steps, PC=00000000")
    expect("exit status when closed at a pace", p.wait(timeout=10), 4)
    poll = assemble(tmp, "poll", POLL)
    p = start([poll], close_after=4)
    expect("closed after the halt", read_lines(p, 1)[0], "Halted (HALT) after 4 steps, PC=00000007")
    expect("exit status after the halt", p.wait(timeout=10), 0)


def test_idle(tmp: str) -> None:
    """A program that polls the console or TIME_LO in a loop sleeps: two
    idle reads within 1000 steps of each other end the chunk, and the
    window waits for an event, up to 10 ms in a loop that waits for a key
    alone and up to 1 ms in one that reads TIME_LO. The close hook looks
    at every chunk end. The 4-step console loop reads at steps 0, 4, 8,
    and so on, so its chunks end after 5, 9, 13, ... steps, and a close
    after 400 steps comes after 401, with 100 waits of 10 ms behind it;
    the 3-step TIME_LO loop ends its chunks after 4, 7, 10, ... steps, and
    a close after 3000 steps comes after 3001, with 1000 waits of 1 ms.
    Each run takes at least 0.5 s of wall time, where the host could run
    the steps in microseconds, and at most 5 s, which tells the two waits
    apart, and little of a host core: that bound is loose, as the redraws
    of the window cost too."""
    for name, text, close, want in (
            ("wait", WAIT, 400, "Stopped when the window was closed after 401 steps, PC=00000002"),
            ("timed", TIMED, 3000, "Stopped when the window was closed after 3001 steps, PC=00000002")):
        prog = assemble(tmp, name, text)
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        t = time.monotonic()
        p = start([prog], close_after=close)
        expect(f"closed in the {name} loop", read_lines(p, 1)[0], want)
        expect(f"exit status when closed in the {name} loop", p.wait(timeout=10), 4)
        elapsed = time.monotonic() - t
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        used = (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime)
        if not 0.5 <= elapsed <= 5.0 or used > elapsed * 0.75:
            fail(f"{name} loop: {elapsed:.3f} s for a second of waits, {used:.3f} s of it host CPU")


def test_wait(tmp: str) -> None:
    """A WAIT that no request can end does not stop a run in the window,
    which sleeps until it is closed, after the one step of the WAIT, and
    uses little of a host core meanwhile."""
    prog = assemble(tmp, "waits", WAITS)
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    t = time.monotonic()
    p = start([prog], close_after=1)
    expect("closed in the wait", read_lines(p, 1)[0], "Stopped when the window was closed after 1 steps, PC=00000001")
    expect("exit status when closed in the wait", p.wait(timeout=10), 4)
    elapsed = time.monotonic() - t
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    used = (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime)
    if used > max(elapsed, 0.2) * 0.75:
        fail(f"wait: {elapsed:.3f} s, {used:.3f} s of it host CPU")
    # With --speed, a long wait goes no further than a chunk at once, 1000
    # steps at 1000000 a second, so the pace sleeps a millisecond for each
    # and the window is pumped. The steps are the MOVE, the WAIT at word 3,
    # and wait steps to the close after 5000.
    prog = assemble(tmp, "waits_long", WAITS_LONG)
    t = time.monotonic()
    p = start(["--speed", "1000000", prog], close_after=5000)
    expect("closed in a long wait", read_lines(p, 1)[0],
           "Stopped when the window was closed after 5000 steps, PC=00000004")
    expect("exit status when closed in a long wait", p.wait(timeout=10), 4)
    if time.monotonic() - t > 5.0:
        fail(f"long wait: {time.monotonic() - t:.3f} s for 5000 steps at 1 MHz")


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
    run sleeps in the wait loop. The end of the input still reads 0x200."""
    words = link.assemble(tmp, "wait", WAIT)
    halt = b"\xffh01#C9"
    e = link.Emu(["--window"])
    e.expect("hello", link.HELLO)
    e.send(link.write(0, words))
    e.expect("load", link.ok(0, len(words)))
    e.send(link.write(link.CONTROL, [0x8]))
    e.expect("start", link.ok(link.CONTROL, 1))
    time.sleep(0.5)
    e.send(b"A")
    e.expect("halt at a byte", halt)
    expect("R1 at a byte", link.word(e, 0xFFFFFFE1), 0x141)
    # About 50 reads in 0.5 s, one per wait of 10 ms, where the host could
    # make millions.
    reads = link.word(e, 0xFFFFFFE2)
    if not 5 < reads < 5000:
        fail(f"{reads} reads in 0.5 s")
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


def test_link_irq(tmp: str) -> None:
    """With --link, a WAIT with the console's enable set sleeps until a
    byte comes from the host, whose request ends it (DEVICES.md §1.6,
    §1.9): the program waits once, and reads the byte after it. The end of
    the input ends a wait too."""
    words = link.assemble(tmp, "wait_irq", WAIT_IRQ)
    halt = b"\xffh01#C9"
    e = link.Emu(["--window"])
    e.expect("hello", link.HELLO)
    e.send(link.write(0, words))
    e.expect("load", link.ok(0, len(words)))
    e.send(link.write(link.CONTROL, [0x8]))
    e.expect("start", link.ok(link.CONTROL, 1))
    time.sleep(0.5)
    # Bit 6: the processor waits (DEBUG.md §6).
    expect("control in the wait", link.word(e, link.CONTROL), 0x48)
    e.send(b"A")
    e.expect("halt at a byte", halt)
    expect("R1 at a byte", link.word(e, 0xFFFFFFE1), 0x141)
    expect("waits for a byte", link.word(e, 0xFFFFFFE2), 1)
    # Hold, start again, and end the input with a half-close.
    e.send(link.write(link.CONTROL, [0x9]))
    e.expect("hold", link.ok(link.CONTROL, 1))
    e.send(link.write(link.CONTROL, [0x8]))
    e.expect("start again", link.ok(link.CONTROL, 1))
    time.sleep(0.2)
    e.sock.shutdown(socket.SHUT_WR)
    e.expect("halt at the end", halt)
    e.sock.close()
    e.sock = e.connect()
    e.buf = b""
    e.expect("hello again", link.HELLO)
    expect("R1 at the end", link.word(e, 0xFFFFFFE1), 0x200)
    expect("waits for the end", link.word(e, 0xFFFFFFE2), 1)
    status, _, _ = e.stop()
    expect("exit status", status, 0)
    if link.failures:
        fail("; ".join(link.failures))


def test_link_wait(tmp: str) -> None:
    """With --link and --speed, a long wait goes a chunk at a time, 1000
    steps at 1000000 a second, and the link is served between chunks: a
    request in the wait is answered within the 100 ms of DEBUG.md §5, not
    after the pace of all the wait steps jumped over at once."""
    words = link.assemble(tmp, "waits_long", WAITS_LONG)
    e = link.Emu(["--window", "--speed", "1000000"])
    e.expect("hello", link.HELLO)
    e.send(link.write(0, words) + link.write(link.CONTROL, [0x8]))
    e.expect("start the long wait", link.ok(0, len(words)) + link.ok(link.CONTROL, 1))
    for i in range(3):
        time.sleep(0.05)
        t = time.monotonic()
        expect(f"control in the long wait, read {i}", link.word(e, link.CONTROL), 0x48)
        took = time.monotonic() - t
        if took > 0.1:
            fail(f"read {i} in the long wait was answered after {took:.3f} s")
    status, _, _ = e.stop()
    expect("exit status after the long wait", status, 0)
    if link.failures:
        fail("; ".join(link.failures))


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        test_screen()
        test_poll(tmp)
        test_speed(tmp)
        test_signal(tmp)
        test_close(tmp)
        test_idle(tmp)
        test_wait(tmp)
        test_no_display(tmp)
        test_link(tmp)
        test_link_irq(tmp)
        test_link_wait(tmp)
        test_close_link(tmp)
    print("PASS window (11 tests)")


if __name__ == "__main__":
    main()
