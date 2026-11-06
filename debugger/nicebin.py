#!/usr/bin/env python3
"""The files that nicedbg.py reads, and the loading of a program over the
debug link (doc/DEBUG.md).

read_bin() reads a .bin file, of niceasm.py -o or nicebuild.py, and takes
the lines that niceemu takes. Symbols reads a .sym file, of niceasm.py
--symbols or nicebuild.py, and names an address as niceemu does.
load_words() holds the processor, clears the memory, disables the
breakpoints, and writes the words of a program; start() starts it. A
board whose memory does not reach every address passes a check of its
own to load_words(), which refuses the words that it has no room for.

Only the Python standard library is used.
"""

from __future__ import annotations

import bisect
from typing import Callable

from nicelink import BRK_EN, CLEAR, HOLD, RAM, Link, fail

# A word of a program: (address, word)
Words = list[tuple[int, int]]
# A check of the words against the memory of the system, which may read
# its registers over the link while the processor is held, and stops with
# fail() on a word that does not fit
FitCheck = Callable[[Link, Words], None]

HEX_DIGITS = "0123456789abcdefABCDEF"


def hex_field(path: str, line_no: int, text: str) -> int:
    """A field of a .bin file: 1 to 8 hex digits, as niceemu takes them."""
    if not text or not all(c in HEX_DIGITS for c in text):
        fail(f"{path}:{line_no}: '{text}' is not a hex number")
    if len(text) > 8:
        fail(f"{path}:{line_no}: '{text}' has more than 8 hex digits")
    return int(text, 16)


def read_lines(path: str) -> list[tuple[int, list[str]]]:
    """The lines of a .bin or .sym file that are not blank, as (line number,
    fields), split as niceemu splits them: lines at LF only, with blanks,
    tabs, and CRs stripped, and fields at blanks and tabs only. A byte that
    is not ASCII stays in its field as an escape, which no field takes."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        fail(f"cannot read {path}: {e.strerror}")
    lines = []
    for line_no, raw in enumerate(data.split(b"\n"), 1):
        line = raw.strip(b" \t\r").decode("ascii", "backslashreplace")
        fields = [f for f in line.replace("\t", " ").split(" ") if f]
        if fields:
            lines.append((line_no, fields))
    return lines


def read_bin(path: str) -> Words:
    """The words of a .bin file, as (address, word). It takes the lines that
    niceemu takes: two fields of 1 to 8 hex digits each, with no address
    repeated, and at least one word."""
    words: Words = []
    seen: dict[int, int] = {}
    for line_no, fields in read_lines(path):
        if len(fields) < 2:
            fail(f"{path}:{line_no}: expected 'address word', "
                 f"found only '{fields[0]}'")
        if len(fields) > 2:
            fail(f"{path}:{line_no}: unexpected '{fields[2]}' after the word")
        addr = hex_field(path, line_no, fields[0])
        word = hex_field(path, line_no, fields[1])
        if addr in seen:
            fail(f"{path}:{line_no}: address {addr:08x} is already "
                 f"loaded by line {seen[addr]}")
        seen[addr] = line_no
        words.append((addr, word))
    if not words:
        fail(f"{path}: no words to load; is it a .bin file, as niceasm.py "
             f"writes with -o?")
    return words


class Symbols:
    """The labels of a file that niceasm.py --symbols writes, lines of
    "address name", for naming an address as niceemu does."""

    def __init__(self, path: str) -> None:
        symbols = []
        for line_no, fields in read_lines(path):
            where = f"{path}:{line_no}"
            if len(fields) == 1:
                fail(f"{where}: expected 'address name', found only "
                     f"'{fields[0]}'")
            if len(fields) > 2:
                fail(f"{where}: unexpected '{fields[2]}' after the name")
            addr, name = fields
            if not all(c in HEX_DIGITS for c in addr):
                fail(f"{where}: '{addr}' is not a hex number")
            if len(addr) > 8:
                fail(f"{where}: '{addr}' has more than 8 hex digits")
            symbols.append((int(addr, 16), name))
        # A stable sort keeps the file's order of the labels at one address
        symbols.sort(key=lambda s: s[0])
        self.addrs = [a for a, _ in symbols]
        self.names = [n for _, n in symbols]

    def before(self, addr: int) -> int | None:
        """The index of the label at or before addr, the first in the file
        of those at one address, or None when addr is before them all."""
        i = bisect.bisect_right(self.addrs, addr)
        if i == 0:
            return None
        i -= 1
        while i > 0 and self.addrs[i - 1] == self.addrs[i]:
            i -= 1
        return i

    def location(self, addr: int) -> str:
        """addr as niceemu prints it: the label at it, "label+0x1f" after
        one, or eight hex digits when no label is at or before it."""
        i = self.before(addr)
        if i is None:
            return f"{addr:08x}"
        if addr == self.addrs[i]:
            return self.names[i]
        return f"{self.names[i]}+0x{addr - self.addrs[i]:x}"


def write_words(link: Link, words: Words) -> None:
    """Writes the words, with one W for each run of consecutive
    addresses."""
    words = sorted(words)
    i = 0
    while i < len(words):
        j = i + 1
        while j < len(words) and words[j][0] == words[j - 1][0] + 1:
            j += 1
        link.write(words[i][0], [w for _, w in words[i:j]])
        i = j


def load_words(link: Link, words: Words,
               check: FitCheck | None = None) -> None:
    """Holds the processor, hides the ROM, clears the memory, checks the
    words with check, if one is given, disables the breakpoints, and writes
    the words. A system without a ROM ignores the hiding, and one without
    breakpoints takes the write of their enable bits as one of a reserved
    word (DEBUG.md §6)."""
    link.control(HOLD | CLEAR | RAM)
    if check is not None:
        check(link, words)
    link.write(BRK_EN, [0])
    write_words(link, words)


def start(link: Link) -> None:
    """Starts the processor at 0, with the ROM hidden. load_words() has held
    it, so this one write starts it (DEBUG.md §6)."""
    link.control(RAM)
