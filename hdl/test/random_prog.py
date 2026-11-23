#!/usr/bin/env python3
"""Writes a random NICE program for the tests of both cores.

Usage: random_prog.py SEED OUT.bin

The program is a stream of random instructions in the .bin format of
ISA.md §10.4. Word 0 jumps to the program at CODE, away from the small
addresses that registers often hold, and the program ends with a jump back
to its start.

The instructions are random, with these limits, so that a run lasts long
enough to be worth comparing:
- Ordinary instructions read R15 only in the modes without a side effect,
  and never write it. The other uses of R15 come from templates that keep
  PC on the program (see r15_template): forward jumps, also with an ALU
  operation or a shift and the destinations R15++ and R15--; the sources --R15,
  @--R15, R15++, and @R15++; and stores through @R15, @R15++, @--R15, and
  0[R15], which change the program as it runs (ISA.md §8.2).
- Constant words are mostly small numbers, so that shift counts around 32
  and 33 are common, and addresses in a data region. A few are the read
  counter of sim/wb_mem.vhd and the emulator, so that the number and order
  of data reads are compared too. A store through a register can still
  reach the program by chance; both models then run the changed program.
- The jumps of one word go forward like the others, JMP and CALL, or
  back like the predicted ADD R15, R15, c, JMPR (ISA.md §5.3). A CALL
  pushes through R13, which points into the data region.
- The other control instructions are rare: HALT and the reserved control
  words, which halt the processor. They always have a condition, so that
  they halt now and then.
- A memory destination is never @R0, @--R0, or @R0++, which store to
  word 0.
- A source or base register is often one that the last three
  instructions wrote, so that a register is often read right after it is
  written (MICROARCH.md §5.1).
- Most forward jumps skip only a few instructions, so that most of the
  program runs before the jump back to its start.
- The program starts by pointing R1 to R13 into the data region, so that
  fewer stores reach the low words. The words below DATA restart the
  program, so that a jump to a small address, or a run of NOPs from one,
  soon goes back to it.

test/random_stats.py shows how the runs spend their steps, and how often
they make the hazards of MICROARCH.md §5. The same seed always gives the
same program.
"""

import random
import sys

INSTRUCTIONS = 300
CODE = 0x10000  # The program
DATA = 0x1000  # The data region
M_CHANCE = 0.75  # The chance that an ALU or SHIFT instruction sets the flags (M = 1)
LOCAL = 0.4  # The chance that a register field takes a register written just before
NEAR = 0.9  # The chance that a forward jump skips at most JUMP_SPAN - 1 instructions
JUMP_SPAN = 5
BACK_SPAN = 12  # How far back a predicted jump goes, in instructions
COUNTER = 0xFFFFFF01  # The read counter (DEVICES.md §1)

# MOVE R15, c: a jump to the constant word that follows.
JUMP = 0x0003D800
# The jumps and the call of one word, by their command (ISA.md §5.3): the
# distance is in bits 20..0.
SHORT_JMP, SHORT_JMPR, SHORT_CALL = 4, 5, 6
# A word 0 below this marks a jump or a call of one word whose distance
# main() works out: SHORT_MARK - (cond << 3 | command), forward for JMP and
# CALL, and back for JMPR.
SHORT_MARK = -100
MOVE_C = 0x00001800  # MOVE R0, c: add the destination register << 14


def constant(rng: random.Random) -> int:
    kind = rng.random()
    if kind < 0.45:
        return rng.randrange(70)
    if kind < 0.8:
        return DATA + rng.randrange(64)
    if kind < 0.83:
        return COUNTER
    return rng.getrandbits(32)


def operand(rng: random.Random, dest: bool, recent: list[list[int]]) -> int:
    """An operand field. recent holds the registers that each of the last
    three instructions wrote."""
    mode = rng.randrange(8)
    kind = rng.random()
    written = [reg for regs in recent for reg in regs]
    # R14 as a register destination changes the flags that the conditions
    # test, so it is rarer than as a source.
    if kind < (0.01 if dest and mode in (0b000, 0b001, 0b010) else 0.03):
        reg = 14
    elif kind < 0.06 and not dest and mode in (0b000, 0b011, 0b100, 0b111):
        reg = 15
    elif written and (not dest or mode != 0b000) and rng.random() < LOCAL:
        # A source, a base, or the register of a side effect.
        reg = rng.choice(written)
    else:
        # @R0, @--R0, and @R0++ as a destination store to word 0
        # (ISA.md §4.3), the jump back to the program (see main()).
        reg = rng.randrange(1 if dest and mode in (0b100, 0b101, 0b110) else 0, 14)
    return mode << 4 | reg


def written(fields: list[int]) -> list[int]:
    """The registers that an instruction with these fields writes, R15
    left out: a register destination, and every side effect."""
    regs = [f & 15 for f in fields[1:] if f >> 4 in (1, 2, 5, 6)]
    if fields[0] >> 4 in (0, 1, 2, 5, 6):
        regs.append(fields[0] & 15)
    return [reg for reg in regs if reg not in (0, 15)]


def remember(recent: list[list[int]], regs: list[int]) -> None:
    recent.append(regs)
    if len(recent) > 3:
        recent.pop(0)


def plain(rng: random.Random, cond: int, recent: list[list[int]]) -> list[int]:
    """An ALU or SHIFT instruction that writes no R15."""
    shift = rng.random() < 0.35
    iw = cond << 28 | (0b10 if shift else rng.randrange(2)) << 26
    iw |= (rng.random() < M_CHANCE) << 25 | rng.randrange(16) << 21
    fields = [operand(rng, True, recent), operand(rng, False, recent), operand(rng, False, recent)]
    iw |= fields[0] << 14 | fields[1] << 7 | fields[2]
    remember(recent, written(fields))
    # The constant of a destination is mostly an address in the data
    # region, so that few stores reach the low words.
    consts = [constant(rng) for f in fields if f & 0x30 == 0x30]
    if fields[0] & 0x30 == 0x30 and rng.random() < 0.8:
        consts[0] = DATA + rng.randrange(64)
    return [iw] + consts


def r15_template(rng: random.Random, cond: int, recent: list[list[int]]) -> list[int]:
    """An instruction that uses R15 with a side effect, or writes it, such
    that PC stays on the program. A forward jump leaves its target as -1,
    and the jump that follows from it is worked out in main()."""
    alu = rng.randrange(2) << 26 | rng.randrange(2) << 25  # C and M bits
    kind = rng.randrange(4)
    if kind == 0:
        alu &= ~(1 << 26)  # no carry input, so that r = c
        # A jump through dest R15, R15++, or R15--, with MOVE, ADD, SUB, or
        # OR: dest, s0 = c, s1 = 0 (or R0 for MOVE). Or the shift 0<0 R15,
        # c, 1, whose target is 2c: the opcode of MOVE in the shift class.
        if rng.random() < 0.2:
            iw = cond << 28 | alu | 1 << 27 | 15 << 14 | 0x30 << 7 | 0x30
            return [iw, -4, 1]
        mode = rng.choice((0b000, 0b001, 0b010))
        op = rng.choice((0x0, 0x3, 0x1, 0xF))
        s1 = 0 if op == 0 else 0x30
        iw = cond << 28 | alu | op << 21 | (mode << 4 | 15) << 14 | 0x30 << 7 | s1
        return [iw, -1 - mode] + ([0] if s1 else [])
    if kind == 1:
        # s0 = R15++ or @R15++ skips the padding NOP after the instruction.
        s0 = rng.choice((0x20, 0x60)) | 15
        dest = operand(rng, True, recent)
        iw = cond << 28 | alu | rng.randrange(16) << 21 | dest << 14 | s0 << 7
        consts = [constant(rng)] if dest & 0x30 == 0x30 else []
        return [iw] + consts + [0]
    if kind == 2:
        # s0 = --R15 or @--R15 points PC at the last word, s1's constant 0,
        # which then runs as a NOP.
        s0 = rng.choice((0x10, 0x50)) | 15
        dest = operand(rng, True, recent)
        iw = cond << 28 | alu | rng.randrange(16) << 21 | dest << 14 | s0 << 7 | 0x30
        consts = [constant(rng)] if dest & 0x30 == 0x30 else []
        return [iw] + consts + [0]
    # MOVE @R15, w; MOVE @R15++, w; MOVE @--R15, w; or MOVE 0[R15], w, with
    # w a one-word instruction, followed by a padding NOP. The store puts w
    # in the padding word, or for @--R15 in w's own constant word, and w
    # runs or is skipped.
    w = plain(rng, 0 if rng.random() < 0.7 else rng.randrange(16), recent)
    while len(w) != 1:
        w = plain(rng, 0, recent)
    dest = rng.choice((0x4F, 0x6F, 0x5F, 0x3F))
    iw = cond << 28 | dest << 14 | 0x30 << 7
    return [iw] + ([0] if dest == 0x3F else []) + w + [0]


def back_jump(rng: random.Random) -> list[int]:
    """A conditional ADD R15, R15, c, with R15 in either source, which
    DECODE predicts taken for a negative c. A -5 leaves the offset to a
    start among the last BACK_SPAN instructions, worked out in main(). The
    C and M bits are 0, so that the result is R15 + c."""
    cond = rng.randrange(1, 16)
    if rng.random() < 0.5:
        s0, s1 = 15, 0x30
    else:
        s0, s1 = 0x30, 15
    if rng.random() < 0.5:
        return [SHORT_MARK - (cond << 3 | SHORT_JMPR)]
    return [cond << 28 | 0x3 << 21 | 15 << 14 | s0 << 7 | s1, -5]


def instruction(rng: random.Random, recent: list[list[int]]) -> list[int]:
    """One instruction. A forward jump leaves its target as -1 for MOVE
    R15, c, -1 - mode for the jumps of r15_template, and -4 for its shift,
    whose constant is half the target."""
    cond = 0 if rng.random() < 0.7 else rng.randrange(16)
    kind = rng.random()
    # HALT and the reserved words are rare, because most of the program
    # runs on each pass. They always have a condition, so that they halt
    # now and then.
    if kind < 0.0003:
        cond = rng.randrange(1, 16)
    if kind < 0.0001:
        return [cond << 28 | 0b11 << 26]  # HALT
    if kind < 0.0003:
        # A reserved command, with or without other bits, or HALT with a
        # bit of 20 to 0 set (ISA.md §5.3).
        # The commands 4 to 6 are the jumps and the call of one word.
        cmd = rng.choice([c for c in range(1, 32) if c not in (4, 5, 6)])
        bad = rng.choice((cmd << 21, cmd << 21 | rng.getrandbits(21), 1 << rng.randrange(21)))
        return [cond << 28 | 0b11 << 26 | bad]
    if kind < 0.05:
        return r15_template(rng, cond, recent)
    if kind < 0.07:
        return back_jump(rng)
    if kind < 0.15:
        # Jumps are about a fifth of the instructions in the benchmark
        # (MICROARCH.md §5.6), and half of these are conditional.
        if rng.random() < 0.5:
            cond = rng.randrange(1, 16)
        # Half of them are the JMP and the CALL of one word.
        if rng.random() < 0.5:
            return [SHORT_MARK - (cond << 3 | rng.choice((SHORT_JMP, SHORT_CALL)))]
        return [cond << 28 | JUMP, -1]
    return plain(rng, cond, recent)


def main() -> None:
    seed = int(sys.argv[1])
    rng = random.Random(seed)

    recent: list[list[int]] = []
    # The program starts by pointing R1 to R13 into the data region, so
    # that fewer stores reach the low words.
    prologue = [[MOVE_C | reg << 14, DATA + 4 * reg] for reg in range(1, 14)]
    program = prologue + [instruction(rng, recent) for _ in range(INSTRUCTIONS)]
    starts = []
    addr = CODE
    for words in program:
        starts.append(addr)
        addr += len(words)
    # Run the program again.
    program.append([JUMP, CODE])
    starts.append(addr)

    # Words 0 to 0xFFF repeat the jump to CODE, so that a run of NOPs from
    # a low address soon restarts the program.
    image = {a: (JUMP, CODE)[a % 2] for a in range(DATA)}
    for i, words in enumerate(program):
        # The jump target t is the constant c of dest mode 000 (and of MOVE
        # R15, c), c + 1 for R15-- and c - 1 for R15++, since those store
        # r - 1 and r + 1 (ISA.md §4.2), and 2c for the shift. The
        # template's s1 is 0, or 1 for the shift.
        for j, word in enumerate(words):
            if j == 0 and word <= SHORT_MARK:
                cond, cmd = (SHORT_MARK - word) >> 3, (SHORT_MARK - word) & 7
                if cmd == SHORT_JMPR:
                    t = rng.choice(starts[max(0, i - BACK_SPAN) : i + 1])
                else:
                    near = starts[i + 1 : i + JUMP_SPAN]
                    t = rng.choice(near if near and rng.random() < NEAR else starts[i + 1:])
                d = t - (starts[i] + 1)
                words[j] = cond << 28 | 0b11 << 26 | cmd << 21 | d & 0x1FFFFF
            elif j > 0 and word == -5:
                # R15 is the address after the constant, so the offset is
                # the target less that.
                back = starts[max(0, i - BACK_SPAN) : i + 1]
                words[j] = (rng.choice(back) - (starts[i] + len(words))) & 0xFFFFFFFF
            elif j > 0 and word in (-1, -2, -3, -4):
                near = starts[i + 1 : i + JUMP_SPAN]
                later = starts[i + 1:]
                if word == -4:
                    # The shift doubles its constant, so the target is even:
                    # one of the even starts ahead, or the program's.
                    near = [s for s in near if s % 2 == 0]
                    later = [s for s in later if s % 2 == 0] or [CODE]
                t = rng.choice(near if near and rng.random() < NEAR else later)
                words[j] = (t + {-1: 0, -2: 1, -3: -1, -4: 0}[word]) & 0xFFFFFFFF
                if word == -4:
                    words[j] >>= 1
        for j, word in enumerate(words):
            image[starts[i] + j] = word

    with open(sys.argv[2], "w") as f:
        for a, word in sorted(image.items()):
            f.write(f"{a:08x} {word:08x}\n")


if __name__ == "__main__":
    main()
