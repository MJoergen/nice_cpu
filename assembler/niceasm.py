#!/usr/bin/env python3
"""niceasm - a simple assembler for the NICE processor.

Implements the assembler syntax in doc/ISA.md section 10 and writes the .bin
object format of section 10.4: one line per word, "AAAAAAAA WWWWWWWW".

Usage: niceasm.py [-o output.bin] input.asm

Two passes: pass 1 assigns addresses to labels, pass 2 emits the words. The
size of every statement depends only on its operand modes, and .EQU
definitions are collected before pass 1, so both passes agree on sizes.
"""

import argparse
import os
import re
import sys

MASK = 0xFFFFFFFF

ALU, SHIFT, CTRL = range(3)

# name: (class, opcode or control command, number of operands)
MNEMONICS = {
    "MOVE": (ALU, 0x0, 2), "SUB": (ALU, 0x1, 3), "MDBL": (ALU, 0x2, 3),
    "ADD": (ALU, 0x3, 3), "DBL": (ALU, 0x4, 2), "DEC": (ALU, 0x5, 2),
    "NOT": (ALU, 0x6, 2), "NOR": (ALU, 0x7, 3), "IAND": (ALU, 0x8, 3),
    "NAND": (ALU, 0x9, 3), "XOR": (ALU, 0xA, 3), "IOR": (ALU, 0xB, 3),
    "XNOR": (ALU, 0xC, 3), "AND": (ALU, 0xD, 3), "ONE": (ALU, 0xE, 1),
    "OR": (ALU, 0xF, 3),

    "0<0": (SHIFT, 0x0, 3), "0<1": (SHIFT, 0x1, 3), "0<C": (SHIFT, 0x2, 3),
    "C<0": (SHIFT, 0x3, 3), "C<1": (SHIFT, 0x4, 3), "C<C": (SHIFT, 0x5, 3),
    "<<<": (SHIFT, 0x6, 3), "C<<": (SHIFT, 0x7, 3), "0>0": (SHIFT, 0x8, 3),
    "1>0": (SHIFT, 0x9, 3), "C>0": (SHIFT, 0xA, 3), "0>C": (SHIFT, 0xB, 3),
    "1>C": (SHIFT, 0xC, 3), "C>C": (SHIFT, 0xD, 3), ">>>": (SHIFT, 0xE, 3),
    ">>C": (SHIFT, 0xF, 3),
    "SHL": (SHIFT, 0x0, 3), "ROL": (SHIFT, 0x6, 3), "BPL": (SHIFT, 0x7, 3),
    "SHR": (SHIFT, 0x8, 3), "ROR": (SHIFT, 0xE, 3), "BPR": (SHIFT, 0xF, 3),

    "HALT": (CTRL, 0x00, 0), "RTI": (CTRL, 0x01, 0), "INT": (CTRL, 0x02, 1),
}

DIRECTIVES = {".EQU", ".ORG", ".DAT", ".BLK", ".ASCII_L", ".ASCII_B"}

CONDITION_FLAGS = "1XCZNVEI"  # SEL 0..7; ?M is the 2004 name of ?E

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*$")
REGISTER = re.compile(r"R(\d{1,2})$", re.IGNORECASE)
TOKEN = re.compile(r"""\s*(?:([;*].*)|('[^']*'|"[^"]*")|([^\s,;'"][^\s,;]*))[\s,]*""")


class AsmError(Exception):
    pass


class Assembler:
    def __init__(self):
        self.equs = {}     # name -> replacement text
        self.labels = {}   # name -> address
        self.words = {}    # address -> (word, line number)
        self.pc = 0
        self.pass_no = 0

    # -- Symbols and expressions -------------------------------------------

    def resolve(self, text):
        """Follows .EQU names until reaching text that is not one."""
        for _ in range(100):
            if text not in self.equs:
                return text
            text = self.equs[text]
        raise AsmError(f"'{text}': .EQU definitions form a loop")

    def register(self, text):
        """Register number 0..15 if text (after .EQU) names one, else None."""
        m = REGISTER.match(self.resolve(text))
        if m and int(m.group(1)) <= 15:
            return int(m.group(1))
        return None

    def term(self, t, depth):
        if t[:1].isdigit():
            try:
                if t[:2].lower() == "0x":
                    v = int(t[2:], 16)
                elif t[:2].lower() == "0b":
                    v = int(t[2:], 2)
                else:
                    v = int(t, 10)
            except ValueError:
                raise AsmError(f"bad number: '{t}'")
            if v > MASK:
                raise AsmError(f"number too large: '{t}'")
            return v
        if not IDENT.match(t):
            raise AsmError(f"expected a number or a symbol at '{t}'")
        if t in self.equs:
            if depth > 100:
                raise AsmError(f"'{t}': .EQU definitions form a loop")
            if self.register(t) is not None:
                raise AsmError(f"'{t}' is a register where a number is expected")
            return self.expr(self.equs[t], depth + 1)
        if t in self.labels:
            return self.labels[t]
        if self.pass_no == 2:
            raise AsmError(f"undefined symbol '{t}'")
        return 0  # pass 1: value not needed yet

    def expr(self, text, depth=0, must_be_known=False):
        """expr := ['-'|'+'] term {('+'|'-') term}, wrapping modulo 2^32."""
        saved = self.pass_no
        if must_be_known:
            self.pass_no = 2
        try:
            parts = re.split(r"([+-])", text)
            if parts[0] == "":       # leading sign
                parts = parts[1:]
            else:
                parts = ["+"] + parts
            if len(parts) % 2 or "" in parts:
                raise AsmError(f"bad expression '{text}'")
            acc = 0
            for op, t in zip(parts[0::2], parts[1::2]):
                v = self.term(t, depth)
                acc = acc + v if op == "+" else acc - v
            return acc & MASK
        finally:
            self.pass_no = saved

    # -- Operands ----------------------------------------------------------

    def operand(self, tok, is_dest):
        """Returns (7-bit field, constant or None). See ISA.md section 4."""
        indirect = tok.startswith("@")
        p = tok[1:] if indirect else tok
        hi = 0x40 if indirect else 0x00

        if p.startswith("--"):                          # --Rx
            reg = self.register(p[2:])
            if reg is not None:
                if is_dest and not indirect:
                    raise AsmError(f"'{tok}': pre-decrement is not a destination mode, use Rx--")
                return hi | 0x10 | reg, None

        if len(p) > 2 and p[-2:] in ("++", "--"):       # Rx++ and Rx--
            reg = self.register(p[:-2])
            if reg is not None:
                if p[-1] == "+":
                    return hi | 0x20 | reg, None
                if not is_dest or indirect:
                    raise AsmError(f"'{tok}': post-decrement is only a direct destination mode")
                return 0x10 | reg, None

        reg = self.register(p)                          # Rx
        if reg is not None:
            return hi | reg, None

        reg = 0                                         # c and c[Rx]
        m = re.match(r"(.*)\[(.*)\]$", p)
        if m:
            p = m.group(1)
            reg = self.register(m.group(2))
            if reg is None:
                raise AsmError(f"'{tok}': '{m.group(2)}' is not a register")
        elif "[" in p:
            raise AsmError(f"'{tok}': bad index, expected c[Rx]")
        if not p:
            raise AsmError(f"'{tok}': missing constant")
        return hi | 0x30 | reg, self.expr(p)

    # -- Output ------------------------------------------------------------

    def emit(self, word, line_no):
        if self.pass_no == 2:
            if self.pc in self.words:
                raise AsmError(f"address 0x{self.pc:08x} is already used by line "
                               f"{self.words[self.pc][1]}")
            self.words[self.pc] = (word & MASK, line_no)
        self.pc = (self.pc + 1) & MASK

    # -- Statements --------------------------------------------------------

    def directive(self, d, args, line_no):
        if d == ".ORG":
            if len(args) != 1:
                raise AsmError(".ORG takes one address")
            self.pc = self.expr(args[0], must_be_known=True)
        elif d == ".DAT":
            if not args:
                raise AsmError(".DAT takes at least one value")
            for a in args:
                self.emit(self.expr(a), line_no)
        elif d == ".BLK":
            if len(args) != 1:
                raise AsmError(".BLK takes one count")
            for _ in range(self.expr(args[0], must_be_known=True)):
                self.emit(0, line_no)
        elif d in (".ASCII_L", ".ASCII_B"):
            if len(args) != 1 or args[0][:1] not in ("'", '"'):
                raise AsmError("expected one quoted string")
            data = args[0][1:-1].encode("latin-1")
            if d == ".ASCII_L":
                for c in data + b"\0":
                    self.emit(c, line_no)
            else:
                for i in range(0, len(data), 4):
                    self.emit(int.from_bytes(data[i:i + 4], "little"), line_no)
        else:
            raise AsmError(f"'{d}' is not allowed here")

    def instruction(self, cond, mtok, args, line_no):
        m = re.match(r"([^\[]+)(?:\[(.*)\])?$", mtok)
        name = m.group(1).upper() if m else ""
        if name not in MNEMONICS:
            raise AsmError(f"unknown mnemonic '{mtok}'")
        cls, opcode, nops = MNEMONICS[name]

        mods = (m.group(2) or "").upper()
        if m.group(2) is not None and (not mods or len(set(mods)) != len(mods)
                                       or set(mods) - set("MC")):
            raise AsmError(f"'{mtok}': bad modifier")
        if mods and cls == CTRL:
            raise AsmError(f"{name} takes no modifiers")
        if "C" in mods and cls != ALU:
            raise AsmError("[C] is only allowed on ALU instructions")
        if len(args) != nops:
            raise AsmError(f"{name} takes {nops} operand{'' if nops == 1 else 's'}, "
                           f"got {len(args)}")

        iw = cond << 28
        if cls == CTRL:
            iw |= 0x0C000000 | opcode << 21
            if args:
                v = self.expr(args[0])
                if v > 255:
                    raise AsmError(f"interrupt vector {v} is out of range 0..255")
                iw |= v
            self.emit(iw, line_no)
            return

        ops = [self.operand(a, i == 0) for i, a in enumerate(args)]
        ops += [(0, None)] * (3 - len(ops))  # unused fields are R0
        if cls == SHIFT:
            iw |= 0x08000000
        iw |= ("C" in mods) << 26 | ("M" in mods) << 25 | opcode << 21
        iw |= ops[0][0] << 14 | ops[1][0] << 7 | ops[2][0]
        self.emit(iw, line_no)
        for _, c in ops:  # constant words in field order dest, s0, s1
            if c is not None:
                self.emit(c, line_no)

    @staticmethod
    def tokenize(text):
        """Splits at whitespace and commas. A comment starts with ';' or '*'.
        A quoted string is one token, quotes kept."""
        tokens = []
        pos = 0
        text = text.rstrip("\r\n")
        while pos < len(text):
            m = TOKEN.match(text, pos)
            if not m or m.end() == pos:
                if text[pos] in "'\"":
                    raise AsmError("unterminated string")
                break
            if m.group(1) is not None:
                break
            tokens.append(m.group(2) or m.group(3))
            pos = m.end()
        return tokens

    @staticmethod
    def is_keyword(tok):
        return (tok.startswith("?") or tok.upper() in DIRECTIVES
                or tok.split("[")[0].upper() in MNEMONICS)

    def line(self, text, line_no):
        try:
            tok = self.tokenize(text)
        except AsmError:
            if self.pass_no == 0:
                return  # reported in pass 1
            raise
        if not tok:
            return

        if len(tok) >= 2 and tok[1].upper() == ".EQU":  # handled before pass 1
            if self.pass_no == 0:
                if len(tok) != 3:
                    raise AsmError(".EQU takes one value")
                if not IDENT.match(tok[0]):
                    raise AsmError(f"bad symbol name '{tok[0]}'")
                if tok[0] in self.equs:
                    raise AsmError(f"symbol '{tok[0]}' is already defined")
                self.equs[tok[0]] = tok[2]
            return
        if self.pass_no == 0:
            return

        # A label is a first word that is not a condition, mnemonic or directive.
        if not self.is_keyword(tok[0]):
            if len(tok) > 1 and not self.is_keyword(tok[1]):
                raise AsmError(f"unknown mnemonic '{tok[0]}'")
            name = tok.pop(0)
            if len(name) > 1 and name.endswith(":"):
                name = name[:-1]
            if self.pass_no == 1:
                if not IDENT.match(name):
                    raise AsmError(f"bad label '{name}'")
                if self.register(name) is not None:
                    raise AsmError(f"'{name}' is a register name, not a label")
                if name in self.labels or name in self.equs:
                    raise AsmError(f"symbol '{name}' is already defined")
                self.labels[name] = self.pc
        if not tok:
            return

        cond = 0
        if tok[0].startswith("?"):
            c = tok.pop(0)
            m = re.match(r"\?(!?)(.)$", c)
            flag = m.group(2).upper().replace("M", "E") if m else ""
            if not flag or flag not in CONDITION_FLAGS:
                raise AsmError(f"bad condition '{c}'")
            cond = (m.group(1) == "!") << 3 | CONDITION_FLAGS.index(flag)
            if not tok:
                raise AsmError("condition without an instruction")

        if tok[0].startswith("."):
            if cond:
                raise AsmError("a directive cannot have a condition")
            if tok[0].upper() == ".EQU":
                raise AsmError(".EQU needs a name")
            self.directive(tok[0].upper(), tok[1:], line_no)
        else:
            self.instruction(cond, tok[0], tok[1:], line_no)

    def run(self, lines, name):
        """Assembles lines. Returns a list of error messages."""
        errors = []
        for self.pass_no in (0, 1, 2):
            if self.pass_no == 2 and errors:
                break  # pass 2 would only repeat pass 1's errors
            self.pc = 0
            for n, text in enumerate(lines, 1):
                try:
                    self.line(text, n)
                except AsmError as e:
                    errors.append(f"{name}:{n}: error: {e}")
        return errors


def main():
    ap = argparse.ArgumentParser(description="Assembler for the NICE processor.")
    ap.add_argument("input", help="assembly source (.asm)")
    ap.add_argument("-o", dest="output",
                    help="output file (default: input with .bin extension)")
    args = ap.parse_args()

    try:
        with open(args.input, encoding="latin-1") as f:
            lines = f.readlines()
    except OSError as e:
        sys.exit(f"{args.input}: {e.strerror}")

    asm = Assembler()
    errors = asm.run(lines, args.input)
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        print(f"{len(errors)} error{'' if len(errors) == 1 else 's'}", file=sys.stderr)
        sys.exit(1)

    out = args.output or os.path.splitext(args.input)[0] + ".bin"
    with open(out, "w") as f:
        for addr in sorted(asm.words):
            f.write(f"{addr:08x} {asm.words[addr][0]:08x}\n")


if __name__ == "__main__":
    main()
