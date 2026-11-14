#!/usr/bin/env python3
"""Tests of niceemu's debug link, doc/DEBUG.md, over TCP.

Each test starts niceemu --link 0, connects as the host, and checks the
bytes that come back. The packets of DEBUG.md §8 are written out in full,
with their checksums from the spec. The other packets are built by pkt(),
which sums the bytes as DEBUG.md §2 says; their payloads are written by
hand."""

from __future__ import annotations

import os
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from typing import Callable, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
NICEASM = os.path.join(HERE, "..", "..", "assembler", "niceasm.py")
# NICEEMU in the environment names another build, such as one of make dist.
NICEEMU = os.environ.get("NICEEMU") or os.path.join(HERE, "..", "zig-out", "bin", "niceemu")

ESC = b"\xff"

# Echoes each input byte, and halts at the end of the input, with the
# number of bytes echoed in R2.
ECHO = """
CONSOLE         .EQU    0xFFFFFF00
loop            MOVE    R1, @CONSOLE
                AND[M]  R0, R1, 0x200
        ?!Z     HALT
                MOVE    @CONSOLE, R1
                ADD     R2, R2, 1
                MOVE    R15, loop
"""

# Echoes each input byte, and reads on at the end of the input, as a
# monitor does, so it never halts. R2 counts the bytes, before each echo,
# so that a host that has the echo reads the count of it.
ECHO_ON = """
CONSOLE         .EQU    0xFFFFFF00
loop            MOVE    R1, @CONSOLE
                AND[M]  R0, R1, 0x100
        ?Z      MOVE    R15, loop       ; the end, 0x200: read again
                ADD     R2, R2, 1
                MOVE    @CONSOLE, R1
                MOVE    R15, loop
"""

# Counts in R2, and never reads the console or halts. R15 is 0 or 2 between
# two steps.
COUNT = """
loop            ADD     R2, R2, 1
                MOVE    R15, loop
"""

# The first instruction is one word long (DEBUG.md §8).
ONE = """
                MOVE    R2, R3
loop            MOVE    R15, loop
"""

# Reads the console twice in one instruction (DEBUG.md §7).
TWICE = """
CONSOLE         .EQU    0xFFFFFF00
                ADD     R3, @CONSOLE, @CONSOLE
                HALT
"""

# Halts at its first instruction.
STOP = """
                HALT
"""

# The halt reasons 2, 3, and 4 (ISA.md §5.3, §7.2, §7.4): a reserved control
# word, INT inside an interrupt routine, and RTI outside one.
RESERVED = """
                .DAT    0x0FE00000
"""
INT_IN_ISR = """
                MOVE    R14, 0x00000001
                INT     2
                HALT
isr             INT     3
                .ORG    0x102
                .DAT    isr
"""
RTI_OUTSIDE = """
                RTI
"""

# Never halts, and never reads the console.
SPIN = """
loop            MOVE    R15, loop
"""

# Jumps to a loop at 0x10, for the breakpoint of DEBUG.md §8.
AT10 = """
                MOVE    R15, loop
                .ORG    0x10
loop            MOVE    R15, loop
"""

# Reads data into R2 at 0, and counts the passes in R3.
LOAD = """
loop            MOVE    R2, @data
                ADD     R3, R3, 1
                MOVE    R15, loop
data            .DAT    7
"""

# Counts in R2, and skips the HALT at 2, as Z is 0.
SKIP = """
loop            ADD     R2, R2, 1
        ?Z      HALT
                MOVE    R15, loop
"""


# The data accesses of DEBUG.md §6 for the watchpoints: a write at 0, a read
# at 3, a skipped read at 5, two reads in one step at 7, and the vector read
# of the INT at 12, whose routine is at 14. data is at 15.
WATCH = """
                MOVE    @data, 5        ; a write
                MOVE    R2, @data       ; a read
        ?Z      MOVE    R3, @data       ; skipped: Z is 0
                ADD     R4, @data, @data  ; two reads
                MOVE    R14, 1          ; VBASE = 1: the table is at 0x100
                INT     2
back            HALT
isr             RTI
data            .DAT    7
                .ORG    0x102
                .DAT    isr
"""

# Writes the word at 0x200 at 0x10, for the watchpoint of DEBUG.md §8.
WRITE200 = """
                MOVE    R15, there
                .ORG    0x10
there           MOVE    @0x200, R1
                HALT
"""

# Copies R3 to R4 at 0x20, and halts, for the writes of R0-R15 (DEBUG.md §6).
WAITER = """
                WAIT
                MOVE    R1, 1
                HALT
"""
# Skips 1000 wait steps with --step-time (DEVICES.md §3). The MOVE is at
# 3, and the HALT at 5.
TIME_SKIPPER = """
                MOVE    @0xFFFFFF5F, 1000
                MOVE    R1, 1
                HALT
"""
# Counts in R2 with E = 0, so no IRQ is taken. Vector 2 leads to a routine
# at 7 that sets R3 and halts, for the NMI of the link (DEBUG.md §6). The
# loop's two instructions are at 3 and 5.
NMI_PROG = """
                MOVE    R15, loop
                .DAT    nmi
loop            ADD     R2, R2, 1
                MOVE    R15, loop
nmi             MOVE    R3, 0x77
                HALT
"""
# Waits with no request to come. Vector 2 leads to a routine at 3 that sets
# R3 and halts.
WAIT_NMI = """
                WAIT
                HALT
                .DAT    nmi
nmi             MOVE    R3, 0x77
                HALT
"""
# An INT, its RTI, and an NMI routine that halts, for the hidden state
# (DEBUG.md §6). back is at 3, isr at 5, and nmi at 7.
HIDDEN = """
                MOVE    R14, 0x00000001
                INT     2
back            NOP
                HALT
isr             NOP
                RTI
nmi             HALT
                .ORG    0x102
                .DAT    isr
                .DAT    nmi
"""
REGS = """
                MOVE    R2, R3
loop            MOVE    R15, loop
                .ORG    0x20
                MOVE    R4, R3
                HALT
"""

# Spins at 0, and copies R3 to R4 at 0x20 and spins there, for the example
# of DEBUG.md §8.
AT20 = """
loop            MOVE    R15, loop
                .ORG    0x20
                MOVE    R4, R3
there           MOVE    R15, there
"""


def pkt(tag: str, payload: str) -> bytes:
    """ESC, the tag, the payload, '#', and the checksum (DEBUG.md §2)."""
    body = (tag + payload).encode()
    return ESC + body + b"#" + f"{sum(body) % 256:02X}".encode()


def read(addr: int, n: int) -> bytes:
    return pkt("R", f"{addr:08X}{n:04X}")


def write(addr: int, words: List[int]) -> bytes:
    return pkt("W", f"{addr:08X}{len(words):04X}" + "".join(f"{w:08X}" for w in words))


def ok(addr: int, n: int) -> bytes:
    return pkt("k", f"{addr:08X}{n:04X}")


def answer(addr: int, words: List[int]) -> bytes:
    return pkt("r", f"{addr:08X}{len(words):04X}" + "".join(f"{w:08X}" for w in words))


CONTROL = 0xFFFFFFF0
SAVED_PC = 0xFFFFFFD0
HELLO = b"\xffb08#CA"
PAUSED = b"\xffp#70"
CYCLE_LO = 0xFFFFFF40
TIME_LO = 0xFFFFFF44


def assemble(tmp: str, name: str, text: str) -> List[int]:
    """The words of a program from address 0, from niceasm."""
    src = os.path.join(tmp, name + ".nasm")
    with open(src, "w") as f:
        f.write(text)
    subprocess.run([sys.executable, NICEASM, src], check=True)
    words: dict[int, int] = {}
    with open(os.path.join(tmp, name + ".bin")) as f:
        for line in f:
            a, w = line.split()
            words[int(a, 16)] = int(w, 16)
    return [words.get(i, 0) for i in range(max(words) + 1)]


class Emu:
    """A niceemu --link 0, or on `addr`, and a host connected to it, at
    `host` if that is not the address to connect to."""

    def __init__(self, args: List[str] = [], addr: str = "127.0.0.1", host: Optional[str] = None) -> None:
        self.addr = host or addr
        link = "0" if addr == "127.0.0.1" else f"{addr}:0"
        self.proc = subprocess.Popen([NICEEMU, "--link", link] + args, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert self.proc.stderr is not None
        line = self.proc.stderr.readline().decode()
        if not line.startswith("link: port "):
            raise RuntimeError(f"no port line, got {line!r}")
        self.port = int(line.split()[2])
        self.sock = self.connect()
        self.buf = b""

    def connect(self) -> socket.socket:
        return socket.create_connection((self.addr, self.port), timeout=5)

    def send(self, data: bytes) -> None:
        self.sock.sendall(data)

    def take(self, n: int, timeout: float = 5) -> bytes:
        """The next n bytes, or fewer if none come for `timeout` s."""
        end = time.monotonic() + timeout
        while len(self.buf) < n:
            left = end - time.monotonic()
            if left <= 0:
                break
            self.sock.settimeout(left)
            try:
                got = self.sock.recv(65536)
            except socket.timeout:
                break
            if not got:
                break
            self.buf += got
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def expect(self, name: str, want: bytes, timeout: float = 5) -> None:
        expect(name, self.take(len(want), timeout), want)

    def stop(self) -> Tuple[int, bytes, bytes]:
        """Close the connection, end niceemu with SIGTERM, and return its
        exit status, stdout, and stderr."""
        self.sock.close()
        self.proc.send_signal(signal.SIGTERM)
        out, err = self.proc.communicate(timeout=10)
        return self.proc.returncode, out, err


failures: List[str] = []


def expect(name: str, got: bytes, want: bytes) -> None:
    if got != want:
        failures.append(f"{name}: got {got!r}, expected {want!r}")


def test_example() -> None:
    """DEBUG.md §8, byte for byte, with the processor held."""
    e = Emu()
    expect("b on connect", e.take(len(HELLO)), HELLO)
    e.send(b"\xffW0000010000021122334455667788#E2")
    e.expect("W", b"\xffk000001000002#AE")
    e.send(b"\xffR000001000001#94")
    e.expect("R", b"\xffr00000100000111223344#48")
    # The control register: held, and the ROM hidden, as with no ROM.
    e.send(read(CONTROL, 1))
    e.expect("control held", answer(CONTROL, [0x9]))
    # The halt reason, the version, the free space, and a reserved word.
    e.send(read(0xFFFFFFF1, 4))
    e.expect("F1-F4", answer(0xFFFFFFF1, [0, 8, 2048, 0]))
    # The breakpoints: four, none enabled, no stop, and the addresses 0.
    e.send(read(0xFFFFFFF5, 11))
    e.expect("F5-FF", answer(0xFFFFFFF5, [4] + [0] * 10))
    status, out, _ = e.stop()
    expect("exit status", bytes([status]), b"\x00")
    expect("stdout", out, b"")


def test_errors() -> None:
    """The errors of §3 and the drops of §5."""
    e = Emu()
    e.take(len(HELLO))
    # An unknown tag, upper and lower case: 01, with the tag as hex.
    e.send(pkt("X", "00000000"))
    e.expect("e01 X", pkt("e", "5801"))
    e.send(pkt("q", ""))
    e.expect("e01 q", pkt("e", "7101"))
    # A bad payload: too short, a byte that is not a hex digit.
    e.send(pkt("R", "00000100000"))
    e.expect("e03 short", pkt("e", "5203"))
    e.send(pkt("R", "0000010G0001"))
    e.expect("e03 not hex", pkt("e", "5203"))
    e.send(pkt("R", "0000010000010"))
    e.expect("e03 long R", pkt("e", "5203"))
    # A W with two words for N = 1 writes the first, and answers 03.
    e.send(pkt("W", "00000200" "0001" "AAAAAAAA" "BBBBBBBB"))
    e.expect("e03 long W", pkt("e", "5703"))
    e.send(read(0x200, 2))
    e.expect("long W wrote one", answer(0x200, [0xAAAAAAAA, 0]))
    # Lowercase hex digits are taken; the answer has uppercase ones.
    e.send(pkt("W", "000002ab" "0001" "0000face"))
    e.expect("lowercase W", ok(0x2AB, 1))
    e.send(pkt("R", "000002ab" "0001"))
    e.expect("lowercase R", answer(0x2AB, [0xFACE]))
    # A bad checksum, an ESC before the '#', and ESC and a digit are
    # dropped silently. The next request is answered.
    bad = bytearray(read(0x2AB, 1))
    bad[-1] ^= 1
    e.send(bytes(bad))
    e.send(ESC + b"R0000" + read(0x2AB, 1))
    e.send(ESC + b"1")
    e.send(read(0x2AB, 1))
    e.expect("after drops", answer(0x2AB, [0xFACE]) * 2)
    # A gap of more than 100 ms inside a packet drops it.
    r = read(0x2AB, 1)
    e.send(r[:6])
    time.sleep(0.3)
    e.send(r[6:])
    expect("timeout", e.take(1, timeout=0.5), b"")
    e.send(r)
    e.expect("after timeout", answer(0x2AB, [0xFACE]))
    # N = 0 is answered as any request.
    e.send(read(0, 0))
    e.expect("N = 0", answer(0, []))
    # A link read of the read counter returns 0. A link write to it is
    # ignored, and so is one to a read-only debug register.
    e.send(write(0xFFFFFF01, [5]) + write(0xFFFFFFF2, [7]))
    e.expect("ignored writes", ok(0xFFFFFF01, 1) + ok(0xFFFFFFF2, 1))
    e.send(read(0xFFFFFF01, 1) + read(0xFFFFFFF2, 1))
    e.expect("read counter", answer(0xFFFFFF01, [0]) + answer(0xFFFFFFF2, [8]))
    # A clear: 0x5 clears and stays held.
    e.send(write(CONTROL, [0x5]))
    e.expect("clear", ok(CONTROL, 1))
    e.send(read(0x200, 1) + read(CONTROL, 1))
    e.expect("cleared", answer(0x200, [0]) + answer(CONTROL, [0x9]))
    # A W that wraps past 0xFFFFFFFF is 02, also while held, and writes
    # nothing: not the start in its first word, nor word 0. An R may wrap.
    e.send(write(CONTROL, [0x0] + [0] * 15 + [0x1234]))
    e.expect("W wraps", pkt("e", "5702"))
    e.send(read(0xFFFFFFFF, 2) + read(CONTROL, 1))
    e.expect("R wraps", answer(0xFFFFFFFF, [0, 0]) + answer(CONTROL, [0x9]))
    # A second host is closed at once, with nothing sent.
    other = e.connect()
    other.settimeout(2)
    expect("second host", other.recv(100), b"")
    other.close()
    e.stop()


def test_run(echo: List[int]) -> None:
    """Load the echo program, start it, use the console, halt, restart."""
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, echo))
    e.expect("load", ok(0, len(echo)))
    # Console bytes are dropped while held: this one never reaches it.
    e.send(b"x")
    # Start: bit 0 from 1 to 0, with bit 3 kept at 1.
    e.send(b"\xffWFFFFFFF0000100000008#BA")
    e.expect("start", b"\xffkFFFFFFF00001#46")
    e.send(b"Hi" + ESC + ESC)
    e.expect("echo", b"Hi\xff\xff")
    # A packet with a bad high digit of cc is dropped with both bytes of cc,
    # so only the "4" after them reaches the program.
    e.send(b"\xffR000001000001#Z94")
    e.expect("bad cc digit", b"4")
    # While it runs, the memory is not reached, the debug registers are.
    e.send(b"\xffR000001000001#94")
    e.expect("e02", b"\xffe5202#2E")
    e.send(read(CONTROL, 2))
    e.expect("running", answer(CONTROL, [0x8, 0]))
    # The end of the input halts the program.
    e.sock.shutdown(socket.SHUT_WR)
    e.expect("halt", b"\xffh01#C9")
    e.sock.close()
    # A new host may connect after a half-close. The registers are those
    # the program left: R1 = 0x200, R2 = 4 bytes echoed.
    e.sock = e.connect()
    e.buf = b""
    expect("b again", e.take(len(HELLO)), HELLO)
    e.send(read(0xFFFFFFE1, 2) + read(CONTROL, 2))
    e.expect("after halt",
             answer(0xFFFFFFE1, [0x200, 4]) + answer(CONTROL, [0xA, 1]))
    # The restart of §8. The end of the input is cleared.
    e.send(b"\xffWFFFFFFF0000100000009#BB")
    e.expect("hold", b"\xffkFFFFFFF00001#46")
    e.send(read(CONTROL, 2))
    e.expect("held after halt", answer(CONTROL, [0xB, 1]))
    e.send(b"\xffWFFFFFFF0000100000008#BA")
    e.expect("restart", b"\xffkFFFFFFF00001#46")
    e.send(b"A")
    e.expect("echo after restart", b"A")
    # A hold while a console read waits stops the program, with no notice.
    e.send(write(CONTROL, [0x9]))
    e.expect("hold running", ok(CONTROL, 1))
    e.send(read(CONTROL, 2))
    e.expect("held, no h", answer(CONTROL, [0x9, 0]))
    status, out, err = e.stop()
    expect("exit status", bytes([status]), b"\x00")
    expect("stdout", out, b"")
    want = b"Halted (HALT) after 27 steps, PC=00000005\n"
    if want not in err:
        failures.append(f"stderr: {want!r} not in {err!r}")


def test_reconnect(echo_on: List[int]) -> None:
    """A half-close ends the line's input, and a program that reads on gets
    0x200 and keeps running. A new host's connection starts the line anew:
    its bytes reach the program, which echoes them to it (DEBUG.md §7)."""
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, echo_on))
    e.expect("load", ok(0, len(echo_on)))
    e.send(write(CONTROL, [0x8]))
    e.expect("start", ok(CONTROL, 1))
    e.send(b"ab")
    e.expect("echo", b"ab")
    e.sock.shutdown(socket.SHUT_WR)
    # The program reads the end and goes on, and nothing comes.
    expect("quiet after the half-close", e.take(1, timeout=0.3), b"")
    e.sock.close()
    e.sock = e.connect()
    e.buf = b""
    expect("b again", e.take(len(HELLO)), HELLO)
    e.send(b"c")
    e.expect("echo to the new host", b"c")
    e.send(read(0xFFFFFFE2, 1))
    e.expect("3 bytes echoed", answer(0xFFFFFFE2, [3]))
    status, out, err = e.stop()
    expect("exit status", bytes([status]), b"\x00")
    expect("stdout", out, b"")

    # A host that connects at once after the last one closed is served:
    # one poll may return both, and the emulator reads the end first.
    e = Emu()
    e.take(len(HELLO))
    for i in range(50):
        e.send(read(CONTROL, 1))
        e.expect(f"control {i}", answer(CONTROL, [0x9]))
        e.sock.close()
        e.sock = e.connect()
        e.buf = b""
        expect(f"b of host {i}", e.take(len(HELLO), timeout=0.5), HELLO)
    e.stop()


def test_overflow(spin: List[int]) -> None:
    """A full input buffer loses bytes, and sends one 'o' (§4)."""
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, spin) + write(CONTROL, [0x8]))
    e.expect("load and start", ok(0, len(spin)) + ok(CONTROL, 1))
    e.send(b"z" * 2048)
    e.send(read(0xFFFFFFF3, 1))
    e.expect("free space 0", answer(0xFFFFFFF3, [0]))
    e.send(b"zz")
    e.expect("o", b"\xffo#6F")
    expect("o once", e.take(1, timeout=0.5), b"")
    # A hold while it runs, as the spin program never reads.
    e.send(write(CONTROL, [0x9]))
    e.expect("hold", ok(CONTROL, 1))
    e.stop()


def send_behind(e: Emu, data: bytes) -> threading.Thread:
    """Send `data` from another thread, as the link may hold it back while
    the test reads the answers (DEBUG.md §1)."""
    t = threading.Thread(target=e.send, args=(data,))
    t.start()
    return t


def test_flood(echo: List[int], spin: List[int]) -> None:
    """Flow control over TCP (DEBUG.md §1, §7): a console byte that finds the
    input buffer full waits up to 50 ms for room, and the bytes behind it
    wait too."""
    # A program that reads gets every byte of a flood far larger than its
    # buffer, with no `o`.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, echo) + write(CONTROL, [0x8]))
    e.expect("echo start", ok(0, len(echo)) + ok(CONTROL, 1))
    flood = bytes(i % 255 for i in range(100000))
    t = send_behind(e, flood)
    got = e.take(len(flood), timeout=30)
    t.join()
    if got != flood:
        failures.append(f"flood to the echo program: {len(got)} of {len(flood)} bytes, "
                        f"{'equal' if flood.startswith(got) else 'different'}")
    expect("no o after the flood", e.take(1, timeout=0.3), b"")
    e.stop()

    # A program that never reads: the first byte past the buffer waits
    # 50 ms and is lost with one `o`. The rest are lost at once, and the
    # request behind them is answered then.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, spin) + write(CONTROL, [0x8]))
    e.expect("spin start", ok(0, len(spin)) + ok(CONTROL, 1))
    start = time.monotonic()
    t = send_behind(e, b"z" * 20000 + read(0xFFFFFFF3, 1))
    e.expect("o, then the answer", b"\xffo#6F" + answer(0xFFFFFFF3, [0]))
    took = time.monotonic() - start
    t.join()
    # The emulator counts whole milliseconds, so the 50 ms may be 49.x.
    if not 0.045 <= took < 2:
        failures.append(f"flood to the spin program: answered after {took:.3f} s")
    expect("o once", e.take(1, timeout=0.3), b"")
    e.stop()

    # Paused, the program reads nothing: the buffer fills, the next byte
    # is lost with `o` after 50 ms, the rest at once, and the go on behind
    # them is carried out. The program then echoes the buffer.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, echo) + write(CONTROL, [0x18]))
    e.expect("echo start paused", ok(0, len(echo)) + ok(CONTROL, 1) + PAUSED)
    first = bytes(ord("a") + i % 26 for i in range(2048))
    t = send_behind(e, first + b"Z" * 500 + write(CONTROL, [0x8]))
    e.expect("o, then the go on", b"\xffo#6F" + ok(CONTROL, 1))
    t.join()
    e.expect("the buffer after the go on", first)
    expect("the lost bytes", e.take(1, timeout=0.3), b"")
    e.stop()


def test_step_limit(spin: List[int]) -> None:
    """The step limit is a halt with reason 5 (§6, §7)."""
    e = Emu(["-n", "10"])
    e.take(len(HELLO))
    e.send(write(0, spin) + write(CONTROL, [0x8]))
    e.expect("load and start", ok(0, len(spin)) + ok(CONTROL, 1))
    e.expect("h05", b"\xffh05#CD")
    e.send(read(CONTROL, 2))
    e.expect("reason 5", answer(CONTROL, [0xA, 5]))
    # A clear ends the halt state, also that of the step limit.
    e.send(write(CONTROL, [0x5]) + read(CONTROL, 2))
    e.expect("clear after reason 5", ok(CONTROL, 1) + answer(CONTROL, [0x9, 0]))
    _, _, err = e.stop()
    want = b"Stopped at the step limit after 10 steps, PC=00000000\n"
    if want not in err:
        failures.append(f"stderr: {want!r} not in {err!r}")


def test_halts(reserved: List[int], int_in_isr: List[int], rti: List[int], spin: List[int]) -> None:
    """The halt reasons 2 to 4 reach the host as `h` and in the register
    (§4, §6), a clear ends the halt state, and a clear of the memory stops
    a running program (§6). INT in a routine halts with in_service, bit 7,
    at 1, which is not defined after the clear, so bits 7 and 8 are left
    out there."""
    for name, prog, reason, note, control in (
        ("reserved", reserved, 2, b"\xffh02#CA", 0xA),
        ("INT in a routine", int_in_isr, 3, b"\xffh03#CB", 0x8A),
        ("RTI outside", rti, 4, b"\xffh04#CC", 0xA),
    ):
        e = Emu()
        e.take(len(HELLO))
        e.send(write(0, prog) + write(CONTROL, [0x8]))
        e.expect(name + " start", ok(0, len(prog)) + ok(CONTROL, 1))
        e.expect(name + " notice", note)
        e.send(read(CONTROL, 2))
        e.expect(name + " reason", answer(CONTROL, [control, reason]))
        e.send(write(CONTROL, [0x5]))
        e.expect(name + " clear", ok(CONTROL, 1))
        expect(name + " cleared", bytes([word(e, CONTROL) & ~0x180, word(e, CONTROL + 1)]), bytes([0x9, 0]))
        e.stop()
    # A clear while the program runs holds it first. Bit 2 with bit 0 set
    # clears and stays held, with no notice.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, spin) + write(CONTROL, [0x8]))
    e.expect("spin start", ok(0, len(spin)) + ok(CONTROL, 1))
    e.send(write(CONTROL, [0xD]))
    e.expect("clear while running", ok(CONTROL, 1))
    e.send(read(0, 1) + read(CONTROL, 2))
    e.expect("cleared", answer(0, [0]) + answer(CONTROL, [0x9, 0]))
    e.stop()


def word(e: Emu, addr: int) -> int:
    """The word at addr, read over the link."""
    e.send(read(addr, 1))
    got = e.take(len(answer(addr, [0])))
    expect(f"answer at {addr:08X}", got[:14], answer(addr, [0])[:14])
    return int(got[-11:-3], 16)


def test_pause(count: List[int], echo: List[int]) -> None:
    """The pause of §6: bit 4, the `p` notice, the registers, a hold, a start
    paused, a halt first, and the console."""
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, count) + write(CONTROL, [0x8]))
    e.expect("load and start", ok(0, len(count)) + ok(CONTROL, 1))
    # A request. Bit 4 reads 1 once the processor has paused, and the memory
    # is reached then.
    e.send(write(CONTROL, [0x18]))
    e.expect("pause request", ok(CONTROL, 1))
    e.expect("p", PAUSED)
    expect("paused control", bytes([word(e, CONTROL)]), bytes([0x18]))
    r2 = word(e, 0xFFFFFFE2)
    r15 = word(e, 0xFFFFFFEF)
    if r2 == 0 or r15 not in (0, 2):
        failures.append(f"paused registers: R2 = {r2}, R15 = {r15}")
    e.send(read(0, 1))
    e.expect("memory while paused", answer(0, count[:1]))
    # Nothing moves while paused, and a console byte waits in the buffer.
    e.send(b"x")
    time.sleep(0.2)
    expect("R2 while paused", bytes([word(e, 0xFFFFFFE2) == r2]), b"\x01")
    expect("free space while paused", bytes([word(e, 0xFFFFFFF3) == 2047]), b"\x01")
    # A write of 0 to bit 4 goes on. The memory is out of reach again.
    e.send(write(CONTROL, [0x8]))
    e.expect("go on", ok(CONTROL, 1))
    e.send(read(0, 1))
    e.expect("e02 running", pkt("e", "5202"))
    expect("running control", bytes([word(e, CONTROL)]), bytes([0x8]))
    # The registers are the running program's (§6): R2 moves.
    r2a = word(e, 0xFFFFFFE2)
    time.sleep(0.05)
    r2c = word(e, 0xFFFFFFE2)
    if not r2 < r2a < r2c:
        failures.append(f"R2 did not move while running: {r2}, {r2a}, {r2c}")
    # A second pause: R2 has grown. A hold keeps the registers, and ends the
    # pause.
    e.send(write(CONTROL, [0x18]))
    e.expect("second request", ok(CONTROL, 1))
    e.expect("second p", PAUSED)
    r2b = word(e, 0xFFFFFFE2)
    if r2b <= r2:
        failures.append(f"R2 did not grow after go on: {r2} then {r2b}")
    e.send(write(CONTROL, [0x9]))
    e.expect("hold paused", ok(CONTROL, 1))
    expect("held control", bytes([word(e, CONTROL)]), bytes([0x9]))
    expect("held keeps R2", bytes([word(e, 0xFFFFFFE2) == r2b]), b"\x01")
    # A start with bit 4 set pauses before the first step: R15 is 0, the
    # input buffer is empty again, and R2 is not defined.
    e.send(write(CONTROL, [0x19]))
    e.expect("hold with request", ok(CONTROL, 1))
    expect("request reads 0 while held", bytes([word(e, CONTROL)]), bytes([0x9]))
    e.send(write(CONTROL, [0x18]))
    e.expect("start paused", ok(CONTROL, 1))
    e.expect("p at start", PAUSED)
    expect("start paused control", bytes([word(e, CONTROL)]), bytes([0x18]))
    expect("start paused R15", bytes([word(e, 0xFFFFFFEF)]), bytes([0]))
    # A canceled request: held, a request, and a write of 0 before the start.
    e.send(write(CONTROL, [0x9]))
    e.expect("hold again", ok(CONTROL, 1))
    e.send(write(CONTROL, [0x19]))
    e.expect("request while held", ok(CONTROL, 1))
    e.send(write(CONTROL, [0x9]))
    e.expect("cancel", ok(CONTROL, 1))
    e.send(write(CONTROL, [0x8]))
    e.expect("start", ok(CONTROL, 1))
    expect("no p after a cancel", e.take(1, timeout=0.5), b"")
    e.send(write(CONTROL, [0x9]))
    e.expect("hold", ok(CONTROL, 1))
    e.stop()

    # A pause while a console read waits undoes the step of the read: the
    # processor pauses before it, with R15 at the read, no byte taken, and
    # the counters as they were. A paused processor keeps what it is sent.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, echo) + write(CONTROL, [0x8]))
    e.expect("echo loaded", ok(0, len(echo)) + ok(CONTROL, 1))
    time.sleep(0.2)
    e.send(write(CONTROL, [0x18]))
    e.expect("p while the read waits", ok(CONTROL, 1) + PAUSED)
    expect("R15 at the read", bytes([word(e, 0xFFFFFFEF)]), b"\x00")
    expect("no byte in R1", bytes([word(e, 0xFFFFFFE1)]), b"\x00")
    expect("no step counted", bytes([word(e, CYCLE_LO)]), b"\x00")
    # A go on runs the read again, and it waits again.
    e.send(write(CONTROL, [0x8]))
    e.expect("echo go on", ok(CONTROL, 1))
    time.sleep(0.2)
    e.send(write(CONTROL, [0x18]))
    e.expect("second p", ok(CONTROL, 1) + PAUSED)
    expect("still no step", bytes([word(e, CYCLE_LO)]), b"\x00")
    e.send(b"abc")
    expect("no echo while paused", e.take(1, timeout=0.5), b"")
    expect("free space with three waiting", bytes([word(e, 0xFFFFFFF3) == 2045]), b"\x01")
    e.send(write(CONTROL, [0x8]))
    e.expect("echo go on with bytes", ok(CONTROL, 1))
    e.expect("echo abc", b"abc")
    # Three passes of six steps: the read, AND, the HALT not taken, the
    # echo, ADD, and the jump back. Then the read waits at 0.
    time.sleep(0.2)
    e.send(write(CONTROL, [0x18]))
    e.expect("p after abc", ok(CONTROL, 1) + PAUSED)
    expect("R15 at the read again", bytes([word(e, 0xFFFFFFEF)]), b"\x00")
    expect("R2 counts three", bytes([word(e, 0xFFFFFFE2)]), b"\x03")
    expect("18 steps", bytes([word(e, CYCLE_LO)]), b"\x12")
    e.send(write(CONTROL, [0x9]))
    e.expect("echo hold", ok(CONTROL, 1))
    e.stop()

    # A halt goes first: at the step limit, a request ends in h, not p, and
    # a halted processor ignores a request.
    e = Emu(["-n", "0"])
    e.take(len(HELLO))
    e.send(write(0, count) + write(CONTROL, [0x18]))
    e.expect("limit start", ok(0, len(count)) + ok(CONTROL, 1))
    e.expect("h05 first", b"\xffh05#CD")
    expect("halted control", bytes([word(e, CONTROL)]), bytes([0xA]))
    e.send(write(CONTROL, [0x18]))
    e.expect("request when halted", ok(CONTROL, 1))
    expect("still halted", bytes([word(e, CONTROL)]), bytes([0xA]))
    expect("no p when halted", e.take(1, timeout=0.5), b"")
    e.stop()


def test_clock(spin: List[int]) -> None:
    """The microsecond counter counts the host's time while the processor
    runs, and stops while it is paused or held. A start sets it to 0
    (DEVICES.md §3). With --step-time it counts the steps."""
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, spin) + write(CONTROL, [0x8]))
    e.expect("clock start", ok(0, len(spin)) + ok(CONTROL, 1))
    time.sleep(0.2)
    e.send(write(CONTROL, [0x18]))
    e.expect("clock pause", ok(CONTROL, 1) + PAUSED)
    t1 = word(e, TIME_LO)
    if not 150_000 <= t1 < 2_000_000:
        failures.append(f"clock after 0.2 s of running: {t1} us")
    time.sleep(0.5)
    expect("clock stopped while paused", bytes([word(e, TIME_LO) == t1]), b"\x01")
    # 0.1 s more of running. Had the pause counted, it would be 0.6 s.
    e.send(write(CONTROL, [0x8]))
    e.expect("clock go on", ok(CONTROL, 1))
    time.sleep(0.1)
    e.send(write(CONTROL, [0x18]))
    e.expect("clock second pause", ok(CONTROL, 1) + PAUSED)
    t2 = word(e, TIME_LO)
    if not 50_000 <= t2 - t1 < 400_000:
        failures.append(f"clock after 0.1 s more of running: {t1} us, then {t2} us")
    e.send(write(CONTROL, [0x9]))
    e.expect("clock hold", ok(CONTROL, 1))
    time.sleep(0.3)
    expect("clock stopped while held", bytes([word(e, TIME_LO) == t2]), b"\x01")
    # A start sets it to 0: at once paused, it is below the 0.3 s before.
    e.send(write(CONTROL, [0x8]) + write(CONTROL, [0x18]))
    e.expect("clock restart", ok(CONTROL, 1) + ok(CONTROL, 1) + PAUSED)
    t3 = word(e, TIME_LO)
    if not t3 < t1:
        failures.append(f"clock after a start: {t3} us, before it {t2} us")
    e.stop()

    e = Emu(["--step-time"])
    e.take(len(HELLO))
    e.send(write(0, spin) + write(CONTROL, [0x8]))
    e.expect("step-time start", ok(0, len(spin)) + ok(CONTROL, 1))
    time.sleep(0.05)
    e.send(write(CONTROL, [0x18]))
    e.expect("step-time pause", ok(CONTROL, 1) + PAUSED)
    t, c = word(e, TIME_LO), word(e, CYCLE_LO)
    if t != c or t == 0:
        failures.append(f"--step-time: {t} us after {c} steps")
    e.stop()


def regs_after_steps(irq: str, steps: int, opts: List[str]) -> List[Tuple[int, int, Optional[int]]]:
    """R13, R14, and R15 after each of the first `steps` steps of irq.bin,
    from `niceemu --trace`: a line shows the registers that its step wrote,
    and the pc of the next line is R15 after the step, but for an entry, whose line
    shows the vector. Then R15 is None."""
    proc = subprocess.run([NICEEMU, "-t", "-n", str(steps + 1)] + opts + [irq], capture_output=True, text=True)
    r = {13: 0, 14: 0}
    lines = proc.stdout.splitlines()[:steps + 1]
    out = []
    for i in range(steps):
        for part in lines[i].split():
            if part[0] == "R" and "=" in part and part[1:part.index("=")] in ("13", "14"):
                r[int(part[1:part.index("=")])] = int(part.split("=")[1], 16)
        nxt = lines[i + 1]
        r15 = None if nxt[0] in "NI" else int(nxt.split()[0], 16)
        out.append((r[13], r[14], r15))
    return out


def test_step(count: List[int], one: List[int], stop: List[int], echo: List[int], twice: List[int],
              irq: List[int], irq_bin: str) -> None:
    """The single step of §6: bit 5, the `p` or `h` after it, the cases where
    it does nothing, the step at a console read that would wait, and the
    interrupt entry."""
    # The example of §8, with its checksums written out.
    e = Emu()
    e.expect("hello", HELLO, timeout=5)
    e.send(write(0, one))
    e.expect("load one", ok(0, len(one)))
    e.send(ESC + b"WFFFFFFF0000100000018#BB")
    e.expect("start paused", b"\xffkFFFFFFF00001#46" + PAUSED)
    e.send(ESC + b"RFFFFFFEF0001#42")
    e.expect("R15 at 0", ESC + b"rFFFFFFEF000100000000#E2")
    e.send(ESC + b"WFFFFFFF0000100000038#BD")
    e.expect("step", b"\xffkFFFFFFF00001#46" + PAUSED)
    e.send(ESC + b"RFFFFFFEF0001#42")
    e.expect("R15 at 1", ESC + b"rFFFFFFEF000100000001#E3")
    e.stop()

    # R2 and R15 after each step of COUNT: ADD is two words, and MOVE R15 jumps
    # back. A step of a processor that is not paused does nothing, and a write
    # with bit 5 and without bit 4 goes on.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, count) + write(CONTROL, [0x38]))
    e.expect("load, bit 5 at a start", ok(0, len(count)) + ok(CONTROL, 1) + PAUSED)
    expect("start with bit 5 does not step", bytes([word(e, 0xFFFFFFEF)]), bytes([0]))
    for n, (r2, r15) in enumerate([(1, 2), (1, 0), (2, 2), (2, 0)]):
        e.send(write(CONTROL, [0x38]))
        e.expect(f"step {n}", ok(CONTROL, 1) + PAUSED)
        expect(f"control after step {n}", bytes([word(e, CONTROL)]), bytes([0x18]))
        expect(f"R2 and R15 after step {n}", bytes([word(e, 0xFFFFFFE2), word(e, 0xFFFFFFEF)]), bytes([r2, r15]))
    # Bit 5 reads 0, and a write of 0x28 goes on.
    e.send(write(CONTROL, [0x28]))
    e.expect("bit 5 without bit 4", ok(CONTROL, 1))
    e.send(read(0, 1))
    e.expect("runs", pkt("e", "5202"))
    # A step request to a running processor is a pause request.
    e.send(write(CONTROL, [0x38]))
    e.expect("step while running", ok(CONTROL, 1) + PAUSED)
    # Held: a step with bit 0 set holds, and bit 0 at 0 starts, paused, with no step.
    e.send(write(CONTROL, [0x39]))
    e.expect("step while held", ok(CONTROL, 1))
    expect("held", bytes([word(e, CONTROL)]), bytes([0x9]))
    e.send(write(CONTROL, [0x39]))
    e.expect("step with hold again", ok(CONTROL, 1))
    expect("no p", e.take(1, timeout=0.3), b"")
    e.send(write(CONTROL, [0x38]))
    e.expect("start with bit 5", ok(CONTROL, 1) + PAUSED)
    expect("R15 after the start", bytes([word(e, 0xFFFFFFEF)]), bytes([0]))
    e.stop()

    # A step into HALT ends in h, not p.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, stop) + write(CONTROL, [0x18]))
    e.expect("stop loaded", ok(0, len(stop)) + ok(CONTROL, 1) + PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("step into HALT", ok(CONTROL, 1) + b"\xffh01#C9")
    expect("halted", bytes([word(e, CONTROL)]), bytes([0xA]))
    e.send(write(CONTROL, [0x38]))
    e.expect("step when halted", ok(CONTROL, 1))
    expect("still halted, no notice", e.take(1, timeout=0.3), b"")
    e.stop()

    # The step limit counts the steps: the second step ends in h05.
    e = Emu(["-n", "2"])
    e.take(len(HELLO))
    e.send(write(0, count) + write(CONTROL, [0x18]))
    e.expect("limit loaded", ok(0, len(count)) + ok(CONTROL, 1) + PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("first step", ok(CONTROL, 1) + PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("second step", ok(CONTROL, 1) + b"\xffh05#CD")
    e.stop()

    # A step at a console read that would wait does not run: the processor
    # pauses again at once, with R15 at the read. With a byte in the input
    # buffer, the step runs.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, echo) + write(CONTROL, [0x18]))
    e.expect("echo loaded", ok(0, len(echo)) + ok(CONTROL, 1) + PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("echo step", ok(CONTROL, 1) + PAUSED)
    expect("R15 at the read", bytes([word(e, 0xFFFFFFEF)]), b"\x00")
    expect("no step counted", bytes([word(e, CYCLE_LO)]), b"\x00")
    e.send(b"a" + write(CONTROL, [0x38]))
    e.expect("step with a byte", ok(CONTROL, 1) + PAUSED)
    expect("R1 holds the byte", bytes([word(e, 0xFFFFFFE1) & 0xFF]), b"a")
    # AND, the HALT that is not taken, the echo, ADD, and the jump back.
    for n in range(5):
        e.send(write(CONTROL, [0x38]))
        e.expect(f"echo step {n}", ok(CONTROL, 1) + (b"a" if n == 2 else b"") + PAUSED)
    # At the read again, with a breakpoint there: the step that does not run
    # ends in x.
    set_breaks(e, [0], 1)
    e.send(write(CONTROL, [0x38]))
    e.expect("read step at a breakpoint", ok(CONTROL, 1) + hit(0))
    expect("six steps", bytes([word(e, CYCLE_LO)]), b"\x06")
    e.send(write(CONTROL, [0x9]))
    e.expect("hold", ok(CONTROL, 1))
    expect("held control", bytes([word(e, CONTROL)]), bytes([0x9]))
    e.stop()

    # An instruction that reads the console twice, with one byte waiting:
    # the first read takes it, and the second waits. The step does not run,
    # and the byte is back in the buffer. With a second byte, it runs, and
    # R3 is 0x161 + 0x162 (DEVICES.md §1).
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, twice) + write(CONTROL, [0x18]))
    e.expect("twice loaded", ok(0, len(twice)) + ok(CONTROL, 1) + PAUSED)
    e.send(b"a" + write(CONTROL, [0x38]))
    e.expect("step at the second read", ok(CONTROL, 1) + PAUSED)
    expect("R15 at the double read", bytes([word(e, 0xFFFFFFEF)]), b"\x00")
    expect("the byte is back", bytes([word(e, 0xFFFFFFF3) == 2047]), b"\x01")
    e.send(b"b" + write(CONTROL, [0x38]))
    e.expect("step with two bytes", ok(CONTROL, 1) + PAUSED)
    expect("R15 after the double read", bytes([word(e, 0xFFFFFFEF)]), b"\x03")
    expect("R3 holds both bytes", bytes([word(e, 0xFFFFFFE3) == 0x2C3]), b"\x01")
    expect("the buffer is empty", bytes([word(e, 0xFFFFFFF3) == 2048]), b"\x01")
    e.stop()

    # R13, R14, and R15 after each step, with an NMI and an IRQ: an entry is a
    # step of its own, and they match the trace.
    opts = ["--nmi", "2:1", "--irq", "2:2"]
    steps = 14
    want = regs_after_steps(irq_bin, steps, opts)
    # R15 before an entry: the words 4 and 10 are the next instructions of
    # irq.nasm after steps 1 and 7.
    here = {1: 4, 7: 10}
    e = Emu(opts)
    e.take(len(HELLO))
    e.send(write(0, irq) + write(CONTROL, [0x18]))
    e.expect("irq loaded", ok(0, len(irq)) + ok(CONTROL, 1) + PAUSED)
    for n in range(steps):
        e.send(write(CONTROL, [0x38]))
        e.expect(f"irq step {n}", ok(CONTROL, 1) + PAUSED)
        got = (word(e, 0xFFFFFFED), word(e, 0xFFFFFFEE), word(e, 0xFFFFFFEF))
        w13, w14, w15 = want[n]
        if got != (w13, w14, here[n] if w15 is None else w15):
            failures.append(f"irq step {n}: R13, R14, R15 = {got}, trace has {want[n]}, {here.get(n)}")
    e.stop()


BREAK_EN = 0xFFFFFFF4
STOP_REG = 0xFFFFFFF6
BREAK0 = 0xFFFFFFF8


def hit(n: int) -> bytes:
    """The `x` notice of breakpoint n (DEBUG.md §4)."""
    return pkt("x", f"{n:02X}")


def set_breaks(e: Emu, addrs: List[int], en: int) -> None:
    """Write the addresses of breakpoints 0 up, and then the enable bits."""
    e.send(write(BREAK0, addrs) + write(BREAK_EN, [en]))
    e.expect("set breakpoints", ok(BREAK0, len(addrs)) + ok(BREAK_EN, 1))


def test_break(at10: List[int], load: List[int], count: List[int], skip: List[int],
               stop: List[int], irq: List[int]) -> None:
    """The breakpoints of §6: the `x` notice, the stop register, the first
    step exempt, an interrupt entry first, and what keeps and clears them."""
    # The example of §8, with its checksums written out. The go on runs the
    # instruction at 0x10, a jump to itself, which stops there again.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, at10))
    e.expect("load at10", ok(0, len(at10)))
    e.send(ESC + b"WFFFFFFF8000100000010#BB")
    e.expect("address", ESC + b"kFFFFFFF80001#4E")
    e.send(ESC + b"WFFFFFFF4000100000001#B7")
    e.expect("enable", ESC + b"kFFFFFFF40001#4A")
    e.send(ESC + b"WFFFFFFF0000100000008#BA")
    e.expect("start to x", ESC + b"kFFFFFFF00001#46" + ESC + b"x00#D8")
    e.send(ESC + b"RFFFFFFEF0001#42")
    e.expect("R15 at 0x10", ESC + b"rFFFFFFEF000100000010#E3")
    e.send(ESC + b"RFFFFFFF60001#33")
    e.expect("stop register", ESC + b"rFFFFFFF6000100000100#D4")
    expect("control at x", bytes([word(e, CONTROL)]), bytes([0x18]))
    e.send(ESC + b"WFFFFFFF0000100000008#BA")
    e.expect("go on to x", ESC + b"kFFFFFFF00001#46" + ESC + b"x00#D8")
    e.stop()

    # A breakpoint at the start address, at an instruction with a data read,
    # fires before the first instruction and on each pass. Disabled, it lets
    # the program run, and the stop register reads 0 after a go on.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, load))
    e.expect("load load", ok(0, len(load)))
    set_breaks(e, [0], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("start at a breakpoint", ok(CONTROL, 1) + hit(0))
    expect("R2, R3 before the first", bytes([word(e, 0xFFFFFFE2), word(e, 0xFFFFFFE3)]), bytes([0, 0]))
    for n in range(1, 3):
        e.send(write(CONTROL, [0x8]))
        e.expect(f"pass {n}", ok(CONTROL, 1) + hit(0))
        expect(f"R2, R3 after pass {n}", bytes([word(e, 0xFFFFFFE2), word(e, 0xFFFFFFE3)]), bytes([7, n]))
    e.send(write(BREAK_EN, [0]) + write(CONTROL, [0x8]))
    e.expect("disable and go on", ok(BREAK_EN, 1) + ok(CONTROL, 1))
    expect("no x when disabled", e.take(1, timeout=0.3), b"")
    expect("stop register after a go on", bytes([word(e, STOP_REG)]), bytes([0]))
    e.send(write(CONTROL, [0x18]))
    e.expect("pause, not at a breakpoint", ok(CONTROL, 1) + PAUSED)
    expect("stop register after p", bytes([word(e, STOP_REG)]), bytes([0]))
    e.stop()

    # A step that ends at a breakpoint sends x, and a start paused at one
    # too. Two at one address send the lower number. Bits from N up and
    # addresses from N up take no write.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, count))
    e.expect("load count", ok(0, len(count)))
    set_breaks(e, [5, 2, 2, 7, 9], 0xFE)
    e.send(read(BREAK_EN, 1) + read(0xFFFFFFFC, 1))
    e.expect("no bits and addresses from N", answer(BREAK_EN, [0xE]) + answer(0xFFFFFFFC, [0]))
    e.send(write(CONTROL, [0x18]))
    e.expect("start paused at 0", ok(CONTROL, 1) + PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("step to 2", ok(CONTROL, 1) + hit(1))
    expect("stop register 1", bytes([word(e, STOP_REG) >> 8, word(e, STOP_REG) & 0xFF]), bytes([1, 1]))
    e.send(write(CONTROL, [0x38]))
    e.expect("step to 0", ok(CONTROL, 1) + PAUSED)
    set_breaks(e, [0], 0x1)
    e.send(write(CONTROL, [0x9]) + write(CONTROL, [0x18]))
    e.expect("start paused at a breakpoint", ok(CONTROL, 1) + ok(CONTROL, 1) + hit(0))
    # A hold keeps the stop register, and a clear clears it. Both keep the
    # breakpoints, and so does a start.
    e.send(write(CONTROL, [0x9]))
    e.expect("hold at x", ok(CONTROL, 1))
    expect("hold keeps the stop", bytes([word(e, STOP_REG) >> 8]), bytes([1]))
    e.send(write(CONTROL, [0x5]))
    e.expect("clear", ok(CONTROL, 1))
    expect("clear clears the stop", word(e, STOP_REG).to_bytes(4, "big"), bytes(4))
    e.send(read(BREAK_EN, 1) + read(BREAK0, 2))
    e.expect("clear keeps them", answer(BREAK_EN, [1]) + answer(BREAK0, [0, 2]))
    e.send(write(0, count) + write(BREAK_EN, [0]) + write(CONTROL, [0x8]))
    e.expect("reload and start", ok(0, len(count)) + ok(BREAK_EN, 1) + ok(CONTROL, 1))
    expect("start clears the stop", bytes([word(e, STOP_REG)]), bytes([0]))
    e.send(read(BREAK0, 2))
    e.expect("start keeps them", answer(BREAK0, [0, 2]))
    e.send(write(BREAK_EN, [1]))
    e.expect("enable while running", ok(BREAK_EN, 1) + hit(0))
    # A new connection clears them, with its b.
    e.sock.close()
    e.sock = e.connect()
    e.buf = b""
    e.expect("b again", HELLO)
    e.send(read(BREAK_EN, 1) + read(BREAK0, 2))
    e.expect("connection clears them", answer(BREAK_EN, [0]) + answer(BREAK0, [0, 0]))
    e.stop()

    # A skipped instruction is a step, so a breakpoint at it fires.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, skip))
    e.expect("load skip", ok(0, len(skip)))
    set_breaks(e, [2], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("skipped HALT", ok(CONTROL, 1) + hit(0))
    e.send(write(CONTROL, [0x8]))
    e.expect("skipped HALT again", ok(CONTROL, 1) + hit(0))
    expect("R2 after two passes", bytes([word(e, 0xFFFFFFE2)]), bytes([2]))
    e.stop()

    # A HALT at a breakpoint: x first, then h after a go on.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, stop))
    e.expect("load stop", ok(0, len(stop)))
    set_breaks(e, [0], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("x before HALT", ok(CONTROL, 1) + hit(0))
    e.send(write(CONTROL, [0x8]))
    e.expect("h after the go on", ok(CONTROL, 1) + b"\xffh01#C9")
    e.stop()

    # irq.nasm with one IRQ, raised before step 5, the A3 at word 10: the
    # entry goes first, and the breakpoint at 10 fires after the RTI, at the
    # instruction after it. The log at 0x200 is A1 A2 C1 C2 then.
    def log(e: Emu) -> List[int]:
        e.send(read(0x200, 4))
        got = e.take(len(answer(0x200, [0] * 4)))
        return [int(got[14 + 8 * i:22 + 8 * i], 16) for i in range(4)]

    e = Emu(["--irq", "5:2"])
    e.take(len(HELLO))
    e.send(write(0, irq))
    e.expect("load irq", ok(0, len(irq)))
    set_breaks(e, [10], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("entry first", ok(CONTROL, 1) + hit(0))
    expect("log after the RTI", bytes(log(e)), bytes([0xA1, 0xA2, 0xC1, 0xC2]))
    e.stop()

    # A breakpoint at the IRQ routine's first instruction fires inside it.
    e = Emu(["--irq", "5:2"])
    e.take(len(HELLO))
    e.send(write(0, irq))
    e.expect("load irq", ok(0, len(irq)))
    set_breaks(e, [20], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("in the routine", ok(CONTROL, 1) + hit(0))
    expect("log in the routine", bytes(log(e)), bytes([0xA1, 0xA2, 0, 0]))
    e.stop()

    # Stepped to the breakpoint at 10 before step 5, the go on takes the IRQ
    # raised then first, and stops at 10 again after the RTI.
    e = Emu(["--irq", "5:2"])
    e.take(len(HELLO))
    e.send(write(0, irq))
    e.expect("load irq", ok(0, len(irq)))
    set_breaks(e, [10], 1)
    e.send(write(CONTROL, [0x18]))
    e.expect("irq start paused", ok(CONTROL, 1) + PAUSED)
    for n in range(4):
        e.send(write(CONTROL, [0x38]))
        e.expect(f"irq step {n}", ok(CONTROL, 1) + PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("step to 10", ok(CONTROL, 1) + hit(0))
    expect("log at 10", bytes(log(e)), bytes([0xA1, 0xA2, 0, 0]))
    e.send(write(CONTROL, [0x8]))
    e.expect("go on to the entry", ok(CONTROL, 1) + hit(0))
    expect("log after the RTI", bytes(log(e)), bytes([0xA1, 0xA2, 0xC1, 0xC2]))
    e.stop()


WATCH_EN = 0xFFFFFFD4
WATCH_PC = 0xFFFFFFD6
WATCH0 = 0xFFFFFFD8
HALTED = b"\xffh01#C9"


def whit(n: int) -> bytes:
    """The `w` notice of watchpoint n (DEBUG.md §4)."""
    return pkt("w", f"{n:02X}")


def set_watches(e: Emu, addrs: List[int], en: int) -> None:
    """Write the addresses of watchpoints 0 up, and then the enable bits."""
    e.send(write(WATCH0, addrs) + write(WATCH_EN, [en]))
    e.expect("set watchpoints", ok(WATCH0, len(addrs)) + ok(WATCH_EN, 1))


def test_watch(watch: List[int], write200: List[int], irq: List[int]) -> None:
    """The watchpoints of §6: the `w` notice, a stop after the step, the
    address of the hit, the accesses that hit, and what keeps and clears
    them. The addresses are those of WATCH."""
    data = 15

    def started(name: str, en: int, args: List[str] = [], addrs: List[int] = [data],
                control: int = 0x8) -> Emu:
        e = Emu(args)
        e.take(len(HELLO))
        e.send(write(0, watch))
        e.expect("load watch", ok(0, len(watch)))
        set_watches(e, addrs, en)
        e.send(write(CONTROL, [control]))
        e.expect(name, ok(CONTROL, 1))
        return e

    def at(name: str, e: Emu, r15: int, pc: int, stop: int) -> None:
        got = (word(e, 0xFFFFFFEF), word(e, WATCH_PC), word(e, STOP_REG))
        if got != (r15, pc, stop):
            failures.append(f"{name}: R15, hit, stop = {got}, expected {(r15, pc, stop)}")

    # The example of §8, with its checksums written out.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, write200))
    e.expect("load write200", ok(0, len(write200)))
    e.send(ESC + b"WFFFFFFD8000100000200#BA")
    e.expect("address", ESC + b"kFFFFFFD80001#4C")
    e.send(ESC + b"WFFFFFFD4000100000002#B6")
    e.expect("enable", ESC + b"kFFFFFFD40001#48")
    e.send(ESC + b"WFFFFFFF0000100000008#BA")
    e.expect("start to w", ESC + b"kFFFFFFF00001#46" + ESC + b"w00#D7")
    e.send(ESC + b"RFFFFFFD60001#31")
    e.expect("address of the hit", ESC + b"rFFFFFFD6000100000010#D2")
    e.send(ESC + b"RFFFFFFF60001#33")
    e.expect("stop register", ESC + b"rFFFFFFF6000100000200#D5")
    expect("control at w", bytes([word(e, CONTROL)]), bytes([0x18]))
    expect("R15 after the write", bytes([word(e, 0xFFFFFFEF)]), bytes([0x12]))
    e.stop()

    # A write: the stop comes after it, with the value in memory. The reads
    # are not enabled, so the go on runs to the HALT.
    e = started("start to the write", 0x2)
    e.expect("w after the write", whit(0))
    at("write", e, 3, 0, 0x200)
    expect("the value written", bytes([word(e, data)]), bytes([5]))
    e.send(write(CONTROL, [0x8]))
    e.expect("go on to the halt", ok(CONTROL, 1) + HALTED)
    e.stop()

    # The reads: one, none for a skipped instruction, and two in one step,
    # which stop once.
    e = started("start to the read", 0x1)
    e.expect("w after the read", whit(0))
    at("read", e, 5, 3, 0x200)
    expect("R2 read", bytes([word(e, 0xFFFFFFE2)]), bytes([5]))
    e.send(write(CONTROL, [0x8]))
    e.expect("go on past the skipped read", ok(CONTROL, 1) + whit(0))
    at("two reads", e, 10, 7, 0x200)
    expect("R4 of two reads", bytes([word(e, 0xFFFFFFE4)]), bytes([10]))
    e.send(write(CONTROL, [0x8]))
    e.expect("go on to the halt", ok(CONTROL, 1) + HALTED)
    expect("stop register after a go on", word(e, STOP_REG).to_bytes(4, "big"), bytes(4))
    expect("hit after a go on", word(e, WATCH_PC).to_bytes(4, "big"), bytes(4))
    e.stop()

    # The vector read of INT: the stop is at the routine's first
    # instruction, inside the routine, and the hit at the INT.
    e = started("start to the INT", 0x4, addrs=[data, 0x102])
    e.expect("w after the INT", whit(1))
    at("INT", e, 14, 12, 0x201)
    expect("in_service", bytes([word(e, CONTROL) >> 7 & 1]), bytes([1]))
    e.send(write(CONTROL, [0x8]))
    e.expect("go on to the halt", ok(CONTROL, 1) + HALTED)
    e.stop()

    # The vector read of an IRQ entry, in irq.nasm with the IRQ raised
    # before step 5: the hit is at A3, where the entry goes, its saved PC.
    e = Emu(["--irq", "5:2"])
    e.take(len(HELLO))
    e.send(write(0, irq))
    e.expect("load irq", ok(0, len(irq)))
    set_watches(e, [0x102], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("w after the entry", ok(CONTROL, 1) + whit(0))
    at("IRQ entry", e, 20, 10, 0x200)
    expect("saved PC", bytes([word(e, SAVED_PC)]), bytes([10]))
    e.stop()

    # The lowest number of two that hit, a write that a read watchpoint
    # does not see, and a watchpoint before a breakpoint at the new R15.
    e = started("start to two", 0x14, addrs=[data, data, data])
    e.expect("lowest of two", whit(1))
    at("two at one address", e, 5, 3, 0x201)
    e.stop()
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, watch))
    e.expect("load watch", ok(0, len(watch)))
    set_watches(e, [data], 0x2)
    set_breaks(e, [3], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("w before x", ok(CONTROL, 1) + whit(0))
    at("w before x", e, 3, 0, 0x200)
    e.send(write(CONTROL, [0x8]))
    e.expect("the breakpoint exempt", ok(CONTROL, 1) + HALTED)
    e.stop()

    # A step that hits ends in w, and one that does not in p. A start
    # paused has run no step. A hold keeps the stop and the hit, and a
    # clear clears them, but not the watchpoints.
    e = started("start paused", 0x2, control=0x18)
    e.expect("p at the start", PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("step to w", ok(CONTROL, 1) + whit(0))
    at("step", e, 3, 0, 0x200)
    e.send(write(CONTROL, [0x38]))
    e.expect("step to p", ok(CONTROL, 1) + PAUSED)
    at("step without a hit", e, 5, 0, 0)
    e.send(write(0xFFFFFFEF, [0]) + write(CONTROL, [0x38]))
    e.expect("step again to w", ok(0xFFFFFFEF, 1) + ok(CONTROL, 1) + whit(0))
    e.send(write(CONTROL, [0x9]))
    e.expect("hold at w", ok(CONTROL, 1))
    at("hold keeps them", e, 3, 0, 0x200)
    e.send(write(CONTROL, [0x5]))
    e.expect("clear", ok(CONTROL, 1))
    expect("clear clears the stop", word(e, STOP_REG).to_bytes(4, "big"), bytes(4))
    e.send(read(WATCH_EN, 1) + read(WATCH0, 1))
    e.expect("clear keeps them", answer(WATCH_EN, [2]) + answer(WATCH0, [data]))
    e.stop()

    # The step limit is a halt: a step that hits and reaches it ends in h.
    e = started("start to the limit", 0x2, args=["--max-steps", "1"])
    e.expect("h at the limit", b"\xffh05#CD")
    e.stop()

    # The registers: M = 4, the bits from 2M up and the words from M up
    # take no write, and the reserved words read 0. A new connection clears
    # the watchpoints.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(WATCH_EN, [0xFFFFFFFF]) + write(WATCH0, [1, 2, 3, 4, 5, 6, 7, 8]))
    e.expect("write all", ok(WATCH_EN, 1) + ok(WATCH0, 8))
    e.send(read(0xFFFFFFD2, 14))
    e.expect("D2-DF", answer(0xFFFFFFD2, [0, 0, 0xFF, 4, 0, 0, 1, 2, 3, 4, 0, 0, 0, 0]))
    e.sock.close()
    e.sock = e.connect()
    e.buf = b""
    e.expect("b again", HELLO)
    e.send(read(WATCH_EN, 1) + read(WATCH0, 4))
    e.expect("connection clears them", answer(WATCH_EN, [0]) + answer(WATCH0, [0] * 4))
    e.stop()


def test_wait(waiter: List[int]) -> None:
    """A processor that waits (§6, ISA §7.5): bit 6, a pause and a step in
    the wait, a breakpoint at R15 that fires only when the wait ends, and a
    wait that no request can end, which does not stop the run (§7.2)."""
    # No request can come: the run goes on, and bit 6 reads 1.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, waiter) + write(CONTROL, [0x8]))
    e.expect("start the wait", ok(0, len(waiter)) + ok(CONTROL, 1))
    time.sleep(0.3)
    expect("no notice in the wait", e.take(1, 0.1), b"")
    expect("control in the wait", bytes([word(e, CONTROL)]), bytes([0x48]))
    e.send(write(CONTROL, [0x18]))
    e.expect("pause in the wait", ok(CONTROL, 1) + PAUSED)
    expect("control paused in the wait", bytes([word(e, CONTROL)]), bytes([0x58]))
    expect("R15 after the WAIT", bytes([word(e, 0xFFFFFFEF)]), b"\x01")
    _, _, err = e.stop()
    if b"Stopped" in err or b"Halted" in err:
        failures.append(f"a wait with the link stopped the run: {err!r}")

    # --irq at step 1000, with E = 0: the wait ends there, and the MOVE runs.
    e = Emu(["--irq", "1000:5"])
    e.take(len(HELLO))
    e.send(write(0, waiter) + write(CONTROL, [0x18]))
    e.expect("start paused", ok(0, len(waiter)) + ok(CONTROL, 1) + PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("step the WAIT", ok(CONTROL, 1) + PAUSED)
    expect("control after the WAIT", bytes([word(e, CONTROL)]), bytes([0x58]))
    # A step in the wait is one wait step: R15 stays, and a cycle passes.
    e.send(write(CONTROL, [0x38]))
    e.expect("a wait step", ok(CONTROL, 1) + PAUSED)
    expect("R15 in the wait", bytes([word(e, 0xFFFFFFEF)]), b"\x01")
    expect("CYCLE_LO after two steps", bytes([word(e, 0xFFFFFF40)]), b"\x02")
    # A breakpoint at R15 does not stop the wait, and fires when the request
    # at step 1000 ends it, before the MOVE. Bit 6 reads 0 then, and bit
    # 10 reads 1, as E = 0 keeps the IRQ pending.
    set_breaks(e, [1], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("go on to the end of the wait", ok(CONTROL, 1) + hit(0))
    expect("control at the end of the wait", word(e, CONTROL).to_bytes(2, "big"), (0x418).to_bytes(2, "big"))
    expect("CYCLE_LO at the end of the wait", word(e, 0xFFFFFF40).to_bytes(2, "big"), (1000).to_bytes(2, "big"))
    e.send(write(BREAK_EN, [0]) + write(CONTROL, [0x8]))
    e.expect("go on to the halt", ok(BREAK_EN, 1) + ok(CONTROL, 1) + b"\xffh01#C9")
    expect("R1 after the wait", bytes([word(e, 0xFFFFFFE1)]), b"\x01")
    e.stop()


def test_time_skip(skipper: List[int]) -> None:
    """A skip of TIME_SKIP with --step-time (§6, DEVICES.md §3): a single
    step runs the rest of the skip with the step after it, bit 6 stays 0,
    and a breakpoint at R15 fires after the skip."""
    e = Emu(["--step-time"])
    e.take(len(HELLO))
    e.send(write(0, skipper) + write(CONTROL, [0x18]))
    e.expect("start paused", ok(0, len(skipper)) + ok(CONTROL, 1) + PAUSED)
    e.send(write(CONTROL, [0x38]))
    e.expect("step the write", ok(CONTROL, 1) + PAUSED)
    expect("control after the write", bytes([word(e, CONTROL)]), bytes([0x18]))
    expect("R15 after the write", bytes([word(e, 0xFFFFFFEF)]), b"\x03")
    expect("CYCLE_LO after the write", bytes([word(e, 0xFFFFFF40)]), b"\x01")
    e.send(write(CONTROL, [0x38]))
    e.expect("step the skip and the MOVE", ok(CONTROL, 1) + PAUSED)
    expect("R15 after the skip", bytes([word(e, 0xFFFFFFEF)]), b"\x05")
    expect("R1 after the skip", bytes([word(e, 0xFFFFFFE1)]), b"\x01")
    expect("CYCLE_LO after the skip", word(e, 0xFFFFFF40).to_bytes(2, "big"), (1002).to_bytes(2, "big"))
    e.stop()

    e = Emu(["--step-time"])
    e.take(len(HELLO))
    e.send(write(0, skipper) + write(CONTROL, [0x18]))
    e.expect("start paused again", ok(0, len(skipper)) + ok(CONTROL, 1) + PAUSED)
    set_breaks(e, [3], 1)
    e.send(write(CONTROL, [0x8]))
    e.expect("go on to the end of the skip", ok(CONTROL, 1) + hit(0))
    expect("R1 at the breakpoint", bytes([word(e, 0xFFFFFFE1)]), b"\x00")
    expect("CYCLE_LO at the breakpoint", word(e, 0xFFFFFF40).to_bytes(2, "big"), (1001).to_bytes(2, "big"))
    e.send(write(BREAK_EN, [0]) + write(CONTROL, [0x8]))
    e.expect("go on to the halt after the skip", ok(BREAK_EN, 1) + ok(CONTROL, 1) + b"\xffh01#C9")
    e.stop()


def test_hidden(hidden: List[int], count: List[int]) -> None:
    """The hidden state and the pending requests (§6), stepped through an
    INT, its RTI, and an NMI that waits for the RTI: bits 7 to 10 of the
    control register, saved_pc and saved_sr. The NMI and an IRQ, which
    E = 0 holds, come before step 4 (README, --nmi), so they are pending
    after it. Then the reserved words, and the range while running."""
    e = Emu(["--nmi", "3:3", "--irq", "3:4"])
    e.take(len(HELLO))
    e.send(write(0, hidden) + write(CONTROL, [0x18]))
    e.expect("start paused", ok(0, len(hidden)) + ok(CONTROL, 1) + PAUSED)

    def state(name: str, control: int, pc: int, sr: int, r15: int) -> None:
        e.send(read(CONTROL, 1) + read(SAVED_PC, 2) + read(0xFFFFFFEF, 1))
        e.expect(name, answer(CONTROL, [control]) + answer(SAVED_PC, [pc, sr]) + answer(0xFFFFFFEF, [r15]))

    def step(name: str) -> None:
        e.send(write(CONTROL, [0x38]))
        e.expect(name, ok(CONTROL, 1) + PAUSED)

    state("after reset", 0x18, 0, 0, 0)
    step("MOVE R14")
    state("after MOVE R14", 0x18, 0, 0, 2)
    # INT 2: in_service, and the PC after the INT and the SR saved.
    step("INT 2")
    state("in the routine", 0x98, 3, 0x01000001, 5)
    step("NOP in the routine")
    state("after the NOP", 0x98, 3, 0x01000001, 6)
    # RTI: after_rti, and the NMI and the IRQ pending since this step.
    step("RTI")
    state("after RTI", 0x718, 3, 0x01000001, 3)
    # The instruction after RTI runs first, and clears after_rti.
    step("NOP after RTI")
    state("after the NOP after RTI", 0x618, 3, 0x01000001, 4)
    # The NMI is taken before the HALT at 4. The IRQ stays, as E = 0.
    step("NMI entry")
    state("in the NMI routine", 0x498, 4, 0x01000001, 7)
    # The routine halts: the state stays as the program left it, and the
    # requests read 0. A hold keeps it.
    e.send(write(CONTROL, [0x38]))
    e.expect("HALT", ok(CONTROL, 1) + b"\xffh01#C9")
    state("halted", 0x8A, 4, 0x01000001, 8)
    e.send(write(CONTROL, [0x9]))
    e.expect("hold", ok(CONTROL, 1))
    state("held", 0x8B, 4, 0x01000001, 8)
    # Read only: saved_pc, saved_sr, the reserved words, and the number of
    # watchpoints and the address of a hit take no write, nor do bits 7 to
    # 10. The enable bits and the addresses of the watchpoints do.
    e.send(write(SAVED_PC, [0x55] * 16) + write(CONTROL, [0x789]))
    e.expect("writes", ok(SAVED_PC, 16) + ok(CONTROL, 1))
    e.send(read(SAVED_PC, 16) + read(CONTROL, 1))
    e.expect("unchanged", answer(SAVED_PC, [4, 0x01000001, 0, 0, 0x55, 4, 0, 0] + [0x55] * 4 + [0] * 4)
             + answer(CONTROL, [0x8B]))
    # While the program runs, the whole range answers: r and k, not e02.
    e.send(write(0, count) + write(CONTROL, [0x8]))
    e.expect("start count", ok(0, len(count)) + ok(CONTROL, 1))
    e.send(read(0xFFFFFFD2, 14) + write(0xFFFFFFD2, [1]) + read(0xFFFFFFCF, 1))
    e.expect("running", answer(0xFFFFFFD2, [0, 0, 0x55, 4, 0, 0] + [0x55] * 4 + [0] * 4) + ok(0xFFFFFFD2, 1)
             + pkt("e", "5202"))
    e.stop()


NMI_REQ = 0xFFFFFFD7


def test_nmi(nmi: List[int], wait_nmi: List[int]) -> None:
    """The NMI request of §6: one raised while running, paused, waiting,
    held, and halted, the merge, a write with bit 8 clear, and the drop by
    a hold and by a new host."""
    e = Emu()
    e.take(len(HELLO))
    # Running: the routine runs, and halts. The request reads 0 once taken.
    e.send(write(0, nmi) + write(CONTROL, [0x8]))
    e.expect("start", ok(0, len(nmi)) + ok(CONTROL, 1))
    expect("no NMI pending", bytes([word(e, NMI_REQ)]), b"\x00")
    e.send(write(NMI_REQ, [0x102]))
    e.expect("NMI while running", ok(NMI_REQ, 1) + b"\xffh01#C9")
    e.send(read(0xFFFFFFE3, 1) + read(NMI_REQ, 1))
    e.expect("in the routine", answer(0xFFFFFFE3, [0x77]) + answer(NMI_REQ, [0]))
    expect("saved_pc in the loop", bytes([word(e, SAVED_PC) in (3, 5)]), b"\x01")
    # Halted, then held: a write raises nothing. Bit 7 reads 1, as the
    # routine halted.
    for name, ctl in (("halted", 0x8A), ("held", 0x8B)):
        if name == "held":
            e.send(write(CONTROL, [0x9]))
            e.expect("hold", ok(CONTROL, 1))
        e.send(write(NMI_REQ, [0x102]) + read(NMI_REQ, 1) + read(CONTROL, 1))
        e.expect(f"NMI while {name}", ok(NMI_REQ, 1) + answer(NMI_REQ, [0]) + answer(CONTROL, [ctl]))
    # Paused: it waits, reads with its vector, and bit 9 reads 1. A second
    # write merges, and bit 8 clear raises nothing. A step takes it.
    e.send(write(CONTROL, [0x18]))
    e.expect("start paused", ok(CONTROL, 1) + PAUSED)
    e.send(write(NMI_REQ, [0x02]) + read(NMI_REQ, 1))
    e.expect("bit 8 clear", ok(NMI_REQ, 1) + answer(NMI_REQ, [0]))
    e.send(write(NMI_REQ, [0x102]) + write(NMI_REQ, [0x1FF]) + read(NMI_REQ, 1) + read(CONTROL, 1))
    e.expect("pending while paused", ok(NMI_REQ, 1) + ok(NMI_REQ, 1) + answer(NMI_REQ, [0x102])
             + answer(CONTROL, [0x218]))
    e.send(write(CONTROL, [0x38]))
    e.expect("step into the routine", ok(CONTROL, 1) + PAUSED)
    e.send(read(0xFFFFFFEF, 1) + read(NMI_REQ, 1) + read(CONTROL, 1) + read(SAVED_PC, 1))
    e.expect("at the routine", answer(0xFFFFFFEF, [7]) + answer(NMI_REQ, [0]) + answer(CONTROL, [0x98])
             + answer(SAVED_PC, [0]))
    # A hold drops a pending request: the next start paused steps the MOVE.
    e.send(write(CONTROL, [0x11]) + write(CONTROL, [0x18]))
    e.expect("restart paused", ok(CONTROL, 1) + ok(CONTROL, 1) + PAUSED)
    e.send(write(NMI_REQ, [0x102]) + write(CONTROL, [0x11]) + write(CONTROL, [0x18]))
    e.expect("raise, hold, start", ok(NMI_REQ, 1) + ok(CONTROL, 1) + ok(CONTROL, 1) + PAUSED)
    e.send(read(NMI_REQ, 1) + write(CONTROL, [0x38]))
    e.expect("dropped", answer(NMI_REQ, [0]) + ok(CONTROL, 1) + PAUSED)
    expect("R15 after the MOVE", bytes([word(e, 0xFFFFFFEF)]), b"\x03")
    # A new host drops it too: every b leaves none.
    e.send(write(NMI_REQ, [0x102]))
    e.expect("raise before the new host", ok(NMI_REQ, 1))
    e.sock.close()
    e.sock = e.connect()
    e.buf = b""
    e.expect("b of the new host", HELLO)
    e.send(read(NMI_REQ, 1) + read(CONTROL, 1))
    e.expect("none after b", answer(NMI_REQ, [0]) + answer(CONTROL, [0x18]))
    e.stop()

    # Waiting with no request to come: the NMI ends the wait, and the
    # routine runs with the PC after the WAIT saved.
    e = Emu()
    e.take(len(HELLO))
    e.send(write(0, wait_nmi) + write(CONTROL, [0x8]))
    e.expect("start the wait", ok(0, len(wait_nmi)) + ok(CONTROL, 1))
    time.sleep(0.2)
    expect("control in the wait", bytes([word(e, CONTROL)]), bytes([0x48]))
    e.send(write(NMI_REQ, [0x102]))
    e.expect("NMI in the wait", ok(NMI_REQ, 1) + b"\xffh01#C9")
    e.send(read(0xFFFFFFE3, 1) + read(SAVED_PC, 1))
    e.expect("the routine after the wait", answer(0xFFFFFFE3, [0x77]) + answer(SAVED_PC, [1]))
    e.stop()


def test_write_regs(regs: List[int], at20: List[int], count: List[int]) -> None:
    """The writes of R0-R15 of §6: what they mean, a written R15 and the
    breakpoints, e04 while not paused, and the example of §8."""
    e = Emu()
    e.take(len(HELLO))
    # Start paused at a breakpoint at 0: x00, and the stop register.
    e.send(write(0, regs) + write(0xFFFFFFF8, [0]) + write(BREAK_EN, [1]) + write(CONTROL, [0x18]))
    e.expect("load and start paused", ok(0, len(regs)) + ok(0xFFFFFFF8, 1) + ok(BREAK_EN, 1)
             + ok(CONTROL, 1) + hit(0))
    # R3 and R15 take the value, R0 none, and R14 gets bit 24. The stop
    # register keeps its value.
    e.send(write(0xFFFFFFE3, [5]) + write(0xFFFFFFEF, [0x20]) + write(0xFFFFFFE0, [7])
           + write(0xFFFFFFEE, [0]))
    e.expect("writes while paused", ok(0xFFFFFFE3, 1) + ok(0xFFFFFFEF, 1) + ok(0xFFFFFFE0, 1)
             + ok(0xFFFFFFEE, 1))
    e.send(read(0xFFFFFFE0, 16) + read(STOP_REG, 1))
    e.expect("read back", answer(0xFFFFFFE0, [0, 0, 0, 5] + [0] * 10 + [0x01000000, 0x20])
             + answer(STOP_REG, [0x100]))
    # A step runs the instruction at the new R15.
    e.send(write(CONTROL, [0x38]))
    e.expect("step at 0x20", ok(CONTROL, 1) + PAUSED)
    e.send(read(0xFFFFFFE4, 1) + read(0xFFFFFFEF, 1) + read(STOP_REG, 1))
    e.expect("after the step", answer(0xFFFFFFE4, [5]) + answer(0xFFFFFFEF, [0x21])
             + answer(STOP_REG, [0]))
    # A write of R15 to an enabled breakpoint, and a go on: its instruction
    # runs, and the program halts after it, with no stop first.
    e.send(write(0xFFFFFFF8, [0x20]) + write(0xFFFFFFE4, [0]) + write(0xFFFFFFEF, [0x20]))
    e.expect("breakpoint at the new R15", ok(0xFFFFFFF8, 1) + ok(0xFFFFFFE4, 1) + ok(0xFFFFFFEF, 1))
    e.send(write(CONTROL, [0x8]))
    e.expect("go on from it", ok(CONTROL, 1) + b"\xffh01#C9")
    e.send(read(0xFFFFFFE4, 1) + read(0xFFFFFFEF, 1))
    e.expect("halted", answer(0xFFFFFFE4, [5]) + answer(0xFFFFFFEF, [0x22]))
    # Halted, and then held: e04 by the range, R0 and from the devices
    # included, and nothing is written. N = 0 reaches nothing. 0xFFFFFFDF
    # is a reserved register of the link, which takes no write, and
    # 0xFFFFFEFF the last word of the memory, 0xE1 words below R0.
    for state in ("halted", "held"):
        e.send(write(0xFFFFFFDF, [0x77]) + write(0xFFFFFEFF, [0x77]))
        e.expect(f"{state}: reserved", ok(0xFFFFFFDF, 1) + ok(0xFFFFFEFF, 1))
        e.send(write(0xFFFFFFE3, [9]) + write(0xFFFFFFE0, [9]) + write(0xFFFFFFDF, [0x99, 9])
               + write(0xFFFFFEFF, [0x99] + [0] * 0xE1) + write(0xFFFFFFE0, []))
        e.expect(f"{state}: e04", pkt("e", "5704") * 4 + ok(0xFFFFFFE0, 0))
        e.send(read(0xFFFFFFDF, 5) + read(0xFFFFFEFF, 1))
        e.expect(f"{state}: unchanged", answer(0xFFFFFFDF, [0, 0, 0, 0, 5]) + answer(0xFFFFFEFF, [0x77]))
        e.send(write(CONTROL, [0x9]))
        e.expect(f"{state}: hold", ok(CONTROL, 1))
    # A W with a bad payload gets e03, which goes first.
    e.send(pkt("W", "FFFFFFE3" "0001" "0000000G"))
    e.expect("e03 before e04", pkt("e", "5703"))
    # Running: e02 goes first where it applies, and e04 otherwise.
    e.send(write(0, count) + write(CONTROL, [0x8]))
    e.expect("start count", ok(0, len(count)) + ok(CONTROL, 1))
    e.send(write(0xFFFFFFE3, [9]) + write(0xFFFFFFE0, [9]) + write(0xFFFFFFDF, [0, 0])
           + write(0xFFFFFFCF, [0] * 18))
    e.expect("running", pkt("e", "5704") * 3 + pkt("e", "5702"))
    # DEBUG.md §8, byte for byte, from a pause of a program spinning at 0.
    e.send(write(CONTROL, [0x9]) + write(0, at20) + write(CONTROL, [0x18]))
    e.expect("start at20 paused", ok(CONTROL, 1) + ok(0, len(at20)) + ok(CONTROL, 1) + PAUSED)
    e.send(b"\xffWFFFFFFE3000100000005#B9")
    e.expect("set R3", b"\xffkFFFFFFE30001#48")
    e.send(b"\xffWFFFFFFEF000100000020#C9")
    e.expect("set R15", b"\xffkFFFFFFEF0001#5B")
    e.send(b"\xffWFFFFFFF0000100000008#BA")
    e.expect("go on", b"\xffkFFFFFFF00001#46")
    e.send(b"\xffWFFFFFFE3000100000005#B9")
    e.expect("too late", b"\xffe5704#35")
    e.send(write(CONTROL, [0x18]))
    e.expect("pause at20", ok(CONTROL, 1) + PAUSED)
    e.send(read(0xFFFFFFE3, 2) + read(0xFFFFFFEF, 1))
    e.expect("ran from 0x20", answer(0xFFFFFFE3, [5, 5]) + answer(0xFFFFFFEF, [0x21]))
    e.stop()


def test_old_host(stop: List[int], echo: List[int]) -> None:
    """A host of version 1 works with this system (§9). It checks the
    major and the minor, knows bits 0 to 3 of the control register, writes
    back what it reads with 0 for the other bits, and gets no notice but h."""
    e = Emu()
    hello = e.take(len(HELLO))
    expect("b", hello[:2], b"\xffb")
    version = int(hello[2:4], 16)
    expect("major 0, minor 1 or more", bytes([version >> 4, version & 0xF >= 1]), b"\x00\x01")

    def control(set_bits: int, clear_bits: int) -> None:
        value = (word(e, CONTROL) & 0xF | set_bits) & ~clear_bits
        e.send(write(CONTROL, [value]))
        e.expect(f"write {value:X}", ok(CONTROL, 1))

    # Load, start, halt, and again, each load after a clear and a hold.
    for prog in (stop, stop):
        control(0x5, 0)
        e.send(write(0, prog))
        e.expect("load", ok(0, len(prog)))
        control(0, 0x5)
        e.expect("halt", b"\xffh01#C9")
        e.send(read(CONTROL, 2))
        e.expect("halted", answer(CONTROL, [0xA, 1]))
    # The registers it does not know read 0 but for the version, which reads
    # 8 with its high bits 0.
    e.send(read(0xFFFFFFF2, 1) + read(0xFFFFFFF7, 1))
    e.expect("version and 0xFFFFFFF7", answer(0xFFFFFFF2, [8]) + answer(0xFFFFFFF7, [0]))
    # A program that runs until the host holds it.
    control(0x5, 0)
    e.send(write(0, echo))
    e.expect("load echo", ok(0, len(echo)))
    control(0, 0x5)
    e.send(b"Hi")
    e.expect("echo", b"Hi")
    # Version 6 changes one thing it could see: a write of R0-R15 while
    # the program runs gets e04, where version 5 answered k.
    e.send(write(0xFFFFFFE3, [5]))
    e.expect("register write while running", pkt("e", "5704"))
    control(0x1, 0)
    e.send(read(CONTROL, 2))
    e.expect("held", answer(CONTROL, [0x9, 0]))
    expect("no other notice", e.take(1, timeout=0.5), b"")
    e.stop()


def test_net(spin: List[int]) -> None:
    """The network station (DEVICES.md §6): NET_STATUS gives the port, and
    bit 31 while a host is connected. A start and a clear keep the
    addresses, and so does a new connection."""
    net_ip, net_status = 0xFFFFFFB0, 0xFFFFFFB6
    e = Emu()
    e.take(len(HELLO))
    expect("NET_STATUS", bytes([word(e, net_status) == 0x80000000 | e.port]), b"\x01")
    e.send(write(net_ip, [0xC0A80141]))
    e.expect("NET_IP written", ok(net_ip, 1))
    e.send(write(0, spin) + write(CONTROL, [0x8]))
    e.expect("load and start", ok(0, len(spin)) + ok(CONTROL, 1))
    e.send(write(CONTROL, [0xD]) + write(CONTROL, [0x8]) + write(CONTROL, [0x9]))
    e.expect("clear, start, and hold", ok(CONTROL, 1) * 3)
    e.send(read(net_ip, 3))
    e.expect("kept by a start and a clear", answer(net_ip, [0xC0A80141, 0x024E, 0x49434500]))
    # A half-close first, so that the emulator accepts the next host.
    e.sock.shutdown(socket.SHUT_WR)
    expect("quiet after the half-close", e.take(1, timeout=0.3), b"")
    e.sock.close()
    e.sock = e.connect()
    e.buf = b""
    e.take(len(HELLO))
    expect("NET_STATUS again", bytes([word(e, net_status) == 0x80000000 | e.port]), b"\x01")
    e.send(read(net_ip, 1))
    e.expect("kept by a new connection", answer(net_ip, [0xC0A80141]))
    e.stop()


def test_fpu() -> None:
    """The FPU's words over the link (DEVICES.md §11): a write pushes, as
    the processor's does, and a read of the eight words changes nothing,
    so two dumps agree. With --no-fpu they are ordinary memory."""
    fpu = 0xFFFFFF88
    e = Emu()
    e.take(len(HELLO))
    e.send(write(fpu + 3, [7]) + write(fpu + 3, [2]))
    e.expect("pushes through X_W", ok(fpu + 3, 1) * 2)
    # X = 2.0 over 7.0: X_LO, X_HI, X_S, and X_W of 2.0, CMD 0, STATUS
    # with depth 2 and X whole and fitting, REL 1 as 7 > 2, and 0.
    words = [0, 0x40000000, 0x40000000, 2, 0, 0x00300002, 1, 0]
    for n in ("first", "second"):
        e.send(read(fpu, 8))
        e.expect(f"the FPU's words, {n} dump", answer(fpu, words))
    e.stop()
    e = Emu(["--no-fpu"])
    e.take(len(HELLO))
    e.send(write(fpu + 3, [7]))
    e.expect("--no-fpu: a write", ok(fpu + 3, 1))
    e.send(read(fpu, 8))
    e.expect("--no-fpu: memory", answer(fpu, [0, 0, 0, 7, 0, 0, 0, 0]))
    e.stop()


def test_start_reset() -> None:
    """A start gives the console's receive interrupt and the FPU their
    reset values (§6, DEVICES.md §1.9, §11): v and the enable at 0, and
    an empty stack with no flags."""
    console_irq, fpu = 0xFFFFFF02, 0xFFFFFF88
    e = Emu()
    e.take(len(HELLO))
    # The enable with v = 5, a push of 7.0, and the invalid flag.
    e.send(write(console_irq, [0x105]) + write(fpu + 3, [7]) + write(fpu + 5, [0x100]))
    e.expect("writes while held", ok(console_irq, 1) + ok(fpu + 3, 1) + ok(fpu + 5, 1))
    # STATUS with depth 1, invalid, and X whole and fitting.
    e.send(read(console_irq, 1) + read(fpu + 5, 1))
    e.expect("before the start", answer(console_irq, [0x105]) + answer(fpu + 5, [0x00300101]))
    e.send(write(CONTROL, [0x18]))
    e.expect("start paused", ok(CONTROL, 1) + PAUSED)
    # An empty stack reads as the canonical NaN: X_LO, X_HI, X_S, and X_W
    # of it, CMD 0, STATUS with depth 0, no flag, and X a NaN, REL 2 as
    # for a NaN, and 0.
    e.send(read(console_irq, 1) + read(fpu, 8))
    e.expect("after the start", answer(console_irq, [0]) +
             answer(fpu, [0, 0x7FF80000, 0x7FC00000, 0, 0, 0x00080000, 2, 0]))
    e.stop()


def test_address() -> None:
    """--link ADDR:PORT serves on ADDR only. All of 127.0.0.0/8 is
    loopback on Linux, so 127.0.0.2 is an address other than the
    default. An IPv6 address goes in brackets, and 0.0.0.0 serves every
    address of the computer, 127.0.0.1 among them."""
    e = Emu(addr="127.0.0.2")
    expect("b on connect", e.take(len(HELLO)), HELLO)
    e.send(read(CONTROL, 1))
    e.expect("control held", answer(CONTROL, [0x9]))
    try:
        socket.create_connection(("127.0.0.1", e.port), timeout=5).close()
        failures.append("127.0.0.2: a connect to 127.0.0.1 was accepted")
    except ConnectionRefusedError:
        pass
    status, out, _ = e.stop()
    expect("exit status", bytes([status]), b"\x00")
    for addr, host in (("[::1]", "::1"), ("0.0.0.0", "127.0.0.1")):
        e = Emu(addr=addr, host=host)
        expect(f"b on connect to {addr}", e.take(len(HELLO)), HELLO)
        e.send(read(CONTROL, 1))
        e.expect(f"control held on {addr}", answer(CONTROL, [0x9]))
        status, out, _ = e.stop()
        expect(f"exit status of {addr}", bytes([status]), b"\x00")


def test_not_at_0(tmp: str) -> None:
    """A program with nothing at 0, which niceemu refuses to run on its own,
    is loaded with --link, as the processor starts held."""
    path = os.path.join(tmp, "at8000.bin")
    with open(path, "w") as f:
        f.write("00008000 12345678\n")
    e = Emu([path])
    expect("b on connect", e.take(len(HELLO)), HELLO)
    e.send(read(0x8000, 1))
    e.expect("word at 0x8000", answer(0x8000, [0x12345678]))
    status, _, _ = e.stop()
    expect("exit status", bytes([status]), b"\x00")


def test_usage() -> None:
    proc = subprocess.run([NICEEMU, "--link", "0", "--input", "x"], capture_output=True, text=True)
    want = "niceemu: --input cannot be given with --link\n"
    if proc.returncode != 1 or proc.stderr != want:
        failures.append(f"--input: status {proc.returncode}, stderr {proc.stderr!r}")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        echo = assemble(tmp, "echo", ECHO)
        echo_on = assemble(tmp, "echo_on", ECHO_ON)
        spin = assemble(tmp, "spin", SPIN)
        count = assemble(tmp, "count", COUNT)
        one = assemble(tmp, "one", ONE)
        stop = assemble(tmp, "stop", STOP)
        twice = assemble(tmp, "twice", TWICE)
        at10 = assemble(tmp, "at10", AT10)
        load = assemble(tmp, "load", LOAD)
        skip = assemble(tmp, "skip", SKIP)
        regs = assemble(tmp, "regs", REGS)
        hidden = assemble(tmp, "hidden", HIDDEN)
        waiter = assemble(tmp, "waiter", WAITER)
        skipper = assemble(tmp, "skipper", TIME_SKIPPER)
        nmi = assemble(tmp, "nmi", NMI_PROG)
        wait_nmi = assemble(tmp, "wait_nmi", WAIT_NMI)
        watch = assemble(tmp, "watch", WATCH)
        write200 = assemble(tmp, "write200", WRITE200)
        at20 = assemble(tmp, "at20", AT20)
        reserved = assemble(tmp, "reserved", RESERVED)
        int_in_isr = assemble(tmp, "int_in_isr", INT_IN_ISR)
        rti = assemble(tmp, "rti", RTI_OUTSIDE)
        with open(os.path.join(HERE, "irq.nasm")) as src:
            irq = assemble(tmp, "irq", src.read())
        irq_bin = os.path.join(tmp, "irq.bin")
        tests: List[Callable[[], None]] = [
            test_example, test_errors, lambda: test_run(echo), lambda: test_reconnect(echo_on),
            lambda: test_overflow(spin), lambda: test_flood(echo, spin),
            lambda: test_step_limit(spin), lambda: test_halts(reserved, int_in_isr, rti, spin),
            lambda: test_pause(count, echo), lambda: test_clock(spin),
            lambda: test_step(count, one, stop, echo, twice, irq, irq_bin),
            lambda: test_break(at10, load, count, skip, stop, irq),
            lambda: test_watch(watch, write200, irq),
            lambda: test_write_regs(regs, at20, count), lambda: test_wait(waiter),
            lambda: test_time_skip(skipper),
            lambda: test_hidden(hidden, count), lambda: test_nmi(nmi, wait_nmi),
            lambda: test_old_host(stop, echo), lambda: test_net(spin), test_fpu, test_start_reset,
            test_address, test_usage, lambda: test_not_at_0(tmp),
        ]
        for t in tests:
            t()
    for f in failures:
        print("FAIL " + f)
    print(f"PASS link ({len(tests)} tests)" if not failures else f"FAIL link ({len(failures)} checks)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
