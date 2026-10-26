#!/usr/bin/env python3
"""The stops of a program at its breakpoints on the emulator, for tb_core.

Usage: break_stops.py [--emu NICEEMU] PROGRAM.bin "ADDR ..." [-- EMULATOR_OPTIONS...]

ADDR are the addresses of the breakpoints in hex, as tb_core's G_BREAK_AT
takes them, at most four, as the emulator has (doc/DEBUG.md §6).
EMULATOR_OPTIONS go to the emulator as they are, for example "--irq 6:2".

The script runs "niceemu --link 0" with the program, connects as the
host, sets the breakpoints, enables them all, and starts the program. At
each `x` notice it reads R0-R15 and goes on, until the processor halts.
It prints a line for each stop, "stop" and R0-R15 in hex, as tb_core
writes them to G_BREAK_LOG. So the two can be compared with diff. It
fails if a notice other than `x` and `h` comes, or none in 10 s.
"""

from __future__ import annotations

import argparse
import os
import socket
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_EMU = os.path.join(HERE, "..", "..", "emulator", "zig-out", "bin", "niceemu")

ESC = 0xFF
CONTROL = 0xFFFFFFF0
BREAK_EN = 0xFFFFFFF4
BREAK0 = 0xFFFFFFF8
REGS = 0xFFFFFFE0
GO = 0x8
MAX_STOPS = 10000


def packet(tag: str, payload: str) -> bytes:
    """ESC, the tag, the payload, '#', and the checksum (DEBUG.md §2)."""
    body = (tag + payload).encode()
    return bytes([ESC]) + body + b"#" + f"{sum(body) % 256:02X}".encode()


class Host:
    """The host's side of the link to a niceemu."""

    def __init__(self, port: int) -> None:
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.buf = b""

    def byte(self) -> int:
        if not self.buf:
            got = self.sock.recv(65536)
            if not got:
                raise RuntimeError("the emulator closed the link")
            self.buf = got
        b = self.buf[0]
        self.buf = self.buf[1:]
        return b

    def packet(self) -> tuple[str, str]:
        """The tag and the payload of the next packet. Console bytes, which
        come without ESC, are skipped."""
        while self.byte() != ESC:
            pass
        tag = chr(self.byte())
        payload = ""
        while (c := chr(self.byte())) != "#":
            payload += c
        self.byte()
        self.byte()
        return tag, payload

    def answer(self, want: str) -> str:
        tag, payload = self.packet()
        if tag != want:
            raise RuntimeError(f"expected {want!r}, got {tag!r} {payload!r}")
        return payload

    def write(self, addr: int, words: list[int]) -> None:
        self.sock.sendall(packet("W", f"{addr:08X}{len(words):04X}" + "".join(f"{w:08X}" for w in words)))
        self.answer("k")

    def read(self, addr: int, n: int) -> list[int]:
        self.sock.sendall(packet("R", f"{addr:08X}{n:04X}"))
        payload = self.answer("r")[12:]
        return [int(payload[8 * i:8 * i + 8], 16) for i in range(n)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--emu", default=DEFAULT_EMU)
    ap.add_argument("program")
    ap.add_argument("breaks")
    ap.add_argument("emu_opts", nargs="*")
    args = ap.parse_args()
    addrs = [int(a, 16) for a in args.breaks.split()]
    if not 1 <= len(addrs) <= 4:
        sys.exit("break_stops.py: from 1 to 4 breakpoints")

    proc = subprocess.Popen([args.emu, "--link", "0", *args.emu_opts, args.program],
                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE)
    try:
        assert proc.stderr is not None
        line = proc.stderr.readline().decode()
        if not line.startswith("link: port "):
            raise RuntimeError(f"no port line, got {line!r}")
        host = Host(int(line.split()[2]))
        host.answer("b")
        host.write(BREAK0, addrs)
        host.write(BREAK_EN, [(1 << len(addrs)) - 1])
        host.write(CONTROL, [GO])
        for _ in range(MAX_STOPS):
            tag, payload = host.packet()
            if tag == "h":
                return 0
            if tag != "x":
                raise RuntimeError(f"expected x or h, got {tag!r} {payload!r}")
            print("stop " + " ".join(f"{r:08X}" for r in host.read(REGS, 16)))
            host.write(CONTROL, [GO])
        raise RuntimeError(f"more than {MAX_STOPS} stops")
    except (RuntimeError, OSError) as e:
        sys.exit(f"break_stops.py: {e}")
    finally:
        proc.terminate()
        proc.communicate(timeout=10)


if __name__ == "__main__":
    sys.exit(main())
