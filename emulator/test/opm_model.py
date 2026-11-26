#!/usr/bin/env python3
"""A reference model of the FM synthesizer of doc/DEVICES.md §12, whose
registers are the YM2151's.

The model is the definition: the emulator and the RTL compute the same
samples from the same writes, bit for bit. It follows ymfm by Aaron
Giles, src/ymfm_opm.cpp and src/ymfm_fm.ipp, of
https://github.com/aaronsgiles/ymfm at commit 81aec25, step by step,
under the notice in opm_tables.py. `make -C emulator ymfmcheck`
compares the two. Where it departs from ymfm, §12.6 says so.

Opm is the synthesizer without its FIFO. write() changes a register,
and sample() computes the next sample. The device applies at most one
write before each sample (§12.3).

The operators are numbered by slot, 0 to 31, as their registers are:
slot 8 * op + ch for the operator op of channel ch, where op is 0 for
M1, 1 for M2, 2 for C1, and 3 for C2. The connections take them in the
order M1, C1, M2, C2, which ORDER gives.
"""

from __future__ import annotations

import argparse
import sys
from typing import List, Optional, Sequence, Tuple

import opm_tables as T

# The envelope's states.
ATTACK = 0
DECAY = 1
SUSTAIN = 2
RELEASE = 3

# The attenuation above which an operator gives 0.
QUIET = 0x380

# The slots of a channel's operators in the order of the connections: M1,
# C1, M2, C2. The key-on bits 3 to 6 of register 0x08 take this order too.
ORDER = (0, 2, 1, 3)

# For each connection: the input of the 2nd, 3rd, and 4th operator in
# that order, and which of the 1st, 2nd, and 3rd go to the output. An
# input names a value of the list below: 0 nothing, 1 to 3 the 1st to
# 3rd operator, 5 the 1st plus the 2nd, 6 the 1st plus the 3rd, and 7 the
# 2nd plus the 3rd. The 4th always goes to the output.
CONNECTIONS: Tuple[Tuple[int, int, int, bool, bool, bool], ...] = (
    (1, 2, 3, False, False, False),  # 0: M1 -> C1 -> M2 -> C2
    (0, 5, 3, False, False, False),  # 1: (M1 + C1) -> M2 -> C2
    (0, 2, 6, False, False, False),  # 2: (M1 + (C1 -> M2)) -> C2
    (1, 0, 7, False, False, False),  # 3: ((M1 -> C1) + M2) -> C2
    (1, 0, 3, False, True, False),  # 4: (M1 -> C1) + (M2 -> C2)
    (1, 1, 1, False, True, True),  # 5: M1 -> each of C1, M2, and C2
    (1, 0, 0, False, True, True),  # 6: (M1 -> C1) + M2 + C2
    (0, 0, 0, True, True, True),  # 7: M1 + C1 + M2 + C2
)


def phase_step_of(block_freq: int, delta: int) -> int:
    """The phase step of the 13 bits block, note, and fraction, moved by
    delta 64ths of a semitone."""
    block = block_freq >> 10
    # The note is 0 to 15 with gaps, 12 in an octave: take 1/4 off.
    code = ((block_freq >> 6) & 15) - ((block_freq >> 8) & 3)
    freq = (code << 6) + (block_freq & 63) + delta
    if not 0 <= freq < 768:
        if freq < 0:
            freq += 768
            if block == 0:
                return (T.PHASE_STEP[0] << 5) >> 7
            block -= 1
        else:
            freq -= 768
            if freq >= 768:
                block += 1
                freq -= 768
            if block >= 7:
                return T.PHASE_STEP[767] << 5
            block += 1
    return (T.PHASE_STEP[freq] << 5) >> (block ^ 7)


def volume(att: int) -> int:
    """The linear level, 13 bits, of an attenuation of 5.8 bits."""
    return ((T.POW[att & 0xFF] | 0x400) << 2) >> (att >> 8)


def sin_att(phase: int) -> Tuple[int, bool]:
    """The attenuation of |sin| at a phase of 10 bits, and its sign."""
    i = phase & 0x3FF
    q = i & 0x1FF
    if q & 0x100:
        q = ~q
    return T.SIN[q & 0xFF], bool(i & 0x200)


def dac(value: int) -> int:
    """value as the DAC gives it: clipped to 16 bits, and rounded down to
    a mantissa of 10 bits and an exponent of 3."""
    if value < -32768:
        return -32768
    if value > 32767:
        return 32767
    # The bits of the magnitude: those of value, or of ~value if negative.
    bits = (value ^ (value >> 31)).bit_length()
    shift = max(bits - 8, 1) - 1
    return value & ~((1 << shift) - 1)


def clamp(v: int) -> int:
    return -32768 if v < -32768 else 32767 if v > 32767 else v


class Operator:
    """The state of one operator, and what the registers give it in this
    sample."""

    __slots__ = (
        "phase",
        "att",
        "state",
        "key",
        "keyon",
        "step",
        "dynamic",
        "block_freq",
        "detune",
        "multiple",
        "tl",
        "sustain",
        "rates",
    )

    def __init__(self) -> None:
        self.phase = 0  # 10.10 bits
        self.att = 0x3FF  # 4.6 bits
        self.state = RELEASE
        self.key = 0  # the key state the envelope follows
        self.keyon = 0  # the key state that register 0x08 wrote
        self.step = 0
        self.dynamic = False
        self.block_freq = 0
        self.detune = 0
        self.multiple = 1
        self.tl = 0
        self.sustain = 0
        self.rates = [0, 0, 0, 0]


class Opm:
    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        """The state after a reset of the system or a start (§12.5)."""
        self.regs = bytearray(256)
        for ch in range(8):
            self.regs[0x20 + ch] = 0xC0
        self.ops = [Operator() for _ in range(32)]
        self.fb = [[0, 0] for _ in range(8)]
        self.fb_in = [0] * 8
        self.env_counter = 0
        self.lfo_counter = 0
        self.lfo_am = 0
        self.noise_lfsr = 1
        self.noise_counter = 0
        self.noise_state = 0
        self.noise_wave = [0] * 256

    def write(self, reg: int, data: int) -> None:
        """A write of data to the register reg."""
        if reg == 0x19:
            # Bit 7 says AM (0) or PM (1); the PM depth is kept at 0x1A.
            self.regs[0x19 + (data >> 7)] = data
        elif reg != 0x1A:
            self.regs[reg] = data
        if reg == 0x08:
            ch = data & 7
            for i, o in enumerate(ORDER):
                self.ops[8 * o + ch].keyon = (data >> (3 + i)) & 1

    # Registers.

    def _pm_depth(self) -> int:
        return self.regs[0x1A] & 0x7F

    def _prepare(self, slot: int) -> None:
        r = self.regs
        op = self.ops[slot]
        ch = slot & 7
        bf = (r[0x28 + ch] & 0x7F) << 6 | r[0x30 + ch] >> 2
        op.block_freq = bf
        keycode = bf >> 8
        dt1 = (r[0x40 + slot] >> 4) & 7
        d = T.DETUNE[keycode][dt1 & 3]
        op.detune = -d if dt1 & 4 else d
        op.multiple = (r[0x40 + slot] & 15) * 2 or 1
        pms = (r[0x38 + ch] >> 4) & 7
        op.dynamic = self._pm_depth() != 0 and pms != 0
        if not op.dynamic:
            op.step = self._phase_step(slot, 0)
        op.tl = (r[0x60 + slot] & 0x7F) << 3
        sl = r[0xE0 + slot] >> 4
        sl |= (sl + 1) & 0x10
        op.sustain = sl << 5
        ksr = keycode >> ((r[0x80 + slot] >> 6) ^ 3)

        def rate(raw: int) -> int:
            return 0 if raw == 0 else min(raw + ksr, 63)

        op.rates[ATTACK] = rate((r[0x80 + slot] & 31) * 2)
        op.rates[DECAY] = rate((r[0xA0 + slot] & 31) * 2)
        op.rates[SUSTAIN] = rate((r[0xC0 + slot] & 31) * 2)
        op.rates[RELEASE] = rate((r[0xE0 + slot] & 15) * 4 + 2)

    def _phase_step(self, slot: int, pm: int) -> int:
        r = self.regs
        op = self.ops[slot]
        ch = slot & 7
        delta = T.DT2[r[0xC0 + slot] >> 6]
        pms = (r[0x38 + ch] >> 4) & 7
        if pms:
            delta += pm >> (6 - pms) if pms < 6 else pm << (pms - 5)
        step = phase_step_of(op.block_freq, delta) + op.detune
        return ((step & 0xFFFFFFFF) * op.multiple >> 1) & 0xFFFFFFFF

    # The envelope.

    def _keystate(self, op: Operator) -> None:
        if op.keyon != op.key:
            op.key = op.keyon
            if op.key:
                if op.state != ATTACK:
                    op.state = ATTACK
                    op.phase = 0
                    if op.rates[ATTACK] >= 62:
                        op.att = 0
            elif op.state != RELEASE:
                op.state = RELEASE

    def _envelope(self, op: Operator, counter: int) -> None:
        if op.state == ATTACK and op.att == 0:
            op.state = DECAY
        if op.state == DECAY and op.att >= op.sustain:
            op.state = SUSTAIN
        rate = op.rates[op.state]
        shift = rate >> 2
        counter = (counter << shift) & 0xFFFFFFFF
        if counter & 0x7FF:
            return
        index = (counter >> (11 if shift <= 11 else shift)) & 7
        inc = (T.INCREMENT[rate] >> (4 * index)) & 15
        if op.state == ATTACK:
            if rate < 62:
                op.att += (-(op.att + 1) * inc) >> 4
        else:
            op.att += inc
            if op.att >= 0x400:
                op.att = 0x3FF

    def _env_att(self, op: Operator, slot: int, am: int) -> int:
        a = op.att
        if self.regs[0xA0 + slot] & 0x80:
            a += am
        a += op.tl
        return min(a, 0x3FF)

    def _op_out(self, op: Operator, slot: int, mod: int, am: int) -> int:
        if op.att > QUIET:
            return 0
        s, neg = sin_att((op.phase >> 10) + mod)
        v = volume(s + (self._env_att(op, slot, am) << 2))
        return -v if neg else v

    # The LFO and the noise.

    def _noise_and_lfo(self) -> int:
        r = self.regs
        freq = (r[0x0F] & 31) ^ 31
        for _ in range(2):
            # The taps are those of the register after the shift.
            lfsr = (self.noise_lfsr << 1) & 0xFFFFFFFF
            lfsr |= ((lfsr >> 17) ^ (lfsr >> 14) ^ 1) & 1
            self.noise_lfsr = lfsr
            c = self.noise_counter
            self.noise_counter = (c + 1) & 0xFF
            if c >= freq:
                self.noise_counter = 0
                self.noise_state = (lfsr >> 17) & 1
        rate = r[0x18]
        self.lfo_counter = (self.lfo_counter + ((0x10 | (rate & 15)) << (rate >> 4))) & 0xFFFFFFFF
        if r[0x01] & 2:
            self.lfo_counter = 0
        lfo = (self.lfo_counter >> 22) & 0xFF
        noise = (self.noise_lfsr >> 17) & 0xFF
        self.noise_wave[(lfo + 1) & 0xFF] = noise
        shape = r[0x1B] & 3
        if shape == 3:
            am = self.noise_wave[lfo]
            pm = am - 256 if am & 0x80 else am
        else:
            am, pm = T.lfo_wave(shape, lfo)
        self.lfo_am = (am * (r[0x19] & 0x7F)) >> 7
        return (pm * self._pm_depth()) >> 7

    # A sample.

    def sample(self) -> Tuple[int, int]:
        """The next sample, left and right."""
        r = self.regs
        ops = self.ops
        for slot in range(32):
            self._prepare(slot)
            self._keystate(ops[slot])
        c = self.env_counter + 1
        if c & 3 == 3:
            c += 1
        self.env_counter = c & 0xFFFFFFFF
        pm = self._noise_and_lfo()
        env = self.env_counter >> 2 if self.env_counter & 3 == 0 else -1
        for ch in range(8):
            fb = self.fb[ch]
            fb[0] = fb[1]
            fb[1] = self.fb_in[ch]
        for slot in range(32):
            op = ops[slot]
            if env >= 0:
                self._envelope(op, env)
            step = self._phase_step(slot, pm) if op.dynamic else op.step
            op.phase = (op.phase + step) & 0xFFFFF
        left = 0
        right = 0
        for ch in range(8):
            ams = r[0x38 + ch] & 3
            am = self.lfo_am << (ams - 1) if ams else 0
            m1, c1, m2, c2 = (ops[8 * o + ch] for o in ORDER)
            s1, s2, s3, s4 = (8 * o + ch for o in ORDER)
            fbl = (r[0x20 + ch] >> 3) & 7
            fb = self.fb[ch]
            mod = (fb[0] + fb[1]) >> (10 - fbl) if fbl else 0
            o1 = self._op_out(m1, s1, mod, am)
            self.fb_in[ch] = o1
            pan = r[0x20 + ch] >> 6
            if pan == 0:
                continue
            in2, in3, in4, out1, out2, out3 = CONNECTIONS[r[0x20 + ch] & 7]
            v = [0, o1, 0, 0, 0, 0, 0, 0]
            v[2] = self._op_out(c1, s2, v[in2] >> 1, am)
            v[5] = v[1] + v[2]
            v[3] = self._op_out(m2, s3, v[in3] >> 1, am)
            v[6] = v[1] + v[3]
            v[7] = v[2] + v[3]
            if ch == 7 and r[0x0F] & 0x80:
                n = (self._env_att(c2, s4, am) ^ 0x3FF) << 1
                out = -n if self.noise_state else n
            else:
                out = self._op_out(c2, s4, v[in4] >> 1, am)
            if out1:
                out = clamp(out + v[1])
            if out2:
                out = clamp(out + v[2])
            if out3:
                out = clamp(out + v[3])
            if pan & 1:
                left += out
            if pan & 2:
                right += out
        return dac(left), dac(right)


Write = Tuple[int, int, int]  # the sample before which it lands, the register, the data


def run(writes: Sequence[Write], count: int, opm: Optional[Opm] = None) -> List[Tuple[int, int]]:
    """The samples 0 to count - 1 from writes, ordered by sample, with at
    most one in a sample."""
    opm = opm or Opm()
    out: List[Tuple[int, int]] = []
    i = 0
    for n in range(count):
        if i < len(writes) and writes[i][0] == n:
            opm.write(writes[i][1], writes[i][2])
            i += 1
            if i < len(writes) and writes[i][0] == n:
                raise ValueError(f"two writes before sample {n}")
        out.append(opm.sample())
    return out


def read_log(lines: Sequence[str]) -> Tuple[List[Write], int]:
    """A log of writes, one a line: the sample, the register, and the
    data, in hex but for the sample; and "end N", the number of samples.
    "#" starts a comment."""
    writes: List[Write] = []
    count = 0
    for line in lines:
        f = line.split("#")[0].split()
        if not f:
            continue
        if f[0] == "end":
            count = int(f[1])
        else:
            writes.append((int(f[0]), int(f[1], 16), int(f[2], 16)))
    return writes, count


def main() -> int:
    p = argparse.ArgumentParser(description="Run a log of writes through the model; print each sample.")
    p.add_argument("log")
    a = p.parse_args()
    with open(a.log) as f:
        writes, count = read_log(f.readlines())
    for left, right in run(writes, count):
        print(f"{left} {right}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
