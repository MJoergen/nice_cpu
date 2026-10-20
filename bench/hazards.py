#!/usr/bin/env python3
"""How often the pipeline hazards of doc/MICROARCH.md §5 occur in a program.

    ./hazards.py FILE...      profile each program
    ./hazards.py --test       check the counts on a small program

A FILE that ends in .bin is run on the emulator with --trace. The emulator
is ../emulator/zig-out/bin/niceemu next to this script, or $NICEEMU. Any
other FILE is a trace that "niceemu --trace" wrote.

Each instruction in the trace is decoded (ISA.md §2 and §4) into the
registers it reads and writes, its data accesses, its constant words, and
its micro-operations (MICROARCH.md §4). Each count compares an instruction
with the one, two, or three before it. A skipped instruction counts as if
it ran, because DECODE sees its operands before the condition is known, so
a register it would write counts as written. An interrupt entry starts the
sequence afresh, as it flushes the pipeline. The console output in the
trace and the lines after the halt are skipped (steps(), which
pipecycles.py reads a trace with too).

The last counts are for a core that forms every operand value, address,
and shift count in PREPARE, the rules of pipecycles.py's --shift-mem,
--shift-reg, --sum-wait, and --dest-adjust: shifts by the kind of their
count, counts, sums, and store pointers whose register the previous
instruction writes, the taken jumps that WRITE resolves by their
target, and register destinations with a side effect.
"""

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Dict, FrozenSet, Iterable, Iterator, List, Optional, Tuple

# The modes of ISA.md §4: those with a side effect on the register, those
# that read memory as a source, and those that take a constant word.
SIDE_EFFECT = {1, 2, 5, 6}
MEMORY = {4, 5, 6, 7}
CONSTANT = {3, 7}


@dataclass
class Instr:
    """What DECODE learns from one instruction word."""

    conditional: bool          # The condition is not "always"
    control: bool              # HALT, RTI, INT, or a reserved word
    reads: FrozenSet[int]      # Registers read as operands or bases, R0 left out
    writes: FrozenSet[int]     # Registers written by the result or a side effect
    mem_reads: int             # Data reads
    store: bool                # Writes memory
    words: int                 # The instruction word and its constant words
    uops: int                  # Micro-operations of MICROARCH.md §4
    sr_write: bool             # Writes SR: M = 1, R14 written, or control
    redirect: bool             # Writes R15, or control
    early_jump: bool           # A jump that DECODE resolves (MICROARCH.md §5.4)
    r15_known: bool            # Reads R15 in mode 000 or 011, where DECODE knows PC
    r15_pointer: bool          # R15 as a pointer or base, or with a side effect
    skipped: bool = False
    # For the rules of a core that forms every operand value, address, and
    # shift count in PREPARE (pipecycles.py's --shift-mem and the like).
    # R0 and R15, which DECODE knows, count as constants.
    shift_count: str = ""      # A shift's count: "constant", "register", "adder", or "memory"
    count_reg: int = 0         # The register of a shift's count, if one
    sum_regs: FrozenSet[int] = frozenset()  # Registers of sources in modes 001 and 011
    store_sum_reg: int = 0     # The register of a store's address in mode 011, 101, or 111
    store_ptr_reg: int = 0     # The register of a store through @R or @R++
    jump_kind: str = ""        # A jump WRITE resolves: "constant", "memory", or "computed"
    dest_adjust: bool = False  # A register destination in mode 001 or 010
    reg_jump: bool = False     # An early_jump through a register, which WRITE resolves


def decode(iw: int) -> Instr:
    conditional = ((iw >> 31) & 1, (iw >> 28) & 7) != (0, 0)
    if (iw >> 26) & 3 == 3:
        return Instr(conditional, True, frozenset(), frozenset(), 0, False, 1, 1,
                     True, True, False, False, False)
    m = (iw >> 25) & 1
    dm, dr = (iw >> 18) & 7, (iw >> 14) & 15
    sources = (((iw >> 11) & 7, (iw >> 7) & 15), ((iw >> 4) & 7, iw & 15))
    reads = set()
    writes = set()
    mem_reads = constants = 0
    uops = 1
    r15_known = r15_pointer = False
    for mode, reg in sources:
        if reg == 15:
            if mode in (0, 3):
                r15_known = True
            else:
                r15_pointer = True
        if reg != 0:
            reads.add(reg)
            if mode in SIDE_EFFECT:
                writes.add(reg)
                uops += 1
        if mode in MEMORY:
            mem_reads += 1
        if mode in CONSTANT:
            constants += 1
    if dm in CONSTANT:
        constants += 1
    store = dm >= 3  # Mode 011 is an alias of 111 (ISA.md §4.2)
    if store:
        if dr != 0:
            reads.add(dr)
            if dm in SIDE_EFFECT:
                writes.add(dr)
        if dr == 15:
            r15_pointer = True
    elif dr != 0:
        writes.add(dr)
    early_jump = not conditional and dm == 0 and dr == 15 and mem_reads == 0
    d = Instr(conditional, False, frozenset(reads), frozenset(writes), mem_reads, store,
              constants + 1, uops, bool(m) or 14 in writes, 15 in writes, early_jump,
              r15_known, r15_pointer)
    known = (0, 15)
    (m0, r0), (m1, r1) = sources
    if (iw >> 27) & 1:
        if m1 in MEMORY:
            d.shift_count = "memory"
        elif r1 in known:
            d.shift_count = "constant"
        else:
            # Through an adder, c[R] or --R, WRITE reduces the count in a
            # cycle of its own (MICROARCH.md §7.3), whoever wrote R.
            d.shift_count = "adder" if m1 in (1, 3) else "register"
            d.count_reg = r1
    # DECODE resolves only MOVE R15, c and ADD R15, R15, c (MICROARCH.md
    # §5.4). early_jump counts every unconditional jump to R15 in mode 000
    # that reads no memory; this row shows the others among them.
    f1, f2 = (iw >> 7) & 0x7F, iw & 0x7F
    shift = (iw >> 27) & 1
    op = (iw >> 21) & 15
    resolved = not shift and ((op == 0 and f1 == 0x30 and f2 == 0) or
                              (op == 3 and not (iw >> 26) & 1 and {f1, f2} == {0x0F, 0x30}))
    d.reg_jump = early_jump and not resolved
    d.sum_regs = frozenset(r for mode, r in sources if mode in (1, 3) and r not in known)
    if dr not in known:
        if dm in (3, 5, 7):
            d.store_sum_reg = dr
        elif dm in (4, 6):
            d.store_ptr_reg = dr
    d.dest_adjust = dm in (1, 2) and dr != 0
    if 15 in writes and not early_jump:
        move = not (iw >> 27) & 1 and (iw >> 21) & 15 == 0
        if move and dm == 0 and dr == 15 and (m0, r0) == (3, 0):
            d.jump_kind = "constant"
        elif move and dm == 0 and dr == 15 and m0 in MEMORY:
            d.jump_kind = "memory"
        else:
            d.jump_kind = "computed"
    return d


LABELS = [
    "conditional",
    "conditional with a data read",
    "data read",
    "two data reads",
    "store",
    "jump: writes R15, or control",
    "conditional jump",
    "jump that DECODE resolves",
    "the same, through a register, which WRITE resolves",
    "writes SR",
    "conditional, SR written by the previous instruction",
    "conditional, SR written two back, not one",
    "conditional with a data read, SR written by the previous",
    "data read after a store",
    "data read after a conditional jump",
    "reads a register the previous instruction writes",
    "the same, R13 only",
    "reads a register written two back, not one",
    "reads a register written three back, not one or two",
    "R14 read as an operand or base",
    "R14 written as a register",
    "R15 read where DECODE knows PC",
    "R15 as a pointer, or with a side effect",
    "shift, count a constant",
    "shift, count a register",
    "shift, count in memory",
    "shift, count through an adder (c[R] or --R)",
    "shift count register written by the previous instruction",
    "source in mode 001 or 011, register from the previous",
    "store in mode 011, 101, or 111, register from the previous",
    "store through @R or @R++, R from the previous",
    "taken jump resolved in WRITE, to a constant",
    "taken jump resolved in WRITE, to a word in memory",
    "taken jump resolved in WRITE, to a computed target",
    "register destination in mode 001 or 010",
]


class Profile:
    """The counts for one program."""

    def __init__(self) -> None:
        self.instructions = 0
        self.skipped = 0
        self.words: Dict[int, int] = {}
        self.uops: Dict[int, int] = {}
        self.counts: Dict[str, int] = {label: 0 for label in LABELS}
        self.raw_regs: Dict[int, int] = {}
        self.history: List[Instr] = []

    def interrupt(self) -> None:
        self.history.clear()

    def add(self, d: Instr) -> None:
        c = self.counts
        self.instructions += 1
        self.skipped += d.skipped
        self.words[d.words] = self.words.get(d.words, 0) + 1
        self.uops[d.uops] = self.uops.get(d.uops, 0) + 1
        reading = d.mem_reads > 0
        c["conditional"] += d.conditional
        c["conditional with a data read"] += d.conditional and reading
        c["data read"] += reading
        c["two data reads"] += d.mem_reads > 1
        c["store"] += d.store
        c["jump: writes R15, or control"] += d.redirect
        c["conditional jump"] += d.redirect and d.conditional
        c["jump that DECODE resolves"] += d.early_jump
        c["the same, through a register, which WRITE resolves"] += d.reg_jump
        c["writes SR"] += d.sr_write
        c["R14 read as an operand or base"] += 14 in d.reads
        c["R14 written as a register"] += 14 in d.writes
        c["R15 read where DECODE knows PC"] += d.r15_known
        c["R15 as a pointer, or with a side effect"] += d.r15_pointer
        if d.shift_count:
            c["shift, count " + {"memory": "in memory", "adder": "through an adder (c[R] or --R)",
                                 "constant": "a constant", "register": "a register"}[d.shift_count]] += 1
        if d.jump_kind and not d.skipped:
            c["taken jump resolved in WRITE, to " + {
                "constant": "a constant", "memory": "a word in memory",
                "computed": "a computed target"}[d.jump_kind]] += 1
        c["register destination in mode 001 or 010"] += d.dest_adjust
        h = self.history
        if h:
            p1 = h[-1]
            c["conditional, SR written by the previous instruction"] += d.conditional and p1.sr_write
            c["conditional with a data read, SR written by the previous"] += (
                d.conditional and reading and p1.sr_write)
            c["data read after a store"] += reading and p1.store
            c["data read after a conditional jump"] += reading and p1.redirect and p1.conditional
            raw1 = (d.reads & p1.writes) - {15}
            c["reads a register the previous instruction writes"] += bool(raw1)
            c["the same, R13 only"] += raw1 == {13}
            c["shift count register written by the previous instruction"] += (
                d.count_reg in p1.writes)
            c["source in mode 001 or 011, register from the previous"] += bool(
                d.sum_regs & p1.writes)
            c["store in mode 011, 101, or 111, register from the previous"] += (
                d.store_sum_reg in p1.writes)
            c["store through @R or @R++, R from the previous"] += (
                d.store_ptr_reg in p1.writes)
            for reg in raw1:
                self.raw_regs[reg] = self.raw_regs.get(reg, 0) + 1
            if len(h) > 1:
                p2 = h[-2]
                c["conditional, SR written two back, not one"] += (
                    d.conditional and p2.sr_write and not p1.sr_write)
                raw2 = (d.reads & p2.writes) - {15} - raw1
                c["reads a register written two back, not one"] += bool(raw2)
                if len(h) > 2:
                    raw3 = (d.reads & h[-3].writes) - {15} - raw1 - raw2
                    c["reads a register written three back, not one or two"] += bool(raw3)
        h.append(d)
        if len(h) > 3:
            h.pop(0)

    def report(self, name: str) -> str:
        n = self.instructions
        if n == 0:
            return f"{name}: no instructions"

        def distribution(what: str, d: Dict[int, int]) -> str:
            shares = "  ".join(f"{k}: {100 * v / n:.1f}%" for k, v in sorted(d.items()))
            return f"  {what:12s} {shares}   mean {sum(k * v for k, v in d.items()) / n:.2f}"

        lines = [f"{name}: {n} instructions, {self.skipped} skipped ({100 * self.skipped / n:.1f}%)",
                 distribution("words", self.words), distribution("micro-ops", self.uops)]
        for label in LABELS:
            lines.append(f"  {label:58s} {self.counts[label]:9d} {100 * self.counts[label] / n:5.1f}%")
        top = sorted(self.raw_regs.items(), key=lambda kv: -kv[1])[:6]
        lines.append("  registers read from the previous instruction: "
                     + ", ".join(f"R{reg} {100 * v / n:.1f}%" for reg, v in top))
        return "\n".join(lines)


STEP_RE = re.compile(r"([0-9a-f]{8}) ([0-9a-f]{8})(?= |$)")
ENTRY_RE = re.compile(r"(?:NMI|IRQ) [0-9a-f]{2}(?= |$)")


def steps(lines: Iterable[str]) -> Iterator[Optional[Tuple[int, int, List[str]]]]:
    """The steps of a trace: the address, the instruction word, and the
    rest of the line for an instruction, and None for an interrupt entry.
    The emulator writes the program's console output to stdout too, so a
    step may follow output that did not end in a newline, on the same
    line. The lines after the halt are not steps."""
    for line in lines:
        if line.startswith(("Halted", "Stopped")):
            return
        m = STEP_RE.match(line) or STEP_RE.search(line)
        e = ENTRY_RE.search(line)
        if e and (m is None or e.start() < m.start()):
            yield None
        elif m:
            yield int(m.group(1), 16), int(m.group(2), 16), line[m.end():].split()


def profile(lines: Iterable[str]) -> Profile:
    p = Profile()
    for step in steps(lines):
        if step is None:
            p.interrupt()
            continue
        d = decode(step[1])
        d.skipped = "skipped" in step[2]
        p.add(d)
    return p


def trace_lines(path: str) -> Iterator[str]:
    """The lines of a trace file, or of the emulator's trace of a .bin file."""
    if not path.endswith(".bin"):
        with open(path) as f:
            yield from f
        return
    emulator = os.environ.get("NICEEMU") or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "emulator", "zig-out", "bin", "niceemu")
    try:
        proc = subprocess.Popen([emulator, "--trace", path], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, text=True)
    except OSError as e:
        sys.exit(f"hazards.py: cannot run {emulator}: {e.strerror}")
    assert proc.stdout is not None
    yield from proc.stdout
    proc.wait()


# The trace of this program, from niceemu --trace, with the counts below
# worked out by hand:
#        MOVE R1, 5                    writes R1
#        ADD[M] R2, R1, 1              reads R1 from the previous instruction; writes SR
#        ?Z MOVE R3, R2                conditional after SR; reads R2 from the previous; skipped
#        MOVE @--R13, R1               a store; reads R1 from three back
#        MOVE R4, @R13++               a data read after the store; reads R13 from the
#                                      previous; two micro-ops
#        ?V XOR R14, R14, 0x10000000   conditional; reads and writes R14; writes SR; skipped
#        ?N MOVE R5, 1                 conditional after SR; skipped
#        MOVE R15, done                a jump that DECODE resolves
#        .DAT 0
# done:  MOVE R6, 3                    writes R6
#        SHL R1, R1, R6                count a register, R6 from the previous
#        SHL R1, R1, 2                 count a constant; reads R1 from the previous
#        SHR R1, R1, @R13              count in memory, a data read; reads R1 from the previous
#        ADD R2, 0x100[R1], R0         a source in mode 011, R1 from the previous
#        MOVE @R2, R1                  a store through @R2, R2 from the previous; reads R1
#                                      from two back
#        ADD R2, R2, 1                 reads R2 from two back
#        MOVE 2[R2], R1                a store in mode 011, R2 from the previous
#        MOVE R5++, 1                  a destination in mode 010
#        MOVE R8, tab                  writes R8
#        MOVE R15, @R8                 a jump to a word in memory, which WRITE resolves; a
#                                      data read; reads R8 from the previous
# tab:   .DAT j1
# j1:    MOVE R7, j2                   writes R7
#        ?!Z MOVE R15, R7              conditional; a computed jump, taken (to the next
#                                      instruction); reads R7 from the previous
# j2:    ?!Z MOVE R15, j3              conditional; a jump to a constant, taken
# j3:    MOVE R9, j4                   writes R9
#        MOVE R15, R9                  a jump through a register, which WRITE resolves, and
#                                      which early_jump counts too; reads R9 from the previous
# j4:    0<0 R2, R6, 2[R6]             count through an adder
#        HALT                          control: a jump, and SR counts as written
TEST_TRACE = """\
00000000 00005800 R1=00000005
00000002 026080b0 R2=00000006
00000004 3000c100 skipped
00000005 00174080 R13=ffffffff [ffffffff]=00000005
00000006 00013680 R4=00000005 R13=00000000
00000007 51438730 skipped
00000009 40015800 skipped
0000000b 0003d800 R15=0000000e
0000000e 00019800 R6=00000003
00000010 08004086 R1=00000028
00000011 080040b0 R1=000000a0
00000013 090040cd R1=00000000
00000014 00609880 R2=00000100
00000016 00108080 [00000100]=00000000
00000017 00608130 R2=00000101
00000019 000c8080 [00000103]=00000000
0000001b 00095800 R5=00000002
0000001d 00021800 R8=00000020
0000001f 0003e400 R15=00000021
00000021 0001d800 R7=00000024
00000023 b003c380
00000024 b003d800
00000026 00025800 R9=00000029
00000028 0003c480 R15=00000029
00000029 08008336 R2=00000060
0000002b 0c000000 HALT
Halted (HALT) after 26 steps, PC=0000002c
R0  00000000 R1  00000000 R2  00000060 R3  00000000
"""
TEST_WORDS = {1: 10, 2: 16}
TEST_UOPS = {1: 25, 2: 1}
TEST_RAW_REGS = {1: 4, 2: 3, 6: 1, 7: 1, 8: 1, 9: 1, 13: 1}
TEST_COUNTS = {
    "conditional": 5,
    "conditional with a data read": 0,
    "data read": 3,
    "two data reads": 0,
    "store": 3,
    "jump: writes R15, or control": 6,
    "conditional jump": 2,
    "jump that DECODE resolves": 2,
    "the same, through a register, which WRITE resolves": 1,
    "writes SR": 3,
    "conditional, SR written by the previous instruction": 2,
    "conditional, SR written two back, not one": 0,
    "conditional with a data read, SR written by the previous": 0,
    "data read after a store": 1,
    "data read after a conditional jump": 0,
    "reads a register the previous instruction writes": 12,
    "the same, R13 only": 1,
    "reads a register written two back, not one": 2,
    "reads a register written three back, not one or two": 1,
    "R14 read as an operand or base": 1,
    "R14 written as a register": 1,
    "R15 read where DECODE knows PC": 0,
    "R15 as a pointer, or with a side effect": 0,
    "shift, count a constant": 1,
    "shift, count a register": 1,
    "shift, count in memory": 1,
    "shift, count through an adder (c[R] or --R)": 1,
    "shift count register written by the previous instruction": 1,
    "source in mode 001 or 011, register from the previous": 1,
    "store in mode 011, 101, or 111, register from the previous": 1,
    "store through @R or @R++, R from the previous": 1,
    "taken jump resolved in WRITE, to a constant": 1,
    "taken jump resolved in WRITE, to a word in memory": 1,
    "taken jump resolved in WRITE, to a computed target": 1,
    "register destination in mode 001 or 010": 1,
}


def test() -> None:
    p = profile(TEST_TRACE.splitlines())
    bad = []
    if (p.instructions, p.skipped) != (26, 3):
        bad.append(f"{p.instructions} instructions, {p.skipped} skipped, expected 26 and 3")
    for what, have, want in (("words", p.words, TEST_WORDS), ("micro-ops", p.uops, TEST_UOPS),
                             ("registers", p.raw_regs, TEST_RAW_REGS)):
        if have != want:
            bad.append(f"{what}: {have}, expected {want}")
    for label in LABELS:
        if p.counts[label] != TEST_COUNTS[label]:
            bad.append(f"{label}: {p.counts[label]}, expected {TEST_COUNTS[label]}")
    if bad:
        sys.exit("FAIL hazards.py --test\n  " + "\n  ".join(bad))
    print("PASS hazards.py: the counts of the test program are the ones worked out by hand")


def main() -> None:
    args = sys.argv[1:]
    if args == ["--test"]:
        test()
        return
    if not args or args[0].startswith("-"):
        sys.exit(__doc__.split("\n\n")[1])
    for path in args:
        name = os.path.splitext(os.path.basename(path))[0] if path.endswith(".bin") else path
        print(profile(trace_lines(path)).report(name))


if __name__ == "__main__":
    main()
