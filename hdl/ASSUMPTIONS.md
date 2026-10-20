# Assumptions of the pipelined core

The pipelined core, `src/pipeline.vhd`, follows
[doc/MICROARCH.md](../doc/MICROARCH.md). Where the note left a question
open, or where the core first did something else, this file says what the
core does and why. MICROARCH.md has since taken up items 1, 9, 10, and 15. ISA.md is not changed. Items that need a
change outside `hdl/` are marked **Outside hdl/**, and are also in
[TODO.md](../TODO.md).

## Structure

1. **Registers are read in PREPARE, not in DECODE, and WRITE has one
   bypass.** MICROARCH.md §3 and §5.1 once had DECODE read three
   registers, with bypasses from WRITE. The core reads them in PREPARE,
   one stage before WRITE, and forms every operand value and address
   there (MICROARCH.md §7.4). WRITE is the only stage that writes the
   registers, in program order, so only the micro-operation in WRITE can
   still change a register PREPARE read, and it writes one at most. WRITE
   keeps the value it wrote last, and a field that is that register takes
   it. A field that needs an adder on it, or a read address, waits while
   the micro-operation in WRITE will still write it. That wait costs a
   cycle, but only for a pointer that the previous micro-operation writes,
   as in `ADD R1, R2++, @R2` or a load through a register just loaded, and
   for a sum on a register just written, which neither benchmark has
   (MICROARCH.md §5.6). Values in R1 to R4 passed from one ALU
   instruction to the next need no wait. R14 is SR in WRITE, as §5.4
   wants, and a field that is R14 reads it there. R15 is the
   instruction's next address, carried with it, unless an earlier
   micro-operation of the same instruction wrote R15.

   Reading the registers and forming the sums in PREPARE keeps a register
   mux, an adder, the shifter or the ALU, and the register write out of one
   cycle ([doc/review/pipeline-timing.md](../doc/review/pipeline-timing.md)).

   The registers are in WRITE, not in a module of their own. They are
   `w_r.regs`, R0 to R15 in
   WRITE's state record (`src/pipe_pkg.vhd`), so they are flip-flops,
   not block RAM. There is one write port. PREPARE reads three registers
   at once, for the destination, s0, and s1, each a 16-way mux, and the
   value written last is `w_r.last`. R0 is only ever written with 0, so
   synthesis can reduce it to a constant. PREPARE gets all of `w_r`
   through a port, which is part of why it depends combinationally on
   WRITE (item 7).
2. **One entity for each part**: FETCH in `src/pipe_fetch.vhd`, with a
   formal proof of its own; DECODE in `src/pipe_decode.vhd`; PREPARE in
   `src/pipe_prepare.vhd`; WRITE in `src/pipe_write.vhd`; and DBUS, the
   data bus port, in `src/pipe_dbus.vhd`.
   `src/pipeline.vhd` connects them. Each part keeps its state in
   registers, but not every output is registered: PREPARE decides on a
   read with WRITE's decisions of the same cycle, a flush reaches every
   stage at once, and WRITE drives its stores onto the bus. Registering
   those would cost cycles (item 7). The micro-operations, the decode
   functions, and WRITE's state record are in `src/pipe_pkg.vhd`, and the
   parts both cores share (the ALU, the shifter, the fields) in
   `src/nice_pkg.vhd`.
3. **FETCH's buffer is a ring of 16 words.** FETCH issues a request only when every
   word that may still arrive has room, so at most 8 requests are in
   flight on the instruction bus.
4. **At most 4 data bus requests are in flight**, `C_MAX_OUT`.
5. **An instruction in flight has a 3-bit id**, which PREPARE compares
   with the one in WRITE to tell an older instruction from an earlier
   micro-operation of its own. No more than five instructions are in
   flight between DECODE and WRITE: DECODE holds two, the one it splits
   and the one after it (MICROARCH.md §3).
6. **WRITE takes two cycles for three rare cases** (MICROARCH.md §7.4):
   a register destination in mode 001 or 010, a jump to a target that is
   not a `MOVE`'s source, and a shift whose count PREPARE could not
   reduce, which takes three for a rotation through C. `w_r.exec_done`
   marks the second cycle of the first two, and `w_r.cnt_step`, 0 to 2,
   the progress of the count. No interrupt is taken between the cycles:
   `bound_v` in `src/pipe_write.vhd` waits for both to be clear.

## The data bus

7. **WRITE drives its stores and vector reads onto the bus
   combinationally**, and holds them while STALL is high. PREPARE loads
   its reads into a register first. So a read leaves one cycle after
   PREPARE decides on it, and a store in the cycle WRITE runs it. That
   lets a store retire in the cycle the bus accepts it, which the trace
   writer's contract asks (`src/trace_pkg.vhd`, e), at the cost of a
   longer path from the ALU to the bus. A faster clock would register the
   store and delay its instruction's report instead.
8. **A store accepted in cycle c is seen by an instruction fetch accepted
   in cycle c + 1 or later.** This is a contract on the system, stated in
   the header of `src/pipeline.vhd`. `wb_mem` and `wb_dmux`, which has no
   buffer, keep it. A refetch after a store into fetched code relies on
   it.
9. **The read of a performance counter.** SYSTEM.md §3 wants a read of
   `INSTR_LO` to count every older instruction, and MICROARCH.md §8 lets
   the core raise `instret_o` early for that. The core raises it in the
   cycle the bus accepts an instruction's last data read, or, for an
   instruction without a read, in the cycle its last micro-operation
   retires. The counters return a count from before that cycle's, so the
   instruction's own reads leave it out, and PREPARE loads a younger read
   only then. The two ways never fall in one cycle, which `p_check`
   asserts. A read may wait on the bus, for example while `wb_dmux` waits
   for another slave's ACK, so the count cannot be tied to the cycle
   PREPARE loads the read; `test/instret.nasm` checks this.

## Interrupts

10. **Rule 4 of MICROARCH.md §5.3 exempts an instruction that has issued a
   data read.** As written, the rule would stop the second read of an
   instruction such as `ADD R1, @R2, @R3` if a request came after the
   first. But the first read committed the core to the instruction, so
   the request cannot be taken before it, and the core would wait for
   ever. An instruction that has made a read, or whose first
   micro-operation has retired, is exempt, as the instruction after `RTI`
   is. MICROARCH.md §5.3 says so.
11. **The report of a step is combinational**, in the cycle the step
    retires, with the registers it leaves. `tb_core` raises a request for
    step S when it sees step S - 1 reported, so the request reaches the
    core at the boundary before step S. The core is then late only when
    step S had already issued a data read, as MICROARCH.md §6 allows.
12. **`irq_compare.py --read-delay`** checks exactly that: a request may be
    taken late by the run of steps right before its entry that are
    instructions with a data read, and by nothing else. `make test
    CORE=pipeline` and `irq_sweep.py` use it, and skip the exact diff
    against the emulator for runs with requests, which cannot hold
    (MICROARCH.md §9).
13. **The timer in `tb_core` ticks with `instret_o`** and the report of
    each interrupt entry, not with the report of each step. A read of
    `TIMER_COUNT` then sees the ticks of every older instruction, as in
    the emulator, whose timer counts steps.
14. **A timer request may be taken late too**, like any other. `tb_core`
    logs the timer's requests as IRQs, and `irq_compare.py` runs the
    emulator with its option `--no-timer-irq`, which keeps the timer
    counting but drops its requests, so that the log's requests stand in
    for them (**Outside hdl/:** the option is new in the emulator).

## Formal checks

15. **FETCH, PREPARE, and DBUS are proven, the rest of the core is
    checked for 8 cycles.** `formal/pipe_fetch.sby`, `pipe_prepare.sby`,
    and `pipe_dbus.sby` prove the three for every cycle, with invariants
    under their `G_FORMAL`, and with assumptions that model the stages
    beside them, which `p_check` in `src/pipeline.vhd` checks in the
    whole core. FETCH needs Boolector, which CI installs; Yices does not
    finish its induction, but proves the other two. The whole core is too
    deep for that without many more invariants, so
    `formal/pipeline.sby` checks its ports and its own assertions for the
    first 8 cycles after reset. The simulation tests check the same
    assertions on every run.
