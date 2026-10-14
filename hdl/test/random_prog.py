#!/usr/bin/env python3
"""Writes a random NICE program for the multicycle core's tests.

Usage: random_prog.py SEED OUT.bin

The program is a stream of random instructions in the .bin format of
ISA.md §10.4. Word 0 jumps to the program at CODE, away from the small
addresses that registers often hold, and the program ends with a jump back
to its start. So do the other words below DATA, except the vector table.

The instructions are random, with these limits, so that a run lasts long
enough to be worth comparing:
- Ordinary instructions read R15 only in the modes without a side effect,
  and never write it. The other uses of R15 come from templates that keep
  PC on the program (see r15_template): forward jumps, also with an ALU
  operation and the destinations R15++ and R15--; the sources --R15,
  @--R15, R15++, and @R15++; and stores through @R15, @R15++, @--R15, and
  0[R15], which change the program as it runs (ISA.md §8.2).
- Constant words are mostly small numbers, so that shift counts around 32
  and 33 are common, and addresses in a data region. A few are the read
  counter of sim/wb_mem.vhd and the emulator, so that the number and order
  of data reads are compared too. A store through a register can still
  reach the program by chance; both models then run the changed program.
- Control instructions are rare. Most RTIs have the condition ?I, and most
  INTs ?!I. INT inside an interrupt routine and RTI outside one still halt
  the processor now and then, and so do the rarer HALT and reserved
  control words.
- A vector table entry that holds 0 leads to word 0, which restarts the
  program.

The script prints interrupt options for the emulator, such as
"--nmi 12:4 --irq 40:7", on stdout. The same seed always gives the same
program and options.
"""

import random
import sys

INSTRUCTIONS = 300
STEPS = 3000
CODE = 0x10000  # The program
DATA = 0x1000  # The data region
VECTORS = range(4, 8)  # Vector table entries, at VBASE = 0
COUNTER = 0xFFFFFF01  # The read counter (ISA.md §8.3)

# MOVE R15, c: a jump to the constant word that follows.
JUMP = 0x0003D800


def constant(rng: random.Random) -> int:
    kind = rng.random()
    if kind < 0.45:
        return rng.randrange(70)
    if kind < 0.8:
        return DATA + rng.randrange(64)
    if kind < 0.83:
        return COUNTER
    return rng.getrandbits(32)


def operand(rng: random.Random, dest: bool) -> int:
    mode = rng.randrange(8)
    kind = rng.random()
    if kind < 0.03:
        reg = 14
    elif kind < 0.06 and not dest and mode in (0b000, 0b011, 0b100, 0b111):
        reg = 15
    else:
        reg = rng.randrange(14)
    return mode << 4 | reg


def plain(rng: random.Random, cond: int) -> list[int]:
    """An ALU or SHIFT instruction that writes no R15."""
    shift = rng.random() < 0.35
    iw = cond << 28 | (0b10 if shift else rng.randrange(2)) << 26
    iw |= rng.randrange(2) << 25 | rng.randrange(16) << 21
    fields = [operand(rng, True), operand(rng, False), operand(rng, False)]
    iw |= fields[0] << 14 | fields[1] << 7 | fields[2]
    return [iw] + [constant(rng) for f in fields if f & 0x30 == 0x30]


def r15_template(rng: random.Random, cond: int) -> list[int]:
    """An instruction that uses R15 with a side effect, or writes it, such
    that PC stays on the program. A forward jump leaves its target as -1,
    and the jump that follows from it is worked out in main()."""
    alu = rng.randrange(2) << 26 | rng.randrange(2) << 25  # C and M bits
    kind = rng.randrange(4)
    if kind == 0:
        alu &= ~(1 << 26)  # no carry input, so that r = c
        # A jump through dest R15, R15++, or R15--, with MOVE, ADD, SUB, or
        # OR: dest, s0 = c, s1 = 0 (or R0 for MOVE).
        mode = rng.choice((0b000, 0b001, 0b010))
        op = rng.choice((0x0, 0x3, 0x1, 0xF))
        s1 = 0 if op == 0 else 0x30
        iw = cond << 28 | alu | op << 21 | (mode << 4 | 15) << 14 | 0x30 << 7 | s1
        return [iw, -1 - mode] + ([0] if s1 else [])
    if kind == 1:
        # s0 = R15++ or @R15++ skips the padding NOP after the instruction.
        s0 = rng.choice((0x20, 0x60)) | 15
        dest = operand(rng, True)
        iw = cond << 28 | alu | rng.randrange(16) << 21 | dest << 14 | s0 << 7
        consts = [constant(rng)] if dest & 0x30 == 0x30 else []
        return [iw] + consts + [0]
    if kind == 2:
        # s0 = --R15 or @--R15 points PC at the last word, s1's constant 0,
        # which then runs as a NOP.
        s0 = rng.choice((0x10, 0x50)) | 15
        dest = operand(rng, True)
        iw = cond << 28 | alu | rng.randrange(16) << 21 | dest << 14 | s0 << 7 | 0x30
        consts = [constant(rng)] if dest & 0x30 == 0x30 else []
        return [iw] + consts + [0]
    # MOVE @R15, w; MOVE @R15++, w; MOVE @--R15, w; or MOVE 0[R15], w, with
    # w a one-word instruction, followed by a padding NOP. The store puts w
    # in the padding word, or for @--R15 in w's own constant word, and w
    # runs or is skipped.
    w = plain(rng, 0 if rng.random() < 0.7 else rng.randrange(16))
    while len(w) != 1:
        w = plain(rng, 0)
    dest = rng.choice((0x4F, 0x6F, 0x5F, 0x3F))
    iw = cond << 28 | dest << 14 | 0x30 << 7
    return [iw] + ([0] if dest == 0x3F else []) + w + [0]


def instruction(rng: random.Random) -> list[int]:
    """One instruction. A forward jump leaves its target as -1 for MOVE
    R15, c, and -1 - mode for the jumps of r15_template."""
    cond = 0 if rng.random() < 0.7 else rng.randrange(16)
    kind = rng.random()
    if kind < 0.002:
        return [cond << 28 | 0b11 << 26]  # HALT
    if kind < 0.004:
        # A reserved command, or HALT, RTI, or INT with a bit set that must
        # be 0 (ISA.md §5.3).
        bad = rng.choice((rng.randrange(3, 32) << 21, 1 << rng.randrange(8, 21),
                          0b00001 << 21 | 1 << rng.randrange(8), 1 << rng.randrange(8)))
        return [cond << 28 | 0b11 << 26 | bad]
    # RTI mostly with ?I and INT mostly with ?!I, so that they seldom halt.
    if kind < 0.009:
        cond = 0b0111 if rng.random() < 0.8 else cond
        return [cond << 28 | 0b11 << 26 | 0b00001 << 21]  # RTI
    if kind < 0.014:
        cond = 0b1111 if rng.random() < 0.8 else cond
        return [cond << 28 | 0b11 << 26 | 0b00010 << 21 | rng.choice(VECTORS)]  # INT
    if kind < 0.05:
        return r15_template(rng, cond)
    if kind < 0.08:
        return [cond << 28 | JUMP, -1]
    return plain(rng, cond)


def main() -> None:
    seed = int(sys.argv[1])
    rng = random.Random(seed)

    program = [instruction(rng) for _ in range(INSTRUCTIONS)]
    starts = []
    addr = CODE
    for words in program:
        starts.append(addr)
        addr += len(words)
    program.append([JUMP, CODE])  # Run the program again
    starts.append(addr)

    # Words 0 to 0xFFF repeat the jump to CODE, except for the vector table,
    # so that a run of NOPs from a low address soon restarts the program.
    image = {a: (JUMP, CODE)[a % 2] for a in range(DATA)}
    for v in VECTORS:
        image[v] = rng.choice(starts)
    for i, words in enumerate(program):
        # The jump target t is the constant c of dest mode 000 (and of MOVE
        # R15, c), c + 1 for R15-- and c - 1 for R15++, since those store
        # r - 1 and r + 1 (ISA.md §4.2). The template's s1 is 0.
        for j, word in enumerate(words):
            if j > 0 and word in (-1, -2, -3):
                t = rng.choice(starts[i + 1:])
                words[j] = (t + {-1: 0, -2: 1, -3: -1}[word]) & 0xFFFFFFFF
        for j, word in enumerate(words):
            image[starts[i] + j] = word

    with open(sys.argv[2], "w") as f:
        for a, word in sorted(image.items()):
            f.write(f"{a:08x} {word:08x}\n")

    requests = []
    for _ in range(rng.randrange(1, 9)):
        kind = rng.choice(["--nmi", "--irq"])
        requests.append(f"{kind} {rng.randrange(STEPS)}:{rng.choice(VECTORS)}")
    print(" ".join(requests))


if __name__ == "__main__":
    main()
