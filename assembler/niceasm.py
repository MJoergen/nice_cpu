#!/usr/bin/env python3
"""niceasm - a simple assembler for the NICE processor.

Implements the assembler syntax in doc/ISA.md section 10 and writes the .bin
object format of section 10.4: one line per word, "AAAAAAAA WWWWWWWW".

Usage: niceasm.py [-o output.bin] input.nasm

Pass 0 collects and checks the .EQU definitions, pass 1 assigns addresses to
labels, pass 2 emits the words. The size of every statement depends only on
its operand modes, which depend only on .EQU definitions, so passes 1 and 2
agree on sizes.
"""

from __future__ import annotations

import argparse
import bisect
import os
import re
import sys
from typing import Dict, Iterator, List, Optional, Set, Tuple

MASK = 0xFFFFFFFF

ALU, SHIFT, CTRL = range(3)

# name: (class, opcode or control command, number of operands)
MNEMONICS: Dict[str, Tuple[int, int, int]] = {
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

DIRECTIVES = {".EQU", ".ORG", ".DAT", ".BLK", ".RES", ".ASCII_L", ".ASCII_B"}

CONDITION_FLAGS = "1XCZNVEI"  # SEL 0..7; ?M is the 2004 name of ?E

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_.]*$")
IDENT_IN_TEXT = re.compile(r"(?<![A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_.]*")
REGISTER = re.compile(r"R(\d{1,2})$", re.IGNORECASE)
REGISTER_LIKE = re.compile(r"R\d+$", re.IGNORECASE)  # reserved, never a symbol
NUMBER = re.compile(r"0x[0-9a-f]+$|0b[01]+$|[0-9]+$", re.IGNORECASE)
TOKEN = re.compile(r"""'[^']*'|"[^"]*"|[^\s,;'"][^\s,;]*""")
QUOTES = ("'", '"')


class AsmError(Exception):
    pass


class Assembler:
    def __init__(self) -> None:
        self.equs: Dict[str, str] = {}                 # name -> replacement text
        self.bad_equs: Set[str] = set()                # .EQU names with a reported error
        self.labels: Dict[str, int] = {}               # name -> address
        self.defined_on: Dict[str, int] = {}           # label or .EQU name -> line number
        self.words: Dict[int, Tuple[int, int]] = {}    # address -> (word, line number)
        # .BLK and .RES: (address, count, line number, True for .BLK)
        self.blocks: List[Tuple[int, int, int, bool]] = []
        self.pc = 0
        self.pass_no = 0
        self.line_no = 0
        self.equ_cache: Dict[str, int] = {}            # .EQU values in pass 0
        self.early_labels: Dict[str, int] = {}         # label name -> first line, from pass 0
        self.must_know: Optional[str] = None  # set while evaluating a .ORG, .BLK, or .RES argument

    # -- Symbols and expressions -------------------------------------------

    def resolve(self, text: str) -> str:
        """Follows .EQU names until reaching text that is not one. Loops
        cannot occur: check_equs() marks a name in every loop as bad."""
        while text in self.equs and text not in self.bad_equs:
            text = self.equs[text]
        return text

    def deps(self, name: str) -> List[str]:
        """The good .EQU names that the value of .EQU name mentions."""
        return [d for d in IDENT_IN_TEXT.findall(self.equs[name])
                if d in self.equs and d not in self.bad_equs]

    def register(self, text: str) -> Optional[int]:
        """Register number 0..15 if text (after .EQU) names one, else None."""
        m = REGISTER.match(self.resolve(text))
        if m and int(m.group(1)) <= 15:
            return int(m.group(1))
        return None

    def check_name(self, name: str) -> None:
        """Checks that name can be defined as a label or an .EQU name."""
        if not IDENT.match(name):
            raise AsmError(f"bad symbol name '{name}'")
        if name in self.defined_on:
            raise AsmError(f"symbol '{name}' is already defined on line {self.defined_on[name]}")
        if REGISTER_LIKE.match(name):
            if self.register(name) is not None:
                raise AsmError(f"'{name}' is a register name, not a symbol")
            raise AsmError(f"'{name}' looks like a register and cannot be a symbol "
                           f"(the registers are R0 to R15)")
        if name.upper() in MNEMONICS:
            raise AsmError(f"'{name}' is a mnemonic and cannot be a symbol")

    def term(self, t: str, done: Dict[str, int]) -> int:
        if t[:1] in QUOTES:
            raise AsmError(f"a string ({t}) is only allowed after .ASCII_L and .ASCII_B")
        if t[:1].isdigit():
            if not NUMBER.match(t):
                raise AsmError(f"bad number '{t}'")
            if t[:2].lower() == "0x":
                v = int(t[2:], 16)
            elif t[:2].lower() == "0b":
                v = int(t[2:], 2)
            else:
                v = int(t, 10)
            if v > MASK:
                raise AsmError(f"number too large: '{t}'")
            return v
        if not IDENT.match(t):
            raise AsmError(f"expected a number or a symbol at '{t}'")
        if REGISTER_LIKE.match(t):
            if self.register(t) is not None:
                raise AsmError(f"'{t}' is a register where a number is expected")
            raise AsmError(f"'{t}' is not a register (the registers are R0 to R15)")
        if t in self.bad_equs:
            return 0  # its definition has already been reported
        if t in self.equs:
            return done[t] if t in done else self.equ_value(t)
        if t in self.labels:
            return self.labels[t]
        if self.must_know:
            raise AsmError(f"'{t}' must be defined before the {self.must_know}")
        if self.pass_no == 2:
            raise AsmError(f"undefined symbol '{t}'")
        return 0  # pass 0 or 1: value not needed yet

    def check_number(self, name: str) -> None:
        """Checks that .EQU name stands for a number, not a register or operand."""
        if self.register(name) is not None:
            raise AsmError(f"'{name}' is a register where a number is expected")
        s = self.resolve(name)
        if s.startswith(("@", "--")) or s.endswith(("++", "--")) or "[" in s:
            raise AsmError(f"'{name}' stands for the operand '{s}', not a number")

    def equ_value(self, name: str) -> int:
        """The value of .EQU name. Evaluates the names it depends on first,
        with an explicit stack, so a long chain cannot exhaust Python's. In
        pass 0 no label is known yet, so values are kept for check_equs()."""
        done: Dict[str, int] = self.equ_cache if self.pass_no == 0 else {}
        checked: Set[str] = set()
        stack = [name]
        while stack:
            n = stack[-1]
            if n not in done and n not in checked:
                self.check_number(n)  # before its dependencies, so an error names n
                checked.add(n)
            todo = [d for d in self.deps(n) if d not in done]
            if todo:
                stack += todo
                continue
            stack.pop()
            if n not in done:
                done[n] = self.value(self.equs[n], done)
        return done[name]

    def value(self, text: str, done: Optional[Dict[str, int]] = None) -> int:
        """expr := ['-'|'+'] term {('+'|'-') term}, not yet wrapped modulo 2^32.
        done holds .EQU values that are already known."""
        parts = re.split(r"([+-])", text)
        if parts[0] == "":       # leading sign
            parts = parts[1:]
        else:
            parts = ["+"] + parts
        if len(parts) % 2 or "" in parts:
            raise AsmError(f"bad expression '{text}'")
        acc = 0
        for op, t in zip(parts[0::2], parts[1::2]):
            v = self.term(t, done or {})
            acc = acc + v if op == "+" else acc - v
        return acc

    def expr(self, text: str) -> int:
        """An expression, wrapped modulo 2^32."""
        return self.value(text) & MASK

    def known(self, text: str, directive: str) -> int:
        """The unwrapped value of an expression whose symbols are all defined
        on earlier lines, so that it has the same value in pass 1 and 2."""
        self.must_know = directive
        try:
            return self.value(text)
        finally:
            self.must_know = None

    def check_equs(self) -> List[Tuple[int, str]]:
        """Checks every .EQU value, each after the .EQU names it uses. Returns
        (line number, message) for each bad one and marks it as bad, so that
        its uses do not report it again. A depth-first search with an explicit
        stack, so a long chain cannot exhaust Python's."""
        errors: List[Tuple[int, str]] = []
        state: Dict[str, bool] = {}  # name -> True once checked, False while checking

        def fail(name: str, msg: str) -> None:
            self.bad_equs.add(name)
            errors.append((self.defined_on[name], msg))

        for root in self.equs:
            if root in state:
                continue
            state[root] = False
            stack = [root]
            while stack:
                name = stack[-1]
                if name not in self.bad_equs:
                    deps = self.deps(name)
                    if any(state.get(d) is False for d in deps):
                        fail(name, f"'{name}': .EQU definitions form a loop")
                    else:
                        todo = [d for d in deps if d not in state]
                        if todo:
                            state[todo[0]] = False
                            stack.append(todo[0])
                            continue
                        value = self.equs[name]
                        try:  # any operand will do, as a destination or a source
                            try:
                                self.operand(value, True)
                            except AsmError:
                                self.operand(value, False)
                        except AsmError as e:
                            fail(name, str(e))
                state[name] = True
                stack.pop()
        return errors

    # -- Operands ----------------------------------------------------------

    def base_register(self, name: str) -> Optional[int]:
        """Like register(), for the name in --Rx, Rx++ and Rx--. An .EQU name
        there must stand for a register."""
        reg = self.register(name)
        if reg is None and name in self.equs and name not in self.bad_equs:
            raise AsmError(f"'{name}' stands for '{self.resolve(name)}', not a register")
        return reg

    def operand(self, tok: str, is_dest: bool) -> Tuple[int, Optional[int]]:
        """Returns (7-bit field, constant or None). See ISA.md section 4.
        An .EQU name may stand for the whole operand or for the part after @."""
        text = self.resolve(tok)
        indirect = text.startswith("@")
        p = self.resolve(text[1:]) if indirect else text
        hi = 0x40 if indirect else 0x00
        full = "@" + p if indirect else p
        shown = f"'{tok}'" if full == tok else f"'{tok}' (= '{full}')"
        if indirect and p.startswith("@"):
            raise AsmError(f"{shown}: there is only one level of '@'")

        if p.startswith("--"):                          # --Rx
            reg = self.base_register(p[2:])
            if reg is not None:
                if is_dest and not indirect:
                    raise AsmError(f"{shown}: pre-decrement is not a destination mode, use Rx--")
                return hi | 0x10 | reg, None

        if len(p) > 2 and p[-2:] in ("++", "--"):       # Rx++ and Rx--
            reg = self.base_register(p[:-2])
            if reg is not None:
                if p[-1] == "+":
                    return hi | 0x20 | reg, None
                if not is_dest or indirect:
                    raise AsmError(f"{shown}: post-decrement is only a direct destination mode")
                return 0x10 | reg, None

        reg = self.register(p)                          # Rx
        if reg is not None:
            return hi | reg, None

        reg = 0                                         # c and c[Rx]
        m = re.match(r"(.*)\[(.*)\]$", p)
        if m:
            p = m.group(1)
            index = self.register(m.group(2))
            if index is None:
                raise AsmError(f"{shown}: '{m.group(2)}' is not a register")
            reg = index
        elif "[" in p:
            raise AsmError(f"{shown}: bad index, expected c[Rx]")
        if not p:
            raise AsmError(f"{shown}: missing constant")
        return hi | 0x30 | reg, self.expr(p)

    def looks_like_operand(self, tok: str) -> bool:
        """True if tok can only be an operand, not a mnemonic."""
        tok = self.resolve(tok)
        return (tok[:1] in ("@", "-", "'", '"') or tok[:1].isdigit() or "[" in tok
                or tok.endswith(("++", "--")) or self.register(tok) is not None)

    # -- Output ------------------------------------------------------------

    def emit(self, word: int, line_no: int) -> None:
        if self.pass_no == 2:
            if self.pc in self.words:
                raise AsmError(f"address 0x{self.pc:08x} is already used by line "
                               f"{self.words[self.pc][1]}")
            self.words[self.pc] = (word & MASK, line_no)
        self.pc = (self.pc + 1) & MASK

    def check_blocks(self) -> List[Tuple[int, str]]:
        """Finds .BLK and .RES ranges that overlap each other or another word. Returns
        (line number, message) for each, reported on the later line."""
        errors: List[Tuple[int, str]] = []
        addrs = sorted(self.words)
        end = 0
        prev_line = 0
        for start, count, line_no, _ in sorted(self.blocks):
            if start < end:
                errors.append((max(line_no, prev_line),
                               f"address 0x{start:08x} is already used by line "
                               f"{min(line_no, prev_line)}"))
            if start + count > end:
                end, prev_line = start + count, line_no
            i = bisect.bisect_left(addrs, start)
            if i < len(addrs) and addrs[i] < start + count:
                other = self.words[addrs[i]][1]
                errors.append((max(line_no, other),
                               f"address 0x{addrs[i]:08x} is already used by line "
                               f"{min(line_no, other)}"))
        return errors

    def output(self) -> Iterator[Tuple[int, int]]:
        """Yields (address, word) in address order, with .BLK ranges expanded.
        .RES ranges are not in the output."""
        runs = [(a, 1, w) for a, (w, _) in self.words.items()]
        runs += [(a, n, 0) for a, n, _, zeros in self.blocks if zeros]
        for start, count, word in sorted(runs):
            for addr in range(start, start + count):
                yield addr, word

    # -- Statements --------------------------------------------------------

    def directive(self, d: str, args: List[str], line_no: int) -> None:
        if d == ".ORG":
            if len(args) != 1:
                raise AsmError(".ORG takes one address")
            self.pc = self.known(args[0], ".ORG") & MASK
        elif d == ".DAT":
            if not args:
                raise AsmError(".DAT takes at least one value")
            for a in args:
                self.emit(self.expr(a), line_no)
        elif d in (".BLK", ".RES"):
            if len(args) != 1:
                raise AsmError(f"{d} takes one count")
            n = self.known(args[0], d)
            if n < 0:
                raise AsmError(f"{d} count {n} is negative")
            if self.pc + n > MASK + 1:
                raise AsmError(f"{d} of {n} words at 0x{self.pc:08x} runs past "
                               f"address 0xffffffff")
            if self.pass_no == 2 and n:
                self.blocks.append((self.pc, n, line_no, d == ".BLK"))
            self.pc = (self.pc + n) & MASK
        elif d in (".ASCII_L", ".ASCII_B"):
            if len(args) > 1 and args[0][:1] in QUOTES and args[1][:1] in QUOTES:
                raise AsmError(f"{d} takes one string, got {len(args)}")
            if len(args) > 1 and args[0][:1] in QUOTES:
                q = args[0][0]
                other = "'" if q == '"' else '"'
                raise AsmError(f"text after the string {args[0]}: to put {q} in a string, "
                               f"quote the string with {other}")
            if len(args) != 1 or args[0][:1] not in QUOTES:
                raise AsmError(f"{d} takes one quoted string")
            data = args[0][1:-1].encode("latin-1")
            if d == ".ASCII_L":
                for c in data + b"\0":
                    self.emit(c, line_no)
            else:
                for i in range(0, len(data), 4):
                    self.emit(int.from_bytes(data[i:i + 4], "little"), line_no)
        else:
            raise AsmError(f"'{d}' is not allowed here")

    def instruction(self, cond: int, mtok: str, args: List[str], line_no: int) -> None:
        m = re.match(r"([^\[]+)(?:\[(.*)\])?$", mtok)
        if not m or m.group(1).upper() not in MNEMONICS:
            if mtok.split("[")[0].upper() in MNEMONICS:
                raise AsmError(f"'{mtok}': bad modifier, expected [M], [C] or [CM]")
            raise AsmError(f"unknown mnemonic '{mtok}'")
        name = m.group(1).upper()
        cls, opcode, nops = MNEMONICS[name]

        if args and args[0].startswith("["):
            if m.group(2) is None:
                raise AsmError(f"'{mtok} {args[0]}': write the modifier without a space, "
                               f"as {mtok}{args[0]}")
            both = m.group(2) + args[0].strip("[]")
            if both and len(set(both.upper())) == len(both) and set(both.upper()) <= set("MC"):
                raise AsmError(f"'{mtok} {args[0]}': write all modifiers in one bracket, "
                               f"as {m.group(1)}[{both}]")
            raise AsmError(f"'{mtok} {args[0]}': write each modifier once, in one bracket "
                           f"after the mnemonic")
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
                v = self.value(args[0])
                if not 0 <= v <= 255:
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
    def tokenize(text: str) -> Tuple[List[str], List[bool]]:
        """Splits at whitespace and single commas. A comment starts with ';'
        or '*'. A quoted string is one token, quotes kept. Returns the tokens
        and, for each, whether a comma comes before it."""
        tokens: List[str] = []
        commas: List[bool] = []
        text = text.rstrip("\r\n")
        pos = 0
        comma = False  # a comma since the last token
        while True:
            while pos < len(text) and text[pos].isspace():
                pos += 1
            if pos == len(text) or text[pos] in ";*":
                break
            if text[pos] == ",":
                if not tokens:
                    raise AsmError("unexpected ',' at the start of the line")
                if comma:
                    raise AsmError("two commas with no operand between them")
                comma = True
                pos += 1
                continue
            m = TOKEN.match(text, pos)
            if not m:
                if text[pos] in QUOTES:
                    raise AsmError(f"unterminated string {text[pos:]}")
                raise AsmError(f"unexpected character '{text[pos]}'")
            tokens.append(m.group())
            commas.append(comma)
            pos = m.end()
            comma = False
        if comma:
            raise AsmError("',' at the end of the line has no operand after it")
        return tokens, commas

    @staticmethod
    def check_commas(tokens: List[str], commas: List[bool], first_arg: int) -> None:
        """A comma may only come between two operands, which start at first_arg."""
        for i in range(1, min(first_arg + 1, len(tokens))):
            if commas[i]:
                raise AsmError(f"',' after '{tokens[i - 1]}': a comma only separates operands")

    @staticmethod
    def strip_colon(name: str) -> str:
        return name[:-1] if len(name) > 1 and name.endswith(":") else name

    @staticmethod
    def is_keyword(tok: str) -> bool:
        return (tok.startswith("?") or tok.upper() in DIRECTIVES
                or tok.split("[")[0].upper() in MNEMONICS)

    def define_label(self, name: str) -> None:
        if self.pass_no == 1:
            self.check_name(name)
            self.labels[name] = self.pc
            self.defined_on[name] = self.line_no

    def line(self, text: str, line_no: int) -> None:
        self.line_no = line_no
        try:
            tok, commas = self.tokenize(text)
        except AsmError:
            if self.pass_no == 0:
                return  # reported in pass 1
            raise
        if not tok:
            return

        if len(tok) >= 2 and tok[1].upper() == ".EQU":  # handled before pass 1
            if self.pass_no == 0:
                self.check_commas(tok, commas, 2)
                if len(tok) != 3:
                    raise AsmError(".EQU takes one value")
                name = self.strip_colon(tok[0])
                if name in self.early_labels:
                    raise AsmError(f"symbol '{name}' is already defined on line "
                                   f"{self.early_labels[name]}")
                self.check_name(name)
                self.equs[name] = tok[2]
                self.defined_on[name] = line_no
            return
        if self.pass_no == 0:
            # Note labels, so that an .EQU of the same name further down is
            # reported on the .EQU line. Pass 1 checks and defines them.
            if (not self.is_keyword(tok[0]) and not tok[0].startswith(".")
                    and (len(tok) == 1 or self.is_keyword(tok[1]))):
                self.early_labels.setdefault(self.strip_colon(tok[0]), line_no)
            return
        all_tok = list(tok)

        # A label is a first word that is not a condition, mnemonic or directive.
        label = None
        if not self.is_keyword(tok[0]):
            if tok[0].startswith("."):
                raise AsmError(f"unknown directive '{tok[0]}'")
            if len(tok) > 1 and not self.is_keyword(tok[1]):
                if tok[1].startswith("."):
                    raise AsmError(f"unknown directive '{tok[1]}'")
                if self.looks_like_operand(tok[1]):
                    raise AsmError(f"unknown mnemonic '{tok[0]}'")
                raise AsmError(f"unknown mnemonic '{tok[1]}' "
                               f"('{tok[0]}' is read as a label)")
            label = self.strip_colon(tok.pop(0))
        if not tok:
            if label is not None:
                self.define_label(label)
            return

        cond = 0
        has_cond = tok[0].startswith("?")
        if has_cond:
            c = tok.pop(0)
            m = re.match(r"\?(!?)(.)$", c)
            flag = m.group(2).upper().replace("M", "E") if m else ""
            if not m or flag not in CONDITION_FLAGS:
                raise AsmError(f"bad condition '{c}'")
            cond = (m.group(1) == "!") << 3 | CONDITION_FLAGS.index(flag)
            if not tok:
                raise AsmError("condition without an instruction")
        self.check_commas(all_tok, commas, len(all_tok) - len(tok) + 1)

        if tok[0].startswith("."):
            d = tok[0].upper()
            if has_cond:
                raise AsmError("a directive cannot have a condition")
            if d == ".EQU":
                raise AsmError(".EQU needs a name")
            if d == ".ORG":  # a label on a .ORG line names the new address
                self.directive(d, tok[1:], line_no)
                if label is not None:
                    self.define_label(label)
                return
            if label is not None:
                self.define_label(label)
            self.directive(d, tok[1:], line_no)
        else:
            if label is not None:
                self.define_label(label)
            self.instruction(cond, tok[0], tok[1:], line_no)

    def run(self, lines: List[str], name: str) -> List[str]:
        """Assembles lines. Returns a list of error messages."""
        errors: List[Tuple[int, str]] = []
        for self.pass_no in (0, 1, 2):
            if self.pass_no == 2 and errors:
                break  # pass 2 would only repeat pass 1's errors
            self.pc = 0
            for n, text in enumerate(lines, 1):
                try:
                    self.line(text, n)
                except AsmError as e:
                    errors.append((n, str(e)))
            if self.pass_no == 0:
                errors += self.check_equs()
        if not errors:
            errors += self.check_blocks()
        errors.sort(key=lambda e: e[0])
        return [f"{name}:{n}: error: {msg}" for n, msg in errors]


def main() -> None:
    ap = argparse.ArgumentParser(description="Assembler for the NICE processor.")
    ap.add_argument("input", help="assembly source (.nasm)")
    ap.add_argument("-o", dest="output",
                    help="output file (default: input with .bin extension)")
    args = ap.parse_args()

    out = args.output or os.path.splitext(args.input)[0] + ".bin"
    try:
        with open(args.input, encoding="latin-1") as f:
            lines = f.readlines()
        if os.path.exists(out) and os.path.samefile(out, args.input):
            sys.exit(f"{args.input}: the output file would overwrite the input; use -o")
    except OSError as e:
        sys.exit(f"{e.filename}: {e.strerror}")
    if lines and lines[0].startswith("\xef\xbb\xbf"):  # UTF-8 byte order mark
        lines[0] = lines[0][3:]

    asm = Assembler()
    errors = asm.run(lines, args.input)
    if errors:
        for msg in errors:
            print(msg, file=sys.stderr)
        print(f"{len(errors)} error{'' if len(errors) == 1 else 's'}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(out, "w") as f:
            for addr, word in asm.output():
                f.write(f"{addr:08x} {word:08x}\n")
    except OSError as e:
        sys.exit(f"{e.filename}: {e.strerror}")


if __name__ == "__main__":
    main()
