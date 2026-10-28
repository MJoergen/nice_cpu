#!/usr/bin/env python3
"""nicedis - a disassembler for the NICE processor.

Reads a .bin file (doc/ISA.md section 10.4) and writes the assembler syntax
of section 10, in the layout of nicefmt, so that niceasm assembles the
output back to the same words.

Usage: nicedis.py [--symbols FILE] [--start ADDR] [--end ADDR] input.bin

Other tools import disassemble(), which disassembles one instruction from a
word reader. The listing adds the rules that keep the round trip: words that
no instruction gives are .DAT, .ORG lines fill the gaps, and an instruction
never spans a label of the symbols file.
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import Callable, Dict, List, Mapping, NamedTuple, Optional, Set, Tuple

import niceasm
import nicefmt

MASK = niceasm.MASK

ALU_NAMES = ["MOVE", "SUB", "MDBL", "ADD", "DBL", "DEC", "NOT", "NOR",
             "IAND", "NAND", "XOR", "IOR", "XNOR", "AND", "ONE", "OR"]
# The alias where one exists, the canonical mnemonic otherwise.
SHIFT_NAMES = ["SHL", "0<1", "0<C", "C<0", "C<1", "C<C", "ROL", "BPL",
               "SHR", "1>0", "C>0", "0>C", "1>C", "C>C", "ROR", "BPR"]
CTRL_NAMES = ["HALT", "RTI", "INT"]
FIELD_NAMES = ["dest", "s0", "s1"]

# The constant of a label is only shown as one from this value on, so that
# small numbers, such as the 2 of a call, stay numbers.
MIN_LABEL = 16

BIN_LINE = re.compile(r"([0-9a-fA-F]{1,8})[ \t]+([0-9a-fA-F]{1,8})$")
SYM_LINE = re.compile(r"([0-9a-fA-F]{8}) (.+)$")

Reader = Callable[[int], Optional[int]]
Namer = Callable[[int], Optional[str]]


class DisError(Exception):
    pass


class Operand(NamedTuple):
    field: int             # the 7-bit operand field
    const: Optional[int]   # its constant word, or None if it takes none or it is missing
    dest: bool
    shift_count: bool      # a SHIFT count in mode 011, which is never a label


class Insn(NamedTuple):
    """One decoded instruction. It is a .DAT if dat() is true."""
    words: List[int]        # the words it takes, as far as they are there
    cond: str               # "" for "always"
    mnemonic: str           # with its modifiers
    operands: List[Operand]
    unused: List[Tuple[str, Operand]]  # unused fields that are not R0, by name
    vector: Optional[int]   # the vector of INT
    reserved: bool          # a reserved control word
    cut: bool               # constant words are missing

    def dat(self) -> bool:
        return self.reserved or self.cut or bool(self.unused)


def takes_const(field: int) -> bool:
    return field & 0x30 == 0x30


def condition(word: int) -> str:
    sel, neg = word >> 28 & 7, word >> 31
    if sel == 0 and not neg:
        return ""
    return ("?!" if neg else "?") + niceasm.CONDITION_FLAGS[sel]


def decode(addr: int, read: Reader) -> Insn:
    """Decodes the instruction at addr, whose word read() must return. A
    constant word for which read() returns None, or one past address
    0xFFFFFFFF, is missing, and the instruction is cut off before it."""
    word = read(addr)
    assert word is not None
    cond = condition(word)
    if word >> 26 & 3 == 3:
        cmd, vector = word >> 21 & 0x1F, word & 0xFF
        if cmd > 2 or word >> 8 & 0x1FFF or (cmd != 2 and vector):
            return Insn([word], cond, "", [], [], None, True, False)
        return Insn([word], cond, CTRL_NAMES[cmd], [], [], vector if cmd == 2 else None,
                    False, False)

    shift = word >> 27 & 1
    opcode = word >> 21 & 0xF
    fields = [word >> 14 & 0x7F, word >> 7 & 0x7F, word & 0x7F]
    words = [word]
    cut = False
    consts: List[Optional[int]] = []
    for f in fields:  # constant words in field order dest, s0, s1
        c = None
        if takes_const(f) and not cut:
            a = addr + len(words)
            c = read(a) if a <= MASK else None
            if c is None:
                cut = True
            else:
                words.append(c)
        consts.append(c)

    if shift:
        name, nops = SHIFT_NAMES[opcode], 3
    else:
        name = ALU_NAMES[opcode]
        nops = niceasm.MNEMONICS[name][2]
    mods = ("C" if not shift and word >> 26 & 1 else "") + ("M" if word >> 25 & 1 else "")
    if mods:
        name += f"[{mods}]"
    ops = [Operand(f, c, i == 0, bool(shift) and i == 2 and f >> 4 == 3)
           for i, (f, c) in enumerate(zip(fields, consts))]
    unused = [(FIELD_NAMES[i], ops[i]) for i in range(nops, 3) if fields[i]]
    return Insn(words, cond, name, ops[:nops], unused, None, False, cut)


def operand_text(op: Operand, name: Namer) -> str:
    """The operand in the syntax of ISA.md section 10.2. A missing constant is '?'."""
    mode, reg = op.field >> 4, f"R{op.field & 0xF}"
    if mode & 3 == 3:
        if op.const is None:
            c = "?"
        else:
            c = (None if op.shift_count else name(op.const)) or f"0x{op.const:x}"
        text = c if reg == "R0" else f"{c}[{reg}]"
    elif mode & 3 == 2:
        text = f"{reg}++"
    elif mode & 3 == 1:  # a direct destination decrements after, all others before
        text = f"{reg}--" if op.dest and mode == 1 else f"--{reg}"
    else:
        text = reg
    return "@" + text if mode & 4 else text


def statement(insn: Insn, name: Namer) -> str:
    """The condition, mnemonic, and operands of an instruction that is not a .DAT."""
    if insn.vector is not None:
        args = str(insn.vector)
    else:
        args = ", ".join(operand_text(op, name) for op in insn.operands)
    return " ".join(t for t in (insn.cond, insn.mnemonic, args) if t)


def meaning(insn: Insn) -> str:
    """What the words of a .DAT would do as an instruction, for its comment."""
    if insn.reserved:
        return "reserved control word"
    text = statement(insn, lambda v: None)
    if insn.unused:
        text += " (" + ", ".join(f"{n}: {operand_text(op, lambda v: None)}"
                                 for n, op in insn.unused) + ")"
    return text + (" (cut off)" if insn.cut else "")


def dat(words: List[int]) -> str:
    return ".DAT " + ", ".join(f"0x{w:08x}" for w in words)


def disassemble(addr: int, read: Reader,
                symbols: Optional[Mapping[int, str]] = None) -> Tuple[str, int]:
    """Disassembles the instruction at addr. read(a) returns the word at a,
    or None if there is none. symbols maps an address to a name, which is
    shown in place of a constant of 16 or more at that address; any name
    will do, since nothing reassembles the text. Returns the text and the
    number of words it used. A .DAT has its meaning as a comment."""
    syms = symbols or {}
    insn = decode(addr, read)
    if insn.dat():
        return f"{dat(insn.words)} ; {meaning(insn)}", len(insn.words)
    return statement(insn, lambda v: syms.get(v) if v >= MIN_LABEL else None), len(insn.words)


# -- Listing -----------------------------------------------------------------

def valid_names(symbols: List[Tuple[int, str]]) -> Set[str]:
    """The names that niceasm accepts as labels and that occur once."""
    seen: Dict[str, int] = {}
    for _, n in symbols:
        seen[n] = seen.get(n, 0) + 1
    return {n for n, k in seen.items()
            if k == 1 and niceasm.IDENT.match(n) and not niceasm.REGISTER_LIKE.match(n)
            and n.upper() not in niceasm.MNEMONICS}


def listing(words: Mapping[int, int], symbols: List[Tuple[int, str]],
            start: int = 0, end: int = MASK + 1) -> List[str]:
    """The lines of the listing of the words from start to end (exclusive).
    symbols are (address, name) in the order of the symbols file."""
    good = valid_names(symbols)
    at: Dict[int, List[str]] = {}
    where: Dict[str, int] = {}  # the address of each good name
    for a, n in symbols:
        at.setdefault(a, []).append(n)
        if n in good:
            where[n] = a
    starts = sorted(at)

    def shown(v: int) -> Optional[str]:
        """The name shown for the constant v: the first good one at v, else the first."""
        names = at.get(v, [])
        return next((n for n in names if n in good), names[0] if names else None)

    used: Set[str] = set()
    defined: Set[str] = set()
    notes: List[str] = []

    def name(v: int) -> Optional[str]:
        """The label for the constant v, noting it for the comment."""
        n = shown(v) if v >= MIN_LABEL else None
        if n is None:
            return None
        notes.append(f"{n} = 0x{v:08x}")
        if n not in good:
            return None
        used.add(n)
        return n

    body: List[str] = []
    expected = 0
    addrs = [a for a in sorted(words) if start <= a < end]
    i = 0
    while i < len(addrs):
        addr = addrs[i]
        if addr != expected:
            body += nicefmt.format_line(f" .ORG 0x{addr:08x}")
        labels = at.get(addr, [])
        for n in labels:
            if n not in good:
                body.append(f"; {n}")
        good_here = [n for n in labels if n in good]
        defined.update(good_here)
        for n in good_here[:-1]:
            body += nicefmt.format_line(n)
        label = good_here[-1] if good_here else ""

        k = next((s for s in starts if s > addr), end)  # the next label ends the instruction
        limit = min(k, end)
        insn = decode(addr, lambda a: words.get(a) if a < limit else None)
        notes.clear()
        if insn.dat():
            text = f"{dat(insn.words)} ; {meaning(insn)}"
        else:
            text = statement(insn, name)
            if notes:
                text += " ; " + ", ".join(dict.fromkeys(notes))  # each once, in order
        body += nicefmt.format_line(f"{label} {text}" if label else f" {text}")
        expected = addr + len(insn.words)
        i += len(insn.words)

    # The labels used but not defined: outside the range, or where no word is.
    head = [line for n in sorted(used - defined, key=lambda n: (where[n], n))
            for line in nicefmt.format_line(f"{n} .EQU 0x{where[n]:08x}")]
    return head + body


# -- Files -------------------------------------------------------------------

def read_bin(path: str) -> Dict[int, int]:
    """The words of a .bin file, with the leniency of niceemu's loader."""
    words: Dict[int, int] = {}
    with open(path, encoding="latin-1") as f:
        for n, line in enumerate(f, 1):
            text = line.rstrip("\r\n").strip(" \t")
            if not text:
                continue
            m = BIN_LINE.match(text)
            if not m:
                raise DisError(f"{path}:{n}: error: expected an address and a word in hex")
            a, w = int(m.group(1), 16), int(m.group(2), 16)
            if a in words:
                raise DisError(f"{path}:{n}: error: address 0x{a:08x} appears twice")
            words[a] = w
    if not words:
        raise DisError(f"{path}: error: no words")
    return words


def read_symbols(path: str) -> List[Tuple[int, str]]:
    """The labels of a symbols file of niceasm or nicebuild.py, in file order."""
    symbols: List[Tuple[int, str]] = []
    with open(path, encoding="latin-1") as f:
        for n, line in enumerate(f, 1):
            text = line.rstrip("\r\n")
            m = SYM_LINE.match(text)
            if not m or m.group(2).strip() != m.group(2):
                raise DisError(f"{path}:{n}: error: expected an 8-digit hex address, "
                               f"a space, and a name")
            symbols.append((int(m.group(1), 16), m.group(2)))
    return symbols


def address(text: str) -> int:
    try:
        v = int(text, 0)
    except ValueError:
        raise argparse.ArgumentTypeError(f"bad address '{text}'")
    if not 0 <= v <= MASK + 1:
        raise argparse.ArgumentTypeError(f"address '{text}' is out of range")
    return v


def main() -> None:
    ap = argparse.ArgumentParser(description="Disassembler for the NICE processor.")
    ap.add_argument("input", help="program (.bin)")
    ap.add_argument("--symbols", metavar="FILE",
                    help="labels of niceasm --symbols or nicebuild.py --symbols")
    ap.add_argument("--start", type=address, default=0, metavar="ADDR",
                    help="first address to list (default 0)")
    ap.add_argument("--end", type=address, default=MASK + 1, metavar="ADDR",
                    help="address after the last one to list (default: all)")
    args = ap.parse_args()
    try:
        words = read_bin(args.input)
        symbols = read_symbols(args.symbols) if args.symbols else []
    except OSError as e:
        sys.exit(f"{e.filename}: {e.strerror}")
    except DisError as e:
        sys.exit(str(e))
    try:
        for line in listing(words, symbols, args.start, args.end):
            print(line)
    except BrokenPipeError:
        sys.stderr.close()


if __name__ == "__main__":
    main()
