#!/usr/bin/env python3
"""Estimate the clock cycles of a NICE program on the pipelined core of
doc/MICROARCH.md, from the emulator's trace.

    ./pipecycles.py [options] FILE.bin...         run the emulator with --trace
    ./pipecycles.py [options] --bin FILE.bin TRACE  use a trace written before
    ./pipecycles.py --test                        check the model on snippets

The emulator is the one hazards.py uses: ../emulator/zig-out/bin/niceemu
next to this script, or $NICEEMU. The .bin is needed even with a trace,
for the constant words, which the trace does not show.

It prints the instructions, the estimated cycles, the CPI, and where the
cycles above one per instruction come from. A program that reads INSTR_LO
(0xFFFFFF42) in pairs, as bench.c and hand.nasm do around each phase, also
gets one row per pair: the instructions between the two reads (which match
the emulator's count) and the cycles between them.

THE MODEL. Roughly cycle-level, not RTL-exact. Each instruction of the trace
is decoded (the decoding of hazards.py, which is imported and checked
against, refined to say which micro-op makes which access) into the
micro-ops of MICROARCH.md §4. Each micro-op gets the cycle it is in
SEQUENCER, PREPARE, and WRITE. Stages hold one micro-op each, and a micro-op
may enter a stage in the cycle its predecessor leaves it (valid/ready).

- FETCH reads an aligned pair of words per cycle, from the redirect target
  on. The pair fetched in cycle f is in ICACHE in f + 1 and DECODE can take
  the instruction in f + 2, once all its words are there. FETCH runs ahead
  by at most --ibuf words (default 8) that DECODE has not taken yet.
- DECODE takes one instruction per cycle. SEQUENCER issues one micro-op per
  cycle, so an instruction of n micro-ops costs n cycles ("multi-micro-op").
- A jump that DECODE resolves (condition always, dest R15 in mode 000, no
  data read: hazards.py's early_jump) restarts FETCH in the cycle after
  DECODE: the target is in DECODE 3 cycles after the jump, a bubble of
  --early (2) cycles. Every other taken jump (conditional jumps, returns
  MOVE R15, @SP++, table jumps, control instructions) is resolved in WRITE
  by its last micro-op and refetches: the target reaches WRITE --flush (5)
  cycles later than a fall-through would (FETCH, ICACHE, DECODE, SEQUENCER,
  PREPARE). A skipped jump costs nothing itself.
- Registers: bypasses from WRITE make ALU operand dependences free. A
  register used as the base of a data access (read or store; the address is
  formed in PREPARE) is ready only the cycle after the micro-op that writes
  it leaves WRITE: an --agen (1) cycle stall when it is the previous
  micro-op. This includes the side effects of a push or pop and s0's side
  effect read by s1; --sidefx-fast makes side-effect writes (Rx +/- 1) free.
  A skipped writer counts as writing, as DECODE cannot tell.
- Data reads are issued in PREPARE (MICROARCH.md §5.3): a conditional
  instruction's read waits until the cycle after the last older SR writer
  (M = 1, R14 written, control) has left WRITE ("SR stall"), and a read waits
  until the cycle after an older skipped jump has left WRITE ("jump wait").
  A skipped instruction waits too, but makes no access.
- The data bus takes one access per cycle, in program order. Reads go in
  PREPARE, stores in WRITE, so a read directly after a store, or a second
  read in one micro-op, waits a cycle ("data bus"). RAM answers in the next
  cycle, in time for WRITE.
- The math unit, as in hdl/src/mpu.vhd: a write to A or B (C or D), accepted
  in cycle t, starts the multiplier and the two dividers (the two 64-bit
  dividers), and a read of a result waits for its unit. The multiplier takes
  two cycles, so a read of a product is accepted in cycle t + --mul (3) at
  the earliest. A divider takes a cycle to start, then one cycle per
  quotient bit, but --div-skip (8) bits in one cycle while they are all 0,
  which the model works out from the operands in the trace: a read of a
  quotient or remainder is accepted in cycle t + 2 + n at the earliest,
  with n the divider's cycles. The signed dividers divide the absolute
  values. The bus is held until then ("MPU wait").
- Not modelled: interrupts (an entry is treated as a flush), self-modifying
  code checks, the INSTR_LO retire rule, wrong-path fetch traffic, and bus
  stalls other than the math unit.

Each cycle a micro-op leaves WRITE later than one after its predecessor is
charged to the constraint that bound it, so cycles = instructions +
multi-micro-op cycles + the charged gaps, exactly.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
from typing import Dict, Iterable, List, Optional, Tuple

import hazards

HERE = os.path.dirname(os.path.abspath(__file__))

PHASES = ["rng64", "crc32", "bst", "heapsort", "vm", "strings"]
CAUSES = ["startup", "fetch", "flush", "early", "sr", "jumpwait", "agen", "bus", "mpu", "interrupt"]
CAUSE_TEXT = {
    "multi": "multi-micro-op instructions",
    "startup": "pipeline start",
    "fetch": "fetch-bound (2 words/cycle, unaligned targets, buffer)",
    "flush": "taken jumps resolved in WRITE (flush)",
    "early": "jumps DECODE resolves (early-redirect bubble)",
    "sr": "conditional data read waits for SR",
    "jumpwait": "data read waits for an older skipped jump",
    "agen": "address register written by the previous micro-op",
    "bus": "data bus: read after store, two reads in a micro-op",
    "mpu": "math unit result not ready",
    "interrupt": "interrupt entries",
}
INSTR_LO = 0xFFFFFF42
MEMORY = (4, 5, 6, 7)
SIDE = (1, 2, 5, 6)

# The units of the math unit (ISA.md §8.4), and the result words that wait
# for each: the products, the signed and the unsigned quotient and
# remainder, and the 64-bit ones.
MPU_UNITS = ["mul", "sdiv", "udiv", "sdiv64", "udiv64"]
MPU_RESULTS = {0xFFFFFF22: "mul", 0xFFFFFF23: "mul", 0xFFFFFF24: "mul", 0xFFFFFF25: "mul",
               0xFFFFFF26: "sdiv", 0xFFFFFF27: "sdiv", 0xFFFFFF28: "udiv", 0xFFFFFF29: "udiv",
               0xFFFFFF34: "sdiv64", 0xFFFFFF35: "sdiv64", 0xFFFFFF36: "sdiv64",
               0xFFFFFF37: "sdiv64", 0xFFFFFF38: "udiv64", 0xFFFFFF39: "udiv64",
               0xFFFFFF3A: "udiv64", 0xFFFFFF3B: "udiv64"}


def absolute(x: int, bits: int) -> int:
    """The absolute value of a two's complement number of the given width."""
    return (1 << bits) - x if x >> (bits - 1) else x


def div_cycles(n: int, d: int, bits: int, skip: int) -> int:
    """The cycles the restoring divider of hdl/src/mpu.vhd takes for n / d,
    after its start cycle: one per quotient bit, but skip bits in one
    cycle when the remainder, shifted by skip with the next skip bits of
    the dividend, is still less than the divisor, so they are all 0."""
    mask = (1 << bits) - 1
    rem, quo, count, cycles = 0, n & mask, bits, 0
    while count:
        cycles += 1
        if skip and count >= skip and rem >> (bits - skip) == 0 and \
                ((rem << skip | quo >> (bits - skip)) & mask) < d:
            rem = (rem << skip | quo >> (bits - skip)) & mask
            quo = (quo << skip) & mask
            count -= skip
        else:
            shifted = rem << 1 | quo >> (bits - 1)
            bit = 0
            if shifted >= d:
                shifted -= d
                bit = 1
            rem = shifted & mask
            quo = (quo << 1 | bit) & mask
            count -= 1
    return cycles


class Uop:
    __slots__ = ("reads", "bases", "store", "store_base", "writes", "sidefx", "sr_write")

    def __init__(self) -> None:
        self.reads: List[int] = []           # operand index, 0 = s0, 1 = s1
        self.bases: List[Optional[int]] = []  # base register of each read
        self.store = False
        self.store_base: Optional[int] = None
        self.writes: List[int] = []          # registers written
        self.sidefx: List[bool] = []         # whether each write is a +/- 1
        self.sr_write = False


class Info:
    """What the model needs of one instruction word."""
    __slots__ = ("cond", "control", "words", "uops", "redirect", "early", "dm", "dr",
                 "src", "nreads")
    cond: bool
    control: bool
    words: int
    uops: List[Uop]
    redirect: bool
    early: bool
    dm: int
    dr: int
    src: Tuple[Tuple[int, int], Tuple[int, int]]
    nreads: int


def base_of(mode: int, reg: int) -> Optional[int]:
    # R0 is a constant, and DECODE knows R15 (MICROARCH.md §3).
    return None if reg in (0, 15) else reg


def decode(iw: int) -> Info:
    h = hazards.decode(iw)
    info = Info()
    info.cond = h.conditional
    info.control = h.control
    info.words = h.words
    info.early = h.early_jump
    info.redirect = h.redirect
    info.dm = (iw >> 18) & 7
    info.dr = (iw >> 14) & 15
    info.src = (((iw >> 11) & 7, (iw >> 7) & 15), ((iw >> 4) & 7, iw & 15))
    info.nreads = h.mem_reads
    if h.control:
        u = Uop()
        u.sr_write = True
        info.uops = [u]
        return info
    uops = []
    pending = [i for i, (m, _) in enumerate(info.src) if m in MEMORY]
    for i, (m, r) in enumerate(info.src):
        if m in SIDE and r != 0:
            u = Uop()
            for j in [p for p in pending if p <= i]:
                u.reads.append(j)
                u.bases.append(base_of(*info.src[j]))
            pending = [p for p in pending if p > i]
            u.writes.append(r)
            u.sidefx.append(True)
            uops.append(u)
    op = Uop()
    for j in pending:
        op.reads.append(j)
        op.bases.append(base_of(*info.src[j]))
    dm, dr = info.dm, info.dr
    if dm >= 3:
        op.store = True
        op.store_base = base_of(dm, dr)
        if dm in SIDE and dr != 0:
            op.writes.append(dr)
            op.sidefx.append(True)
    elif dr != 0:
        op.writes.append(dr)
        op.sidefx.append(False)
    op.sr_write = bool((iw >> 25) & 1) or 14 in op.writes
    uops.append(op)
    info.uops = uops
    assert len(uops) == h.uops, hex(iw)
    assert sum(len(u.reads) for u in uops) == h.mem_reads, hex(iw)
    return info


def read_addresses(info: Info, pc: int, regs: List[int], mem: Dict[int, int]) -> List[int]:
    """The addresses of s0's and s1's data reads, in field order (ISA.md §4)."""
    a = pc + 1
    consts = []
    if info.dm in (3, 7):
        a += 1
    for m, _ in info.src:
        if m in (3, 7):
            consts.append(mem.get(a & 0xFFFFFFFF, 0))
            a += 1
        else:
            consts.append(0)
    local = {15: (pc + info.words) & 0xFFFFFFFF}

    def val(r: int) -> int:
        if r == 0:
            return 0
        v = local[r] if r in local else regs[r]
        return v | (1 << 24) if r == 14 else v

    out = [0, 0]
    for i, (m, r) in enumerate(info.src):
        if m in (1, 5):
            local[r] = (val(r) - 1) & 0xFFFFFFFF
        if m in MEMORY:
            out[i] = (val(r) + consts[i]) & 0xFFFFFFFF if m == 7 else val(r)
        if m in (2, 6):
            local[r] = (val(r) + 1) & 0xFFFFFFFF
    return out


TRACE_RE = re.compile(r"([0-9a-f]{8}) ([0-9a-f]{8})(?= |$)")


class Model:
    def __init__(self, mem: Dict[int, int], ibuf: int = 8, flush: int = 5, early: int = 2,
                 agen: int = 1, sidefx_fast: bool = False, mul: int = 3,
                 div_skip: int = 8) -> None:
        self.mem = mem
        self.bp = max(2, ibuf // 2)
        self.flush, self.early, self.agen = flush, early, agen
        self.sidefx_fast = sidefx_fast
        self.mul, self.div_skip = mul, div_skip
        self.bubble = {"flush": flush, "early": early, "interrupt": flush + 1}
        self.cache: Dict[int, Info] = {}
        self.regs = [0] * 16
        self.regs[14] = 0x01000000
        self.instructions = 0
        self.multi = 0
        self.gaps = {c: 0 for c in CAUSES}
        self.counter_reads: List[Tuple[int, int, int, Dict[str, int]]] = []
        # Fetch stream.
        self.stream_base = 0          # pair number of the target's pair
        self.ftimes: List[Tuple[int, str]] = []
        self.leave: List[int] = []
        self.restart: Tuple[int, str] = (0, "startup")
        self.expect_pc = 0
        # Pipeline.
        self.d_prev = -10
        self.leave_prev = -10
        self.s_prev = -10
        self.p_prev = -10
        self.w_prev = -10         # cycle the previous micro-op entered WRITE
        self.done_prev = -1       # cycle the previous micro-op left WRITE
        self.first = True
        self.last_bus = -10
        self.reg_ready = [-10] * 16
        self.sr_ready = -10
        self.jump_ready = -10
        # The math unit: its operands, and the cycle in which a read of each
        # unit's result can be accepted.
        self.mpu_ops = {0xFFFFFF20: 0, 0xFFFFFF21: 0, 0xFFFFFF30: 0, 0xFFFFFF31: 0,
                        0xFFFFFF32: 0, 0xFFFFFF33: 0}
        self.mpu_ready = {u: -10 for u in MPU_UNITS}

    # FETCH: the cycle pair k of the stream is fetched.
    def fetch_time(self, k: int) -> Tuple[int, str]:
        f = self.ftimes
        while len(f) <= k:
            n = len(f)
            if n == 0:
                f.append(self.restart)
                continue
            t, tag = f[-1][0] + 1, "fetch"
            if n - self.bp >= 0:
                lv = self.leave[n - self.bp] if n - self.bp < len(self.leave) else None
                if lv is None:
                    raise RuntimeError("fetch buffer smaller than an instruction")
                if lv > t:
                    t = lv
            f.append((t, tag))
        return f[k]

    def new_stream(self, pc: int, when: Tuple[int, str]) -> None:
        self.stream_base = pc >> 1
        self.restart = when
        self.ftimes = []
        self.leave = []

    def interrupt(self) -> None:
        # An entry: flush, a vector read, and a refetch.
        self.restart_after(self.done_prev + 1 + self.flush - 4, "interrupt")
        self.last_bus = max(self.last_bus, self.done_prev + 1)

    def step(self, pc: int, iw: int, skipped: bool, changes: List[str]) -> None:
        info = self.cache.get(iw)
        if info is None:
            info = self.cache[iw] = decode(iw)
        if self.stream_base == -1:
            self.stream_base = pc >> 1  # the target of a redirect
        elif pc != self.expect_pc:
            # Not the fall-through, and no jump seen: start afresh.
            self.new_stream(pc, (self.done_prev + 1, "interrupt"))
        k0 = (pc >> 1) - self.stream_base
        k1 = ((pc + info.words - 1) >> 1) - self.stream_base
        ft, ftag = self.fetch_time(k1)
        # DECODE.
        d, dtag = self.d_prev + 1, "flow"
        if self.leave_prev > d:
            d = self.leave_prev
        if ft + 2 > d:
            d, dtag = ft + 2, ftag
        self.instructions += 1
        self.multi += len(info.uops) - 1
        addrs: List[int] = []
        if not skipped and info.nreads:
            addrs = read_addresses(info, pc, self.regs, self.mem)
        first_s = -1
        counter_read_time = None
        for j, u in enumerate(info.uops):
            # SEQUENCER
            if j == 0:
                s, stag = d + 1, dtag
            else:
                s, stag = self.s_prev + 1, "flow"
            if self.p_prev > s:
                s, stag = self.p_prev, "flow"
            if first_s < 0:
                first_s = s
            # PREPARE
            p, ptag = s + 1, stag
            if self.w_prev > p:
                p, ptag = self.w_prev, "flow"
            data = -10
            for operand, base in zip(u.reads, u.bases):
                t, tag = p, ptag
                if base is not None and self.reg_ready[base] > t:
                    t, tag = self.reg_ready[base], "agen"
                if info.cond and self.sr_ready > t:
                    t, tag = self.sr_ready, "sr"
                if self.jump_ready > t:
                    t, tag = self.jump_ready, "jumpwait"
                if not skipped:
                    if self.last_bus + 1 > t:
                        t, tag = self.last_bus + 1, "bus"
                    a = addrs[operand]
                    acc = t
                    unit = MPU_RESULTS.get(a)
                    if unit is not None and self.mpu_ready[unit] > acc:
                        acc = self.mpu_ready[unit]
                    if acc + 1 > data:
                        data = acc + 1
                        dtg = "mpu" if acc > t else "flow"
                    self.last_bus = acc
                    if a == INSTR_LO:
                        counter_read_time = acc
                p, ptag = t, tag
            if u.store and u.store_base is not None and self.reg_ready[u.store_base] > p:
                p, ptag = self.reg_ready[u.store_base], "agen"
            # WRITE
            w, wtag = self.done_prev + 1, "flow"
            if p + 1 > w:
                w, wtag = p + 1, ptag
            done, tag = w, wtag
            if data > done:
                done, tag = data, dtg
            if u.store and not skipped:
                if self.last_bus + 1 > done:
                    done, tag = self.last_bus + 1, "bus"
                self.last_bus = done
            gap = done - self.done_prev - 1
            if self.first:
                self.gaps["startup"] += done
                self.first = False
            elif gap > 0:
                assert tag != "flow"
                rt = self.restart[1]
                if j == 0 and k0 == 0 and tag == "fetch" and rt in self.bubble:
                    # The first instruction after a redirect: the bubble is
                    # the redirect's, the rest (an unaligned or long target
                    # instruction) is fetch's.
                    b = min(gap, self.bubble[rt])
                    self.gaps[rt] += b
                    gap -= b
                if gap:
                    self.gaps[tag] += gap
            self.s_prev, self.p_prev, self.w_prev, self.done_prev = s, p, w, done
            for r, fx in zip(u.writes, u.sidefx):
                if fx and self.sidefx_fast:
                    continue
                self.reg_ready[r] = done + self.agen
            if u.sr_write:
                self.sr_ready = done + 1
                self.reg_ready[14] = done + self.agen
        # Leaving DECODE frees the fetch buffer.
        lv = self.leave
        while len(lv) <= k1:
            lv.append(first_s)
        for k in range(k0, k1 + 1):
            lv[k] = first_s
        self.d_prev, self.leave_prev = d, first_s
        if counter_read_time is not None:
            self.counter_reads.append((self.instructions - 1, counter_read_time, self.total(),
                                       dict(self.gaps, multi=self.multi)))
        # Shadow registers and memory, from the trace.
        for c in changes:
            if c[0] == "R" and "=" in c:
                reg, hexval = c[1:].split("=")
                self.regs[int(reg)] = int(hexval, 16)
            elif c[0] == "[":
                hexaddr, hexval = c[1:].split("]=")
                addr, val = int(hexaddr, 16), int(hexval, 16)
                self.mem[addr] = val
                if addr in self.mpu_ops:
                    self.mpu_ops[addr] = val
                    self.mpu_write(addr, self.last_bus)
        nxt = (pc + info.words) & 0xFFFFFFFF
        if info.redirect and not skipped:
            if info.early:
                self.restart_after(d + self.early - 1, "early")
            else:
                self.restart_after(self.done_prev + self.flush - 4, "flush")
        else:
            if info.redirect:  # skipped jump: younger reads wait for it
                self.jump_ready = self.done_prev + 1
            self.expect_pc = nxt

    def mpu_write(self, addr: int, t: int) -> None:
        """A write to an operand of the math unit, accepted in cycle t,
        restarts the units of its half (hdl/src/mpu.vhd)."""
        ops = self.mpu_ops
        if addr < 0xFFFFFF30:
            a, b = ops[0xFFFFFF20], ops[0xFFFFFF21]
            self.mpu_ready["mul"] = t + self.mul
            self.mpu_ready["udiv"] = t + 2 + div_cycles(a, b, 32, self.div_skip)
            self.mpu_ready["sdiv"] = t + 2 + div_cycles(absolute(a, 32), absolute(b, 32), 32,
                                                       self.div_skip)
        else:
            c = ops[0xFFFFFF30] | ops[0xFFFFFF31] << 32
            d = ops[0xFFFFFF32] | ops[0xFFFFFF33] << 32
            self.mpu_ready["udiv64"] = t + 2 + div_cycles(c, d, 64, self.div_skip)
            self.mpu_ready["sdiv64"] = t + 2 + div_cycles(absolute(c, 64), absolute(d, 64), 64,
                                                         self.div_skip)

    def restart_after(self, t: int, tag: str) -> None:
        self.ftimes = []
        self.leave = []
        self.restart = (t, tag)
        self.stream_base = -1  # set by the next instruction

    def total(self) -> int:
        return self.done_prev + 1


def run_model(model: Model, lines: Iterable[str]) -> Model:
    for line in lines:
        if line.startswith("Halted") or line.startswith("Stopped"):
            break
        parts = line.split()
        if not parts:
            continue
        if parts[0] in ("NMI", "IRQ"):
            model.interrupt()
            continue
        if len(parts) >= 2 and len(parts[0]) == 8 and len(parts[1]) == 8:
            try:
                pc, iw = int(parts[0], 16), int(parts[1], 16)
            except ValueError:
                continue
            rest = parts[2:]
        else:
            m = TRACE_RE.search(line)
            if not m:
                continue
            pc, iw = int(m.group(1), 16), int(m.group(2), 16)
            rest = line[m.end():].split()
        skipped = bool(rest) and rest[0] == "skipped"
        model.step(pc, iw, skipped, [] if skipped else rest)
    return model


def load_bin(path: str) -> Dict[int, int]:
    mem = {}
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) == 2:
                mem[int(p[0], 16)] = int(p[1], 16)
    return mem


def breakdown(gaps: Dict[str, int], instructions: int, cycles: int, indent: str = "  ") -> List[str]:
    out = []
    extra = cycles - instructions
    for key in ["multi"] + CAUSES:
        v = gaps.get(key, 0)
        if v:
            out.append(f"{indent}{CAUSE_TEXT[key]:56s} {v:10d} {v / instructions:6.3f}/instr"
                       f" {100 * v / max(extra, 1):5.1f}%")
    return out


def phases(m: Model) -> List[Tuple[str, Tuple[int, int, int, Dict[str, int]],
                                   Tuple[int, int, int, Dict[str, int]]]]:
    """The phases of a run, each named, with the model's state at the two
    reads of INSTR_LO around it."""
    reads = m.counter_reads
    pairs = [(reads[i], reads[i + 1]) for i in range(0, len(reads) - 1, 2)]
    names = PHASES if len(pairs) == len(PHASES) else [f"phase{i + 1}" for i in range(len(pairs))]
    return [(nm, a, b) for nm, (a, b) in zip(names, pairs)]


def compare(m: Model, core_output: str) -> str:
    """The model's cycles of each phase beside the core's, from the table
    that the program printed on the core (make core in bench/)."""
    core: Dict[str, int] = {}
    with open(core_output) as f:
        for line in f:
            p = line.split()
            if len(p) >= 3 and p[1].isdigit() and p[2].isdigit() and (p[0] in PHASES or p[0] == "total"):
                core[p[0]] = int(p[2])
    if not core:
        sys.exit(f"pipecycles.py: no phase table in {core_output}")
    rows = [(nm, b[1] - a[1]) for nm, a, b in phases(m)]
    rows.append(("total", sum(c for _, c in rows)))
    lines = ["", f"  {'phase':9s} {'model':>9s} {'core':>9s}   model against the core"]
    for nm, c in rows:
        if nm in core:
            lines.append(f"  {nm:9s} {c:9d} {core[nm]:9d}   {100 * (c - core[nm]) / core[nm]:+.1f}%")
    return "\n".join(lines)


def report(name: str, m: Model) -> str:
    n, c = m.instructions, m.total()
    lines = [f"{name}: {n} instructions, {c} cycles (estimate), CPI {c / n:.3f}",
             f"  cycles above 1/instruction: {c - n}"]
    allg = dict(m.gaps, multi=m.multi)
    lines += breakdown(allg, n, c)
    if len(m.counter_reads) >= 2:
        lines.append("")
        lines.append(f"  {'phase':9s} {'instr':>9s} {'cycles':>9s} {'CPI':>6s}   main extra cycles per instruction")
        tot_i = tot_c = 0
        for nm, a, b in phases(m):
            ni, nc = b[0] - a[0], b[1] - a[1]
            tot_i += ni
            tot_c += nc
            diff = {k: b[3].get(k, 0) - a[3].get(k, 0) for k in ["multi"] + CAUSES}
            top = sorted(((v, k) for k, v in diff.items() if v > 0), reverse=True)[:4]
            tops = ", ".join(f"{k} {v / ni:.2f}" for v, k in top)
            lines.append(f"  {nm:9s} {ni:9d} {nc:9d} {nc / ni:6.3f}   {tops}")
        lines.append(f"  {'total':9s} {tot_i:9d} {tot_c:9d} {tot_c / max(tot_i, 1):6.3f}")
    return "\n".join(lines)


# --test: snippets with the cycles worked out by hand from the model.
TESTS = [
    ("straight-line 1-word register code: 1 per instruction plus the start",
     "\n".join(["        ADD R1, R2, R3", "        ADD R2, R1, R1"] * 50) + "\n        HALT\n",
     # 101 instructions. The first in DECODE at 2, WRITE at 5, so 6 cycles
     # for it, then one per instruction.
     101, 106, {"startup": 5}),
    ("2-word instructions: fetch keeps up",
     "\n".join(["        ADD R1, R2, 0x1234"] * 100) + "\n        HALT\n",
     100 + 1, 106, {"startup": 5}),
    ("3-word instructions: fetch-bound at 1.5 cycles per instruction",
     "\n".join(["        ADD R1, 0x1234, 0x5678"] * 100) + "\n        HALT\n",
     # The first needs pair 1, fetched at 1: DECODE 3, done 6 (startup).
     # HALT at word 300, pair 150, fetched at 150: DECODE 152, done 155, so
     # 156 cycles: 155 - 6 - 100 = 49 fetch-bound.
     101, 156, {"startup": 6, "fetch": 49}),
    ("a counted loop: SUB[M] then ?!Z jump back, each taken jump flushes",
     """        MOVE R1, 10
loop    SUB[M] R1, R1, 1
        ?!Z MOVE R15, loop
        HALT
""",
     # MOVE (2 words) done 5. Each iteration SUB (2 words) + jump (2 words).
     # Taken jump done at t: target SUB fetched at t+1, DECODE t+3, WRITE t+6:
     # a gap of 5 for each of the 9 taken jumps. The first SUB and the jump
     # come straight from the stream: SUB at 6, jump at 7. Then 9 x (1 + 5)
     # ... the HALT after the untaken jump needs pair 3 (words 6), fine.
     # Instructions: 1 + 10 * 2 + 1 = 22; cycles 22 + 5 (start) + 45 = 72.
     22, 72, {"startup": 5, "flush": 45}),
    ("unconditional MOVE R15, label: DECODE redirect, 2-cycle bubble",
     """        MOVE R15, a
        HALT
a       MOVE R15, b
        HALT
b       MOVE R15, c
        HALT
c       HALT
""",
     # Each jump is 2 words, DECODE at d, the target fetched at d + 1 and in
     # DECODE at d + 3: a bubble of 2. Jump 1 is done at 5. a is at word 3,
     # odd, so its words 3 and 4 are in pairs 1 and 2, DECODE at d + 4: early
     # 2 and fetch 1. b (word 6) and c (word 9, one word) cost 2 each.
     # 4 instructions + 5 (start) + 6 + 1 = 16.
     4, 16, {"startup": 5, "early": 6, "fetch": 1}),
    ("conditional read after SUB[M]: one SR stall; unconditional: none",
     """        MOVE R2, 0x100
        SUB[M] R1, R2, 1
        ?!Z MOVE R3, @R2
        SUB[M] R1, R2, 1
        MOVE R3, @R2
        HALT
""",
     # MOVE R2 writes R2, the SUB reads it: free. ?!Z MOVE R3, @R2 waits a
     # cycle for SR (R2 was written two micro-ops back: no agen stall).
     6, 12, {"startup": 5, "sr": 1}),
    ("push, push, pop: address register from the previous micro-op",
     """        MOVE R13, 0x200
        MOVE @--R13, 1
        MOVE @--R13, 2
        MOVE R1, @R13++
        HALT
""",
     # Push 1 needs R13 from MOVE R13: agen 1. Push 2 needs R13 from push 1:
     # agen 1. The pop's S0 needs R13 from push 2: agen 1, and its read
     # follows the store of push 2 on the bus, which the agen wait covers.
     # Instructions 5, micro-ops 6.
     5, 5 + 1 + 5 + 3, {"startup": 5, "multi": 1, "agen": 3}),
    ("math unit: write A and B, read the product",
     """        MOVE @0xFFFFFF20, 7
        MOVE @0xFFFFFF21, 6
        MOVE R1, @0xFFFFFF22
        HALT
""",
     # Two 3-word stores, done at 6 (start) and 7: the second starts the
     # computation in cycle 7. The read is in PREPARE at 7, after the
     # store on the bus at 8, but the product can be read at 7 + 3 = 10,
     # data in WRITE at 11: a gap of 11 - 7 - 1 = 3. HALT done at 12, so
     # 13 cycles.
     4, 13, {"startup": 6, "mpu": 3}),
    ("math unit: 9 / 7 unsigned skips 24 quotient bits in 3 cycles",
     """        MOVE @0xFFFFFF20, 9
        MOVE @0xFFFFFF21, 7
        MOVE R1, @0xFFFFFF28
        HALT
""",
     # As above, but the divider: 3 cycles skip 8 bits each, since the
     # dividend's top 24 bits are 0 and 9 shifted into view is not less
     # than 7 until then, and 8 cycles run the rest, n = 11, as tb_mpu
     # counts it. The read is accepted at 7 + 2 + 11 = 20, data at 21:
     # a gap of 13. HALT done at 22, so 23 cycles.
     4, 23, {"startup": 6, "mpu": 13}),
    ("math unit: -7 / 2 signed divides 7 by 2, n = 11",
     """        MOVE @0xFFFFFF20, 0xFFFFFFF9
        MOVE @0xFFFFFF21, 2
        MOVE R1, @0xFFFFFF26
        HALT
""",
     # The signed divider takes the absolute values: 7 / 2 skips 24 bits
     # in 3 cycles and runs 8, n = 11, so the same 23 cycles.
     4, 23, {"startup": 6, "mpu": 13}),
    ("math unit: 0xFFFFFFF9 / 2 unsigned skips nothing, n = 32",
     """        MOVE @0xFFFFFF20, 0xFFFFFFF9
        MOVE @0xFFFFFF21, 2
        MOVE R1, @0xFFFFFF28
        HALT
""",
     # The unsigned divider sees a dividend whose top bits are 1, so no
     # cycle skips: n = 32. The read is accepted at 7 + 2 + 32 = 41,
     # data at 42: a gap of 34. HALT done at 43, so 44 cycles.
     4, 44, {"startup": 6, "mpu": 34}),
    ("a skipped jump, then a read; a call and a return",
     """        MOVE R13, 0x200
        ?Z MOVE R15, 0
        MOVE R1, @R13
        ADD @--R13, 2, R15
        MOVE R15, f
        HALT
f       MOVE R15, @R13++
""",
     # MOVE R13 (words 0,1) done 5. ?Z MOVE R15, 0 (2,3) skipped, done 6.
     # MOVE R1, @R13 (4) waits for the skipped jump: PREPARE at 7, done 8,
     # jumpwait 1. The call ADD @--R13, 2, R15 (5,6) is a store, no stall:
     # done 9, its DECODE held to 7 by the read's wait. MOVE R15, f (7,8):
     # DECODE 7, done 10, and early: f (word 10, pair 5) fetched at 8,
     # DECODE 10, S0 done 13: early 2. The S0 needs R13 from the call, two
     # micro-ops back: free. Its OP is done 14 and flushes: HALT (word 9)
     # fetched 15, DECODE 17, done 20: flush 5. So 21 cycles:
     # 7 instructions, 1 multi, 5 start, 1 + 2 + 5.
     7, 21, {"startup": 5, "multi": 1, "jumpwait": 1, "early": 2, "flush": 5}),
]


def test() -> None:
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        for i, (what, src, n, cycles, gaps) in enumerate(TESTS):
            nasm, binp = os.path.join(tmp, f"t{i}.nasm"), os.path.join(tmp, f"t{i}.bin")
            with open(nasm, "w") as f:
                f.write(src)
            subprocess.run([sys.executable, os.path.join(HERE, "..", "assembler", "niceasm.py"),
                            "-o", binp, nasm], check=True, stdout=subprocess.DEVNULL)
            m = run_model(Model(load_bin(binp)), hazards.trace_lines(binp))
            have = {k: v for k, v in dict(m.gaps, multi=m.multi).items() if v}
            ok = (m.instructions, m.total(), have) == (n, cycles, gaps)
            bad += not ok
            print(f"{'PASS' if ok else 'FAIL'} {what}: {m.instructions} instructions, "
                  f"{m.total()} cycles" + ("" if ok else f" {have}, expected {n}, {cycles}, {gaps}"))
    if bad:
        sys.exit(f"FAIL pipecycles.py --test: {bad} of {len(TESTS)}")
    print("PASS pipecycles.py --test")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--test", action="store_true")
    ap.add_argument("--bin", help="the .bin of a trace FILE")
    ap.add_argument("--ibuf", type=int, default=8, help="words FETCH may run ahead (8)")
    ap.add_argument("--flush", type=int, default=5, help="bubble of a jump taken in WRITE (5)")
    ap.add_argument("--early", type=int, default=2, help="bubble of a jump DECODE resolves (2)")
    ap.add_argument("--agen", type=int, default=1, help="address-register stall (1, 0 = none)")
    ap.add_argument("--sidefx-fast", action="store_true", help="side-effect writes need no agen stall")
    ap.add_argument("--mul", type=int, default=3,
                    help="cycles from the write of an operand to the read of a product (3)")
    ap.add_argument("--div-skip", type=int, default=8,
                    help="quotient bits a divider skips in one cycle (8, 0 = none)")
    ap.add_argument("--phases", type=int, metavar="N",
                    help="fail unless each program reads INSTR_LO around N phases")
    ap.add_argument("--against", metavar="FILE",
                    help="the core's output for the same program (make core in bench/), "
                         "to compare the phases with")
    a = ap.parse_args()
    if a.test:
        test()
        return
    if not a.files:
        ap.error("no FILE")
    for path in a.files:
        binp = path if path.endswith(".bin") else a.bin
        if not binp:
            sys.exit("pipecycles.py: a trace needs --bin")
        m = Model(load_bin(binp), a.ibuf, a.flush, a.early, a.agen, a.sidefx_fast, a.mul,
                  a.div_skip)
        run_model(m, hazards.trace_lines(path))
        print(report(os.path.basename(path), m))
        if a.phases is not None and len(m.counter_reads) != 2 * a.phases:
            sys.exit(f"pipecycles.py: {path} read INSTR_LO {len(m.counter_reads)} times, "
                     f"not {2 * a.phases}")
        if a.against:
            print(compare(m, a.against))


if __name__ == "__main__":
    main()
