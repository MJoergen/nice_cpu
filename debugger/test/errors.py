#!/usr/bin/env python3
"""Tests of nicedbg.py's errors. Each case runs nicedbg.py with options and
files that it must refuse, and checks the exit status and the last line
on stderr. The files are checked before the link opens, so their cases
give a port that nothing serves. Two servers in this script stand in for
a wrong peer: one that never sends niceemu's b notice, and one that
serves a link of a major that nicedbg.py does not know, 2 or 0 (DEBUG.md
§9).
One case is no error: --help, which must print DESCRIPTION. No niceemu
is needed."""

from __future__ import annotations

import argparse
import os
import socket
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
NICEDBG = os.path.join(os.path.dirname(HERE), "nicedbg.py")
sys.path.insert(0, os.path.dirname(HERE))

from nicedbg import DESCRIPTION  # noqa: E402
from nicelink import VERSION, packet  # noqa: E402

results: list[bool] = []


def free_port() -> int:
    """A port of 127.0.0.1 that nothing serves, at least for a while."""
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port: int = s.getsockname()[1]
        return port


def serve(answer: bool, version: int = 0x20) -> int:
    """A server of one connection on a free port. With answer, it sends a b
    notice and answers a read of VERSION with version, 0x20, major 2, by
    default; without, it sends nothing. It closes the connection when the
    client does."""
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    port: int = server.getsockname()[1]

    def run() -> None:
        conn, _ = server.accept()
        with conn, server:
            if answer:
                conn.sendall(packet("b", ""))
            data = b""
            while chunk := conn.recv(4096):
                data += chunk
                if answer and b"#" in data:
                    conn.sendall(packet("r", f"{VERSION:08X}0001"
                                             f"{version:08X}"))
                    data = b""

    threading.Thread(target=run, daemon=True).start()
    return port


def case(name: str, args: list[str], status: int, want: str) -> None:
    """nicedbg.py with args must exit with status and print want as the
    last line of its stderr."""
    p = subprocess.run([sys.executable, NICEDBG] + args, input="q\n",
                       capture_output=True, text=True, timeout=30)
    lines = p.stderr.strip().splitlines()
    got = lines[-1] if lines else ""
    ok = p.returncode == status and got == want
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} {name}")
    if not ok:
        print(f"  status {p.returncode}, wanted {status}")
        print(f"  got    {got!r}")
        print(f"  wanted {want!r}")


def help_case() -> None:
    """nicedbg.py --help must exit with status 0 and print DESCRIPTION, the
    sentence that a front end may take for its subcommand, as a paragraph
    of its own after the usage."""
    p = subprocess.run([sys.executable, NICEDBG, "--help"],
                       capture_output=True, text=True, timeout=30,
                       env=dict(os.environ, COLUMNS="80"))
    ok = (p.returncode == 0 and p.stdout.startswith("usage: nicedbg.py ")
          and f"\n\n{DESCRIPTION}\n\n" in p.stdout)
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} --help has DESCRIPTION")
    if not ok:
        print(f"  status {p.returncode}")
        print(f"  got    {p.stdout!r}")
        print(f"  wanted {DESCRIPTION!r}")


def main() -> None:
    argparse.ArgumentParser(description=__doc__).parse_args()
    port = str(free_port())
    with tempfile.TemporaryDirectory() as tmp:
        def file(name: str, text: str) -> str:
            path = os.path.join(tmp, name)
            with open(path, "w") as f:
                f.write(text)
            return path

        good = file("good.bin", "0 0c000000\n")
        tcp = ["--tcp", port]

        # The options
        help_case()
        case("no link", [], 2, "nicedbg.py: error: one of the arguments "
             "--tcp --port is required")
        case("--tcp and --port", ["--tcp", "1", "--port", "x"], 2,
             "nicedbg.py: error: argument --port: not allowed with "
             "argument --tcp")
        case("--tcp x", ["--tcp", "x"], 1,
             "nicedbg.py: --tcp x: not PORT or HOST:PORT")
        case("--tcp 70000", ["--tcp", "70000"], 1,
             "nicedbg.py: --tcp 70000: not PORT or HOST:PORT")
        case("--tcp with an IPv6 host without brackets",
             ["--tcp", "::1:5000"], 1, "nicedbg.py: --tcp ::1:5000: an "
             "IPv6 HOST goes in brackets, [HOST]:PORT")

        # The link
        case("a port that nothing serves", tcp, 1,
             f"nicedbg.py: cannot connect to 127.0.0.1:{port}: Connection "
             f"refused; is niceemu --link {port} running?")
        quiet = serve(False)
        case("a port that sends no b notice", ["--tcp", str(quiet)], 1,
             f"nicedbg.py: no b notice, the packet that niceemu --link "
             f"sends to each host that connects, from 127.0.0.1:{quiet}; is "
             f"that port served by niceemu --link, not by another program?")
        major = serve(True)
        case("a link of major 2", ["--tcp", str(major)], 1,
             "nicedbg.py: the system serves debug link version 2.0 (0x20); "
             "this tool knows major 1")
        old = serve(True, 0x08)
        case("a link of major 0", ["--tcp", str(old)], 1,
             "nicedbg.py: the system serves debug link version 0.8 (0x08); "
             "this tool knows major 1")
        case("--port of a missing device", ["--port", "/nonexistent/tty"],
             1, "nicedbg.py: cannot open /nonexistent/tty: No such file or "
             "directory")
        case("--port of a file that is no serial device",
             ["--port", good], 1,
             f"nicedbg.py: {good} is not a serial device")

        # The .bin file, as niceemu takes it
        missing = os.path.join(tmp, "missing.bin")
        case("a missing .bin file", tcp + [missing], 1,
             f"nicedbg.py: cannot read {missing}: No such file or directory")
        path = file("one.bin", "0 1\n2\n")
        case("a line with one field", tcp + [path], 1,
             f"nicedbg.py: {path}:2: expected 'address word', found only "
             f"'2'")
        path = file("three.bin", "0 1 2\n")
        case("a line with three fields", tcp + [path], 1,
             f"nicedbg.py: {path}:1: unexpected '2' after the word")
        path = file("hex.bin", "0x10 1\n")
        case("an address with 0x", tcp + [path], 1,
             f"nicedbg.py: {path}:1: '0x10' is not a hex number")
        path = file("long.bin", "\n0 123456789\n")
        case("a word of nine digits", tcp + [path], 1,
             f"nicedbg.py: {path}:2: '123456789' has more than 8 hex digits")
        path = file("twice.bin", "10 1\n\n010 2\n")
        case("an address loaded twice", tcp + [path], 1,
             f"nicedbg.py: {path}:3: address 00000010 is already loaded by "
             f"line 1")
        path = file("empty.bin", " \n\t\r\n")
        case("a .bin file without words", tcp + [path], 1,
             f"nicedbg.py: {path}: no words to load; is it a .bin file, as "
             f"niceasm.py writes with -o?")

        # The .sym file
        missing = os.path.join(tmp, "missing.sym")
        case("a missing .sym file", tcp + ["--symbols", missing, good], 1,
             f"nicedbg.py: cannot read {missing}: No such file or directory")
        path = file("one.sym", "0 START\n10\n")
        case("a label without a name", tcp + ["--symbols", path], 1,
             f"nicedbg.py: {path}:2: expected 'address name', found only "
             f"'10'")
        path = file("three.sym", "0 START END\n")
        case("a label with three fields", tcp + ["--symbols", path], 1,
             f"nicedbg.py: {path}:1: unexpected 'END' after the name")
        path = file("hex.sym", "g START\n")
        case("a label at no hex number", tcp + ["--symbols", path], 1,
             f"nicedbg.py: {path}:1: 'g' is not a hex number")
        path = file("long.sym", "123456789 START\n")
        case("a label at nine digits", tcp + ["--symbols", path], 1,
             f"nicedbg.py: {path}:1: '123456789' has more than 8 hex digits")

    passed = sum(results)
    print(f"{passed}/{len(results)} passed")
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
