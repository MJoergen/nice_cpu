# Assumptions of the pipelined core

The pipelined core, `src/pipeline.vhd`, follows
[doc/MICROARCH.md](../doc/MICROARCH.md), which is a draft. Where the note
left a question open, or where the core does something else, this file
says what the core does and why. ISA.md is not changed. Items that need a
change outside `hdl/` are marked **Outside hdl/**, and are also in
[TODO.md](../TODO.md).

## Structure

1. **Registers are read in PREPARE and WRITE, not in DECODE.** MICROARCH.md
   §3 and §5.1 have DECODE read three registers, with bypasses from WRITE.
   The core does without both. WRITE is the only stage that writes the
   registers, in program order, so when a micro-operation reaches WRITE,
   every older one has retired and the register file is current. PREPARE
   reads a register only for the address of a data read, and waits while
   the micro-operation in WRITE will still write it. That wait costs a
   cycle where a bypass from WRITE's result would not, but only for a
   pointer that the previous micro-operation writes, as in `ADD R1, R2++,
   @R2` or a load through a register just loaded. Values in R1 to R4
   passed from one ALU instruction to the next (MICROARCH.md §5.6) need no
   wait, because WRITE reads them. R14 is SR in WRITE, as §5.4 wants. R15
   is the instruction's next address, carried with it, unless an earlier
   micro-operation of the same instruction wrote R15.
2. **DECODE, SEQUENCER, PREPARE, and WRITE share one entity**, as
   cpu_main does in qnice_cpu. FETCH and ICACHE are one entity,
   `src/pipe_fetch.vhd`, with a formal proof of their own. The
   micro-operations and the decode functions are in `src/pipe_pkg.vhd`, and
   the parts both cores share (the ALU, the shifter, the fields) in
   `src/nice_pkg.vhd`.
3. **ICACHE is a ring of 16 words.** FETCH issues a request only when every
   word that may still arrive has room, so at most 8 requests are in
   flight on the instruction bus.
4. **At most 4 data bus requests are in flight**, `C_MAX_OUT`.
5. **An instruction in flight has a 3-bit id**, which PREPARE compares
   with the one in WRITE to tell an older instruction from an earlier
   micro-operation of its own. No more than four instructions are in
   flight between DECODE and WRITE.

## The data bus

6. **WRITE drives its stores and vector reads onto the bus
   combinationally**, and holds them while STALL is high. PREPARE loads
   its reads into a register first. So a read leaves one cycle after
   PREPARE decides on it, and a store in the cycle WRITE runs it. That
   lets a store retire in the cycle the bus accepts it, which the trace
   writer's contract asks (`src/trace_pkg.vhd`, e), at the cost of a
   longer path from the ALU to the bus. A faster clock would register the
   store and delay its instruction's report instead.
7. **A store accepted in cycle c is seen by an instruction fetch accepted
   in cycle c + 1 or later.** This is a contract on the system, stated in
   the header of `src/pipeline.vhd`. `wb_mem` and `wb_dmux`, which has no
   buffer, keep it. A refetch after a store into fetched code relies on
   it.
8. **The read of a performance counter.** ISA.md §8.5 wants a read of
   `INSTR_LO` to count every older instruction, and MICROARCH.md §8 lets
   the core raise `instret_o` early for that. The core raises it in the
   cycle after PREPARE loads an instruction's last data read, or, for an
   instruction without a read, in the cycle its last micro-operation
   retires. PREPARE loads a younger read only after that. The two ways
   never fall in one cycle, which `p_check` asserts.

## Interrupts

9. **Rule 4 of MICROARCH.md §5.3 exempts an instruction that has issued a
   data read.** As written, the rule would stop the second read of an
   instruction such as `ADD R1, @R2, @R3` if a request came after the
   first. But the first read committed the core to the instruction, so
   the request cannot be taken before it, and the core would wait for
   ever. An instruction that has made a read, or whose first
   micro-operation has retired, is exempt, as the instruction after `RTI`
   is. **Outside hdl/:** MICROARCH.md §5.3 should say so.
10. **The report of a step is combinational**, in the cycle the step
    retires, with the registers it leaves. `tb_core` raises a request for
    step S when it sees step S - 1 reported, so the request reaches the
    core at the boundary before step S. The core is then late only when
    step S had already issued a data read, as MICROARCH.md §6 allows.
11. **`irq_compare.py --read-delay`** checks exactly that: a request may be
    taken late by the run of steps right before its entry that are
    instructions with a data read, and by nothing else. `make test
    CORE=pipeline` and `irq_sweep.py` use it, and skip the exact diff
    against the emulator for runs with requests, which cannot hold
    (MICROARCH.md §9).
12. **The timer in `tb_core` ticks with `instret_o`** and the report of
    each interrupt entry, not with the report of each step. A read of
    `TIMER_COUNT` then sees the ticks of every older instruction, as in
    the emulator, whose timer counts steps.
13. **A timer request may be taken late too**, like any other. `tb_core`
    does not log the timer's requests, so `irq_compare.py` cannot allow
    for it. It would show as a difference from the emulator. Only the
    timer probes start the timer, and they show none. The runtime's and
    the translator's programs of `make programs` do not use it either.
