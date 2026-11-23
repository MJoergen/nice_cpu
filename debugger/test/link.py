#!/usr/bin/env python3
"""Tests of nicelink.py, nicebin.py, and nicedbg.py on niceemu --link.

Each group starts "niceemu --link 0", which picks a free port, and
connects to it as the host. The groups check:

- parse_tcp(), on the forms of --tcp [HOST:]PORT and on bad ones;
- nicedbg.py's pending(), with a notice that arrives during its reads;
- the Link: the version, reads and writes longer than one packet, an
  error answer, the console of test/echo.nasm with a byte 0xFF, the end
  of its input, and the connection that follows it;
- the step and the breakpoints of the Link on test/break.nasm;
- nicedbg.py's commands, as they are typed at its prompt, on
  test/break.nasm with its labels, and its watchpoints on
  test/watch.nasm;
- nicedbg.py as a program, with its commands on stdin;
- add_options() on a parser of a front end's own, and run() on what it
  parses, with hooks of its own;
- its console on a pseudo-terminal, which passes the Enter key as CR.

The expected values come from the programs and DEBUG.md, not from the
tools' output. It prints one line for each check, and exits with status
1 when one fails. niceemu must be built first (make -C ../emulator
build). Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import os
import pty
import re
import select
import subprocess
import sys
import tempfile
import time
from typing import Callable, Iterator

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)

import nicebin  # noqa: E402
import nicedbg  # noqa: E402
import nicelink  # noqa: E402
from nicelink import (CONTROL, HALTED, HOLD, RAM, REGS,  # noqa: E402
                      Link, LinkError)

NICEASM = os.path.join(REPO, "assembler", "niceasm.py")
# NICEEMU in the environment names another build, such as one of make dist.
NICEEMU = (os.environ.get("NICEEMU") or
           os.path.join(REPO, "emulator", "zig-out", "bin", "niceemu"))
# How long a check waits for a notice
WAIT = 2.0

results: list[bool] = []


def check(name: str, ok: bool, detail: str = "") -> bool:
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'} {name}" +
          ("" if ok or not detail else f": {detail}"), flush=True)
    return ok


def assemble(name: str, out_dir: str) -> tuple[str, dict[str, int]]:
    """test/NAME.nasm assembled into out_dir, and its labels."""
    base = os.path.join(out_dir, name)
    subprocess.run([sys.executable, NICEASM, "-o", base + ".bin",
                    "--symbols", base + ".sym",
                    os.path.join(HERE, name + ".nasm")], check=True)
    with open(base + ".sym") as f:
        return base + ".bin", {
            n: int(a, 16) for a, n in (line.split() for line in f
                                       if line.strip())}


@contextlib.contextmanager
def emulator(addr: str = "127.0.0.1") -> Iterator[str]:
    """niceemu --link on a free port of addr, and that port. What it
    prints on stderr after its first line is read away, so the pipe never
    fills."""
    emu = subprocess.Popen([NICEEMU, "--link", f"{addr}:0"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    assert emu.stderr is not None
    first = emu.stderr.readline().decode(errors="replace")
    m = re.search(r"link: port (\d+)", first)
    drain = subprocess.Popen(["cat"], stdin=emu.stderr,
                             stdout=subprocess.DEVNULL)
    try:
        if not m:
            sys.exit(f"link.py: niceemu --link printed {first!r}, not its "
                     "port")
        yield m.group(1)
    finally:
        emu.terminate()
        emu.wait()
        drain.wait()


def connect(port: str) -> Link:
    """A link to niceemu, tried again for a while: niceemu refuses a new
    host, closing it, until it has seen the last one close."""
    end = time.monotonic() + WAIT
    while True:
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                return nicelink.open_link(argparse.Namespace(tcp=port))
        except (LinkError, SystemExit):
            if time.monotonic() > end:
                raise
            time.sleep(0.05)


def wait_for(link: Link, done: Callable[[], bool]) -> bool:
    """Polls the link until done(), at most WAIT seconds."""
    end = time.monotonic() + WAIT
    while not done() and time.monotonic() < end:
        link.poll(end - time.monotonic())
    return done()


def test_parse_tcp() -> None:
    """parse_tcp() takes PORT, HOST:PORT, and [HOST]:PORT, with the colons
    of an IPv6 host in brackets, and refuses the rest with fail(), which
    exits."""
    good: list[tuple[str | int, tuple[str, int]]] = [
        ("5000", ("127.0.0.1", 5000)), (5000, ("127.0.0.1", 5000)),
        ("127.0.0.2:5000", ("127.0.0.2", 5000)),
        ("[::1]:5000", ("::1", 5000)),
        ("[fe80::1%eth0]:1", ("fe80::1%eth0", 1))]
    for text, want in good:
        got = nicelink.parse_tcp(text)
        check(f"parse_tcp({text!r})", got == want, repr(got))
    for text in ["::1:5000", "x", "", ":5000", "5000:", "1.2.3.4:70000",
                 "[::1]", "[]:5000"]:
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                got = nicelink.parse_tcp(text)
            check(f"parse_tcp({text!r}) fails", False, repr(got))
        except SystemExit:
            check(f"parse_tcp({text!r}) fails", True)


class Arrival(Link):
    """A Link on no transport, on which a boot notice arrives in the first
    read, as one may while pending() reads the PC for another notice."""

    def __init__(self) -> None:
        super().__init__(nicelink.Transport())

    def read_word(self, addr: int) -> int:
        if not self.boots:
            self.boots += 1
        return 0x42


def test_pending() -> None:
    """A notice that arrives while pending() reads the PC for another is
    shown the next time, not lost."""
    link = Arrival()
    dbg = nicedbg.Debugger(link)
    link.halts.append(1)
    first = dbg.pending()
    second = dbg.pending()
    check("a notice during pending()'s reads is shown next",
          first == b"[halted: HALT, PC=00000042]\n" and
          second == b"[boot]\n", repr((first, second)))


def test_link(port: str, echo: str) -> None:
    """The Link on niceemu: the version of DEBUG.md, reads and writes of
    more words than one packet holds, an error answer, and the console of
    test/echo.nasm, which echoes its input and halts at its end with the
    count in R2. After the end of the input, the next request connects
    again, and niceemu sends b on the new connection."""
    link = connect(port)
    try:
        version = link.read_word(nicelink.VERSION)
        check("the link's version is 1.0", version == 0x10, f"{version:02x}")
        link.control(HOLD | RAM)
        words = [0x1000 * i + 7 for i in range(nicelink.MAX_WORDS + 44)]
        link.write(0x4000, words)
        got = link.read(0x4000, len(words))
        check("a write and a read of more than MAX_WORDS", got == words)
        link.write(0x3FFF, [0xFFFFFFFF])
        got = link.read(0x3FFF, 2)
        check("a word written to all ones", got == [0xFFFFFFFF, 7],
              repr(got))
        got = nicelink.read_words(link, [0x4001, 0x4002, 0x4005])
        check("read_words() joins runs of addresses",
              got == [0x1007, 0x2007, 0x5007], repr(got))

        nicebin.load_words(link, nicebin.read_bin(echo))
        got = link.read(0x4000, 1)
        check("load_words() clears the memory", got == [0], repr(got))
        nicebin.start(link)
        try:
            link.write(REGS + 1, [5])
            check("a write of R1 while the program runs is an error", False)
        except LinkError as e:
            check("a write of R1 while the program runs is an error",
                  "error 04" in str(e), str(e))
        text = b"abc\xff\x1bdef\n"
        link.send_console(text)
        link.end_input()
        # A second end before the next request has nothing to half-close
        link.end_input()
        ok = wait_for(link, lambda: bool(link.halts))
        check("the halt after the end of the input, ended twice", ok and
              link.halts == [1], repr(link.halts))
        console = link.take_console()
        check("the echo of the input, with 0xFF", console == text,
              repr(console))
        boots = link.boots
        r2 = link.read_word(REGS + 2)
        check("the next request after the end of the input",
              r2 == len(text), f"R2 {r2:x}")
        check("the new connection's b notice", link.boots == boots + 1,
              f"{link.boots - boots}")
        ctl = link.read_word(CONTROL)
        check("the control register after the halt", ctl & HALTED != 0,
              f"{ctl:08x}")
    finally:
        link.close()


def test_run_control(port: str, prog: str, at: dict[str, int]) -> None:
    """The step and the breakpoints of the Link on test/break.nasm: a
    breakpoint at LOOP stops each of its three passes, a step from a
    paused processor goes one instruction on, and the last step at DONE
    halts."""
    link = connect(port)
    try:
        nicebin.load_words(link, nicebin.read_bin(prog))
        link.set_breaks([at["LOOP"], None, at["AFTER"]])
        nicebin.start(link)
        ok = wait_for(link, lambda: bool(link.breaks))
        check("the breakpoint's x notice", ok and link.breaks == [0],
              repr(link.breaks))
        pc = link.read_word(REGS + 15)
        r4 = link.read_word(REGS + 4)
        check("paused at LOOP before its first pass",
              pc == at["LOOP"] and r4 == 3, f"PC {pc:x} R4 {r4:x}")
        # While paused, the bytes wait in the input buffer, 2048 bytes in
        # niceemu, and the program does not read them: a send with timeout
        # 0 returns what has no room, and one with a timeout gives up
        rest = link.send_console(b"x" * 2100, timeout=0)
        check("a send to a full input buffer returns the rest",
              0 < len(rest) < 2100, f"{len(rest)} bytes")
        try:
            link.send_console(rest, timeout=0.2)
            check("a send that the program does not read is an error",
                  False)
        except LinkError as e:
            check("a send that the program does not read is an error",
                  str(e).startswith("the program's input buffer is full")
                  and str(e).endswith(f"{len(rest)} bytes not sent"),
                  str(e))
        why = link.step()
        pc = link.read_word(REGS + 15)
        check("a step", why is None and pc == at["LOOP"] + 2,
              f"{why} PC {pc:x}")
        link.control(RAM)
        ok = wait_for(link, lambda: len(link.breaks) == 2)
        r4 = link.read_word(REGS + 4)
        check("breakpoint 0 again at the second pass",
              ok and link.breaks[-1] == 0 and r4 == 2, f"R4 {r4:x}")
        link.set_breaks([None, None, at["AFTER"]])
        link.control(RAM)
        ok = wait_for(link, lambda: len(link.breaks) == 3)
        pc = link.read_word(REGS + 15)
        r7 = link.read_word(REGS + 7)
        check("breakpoint 2 at AFTER, after the routine",
              ok and link.breaks[-1] == 2 and pc == at["AFTER"] and
              r7 == 0x1234, f"PC {pc:x} R7 {r7:x}")
        link.set_breaks([])
        link.step()
        why = link.step()
        check("a step of the HALT at DONE halts", why == 1, repr(why))
    finally:
        link.close()


def command(dbg: nicedbg.Debugger, line: str) -> str:
    """What nicedbg.py prints for a line typed at its prompt, with print()
    or, as help does, on its stdout."""
    raw = io.BytesIO()
    out = io.TextIOWrapper(raw, write_through=True)
    stdout, dbg.stdout = dbg.stdout, out
    try:
        with contextlib.redirect_stdout(out):
            dbg.onecmd(dbg.precmd(line))
    finally:
        dbg.stdout = stdout
    return raw.getvalue().decode()


def go(dbg: nicedbg.Debugger, count: Callable[[Link], int]) -> str:
    """What nicedbg.py prints for a go, and shows between commands after
    it, until count(link) grows, which counts the notices of one kind. The
    notice may come while the go waits for its answer."""
    link = dbg.link
    before = count(link)
    text = command(dbg, "go")
    wait_for(link, lambda: count(link) > before)
    raw = io.BytesIO()
    out = io.TextIOWrapper(raw, write_through=True)
    with contextlib.redirect_stdout(out):
        dbg.show(dbg.pending())
    return text + raw.getvalue().decode()


def line(addr: int, words: str, text: str) -> str:
    """A line of the disassembly of d."""
    return f"{addr:08x}  {words:<35}  {text}\n"


def test_commands(port: str, prog: str, at: dict[str, int]) -> None:
    """nicedbg.py's commands on test/break.nasm, with its labels: a load,
    a breakpoint at a label and its notice, the registers, a step, set and
    pc, help on a short name, a read at label+N, a bad address, the halt,
    a set while halted, the disassembly, and the status."""
    link = connect(port)
    dbg = nicedbg.Debugger(link, nicebin.Symbols(prog.replace(".bin",
                                                              ".sym")))
    loop, done = at["LOOP"], at["DONE"]
    try:
        out = command(dbg, f"load {prog}")
        check("dbg: load", out == "loaded 19 words; the processor is held "
              "in reset\n", repr(out))
        out = command(dbg, "status")
        check("dbg: status while held", out.startswith(
            "held, ROM hidden, control 00000009, link version 1.0, "),
            repr(out))
        out = command(dbg, "b LOOP")
        check("dbg: a breakpoint at a label", out == f"0: {loop:08x} LOOP\n",
              repr(out))
        out = command(dbg, "b")
        check("dbg: the list of breakpoints", out == f"0: {loop:08x} LOOP\n",
              repr(out))
        out = go(dbg, lambda l: len(l.breaks))
        check("dbg: the breakpoint's notice", out == f"[breakpoint 0, "
              f"PC={loop:08x} LOOP  SUB[M] R4, R4, 0x1]\n", repr(out))
        out = command(dbg, "regs")
        check("dbg: the registers", "R4  00000003" in out and
              f"R15 {loop:08x}" in out, repr(out))
        command(dbg, "bd all")
        out = command(dbg, "b")
        # niceemu has four breakpoints (DEBUG.md §7.2)
        check("dbg: bd all", out == "no breakpoints; 4 free\n", repr(out))
        out = command(dbg, "bd 4")
        check("dbg: bd of a number that is no breakpoint", out ==
              "error: no breakpoint 4; they are 0 to 3\n", repr(out))
        out = command(dbg, "bd ffffffff")
        check("dbg: bd of a huge number", out ==
              "error: no breakpoint ffffffff; they are 0 to 3\n", repr(out))
        out = command(dbg, "s")
        check("dbg: a step", out == f"PC={loop + 2:08x} LOOP+0x2  ?!Z JMP "
              f"0x{loop:x}\n", repr(out))
        out = command(dbg, "set R4 2")
        check("dbg: set a register", out == "R4 00000002\n", repr(out))
        out = command(dbg, "set r0 1")
        check("dbg: set R0, which takes none", out == "R0 00000000\n",
              repr(out))
        out = command(dbg, "set R16 1")
        check("dbg: set a register that is not one", out ==
              "error: 'R16' is not R0 to R15, SP, SR, or PC\n", repr(out))
        out = command(dbg, "pc LOOP")
        check("dbg: pc at a label", out == f"PC={loop:08x} LOOP  "
              "SUB[M] R4, R4, 0x1\n", repr(out))
        command(dbg, "s")
        out = command(dbg, "regs")
        check("dbg: a step from the PC set", "R4  00000001" in out,
              repr(out))
        out = command(dbg, "help s")
        check("dbg: help on a short name", out.startswith("step (s)"),
              repr(out))
        out = command(dbg, "help wp")
        check("dbg: help without the source's indent",
              "\n " not in out, repr(out))
        out = command(dbg, "help frob")
        check("dbg: help on an unknown command", out ==
              "unknown command 'frob'; 'help' lists them\n", repr(out))
        names = [name[3:] for name in vars(nicedbg.Debugger)
                 if name.startswith("do_") and name != "do_EOF"]
        lines = command(dbg, "help").splitlines()
        check("dbg: help has a line for each command, in order",
              [line.split()[0] for line in lines[:-1]] == names,
              repr(lines))
        long = [line for line in lines if len(line) > 79]
        check("dbg: help's lines fit 79 columns", not long, repr(long))
        out = command(dbg, "r TWO+1 1")
        check("dbg: a read at label+N",
              out == f"{at['TWO'] + 1:08x}: 12345678\n", repr(out))
        out = command(dbg, "r NOPE")
        check("dbg: a bad address", out ==
              "error: 'NOPE' is not a label or a hex number\n", repr(out))
        out = command(dbg, "w FFFFFFF0 0")
        check("dbg: w refuses the control register", out ==
              "error: use ctl to write the control register\n", repr(out))
        out = command(dbg, "frob")
        check("dbg: an unknown command", out ==
              "unknown command 'frob'; 'help' lists them\n", repr(out))
        out = go(dbg, lambda l: len(l.halts))
        check("dbg: the halt's notice", out ==
              f"[halted: HALT, PC={done + 1:08x} V3]\n", repr(out))
        out = command(dbg, "set R1 0")
        check("dbg: set while halted", out ==
              "error: the processor is not paused; 'pause' first\n",
              repr(out))
        out = command(dbg, "d LOOP 2")
        check("dbg: the disassembly at a label", out == "LOOP:\n" +
              line(loop, "02210230 00000001", "SUB[M] R4, R4, 0x1") +
              line(loop + 2, "bc9ffffd", "?!Z JMP 0x4"),
              repr(out))
        # MOVE R5, with its constant word at DONE
        command(dbg, "w DONE-1 00015800")
        out = command(dbg, "d DONE-1 2")
        check("dbg: no instruction spans a label", out ==
              line(done - 1, "00015800",
                   ".DAT 0x00015800 ; MOVE R5, ? (cut off)") +
              "DONE:\n" + line(done, "0c000000", "HALT"), repr(out))
        out = command(dbg, "load /nonexistent.bin")
        check("dbg: a load of a missing file", out.endswith(
            "cannot read /nonexistent.bin: No such file or directory\n"),
            repr(out))
    finally:
        dbg.stop()
        link.close()


def test_watch(port: str, prog: str, at: dict[str, int]) -> None:
    """nicedbg.py's watchpoints on test/watch.nasm: wp and its list, the
    notice of a write's hit, a step that reads, the status, two reads in
    one step, the errors, and wpd."""
    link = connect(port)
    dbg = nicedbg.Debugger(link, nicebin.Symbols(prog.replace(".bin",
                                                              ".sym")))
    data, read, add2 = at["DATA"], at["READ"], at["ADD2"]
    try:
        command(dbg, f"load {prog}")
        out = command(dbg, "wp DATA")
        check("dbg: a watchpoint of the writes", out ==
              f"0: {data:08x} DATA w\n", repr(out))
        out = command(dbg, "wp")
        check("dbg: the list of watchpoints", out ==
              f"0: {data:08x} DATA w\n", repr(out))
        out = go(dbg, lambda l: len(l.watches))
        check("dbg: the notice of a write's hit", out ==
              f"[watchpoint 0, hit at 00000000 START, PC={read:08x} READ  "
              f"MOVE R2, @0x{data:x}]\n", repr(out))
        out = command(dbg, "r DATA 1")
        check("dbg: the word written", out == f"{data:08x}: 00000005\n",
              repr(out))
        command(dbg, "wpd 0")
        out = command(dbg, "wp DATA r")
        check("dbg: a watchpoint of the reads", out ==
              f"0: {data:08x} DATA r\n", repr(out))
        out = command(dbg, "s")
        check("dbg: a step that reads", out ==
              f"watchpoint 0, hit at {read:08x} READ, PC={add2:08x} ADD2  "
              f"ADD R3, @0x{data:x}, @0x{data:x}\n", repr(out))
        out = command(dbg, "status")
        check("dbg: status at a watchpoint", out.startswith(
            f"at watchpoint 0, hit at {read:08x} READ, ROM hidden, "),
            repr(out))
        out = command(dbg, "wp DATA rw")
        check("dbg: a second watchpoint, of both", out ==
              f"1: {data:08x} DATA rw\n", repr(out))
        out = command(dbg, "s")
        check("dbg: two hits in one step, the lowest number", out.startswith(
            f"watchpoint 0, hit at {add2:08x} ADD2, PC="), repr(out))
        out = command(dbg, "wp DATA x")
        check("dbg: wp of a kind that is none", out ==
              "error: give the address, and r, w, or rw\n", repr(out))
        out = command(dbg, "wpd 4")
        check("dbg: wpd of a number that is no watchpoint", out ==
              "error: no watchpoint 4; they are 0 to 3\n", repr(out))
        command(dbg, "wpd all")
        out = command(dbg, "wp")
        # niceemu has four watchpoints (DEBUG.md §7.2)
        check("dbg: wpd all", out == "no watchpoints; 4 free\n", repr(out))
        out = go(dbg, lambda l: len(l.halts))
        check("dbg: the halt after them", out.startswith("[halted: HALT"),
              repr(out))
        command(dbg, "wp DATA")
        command(dbg, f"load {prog}")
        out = command(dbg, "wp")
        check("dbg: load disables the watchpoints", out ==
              "no watchpoints; 4 free\n", repr(out))
    finally:
        dbg.stop()
        link.close()


def test_program(port: str, prog: str) -> None:
    """nicedbg.py as a program, with --symbols, a file to load, and its
    commands on stdin, which ends with q."""
    sym = prog.replace(".bin", ".sym")
    p = subprocess.run([sys.executable, os.path.join(TOOLS, "nicedbg.py"),
                        "--tcp", port, "--symbols", sym, prog],
                       input="b DONE\ng\nregs\nq\n", capture_output=True,
                       text=True, timeout=30)
    out = p.stdout
    check("nicedbg.py: exit status 0", p.returncode == 0,
          f"{p.returncode} {p.stderr!r}")
    check("nicedbg.py: the load at the start",
          out.startswith("loaded 19 words"), repr(out))
    check("nicedbg.py: the breakpoint at DONE", "[breakpoint 0, PC=" in out
          and " DONE  HALT]" in out, repr(out))
    check("nicedbg.py: R6 of AFTER and R7 of the routine",
          "R6  00000007" in out and "R7  00001234" in out, repr(out))


def test_options(port: str, prog: str) -> None:
    """add_options() on a parser with another program name and
    description, as a front end's subcommand builds it, and run() on what
    it parses, with an open_link and a load of its own, and its commands
    on stdin."""
    parser = argparse.ArgumentParser(prog="front.py mon",
                                     description="The front end's monitor.")
    nicedbg.add_options(parser)
    text = parser.format_help()
    check("add_options: the program name and description",
          text.startswith("usage: front.py mon ")
          and "The front end's monitor." in text, repr(text))
    check("add_options: the link's options, --symbols, and the file",
          all(opt in text for opt in ("--tcp", "--port", "--symbols",
                                      "file")), repr(text))
    sym = prog.replace(".bin", ".sym")
    args = parser.parse_args(["--tcp", port, "--symbols", sym, prog])
    opened: list[str] = []
    loaded: list[str] = []

    def open_link(args: argparse.Namespace) -> Link:
        opened.append(args.tcp)
        return nicelink.open_link(args)

    def load(link: Link, path: str) -> int:
        loaded.append(path)
        return nicedbg.plain_load(link, path)

    # run() writes the console's bytes to the buffer under sys.stdout
    raw = io.BytesIO()
    out = io.TextIOWrapper(raw, write_through=True)
    stdin = sys.stdin
    sys.stdin = io.StringIO("b DONE\ng\nregs\nq\n")
    try:
        with contextlib.redirect_stdout(out):
            nicedbg.run(args, open_link, load)
    finally:
        sys.stdin = stdin
    out.flush()
    text = raw.getvalue().decode()
    check("run: the hooks", opened == [port] and loaded == [prog],
          f"{opened} {loaded}")
    check("run: the load, the breakpoint at DONE, and the registers",
          text.startswith("loaded 19 words") and " DONE  HALT]" in text
          and "R7  00001234" in text, repr(text))


def read_until(fd: int, want: bytes, seen: bytearray, start: int = 0) -> bool:
    """Reads fd into seen until seen[start:] holds want, at most WAIT
    seconds."""
    end = time.monotonic() + WAIT
    while want not in seen[start:] and time.monotonic() < end:
        ready, _, _ = select.select([fd], [], [], end - time.monotonic())
        if ready:
            try:
                seen += os.read(fd, 1024)
            except OSError:     # EIO: the other side has closed
                break
    return want in seen[start:]


def test_console(port: str, echo: str) -> None:
    """nicedbg.py's console on a pseudo-terminal, which starts with the
    default modes, ICRNL among them, as a terminal does, on
    test/echo.nasm. The keys a, CR, and b must reach the program as
    typed, and come back from it: a CR made LF would come back as CR LF,
    by the terminal's output modes."""
    master, slave = pty.openpty()
    p = subprocess.Popen([sys.executable, os.path.join(TOOLS, "nicedbg.py"),
                          "--tcp", port, echo],
                         stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    seen = bytearray()
    try:
        os.write(master, b"g\nc\n")
        # The keys go after the console has set the modes, as the line
        # discipline changes them as they arrive: the console prints its
        # line once they are set
        started = read_until(master, b"returns to the prompt", seen)
        check("console: started", started, repr(bytes(seen)))
        os.write(master, b"a\rb")
        echoed = read_until(master, b"a\rb", seen)
        check("console: Enter reaches the program as CR",
              echoed and b"a\r\nb" not in seen, repr(bytes(seen)))
        # The keys after Ctrl-] in the same read are dropped, so q waits
        # for the prompt
        mark = len(seen)
        os.write(master, bytes([nicedbg.CONSOLE_END]))
        read_until(master, b"dbg> ", seen, mark)
        os.write(master, b"q\n")
        p.wait(timeout=10)
        check("console: Ctrl-] and q", p.returncode == 0,
              f"{p.returncode} {bytes(seen)!r}")
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        os.close(master)


def main() -> None:
    argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter).parse_args()
    if not os.path.exists(NICEEMU):
        sys.exit(f"link.py: {NICEEMU} is missing; run "
                 "'make -C ../emulator build'")
    test_parse_tcp()
    test_pending()
    with tempfile.TemporaryDirectory() as tmp:
        echo, _ = assemble("echo", tmp)
        prog, at = assemble("break", tmp)
        watch, watch_at = assemble("watch", tmp)
        with emulator() as port:
            test_link(port, echo)
            test_run_control(port, prog, at)
            test_commands(port, prog, at)
            test_watch(port, watch, watch_at)
            test_program(port, prog)
            test_options(port, prog)
            test_console(port, echo)
    passed = sum(results)
    print(f"{passed}/{len(results)} passed")
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
