#!/usr/bin/env python3
"""Finds the first line where two traces of one program differ, and prints
the data reads of the instruction on that line.

Usage: trace_reads.py PROGRAM.bin EXPECTED.trace ACTUAL.trace

Both traces are in the format of "niceemu --trace" (emulator/README.md),
as the emulator and sim/trace.vhd write them. The script replays the
expected trace from reset, applying each line's register changes and
memory writes, so that it knows the registers when the differing
instruction starts. Then it decodes that instruction with its constant
words from the program and the trace's memory writes, and lists the
addresses of its source reads (ISA.md §4.1, §8.2), with the names of the
I/O words it knows. A read of CYCLE_LO or CYCLE_HI explains a difference
between the core and the emulator: one counts cycles, the other steps
(ISA.md §8.5).
"""

import re
import sys

M = 0xFFFFFFFF
NAMES = {0xFFFFFF00: "CONSOLE", 0xFFFFFF01: "READ_COUNTER", 0xFFFFFF40: "CYCLE_LO",
         0xFFFFFF41: "CYCLE_HI", 0xFFFFFF42: "INSTR_LO", 0xFFFFFF43: "INSTR_HI",
         0xFFFFFF10: "TIMER_PERIOD", 0xFFFFFF11: "TIMER_COUNT", 0xFFFFFF12: "TIMER_VECTOR",
         0xFFFFFF50: "FS_CTRL"}
LINE = re.compile(r"([0-9a-f]{8}) ([0-9a-f]{8})(.*)")


def load_bin(path: str) -> dict[int, int]:
    mem = {}
    with open(path) as f:
        for line in f:
            a, w = line.split()
            mem[int(a, 16)] = int(w, 16)
    return mem


def field(iw: int, i: int) -> int:
    """Operand field i of the instruction word: 0 = dest, 1 = s0, 2 = s1."""
    return (iw >> (14 - 7 * i)) & 0x7F


def length(iw: int) -> int:
    """The number of words of the instruction (ISA.md §2.3)."""
    if (iw >> 26) & 3 == 3:
        return 1
    return 1 + sum(1 for i in range(3) if (field(iw, i) >> 4) & 3 == 3)


def reads(iw: int, pc: int, regs: list[int], mem: dict[int, int]) -> list[int]:
    """The addresses that the sources of iw at pc read, in order, with the
    registers as they are when the instruction starts (ISA.md §5)."""
    consts = [0, 0, 0]
    p = pc + 1
    if (iw >> 26) & 3 != 3:
        for i in range(3):
            if (field(iw, i) >> 4) & 3 == 3:
                consts[i] = mem.get(p, 0)
                p += 1
    r = list(regs)
    r[15] = p

    def rd(x: int) -> int:
        return 0 if x == 0 else r[x]

    def wr(x: int, v: int) -> None:
        if x != 0:
            r[x] = (v & M) | 0x01000000 if x == 14 else v & M

    out = []
    for i in (1, 2):
        f = field(iw, i)
        mode, x = f >> 4, f & 15
        if mode == 1:
            wr(x, rd(x) - 1)
        elif mode == 2:
            wr(x, rd(x) + 1)
        elif mode == 4:
            out.append(rd(x))
        elif mode == 5:
            wr(x, rd(x) - 1)
            out.append(rd(x))
        elif mode == 6:
            out.append(rd(x))
            wr(x, rd(x) + 1)
        elif mode == 7:
            out.append((rd(x) + consts[i]) & M)
    return out


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__.split("\n\n")[1])
    mem = load_bin(sys.argv[1])
    with open(sys.argv[2], encoding="latin-1") as f:
        expected = f.read().splitlines()
    with open(sys.argv[3], encoding="latin-1") as f:
        actual = f.read().splitlines()
    regs = [0] * 16
    regs[14] = 0x01000000
    for n, (e, a) in enumerate(zip(expected, actual), 1):
        m = LINE.match(e)
        if e != a:
            if not m:
                sys.exit(f"line {n} differs and is not an instruction:\n  {e}\n  {a}")
            pc, iw = int(m.group(1), 16), int(m.group(2), 16)
            what = ", ".join(f"{x:08x}" + (f" ({NAMES[x]})" if x in NAMES else "")
                             for x in reads(iw, pc, regs, mem))
            print(f"line {n}: {iw:08x} at {pc:08x} reads {what or 'nothing'}")
            print(f"  expected: {e}\n  actual:   {a}")
            return
        if m:
            regs[15] = int(m.group(1), 16) + length(int(m.group(2), 16))
        elif not re.match(r"(NMI|IRQ) ", e):
            continue
        for rn, v in re.findall(r"R(\d+)=([0-9a-f]{8})", e):
            regs[int(rn)] = int(v, 16)
        for ad, v in re.findall(r"\[([0-9a-f]{8})\]=([0-9a-f]{8})", e):
            mem[int(ad, 16)] = int(v, 16)
    if len(expected) != len(actual):
        sys.exit(f"the traces agree for {min(len(expected), len(actual))} lines, then one ends")
    print("the traces are the same")


if __name__ == "__main__":
    main()
