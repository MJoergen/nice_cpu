#!/usr/bin/env python3
"""Tests of niceemu's command line and loader.

CASES are command lines, some with a .bin file, that must fail with exit
status 1 and print the expected message on stderr. RUNS are programs that
run and stop, each with its exit status and lines of its output."""

from __future__ import annotations

import os
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time
from typing import List, Optional, Tuple

NICEASM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assembler", "niceasm.py")
# NICEEMU in the environment names another build, such as one of make dist.
NICEEMU = os.environ.get("NICEEMU") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "zig-out", "bin", "niceemu")

# (arguments, contents of the .bin file or None, expected stderr line). In
# the arguments and the message, BIN stands for the .bin file's path.
CASES: List[Tuple[List[str], Optional[str], str]] = [
    # Command line
    ([], None, "niceemu: no program given"),
    (["BIN", "BIN"], "00000000 0c000000", "niceemu: more than one program given"),
    (["-x", "BIN"], "00000000 0c000000", "niceemu: unknown option '-x'"),
    (["--mem-size", "5", "BIN"], "00000000 0c000000", "niceemu: unknown option '--mem-size'"),
    (["BIN", "-n"], "00000000 0c000000", "niceemu: -n needs a value"),
    (["-n", "abc", "BIN"], "00000000 0c000000", "niceemu: -n: bad number 'abc'"),
    (["--max-steps", "-1", "BIN"], "00000000 0c000000", "niceemu: --max-steps: bad number '-1'"),
    (["-n", "0x10000000000000000", "BIN"], "00000000 0c000000",
     "niceemu: -n: '0x10000000000000000' is larger than 18446744073709551615"),
    (["-d", "10", "BIN"], "00000000 0c000000", "niceemu: -d wants ADDR:N, not '10'"),
    (["--dump", "10", "BIN"], "00000000 0c000000", "niceemu: --dump wants ADDR:N, not '10'"),
    (["-d", ":5", "BIN"], "00000000 0c000000", "niceemu: -d: bad number ''"),
    (["-d", "0:0x100000000", "BIN"], "00000000 0c000000", "niceemu: -d: '0x100000000' is larger than 4294967295"),
    # NICE has no interrupts, so niceemu has no options to raise them.
    (["--irq", "5:1", "BIN"], "00000000 0c000000", "niceemu: unknown option '--irq'"),
    (["--nmi", "5:1", "BIN"], "00000000 0c000000", "niceemu: unknown option '--nmi'"),
    (["--no-timer-irq", "BIN"], "00000000 0c000000", "niceemu: unknown option '--no-timer-irq'"),
    (["--link", "x"], None, "niceemu: --link: bad number 'x'"),
    (["--link", "1.2.3:0"], None, "niceemu: --link: bad address '1.2.3'"),
    (["--link", "[::1:0"], None, "niceemu: --link: bad address '[::1'"),
    (["--link", "::1:0"], None, "niceemu: --link: bad address '::1'"),
    (["--link", "127.0.0.1:"], None, "niceemu: --link: bad number ''"),
    (["--link", ":0"], None, "niceemu: --link: bad address ''"),
    (["--link", "127.0.0.1:65536"], None, "niceemu: --link: '65536' is larger than 65535"),
    # 192.0.2.1 is for documentation (RFC 5737), and no address of this computer.
    (["--link", "192.0.2.1:0"], None, "niceemu: cannot serve the link on 192.0.2.1:0: AddressUnavailable"),
    (["-d", "0:1_0", "BIN"], "00000000 0c000000", "niceemu: -d: bad number '1_0'"),
    (["-n", "0b11", "BIN"], "00000000 0c000000", "niceemu: -n: bad number '0b11'"),
    (["-d", "0x:1", "BIN"], "00000000 0c000000", "niceemu: -d: bad number '0x'"),
    (["-d", "0xg:1", "BIN"], "00000000 0c000000", "niceemu: -d: bad number '0xg'"),
    (["does-not-exist.bin"], None, "niceemu: cannot read does-not-exist.bin: FileNotFound"),
    (["--speed", "5", "BIN"], "00000000 0c000000", "niceemu: --speed needs --window"),
    (["BIN", "--speed"], "00000000 0c000000", "niceemu: --speed needs a value"),
    (["--window", "--speed", "x", "BIN"], "00000000 0c000000", "niceemu: --speed: bad number 'x'"),
    (["--window", "--speed", "-1", "BIN"], "00000000 0c000000", "niceemu: --speed: bad number '-1'"),
    # make test builds without -Dwindow; test/window.py tests the window.
    (["--window", "BIN"], "00000000 0c000000",
     "niceemu: --window needs a build with -Dwindow (emulator/README.md)"),
    (["BIN", "--input"], "00000000 0c000000", "niceemu: --input needs a value"),
    (["-i", "does-not-exist.txt", "BIN"], "00000000 0c000000",
     "niceemu: cannot read does-not-exist.txt: FileNotFound"),
    (["-i", ".", "BIN"], "00000000 0c000000", "niceemu: cannot read .: IsDir"),
    (["BIN", "--sd0"], "00000000 0c000000", "niceemu: --sd0 needs a value"),
    (["--sd1", "does-not-exist.img", "BIN"], "00000000 0c000000",
     "niceemu: cannot read does-not-exist.img: FileNotFound"),
    (["--sd0", ".", "BIN"], "00000000 0c000000", "niceemu: cannot read .: IsDir"),
    # main() makes empty.img, of 0 bytes, and odd.img, of 700.
    (["--sd0", "empty.img", "BIN"], "00000000 0c000000",
     "niceemu: empty.img: an SD card image must be a positive multiple of 512 bytes, not 0"),
    (["--sd1", "odd.img", "BIN"], "00000000 0c000000",
     "niceemu: odd.img: an SD card image must be a positive multiple of 512 bytes, not 700"),
    (["BIN", "--eth-in"], "00000000 0c000000", "niceemu: --eth-in needs a value"),
    (["--eth-in", "does-not-exist.eth", "BIN"], "00000000 0c000000",
     "niceemu: cannot read does-not-exist.eth: FileNotFound"),
    (["--eth-out", "no/such/dir.eth", "BIN"], "00000000 0c000000",
     "niceemu: cannot write no/such/dir.eth: FileNotFound"),
    # main() makes the .eth files of ETH_FILES.
    (["--eth-in", "short.eth", "BIN"], "00000000 0c000000", "short.eth:2: error: a frame has 14 to 1514 bytes, not 13"),
    (["--eth-in", "long.eth", "BIN"], "00000000 0c000000", "long.eth:1: error: a frame has 14 to 1514 bytes, not 1515"),
    (["--eth-in", "digit.eth", "BIN"], "00000000 0c000000", "digit.eth:1: error: a byte has one hex digit"),
    (["--eth-in", "hex.eth", "BIN"], "00000000 0c000000", "hex.eth:1: error: 'z' is not a hex digit"),
    (["--eth-in", "count.eth", "BIN"], "00000000 0c000000", "count.eth:1: error: '-1' is not a decimal count of frames"),
    (["--eth-in", "big.eth", "BIN"], "00000000 0c000000",
     "big.eth:1: error: '18446744073709551616' is larger than 18446744073709551615"),
    (["--eth-udp", "0", "BIN"], "00000000 0c000000", "niceemu: --eth-udp and --eth-peer go together"),
    (["--eth-peer", "0", "BIN"], "00000000 0c000000", "niceemu: --eth-udp and --eth-peer go together"),
    (["--eth-udp", "x", "BIN"], "00000000 0c000000", "niceemu: --eth-udp: bad number 'x'"),
    (["--eth-peer", "1.2.3:5", "BIN"], "00000000 0c000000", "niceemu: --eth-peer: bad address '1.2.3'"),
    (["--eth-udp", "192.0.2.1:0", "--eth-peer", "9", "BIN"], "00000000 0c000000",
     "niceemu: cannot receive frames on 192.0.2.1:0: AddressUnavailable"),
    (["BIN", "--symbols"], "00000000 0c000000", "niceemu: --symbols needs a value"),
    (["--symbols", "does-not-exist.sym", "BIN"], "00000000 0c000000",
     "niceemu: cannot read does-not-exist.sym: FileNotFound"),
    # Loader
    (["BIN"], "", "BIN: error: no words to load"),
    (["BIN"], "\n  \n", "BIN: error: no words to load"),
    # The processor starts at 0, so a program with nothing there, such as
    # one of nicebuild --monitor, is refused, but for --link (test/link.py).
    (["BIN"], "00008000 0c000000",
     "niceemu: BIN loads nothing at 0, where the processor starts; its lowest word is at 00008000,"
     " and a program of nicebuild --monitor runs behind a monitor (runtime/ABI.md)"),
    (["BIN"], "hello world", "BIN:1: error: 'hello' is not a hex number"),
    (["BIN"], "00000000", "BIN:1: error: expected 'address word', found only '00000000'"),
    (["BIN"], "00000000 0c000000 extra", "BIN:1: error: unexpected 'extra' after the word"),
    (["BIN"], "100000000 0c000000", "BIN:1: error: '100000000' has more than 8 hex digits"),
    (["BIN"], "00000000 0c00_0000", "BIN:1: error: '0c00_0000' is not a hex number"),
    (["BIN"], "+1 +5", "BIN:1: error: '+1' is not a hex number"),
    (["BIN"], "0x0 0c000000", "BIN:1: error: '0x0' is not a hex number"),
    (["BIN"], "00000000 0c000000\n\n00000000 0c000000",
     "BIN:3: error: address 00000000 is already loaded by line 1"),
]

# The --eth-in files of CASES, by name.
FRAME = "ffffffffffff 020000000001 88b5"
ETH_FILES = {
    "short.eth": FRAME + "\n" + FRAME[:-2] + "\n",
    "long.eth": FRAME + " 00" * 1501 + "\n",
    "digit.eth": FRAME[:-1] + " 5\n",
    "hex.eth": "z" + FRAME[1:] + "\n",
    "count.eth": "-1: " + FRAME + "\n",
    "big.eth": "18446744073709551616: " + FRAME + "\n",
    "crlf.eth": "# A file with CR LF line ends\r\n" + FRAME + "\r\n",
}

# Runs that succeed: (contents of the .bin file, arguments before it, exit
# status, lines that stdout must have, or must not have if they start with
# "!"). 0c000000 is HALT, and 0c200000, 0c400001, and 0c800000 are
# reserved control words, commands 1, 2, and 4.
RUNS: List[Tuple[str, List[str], int, List[str]]] = [
    ("00000000 0c000000", [], 0, ["Halted (HALT) after 1 steps, PC=00000001"]),
    ("00000000 0c200000", [], 2, ["Halted (reserved control instruction) after 1 steps, PC=00000001"]),
    ("00000000 0c800000", [], 2, ["Halted (reserved control instruction) after 1 steps, PC=00000001"]),
    ("00000000 0c400001\n00000001 00000002", [], 2,
     ["Halted (reserved control instruction) after 1 steps, PC=00000001"]),
    ("00000000 00000000", ["-n", "5", "--no-cycle-counter"], 3,
     ["Stopped at the step limit after 5 steps, PC=00000005"]),
    ("00000000 00000000", ["-n", "5", "--no-font"], 3,
     ["Stopped at the step limit after 5 steps, PC=00000005"]),
    ("00000000 00000000", ["-n", "5", "--no-screen-mode"], 3,
     ["Stopped at the step limit after 5 steps, PC=00000005"]),
    ("00000000 00000000", ["-n", "5", "--no-fpu"], 3,
     ["Stopped at the step limit after 5 steps, PC=00000005"]),
    # The lines of a .bin file and of an --eth-in file may end with CR LF.
    ("00000000 00000000\r\n00000001 0c000000\r", [], 0, ["Halted (HALT) after 2 steps, PC=00000002"]),
    ("00000000 0c000000", ["--eth-in", "crlf.eth"], 0, ["Halted (HALT) after 1 steps, PC=00000001"]),
    # The word of the old WAIT is control command 3, reserved, which halts
    # (ISA.md §5.3).
    ("00000000 0c600000", [], 2, ["Halted (reserved control instruction) after 1 steps, PC=00000001"]),
    # MOVE @0xFFFFFF10, 100; HALT: 0xFFFFFF10 is a reserved word of the I/O
    # range, which is memory in the emulator (DEVICES.md §4).
    ("00000000 000c1800\n00000001 ffffff10\n00000002 00000064\n00000003 0c000000",
     ["-d", "0xffffff10:1"], 0, ["Halted (HALT) after 2 steps, PC=00000004", "ffffff10: 00000064"]),
    # -n 0 runs nothing. A HALT at the step limit still counts as a halt.
    ("00000000 0c000000", ["-n", "0"], 3, ["Stopped at the step limit after 0 steps, PC=00000000"]),
    ("00000000 0c000000", ["-n", "1"], 0, ["Halted (HALT) after 1 steps, PC=00000001"]),
    # A dump that wraps from 0xFFFFFFFF to 0 stays on one line, and a dump
    # of no words prints nothing.
    ("00000000 0c000000", ["-d", "0xfffffffe:3", "-d", "5:0"], 0,
     ["fffffffe: 00000000 00000000 0c000000", "!00000005:"]),
]


# Programs in assembly, run as those of RUNS: (source, arguments, exit
# status, lines that stdout must have, or must not have if they start with
# "!"). ESC is the escape of a color, and BLOCK the upper half block.
ESC = "\x1b"
BLOCK = "\u2580"
# The screen's mode word (DEVICES.md §1.10) keeps 0 and 1, and a write of
# another value writes 0: R1 = 0 for 2, and R2 = 0 for 0x10001, whose low
# half is 1. The text shows, as the mode is 0.
MODE_WORD = """
 MOVE @0xFFFFFF87, 2
 MOVE R1, @0xFFFFFF87
 MOVE @0xFFFFFF87, 0x10001
 MOVE R2, @0xFFFFFF87
 MOVE @0xFFFF0000, 0x41
 HALT
"""
# The chunky mode at the screen of -2004, 0x400: pixel (0, 0) red, and
# (3, 0) with bits 19..0 only, which is black, as bits 31..20 color a
# pixel. --color prints one line: a red block over black, with the black
# pixels after it left out, as the 49 black lines below are.
CHUNKY_2004 = """
 MOVE @0xFFFFFF87, 1
 MOVE @0x400, 0xF0000000
 MOVE @0x403, 0x000FFFFF
 HALT
"""
ASM_RUNS: List[Tuple[str, List[str], int, List[str]]] = [
    (MODE_WORD, ["-s"], 0, ["R0  00000000 R1  00000000 R2  00000000 R3  00000000", "Screen:", "|A"]),
    # With --no-screen-mode the word is memory, and keeps both values. Only
    # 1 is the chunky mode, so the text shows.
    (MODE_WORD, ["--no-screen-mode", "-s"], 0,
     ["R0  00000000 R1  00000002 R2  00010001 R3  00000000", "Screen:", "|A"]),
    (CHUNKY_2004, ["-2004", "--color"], 0,
     ["Screen: 160x100 pixels", f"|{ESC}[38;2;255;0;0;48;2;0;0;0m{BLOCK}{ESC}[0m", f"!|{ESC}[0m"]),
]

# The name of each trap code of translator/WASM.md, as the trap report of
# runtime/trapmsg.nasm has it, and of a number that is no code. TRAP is the
# program of test/trapsym.nasm with the code in R1, and its symbols.
TRAP_NAMES: List[Tuple[int, str]] = [
    (1, "unreachable"),
    (2, "memory access out of bounds"),
    (3, "division by zero"),
    (4, "integer overflow"),
    (5, "float to integer conversion"),
    (6, "call_indirect: bad index"),
    (7, "call_indirect: type mismatch"),
    (8, "memory beyond the byte windows"),
    (9, "no FPU"),
    (0, "unknown code"),
    (10, "unknown code"),
]
TRAP = ("00000000 00005800\n00000001 {:08x}\n00000002 00009800\n00000003 00000013\n"
        "00000004 0003d800\n00000005 00000006\n00000006 0fe00000\n00000010 0c000000")
TRAP_SYMBOLS = "00000000 start\n00000006 ___wasm_trap\n00000010 body\n"

# Files for --symbols: (contents, expected stderr line, with SYM for the
# file's path, or None for a file in order). The program is a reserved
# control word at 0, so the run halts with status 2 and names the location.
# The file in order has a blank line, CRLF ends, and two labels at 0, of
# which the first is named: "At start".
SYMBOL_FILES: List[Tuple[str, Optional[str]]] = [
    ("00000000\n", "SYM:1: error: expected 'address name', found only '00000000'"),
    ("zz start\n", "SYM:1: error: 'zz' is not a hex number"),
    ("000000001 start\n", "SYM:1: error: '000000001' has more than 8 hex digits"),
    ("0x0 start\n", "SYM:1: error: '0x0' is not a hex number"),
    ("\n00000000 start extra\n", "SYM:2: error: unexpected 'extra' after the name"),
    ("\r\n00000000 start\r\n00000000 zero\r\n00000001 next\r\n", None),
]


def run(tmp: str, args: List[str], text: Optional[str]) -> subprocess.CompletedProcess[str]:
    path = os.path.join(tmp, "t.bin")
    if text is not None:
        with open(path, "w") as f:
            f.write(text + "\n" if text else "")
    args = [path if a == "BIN" else a for a in args]
    return subprocess.run([NICEEMU] + args, capture_output=True, text=True, cwd=tmp)


def main() -> None:
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "t.bin")
        for name, size in (("empty.img", 0), ("odd.img", 700)):
            with open(os.path.join(tmp, name), "wb") as f:
                f.write(bytes(size))
        for name, contents in ETH_FILES.items():
            with open(os.path.join(tmp, name), "w") as f:
                f.write(contents)
        for args, text, expected in CASES:
            expected = expected.replace("BIN", path)
            p = run(tmp, args, text)
            problems = []
            if p.returncode != 1:
                problems.append(f"exit status {p.returncode}, expected 1")
            if expected not in p.stderr.splitlines():
                problems.append(f"expected '{expected}', got:\n{p.stderr}")
            if p.stdout:
                problems.append(f"unexpected output:\n{p.stdout}")
            if problems:
                failed += 1
                print(f"FAIL {args} {text!r}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))

        # The format of a --symbols file.
        sym = os.path.join(tmp, "t.sym")
        for text, message in SYMBOL_FILES:
            with open(sym, "w", newline="") as f:
                f.write(text)
            p = run(tmp, ["--symbols", sym, "BIN"], "00000000 0c800000")
            problems = []
            if message is None:
                if p.returncode != 2:
                    problems.append(f"exit status {p.returncode}, expected 2")
                if "At start" not in p.stdout.splitlines():
                    problems.append(f"expected 'At start', got:\n{p.stdout}")
                if p.stderr:
                    problems.append(f"unexpected stderr:\n{p.stderr}")
            else:
                message = message.replace("SYM", sym)
                if p.returncode != 1:
                    problems.append(f"exit status {p.returncode}, expected 1")
                if message not in p.stderr.splitlines():
                    problems.append(f"expected '{message}', got:\n{p.stderr}")
                if p.stdout:
                    problems.append(f"unexpected output:\n{p.stdout}")
            if problems:
                failed += 1
                print(f"FAIL --symbols {text!r}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))

        # A wait is named at the WAIT, the word before PC, as a halt is.
        with open(sym, "w") as f:
            f.write("00000000 here\n00000001 after\n")
        p = run(tmp, ["--symbols", sym, "BIN"], "00000000 0c600000")
        if p.returncode != 2 or "At here" not in p.stdout.splitlines():
            failed += 1
            print(f"FAIL --symbols in a wait: exit status {p.returncode}, output:\n{p.stdout}")

        # The name of each trap code, after a halt at ___wasm_trap.
        with open(sym, "w") as f:
            f.write(TRAP_SYMBOLS)
        for code, name in TRAP_NAMES:
            p = run(tmp, ["--symbols", sym, "BIN"], TRAP.format(code))
            want = f"Trap {code} ({name}) at body+0x3"
            if p.returncode != 2 or want not in p.stdout.splitlines() or p.stderr:
                failed += 1
                print(f"FAIL trap {code}: exit status {p.returncode}, expected '{want}', got:\n{p.stdout}{p.stderr}")

        # Help goes to stdout, with exit status 0.
        p = run(tmp, ["-h"], None)
        if p.returncode != 0 or not p.stdout.startswith("Usage: niceemu") or p.stderr:
            failed += 1
            print("FAIL -h")

        # The exit status of each way to stop, and lines the output must
        # have, or must not have when they start with "!".
        for text, args, status, lines in RUNS:
            p = run(tmp, args + ["BIN"], text)
            out = p.stdout.splitlines()
            problems = []
            if p.returncode != status:
                problems.append(f"exit status {p.returncode}, expected {status}")
            for line in lines:
                if line.startswith("!"):
                    if any(o.startswith(line[1:]) for o in out):
                        problems.append(f"unexpected '{line[1:]}'")
                elif line not in out:
                    problems.append(f"expected '{line}'")
            if p.stderr:
                problems.append(f"unexpected stderr:\n{p.stderr}")
            if problems:
                failed += 1
                print(f"FAIL {args} {text!r}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))

        # The same for the programs in assembly.
        asm = os.path.join(tmp, "t.nasm")
        for source, args, status, lines in ASM_RUNS:
            with open(asm, "w") as f:
                f.write(source)
            subprocess.run([sys.executable, NICEASM, "-o", path, asm], check=True)
            p = run(tmp, args + ["BIN"], None)
            out = p.stdout.splitlines()
            problems = []
            if p.returncode != status:
                problems.append(f"exit status {p.returncode}, expected {status}")
            for line in lines:
                if line.startswith("!"):
                    if any(o.startswith(line[1:]) for o in out):
                        problems.append(f"unexpected '{line[1:]}'")
                elif line not in out:
                    problems.append(f"expected '{line}'")
            if p.stderr:
                problems.append(f"unexpected stderr:\n{p.stderr}")
            if problems:
                failed += 1
                print(f"FAIL {args} {source!r}")
                for msg in problems:
                    print("    " + msg.replace("\n", "\n    "))
                print("    got:\n    " + p.stdout.replace("\n", "\n    "))

        # A pipe closed early ends the trace quietly, with status 141.
        with open(path, "w") as f:
            f.write("00000000 00000000\n")
        proc = subprocess.Popen([NICEEMU, "-t", path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert proc.stdout is not None and proc.stderr is not None
        proc.stdout.readline()
        proc.stdout.close()
        err = proc.stderr.read()
        if proc.wait() != 141 or err:
            failed += 1
            print(f"FAIL closed pipe: exit status {proc.returncode}, stderr {err!r}")

        # Before a console read waits for input, the output so far is
        # flushed, so that a prompt shows. The program prints "?", reads a
        # byte, and echoes it. The byte is sent only once the "?" has come.
        with open(path, "w") as f:
            f.write("00000000 001c1800\n00000001 ffffff00\n00000002 0000003f\n"
                    "00000003 00007800\n00000004 ffffff00\n"
                    "00000005 001c0080\n00000006 ffffff00\n00000007 0c000000\n")
        prompt = subprocess.Popen([NICEEMU, path], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE)
        assert prompt.stdout is not None
        ready, _, _ = select.select([prompt.stdout], [], [], 5)
        first = os.read(prompt.stdout.fileno(), 1) if ready else b""
        rest, err_b = prompt.communicate(b"x", timeout=10)
        if first != b"?" or not rest.startswith(b"xHalted (HALT) after 4 steps") or err_b:
            failed += 1
            print(f"FAIL prompt: {first!r} first, then {rest[:40]!r}, stderr {err_b!r}")

        # On a terminal, the console output shows at once, so that it is not
        # lost when the user stops a program that loops. The program prints
        # "A" and loops. The "A" must come within 5 seconds, long before the
        # program is stopped.
        loop_asm = os.path.join(tmp, "loop.nasm")
        loop_bin = os.path.join(tmp, "loop.bin")
        with open(loop_asm, "w") as f:
            f.write(" MOVE @0xFFFFFF00, 0x41\nloop MOVE R15, loop\n")
        subprocess.run([sys.executable, NICEASM, "-o", loop_bin, loop_asm], check=True)
        master, slave = pty.openpty()
        tty = subprocess.Popen([NICEEMU, "-n", "1000000000000", loop_bin], stdin=subprocess.DEVNULL,
                               stdout=slave, stderr=subprocess.PIPE)
        os.close(slave)
        with open(master, "rb", buffering=0) as screen:
            ready, _, _ = select.select([screen], [], [], 5)
            shown = screen.read(1) if ready else b""
            tty.kill()
            tty.communicate()
        if shown != b"A":
            failed += 1
            print(f"FAIL terminal output: {shown!r}, expected b'A' within 5 seconds")

        # A program killed by SIGTERM, SIGINT, or SIGHUP with stdout a pipe
        # still writes its buffered output, and then dies of the signal.
        # The program prints "A" and loops.
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            killed = subprocess.Popen([NICEEMU, "-n", "1000000000000", loop_bin], stdin=subprocess.DEVNULL,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(1)
            killed.send_signal(sig)
            out_b, err_b = killed.communicate(timeout=10)
            if out_b != b"A" or killed.returncode != -sig or err_b:
                failed += 1
                print(f"FAIL {sig.name}: output {out_b!r}, exit status {killed.returncode}, stderr {err_b!r}")
        # The same while the program waits in a console read: stdin is a pipe
        # that stays open and silent. The program prints "A" and reads.
        wait_asm = os.path.join(tmp, "wait.nasm")
        wait_bin = os.path.join(tmp, "wait.bin")
        with open(wait_asm, "w") as f:
            f.write(" MOVE @0xFFFFFF00, 0x41\n MOVE R1, @0xFFFFFF00\n HALT\n")
        subprocess.run([sys.executable, NICEASM, "-o", wait_bin, wait_asm], check=True)
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            waiting = subprocess.Popen([NICEEMU, wait_bin], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(1)
            waiting.send_signal(sig)
            try:
                out_b, err_b = waiting.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                waiting.kill()
                out_b, err_b = waiting.communicate()
            if out_b != b"A" or waiting.returncode != -sig or err_b:
                failed += 1
                print(f"FAIL {sig.name} in a console read: output {out_b!r}, "
                      f"exit status {waiting.returncode}, stderr {err_b!r}")
    total = len(CASES) + len(SYMBOL_FILES) + len(RUNS) + len(ASM_RUNS) + len(TRAP_NAMES) + 10
    print(f"PASS errors ({total} cases)" if not failed else f"FAIL errors ({failed} of {total})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
