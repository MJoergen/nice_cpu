#!/usr/bin/env python3
"""Writes a NICE program that stores into its own code at every distance.

Usage: smc_prog.py OUT.nasm

This is part of step 4 of the test order in MICROARCH.md §9, beside
test/hazard.nasm, which stores into the next six words. A store must take
effect on every instruction after it (ISA.md §8.2), so a core that fetches
ahead must refetch a word that a store changes (MICROARCH.md §5.5). The
pipelined core compares each store with the range of words that FETCH
holds or has requested, and with the instructions in DECODE and PREPARE.
The range's far end is the pair whose fetch the bus may accept in the
same cycle as the store, when the memory still gives the old words.

The program stores a NOP over a HALT 1 to 40 words ahead: from the next
word to beyond FETCH's buffer of 16 words and its requests in flight, so
that some store lands in the pair being fetched, whatever the state of
the pipeline: on 2026-10-19, three of the forty did with no stalls and
two with 30%, read off a waveform. After each HALT it counts one in R1.
The emulator runs past every HALT, so the core's trace must match it,
and a core that ran a stale HALT stops early. The program checks itself
too: R12 is 0 at the end only if all 40 HALTs were passed. The makefile
runs it with and without stalls, on every core.
"""

import sys

DISTANCES = range(1, 41)


def program() -> list[str]:
    lines = [
        "; Written by test/smc_prog.py. A store of a NOP over a HALT 1 to 40",
        "; words ahead. R1 counts the HALTs passed, and R12 is 0 at the end",
        "; only if all were.",
        "        MOVE    R12, 1",
        "        MOVE    R1, 0",
    ]
    for d in DISTANCES:
        lines.append(f"        MOVE    @t{d}, 0        ; {d} word{'s' if d > 1 else ''} ahead")
        lines += ["        .DAT    0"] * (d - 1)
        lines.append(f"t{d}     HALT")
        lines.append("        ADD     R1, R1, 1")
    lines += [
        f"        SUB[M]  R0, R1, {len(DISTANCES)}",
        "        ?Z MOVE R12, 0",
        "        HALT",
    ]
    return lines


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: smc_prog.py OUT.nasm")
    with open(sys.argv[1], "w") as f:
        f.write("\n".join(program()) + "\n")


if __name__ == "__main__":
    main()
