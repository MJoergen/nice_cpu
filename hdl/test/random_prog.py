#!/usr/bin/env python3
"""Writes a random NICE program for the multicycle core's tests.

Usage: random_prog.py SEED OUT.bin

The program is a stream of random instructions in the .bin format of
ISA.md §10.4. Word 0 jumps to the program at CODE, away from the small
addresses that registers often hold, and the program ends with a jump back
to its start. So do the other words below DATA, except the vector table.

The instructions are random, with these limits, so that a run lasts long
enough to be worth comparing:
- Only forward jumps write R15, so the program never loops on the spot.
  Sources read R15 only in the modes without a side effect, so PC never
  lands in a constant word.
- Constant words are mostly small numbers, so that shift counts around 32
  and 33 are common, and addresses in a data region. No store reaches the
  program.
- Control instructions are rare. Most RTIs have the condition ?I, and most
  INTs ?!I. INT inside an interrupt routine and RTI outside one still halt
  the processor now and then.
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

# MOVE R15, c: a jump to the constant word that follows.
JUMP = 0x0003D800


def constant(rng: random.Random) -> int:
    kind = rng.random()
    if kind < 0.45:
        return rng.randrange(70)
    if kind < 0.8:
        return DATA + rng.randrange(64)
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


def instruction(rng: random.Random) -> list[int]:
    """One instruction. A forward jump leaves its target as -1."""
    cond = 0 if rng.random() < 0.7 else rng.randrange(16)
    kind = rng.random()
    # RTI mostly with ?I and INT mostly with ?!I, so that they seldom halt.
    if kind < 0.005:
        cond = 0b0111 if rng.random() < 0.8 else cond
        return [cond << 28 | 0b11 << 26 | 0b00001 << 21]  # RTI
    if kind < 0.01:
        cond = 0b1111 if rng.random() < 0.8 else cond
        return [cond << 28 | 0b11 << 26 | 0b00010 << 21 | rng.choice(VECTORS)]  # INT
    if kind < 0.05:
        return [cond << 28 | JUMP, -1]
    shift = kind < 0.4
    iw = cond << 28 | (0b10 if shift else rng.randrange(2)) << 26
    iw |= rng.randrange(2) << 25 | rng.randrange(16) << 21
    fields = [operand(rng, True), operand(rng, False), operand(rng, False)]
    iw |= fields[0] << 14 | fields[1] << 7 | fields[2]
    return [iw] + [constant(rng) for f in fields if f & 0x30 == 0x30]


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
        if words[-1] == -1:
            words[-1] = rng.choice(starts[i + 1:])
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
