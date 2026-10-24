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
CONSOLE .EQU    0xFFFFFF00
loop    MOVE    R1, @CONSOLE
        AND[M]  R0, R1, 0x200
        ?!Z HALT
        MOVE    @CONSOLE, R1
        ADD     R2, R2, 1
        MOVE    R15, loop
"""

# Never halts, and never reads the console.
SPIN = """
loop    MOVE    R15, loop
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
HELLO = b"\xffb01#C3"


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
    """A niceemu --link 0, and a host connected to it."""

    def __init__(self, args: List[str] = []) -> None:
        self.proc = subprocess.Popen([NICEEMU, "--link", "0"] + args, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert self.proc.stderr is not None
        line = self.proc.stderr.readline().decode()
        if not line.startswith("link: port "):
            raise RuntimeError(f"no port line, got {line!r}")
        self.port = int(line.split()[2])
        self.sock = self.connect()
        self.buf = b""

    def connect(self) -> socket.socket:
        return socket.create_connection(("127.0.0.1", self.port), timeout=5)

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
    e.expect("F1-F4", answer(0xFFFFFFF1, [0, 1, 2048, 0]))
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
    e.expect("read counter", answer(0xFFFFFF01, [0]) + answer(0xFFFFFFF2, [1]))
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
    # the program left: R1 = 0x200, R2 = 3 bytes echoed.
    e.sock = e.connect()
    e.buf = b""
    expect("b again", e.take(len(HELLO)), HELLO)
    e.send(read(0xFFFFFFE1, 2) + read(CONTROL, 2))
    e.expect("after halt",
             answer(0xFFFFFFE1, [0x200, 3]) + answer(CONTROL, [0xA, 1]))
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
    want = b"Halted (HALT) after 21 steps, PC=00000005\n"
    if want not in err:
        failures.append(f"stderr: {want!r} not in {err!r}")


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
    _, _, err = e.stop()
    want = b"Stopped at the step limit after 10 steps, PC=00000000\n"
    if want not in err:
        failures.append(f"stderr: {want!r} not in {err!r}")


def test_usage() -> None:
    proc = subprocess.run([NICEEMU, "--link", "0", "--input", "x"], capture_output=True, text=True)
    want = "niceemu: --input cannot be given with --link\n"
    if proc.returncode != 1 or proc.stderr != want:
        failures.append(f"--input: status {proc.returncode}, stderr {proc.stderr!r}")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        echo = assemble(tmp, "echo", ECHO)
        spin = assemble(tmp, "spin", SPIN)
    tests: List[Callable[[], None]] = [
        test_example, test_errors, lambda: test_run(echo), lambda: test_overflow(spin),
        lambda: test_step_limit(spin), test_usage,
    ]
    for t in tests:
        t()
    for f in failures:
        print("FAIL " + f)
    print(f"PASS link ({len(tests)} tests)" if not failures else f"FAIL link ({len(failures)} checks)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
