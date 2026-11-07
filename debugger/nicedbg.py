#!/usr/bin/env python3
"""nicedbg: an interactive debugger on the debug link of doc/DEBUG.md.

It reads and writes memory, loads a .bin file, starts, holds, pauses,
steps, and goes on, sets the breakpoints, shows and sets the registers,
and disassembles, with one short command each. "help" lists them. Numbers
are hex, with or without 0x. An empty line repeats a step.

The disassembler is assembler/nicedis.py. --symbols FILE, or the command
"symbols FILE", reads the labels of niceasm.py --symbols or nicebuild.py:
an address may then be a label, or a label+N or label-N, and the labels
are shown in what is printed.

The program's console output and the link's notices are shown as they
arrive, above the prompt. "send TEXT" sends console bytes to the program,
and "console" passes the terminal through to it, until Ctrl-] returns to
the prompt.

Usage: nicedbg.py (--tcp [HOST:]PORT | --port DEVICE [--baud 230400])
                  [--symbols FILE] [FILE.bin]

--tcp talks to niceemu --link, and --port to a system on its UART. A
FILE is read before the link opens, and loaded with the processor held.
A board adds its own transports and the checks of its memory by calling
main() with hooks of its own. Only the Python standard library is used,
so this runs on Linux and macOS.
"""

from __future__ import annotations

import argparse
import cmd
import codecs
import os
import select
import sys
import termios
import threading
from typing import Callable

try:
    import readline
    HAVE_READLINE = True
except ImportError:
    HAVE_READLINE = False

# The disassembler, next to niceasm.py. Its disassemble(addr, read,
# symbols) decodes the instruction at addr, with read(a) giving the word at
# a, or None where there is none, and symbols an optional {address: name}.
# It returns the text and the number of words it takes.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))), "assembler"))
import nicedis  # noqa: E402

from nicebin import Symbols, load_words, read_bin  # noqa: E402
from nicelink import (BRK_ADDR, BRK_COUNT, BRK_EN, CONTROL, FREE,  # noqa: E402
                      HALT_REASON, HALTED, HOLD, MAX_WORDS, PAUSE, RAM,
                      REASONS, REGS, STOP, VERSION, Link, LinkError,
                      add_arguments, open_link)

# The commands' short names
ALIASES = {
    "s": "step",
    "g": "go",
    "c": "console",
    "q": "quit",
    "exit": "quit",
}

# The registers with a name of their own (ISA §1.2)
REG_NAMES = {"sp": 13, "sr": 14, "pc": 15}

# Ctrl-], which ends the console
CONSOLE_END = 0x1D

# The steps that a step command prints one by one, the words a line of a
# read shows, and the most words of an instruction (ISA §2.3), with a
# constant word for each of its two sources and its destination
STEP_LINES = 16
LINE_WORDS = 8
MAX_INSTR = 4
MASK = 0xFFFFFFFF

# Loads the .bin file at a path into the memory, with the processor held,
# and returns the number of words. A board's checks its memory too.
Loader = Callable[[Link, str], int]


def number(text: str) -> int:
    """A hex number, with or without 0x."""
    try:
        value = int(text, 16)
    except ValueError:
        raise ValueError(f"'{text}' is not a hex number") from None
    if not 0 <= value <= 0xFFFFFFFF:
        raise ValueError(f"'{text}' does not fit in 32 bits")
    return value


def plain_load(link: Link, path: str) -> int:
    """The loader of a system whose memory takes any address, as niceemu's
    does."""
    words = read_bin(path)
    load_words(link, words)
    return len(words)


class Words:
    """The memory for the disassembler, which asks for one word at a time:
    blocks of words read over the link, and kept for the command that
    reads them."""

    def __init__(self, link: Link, block: int) -> None:
        self.link = link
        self.block = block
        self.words: dict[int, int] = {}

    def __call__(self, addr: int) -> int:
        if addr not in self.words:
            # A block does not wrap past the top of the address space.
            words = self.link.read(addr, min(self.block, MASK + 1 - addr))
            for i, w in enumerate(words):
                self.words[addr + i] = w
        return self.words[addr]


class Debugger(cmd.Cmd):
    """The shell. A thread shows what arrives while the prompt waits, and
    the lock keeps it off the link while a command runs."""

    def __init__(self, link: Link, symbols: Symbols | None = None,
                 load: Loader = plain_load) -> None:
        super().__init__()
        self.link = link
        self.load = load
        self.symbols: Symbols | None = None
        self.labels: dict[str, int] = {}
        self.first: dict[int, str] = {}
        if symbols is not None:
            self._use(symbols)
        self.prompt = "dbg> "
        # Reentrant, as an empty line runs the step again inside onecmd
        self.lock = threading.RLock()
        self.at_prompt = False
        self.watcher: threading.Thread | None = None
        self.stopping = threading.Event()
        self.next_read = 0
        # Where d goes on: after the last d, or at the PC of the last stop
        self.next_dis = 0
        self.last = ""
        # The notices already shown
        self.seen = self._counts()

    # What arrives

    def _counts(self) -> tuple[int, int, int, int, int, int]:
        link = self.link
        return (link.pauses, len(link.breaks), len(link.halts), link.boots,
                link.overflows, link.bad)

    def _pc(self, instr: bool = False) -> str:
        """The PC, its label, and with instr the instruction there, for a
        processor that is paused; a halted one has run the instruction
        before the PC."""
        try:
            pc = self.link.read_word(REGS + 15)
        except LinkError:
            return "PC unknown"
        text = f"PC={self._where(pc)}"
        if instr:
            self.next_dis = pc
            try:
                read = Words(self.link, MAX_INSTR)
                text += f"  {self._instr(read, pc)[0]}"
            except LinkError:
                pass
        return text

    def pending(self, line_open: bool = False) -> bytes:
        """The console bytes that have arrived, and a line for each notice
        that has, on a line of its own. line_open is whether the output
        shown last ended inside a line. The lock is held."""
        data = self.link.take_console()
        pauses, breaks, halts, boots, overflows, bad = self.seen
        link = self.link
        lines = []
        lines += ["boot"] * (link.boots - boots)
        lines += ["input overflow"] * (link.overflows - overflows)
        lines += ["bad packet dropped"] * (link.bad - bad)
        for why in link.halts[halts:]:
            lines.append(f"halted: {REASONS.get(why, why)}, {self._pc()}")
        for n in link.breaks[breaks:]:
            lines.append(f"breakpoint {n}, {self._pc(True)}")
        if link.pauses - pauses > len(link.breaks) - breaks:
            lines.append(f"paused, {self._pc(True)}")
        self.seen = self._counts()
        for line in lines:
            if data[-1:] not in (b"", b"\n") or (not data and line_open):
                data += b"\n"
            data += f"[{line}]\n".encode()
        return data

    def show(self, data: bytes) -> None:
        """Shows what arrived on lines of its own, and the prompt again,
        with what was typed, if it waits."""
        if not data:
            return
        out = sys.stdout
        if self.at_prompt:
            out.write("\r\x1b[K")
        out.flush()
        out.buffer.write(data if data.endswith(b"\n") else data + b"\n")
        out.buffer.flush()
        if self.at_prompt:
            typed = readline.get_line_buffer() if HAVE_READLINE else ""
            out.write(self.prompt + typed)
        out.flush()

    def watch(self) -> None:
        """The thread that shows what arrives between commands, until
        stop(). The descriptor is taken on each turn, as the one of --tcp
        changes after "eof". A command may still close it before the
        select, which then fails or sees another descriptor of the same
        number; the poll, with the lock held, finds out."""
        while not self.stopping.is_set():
            with self.lock:
                fd = self.link.fileno()
            try:
                select.select([fd], [], [], 0.05)
            except (OSError, ValueError):
                pass
            with self.lock:
                try:
                    self.link.poll(0)
                    data = self.pending()
                except (LinkError, OSError) as e:
                    data = f"[{e}]\n".encode()
            self.show(data)

    def stop(self) -> None:
        """Ends the watcher, so the link can be closed."""
        self.stopping.set()
        if self.watcher is not None:
            self.watcher.join()

    # The loop

    def preloop(self) -> None:
        if self.watcher is None:
            self.watcher = threading.Thread(target=self.watch, daemon=True)
            self.watcher.start()
        self.at_prompt = True

    def precmd(self, line: str) -> str:
        self.at_prompt = False
        words = line.split(maxsplit=1)
        if words and words[0] in ALIASES:
            words[0] = ALIASES[words[0]]
            line = " ".join(words)
        return line

    def do_help(self, arg: str) -> None:
        """help [CMD]: lists the commands, or describes one, also by its
        short name."""
        super().do_help(ALIASES.get(arg.strip(), arg.strip()))

    def onecmd(self, line: str) -> bool:
        with self.lock:
            try:
                stop = super().onecmd(line)
            except (LinkError, ValueError) as e:
                print(f"error: {e}")
                stop = False
            except SystemExit as e:
                # The fail() of nicebin.py, for a bad file
                print(e.code)
                stop = False
            except KeyboardInterrupt:
                print("^C")
                stop = False
            self.show(self.pending())
        return stop

    def postcmd(self, stop: bool, line: str) -> bool:
        self.at_prompt = True
        return stop

    def emptyline(self) -> bool:
        if self.last.split()[:1] == ["step"]:
            return self.onecmd(self.last)
        return False

    def default(self, line: str) -> None:
        print(f"unknown command '{line.split()[0]}'; 'help' lists them")

    def parseline(self, line: str) -> tuple[str | None, str | None, str]:
        command, arg, line = super().parseline(line)
        if line:
            self.last = line
        return command, arg, line

    # Helpers

    def _use(self, symbols: Symbols) -> None:
        """Takes the labels of a .sym file: by name, the first of a name
        that is there twice, and by address, the first of those at one
        address."""
        self.symbols = symbols
        self.labels = {}
        self.first = {}
        for addr, name in zip(symbols.addrs, symbols.names):
            self.labels.setdefault(name, addr)
            self.first.setdefault(addr, name)

    def address(self, text: str) -> int:
        """A hex number, or, with symbols, a label, label+N, or label-N,
        with N in hex. A label comes before a hex number that is spelled
        the same, such as "add"; a number with 0x is always one."""
        if self.labels and text[:2] not in ("0x", "0X"):
            if text in self.labels:
                return self.labels[text]
            for sign in "+-":
                name, _, offset = text.rpartition(sign)
                if name in self.labels:
                    step = number(offset)
                    return (self.labels[name] +
                            (step if sign == "+" else -step)) & MASK
            try:
                return number(text)
            except ValueError:
                raise ValueError(f"'{text}' is not a label or a hex "
                                 "number") from None
        return number(text)

    def _instr(self, read: Callable[[int], int], addr: int) -> tuple[str, int]:
        """The text of the instruction at addr, and its number of words. An
        instruction never spans a label, as in nicedis's listing: a word at
        a label after addr is missing, which makes the words before it a
        .DAT, and the next instruction starts at the label."""
        def word(a: int) -> int | None:
            return None if a != addr and a in self.first else read(a)
        return nicedis.disassemble(addr, word, self.first or None)

    def _rom_bit(self) -> int:
        """Bit 3 of the control register, which every write keeps."""
        return self.link.read_word(CONTROL) & RAM

    def _wait_notice(self, pauses: int, halts: int) -> None:
        """Waits for the p, x, or h that a pause request brings, after
        pauses and halts of them."""
        wait = 2 * self.link.transport.answer_wait(0)
        while self.link.pauses == pauses and len(self.link.halts) == halts:
            if not self.link.poll(wait):
                print("no pause yet; 'status' shows when it takes effect")
                return

    def _where(self, addr: int) -> str:
        """An address, and its label with symbols."""
        if self.symbols is None or not self.symbols.addrs:
            return f"{addr:08x}"
        where = self.symbols.location(addr)
        return f"{addr:08x}" + ("" if where == f"{addr:08x}" else f" {where}")

    def _regs(self) -> None:
        regs = self.link.read(REGS, 16)
        for row in range(4):
            print(" ".join(f"R{i:<2} {regs[i]:08x}"
                           for i in range(4 * row, 4 * row + 4)))

    # The commands

    def do_status(self, arg: str) -> None:
        """status: the state of the processor, the ROM, and the link."""
        link = self.link
        ctl = link.read_word(CONTROL)
        version = link.read_word(VERSION)
        if ctl & HALTED:
            why = link.read_word(HALT_REASON)
            state = f"halted: {REASONS.get(why, why)}"
            # A hold after a halt keeps bit 1 and the reason, until a
            # clear (link version 5), as by load.
            if ctl & HOLD:
                state = f"held, after a halt: {REASONS.get(why, why)}"
        elif ctl & HOLD:
            state = "held"
        elif ctl & PAUSE:
            # open_link has checked the major, so the minor tells.
            stop = link.read_word(STOP) if (version & 0xF) >= 4 else 0
            state = f"at breakpoint {stop & 0xFF}" if stop & 0x100 \
                else "paused"
        else:
            state = "running"
        rom = "hidden" if ctl & RAM else "shown"
        print(f"{state}, ROM {rom}, control {ctl:08x}, link version "
              f"{version >> 4}.{version & 0xF}, input free "
              f"{link.read_word(FREE)}")
        if ctl & HALTED:
            print(self._pc())
        elif ctl & PAUSE:
            print(self._pc(not ctl & HOLD))

    def do_regs(self, arg: str) -> None:
        """regs: R0 to R15: live while the processor runs, and the stop's
        while it is paused or has halted (DEBUG.md §6)."""
        self._regs()

    def do_r(self, arg: str) -> None:
        """r [ADDR [N]]: reads N words from ADDR, 16 by default. Without
        ADDR, it goes on after the last read."""
        args = arg.split()
        addr = self.address(args[0]) if args else self.next_read
        n = number(args[1]) if len(args) > 1 else 16
        words = self.link.read(addr, n)
        for i in range(0, n, LINE_WORDS):
            line = words[i:i + LINE_WORDS]
            print(f"{(addr + i) & 0xFFFFFFFF:08x}: " +
                  " ".join(f"{w:08x}" for w in line))
        self.next_read = (addr + n) & 0xFFFFFFFF

    def do_w(self, arg: str) -> None:
        """w ADDR WORD...: writes the words from ADDR. The control register
        has the commands hold, go, pause, step, and ctl."""
        args = arg.split()
        if len(args) < 2:
            raise ValueError("give an address and at least one word")
        addr, words = self.address(args[0]), [number(a) for a in args[1:]]
        if addr <= CONTROL <= addr + len(words) - 1:
            raise ValueError("use ctl to write the control register")
        self.link.write(addr, words)

    def _register(self, text: str) -> int:
        """The number of a register: R0 to R15, or SP, SR, or PC, in
        either case."""
        name = text.lower()
        if name in REG_NAMES:
            return REG_NAMES[name]
        if name[:1] == "r" and name[1:].isdecimal() and int(name[1:]) < 16:
            return int(name[1:])
        raise ValueError(f"'{text}' is not R0 to R15, SP, SR, or PC")

    def _write_reg(self, n: int, value: int) -> int:
        """Writes register n of a paused processor, which link version 6
        allows (DEBUG.md §6), and returns what it reads back: R0 stays 0,
        and R14 keeps bit 24 set."""
        link = self.link
        version = link.read_word(VERSION)
        if (version & 0xF) < 6:
            raise ValueError(f"link version {version >> 4}.{version & 0xF} "
                             "cannot write the registers; 0.6 can")
        if not link.read_word(CONTROL) & PAUSE:
            raise ValueError("the processor is not paused; 'pause' first")
        link.write(REGS + n, [value])
        return link.read_word(REGS + n)

    def do_set(self, arg: str) -> None:
        """set Rn VALUE: writes a register of a paused processor, as an
        instruction would: R0 stays 0, bit 24 of R14 stays 1, and R15 is
        where the processor goes on. SP, SR, and PC name R13, R14, and R15,
        and VALUE may be a label."""
        args = arg.split()
        if len(args) != 2:
            raise ValueError("give a register and a value")
        n = self._register(args[0])
        value = self.address(args[1])
        got = self._write_reg(n, value)
        if n == 15:
            print(self._pc(True))
        else:
            print(f"R{n} {got:08x}")

    def do_pc(self, arg: str) -> None:
        """pc [ADDR]: shows the PC of a paused processor and its
        instruction, or sets the PC to ADDR, where the processor goes on at
        the next go or step. A PC set onto a breakpoint runs its
        instruction."""
        if arg.strip():
            self._write_reg(15, self.address(arg.strip()))
        elif not self.link.read_word(CONTROL) & PAUSE:
            raise ValueError("the processor is not paused; 'pause' first")
        print(self._pc(True))

    def do_ctl(self, arg: str) -> None:
        """ctl [VALUE]: reads the control register, or writes it."""
        if arg.strip():
            self.link.control(number(arg.strip()))
        print(f"control {self.link.read_word(CONTROL):08x}")

    def do_load(self, arg: str) -> None:
        """load FILE: holds the processor, hides the ROM, clears the memory,
        disables the breakpoints, and loads the .bin file. 'go' starts
        it."""
        if not arg.strip():
            raise ValueError("give the .bin file")
        n = self.load(self.link, arg.strip())
        print(f"loaded {n} words; the processor is held in reset")

    def do_run(self, arg: str) -> None:
        """run: starts the program at 0 again, from a hold, a halt, a pause,
        or while it runs. The memory is not loaded again."""
        rom = self._rom_bit()
        self.link.control(HOLD | rom)
        self.link.control(rom)

    def do_hold(self, arg: str) -> None:
        """hold: holds the processor in reset. A hold of a paused processor
        keeps R0-R15, and a hold of a running one leaves them undefined."""
        self.link.control(HOLD | self._rom_bit())

    def do_go(self, arg: str) -> None:
        """go (g): goes on from a pause, or starts a held processor at 0."""
        self.link.control(self._rom_bit())

    def do_pause(self, arg: str) -> None:
        """pause: pauses the running processor, and shows where."""
        rom = self._rom_bit()
        # The notice may come while control() waits for its answer.
        pauses, halts = self.link.pauses, len(self.link.halts)
        self.link.control(PAUSE | rom)
        self._wait_notice(pauses, halts)

    def do_step(self, arg: str) -> None:
        """step (s) [N]: runs N steps of a paused processor, 1 by default,
        and shows the PC after each, up to 16. It stops at a breakpoint and
        at a halt. An empty line steps again."""
        link = self.link
        n = number(arg.strip()) if arg.strip() else 1
        ctl = link.read_word(CONTROL)
        if not ctl & PAUSE:
            raise ValueError("the processor is not paused; 'pause' first")
        for i in range(n):
            breaks = len(link.breaks)
            why = link.step(PAUSE | (ctl & RAM))
            # The step prints what it ends in, not the notice watcher.
            self.show(link.take_console())
            self.seen = self._counts()
            if why is not None:
                print(f"halted: {REASONS.get(why, why)}, {self._pc()}")
                return
            if len(link.breaks) > breaks:
                print(f"breakpoint {link.breaks[-1]}, {self._pc(True)}")
                return
            if n <= STEP_LINES or i == n - 1:
                print(self._pc(True))

    def do_d(self, arg: str) -> None:
        """d [ADDR [N]]: disassembles N instructions from ADDR, 16 by
        default, with the labels before them. Without ADDR, it goes on
        after the last d, or at the PC of the last pause, step, or
        breakpoint. The disassembler does not tell code from data."""
        args = arg.split()
        addr = self.address(args[0]) if args else self.next_dis
        n = number(args[1]) if len(args) > 1 else 16
        read = Words(self.link, min(MAX_INSTR * n, MAX_WORDS))
        for _ in range(n):
            if self.symbols is not None:
                for a, name in zip(self.symbols.addrs, self.symbols.names):
                    if a == addr:
                        print(f"{name}:")
            text, size = self._instr(read, addr)
            words = " ".join(f"{read((addr + i) & MASK):08x}"
                             for i in range(size))
            print(f"{addr:08x}  {words:<{9 * MAX_INSTR - 1}}  {text}")
            addr = (addr + size) & MASK
        self.next_dis = addr

    def do_symbols(self, arg: str) -> None:
        """symbols [FILE]: reads the labels of a .sym file, of niceasm.py
        --symbols or nicebuild.py, in place of those read before. Without
        FILE, it shows how many labels there are."""
        if arg.strip():
            self._use(Symbols(arg.strip()))
        n = len(self.symbols.addrs) if self.symbols is not None else 0
        print(f"{n} labels")

    def do_b(self, arg: str) -> None:
        """b [ADDR]: sets a breakpoint at ADDR in a free slot, or, without
        ADDR, lists them."""
        link = self.link
        count = link.read_word(BRK_COUNT)
        if count == 0:
            raise ValueError("this system has no breakpoints")
        en = link.read_word(BRK_EN)
        addrs = link.read(BRK_ADDR, count)
        if not arg.strip():
            for i in range(count):
                if en >> i & 1:
                    print(f"{i}: {self._where(addrs[i])}")
            if not en:
                print(f"no breakpoints; {count} free")
            return
        addr = self.address(arg.strip())
        free = [i for i in range(count) if not en >> i & 1]
        if not free:
            raise ValueError(f"all {count} breakpoints are set; 'bd' one")
        link.write(BRK_ADDR + free[0], [addr])
        link.write(BRK_EN, [en | 1 << free[0]])
        print(f"{free[0]}: {self._where(addr)}")

    def do_bd(self, arg: str) -> None:
        """bd N|all: disables breakpoint N, or all of them."""
        if arg.strip() == "all":
            self.link.write(BRK_EN, [0])
            return
        if not arg.strip():
            raise ValueError("give the breakpoint's number, or all")
        en = self.link.read_word(BRK_EN)
        self.link.write(BRK_EN, [en & ~(1 << number(arg.strip()))])

    def do_send(self, arg: str) -> None:
        r"""send TEXT: sends the text to the program, with escapes such as
        \n, \r, and \x1b."""
        text = codecs.decode(arg, "unicode_escape")
        self.link.send_console(text.encode("latin-1"))

    def do_eof(self, arg: str) -> None:
        """eof: ends the program's input, as the end of a file does."""
        self.link.end_input()

    def do_console(self, arg: str) -> None:
        """console (c): passes the terminal through to the program, the keys
        to its input and its output to the screen, until Ctrl-]."""
        fd = sys.stdin.fileno()
        if not os.isatty(fd):
            raise ValueError("the console needs a terminal; 'send' sends "
                             "text without one")
        old = termios.tcgetattr(fd)
        new = termios.tcgetattr(fd)
        new[0] &= ~termios.IXON
        new[3] &= ~(termios.ICANON | termios.ECHO | termios.ISIG |
                    termios.IEXTEN)
        new[6][termios.VMIN] = 1
        new[6][termios.VTIME] = 0
        print("console; Ctrl-] returns to the prompt")
        link = self.link
        line_open = False
        try:
            termios.tcsetattr(fd, termios.TCSANOW, new)
            while True:
                data = self.pending(line_open)
                if data:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
                    line_open = not data.endswith(b"\n")
                ready, _, _ = select.select([fd, link.fileno()], [], [], 0.1)
                if link.fileno() in ready:
                    link.poll(0)
                if fd in ready:
                    keys = os.read(fd, 1024)
                    end = keys.find(bytes([CONSOLE_END]))
                    if end >= 0:
                        link.send_console(keys[:end])
                        break
                    link.send_console(keys)
        finally:
            termios.tcsetattr(fd, termios.TCSANOW, old)
            if line_open:
                print()

    def do_quit(self, arg: str) -> bool:
        """quit (q): leaves the processor as it is, and quits."""
        return True

    def do_EOF(self, arg: str) -> bool:
        """Ctrl-D quits."""
        print()
        return True


def main(argv: list[str] | None = None,
         add_link_arguments: Callable[[argparse.ArgumentParser], object]
         = add_arguments,
         open_link: Callable[[argparse.Namespace], Link] = open_link,
         load: Loader = plain_load,
         check_file: Callable[[str], object] = read_bin) -> None:
    """Runs the debugger. A board passes its own add_link_arguments and
    open_link, for its transports, load, for the checks of its memory,
    and check_file, which stops on a file that it cannot load before the
    link opens."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split(
        "\n")[0])
    add_link_arguments(parser)
    parser.add_argument("--symbols", metavar="FILE",
                        help="read the labels of niceasm.py --symbols or "
                        "nicebuild.py from FILE: lines of 'address name'")
    parser.add_argument("file", nargs="?",
                        help="a .bin file to load, with the processor held: "
                        "one 'address word' hex pair per line")
    args = parser.parse_args(argv)

    symbols = Symbols(args.symbols) if args.symbols else None
    if args.file:
        check_file(args.file)
    link = open_link(args)
    dbg = Debugger(link, symbols, load)
    dbg.onecmd(f"load {args.file}" if args.file else "status")
    dbg.intro = "'help' lists the commands, and 'q' quits."
    while True:
        try:
            dbg.cmdloop()
            break
        except KeyboardInterrupt:
            print("^C")
            dbg.intro = None
    dbg.stop()
    link.close()


if __name__ == "__main__":
    main()
