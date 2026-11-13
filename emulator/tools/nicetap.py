#!/usr/bin/env python3
"""nicetap: join niceemu's UDP socket for Ethernet frames to a TAP device.

niceemu's --eth-udp and --eth-peer carry each Ethernet frame as one UDP
datagram (doc/DEVICES.md §7). This tool is the peer: each frame read from
the TAP device goes to niceemu as one datagram, and each datagram from
niceemu goes to the device. The host bridges the device, or routes and
NATs it, as for QEMU, and a program in the emulator is on a real network.

    nicetap.py --tap nice0 --udp 5556 --peer 5555
    niceemu --eth-udp 5555 --eth-peer 5556 program.bin

Linux only. The device needs root or CAP_NET_ADMIN, or one made
beforehand with `ip tuntap add mode tap user $USER name nice0`."""

from __future__ import annotations

import argparse
import fcntl
import ipaddress
import os
import select
import socket
import struct
import sys
from typing import NoReturn

TUNSETIFF = 0x400454CA
IFF_TAP = 0x0002
IFF_NO_PI = 0x1000
# The datagrams that niceemu takes, as DEVICES.md §7 says.
MIN_FRAME = 14
MAX_FRAME = 1514


def fail(msg: str) -> NoReturn:
    print(f"nicetap: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_addr(opt: str, s: str) -> tuple[socket.AddressFamily, tuple[str, int]]:
    """The [ADDR:]PORT of niceemu's --eth-udp: ADDR is an IPv4 address, or
    an IPv6 one in brackets, and 127.0.0.1 if none is given. PORT is
    decimal, or hex after 0x."""
    addr, colon, port_s = s.rpartition(":")
    if not colon:
        addr = "127.0.0.1"
    hex_ = port_s[:2] in ("0x", "0X")
    digits = port_s[2:] if hex_ else port_s
    valid = "0123456789abcdefABCDEF" if hex_ else "0123456789"
    if not digits or any(c not in valid for c in digits):
        fail(f"{opt}: bad number '{port_s}'")
    port = int(digits, 16 if hex_ else 10)
    if port > 65535:
        fail(f"{opt}: '{port_s}' is larger than 65535")
    try:
        if len(addr) >= 2 and addr[0] == "[" and addr[-1] == "]":
            return socket.AF_INET6, (str(ipaddress.IPv6Address(addr[1:-1])), port)
        return socket.AF_INET, (str(ipaddress.IPv4Address(addr)), port)
    except ValueError:
        fail(f"{opt}: bad address '{addr}'")


def open_tap(name: str) -> int:
    """Open the TAP device `name`, made if it does not exist and the
    process may, without the packet information header."""
    if len(name.encode()) > 15:
        fail(f"--tap: '{name}' is longer than 15 bytes")
    try:
        fd = os.open("/dev/net/tun", os.O_RDWR)
    except OSError as e:
        fail(f"cannot open /dev/net/tun: {e.strerror}")
    try:
        fcntl.ioctl(fd, TUNSETIFF, struct.pack("16sH", name.encode(), IFF_TAP | IFF_NO_PI))
    except OSError as e:
        os.close(fd)
        fail(f"cannot open TAP device {name}: {e.strerror}")
    return fd


def main() -> None:
    ap = argparse.ArgumentParser(
        prog="nicetap", description="Join niceemu's UDP socket for Ethernet frames to a TAP device.")
    ap.add_argument("--tap", required=True, metavar="NAME", help="the TAP device")
    ap.add_argument("--udp", required=True, metavar="[ADDR:]PORT",
                    help="receive niceemu's frames on PORT of ADDR (default 127.0.0.1)")
    ap.add_argument("--peer", required=True, metavar="[ADDR:]PORT",
                    help="send the device's frames to niceemu's --eth-udp here")
    args = ap.parse_args()
    if not sys.platform.startswith("linux"):
        fail("TAP devices are supported on Linux only")
    family, local = parse_addr("--udp", args.udp)
    peer_family, peer = parse_addr("--peer", args.peer)
    if peer_family != family:
        fail("--udp and --peer must both be IPv4 or both IPv6")
    tap = open_tap(args.tap)
    sock = socket.socket(family, socket.SOCK_DGRAM)
    try:
        sock.bind(local)
    except OSError as e:
        fail(f"cannot receive frames on {args.udp}: {e.strerror}")
    print(f"nicetap: {args.tap} joined to {args.udp}, peer {args.peer}", file=sys.stderr, flush=True)
    try:
        while True:
            ready, _, _ = select.select([tap, sock.fileno()], [], [])
            if tap in ready:
                frame = os.read(tap, 65536)
                try:
                    sock.sendto(frame, peer)
                except OSError:
                    pass  # Nobody on the peer's port yet: the frame is lost, as on a wire.
            if sock.fileno() in ready:
                frame = sock.recv(65536)
                if MIN_FRAME <= len(frame) <= MAX_FRAME:
                    try:
                        os.write(tap, frame)
                    except OSError:
                        pass  # The device is down: the frame is lost.
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
