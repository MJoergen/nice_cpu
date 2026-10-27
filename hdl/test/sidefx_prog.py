#!/usr/bin/env python3
"""Writes a NICE program with every pair of side effects on one register.

Usage: sidefx_prog.py OUT.nasm

This is part of step 4 of the test order in MICROARCH.md §9, beside
test/hazard.nasm. The program has two parts, each run for R2 and for R14:

- Within one instruction: SUB with each of the 8 modes in each of its three
  fields, all on the same register, which makes 512 instructions. They
  hold every pair and every triple of side effects on one register
  (ISA.md §4.1 and §4.2), and every read of a register after a side effect
  on it in the same instruction. For R14 they run twice, with M = 0 and
  with M = 1, because the flags of an instruction with a memory
  destination are written after its side effects (ISA.md §6).
- In two instructions: a SUB that writes the register, with a side effect
  or as a register destination, and then a SUB that uses it in one field,
  in any mode. The second comes right after the first, and once more with
  a NOP between them, for the bypasses of MICROARCH.md §5.1.

Each case starts by setting the register to an address in a data region,
so that every address stays in that region and no store reaches the
program. The other register is R3, which holds an address in the same
region, so the first SUB of a pair leaves a register destination with an
address too. The program does not check itself. The makefile compares the
core's trace with the emulator's, which shows every register and memory
write. R15 is left out: its side effects are jumps, and
test/pcfx_prog.py covers them.

The program runs with E = 1, for test/irq_sweep.py, and has vector table
entries for NMI and IRQ at VBASE 0 and at each VBASE that the side
effects on R14 reach from R14_BASE. A SUB with R14 as a register
destination writes it with any value, so E and VBASE too, and the sweep
leaves out a request that would find no vector table there.
"""

import sys

DATA = 0x100000  # The data region, DATA to DATA + 15, above the program
BASE = DATA + 8  # Each case starts with the register here
R14_BASE = 0x41000000 | BASE  # The same for R14, with E = 1, and bit 24 always 1
NMI, IRQ = 8, 9  # The vectors of test/irq_sweep.py
REACH = 6  # How far R14 moves from R14_BASE through side effects alone

# The operand of each mode for register r, with the constant c for the
# modes that take one. Index: mode.
SOURCE = ["{r}", "--{r}", "{r}++", "{c}[{r}]", "@{r}", "@--{r}", "@{r}++", "@{c}[{r}]"]
DEST = ["{r}", "{r}--", "{r}++", "{c}[{r}]", "@{r}", "@--{r}", "@{r}++", "@{c}[{r}]"]
SIDE_EFFECTS = [1, 2, 5, 6]

# The other operands: a register destination that is not the one under
# test, and two sources.
OTHER = ["R4", "R3", "R0"]


def operand(field: int, mode: int, reg: str) -> str:
    """The text of field 0 (dest), 1 (s0), or 2 (s1) in a mode."""
    table = DEST if field == 0 else SOURCE
    return table[mode].format(r=reg, c=field + 1)


def sub(fields: list[str], m: bool) -> str:
    mnemonic = "SUB[M]" if m else "SUB"
    return f"        {mnemonic:<8}" + ", ".join(fields)


def reset(reg: str) -> str:
    return f"                MOVE    {reg}, 0x{R14_BASE if reg == 'R14' else BASE:X}"


def single(reg: str, m: bool) -> list[str]:
    lines = [f"; Every mode in every field of one SUB{'[M]' if m else ''}, on {reg}."]
    for d in range(8):
        for s0 in range(8):
            for s1 in range(8):
                lines.append(reset(reg))
                lines.append(sub([operand(0, d, reg), operand(1, s0, reg), operand(2, s1, reg)], m))
    return lines


def writers(reg: str) -> list[str]:
    """SUBs that write reg: a register destination, or one side effect."""
    out = []
    for field in range(3):
        for mode in ([0] if field == 0 else []) + SIDE_EFFECTS:
            fields = list(OTHER)
            fields[field] = operand(field, mode, reg)
            out.append(sub(fields, False))
    return out


def readers(reg: str) -> list[str]:
    """SUBs that use reg in one field, in any mode."""
    out = []
    for field in range(3):
        for mode in range(8):
            fields = list(OTHER)
            fields[field] = operand(field, mode, reg)
            out.append(sub(fields, False))
    return out


def pairs(reg: str) -> list[str]:
    lines = [f"; A SUB that writes {reg}, then a SUB that uses it, next or one later."]
    for gap in ([], ["                MOVE    R0, R0"]):
        for w in writers(reg):
            for r in readers(reg):
                lines += [reset(reg), w] + gap + [r]
    return lines


def program() -> list[str]:
    lines = [
        "; Written by test/sidefx_prog.py. Every pair of side effects on one",
        "; register, within one instruction and in two.",
        "                MOVE    R15, start",
        f"                .ORG    {NMI}",
        "                .DAT    nmi, irq",
        "nmi     RTI",
        "irq     RTI",
        "start           MOVE    R14, 0x40000000  ; E = 1, VBASE = 0",
        f"                MOVE    R3, 0x{DATA + 4:X}",
    ]
    lines += single("R2", False)
    lines += single("R14", False)
    lines += single("R14", True)
    lines += pairs("R2")
    lines += pairs("R14")
    lines += [
        "                HALT",
        f"                .ORG    0x{DATA:X}",
        "                .DAT    " + ", ".join(f"0x{0x100 + i:X}" for i in range(16)),
    ]
    for vbase in range(BASE - REACH, BASE + REACH + 1):
        lines += [f"                .ORG    0x{vbase << 8 | NMI:X}", "                .DAT    nmi, irq"]
    return lines


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: sidefx_prog.py OUT.nasm")
    with open(sys.argv[1], "w") as f:
        f.write("\n".join(program()) + "\n")


if __name__ == "__main__":
    main()
