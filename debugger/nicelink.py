#!/usr/bin/env python3
"""The debug link of doc/DEBUG.md, for a host tool.

A Link talks to a system over a transport: niceemu --link over TCP, on
127.0.0.1 or on another computer (Tcp), or a system's UART (Serial). A
board adds transports of its own by subclassing Transport or Tcp. The
Link splits what arrives into console bytes, with ESC ESC as 0xFF, and
packets, which it checks. A packet is an answer to a request, or a
notice, which the system sends on its own (DEBUG.md §4): b at reset, o
when an input byte is lost, p at a pause, h at a halt, x at a
breakpoint, and w after a watchpoint's hit. The answers go to the
request that waits for them, and the notices are counted, b, o, and p,
or kept, h with its reason, x with its breakpoint's number, and w with
its watchpoint's. An x and a w are pauses too, so each counts as one. A
packet with a bad checksum is dropped, as DEBUG.md §5 says.

A request waits ANSWER_WAIT for the first byte of its answer, or what
the transport's answer_wait() gives, and as long as the bytes of a
packet keep coming. Without an answer, a read or a write of memory is
sent again, up to TRIES times, as both may be repeated. A write of the
control register is not sent again blindly (DEBUG.md §3): the register
is read back, and the write is sent again only if it did not take
effect. A write that holds and clears is sent again, as a second clear
of a held processor changes nothing. The words of a read or a write go
in packets of at most MAX_WORDS.

Console bytes to the program are paced by the free-space register, so
that none is lost in its input buffer, and a buffer that the program
does not read for SEND_WAIT is an error, so a send cannot hang. The end
of the input is a break on the UART, and a half-close of the TCP
connection (DEBUG.md §7).

Only the Python standard library is used, so this runs on Linux and
macOS. nicedbg.py is the debugger on the link, and nicebin.py reads the
files that it loads.
"""

from __future__ import annotations

import argparse
import fcntl
import os
import select
import socket
import sys
import termios
import time
from collections import deque
from typing import Callable, NoReturn

ESC = 0xFF

# The debug registers of DEBUG.md §6: the hidden state (version 7),
# R0-R15, and the rest
SAVED_PC = 0xFFFFFFD0
SAVED_SR = 0xFFFFFFD1
# The watchpoints (version 7): the enable bits, two for each, of the
# reads and the writes, their number, the address of a hit, and the
# address of watchpoint 0, then 1 to 3
WCH_EN = 0xFFFFFFD4
WCH_COUNT = 0xFFFFFFD5
WCH_PC = 0xFFFFFFD6
WCH_ADDR = 0xFFFFFFD8
# The kinds of access that a watchpoint stops at, its two enable bits
WCH_READ = 1
WCH_WRITE = 2
REGS = 0xFFFFFFE0
CONTROL = 0xFFFFFFF0
HALT_REASON = 0xFFFFFFF1
VERSION = 0xFFFFFFF2
# The major of the version that the tools know, bits 7 to 4 of it
# (DEBUG.md §9). A new minor, bits 3 to 0, keeps them working.
MAJOR = 0
FREE = 0xFFFFFFF3
# The breakpoints (version 4): the enable bits, their number, the stop
# register, and the address of breakpoint 0, then 1 to 7
BRK_EN = 0xFFFFFFF4
BRK_COUNT = 0xFFFFFFF5
STOP = 0xFFFFFFF6
BRK_ADDR = 0xFFFFFFF8

# Control bits: hold the processor in reset, halted (read only), clear the
# memory first, hide the ROM, so that the RAM is at 0, pause (version 2),
# step a paused processor (version 3), and, read only and of version 7,
# waits for an interrupt, in an interrupt routine, after an RTI, an NMI
# pending, and an IRQ pending
HOLD = 1
HALTED = 2
CLEAR = 4
RAM = 8
PAUSE = 16
STEP = 32
WAITING = 64
IN_SERVICE = 0x80
AFTER_RTI = 0x100
NMI_PENDING = 0x200
IRQ_PENDING = 0x400

# The halt reasons of DEBUG.md §6
REASONS = {
    1: "HALT",
    2: "reserved control instruction",
    3: "INT inside an interrupt routine",
    4: "RTI outside an interrupt routine",
    5: "step limit",
}

# Longer than the 100 ms of DEBUG.md §5, for the latency of a USB serial
# adapter and of the operating system
ANSWER_WAIT = 0.3
# How long a sender waits while the program's input buffer is full, before
# it reads the free space again. Well below the 10 ms in which the demo
# takes an ESC with no byte after it as a key of its own (demo/demo.nasm,
# T_ESC), so that a gap here does not cut an escape sequence in two.
FULL_WAIT = 0.001
# How long a paced send waits for room in the program's input buffer
# before it gives up: a program that reads at all reads sooner
SEND_WAIT = 2.0
# How long a break holds the UART's line low. A board takes a frame of
# zeros for one, 43 us at 230400 baud; this leaves room for the USB serial
# chip. TIOCSBRK and TIOCCBRK set and clear it: Linux's asm-generic/ioctls.h
# has 0x5427 and 0x5428, and macOS's sys/ttycom.h, as the BSDs, 0x2000747B
# and 0x2000747A; Python's termios does not have them.
BREAK_TIME = 0.02
TIOCSBRK = 0x5427 if sys.platform.startswith("linux") else 0x2000747B
TIOCCBRK = 0x5428 if sys.platform.startswith("linux") else 0x2000747A
# The UART's baud rate unless --baud gives another: the highest that the
# termios of both Linux and macOS have a constant for, as macOS has none
# above B230400
DEFAULT_BAUD = 230400
# How many times a request without an answer is sent, the first time
# included, before the link gives up
TRIES = 3
# The most words in one R or W packet, about 2K bytes of payload. The
# count is a 4-digit field (DEBUG.md §2), so the protocol allows more.
MAX_WORDS = 256
# How long open_link() waits for niceemu's b notice: long enough for a
# busy computer, short enough to report a wrong port
BOOT_WAIT = 2.0

# The error codes of DEBUG.md §3
ERRORS = {
    1: "not a request of this version",
    2: "the program runs, and the request reaches a word that is not a "
       "debug register",
    3: "a bad payload",
    4: "a write of R0-R15, and the processor is not paused",
}


class LinkError(Exception):
    """A request that the link could not carry out."""


def fail(message: str) -> NoReturn:
    """Exits with the message, after the name of the running script."""
    sys.exit(f"{os.path.basename(sys.argv[0])}: {message}")


def checksum(text: str) -> str:
    """The checksum of DEBUG.md §2: the sum of the bytes, mod 256, in two
    uppercase hex digits."""
    return f"{sum(text.encode('ascii')) & 0xFF:02X}"


def packet(tag: str, payload: str) -> bytes:
    """A packet: ESC, the tag, the payload, '#', and the checksum."""
    return bytes([ESC]) + f"{tag}{payload}#{checksum(tag + payload)}".encode(
        "ascii")


class Transport:
    """A byte stream to the system. board is whether the system is a
    board's RTL, simulated or not, and not the emulator."""

    board = False

    def answer_wait(self, sent: int) -> float:
        """How long a request of sent bytes waits for its answer to start."""
        return ANSWER_WAIT

    def fileno(self) -> int:
        raise NotImplementedError

    def write(self, data: bytes) -> None:
        raise NotImplementedError

    def read(self) -> bytes:
        """What has arrived, after select says something has."""
        raise NotImplementedError

    def end_input(self, wait: Callable[[float], None]) -> None:
        """Ends the program's input. wait(t) reads what arrives for t
        seconds, so that a transport that has to wait loses no output."""
        raise NotImplementedError

    def close(self) -> None:
        raise NotImplementedError


class Serial(Transport):
    """A system's UART, raw 8-N-1 with no flow control (DEBUG.md §7.1).
    tcdrain() returns when the driver has handed the bytes to the USB
    serial chip, which may still be sending them, and a break sent then
    cuts the last of them off. So this keeps the time at which the bytes
    written are out on the line, at 10 bits a byte, and end_input() waits
    for it.

    A board sends at the full rate with no flow control, and the kernel's
    buffer of a tty holds about 4 KB, 180 ms at 230400 baud. So every wait
    of end_input() reads on, and the break is set and cleared with ioctls
    around such a wait: tcsendbreak() blocks for 0.25 s or more, and the
    output of that time was lost, an h notice too."""

    board = True

    def __init__(self, name: str, baud: int) -> None:
        try:
            self.fd = os.open(name, os.O_RDWR | os.O_NOCTTY)
        except OSError as e:
            fail(f"cannot open {name}: {e.strerror}")
        try:
            termios.tcgetattr(self.fd)
        except termios.error:
            os.close(self.fd)
            fail(f"{name} is not a serial device")
        self.sent_by = time.monotonic()
        self.set_baud(baud)
        termios.tcflush(self.fd, termios.TCIOFLUSH)

    def set_baud(self, baud: int) -> None:
        """Raw 8-N-1 at the baud rate."""
        speed = getattr(termios, f"B{baud}", None)
        if speed is None:
            fail(f"{baud} is not a baud rate of the serial device")
        attr = termios.tcgetattr(self.fd)
        attr[0] = 0                                             # iflag
        attr[1] = 0                                             # oflag
        attr[2] = termios.CS8 | termios.CREAD | termios.CLOCAL  # cflag
        attr[3] = 0                                             # lflag
        attr[4] = speed                                         # ispeed
        attr[5] = speed                                         # ospeed
        attr[6][termios.VMIN] = 0
        attr[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSADRAIN, attr)
        self.byte_time = 10 / baud

    def fileno(self) -> int:
        return self.fd

    def write(self, data: bytes) -> None:
        self.sent_by = (max(self.sent_by, time.monotonic()) +
                        len(data) * self.byte_time)
        while data:
            n = os.write(self.fd, data)
            data = data[n:]

    def read(self) -> bytes:
        return os.read(self.fd, 4096)

    def end_input(self, wait: Callable[[float], None]) -> None:
        # A break: the line low for BREAK_TIME, far longer than a frame,
        # after the bytes before it, with 20 ms more for the latency of USB
        termios.tcdrain(self.fd)
        wait(max(self.sent_by - time.monotonic(), 0) + 0.02)
        try:
            fcntl.ioctl(self.fd, TIOCSBRK)
        except OSError:
            # A system without the ioctl: tcsendbreak(), which blocks for
            # 0.25 s or more, so the output of that time is lost
            termios.tcsendbreak(self.fd, 0)
            return
        try:
            wait(BREAK_TIME)
        finally:
            fcntl.ioctl(self.fd, TIOCCBRK)

    def close(self) -> None:
        os.close(self.fd)


class Tcp(Transport):
    """niceemu --link, on a port of 127.0.0.1 or of another computer
    (DEBUG.md §7.2). A half-close ends the program's input, and a host
    that has half-closed sends no more. So the next request after
    end_input() connects again, which counts the first connection as
    closed. niceemu refuses the new one, closing it at once with nothing
    sent, until it has seen the half-close, so it is tried again until
    niceemu sends its b notice. What niceemu sent on the first connection
    comes before what it sends on the second, so the first is read to its
    end first. A board's transport over TCP subclasses this, with its own
    peer, hint(), _connect(), and _reconnect()."""

    # Who serves the port, for the messages
    peer = "niceemu"

    def __init__(self, port: int, host: str = "127.0.0.1") -> None:
        self.host = host
        self.port = port
        self.sock: socket.socket | None = self._connect()
        # The half-closed connection, until niceemu closes it
        self.old: socket.socket | None = None

    def _connect(self) -> socket.socket:
        try:
            # Wait at most 5 s for the connection
            sock = socket.create_connection((self.host, self.port), 5)
        except OSError as e:
            fail(f"cannot connect to {self.host}:{self.port}: "
                 f"{e.strerror or e}; {self.hint(e)}")
        sock.setblocking(False)
        return sock

    def hint(self, e: OSError) -> str:
        """What to check when the connection fails with e."""
        return (f"is niceemu --link {self.port} running?"
                if self.host in ("127.0.0.1", "localhost", "::1") else
                f"is niceemu --link ADDR:{self.port} running on "
                f"{self.host}, with an ADDR that it can reach?")

    def _reconnect(self) -> socket.socket:
        """A new connection that niceemu has taken: one that it has sent
        something on, its b notice, which stays to be read."""
        # Give up after 5 s; niceemu takes the new connection as soon as it
        # has seen the half-close
        end = time.monotonic() + 5
        while time.monotonic() < end:
            sock = self._connect()
            ready, _, _ = select.select([sock], [], [], 1.0)
            try:
                taken = bool(ready) and sock.recv(1, socket.MSG_PEEK) != b""
            except OSError:
                taken = False
            if taken:
                return sock
            sock.close()
            time.sleep(0.02)   # a pause between tries
        raise LinkError(f"{self.peer} does not take a new connection after "
                        f"the end of the input")

    def fileno(self) -> int:
        sock = self.old or self.sock
        assert sock is not None
        return sock.fileno()

    def write(self, data: bytes) -> None:
        if self.sock is None:
            self.sock = self._reconnect()
        self.sock.setblocking(True)
        try:
            self.sock.sendall(data)
        except OSError as e:
            raise LinkError(f"the connection failed: {e.strerror}")
        finally:
            self.sock.setblocking(False)

    def read(self) -> bytes:
        sock = self.old or self.sock
        assert sock is not None
        try:
            data = sock.recv(4096)
        except BlockingIOError:
            return b""
        except OSError as e:
            raise LinkError(f"the connection failed: {e.strerror}")
        if not data:
            if self.old is not None and self.sock is not None:
                # The first connection has ended; the second takes over.
                self.old.close()
                self.old = None
                return b""
            raise LinkError(f"{self.peer} closed the connection; another "
                            f"host may be connected")
        return data

    def end_input(self, wait: Callable[[float], None]) -> None:
        if self.sock is None:
            # The input has ended, and no request has connected again
            # since, so there is nothing to half-close: a second end
            # changes nothing, as a second break on a UART does.
            return
        self.sock.shutdown(socket.SHUT_WR)
        self.old = self.sock
        self.sock = None

    def close(self) -> None:
        for sock in (self.old, self.sock):
            if sock is not None:
                sock.close()


class Link:
    """The debug link over a transport."""

    def __init__(self, transport: Transport) -> None:
        self.transport = transport
        # What arrived and is not yet taken
        self.console = bytearray()
        self.halts: list[int] = []
        self.boots = 0
        self.overflows = 0
        self.pauses = 0
        self.breaks: list[int] = []
        self.watches: list[int] = []
        self.bad = 0
        self._answers: deque[tuple[str, str]] = deque()
        # The state of the receiver: 0 console bytes, 1 after ESC, 2 in a
        # packet, 3 and 4 the checksum's digits
        self._state = 0
        self._packet = bytearray()
        self.input_ended = False

    @property
    def board(self) -> bool:
        """Whether this is a board, or its simulation, not the
        emulator."""
        return self.transport.board

    def fileno(self) -> int:
        return self.transport.fileno()

    def close(self) -> None:
        self.transport.close()

    # The receiver

    def _feed(self, data: bytes) -> None:
        for b in data:
            if self._state == 0:
                if b == ESC:
                    self._state = 1
                else:
                    self.console.append(b)
            elif self._state == 1:
                if b == ESC:
                    self.console.append(ESC)
                    self._state = 0
                elif chr(b).isascii() and chr(b).isalpha():
                    self._packet = bytearray([b])
                    self._state = 2
                else:
                    # Dropped with the ESC (DEBUG.md §5)
                    self._state = 0
            elif b == ESC:
                # A packet ended early is dropped, and ESC starts anew.
                self.bad += 1
                self._state = 1
            else:
                self._packet.append(b)
                if self._state == 2 and b == ord("#"):
                    self._state = 3
                elif self._state == 3:
                    self._state = 4
                elif self._state == 4:
                    self._state = 0
                    self._dispatch(self._packet.decode("ascii", "replace"))

    def _dispatch(self, text: str) -> None:
        body, _, cc = text.rpartition("#")
        if cc.upper() != checksum(body):
            self.bad += 1
            return
        tag, payload = body[0], body[1:]
        try:
            if tag == "h":
                self.halts.append(int(payload, 16))
            elif tag == "x":
                self.breaks.append(int(payload, 16))
                self.pauses += 1
            elif tag == "w":
                self.watches.append(int(payload, 16))
                self.pauses += 1
        except ValueError:
            # A notice whose payload is not hex
            self.bad += 1
            return
        if tag == "b":
            self.boots += 1
        elif tag == "o":
            self.overflows += 1
        elif tag == "p":
            self.pauses += 1
        elif tag not in "hxw":
            # An answer, or a notice of a newer version, which _request
            # skips, as its tag matches no request (DEBUG.md §9).
            self._answers.append((tag, payload.upper()))

    def in_packet(self) -> bool:
        return self._state >= 2

    def poll(self, timeout: float = 0.0) -> bool:
        """Takes what arrives within timeout seconds. Returns whether
        anything arrived."""
        ready, _, _ = select.select([self.transport.fileno()], [], [],
                                    max(timeout, 0.0))
        if not ready:
            return False
        data = self.transport.read()
        self._feed(data)
        return bool(data)

    def take_console(self) -> bytes:
        """The console bytes that have arrived."""
        data = bytes(self.console)
        self.console.clear()
        return data

    def take_answers(self) -> list[tuple[str, str]]:
        """The answers that have arrived with no request waiting for them,
        as (tag, payload), for a test that sends its own packets."""
        answers = list(self._answers)
        self._answers.clear()
        return answers

    # Requests

    def _request(self, tag: str, payload: str, match: str) -> str:
        """Sends a request once, and returns the payload of its answer, or
        "" when none came. An answer whose tag and A and N do not match
        is a late one, and is skipped. An error answer raises LinkError."""
        self._answers.clear()
        data = packet(tag, payload)
        self.transport.write(data)
        wait = self.transport.answer_wait(len(data))
        end = time.monotonic() + wait
        while True:
            while self._answers:
                t, p = self._answers.popleft()
                if t == "e" and p[:2] == f"{ord(tag):02X}":
                    try:
                        code = int(p[2:4], 16)
                    except ValueError:
                        code = 0
                    raise LinkError(f"{tag} {payload[:12]} answered error "
                                    f"{code:02X}: "
                                    f"{ERRORS.get(code, 'unknown')}")
                if t == match[0] and p.startswith(match[1:]):
                    return p
            now = time.monotonic()
            if now >= end:
                return ""
            if self.poll(end - now) and self.in_packet():
                # The bytes of a packet keep coming.
                end = time.monotonic() + wait

    def _read_once(self, addr: int, n: int) -> list[int] | None:
        an = f"{addr:08X}{n:04X}"
        p = self._request("R", an, "r" + an)
        if not p or len(p) != 12 + 8 * n:
            return None
        try:
            return [int(p[12 + 8 * i:20 + 8 * i], 16) for i in range(n)]
        except ValueError:
            return None

    def read(self, addr: int, n: int = 1) -> list[int]:
        """Reads n words from addr."""
        words: list[int] = []
        while n > 0:
            part = min(n, MAX_WORDS)
            for _ in range(TRIES):
                got = self._read_once(addr, part)
                if got is not None:
                    break
            else:
                raise LinkError(f"no answer to R {addr:08X} {part:04X}")
            words += got
            addr = (addr + part) & 0xFFFFFFFF
            n -= part
        return words

    def read_word(self, addr: int) -> int:
        return self.read(addr)[0]

    def write(self, addr: int, words: list[int]) -> None:
        """Writes the words from addr. Not for the control register, which
        control() writes."""
        while words:
            part = words[:MAX_WORDS]
            an = f"{addr:08X}{len(part):04X}"
            payload = an + "".join(f"{w & 0xFFFFFFFF:08X}" for w in part)
            for _ in range(TRIES):
                if self._request("W", payload, "k" + an):
                    break
            else:
                raise LinkError(f"no answer to W {an}")
            addr = (addr + len(part)) & 0xFFFFFFFF
            words = words[MAX_WORDS:]

    def control(self, value: int) -> None:
        """Writes the control register (DEBUG.md §6), with a W of its own.
        Without an answer, it is read back, and written again only if the
        write did not take effect, or if it holds and clears."""
        an = f"{CONTROL:08X}0001"
        payload = f"{an}{value:08X}"
        for _ in range(TRIES):
            if self._request("W", payload, "k" + an):
                return
            if value & HOLD and value & CLEAR:
                continue
            got = self._read_once(CONTROL, 1)
            if got is None:
                continue
            # A system without a ROM reads bit 3 as 1 whatever was written.
            if (got[0] & HOLD == value & HOLD and
                    (got[0] & RAM == value & RAM or got[0] & RAM)):
                return
        raise LinkError(f"no answer to the write of {value:08X} to the "
                        f"control register")

    def step(self, value: int = PAUSE | RAM,
             timeout: float | None = None) -> int | None:
        """Runs one step of a paused processor (DEBUG.md §6, version 3):
        writes value with STEP to the control register, and waits for the
        p, x, w, or h that ends the step. Returns None when the processor
        paused again, with the x's number in breaks if it stopped at a
        breakpoint, or the w's in watches after a watchpoint's hit, and
        the halt reason when the step halted it. The write
        is not sent again blindly, as control() says, and the notice tells
        that the step ran even when its k was lost. Raises LinkError when
        neither came within timeout seconds, by default twice the wait for
        an answer."""
        if timeout is None:
            timeout = 2 * self.transport.answer_wait(0)
        pauses, halts = self.pauses, len(self.halts)
        self.control(value | STEP)
        end = time.monotonic() + timeout
        while self.pauses == pauses and len(self.halts) == halts:
            if time.monotonic() >= end:
                raise LinkError("no p, x, w, or h after a step")
            self.poll(end - time.monotonic())
        if len(self.halts) > halts:
            return self.halts[-1]
        return None

    def set_breaks(self, addrs: list[int | None]) -> None:
        """Sets the breakpoints (DEBUG.md §6, version 4): breakpoint i at
        addrs[i], or disabled where it is None, and those past the list
        disabled. The addresses are written before the enable bits, so no
        breakpoint is enabled at an old address."""
        en = 0
        for i, addr in enumerate(addrs):
            if addr is not None:
                self.write(BRK_ADDR + i, [addr])
                en |= 1 << i
        self.write(BRK_EN, [en])

    def set_watches(self, watches: list[tuple[int, int] | None]) -> None:
        """Sets the watchpoints (DEBUG.md §6, version 7): watchpoint i at
        the address of watches[i], for its kinds, WCH_READ, WCH_WRITE, or
        both, or disabled where it is None, and those past the list
        disabled. The addresses are written before the enable bits."""
        en = 0
        for i, watch in enumerate(watches):
            if watch is not None:
                self.write(WCH_ADDR + i, [watch[0]])
                en |= watch[1] << 2 * i
        self.write(WCH_EN, [en])

    def free(self) -> int:
        """The free space of the program's input buffer."""
        return self.read_word(FREE)

    # The console

    def send_console(self, data: bytes, paced: bool = True,
                     timeout: float = SEND_WAIT) -> bytes:
        """Sends console bytes to the program, with 0xFF as ESC ESC. Paced,
        each part waits for room in the program's input buffer, and the
        console bytes that arrive meanwhile are kept. A buffer that stays
        full for timeout seconds, because the program does not read it,
        is an error; with a timeout of 0, the bytes that have no room are
        returned at once instead. Returns the bytes not sent."""
        room = time.monotonic()
        while data:
            n = len(data)
            if paced:
                n = min(n, self.free())
                if n == 0:
                    if timeout == 0:
                        return data
                    if time.monotonic() - room >= timeout:
                        raise LinkError(
                            f"the program's input buffer is full, and the "
                            f"program did not read it for {timeout:g} s; "
                            f"{len(data)} bytes not sent")
                    self.poll(FULL_WAIT)
                    continue
                room = time.monotonic()
            part, data = data[:n], data[n:]
            self.transport.write(part.replace(bytes([ESC]), bytes([ESC, ESC])))
        return b""

    def end_input(self) -> None:
        """Ends the program's input: a break on the UART, or a half-close."""
        self.transport.end_input(self._wait)
        self.input_ended = True

    def _wait(self, seconds: float) -> None:
        """Takes what arrives for seconds."""
        end = time.monotonic() + seconds
        while (now := time.monotonic()) < end:
            self.poll(end - now)


def read_words(link: Link, addrs: list[int]) -> list[int]:
    """Reads the words at addrs, in order, with one R for each run of
    consecutive addresses."""
    words: list[int] = []
    i = 0
    while i < len(addrs):
        j = i + 1
        while j < len(addrs) and addrs[j] == (addrs[j - 1] + 1) & 0xFFFFFFFF:
            j += 1
        words += link.read(addrs[i], j - i)
        i = j
    return words


def parse_tcp(text: str | int) -> tuple[str, int]:
    """The host and the port of --tcp [HOST:]PORT, with 127.0.0.1 if no
    HOST is given. An IPv6 HOST is in brackets, as for niceemu --link, so
    that its colons are not the one before PORT."""
    host, sep, port = str(text).rpartition(":")
    if not sep:
        host = "127.0.0.1"
    elif host.startswith("[") and host.endswith("]"):
        host = host[1:-1]
    elif ":" in host:
        fail(f"--tcp {text}: an IPv6 HOST goes in brackets, [HOST]:PORT")
    if not port.isdigit() or not host or int(port) > 65535:
        fail(f"--tcp {text}: not PORT or HOST:PORT")
    return host, int(port)


def add_arguments(parser: argparse.ArgumentParser
                  ) -> argparse._MutuallyExclusiveGroup:
    """The options that pick the link: --tcp for niceemu --link, or --port
    and --baud for a system's UART. One of --tcp and --port must be given.
    Returns their group, to which a board adds the options of its own
    transports."""
    line = parser.add_mutually_exclusive_group(required=True)
    line.add_argument("--tcp", metavar="[HOST:]PORT",
                      help="talk to niceemu --link on PORT of HOST (default "
                      "127.0.0.1); serve the link beyond 127.0.0.1 only on a "
                      "trusted network")
    line.add_argument("--port", metavar="DEVICE",
                      help="talk to a system on its UART, the serial device "
                      "DEVICE, such as /dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD,
                        help="the UART's baud rate (default %(default)s)")
    return line


def check_version(link: Link) -> int:
    """Reads the version of the link, and stops on a major that the tools
    do not know (DEBUG.md §9). Returns the version."""
    version = link.read_word(VERSION)
    if version >> 4 != MAJOR:
        fail(f"the system serves debug link version {version >> 4}."
             f"{version & 0xF} (0x{version:02x}); this tool knows major "
             f"{MAJOR}")
    return version


def wait_boot(link: Link, where: str) -> None:
    """Waits for the b notice that niceemu sends to each host that connects
    (DEBUG.md §7.2), and stops without one."""
    end = time.monotonic() + BOOT_WAIT
    try:
        while not link.boots and time.monotonic() < end:
            link.poll(end - time.monotonic())
    except LinkError as e:
        fail(f"{where}: {e}")
    if not link.boots:
        fail(f"no b notice, the packet that niceemu --link sends to each "
             f"host that connects, from {where}; is that port served by "
             f"niceemu --link, not by another program?")


def open_link(args: argparse.Namespace) -> Link:
    """The link that the options of add_arguments pick, after a check of
    its version. A board that adds options of its own makes its link
    itself, and calls check_version()."""
    if getattr(args, "tcp", None) is not None:
        host, port = parse_tcp(args.tcp)
        link = Link(Tcp(port, host))
        wait_boot(link, f"{host}:{port}")
    else:
        link = Link(Serial(args.port, getattr(args, "baud", DEFAULT_BAUD)))
    try:
        check_version(link)
    except LinkError as e:
        link.close()
        fail(str(e))
    return link
