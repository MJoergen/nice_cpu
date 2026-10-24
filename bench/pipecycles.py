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
  by at most --ibuf words (default 16, the buffer of hdl/src/pipe_fetch.vhd)
  that DECODE has not taken yet. After reset, the first pair is fetched in
  cycle 1.
- DECODE takes one instruction per cycle. SEQUENCER issues one micro-op per
  cycle, so an instruction of n micro-ops costs n cycles ("multi-micro-op").
- DECODE holds two instructions (dec_r, which it splits into micro-ops,
  and dec_q, the next) and skid_r, a micro-op that PREPARE did not take
  (hdl/src/pipe_decode.vhd). It takes an instruction when dec_q is free,
  which is once the last micro-op of the instruction before the one in
  dec_r is split off. A micro-op is split off once the one before has
  entered PREPARE, in which it may still wait.
- A redirect in cycle x puts the target's pair on the bus in x + 2, and
  DECODE takes the target in x + 4. A jump that DECODE resolves (MOVE R15,
  c and ADD R15, R15, c, with the condition always and the C bit clear,
  and the ADD with another condition when c is negative: hazards.py's
  early_jump) redirects FETCH in the cycle DECODE takes it, d, so the
  target is in DECODE in d + 4, a bubble of --early (3) cycles. Such a
  conditional jump that is skipped costs a flush, like a taken jump that
  WRITE resolves, and FETCH refetches the next instruction. Every other
  taken jump (conditional jumps, returns MOVE R15, @SP++,
  table jumps, control instructions) is resolved in WRITE by its last
  micro-op, which flushes in the cycle it leaves WRITE, c - 2. The
  redirect reaches FETCH from a register in c - 1, FETCH issues the
  request in c, it is on the bus in c + 1, the memory acknowledges in
  c + 2, DECODE takes the instruction in c + 3 and emits its micro-op in
  c + 4, PREPARE passes it on in c + 5, and WRITE runs it in c + 6,
  --flush (7) cycles later than a fall-through would. hdl/test/bubble.nasm
  measures 7, and 2 for an early jump, since its read of the cycle
  counter before the jump hides a cycle. Any other skipped jump costs
  nothing itself.
- Registers: bypasses from WRITE make ALU operand dependences free. A
  register used as the base of a data read (the address is formed in
  PREPARE) is ready only the cycle after the micro-op that writes it leaves
  WRITE: an --agen (1) cycle stall when it is the previous micro-op. This
  includes the side effects of a push or pop and s0's side effect read by
  s1; --sidefx-fast makes side-effect writes (Rx +/- 1) free. A store
  through @R or @R++ does not wait: WRITE takes the value it wrote last
  (MICROARCH.md §7.4). A skipped writer counts as writing, as DECODE
  cannot tell.
- Data reads are loaded in PREPARE (MICROARCH.md §5.3). A read waits until
  the cycle after the last older SR writer (M = 1, R14 written, control)
  has left WRITE ("SR stall"), whatever its condition: the core decides
  every read's condition first, though MICROARCH.md §5.2 exempts the
  condition "always". A read after a skipped jump may load in the cycle the
  jump leaves WRITE, when it is in PREPARE anyway, so that costs nothing.
  No read loads before an older jump leaves WRITE (MICROARCH.md §5.3, rule
  2, "jump"). That matters after a jump that DECODE resolves with an ADD,
  which takes WRITE two cycles, when its target waits in PREPARE already.
  A skipped instruction waits too, but makes no access.
- The data bus takes one access per cycle, in program order. A read loaded
  in PREPARE in cycle t is on the bus in t + --read-bus (1), since the
  request is a register, and RAM answers in the cycle after that
  ("readbus"). A store leaves WRITE into DBUS's store register, and is on
  the bus from the next cycle until the bus takes it. One into memory
  retires as it leaves WRITE, one into the I/O range when the bus takes
  it ("data bus"). So a read loaded while a store is in WRITE follows it
  on the bus at no cost, and a second read in one micro-op waits a cycle
  ("data bus"). FETCH puts no request on the bus while a store waits in
  the register after its first cycle there, nor in the cycle after WRITE
  queued a store, when DECODE redirected FETCH in that cycle or the one
  before (hdl/src/pipeline.vhd): the target of a jump that DECODE
  resolves right after a store comes a cycle later. The bus decoder,
  hdl/src/wb_dmux.vhd, passes a request to another slave than the one
  before (RAM, the math unit, the counters, the fetch statistics, the
  timer) only a cycle after the last ACK: --slave-gap (1) cycles more
  ("data bus").
- The math unit, as in hdl/src/mpu.vhd: a write to A or B (C or D), accepted
  in cycle t, starts the multiplier and the two dividers (the two 64-bit
  dividers), and a read of a result waits for its unit. The multiplier takes
  two cycles, so a read of a product is accepted on the bus in cycle t +
  --mul (3) at the earliest. A divider takes a cycle to start, then one cycle per
  quotient bit, but --div-skip (8) bits in one cycle while they are all 0,
  which the model works out from the operands in the trace: a read of a
  quotient or remainder is accepted in cycle t + 2 + n at the earliest,
  with n the divider's cycles. The signed dividers divide the absolute
  values. The bus is held until then ("MPU wait").
- A core that forms every operand value, address, and shift count in
  PREPARE, one stage before WRITE, as the re-timed core does, has four
  more rules, each 1 by default; 0 turns one off. --shift-late N: a
  shift (bit 27 set, not a control instruction) whose count WRITE
  reduces, as hazards.py's count_late says, takes N cycles more in
  WRITE, and 2N for a rotation through C ("shiftlate"): a count from
  memory, through an adder (c[R] or --R), with a side effect, in R14, or
  of C<C or C>C, but for a constant word. --shift-reg N: a shift whose
  count is any other register (s1 in mode 000, not R0 or R15) waits in
  PREPARE until N cycles after the micro-op that writes it left WRITE,
  as for --agen ("shiftreg"); the core reduces that count in WRITE too,
  at the same cost. --sum-wait N: the same for a source in
  mode 001 or 011 and a store address in mode 011, 101, or 111, the sums
  ("sumwait"). The waits are not added: a micro-op waits for the latest
  of them, charged to the first that binds.
  --dest-adjust N: a register destination in mode 001 or 010, and a jump
  to a computed target (dest R15 in mode 000 of an operation other than
  MOVE, whose target is its source), take N cycles more in WRITE
  ("adjust"). The waits in PREPARE hold for a skipped instruction too,
  as DECODE cannot tell; the cycles in WRITE only for one that runs.
- --read-late N (1 by default, 0 turns it off): WRITE takes read data N
  cycles after its ACK (MICROARCH.md §5.3), but for a micro-op whose read
  data only goes into a register: s0 or s1 with a side effect, and a MOVE
  into a register other than R15, which take it in the cycle of the ACK
  ("readlate").
- Not modeled: interrupts (an entry is treated as a flush), self-modifying
  code checks, the INSTR_LO retire rule, wrong-path fetch traffic, and bus
  stalls other than the math unit.

Each cycle a micro-op leaves WRITE later than one after its predecessor is
charged to the constraint that bound it, so cycles = instructions +
multi-micro-op cycles + the charged gaps, exactly. The gap has up to three
parts: the wait to enter WRITE, charged to what held the micro-op up before
it, the wait for its read data, and the wait for the bus to take its
store into the I/O range.

The model gives the core's cycles for both benchmark programs to within
0.02%. --retires FILE compares the model with the retire log of the core,
which hdl/test/tb_core.vhd writes with G_RETIRE_LOG (make core in bench/):
for each step, the core's cycles since the step before less the model's,
summed by the cause the model charged and by address.
"""

import argparse
import os
import subprocess
import sys
import tempfile
from typing import Dict, Iterable, List, Optional, Set, Tuple

import hazards

HERE = os.path.dirname(os.path.abspath(__file__))

PHASES = ["rng64", "crc32", "bst", "heapsort", "vm", "strings"]
CAUSES = ["startup", "fetch", "flush", "early", "sr", "jump", "agen", "shiftreg", "sumwait",
          "bus", "mpu", "readbus", "readlate", "shiftlate", "adjust", "interrupt"]
CAUSE_TEXT = {
    "multi": "multi-micro-op instructions",
    "startup": "pipeline start",
    "fetch": "fetch-bound (2 words/cycle, unaligned targets, buffer)",
    "flush": "taken jumps resolved in WRITE (flush)",
    "early": "jumps DECODE resolves (early-redirect bubble)",
    "sr": "data read waits for an older write of SR",
    "jump": "data read waits for an older jump to be done",
    "agen": "address register written by the previous micro-op",
    "shiftreg": "shift count register written by the previous micro-op",
    "sumwait": "sum operand or store address register just written",
    "bus": "data bus: read after store, two reads in a micro-op",
    "mpu": "math unit result not ready",
    "readbus": "read data a cycle after the bus (registered request)",
    "readlate": "read data used by more than a register write",
    "shiftlate": "shift count reduced in WRITE (memory, adder, R14, C<C)",
    "adjust": "destination adjusted by 1, or a computed jump",
    "interrupt": "interrupt entries",
}
INSTR_LO = 0xFFFFFF42
IO_BASE = 0xFFFFFF00
MEMORY = (4, 5, 6, 7)
SIDE = (1, 2, 5, 6)

# The units of the math unit (SYSTEM.md §2), and the result words that wait
# for each: the products, the signed and the unsigned quotient and
# remainder, and the 64-bit ones.
MPU_UNITS = ["mul", "sdiv", "udiv", "sdiv64", "udiv64"]
MPU_RESULTS = {0xFFFFFF22: "mul", 0xFFFFFF23: "mul", 0xFFFFFF24: "mul", 0xFFFFFF25: "mul",
               0xFFFFFF26: "sdiv", 0xFFFFFF27: "sdiv", 0xFFFFFF28: "udiv", 0xFFFFFF29: "udiv",
               0xFFFFFF34: "sdiv64", 0xFFFFFF35: "sdiv64", 0xFFFFFF36: "sdiv64",
               0xFFFFFF37: "sdiv64", 0xFFFFFF38: "udiv64", 0xFFFFFF39: "udiv64",
               0xFFFFFF3A: "udiv64", 0xFFFFFF3B: "udiv64"}


def slave(addr: int) -> str:
    """The slave of the data bus that addr reaches, as in hdl/test/tb_core.vhd."""
    if addr >> 4 == 0xFFFFFF10 >> 4:
        return "timer"
    if addr >> 5 == 0xFFFFFF20 >> 5:
        return "mpu"
    if addr >> 4 == 0xFFFFFF40 >> 4:
        return "perf"
    if addr >> 6 == 0xFFFFFF40 >> 6 and (addr >> 4) & 3:
        return "stats"
    return "mem"


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
    __slots__ = ("reads", "bases", "store", "store_base", "writes", "sidefx", "sr_write",
                 "bypass")

    def __init__(self) -> None:
        self.reads: List[int] = []           # operand index, 0 = s0, 1 = s1
        self.bases: List[Optional[int]] = []  # base register of each read
        self.store = False
        self.store_base: Optional[int] = None
        self.writes: List[int] = []          # registers written
        self.sidefx: List[bool] = []         # whether each write is a +/- 1
        self.sr_write = False
        self.bypass = True                    # its read data only goes into a register


class Info:
    """What the model needs of one instruction word."""
    __slots__ = ("cond", "control", "words", "uops", "redirect", "early", "dm", "dr",
                 "src", "nreads", "shift_late", "shift_regs", "sum_regs", "adjust")
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
    shift_late: int         # WRITE's cycles to reduce a shift's count, 0 to 2
    shift_regs: List[int]   # the register of a shift's count, if one
    sum_regs: List[int]     # registers of sum operands and store addresses
    adjust: bool            # a destination in mode 001 or 010, or a computed jump


def base_of(mode: int, reg: int) -> Optional[int]:
    # R0 is a constant, and DECODE knows R15 (MICROARCH.md §3).
    return None if reg in (0, 15) else reg


def decode(iw: int, c: int = 0) -> Info:
    h = hazards.decode(iw, c)
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
    info.shift_late, info.shift_regs, info.sum_regs, info.adjust = 0, [], [], False
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
    # The read data of a MOVE into a register other than R15 goes into the
    # register only (--read-late). MOVE is opcode 0000 without bit 27, the
    # shift 0<0 has the same opcode.
    op.bypass = not (iw >> 27) & 1 and (iw >> 21) & 15 == 0 and dm == 0 and dr != 15
    # The rules of a core that forms every operand value, address, and
    # shift count in PREPARE (--shift-late, --shift-reg, --sum-wait, and
    # --dest-adjust). R0 is a constant, and DECODE knows R15.
    (m0, r0), (m1, r1) = info.src
    if (iw >> 27) & 1:
        info.shift_late = h.count_late
        if not h.count_late and m1 == 0 and base_of(m1, r1) is not None:
            info.shift_regs = [r1]
    for m, r in info.src:
        if m in (1, 3) and base_of(m, r) is not None:
            info.sum_regs.append(r)
    if dm in (3, 5, 7) and base_of(dm, dr) is not None:
        info.sum_regs.append(dr)
    move = not (iw >> 27) & 1 and (iw >> 21) & 15 == 0
    computed = dm == 0 and dr == 15 and not move
    info.adjust = (dm in (1, 2) and dr != 0) or computed
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


class Model:
    def __init__(self, mem: Dict[int, int], ibuf: int = 16, flush: int = 7, early: int = 3,
                 agen: int = 1, sidefx_fast: bool = False, mul: int = 3,
                 div_skip: int = 8, shift_late: int = 1, shift_reg: int = 1,
                 sum_wait: int = 1, dest_adjust: int = 1, read_late: int = 1,
                 read_bus: int = 1, slave_gap: int = 1) -> None:
        self.mem = mem
        self.bp = max(2, ibuf // 2)
        self.flush, self.early, self.agen = flush, early, agen
        self.sidefx_fast = sidefx_fast
        self.mul, self.div_skip = mul, div_skip
        self.shift_late, self.shift_reg = shift_late, shift_reg
        self.sum_wait, self.dest_adjust = sum_wait, dest_adjust
        self.read_late = read_late
        self.read_bus = read_bus
        self.slave_gap = slave_gap
        self.bubble = {"flush": flush, "early": early, "interrupt": flush + 1}
        self.cache: Dict[Tuple[int, int], Info] = {}
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
        self.restart: Tuple[int, str] = (1, "startup")
        # The cycles in which FETCH may put no request on the bus, for a
        # store in DBUS, and the cycles in which WRITE queued the last
        # stores.
        self.fblock: Set[int] = set()
        self.store_w: List[int] = []
        self.expect_pc = 0
        # Pipeline.
        self.d_prev = -10
        self.leave_prev = -10
        self.s_prev = -10
        self.pin_prev = -10       # cycle the previous micro-op entered PREPARE
        self.w_prev = -10         # cycle the previous micro-op entered WRITE
        self.done_prev = -1       # cycle the previous micro-op left WRITE
        self.first = True
        self.last_bus = -10
        self.last_slave = "mem"
        self.reg_ready = [-10] * 16
        self.reg_done = [-10] * 16  # cycle the last write of each register left WRITE
        self.sr_ready = -10
        self.jump_ready = -10     # first cycle a read may load after the last jump
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
            f.append((self.unblocked(t), tag))
        return f[k]

    def unblocked(self, t: int) -> int:
        """The first cycle from t in which FETCH may put a request on the bus."""
        while t in self.fblock:
            t += 1
        return t

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
        # The sign of the first constant word, which decides whether
        # DECODE predicts a conditional jump.
        sign = self.mem.get((pc + 1) & 0xFFFFFFFF, 0) & 0x80000000
        info = self.cache.get((iw, sign))
        if info is None:
            info = self.cache[(iw, sign)] = decode(iw, sign)
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
        store_addr = 0
        for c in changes:
            if c[0] == "[":
                store_addr = int(c[1:].split("]=")[0], 16)
        first_s = -1
        # The instruction moves into dec_r once the last micro-op of the
        # one before is split off, into PREPARE or skid_r, which frees
        # dec_q for the next (hdl/src/pipe_decode.vhd).
        enter = max(d + 1, self.s_prev + 1)
        counter_read_time = None
        for j, u in enumerate(info.uops):
            # SEQUENCER
            if j == 0:
                s, stag = d + 1, dtag
            else:
                s, stag = self.s_prev + 1, "flow"
            # A micro-op is split off when skid_r is empty: once the one
            # before has entered PREPARE, if it waited in skid_r.
            if self.pin_prev > s:
                s, stag = self.pin_prev, "flow"
            if first_s < 0:
                first_s = s
            # PREPARE: it enters in pin, and may wait there.
            p, ptag = s + 1, stag
            if self.w_prev > p:
                p, ptag = self.w_prev, "flow"
            pin = p
            data = -10
            dtg = "flow"
            for operand, base in zip(u.reads, u.bases):
                t, tag = p, ptag
                if base is not None and self.reg_ready[base] > t:
                    t, tag = self.reg_ready[base], "agen"
                if self.sr_ready > t:
                    t, tag = self.sr_ready, "sr"
                # Nor while an older jump in WRITE may still redirect
                # (MICROARCH.md §5.3, rule 2): until the cycle it is done,
                # which is a cycle late for an ADD into R15.
                if self.jump_ready > t:
                    t, tag = self.jump_ready, "jump"
                if not skipped:
                    # Loaded in t, the read is on the bus in t + --read-bus,
                    # after the access before it.
                    a = addrs[operand]
                    free = self.bus_free(a)
                    if free > t + self.read_bus:
                        t, tag = free - self.read_bus, "bus"
                    acc = t + self.read_bus
                    unit = MPU_RESULTS.get(a)
                    if unit is not None and self.mpu_ready[unit] > acc:
                        acc = self.mpu_ready[unit]
                    late = 0 if u.bypass else self.read_late
                    if acc + 1 + late > data:
                        data = acc + 1 + late
                        dtg = ("mpu" if acc > t + self.read_bus else "readlate" if late else
                               "readbus" if self.read_bus else "flow")
                    self.last_bus = acc
                    if a == INSTR_LO:
                        counter_read_time = acc
                p, ptag = t, tag
            # A store's address is formed in PREPARE too, but a plain @R or
            # @R++ takes the value WRITE wrote last (MICROARCH.md §7.4): no
            # wait. A sum, @c[R] or @--R, waits under --sum-wait below.
            last = j == len(info.uops) - 1
            if last:
                for regs, n, tag in ((info.shift_regs, self.shift_reg, "shiftreg"),
                                     (info.sum_regs, self.sum_wait, "sumwait")):
                    for r in regs if n > 0 else []:
                        if self.reg_done[r] + n > p:
                            p, ptag = self.reg_done[r] + n, tag
            # WRITE. The gap after the micro-op before is charged in three
            # parts: the wait to enter WRITE, the wait for read data, and
            # the wait for the bus to take a store.
            w, wtag = self.done_prev + 1, "flow"
            if p + 1 > w:
                w, wtag = p + 1, ptag
            done = max(w, data)
            parts = [(w - self.done_prev - 1, wtag), (done - w, dtg)]
            if self.first:
                self.gaps["startup"] += done
                self.first = False
            else:
                for n, tag in parts:
                    if n <= 0:
                        continue
                    assert tag != "flow"
                    rt = self.restart[1]
                    if j == 0 and k0 == 0 and tag == "fetch" and rt in self.bubble:
                        # The first instruction after a redirect: the bubble
                        # is the redirect's, the rest (an unaligned or long
                        # target instruction) is fetch's.
                        b = min(n, self.bubble[rt])
                        self.gaps[rt] += b
                        n -= b
                    if n:
                        self.gaps[tag] += n
            # Extra cycles in WRITE, for an instruction that runs.
            if last and not skipped:
                for extra, tag in ((self.shift_late * info.shift_late, "shiftlate"),
                                   (self.dest_adjust if info.adjust else 0, "adjust")):
                    if extra > 0:
                        done += extra
                        self.gaps[tag] += extra
            # A store goes into DBUS's register as it leaves WRITE, and
            # is on the bus from the next cycle. One into the I/O range
            # retires when the bus takes it.
            if u.store and not skipped:
                acc = max(done + 1, self.bus_free(store_addr))
                self.last_bus = acc
                # FETCH makes no request while the store waits in DBUS
                # after its first cycle there (hdl/src/pipeline.vhd).
                self.fblock.update(range(done + 2, acc + 1))
                self.store_w = self.store_w[-1:] + [done]
                if len(self.fblock) > 64:
                    self.fblock = {c for c in self.fblock if c > done - 16}
                if store_addr >= IO_BASE:
                    self.gaps["bus"] += acc - done
                    done = acc
            self.s_prev, self.w_prev, self.done_prev = s, w, done
            self.pin_prev = pin
            for r, fx in zip(u.writes, u.sidefx):
                if fx and self.sidefx_fast:
                    continue
                self.reg_ready[r] = done + self.agen
                self.reg_done[r] = done
            if u.sr_write:
                self.sr_ready = done + 1
            if last and info.redirect:
                self.jump_ready = done
                self.reg_ready[14] = done + self.agen
                self.reg_done[14] = done
        # Leaving DECODE frees the fetch buffer.
        lv = self.leave
        while len(lv) <= k1:
            lv.append(first_s)
        for k in range(k0, k1 + 1):
            lv[k] = first_s
        self.d_prev, self.leave_prev = d, enter
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
        if info.early and skipped:
            # A backward jump that DECODE predicted taken, not taken: WRITE
            # flushes, and FETCH refetches the next instruction.
            self.restart_after(self.done_prev + self.flush - 4, "flush")
        elif info.redirect and not skipped:
            if info.early:
                # Nor in the cycle after WRITE queues a store, if DECODE
                # redirected FETCH in that cycle or the one before.
                for w in self.store_w:
                    if w in (d, d + 1):
                        self.fblock.add(w + 1)
                self.restart_after(d + self.early - 1, "early")
            else:
                self.restart_after(self.done_prev + self.flush - 4, "flush")
        else:
            self.expect_pc = nxt

    def bus_free(self, addr: int) -> int:
        """The first cycle the data bus takes an access to addr. The bus
        decoder passes a request to another slave than the one before
        only --slave-gap cycles after the last ACK (hdl/src/wb_dmux.vhd)."""
        sl = slave(addr)
        free = self.last_bus + 1
        if sl != self.last_slave:
            free += self.slave_gap
        self.last_slave = sl
        return free

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
        self.restart = (self.unblocked(t), tag)
        self.stream_base = -1  # set by the next instruction

    def total(self) -> int:
        return self.done_prev + 1


def run_model(model: Model, lines: Iterable[str]) -> Model:
    for step in hazards.steps(lines):
        if step is None:
            model.interrupt()
            continue
        pc, iw, rest = step
        skipped = bool(rest) and rest[0] == "skipped"
        model.step(pc, iw, skipped, [] if skipped else rest)
    return model


def retires(model: Model, lines: Iterable[str], core_log: str, top: int = 20) -> str:
    """The model's cycle of each step beside the core's, from the retire
    log of tb_core (G_RETIRE_LOG), up to the first step at another
    address. For each step, the core's cycles since the step before less
    the model's are charged to the causes that the model charged that
    step's own gap to, "none" if it charged none, and to the step's
    address. The table gives the sums by cause, and the addresses with
    the largest sums."""
    core: List[Tuple[int, str]] = []
    with open(core_log) as f:
        for line in f:
            c, a = line.split()
            core.append((int(c), a))
    mine: List[Tuple[int, str, str, int]] = []   # cycle, address, cause, iw
    for step in hazards.steps(lines):
        before = dict(model.gaps, multi=model.multi)
        if step is None:
            model.interrupt()
            addr, iw = "intr", 0
        else:
            pc, iw, rest = step
            skipped = bool(rest) and rest[0] == "skipped"
            model.step(pc, iw, skipped, [] if skipped else rest)
            addr = f"{pc:08X}"
        after = dict(model.gaps, multi=model.multi)
        causes = "+".join(k for k in after if after[k] != before[k]) or "none"
        mine.append((model.total() - 1, addr, causes, iw))
    # The two runs part where the program prints a cycle count of its own,
    # which differs, so the comparison ends at the first step that does.
    n = min(len(core), len(mine))
    for i in range(n):
        if core[i][1] != mine[i][1]:
            n = i
            break
    core, mine = core[:n], mine[:n]
    by_cause: Dict[str, List[int]] = {}
    by_addr: Dict[str, List[int]] = {}
    for i in range(1, n):
        d = (core[i][0] - core[i - 1][0]) - (mine[i][0] - mine[i - 1][0])
        addr_key = f"{mine[i][1]} {mine[i][3]:08X} {mine[i][2]}"
        for table, key in ((by_cause, mine[i][2]), (by_addr, addr_key)):
            row = table.setdefault(key, [0, 0, 0])
            row[0] += 1
            row[1] += d
            row[2] += d != 0
    total = (core[-1][0] - core[0][0]) - (mine[-1][0] - mine[0][0])
    out = [f"  {n} steps compared, until the runs part",
           f"  core {core[-1][0] - core[0][0]} cycles, model {mine[-1][0] - mine[0][0]}, "
           f"core - model {total}", "",
           f"  {'cause of the model':24s} {'steps':>9s} {'core - model':>13s} {'differ':>9s}"]
    for key, (k, d, nd) in sorted(by_cause.items(), key=lambda kv: -abs(kv[1][1])):
        out.append(f"  {key:24s} {k:9d} {d:13d} {nd:9d}")
    out += ["", f"  {'address  word     cause':40s} {'steps':>9s} {'core - model':>13s} "
                f"{'differ':>9s}"]
    for key, (k, d, nd) in sorted(by_addr.items(), key=lambda kv: -abs(kv[1][1]))[:top]:
        out.append(f"  {key:40s} {k:9d} {d:13d} {nd:9d}")
    return "\n".join(out)


load_bin = hazards.load_bin


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


# --test: snippets with the cycles worked out by hand from the model. Each
# gives the core's cycles, step by step, in the retire log of tb_core.
TESTS = [
    ("straight-line 1-word register code: 1 per instruction plus the start",
     "\n".join(["        ADD R1, R2, R3", "        ADD R2, R1, R1"] * 50) + "\n        HALT\n",
     # 101 instructions. FETCH's first request is on the bus in cycle 1, so
     # the first instruction is in DECODE at 3, WRITE at 6, so 7 cycles
     # for it, then one per instruction.
     101, 107, {"startup": 6}),
    ("2-word instructions: fetch keeps up",
     "\n".join(["        ADD R1, R2, 0x1234"] * 100) + "\n        HALT\n",
     100 + 1, 107, {"startup": 6}),
    ("3-word instructions: fetch-bound at 1.5 cycles per instruction",
     "\n".join(["        ADD R1, 0x1234, 0x5678"] * 100) + "\n        HALT\n",
     # The first needs pair 1, fetched at 2: DECODE 4, done 7 (startup).
     # HALT at word 300, pair 150, fetched at 151: DECODE 153, done 156, so
     # 157 cycles: 156 - 7 - 100 = 49 fetch-bound.
     101, 157, {"startup": 7, "fetch": 49}),
    ("a counted loop: SUB[M] then ?!Z jump back, each taken jump flushes",
     """        MOVE R1, 10
loop    SUB[M] R1, R1, 1
        ?!Z MOVE R15, loop
        HALT
""",
     # MOVE (2 words) done 6. Each iteration SUB (2 words) + jump (2 words).
     # Taken jump done at t: the redirect reaches FETCH from a register in
     # t + 1, the target SUB is fetched at t + 3, DECODE t + 5, WRITE t + 8:
     # a gap of 7 for each of the 9 taken jumps. The first SUB and the jump
     # come straight from the stream: SUB at 7, jump at 8. The HALT after
     # the untaken jump needs pair 3 (word 6), fine.
     # Instructions: 1 + 10 * 2 + 1 = 22; cycles 22 + 6 (start) + 63 = 91.
     22, 91, {"startup": 6, "flush": 63}),
    ("the same loop with ?!Z ADD R15, R15, offset: DECODE predicts it taken",
     """        MOVE R1, 10
loop    SUB[M] R1, R1, 1
        ?!Z ADD R15, R15, loop-next
next    HALT
""",
     # The offset is negative, so DECODE redirects FETCH to loop as it
     # takes the jump, as for an unconditional jump: a bubble of 3, of
     # which the ADD's second cycle in WRITE hides one, early 2 and adjust
     # 1 for each of the 9 taken jumps. The last jump is skipped: WRITE
     # flushes, and FETCH refetches the HALT, a flush of 7.
     # 22 instructions + 6 (start) + 18 + 9 + 7 = 62.
     22, 62, {"startup": 6, "early": 18, "adjust": 9, "flush": 7}),
    ("a read at the head of a loop waits for the predicted jump to leave WRITE",
     """        MOVE R2, 0x200
        MOVE R6, 3
l       MOVE R3, @R2++
        XOR @0xFFFFFF20, R5, R3
        MOVE R5, @0xFFFFFF24
        DEC[M] R6, R6
        ?!Z ADD R15, R15, l-n
n       HALT
""",
     # The read of the math unit's product waits for it (mpu 3 a round),
     # and meanwhile DECODE takes the jump and redirects FETCH, so the S0
     # of MOVE R3, @R2++ is in PREPARE when the jump enters WRITE. The
     # jump's ADD takes two cycles there (adjust 1), and the read loads
     # only in the second, a cycle after DEC[M]'s SR would allow: 1 more
     # in each of the 2 taken rounds, charged to the read's data, readbus.
     # The skipped jump flushes (7). Without the wait it would be 49
     # cycles; tb_core's retire log of the pipelined core gives 51.
     18, 51, {"startup": 6, "multi": 3, "flush": 7, "bus": 3, "mpu": 9, "readbus": 3,
              "adjust": 2}),
    ("unconditional MOVE R15, label: DECODE redirect, 3-cycle bubble",
     """        MOVE R15, a
        HALT
a       MOVE R15, b
        HALT
b       MOVE R15, c
        HALT
c       HALT
""",
     # Each jump is 2 words, DECODE at d, the target fetched at d + 2 and in
     # DECODE at d + 4: a bubble of 3. Jump 1 is in DECODE at 3, done at 6.
     # a is at word 3, odd, so its words 3 and 4 are in pairs 1 and 2,
     # fetched at 5 and 6, DECODE at 8, done 11: early 3 and fetch 1. b
     # (word 6) and c (word 9, one word) cost 3 each: done 15 and 19.
     # 4 instructions + 6 (start) + 9 + 1 = 20.
     4, 20, {"startup": 6, "early": 9, "fetch": 1}),
    ("a store, then a jump DECODE resolves: FETCH waits for the store",
     """        MOVE R11, 0x200
        MOVE @R11++, 0
        ADD R1, R1, 1
        MOVE R15, next
        HALT
next    HALT
""",
     # MOVE R11 done 6. The store (words 2, 3) leaves WRITE in 7, into
     # DBUS's register, and is on the bus in 8. ADD done 8. The jump (6, 7)
     # is in DECODE at 6 and redirects FETCH: next (word 9, pair 4) would be
     # fetched at 8, but FETCH puts no request on the bus in the cycle
     # after WRITE queues a store, when a redirect came in that cycle or
     # the one before. So it is fetched at 9, DECODE 11, and done 14: early
     # 4. 5 instructions + 6 (start) + 4 = 15.
     5, 15, {"startup": 6, "early": 4}),
    ("a read after SUB[M] waits for SR, with a condition or without",
     """        MOVE R2, 0x100
        SUB[M] R1, R2, 1
        ?!Z MOVE R3, @R2
        SUB[M] R1, R2, 1
        MOVE R3, @R2
        HALT
""",
     # MOVE R2 writes R2, the SUB reads it: free, done 7. ?!Z MOVE R3, @R2
     # would load its read in PREPARE in 7, but the SUB in WRITE may write
     # SR: it loads in 8, a cycle for SR (R2 was written two micro-ops back:
     # no agen stall). The read is on the bus in 9, its data in 10, done 10:
     # a cycle for the bus. The second SUB[M] is done 11, and the MOVE
     # without a condition waits the same way: done 14. HALT done 15.
     6, 16, {"startup": 6, "sr": 2, "readbus": 2}),
    ("push, push, pop: address register from the previous micro-op",
     """        MOVE R13, 0x200
        MOVE @--R13, 1
        MOVE @--R13, 2
        MOVE R1, @R13++
        HALT
""",
     # MOVE R13 done 6. Push 1 needs R13 - 1 from MOVE R13: sumwait 1, done
     # 8, its store on the bus in 9. Push 2 needs R13 - 1 from push 1:
     # sumwait 1, done 10, its store on the bus in 11. The pop's S0 needs
     # R13 from push 2 for its read: agen 1, loaded in 11, on the bus in
     # 12, data in 13, done 13: readbus 1. Its OP is done 14, HALT 15.
     # Instructions 5, micro-ops 6.
     5, 16, {"startup": 6, "multi": 1, "sumwait": 2, "agen": 1, "readbus": 1}),
    ("math unit: write A and B, read the product",
     """        MOVE @0xFFFFFF20, 7
        MOVE @0xFFFFFF21, 6
        MOVE R1, @0xFFFFFF22
        HALT
""",
     # Two 3-word stores into the I/O range, each of which retires when the
     # bus takes it, a cycle after WRITE: the first in WRITE at 7, done 8,
     # the second in WRITE at 9, done 10, which starts the computation. The
     # read is loaded in PREPARE in 10 and on the bus in 11, but the product
     # can be read at 10 + 3 = 13, data in WRITE at 14: a gap of 14 - 10 -
     # 1 = 3. HALT done at 15, so 16 cycles.
     4, 16, {"startup": 7, "bus": 2, "mpu": 3}),
    ("math unit: 9 / 7 unsigned skips 24 quotient bits in 3 cycles",
     """        MOVE @0xFFFFFF20, 9
        MOVE @0xFFFFFF21, 7
        MOVE R1, @0xFFFFFF28
        HALT
""",
     # As above, but the divider: 3 cycles skip 8 bits each, since the
     # dividend's top 24 bits are 0 and 9 shifted into view is not less
     # than 7 until then, and 8 cycles run the rest, n = 11, as tb_mpu
     # counts it. The read is accepted at 10 + 2 + 11 = 23, data at 24:
     # a gap of 13. HALT done at 25, so 26 cycles.
     4, 26, {"startup": 7, "bus": 2, "mpu": 13}),
    ("math unit: -7 / 2 signed divides 7 by 2, n = 11",
     """        MOVE @0xFFFFFF20, 0xFFFFFFF9
        MOVE @0xFFFFFF21, 2
        MOVE R1, @0xFFFFFF26
        HALT
""",
     # The signed divider takes the absolute values: 7 / 2 skips 24 bits
     # in 3 cycles and runs 8, n = 11, so the same 26 cycles.
     4, 26, {"startup": 7, "bus": 2, "mpu": 13}),
    ("math unit: 0xFFFFFFF9 / 2 unsigned skips nothing, n = 32",
     """        MOVE @0xFFFFFF20, 0xFFFFFFF9
        MOVE @0xFFFFFF21, 2
        MOVE R1, @0xFFFFFF28
        HALT
""",
     # The unsigned divider sees a dividend whose top bits are 1, so no
     # cycle skips: n = 32. The read is accepted at 10 + 2 + 32 = 44,
     # data at 45: a gap of 34. HALT done at 46, so 47 cycles.
     4, 47, {"startup": 7, "bus": 2, "mpu": 34}),
    ("the data bus between two slaves: the math unit, then RAM, and back",
     """        MOVE R2, 0x100
        MOVE @0xFFFFFF20, R2
        MOVE R1, @R3
        MOVE @0xFFFFFF21, R2
        MOVE @R2, 5
        MOVE R1, @R3
        HALT
""",
     # MOVE R2 done 6. The store to A is in WRITE at 7, on the bus in 8,
     # done 8: bus 1, and the math unit acknowledges it in 9. The read of
     # RAM at R3 = 0 would be on the bus in 9, but the bus decoder passes a
     # request to another slave only a cycle after the last ACK: loaded in
     # 9, on the bus in 10, data in 11, done 11: bus 1, readbus 1. The
     # store to B, to the math unit again, is in WRITE at 12 and on the
     # bus in 13, done 13: bus 1. The store to RAM is done 14, as it goes
     # into DBUS's register, and is on the bus in 15, a cycle after the
     # math unit's ACK. The read of RAM after it waits for it: loaded in
     # 15, on the bus in 16, done 17: bus 1, readbus 1. HALT done 18, so 19
     # cycles.
     7, 19, {"startup": 6, "bus": 4, "readbus": 2}),
    ("a skipped jump, then a read; a call and a return",
     """        MOVE R13, 0x200
        ?Z MOVE R15, 0
        MOVE R1, @R13
        ADD @--R13, 2, R15
        MOVE R15, f
        HALT
f       MOVE R15, @R13++
""",
     # MOVE R13 (words 0, 1) done 6. ?Z MOVE R15, 0 (2, 3) skipped, done 7.
     # MOVE R1, @R13 (4) loads its read in 7, as the skipped jump leaves
     # WRITE without a flush: on the bus in 8, data in 9, done 9: readbus
     # 1. The call ADD @--R13, 2, R15 (5, 6) is a store, no stall: done 10.
     # MOVE R15, f (7, 8): DECODE 7, done 11, and early: f (word 10, pair
     # 5) fetched at 9, DECODE 11, S0 in PREPARE at 13, in WRITE at 14:
     # early 2, as the jump was in DECODE well before its WRITE. The S0
     # needs R13 from the call, two micro-ops back: free. Its read is on
     # the bus in 14, data in 15, done 15: readbus 1. Its OP is done 16
     # and flushes: HALT (word 9) done 24: flush 7. So 25 cycles:
     # 7 instructions, 1 multi, 6 start, 1 + 2 + 1 + 7.
     7, 25, {"startup": 6, "multi": 1, "readbus": 2, "early": 2, "flush": 7}),
    ("DECODE goes on while PREPARE waits: a loop that prints",
     """        MOVE R13, 0x300
        MOVE R1, str
        ADD @--R13, 2, R15
        MOVE R15, puts
        HALT
puts    MOVE[M] R2, @R1++
        ?Z MOVE R15, @R13++
        MOVE @0xFFFFFF00, R2
        MOVE R15, puts
str     .DAT 0x41, 0x42, 0
""",
     # MOVE R13 done 6, MOVE R1 7, the call 8. MOVE R15, puts (6, 7) is in
     # DECODE at 6, done 9: puts (word 9, pair 4) fetched 8, DECODE 10. Its
     # S0 reads through R1, in WRITE at 13, data 14, done 14: early 3,
     # readbus 1. Its OP is done 15. The ?Z MOVE R15, @R13++ is skipped,
     # but its S0 enters PREPARE in 15 and waits there for SR until 16,
     # done 17: sr 1. Its OP is split off in 15 into skid_r, and is done 18.
     # So the store moves into DECODE's dec_r in 16, which frees dec_q, and
     # DECODE takes the jump in 16, where it would take it in 17 without
     # skid_r. The store to the console is in WRITE at 19 and retires when
     # the bus takes it, done 20: bus 1. The jump is done 21. It redirected
     # FETCH in 16: puts fetched 18, DECODE 20, its S0 in WRITE at 23, done
     # 24: early 1, readbus 1. So each round after the first takes 10
     # cycles. In the third, the MOVE[M] reads 0, and the ?Z jump returns:
     # its S0 reads the stack after SR, done 38: sr 1, readbus 1, and its
     # OP, done 39, flushes: HALT (word 8) done 47: flush 7. So 48 cycles:
     # 15 instructions, 6 multi, 6 start, early 3 + 1 + 1, readbus 4, sr 3,
     # bus 2, and flush 7.
     15, 48, {"startup": 6, "multi": 6, "early": 5, "readbus": 4, "sr": 3, "bus": 2,
              "flush": 7}),
]

# The same, with options of the model set.
OPTION_TESTS = [
    ("--shift-late 1: counts from memory, of C<C, and through an adder; a count in a register",
     """        MOVE R2, 0x100
        MOVE R3, 1
        SHL R1, R3, @R2
        C<C R1, R1, R3
        SHR R1, R1, 2[R3]
        SHL R1, R1, R3
        HALT
""",
     # MOVE R2 done 6, MOVE R3 done 7. The first SHL reads through R2,
     # written two micro-ops back: free, loaded in 7, on the bus in 8, and
     # its count comes from memory a cycle late (--read-late): 10, and it is
     # done at 11. The C<C by R3 would be done at 12, and takes two cycles
     # more for the count mod 33: 14. The SHR by 2[R3] would be done at 15,
     # and is at 16. The SHL by R3, written long before, takes no cycle
     # more: 17. HALT done 18, so 19 cycles.
     {"shift_late": 1}, 7, 19, {"startup": 6, "readlate": 2, "shiftlate": 4}),
    ("--shift-reg 1: a count register from the previous micro-op; a constant count",
     """        MOVE R3, 3
        SHL R1, R1, R3
        SHL R1, R1, 2
        HALT
""",
     # MOVE R3 done 6. The first SHL needs R3 in PREPARE in cycle 7, not 6:
     # done 8. The second SHL shifts by a constant: done 9, though R1 is
     # written by the previous micro-op. HALT done 10, so 11 cycles.
     {"shift_reg": 1}, 4, 11, {"startup": 6, "shiftreg": 1}),
    ("--sum-wait 1: c[R] as a value, @R and c[R] as a store's address",
     """        MOVE R2, 0x100
        ADD R1, 4[R2], R3
        MOVE @R2, R1
        MOVE R2, 0x200
        MOVE @R2, R1
        MOVE R2, 0x300
        MOVE 1[R2], R1
        HALT
""",
     # MOVE R2 done 6. The ADD's 4[R2] needs R2 from the previous micro-op:
     # done 8. MOVE @R2 stores through R2, written two back: done 9. MOVE
     # R2 done 10. MOVE @R2 stores through the R2 WRITE just wrote, which it
     # takes from its last value: done 11. MOVE R2 done 12. MOVE 1[R2]
     # needs the sum in PREPARE: done 14. HALT done 15, so 16 cycles.
     {"sum_wait": 1}, 8, 16, {"startup": 6, "sumwait": 2}),
    ("--dest-adjust 1: R1++ as a destination; a computed jump, jumps to a register and a constant",
     """        MOVE R1++, 5
        MOVE R3, a
        ?!Z MOVE R15, R3
        HALT
a       ?!Z ADD R15, R3, 2
        HALT
""",
     # MOVE R1++ done 7, a cycle late. MOVE R3 done 8. The jump to R3 (Z is
     # clear) takes its target from the source, no cycle more: done 9, and
     # it flushes: a (words 6 and 7, pair 3) fetched 12, DECODE 14. The ADD
     # at a jumps to a + 2, the HALT at word 8: it would be done 17, a flush
     # of 7, is done 18, and flushes: pair 4 fetched 21, DECODE 23, HALT
     # done 26: flush 7. So 27 cycles.
     {"dest_adjust": 1}, 5, 27, {"startup": 6, "adjust": 2, "flush": 14}),
    ("--read-late 1: read data into a register, into the ALU, and into a store",
     """        MOVE R3, 0x200
        MOVE R2, 0x100
        MOVE R1, @R2
        ADD R1, R1, @R3
        MOVE R4, @R2++
        MOVE @R3, @R2
        HALT
""",
     # MOVE R3 done 6, MOVE R2 done 7. MOVE R1, @R2 reads through R2 from
     # the previous micro-op: agen, loaded in 8, on the bus in 9, data in
     # 10, which goes into R1 only: done 10, readbus 1. The ADD reads
     # through R3: loaded in 9, data in 11, which it takes a cycle late:
     # done 12, readlate 1. MOVE R4, @R2++ is S0, which reads into s0 and
     # writes R2, loaded in 11, done 13, and OP, which moves s0 into R4,
     # done 14. MOVE @R3, @R2 reads through R2 from the micro-op before the
     # one before: loaded in 14, data in 16, which it stores a cycle late:
     # done 17, readlate 2. HALT done 18, so 19 cycles.
     {"read_late": 1}, 7, 19, {"startup": 6, "multi": 1, "agen": 1, "readbus": 1,
                              "readlate": 3}),
]


def test() -> None:
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        none: Dict[str, int] = {}
        tests = [(what, src, none, n, cycles, gaps) for what, src, n, cycles, gaps in TESTS]
        for i, (what, src, opts, n, cycles, gaps) in enumerate(tests + OPTION_TESTS):
            nasm, binp = os.path.join(tmp, f"t{i}.nasm"), os.path.join(tmp, f"t{i}.bin")
            with open(nasm, "w") as f:
                f.write(src)
            subprocess.run([sys.executable, os.path.join(HERE, "..", "assembler", "niceasm.py"),
                            "-o", binp, nasm], check=True, stdout=subprocess.DEVNULL)
            m = Model(load_bin(binp))
            for option, value in opts.items():
                setattr(m, option, value)
            run_model(m, hazards.trace_lines(binp))
            have = {k: v for k, v in dict(m.gaps, multi=m.multi).items() if v}
            ok = (m.instructions, m.total(), have) == (n, cycles, gaps)
            bad += not ok
            print(f"{'PASS' if ok else 'FAIL'} {what}: {m.instructions} instructions, "
                  f"{m.total()} cycles" + ("" if ok else f" {have}, expected {n}, {cycles}, {gaps}"))
    if bad:
        sys.exit(f"FAIL pipecycles.py --test: {bad} of {len(tests + OPTION_TESTS)}")
    print("PASS pipecycles.py --test")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--test", action="store_true")
    ap.add_argument("--bin", help="the .bin of a trace FILE")
    ap.add_argument("--ibuf", type=int, default=16, help="words FETCH may run ahead (16)")
    ap.add_argument("--flush", type=int, default=7, help="bubble of a jump taken in WRITE (7)")
    ap.add_argument("--early", type=int, default=3, help="bubble of a jump DECODE resolves (3)")
    ap.add_argument("--agen", type=int, default=1, help="address-register stall (1, 0 = none)")
    ap.add_argument("--sidefx-fast", action="store_true", help="side-effect writes need no agen stall")
    ap.add_argument("--mul", type=int, default=3,
                    help="cycles from the write of an operand to the read of a product (3)")
    ap.add_argument("--div-skip", type=int, default=8,
                    help="quotient bits a divider skips in one cycle (8, 0 = none)")
    ap.add_argument("--shift-late", type=int, default=1, metavar="N",
                    help="extra WRITE cycles of a shift whose count WRITE reduces, twice for "
                         "C<C and C>C (1)")
    ap.add_argument("--shift-reg", type=int, default=1, metavar="N",
                    help="stall of a shift count register written by the previous micro-op (1)")
    ap.add_argument("--sum-wait", type=int, default=1, metavar="N",
                    help="stall of a sum operand or store address register written by the "
                         "previous micro-op (1)")
    ap.add_argument("--dest-adjust", type=int, default=1, metavar="N",
                    help="extra WRITE cycles of a destination in mode 001 or 010, or of a "
                         "computed jump (1)")
    ap.add_argument("--read-late", type=int, default=1, metavar="N",
                    help="cycles from a read's ACK to WRITE, but for a micro-op whose data "
                         "only goes into a register (1)")
    ap.add_argument("--read-bus", type=int, default=1, metavar="N",
                    help="cycles from PREPARE's load of a read to the bus (1)")
    ap.add_argument("--slave-gap", type=int, default=1, metavar="N",
                    help="cycles more for an access to another slave of the data bus than "
                         "the one before (1)")
    ap.add_argument("--phases", type=int, metavar="N",
                    help="fail unless each program reads INSTR_LO around N phases")
    ap.add_argument("--against", metavar="FILE",
                    help="the core's output for the same program (make core in bench/), "
                         "to compare the phases with")
    ap.add_argument("--retires", metavar="FILE",
                    help="the core's retire log for the same program (G_RETIRE_LOG of "
                         "hdl/test/tb_core.vhd), to compare step by step")
    ap.add_argument("--top", type=int, default=20, metavar="N",
                    help="with --retires, the N addresses that differ most (20)")
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
                  a.div_skip, a.shift_late, a.shift_reg, a.sum_wait, a.dest_adjust, a.read_late,
                  a.read_bus, a.slave_gap)
        if a.retires:
            print(retires(m, hazards.trace_lines(path), a.retires, a.top))
            continue
        run_model(m, hazards.trace_lines(path))
        print(report(os.path.basename(path), m))
        if a.phases is not None and len(m.counter_reads) != 2 * a.phases:
            sys.exit(f"pipecycles.py: {path} read INSTR_LO {len(m.counter_reads)} times, "
                     f"not {2 * a.phases}")
        if a.against:
            print(compare(m, a.against))


if __name__ == "__main__":
    main()
