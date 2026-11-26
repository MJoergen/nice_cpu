#!/usr/bin/env python3
"""Tests of the model of the FM synthesizer, opm_model.py, against the
formulas of doc/DEVICES.md §12.4, and of its rules of writes and of
the DAC, checked by hand.

A waveform cannot be checked by hand, so these test what can: the pitch
of a key code, the time of a rate, the level of a TL and of an SL. Its
samples are checked against ymfm by opm_ymfm.py.
"""

from __future__ import annotations

import math
import sys
from typing import Callable, List

import opm_model as M

FS = 3579545 / 64
failures: List[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    if not ok:
        failures.append(f"{name}: {detail}")


def note_index(code: int) -> int:
    """The semitone of a note code within the octave, 0 for C#."""
    return code - (code >> 2)


def freq(block: int, code: int, kf: int = 0, dt2: int = 0, mul: int = 1) -> float:
    """The frequency in Hz of an operator, from its phase step."""
    o = M.Opm()
    o.write(0x28, block << 4 | code)
    o.write(0x30, kf << 2)
    o.write(0x40, mul)
    o.write(0xC0, dt2 << 6)
    o.sample()
    return o.ops[0].step * FS / 2**20


def cents(f: float, ref: float) -> float:
    return 1200 * math.log2(f / ref)


def test_pitch() -> None:
    """Each note is within 5 cents of 440 Hz equal temperament, with A4
    at block 4, note 10, and KF moves it in 64ths of a semitone."""
    for block in range(8):
        for code in (0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14):
            s = 12 * block + note_index(code)
            ref = 440 * 2 ** ((s - 56) / 12)
            c = cents(freq(block, code), ref)
            check("pitch", abs(c) < 5, f"block {block} note {code}: {c:+.2f} cents")
    a4 = freq(4, 10)
    for kf in (8, 16, 32, 48, 63):
        c = cents(freq(4, 10, kf=kf), a4)
        check("KF", abs(c - kf * 100 / 64) < 2, f"KF {kf}: {c:+.2f} cents")
    for dt2, step in ((1, 600), (2, 781), (3, 950)):
        c = cents(freq(4, 10, dt2=dt2), a4)
        check("DT2", abs(c - step) < 5, f"DT2 {dt2}: {c:+.2f} cents")
    for mul in range(16):
        f = freq(4, 10, mul=mul)
        want = a4 * (mul if mul else 0.5)
        check("MUL", abs(f - want) < 1e-9 * want + 0.02, f"MUL {mul}: {f:.3f} Hz")


def test_tone() -> None:
    """A4 on C2 of connection 7 alone crosses zero 880 times a second."""
    o = M.Opm()
    o.write(0x20, 0xC7)
    o.write(0x28, 0x4A)
    for slot in (0, 8, 16):
        o.write(0x60 + slot, 0x7F)
    o.write(0x58, 0x01)
    o.write(0x98, 0x1F)
    o.write(0x08, 0x78)
    n = int(FS / 10)
    out = [o.sample()[0] for _ in range(n)]
    crossings = sum(1 for a, b in zip(out[100:], out[101:]) if (a < 0) != (b < 0))
    f = crossings / 2 / ((n - 101) / FS)
    check("tone", abs(cents(f, 440)) < 25, f"{f:.1f} Hz")
    peak = max(out)
    check("tone", peak == M.dac(M.volume(0)), f"peak {peak}")


def ticks(state: int, rate: int, sustain: int = 0x400) -> int:
    """The envelope's clocks from the start of a state to its end."""
    o = M.Opm()
    op = M.Operator()
    op.state = state
    op.att = 0x3FF if state == M.ATTACK else 0
    op.sustain = sustain
    op.rates = [rate] * 4
    t = 0
    done: Callable[[], bool] = (lambda: op.att == 0) if state == M.ATTACK else (lambda: op.att >= 0x3FF)
    while not done():
        t += 1
        o._envelope(op, t)
    return t


def decay_ticks(rate: int) -> float:
    """§12.4: the clocks of a decay from 0 to 0x3FF at an effective rate."""
    if rate >= 60:
        return 1023 / 8
    return 1023 * 8 / ((4 + (rate & 3)) * 2.0 ** ((rate >> 2) - 11))


def test_rates() -> None:
    for rate in range(8, 64):
        t = ticks(M.DECAY, rate)
        want = decay_ticks(rate)
        # Within one period of the increments.
        slack = max(8 * 2 ** (11 - (rate >> 2)), 1)
        check("decay", abs(t - want) <= slack, f"rate {rate}: {t} clocks, not {want:.0f}")
    for rate in range(8, 48):
        t = ticks(M.ATTACK, rate)
        ratio = t / decay_ticks(rate)
        check("attack", 0.070 < ratio < 0.072, f"rate {rate}: {ratio:.4f} of the decay")
    for rate in (0, 1):
        o = M.Opm()
        op = M.Operator()
        op.state = M.DECAY
        op.att = 0x100
        op.sustain = 0x400
        op.rates = [rate] * 4
        for t in range(1, 100000):
            o._envelope(op, t)
        check("rate 0", op.att == 0x100, f"rate {rate} moved to {op.att:#x}")


def test_effective_rate() -> None:
    """r = 2R + KSR, 4RR + 2 + KSR for RR, at most 63, 0 for R = 0, and
    KSR = key code >> (3 - KS)."""
    for ks in range(4):
        for kc in (0x00, 0x2A, 0x4A, 0x7E):
            o = M.Opm()
            o.write(0x28, kc)
            o.write(0x80, ks << 6 | 13)
            o.write(0xA0, 0)
            o.write(0xC0, 31)
            o.write(0xE0, 7)
            o.sample()
            ksr = (kc >> 2) >> (3 - ks)
            rates = o.ops[0].rates
            want = [min(26 + ksr, 63), 0, min(62 + ksr, 63), min(30 + ksr, 63)]
            check("rates", rates == want, f"KS {ks} KC {kc:#x}: {rates}, not {want}")


def test_levels() -> None:
    """TL steps 0.75 dB, 2^(-1/8), and SL 3 dB, with SL 15 at 93 dB."""
    for tl in (0, 3, 8, 21, 40, 64):
        o = M.Opm()
        o.write(0x20, 0xC7)
        o.write(0x28, 0x4A)
        for slot in (0, 8, 16):
            o.write(0x60 + slot, 0x7F)
        o.write(0x78, tl)
        o.write(0x58, 0x01)
        o.write(0x98, 0x1F)
        o.write(0x08, 0x78)
        level = max(o.sample()[0] for _ in range(200))
        want = M.volume(0) * 2 ** (-tl / 8)
        check("TL", abs(level - want) <= 0.01 * want + 2, f"TL {tl}: {level}, not {want:.1f}")
    for sl in range(16):
        o = M.Opm()
        o.write(0xE0, sl << 4)
        o.sample()
        want = (sl if sl < 15 else 31) << 5
        check("SL", o.ops[0].sustain == want, f"SL {sl}: {o.ops[0].sustain:#x}")


def test_lfo() -> None:
    """The LFO's period is 2^30 / ((16 + F) << S) samples for the rate
    register's high nibble S and low nibble F."""
    for reg in (0x00, 0x0F, 0x80, 0xC5, 0xFF):
        o = M.Opm()
        o.write(0x18, reg)
        o.sample()
        step = (16 + (reg & 15)) << (reg >> 4)
        check("LFO", o.lfo_counter == step, f"rate {reg:#x}: {o.lfo_counter}")
    o = M.Opm()
    o.write(0x18, 0xFF)
    o.write(0x01, 0x02)
    o.sample()
    check("LFO reset", o.lfo_counter == 0, "")


def test_writes() -> None:
    o = M.Opm()
    check("reset", list(o.regs[0x20:0x28]) == [0xC0] * 8 and not any(o.regs[:0x20]), "")
    o.write(0x19, 0x45)
    o.write(0x19, 0x93)
    check("0x19", o.regs[0x19] == 0x45 and o.regs[0x1A] == 0x93, f"{o.regs[0x19]:#x} {o.regs[0x1A]:#x}")
    o.write(0x1A, 0x00)
    check("0x1A", o.regs[0x1A] == 0x93, "a write of 0x1A changed it")
    # Bits 3 to 6 of 0x08 key M1, C1, M2, and C2 of the channel in bits 2..0.
    for bit, slot in ((3, 5), (4, 21), (5, 13), (6, 29)):
        o = M.Opm()
        o.write(0x08, 1 << bit | 5)
        on = [s for s in range(32) if o.ops[s].keyon]
        check("key on", on == [slot], f"bit {bit}: slots {on}")


def test_dac() -> None:
    """Checked by hand: a value beyond 16 bits saturates, and one within
    keeps 9 bits below its leading sign bits, rounded toward minus
    infinity, but for the 10 bits below 512 in magnitude."""
    for v, want in (
        (0, 0),
        (-1, -1),
        (255, 255),
        (511, 511),
        (512, 512),
        (513, 512),
        (-513, -514),
        (8168, 8160),
        (-8168, -8176),
        (32767, 32704),
        (40000, 32767),
        (-40000, -32768),
    ):
        check("DAC", M.dac(v) == want, f"dac({v}) = {M.dac(v)}, not {want}")


def main() -> int:
    for t in (test_pitch, test_tone, test_rates, test_effective_rate, test_levels, test_lfo, test_writes, test_dac):
        t()
    for f in failures:
        print("FAIL opm_model", f)
    if failures:
        return 1
    print("PASS opm_model_test")
    return 0


if __name__ == "__main__":
    sys.exit(main())
