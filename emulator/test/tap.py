#!/usr/bin/env python3
"""A test of tools/nicetap.py, which joins niceemu's UDP socket for
Ethernet frames to a TAP device.

First the errors of nicetap's options, which need no device. Then, in an
unprivileged user and network namespace (unshare -rn), nicetap makes the
device nice0, niceemu runs ECHO of udp.py as nicetap's peer, and this
script is a host on nice0, with a packet socket: it sees the program's
hello, sends a frame to another MAC address and an ARP request for
NET_IP, which the station answers, and last a frame to the station,
which the program sends back. The frames come padded to 60 bytes. A host
that refuses the namespace, or has no /dev/net/tun or ip, skips that part
with a message."""

from __future__ import annotations

import fcntl
import os
import select
import shutil
import socket
import subprocess
import struct
import sys
import tempfile
import time

import udp

HERE = os.path.dirname(os.path.abspath(__file__))
NICETAP = os.path.join(HERE, "..", "tools", "nicetap.py")
TAP = "nice0"
ETH_P_ALL = 0x0003
PACKET_OUTGOING = 4
SIOCGIFHWADDR = 0x8927

# Arguments to nicetap and the line it must print on stderr.
ERRORS = [
    (["--udp", "5556", "--peer", "5555"], "the following arguments are required: --tap"),
    (["--tap", TAP, "--udp", "x", "--peer", "5555"], "nicetap: --udp: bad number 'x'"),
    (["--tap", TAP, "--udp", "65536", "--peer", "5555"], "nicetap: --udp: '65536' is larger than 65535"),
    (["--tap", TAP, "--udp", "5556", "--peer", "1.2.3:5555"], "nicetap: --peer: bad address '1.2.3'"),
    (["--tap", TAP, "--udp", "5556", "--peer", "[::1]:5555"],
     "nicetap: --udp and --peer must both be IPv4 or both IPv6"),
    (["--tap", "a" * 16, "--udp", "5556", "--peer", "5555"], "nicetap: --tap: '" + "a" * 16 + "' is longer than 15 bytes"),
]


def check_errors(problems: list[str]) -> None:
    for args, want in ERRORS:
        p = subprocess.run([sys.executable, NICETAP, *args], capture_output=True, text=True, timeout=10)
        if p.returncode == 0 or want not in p.stderr:
            problems.append(f"nicetap {' '.join(args)}: exit {p.returncode}, wanted '{want}', got:\n{p.stderr}")


def recv_from_tap(peer: socket.socket, deadline: float) -> bytes:
    """The next frame that comes into nice0 from nicetap, skipping those
    that go out: this host's and the kernel's."""
    while True:
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([peer], [], [], left)[0]:
            raise TimeoutError("no frame from nicetap")
        frame, addr = peer.recvfrom(2048)
        if addr[2] != PACKET_OUTGOING:
            return frame


def bridge(problems: list[str]) -> None:
    """The run through nice0, inside the namespace."""
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    with tempfile.TemporaryDirectory() as tmp:
        nasm = os.path.join(tmp, "echo.nasm")
        with open(nasm, "w") as f:
            f.write(udp.ECHO)
        subprocess.run([sys.executable, udp.NICEASM, nasm], check=True)
        emu_port, tap_port = udp.free_port(), udp.free_port()
        tap = subprocess.Popen(
            [sys.executable, NICETAP, "--tap", TAP, "--udp", str(tap_port), "--peer", str(emu_port)],
            stderr=subprocess.PIPE, text=True)
        emu = None
        try:
            assert tap.stderr is not None
            line = tap.stderr.readline()
            if not line.startswith(f"nicetap: {TAP} joined"):
                problems.append(f"nicetap: {line}{tap.stderr.read()}")
                return
            subprocess.run(["ip", "link", "set", TAP, "up"], check=True)
            peer = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
            peer.bind((TAP, 0))
            # /sys/class/net is the host's, not the namespace's.
            ifreq = fcntl.ioctl(peer, SIOCGIFHWADDR, struct.pack("256s", TAP.encode()))
            mac = ifreq[18:24]
            emu = subprocess.Popen(
                [udp.NICEEMU, "--eth-udp", str(emu_port), "--eth-peer", str(tap_port),
                 os.path.join(tmp, "echo.bin")],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            deadline = time.monotonic() + 10
            got = recv_from_tap(peer, deadline)
            if got != udp.padded(udp.HELLO):
                problems.append(f"hello: got {got.hex()}")
            arp_request = udp.ARP_REQUEST.replace(udp.PEER_MAC, mac)
            arp_reply = udp.ARP_REPLY.replace(udp.PEER_MAC, mac)
            frame = udp.STATION + mac + udp.FRAME[12:]
            peer.send(udp.OTHER.replace(udp.PEER_MAC, mac))
            peer.send(arp_request)
            got = recv_from_tap(peer, deadline)
            if got != udp.padded(arp_reply):
                problems.append(f"ARP reply: got {got.hex()}")
            peer.send(frame)
            got = recv_from_tap(peer, deadline)
            if got != udp.padded(frame):
                problems.append(f"echo: got {got.hex()}")
            out, err = emu.communicate(timeout=10)
            if emu.returncode != 0 or not out.startswith("Halted (HALT)"):
                problems.append(f"niceemu: exit status {emu.returncode}, output:\n{out}{err}")
            peer.close()
        except (TimeoutError, subprocess.TimeoutExpired) as e:
            problems.append(f"timed out: {e}")
        finally:
            for p in (emu, tap):
                if p is not None and p.poll() is None:
                    p.kill()
                    p.wait()


def skip_reason() -> str | None:
    """Why this host cannot run the bridge in a namespace, if it cannot."""
    if not sys.platform.startswith("linux"):
        return "not Linux"
    if shutil.which("unshare") is None or shutil.which("ip") is None:
        return "no unshare or ip"
    if not os.path.exists("/dev/net/tun"):
        return "no /dev/net/tun"
    p = subprocess.run(["unshare", "-rn", "true"], capture_output=True, text=True)
    if p.returncode != 0:
        return f"unshare -rn refused: {p.stderr.strip()}"
    return None


def main() -> None:
    problems: list[str] = []
    if sys.argv[1:] == ["--inside"]:
        bridge(problems)
    else:
        check_errors(problems)
        reason = skip_reason()
        if reason is not None:
            print(f"SKIP tap bridge: {reason}")
        else:
            p = subprocess.run(["unshare", "-rn", sys.executable, os.path.abspath(__file__), "--inside"],
                               capture_output=True, text=True)
            if p.returncode != 0:
                problems.append(f"in the namespace:\n{p.stdout}{p.stderr}")
    if problems:
        print("FAIL tap")
        for msg in problems:
            print("    " + msg.replace("\n", "\n    "))
        sys.exit(1)
    if sys.argv[1:] != ["--inside"]:
        print("PASS tap")


if __name__ == "__main__":
    main()
