#!/usr/bin/env python3
"""Tests of niceemu --window, doc/DEVICES.md §1, on a build with -Dwindow.

SDL's dummy video driver runs the window without a display, so no key can
be typed and the window cannot be closed. Each test reads the report,
which comes at the halt, and then ends niceemu with SIGTERM. The close of
the window is tested through NICEEMU_CLOSE_AFTER=N in the environment, a
hook of niceemu for this file: the window counts as closed once a run has
made N steps. test_link and test_close_link run --window with --link, with
the host of link.py. The sound plays on SDL's dummy audio driver, and on
its disk driver, which writes the samples to a file, in test_sound and
test_player."""

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
import struct
from typing import List, Optional, Tuple

import link
import opm_model

HERE = os.path.dirname(os.path.abspath(__file__))
NICEASM = os.path.join(HERE, "..", "..", "assembler", "niceasm.py")
# NICEEMU in the environment names another build, such as one of make dist.
NICEEMU = os.environ.get("NICEEMU") or os.path.join(HERE, "..", "zig-out", "bin", "niceemu")
# Also for the niceemu that link.Emu starts.
os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["SDL_AUDIODRIVER"] = "dummy"
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

# A skip of 10^9 wait steps with --step-time (DEVICES.md §3). The MOVE
# is three words, so PC is 3 in the skip.
SKIP_LONG = """
                MOVE    @0xFFFFFF5F, 1000000000
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


# The note of DEVICES.md §12.5, then a halt, after which the sound plays
# on.
NOTE_WRITES = [0x20C7, 0x284A, 0x607F, 0x687F, 0x707F, 0x5801, 0x981F, 0xF80F, 0x0878]
NOTE = "OPM_WRITE       .EQU    0xFFFFFF08\n" + "".join(
    f"                MOVE    @OPM_WRITE, 0x{w:04X}\n" for w in NOTE_WRITES) + "                HALT\n"


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


def test_2004() -> None:
    """With -2004, the window opens with the 25 rows of the screen at
    0x400, and the report at the halt has them. The dummy driver shows no
    window, so a unit test of src/window.zig checks its size and what it
    draws."""
    with open(os.path.join(HERE, "scrbound2004.expected")) as f:
        want = f.read().split("\n")[:31]
    p = start(["-2004", "-s", os.path.join(HERE, "scrbound.bin")])
    expect("scrbound with -2004", read_lines(p, 31), want)
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


def test_skip(tmp: str) -> None:
    """With --speed, a long skip of TIME_SKIP goes no further than a chunk
    at once, 1000 steps at 1000000 a second, so the pace sleeps a
    millisecond for each and the window is pumped. The steps are the MOVE
    and wait steps to the close after 5000."""
    prog = assemble(tmp, "skip_long", SKIP_LONG)
    t = time.monotonic()
    p = start(["--step-time", "--speed", "1000000", prog], close_after=5000)
    expect("closed in a long skip", read_lines(p, 1)[0],
           "Stopped when the window was closed after 5000 steps, PC=00000003")
    expect("exit status when closed in a long skip", p.wait(timeout=10), 4)
    if time.monotonic() - t > 5.0:
        fail(f"long skip: {time.monotonic() - t:.3f} s for 5000 steps at 1 MHz")


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


def play(tmp: str, args: List[str], seconds: float) -> Tuple[List[Tuple[int, int]], bytes]:
    """Run the note with the arguments on SDL's disk audio driver for the
    seconds given, and return the samples that it wrote, and stderr."""
    note = assemble(tmp, "note", NOTE)
    raw = os.path.join(tmp, "sound.raw")
    if os.path.exists(raw):
        os.remove(raw)
    env = dict(ENV, SDL_AUDIODRIVER="disk", SDL_AUDIO_DISK_OUTPUT_FILE=raw)
    p = subprocess.Popen([NICEEMU, "--window"] + args + [note], stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    expect("the report of the note", read_lines(p, 1)[0], "Halted (HALT) after 10 steps, PC=0000001c")
    time.sleep(seconds)
    stop(p)
    assert p.stderr is not None
    err = p.stderr.read()
    if not os.path.exists(raw):
        return [], err
    with open(raw, "rb") as f:
        data = f.read()
    return [struct.unpack_from("<hh", data, i) for i in range(0, len(data) - 3, 4)], err


def test_sound(tmp: str) -> None:
    """The window plays the sound's samples (DEVICES.md §12.3) on the
    default device, here SDL's disk driver, which takes them at the
    sound's rate as they are, and writes them to a file. The writes land
    in consecutive samples, after silence. So the file is silence, then
    the model's samples from the first that is not silence. Where the
    stream ran empty, the window put 50 ms of silence ahead of the next
    samples, and where it held too many, it dropped them: each stretch
    after a silence of more than 100 samples must be the model's samples
    from a later point. The first must last 0.2 s. With --no-sound, no
    sound plays, and with no audio device, the run goes on after a
    warning."""
    got, _ = play(tmp, [], 1.0)
    want = opm_model.run([(i, w >> 8, w & 0xFF) for i, w in enumerate(NOTE_WRITES)], 3 * 55930)
    onset = next(i for i, s in enumerate(want) if s != (0, 0))
    # The stretches of the file between the silences.
    stretches: List[Tuple[int, int]] = []
    start_at: Optional[int] = None
    zeros = 0
    for i, smp in enumerate(got + [(0, 0)] * 101):
        if smp != (0, 0):
            if start_at is None:
                start_at = i
            zeros = 0
            continue
        zeros += 1
        if zeros == 101 and start_at is not None:
            stretches.append((start_at, i - 100))
            start_at = None
    if not stretches or stretches[0][1] - stretches[0][0] < 55930 // 5:
        fail(f"sound: stretches {stretches} of {len(got)} samples")
    a, b = stretches[0]
    if got[a:b] != want[onset:onset + b - a]:
        fail("sound: the first stretch is not the model's samples")
    at = onset + b - a
    for a, b in stretches[1:]:
        while at + b - a <= len(want) and got[a:b] != want[at:at + b - a]:
            at += 1
        if at + b - a > len(want):
            fail(f"sound: the stretch at {a} is not a later part of the model's samples")
        at += b - a
    got, _ = play(tmp, ["--no-sound"], 0.2)
    expect("samples with --no-sound", got, [])
    note = assemble(tmp, "note", NOTE)
    p = subprocess.Popen([NICEEMU, "--window", note], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, env=dict(ENV, SDL_AUDIODRIVER="nonexistent"))
    expect("the report without an audio device", read_lines(p, 1)[0], "Halted (HALT) after 10 steps, PC=0000001c")
    stop(p)
    assert p.stderr is not None
    err = p.stderr.read()
    if not err.startswith(b"niceemu: no sound: SDL_InitSubSystem: "):
        fail(f"stderr without an audio device: {err!r}")


# The sample player's tune: PLAYER_COUNT samples of PLAYER_SAMPLE at
# PLAYER_RATE, written before the rate is set, then a halt, after which
# the player plays on.
PLAYER_COUNT = 4096
PLAYER_RATE = 8000
PLAYER_SAMPLE = (3000, -3000)
PLAYER = (
    "PCM_DATA        .EQU    0xFFFFFF0A\n"
    "PCM_RATE        .EQU    0xFFFFFF0B\n"
    f"                MOVE    R1, {PLAYER_COUNT}\n"
    f":               MOVE    @PCM_DATA, 0x{PLAYER_SAMPLE[0] & 0xFFFF:04X}{PLAYER_SAMPLE[1] & 0xFFFF:04X}\n"
    "                DEC[M]  R1, R1\n"
    "        ?!Z     JMP     :-\n"
    f"                MOVE    @PCM_RATE, {PLAYER_RATE}\n"
    "                HALT\n"
)


def test_player(tmp: str) -> None:
    """The window plays the sample player's samples (DEVICES.md §12.7) on
    the same device, here SDL's disk driver at the synthesizer's rate, to
    which SDL converts them from the player's. The samples are a constant,
    so the conversion keeps it: the file must hold it, within a few, for
    nearly the 0.512 s of the 4096 samples at 8000 Hz, and not much
    longer."""
    tune = assemble(tmp, "player", PLAYER)
    raw = os.path.join(tmp, "player.raw")
    if os.path.exists(raw):
        os.remove(raw)
    env = dict(ENV, SDL_AUDIODRIVER="disk", SDL_AUDIO_DISK_OUTPUT_FILE=raw)
    p = subprocess.Popen([NICEEMU, "--window", tune], stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    expect("the report of the player", read_lines(p, 1)[0], "Halted (HALT) after 12291 steps, PC=0000000b")
    time.sleep(1.2)
    stop(p)
    data = open(raw, "rb").read() if os.path.exists(raw) else b""
    got = [struct.unpack_from("<hh", data, i) for i in range(0, len(data) - 3, 4)]
    near = sum(1 for left, right in got
               if abs(left - PLAYER_SAMPLE[0]) <= 4 and abs(right - PLAYER_SAMPLE[1]) <= 4)
    length = PLAYER_COUNT * 55930 // PLAYER_RATE
    if not length * 0.95 <= near <= length * 1.01:
        fail(f"player: {near} samples near {PLAYER_SAMPLE} of {len(got)}, not about {length}")


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


def test_link_skip(tmp: str) -> None:
    """With --link and --speed, a long skip goes a chunk at a time, 1000
    steps at 1000000 a second, and the link is served between chunks: a
    request in the skip is answered within the 100 ms of DEBUG.md §5, not
    after the pace of all the wait steps jumped over at once."""
    words = link.assemble(tmp, "skip_long", SKIP_LONG)
    e = link.Emu(["--window", "--step-time", "--speed", "1000000"])
    e.expect("hello", link.HELLO)
    e.send(link.write(0, words) + link.write(link.CONTROL, [0x8]))
    e.expect("start the long skip", link.ok(0, len(words)) + link.ok(link.CONTROL, 1))
    for i in range(3):
        time.sleep(0.05)
        t = time.monotonic()
        expect(f"control in the long skip, read {i}", link.word(e, link.CONTROL), 0x8)
        took = time.monotonic() - t
        if took > 0.1:
            fail(f"read {i} in the long skip was answered after {took:.3f} s")
    status, _, _ = e.stop()
    expect("exit status after the long skip", status, 0)
    if link.failures:
        fail("; ".join(link.failures))


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        test_screen()
        test_2004()
        test_poll(tmp)
        test_speed(tmp)
        test_signal(tmp)
        test_close(tmp)
        test_idle(tmp)
        test_skip(tmp)
        test_no_display(tmp)
        test_link(tmp)
        test_link_skip(tmp)
        test_close_link(tmp)
        test_sound(tmp)
        test_player(tmp)
    print("PASS window (14 tests)")


if __name__ == "__main__":
    main()
