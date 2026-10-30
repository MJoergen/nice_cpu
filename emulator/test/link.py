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
import time
from typing import Callable, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
NICEASM = os.path.join(HERE, "..", "..", "assembler", "niceasm.py")
NICEEMU = os.path.join(HERE, "..", "zig-out", "bin", "niceemu")

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
# monitor does, so it never halts. R2 counts the bytes echoed.
ECHO_ON = """
CONSOLE         .EQU    0xFFFFFF00
loop            MOVE    R1, @CONSOLE
                AND[M]  R0, R1, 0x100
        ?Z      MOVE    R15, loop       ; the end, 0x200: read again
                MOVE    @CONSOLE, R1
                ADD     R2, R2, 1
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
HELLO = b"\xffb05#C7"
PAUSED = b"\xffp#70"
CYCLE_LO = 0xFFFFFF40


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
    """A niceemu --link 0, or on `addr`, and a host connected to it."""

    def __init__(self, args: List[str] = [], addr: str = "127.0.0.1") -> None:
        self.addr = addr
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
    e.expect("F1-F4", answer(0xFFFFFFF1, [0, 5, 2048, 0]))
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
    e.expect("read counter", answer(0xFFFFFF01, [0]) + answer(0xFFFFFFF2, [5]))
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
    a running program (§6)."""
    for name, prog, reason, note in (
        ("reserved", reserved, 2, b"\xffh02#CA"),
        ("INT in a routine", int_in_isr, 3, b"\xffh03#CB"),
        ("RTI outside", rti, 4, b"\xffh04#CC"),
    ):
        e = Emu()
        e.take(len(HELLO))
        e.send(write(0, prog) + write(CONTROL, [0x8]))
        e.expect(name + " start", ok(0, len(prog)) + ok(CONTROL, 1))
        e.expect(name + " notice", note)
        e.send(read(CONTROL, 2))
        e.expect(name + " reason", answer(CONTROL, [0xA, reason]))
        e.send(write(CONTROL, [0x5]) + read(CONTROL, 2))
        e.expect(name + " cleared", ok(CONTROL, 1) + answer(CONTROL, [0x9, 0]))
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
    # R3 is 0x161 + 0x162 (SYSTEM.md §1).
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
    time.sleep(0.3)
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
    # 5 with its high bits 0.
    e.send(read(0xFFFFFFF2, 1) + read(0xFFFFFFF7, 1))
    e.expect("version and 0xFFFFFFF7", answer(0xFFFFFFF2, [5]) + answer(0xFFFFFFF7, [0]))
    # A program that runs until the host holds it.
    control(0x5, 0)
    e.send(write(0, echo))
    e.expect("load echo", ok(0, len(echo)))
    control(0, 0x5)
    e.send(b"Hi")
    e.expect("echo", b"Hi")
    control(0x1, 0)
    e.send(read(CONTROL, 2))
    e.expect("held", answer(CONTROL, [0x9, 0]))
    expect("no other notice", e.take(1, timeout=0.5), b"")
    e.stop()


def test_address() -> None:
    """--link ADDR:PORT serves on ADDR only. All of 127.0.0.0/8 is
    loopback on Linux, so 127.0.0.2 is an address other than the
    default."""
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
        reserved = assemble(tmp, "reserved", RESERVED)
        int_in_isr = assemble(tmp, "int_in_isr", INT_IN_ISR)
        rti = assemble(tmp, "rti", RTI_OUTSIDE)
        with open(os.path.join(HERE, "irq.nasm")) as src:
            irq = assemble(tmp, "irq", src.read())
        irq_bin = os.path.join(tmp, "irq.bin")
        tests: List[Callable[[], None]] = [
            test_example, test_errors, lambda: test_run(echo), lambda: test_reconnect(echo_on),
            lambda: test_overflow(spin),
            lambda: test_step_limit(spin), lambda: test_halts(reserved, int_in_isr, rti, spin),
            lambda: test_pause(count, echo),
            lambda: test_step(count, one, stop, echo, twice, irq, irq_bin),
            lambda: test_break(at10, load, count, skip, stop, irq),
            lambda: test_old_host(stop, echo), test_address, test_usage,
        ]
        for t in tests:
            t()
    for f in failures:
        print("FAIL " + f)
    print(f"PASS link ({len(tests)} tests)" if not failures else f"FAIL link ({len(failures)} checks)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
