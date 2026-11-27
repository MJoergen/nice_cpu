#!/usr/bin/env python3
"""Logs of writes for the FM synthesizer of doc/DEVICES.md §12, and the
vectors the model computes from them.

A log is a list of writes, each with the sample before which it lands,
at most one in a sample (opm_model.read_log). random_log() makes one
from a seed: it sets up the eight channels with random registers, keys
them on and off, and changes registers, the LFO's and the noise's
included, while they sound. With --bare, the set-up writes only the
attack rates, which are 0 after a reset, and keys on every operator, so
that the registers that the log does not write sound with their values
of a reset. In a log of 500 samples or more, two resets by a program
(DEVICES.md §12.3) land in it, the first between 60% and 70% of its
samples, the second between 85% and 95%, each followed by the set-up of
--bare, the first write of it before the same sample as the reset. The
first sample of a reset is drawn at random, and no write lands between
it and the write before.
opm_ymfm.py checks the model against ymfm with such logs, and the
emulator and the RTL replay the vectors.

A vector file is the log, then one line for each sample: its number,
and the left and the right sample, in decimal. --env-start starts the
envelope's counter elsewhere than at 0, as a test of the RTL can, so
that its high bits are reached in a short run.
"""

from __future__ import annotations

import argparse
import random
import sys
from typing import List

import opm_model
from opm_model import Write

# The registers of a channel, and of an operator, by their first address.
CHANNEL_REGS = (0x20, 0x28, 0x30, 0x38)
OPERATOR_REGS = (0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0)
# The global registers but the key-on, the timers', and the test register.
GLOBAL_REGS = (0x0F, 0x18, 0x19, 0x1B)


def _reg_value(rng: random.Random, reg: int) -> int:
    """A random value for reg, with the ones that silence a note less
    likely: a high TL, and an attack rate of 0."""
    base = reg & 0xE0 if reg >= 0x40 else reg
    if base == 0x60:
        return rng.choice((rng.randrange(0, 0x30), rng.randrange(0, 0x80)))
    if base == 0x80:
        return (rng.randrange(4) << 6) | rng.randrange(8, 32)
    if base == 0x20:
        return rng.randrange(0x40, 0x100)
    if reg == 0x0F:
        return rng.choice((0, 0x80 | rng.randrange(32)))
    if reg == 0x18:
        return rng.choice((rng.randrange(256), rng.randrange(0xC0, 0x100)))
    return rng.randrange(256)


def random_log(seed: int, count: int, bare: bool = False) -> List[Write]:
    """A log of writes over count samples, from seed, which sets up every
    register of the channels and the operators first, or if bare only the
    attack rates, and keys every operator on."""
    rng = random.Random(seed)
    writes: List[Write] = []
    n = 0
    resets = [rng.randrange(lo * count // 100, hi * count // 100) for lo, hi in ((60, 70), (85, 95))]
    if count < 500:
        resets = []

    def put(reg: int, data: int) -> None:
        nonlocal n
        writes.append((n, reg, data))
        n += 1

    def put_bare() -> None:
        for slot in range(32):
            put(0x80 + slot, _reg_value(rng, 0x80))
        for ch in range(8):
            put(0x08, 0x78 | ch)

    if bare:
        put_bare()
    else:
        for reg in GLOBAL_REGS:
            put(reg, _reg_value(rng, reg))
        for ch in range(8):
            for reg in CHANNEL_REGS:
                put(reg + ch, _reg_value(rng, reg))
            for op in range(4):
                for reg in OPERATOR_REGS:
                    put(reg + 8 * op + ch, _reg_value(rng, reg))
    while n < count:
        n += rng.choice((0, 1, 2, 5, 20, 100, 400))
        if resets and n >= resets[0]:
            n = resets[0]
            writes.append((n, opm_model.RESET, 0))
            put_bare()
            resets.pop(0)
            continue
        r = rng.random()
        if r < 0.35:
            put(0x08, rng.randrange(128))
        elif r < 0.45:
            put(0x01, rng.choice((0, 2)))
        elif r < 0.6:
            reg = rng.choice(GLOBAL_REGS)
            put(reg, _reg_value(rng, reg))
        elif r < 0.75:
            reg = rng.choice(CHANNEL_REGS) + rng.randrange(8)
            put(reg, _reg_value(rng, reg))
        else:
            reg = rng.choice(OPERATOR_REGS) + rng.randrange(32)
            put(reg, _reg_value(rng, reg))
    return [w for w in writes if w[0] < count]


def write_log(writes: List[Write], count: int) -> str:
    lines = [f"{n} reset" if reg == opm_model.RESET else f"{n} {reg:02x} {data:02x}" for n, reg, data in writes]
    lines.append(f"end {count}")
    return "\n".join(lines) + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description="Write a random log of writes, or the vectors of one.")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--count", type=int, default=20000, help="the number of samples")
    p.add_argument("--log", action="store_true", help="write the log only")
    p.add_argument("--bare", action="store_true", help="set up the attack rates alone, and key every operator on")
    p.add_argument(
        "--env-start", type=int, default=0, help="the envelope's counter at the start, as the RTL's G_ENV_START sets it"
    )
    p.add_argument("-o", "--output", default="-")
    a = p.parse_args()
    writes = random_log(a.seed, a.count, a.bare)
    text = write_log(writes, a.count)
    if not a.log:
        opm = opm_model.Opm(a.env_start)
        samples = opm_model.run(writes, a.count, opm)
        text += "".join(f"{n} {left} {right}\n" for n, (left, right) in enumerate(samples))
    if a.output == "-":
        sys.stdout.write(text)
    else:
        with open(a.output, "w") as f:
            f.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
