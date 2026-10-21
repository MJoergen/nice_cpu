#!/usr/bin/env python3
"""Writes a NICE program with every pair of side effects on R15.

Usage: pcfx_prog.py OUT.nasm

This is part of step 4 of the test order in MICROARCH.md §9, beside
test/sidefx_prog.py, which does the same for R2 and R14. Here one ALU
instruction has each of the 8 modes in each of its three fields, all on
R15, which makes 512 instructions. They hold every pair and every triple
of side effects on R15 within one instruction (ISA.md §4.1 to §4.3), and
every read of R15 after a side effect on it. Each side effect is a jump,
and a destination on R15 jumps to the result, so each instruction sits in
a block of its own, with words around it that lead to the next block:

    bK      MOVE    R11, bK+1           ; for the words J
            MOVE    R12, bK+1-start     ; for the trampoline
            ADD[M]  R1, R1, 1           ; counts the blocks
            J, J, J, J                  ; J is MOVE PC, R11
    aK      the instruction
            F, F, F, F, F, F, F, F      ; F is J or 0, a NOP

A jump to an address up to TRAMPOLINE runs NOPs into the trampoline,
ADD PC, R12, start. A jump into the top 16 words runs the NOPs that an
instruction fetch from the I/O range reads (ISA.md §8.3), and wraps to
address 0. Reset starts at address 0 too, with R12 = 0.

The program runs with E = 1 and VBASE = 0, for test/irq_sweep.py. Words
8 and 9 are the vector table entries for NMI and IRQ. They point to
routines at 14 and 15, each an RTI, and as instructions they are
MOVE R0, R0, R14 and MOVE R0, R0, R15, which only write R0, so a jump
that runs through them still reaches the trampoline:

    0       NOP, ..., NOP
    8       14, 15                      ; vectors 8 and 9
    10      ADD     PC, R12, start      ; the trampoline
    14      RTI
    15      RTI

The instruction reads the words around it and its own words, and it may
store into a word that runs next, so its operation, its constants, and
its address decide where it goes. The script models it (ISA.md §4 and §5)
and takes the first form whose reads and store stay within its block, and
that lands on a J, the next block, the trampoline, or the top of memory,
through words that only write R0, such as a NOP or a constant 0. A
landing on the instruction itself would run it again, which is allowed
only when it is guarded (GUARDS) and skipped the second time. It tries
OPS, CONSTS, FILLS, and GUARDS in that order, first in the block's own
place, then near the addresses that places() names.

R1 counts the blocks. The program checks itself: R12 is 0 at the end only
if every block ran once. The makefile compares the core's trace with the
emulator's, which shows every register and memory write and every jump.
"""

import itertools
import sys
from typing import Callable, Iterator

MASK = 0xFFFFFFFF
NMI, IRQ = 8, 9  # The vectors of test/irq_sweep.py
TRAMPOLINE = 10  # ADD PC, R12, start: two words
START = 0x10
BASE = 0x100  # The first block
BLOCK = 32  # Words per block
HEAD = 6  # The three instructions at the start of a block
PRE = 4  # The words J in front of the instruction
POST = 8  # The words F after it
PLACE = 40  # How far from a word read the instruction may be placed
TOP = 0xFFFFFFF0  # A jump at or above this runs NOPs to address 0

# The encoding of MOVE PC, R11 (ISA.md §2.1): dest R15, s0 R11, mode 000.
J = (15 << 14) | (11 << 7)

# Opcode and result of the operations tried, in order (ISA.md §5.1).
OPS: list[tuple[str, int, Callable[[int, int], int]]] = [
    ("SUB", 0b0001, lambda a, b: a - b),
    ("ADD", 0b0011, lambda a, b: a + b),
    ("XOR", 0b1010, lambda a, b: a ^ b),
    ("AND", 0b1101, lambda a, b: a & b),
    ("OR", 0b1111, lambda a, b: a | b),
]
CONSTS = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5]
FILLS = [J, 0]  # The words F tried, in order: J, or a NOP
# The conditions tried, in order: none, then ?!Z and ?!N, with M set. The
# instruction runs, since the block's ADD[M] clears Z and N, and if its
# result sets the flag, it is skipped when it runs a second time. Each has
# NEG and SEL (ISA.md §3), and whether a result sets the flag.
GUARDS: dict[str, tuple[int, Callable[[int], bool]]] = {
    "": (0, lambda r: False),
    "Z": (0xB, lambda r: r == 0),
    "N": (0xC, lambda r: r >> 31 == 1),
}

SOURCE = ["R15", "--R15", "R15++", "{c}[R15]", "@R15", "@--R15", "@R15++", "@{c}[R15]"]
DEST = ["R15", "R15--", "R15++", "{c}[R15]", "@R15", "@--R15", "@R15++", "@{c}[R15]"]


class Reject(Exception):
    """The instruction leaves its block, or lands on a word that is not safe."""


def encode(op: int, modes: tuple[int, ...], guard: str) -> int:
    """The instruction word, with R15 in every field (ISA.md §2.1 and §2.2).

    With guard Z or N, it is ?!Z OP[M] or ?!N OP[M] (ISA.md §3).
    """
    dest, s0, s1 = (m << 4 | 15 for m in modes)
    cond = GUARDS[guard][0] << 28 | 1 << 25 if guard else 0
    return cond | op << 21 | dest << 14 | s0 << 7 | s1


def run(a: int, modes: tuple[int, ...], op: int, consts: list[int], fill: int, guard: str) -> None:
    """Models the instruction at a, and what runs after it up to the next block.

    modes are dest, s0, and s1, consts the constant words in that order,
    fill the words F, and guard the flag of GUARDS that it tests, if any.
    Raises Reject unless the instruction is safe.
    """
    words = [a + i for i in range(1 + len(consts))]
    lo, hi = a - PRE, a - PRE - HEAD + BLOCK
    mem = {addr: J if addr < a else fill for addr in range(lo, hi)}
    iw = encode(op, modes, guard)
    mem[a] = iw
    for addr, c in zip(words[1:], consts):
        mem[addr] = c & MASK
    taken = iter(consts)
    c_of = [next(taken) if m & 3 == 3 else 0 for m in modes]
    pc = a + len(words)

    def inside(addr: int) -> int:
        if not lo <= addr < hi:
            raise Reject
        return addr

    values = []
    for mode, c in zip(modes[1:], c_of[1:]):
        if mode in (1, 5):
            pc -= 1
        v = pc + c if mode == 3 else pc
        if mode >= 4:
            v = mem[inside((pc + c) & MASK if mode == 7 else pc)]
        if mode in (2, 6):
            pc += 1
        values.append(v & MASK)
    r = next(f for _, o, f in OPS if o == op)(values[0], values[1]) & MASK
    mode, c = modes[0], c_of[0]
    if mode < 3:
        pc = r + (0, -1, 1)[mode]
    else:
        if mode == 5:
            pc -= 1
        addr = (pc + c) & MASK if mode in (3, 7) else pc
        mem[inside(addr)] = r
        if mode == 6:
            pc += 1
    mem[hi] = J  # The next block, which is as safe
    # A guarded instruction that sets its flag is skipped if it runs again.
    skip = {a: a + len(words)} if guard and GUARDS[guard][1](r) else {}
    land(pc & MASK, mem, skip, iw)


def harmless(w: int) -> bool:
    """Whether word w runs as an ALU or SHIFT instruction that only writes R0.

    Its destination is R0 and its sources registers, so it takes no
    constant word, makes no data access, and has no side effect. It may
    change the flags. 0 is one, the NOP.
    """
    return (w >> 26) & 3 != 3 and (w >> 14) & 0x7F == 0 and (w >> 11) & 7 == 0 and (w >> 4) & 7 == 0


def land(pc: int, mem: dict[int, int], skip: dict[int, int], iw: int) -> None:
    """Follows the harmless words from pc to a J, the next block, or the
    trampoline. skip holds the address of an instruction iw that would be
    skipped, unless a harmless word changed the flags, and where it ends."""
    for _ in range(BLOCK):
        if pc <= TRAMPOLINE or pc >= TOP or mem.get(pc) == J:
            return
        if pc in skip and mem[pc] == iw:
            pc = skip[pc]
            continue
        if pc not in mem or not harmless(mem[pc]):
            raise Reject
        if mem[pc] >> 25 & 1:
            skip = {}
        pc += 1
    raise Reject


def places(modes: tuple[int, ...]) -> Iterator[int]:
    """Addresses to try for the instruction, when its block's own fails.

    A result that combines the instruction's address with a word it reads,
    its own or a J, is safe with the instruction near that word, or near
    half of it. A result that it stores and runs next is safe when it is a
    J, with the instruction near the difference of the two words, or when
    it is 0 and the instruction is guarded: a AND (a - 1) is 0 when a is a
    power of 2.
    """
    bases = [J, J // 2] + [1 << k for k in range(9, 31)]
    for guard in GUARDS:
        for _, op, _ in OPS:
            iw = encode(op, modes, guard)
            bases += [iw, iw // 2, iw - J, (J - iw) & MASK, iw ^ J]
    for base in dict.fromkeys(bases):
        for d in range(-PLACE, PLACE + 1):
            if BASE <= base + d - PRE - HEAD < TOP - BLOCK:
                yield base + d


Form = tuple[int, str, list[int], int, str]  # Address, operation, constants, F, and guard


def form(a: int, modes: tuple[int, ...]) -> Form | None:
    """The first words F, operation, and constants that make the instruction
    at a safe, if any."""
    n = sum(m & 3 == 3 for m in modes)
    for guard, fill in itertools.product(GUARDS, FILLS):
        for name, op, _ in OPS:
            for consts in itertools.product(CONSTS, repeat=n):
                try:
                    run(a, modes, op, list(consts), fill, guard)
                except Reject:
                    continue
                return a, name, list(consts), fill, guard
    return None


def layout(cases: list[tuple[int, ...]]) -> list[Form]:
    """A safe form for each case, each in a block that overlaps no other.

    Case k takes block BASE + BLOCK * k if it can. The others go to the
    first place of places() that is safe and free.
    """
    forms: list[Form | None] = [form(BASE + BLOCK * k + HEAD + PRE, m) for k, m in enumerate(cases)]
    used = {BASE + BLOCK * k for k, f in enumerate(forms) if f} | {BASE + BLOCK * len(cases)}
    for k, m in enumerate(cases):
        if forms[k]:
            continue
        for a in dict.fromkeys(places(m)):
            b = a - PRE - HEAD
            if all(abs(b - u) >= BLOCK for u in used):
                forms[k] = form(a, m)
                if forms[k]:
                    used.add(b)
                    break
        else:
            sys.exit(f"pcfx_prog.py: no safe form for modes {m}")
    return [f for f in forms if f]


def program() -> list[str]:
    lines = [
        "; Written by test/pcfx_prog.py. Every mode in every field of one",
        "; instruction, all on R15. R1 counts the blocks, and R12 is 0 at the",
        "; end only if every block ran once.",
        "        .ORG    0",
        f"        .DAT    {', '.join(['0'] * NMI)}",
        "        .DAT    nmi, irq",
        "        ADD     R15, R12, start",
        "        .ORG    14",
        "nmi     RTI",
        "irq     RTI",
        f"        .ORG    0x{START:X}",
        "start   MOVE    R14, 0x40000000 ; E = 1, VBASE = 0",
        "        MOVE    R1, 0",
        "        MOVE    R15, b0",
    ]
    cases = list(itertools.product(range(8), repeat=3))
    end = BASE + BLOCK * len(cases)
    blocks = []
    for k, (modes, (a, name, consts, fill, guard)) in enumerate(zip(cases, layout(cases))):
        b = a - PRE - HEAD
        taken = iter(consts)
        fields = []
        for i, m in enumerate(modes):
            text = (DEST if i == 0 else SOURCE)[m]
            fields.append(text.format(c=next(taken)) if m & 3 == 3 else text)
        blocks.append((b, [
            f"        .ORG    0x{b:X}",
            f"b{k:<6}MOVE    R11, b{k + 1}",
            f"        MOVE    R12, b{k + 1}-start",
            "        ADD[M]  R1, R1, 1       ; Z = 0 and N = 0",
            f"        .DAT    {', '.join([f'0x{J:X}'] * PRE)}",
            f"        ?!{guard} {name}[M] {', '.join(fields)}" if guard else f"        {name:<8}{', '.join(fields)}",
            f"        .DAT    {', '.join([f'0x{fill:X}'] * POST)}",
        ]))
    blocks.append((end, [
        f"        .ORG    0x{end:X}",
        f"b{len(cases):<6}MOVE    R12, 1",
        f"        SUB[M]  R0, R1, {len(cases)}",
        "        ?Z MOVE R12, 0",
        "        HALT",
    ]))
    for _, block in sorted(blocks):
        lines += block
    return lines


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: pcfx_prog.py OUT.nasm")
    with open(sys.argv[1], "w") as f:
        f.write("\n".join(program()) + "\n")


if __name__ == "__main__":
    main()
