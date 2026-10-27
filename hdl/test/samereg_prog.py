#!/usr/bin/env python3
"""Writes a NICE program with one register in all three fields of a shift.

Usage: samereg_prog.py OUT.nasm

Part of step 4 of the test order in MICROARCH.md §9, beside
test/sidefx_prog.py, which has every pair of side effects on one register.
Here the register is in all three fields at once, for every pair of source
modes and six destination modes, of four shifts: the sources and the
destination then depend on each other through the side effects, the value
written last, and the sums that PREPARE forms (MICROARCH.md §7.4), and the
count comes late to WRITE in most of the forms (§7.3). R2 starts at 0x20
before each shift, so the counts are near 32 and 33, where the shifts
change their behavior (ISA.md §5.2), and the addresses fall in the data
words at 0x18 to 0x37. C is set before each shift, for the shifts that
rotate through it. Then the same with R14, where every write sets bit 24
and SR is the count: R14 starts at 0x05000020, C set, so the addresses
fall at 0x05000020 to 0x05000037, which are empty memory. The program
does not check itself; the core's trace is compared with the emulator's.
"""

import sys

OPS = ["0<0[M]", "C<C[M]", ">>C[M]", "C>C"]
OPS_R14 = ["0<0", "C>C"]
DESTS = ["{r}", "{r}--", "{r}++", "@{r}++", "@--{r}", "1[{r}]"]
S0 = ["{r}", "--{r}", "{r}++", "2[{r}]", "@{r}", "@--{r}", "@{r}++", "@2[{r}]"]
S1 = ["{r}", "--{r}", "{r}++", "3[{r}]", "@{r}", "@--{r}", "@{r}++", "@3[{r}]"]
DATA = [
    "                .DAT    " + ", ".join(f"0x{v:02X}" for v in range(0x18, 0x28)),
    "                .DAT    " + ", ".join(f"0x{v:02X}" for v in range(0x28, 0x38)),
]


def shifts(ops: list[str], reg: str, setup: list[str]) -> list[str]:
    lines = []
    for op in ops:
        for dest in DESTS:
            for s0 in S0:
                for s1 in S1:
                    lines += setup
                    lines.append(f"        {op:7s} {dest.format(r=reg)}, {s0.format(r=reg)}, "
                                 f"{s1.format(r=reg)}")
    return lines


def program() -> list[str]:
    lines = [
        "; Written by test/samereg_prog.py: shifts with one register in all three",
        "; fields, for every pair of source modes and six destination modes. R2",
        "; starts at 0x20, so the counts are near 32 and 33, and the addresses",
        "; fall in the data at 0x18 to 0x37. Then the same with R14.",
        "                MOVE    R15, start",
        "                .ORG    0x18",
    ] + DATA + [
        "                .ORG    0x100",
        "start           MOVE    R1, 0x9ABCDEF1",
    ]
    lines += shifts(OPS, "R2", ["                MOVE    R2, 0x20",
                                "                SUB[M]  R0, R0, 1       ; C = 1"])
    lines += shifts(OPS_R14, "R14", ["                MOVE    R14, 0x05000020  ; C = 1"])
    lines += [
        "                MOVE    R14, 0x01000000",
        "                HALT",
        "                .ORG    0x01000018",
    ] + DATA
    return lines


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: samereg_prog.py OUT.nasm")
    with open(sys.argv[1], "w") as f:
        f.write("\n".join(program()) + "\n")


if __name__ == "__main__":
    main()
