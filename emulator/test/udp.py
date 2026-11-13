#!/usr/bin/env python3
"""A test of niceemu's Ethernet frames over a UDP socket, doc/DEVICES.md §7.

niceemu runs ECHO with --eth-udp and --eth-peer, and this script is the
peer. The program sets NET_IP, enables the port, and says hello with a
frame of 14 bytes, so the peer sends nothing before the station has its
address. Then the peer sends a datagram too short for a frame, a frame
to another MAC address, and an ARP request for NET_IP, none of which
reaches the program, and last a frame to the station, which the program
sends back, and halts. Each frame comes padded to 60 bytes, as on the
wire. The frames are written out in full."""

from __future__ import annotations

import os
import socket
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
NICEASM = os.path.join(HERE, "..", "..", "assembler", "niceasm.py")
# NICEEMU in the environment names another build, such as one of make dist.
NICEEMU = os.environ.get("NICEEMU") or os.path.join(HERE, "..", "zig-out", "bin", "niceemu")

# Copies the first frame received into the send buffer, all 48 chunks,
# and sends it with its length.
ECHO = """
NET_IP          .EQU    0xFFFFFFB0
ETH_CSR         .EQU    0xFFFFFFC0
ETH_RX_LEN      .EQU    0xFFFFFFC1
ETH_TX_LEN      .EQU    0xFFFFFFC2
ETH_CHUNK       .EQU    0xFFFFFFC3
ETH_BUF0        .EQU    0xFFFFFFC8
ETH_BUF1        .EQU    0xFFFFFFC9
ETH_BUF2        .EQU    0xFFFFFFCA
ETH_BUF3        .EQU    0xFFFFFFCB
                MOVE    @NET_IP, 0xC0A80141
                MOVE    @ETH_CSR, 1
                MOVE    @ETH_CHUNK, 0x100
                MOVE    @ETH_BUF0, 0x0000FFFF
                MOVE    @ETH_BUF1, 0xFFFFFFFF
                MOVE    @ETH_BUF2, 0x024E4943
                MOVE    @ETH_BUF3, 0x450088B5
                MOVE    @ETH_TX_LEN, 14
rxwait          TST     @ETH_RX_LEN
        ?Z      JMP     rxwait
                MOVE    R2, 0
chunk           MOVE    R4, ETH_BUF0
                MOVE    R5, 8
word            MOVE    @ETH_CHUNK, R2
                MOVE    R6, @R4
                OR      R7, R2, 0x100
                MOVE    @ETH_CHUNK, R7
                MOVE    @R4++, R6
                SUB[M]  R5, R5, 1
        ?!Z     JMP     word
                ADD     R2, R2, 1
                CMP     R2, 48
        ?!Z     JMP     chunk
                MOVE    @ETH_TX_LEN, @ETH_RX_LEN
                HALT
"""

STATION = bytes.fromhex("024e49434500")
PEER_MAC = bytes.fromhex("020000000001")
HELLO = bytes.fromhex("ffffffffffff 024e49434500 88b5")
ARP_REQUEST = bytes.fromhex(
    "ffffffffffff 020000000001 0806 0001 0800 06 04 0001 020000000001 c0a8010a 000000000000 c0a80141")
ARP_REPLY = bytes.fromhex(
    "020000000001 024e49434500 0806 0001 0800 06 04 0002 024e49434500 c0a80141 020000000001 c0a8010a")
OTHER = bytes.fromhex("024e49434599 020000000001 88b5 01020304")
FRAME = STATION + PEER_MAC + bytes.fromhex("88b5 a1a2a3a4a5a6")


def padded(frame: bytes) -> bytes:
    return frame + bytes(max(0, 60 - len(frame)))


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(("127.0.0.1", 0))
        port: int = s.getsockname()[1]
        return port


def main() -> None:
    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        nasm = os.path.join(tmp, "echo.nasm")
        with open(nasm, "w") as f:
            f.write(ECHO)
        subprocess.run([sys.executable, NICEASM, nasm], check=True)
        peer = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        peer.bind(("127.0.0.1", 0))
        peer.settimeout(10)
        emu_port = free_port()
        emu = ("127.0.0.1", emu_port)
        p = subprocess.Popen(
            [NICEEMU, "--eth-udp", str(emu_port), "--eth-peer", str(peer.getsockname()[1]),
             os.path.join(tmp, "echo.bin")],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            got = peer.recv(2048)
            if got != padded(HELLO):
                problems.append(f"hello: got {got.hex()}")
            peer.sendto(bytes(13), emu)
            peer.sendto(OTHER, emu)
            peer.sendto(ARP_REQUEST, emu)
            got = peer.recv(2048)
            if got != padded(ARP_REPLY):
                problems.append(f"ARP reply: got {got.hex()}")
            peer.sendto(FRAME, emu)
            got = peer.recv(2048)
            if got != padded(FRAME):
                problems.append(f"echo: got {got.hex()}")
            out, err = p.communicate(timeout=10)
            if p.returncode != 0 or not out.startswith("Halted (HALT)"):
                problems.append(f"exit status {p.returncode}, output:\n{out}{err}")
        except (socket.timeout, subprocess.TimeoutExpired) as e:
            problems.append(f"timed out: {e}")
        finally:
            if p.poll() is None:
                p.kill()
                p.wait()
            peer.close()
    if problems:
        print("FAIL udp")
        for msg in problems:
            print("    " + msg.replace("\n", "\n    "))
        sys.exit(1)
    print("PASS udp")


if __name__ == "__main__":
    main()
