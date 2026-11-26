# Assumptions of the pipelined core

The pipelined core, `src/pipeline.vhd`, follows
[doc/MICROARCH.md](../doc/MICROARCH.md). Where the note left a question
open, or where the core first did something else, this file says what the
core does and why. MICROARCH.md has since taken up items 1, 9, 10, and 12 to 15. ISA.md is not changed.

## Structure

1. **Registers are read in PREPARE, not in DECODE, and WRITE has one
   bypass.** MICROARCH.md §3 and §5.1 describe it. The core reads them in PREPARE,
   one stage before WRITE, and forms every operand value and address
   there (MICROARCH.md §7.4). WRITE is the only stage that writes the
   registers, in program order, so only the micro-operation in WRITE can
   still change a register PREPARE read, and it writes one at most. WRITE
   keeps the value it wrote last, and a field that is that register takes
   it. A field that needs an adder on it, or a read address, waits while
   the micro-operation in WRITE will still write it. That wait costs a
   cycle, but only for a pointer that the previous micro-operation writes,
   as in `ADD R1, R2++, @R2` or a load through a register just loaded, and
   for a sum on a register just written, which the benchmarks have in
   stores alone, in 0.1% and 1.1% of their instructions
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
   read with WRITE's decisions of the same cycle, and a flush reaches
   every stage at once.
   Registering those would cost cycles (item 7). The micro-operations, the decode
   functions, and WRITE's state record are in `src/pipe_pkg.vhd`, and the
   parts both cores share (the ALU, the shifter, the fields) in
   `src/nice_pkg.vhd`.
3. **FETCH's buffer is a ring of 16 words.** FETCH issues a request only when every
   word that may still arrive has room, so at most 8 requests are in
   flight on the instruction bus.
4. **At most 4 data bus requests are in flight**, `C_MAX_OUT`.
5. **An instruction in flight has a 3-bit id**, which PREPARE compares
   with the one in WRITE to tell an older instruction from an earlier
   micro-operation of its own. No more than six instructions are in
   flight between DECODE and WRITE: DECODE holds three, the one it
   splits, the one after it, and the one of the micro-operation in its
   skid register (MICROARCH.md §3).
6. **WRITE takes two cycles for three rare cases** (MICROARCH.md §7.4):
   a register destination in mode 001 or 010, a jump to a target that is
   not a `MOVE`'s source, and a shift whose count PREPARE could not
   reduce, which takes three for a rotation through C. `w_r.exec_done`
   marks the second cycle of the first two, and `w_r.cnt_step`, 0 to 2,
   the progress of the count. The core does not pause between the
   cycles: `pbound_v` in `src/pipe_write.vhd` waits for both to be clear.

## The data bus

7. **WRITE puts its stores into a register in DBUS**, which holds each
   on the bus while STALL is high, and PREPARE loads its reads into a
   register too. So a read leaves one cycle after PREPARE decides on it,
   and a store one cycle after WRITE runs it, and no path runs from the
   ALU to the bus (MICROARCH.md §5.3). A store into memory retires when it
   goes into the register. A store into the I/O range retires in the cycle
   the bus accepts it, as the trace writer's contract asks for the console
   (`src/trace_pkg.vhd`, d). It costs a cycle more, but the I/O range is
   not memory, and its stores are rare.

   Read data takes the other way. WRITE takes it from DBUS's FIFO, a cycle
   after its ACK, unless it only goes into a register (MICROARCH.md
   §5.3). So no path runs from the bus through the ALU into the rest of
   the core.
8. **A store accepted in cycle c is seen by an instruction fetch accepted
   in cycle c + 1 or later.** This is a contract on the system, stated in
   the header of `src/pipeline.vhd`. `wb_mem` and `wb_dmux`, which has no
   buffer, keep it. A refetch after a store into fetched code relies on
   it, and so does FETCH's wait for the store in DBUS (MICROARCH.md §5.5).
9. **The read of a performance counter.** DEVICES.md §3 wants a read of
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

## Formal checks

10. **FETCH, DECODE, PREPARE, and DBUS are proven, the rest of the core
    is checked for 12 cycles.** `formal/pipe_fetch.sby`, `pipe_decode.sby`,
    `pipe_prepare.sby`, and `pipe_dbus.sby` prove the four for every
    cycle, and `pipe_write.sby` proves WRITE's halt: it stays halted
    until reset and makes no store or accept. It proves the same of WRITE's pause, and that WRITE reports a
    step after it leaves `PAUSED_ST` before it pauses again, and what
    PREPARE's proof assumes of WRITE. Together with PREPARE's `f_rd_run` and the definition of
    `halted_o`, that is why a halted core makes no data access, for every
    cycle. The four have invariants under their `G_FORMAL`, and
    assumptions
    that model the stages beside them, which `p_check` in
    `src/pipeline.vhd` checks in the whole core, or the proof of the stage
    they name discharges: DECODE's, WRITE's, and DBUS's for PREPARE's. `formal/nice_pkg.sby` proves the shifter,
    the ALU, and the block compares for every input. FETCH and the
    functions need Boolector, which CI installs; Yices does not finish
    their induction, but proves the other three. The whole core is too
    deep for that without many more invariants, so
    `formal/pipeline.sby` checks its ports and its own assertions for the
    first 12 cycles after reset. The simulation tests check the same
    assertions on every run.
11. **Some registers have no reset, on purpose.** WRITE's `s0val`,
    `s1val`, `last`, `m33sum`, and `cnt`, PREPARE's `rd_addr_r`, DBUS's
    `tags_r`, `rq_r`, `st_addr_r`, and `st_data_r`, and FETCH's `ring_r`
    are not reset. Every use is gated by a valid bit or a count, which
    are reset, so the unreset value is never used. The outputs follow:
    `dbus_addr_o`, for one, is 'U' in simulation until the first request,
    where the multi-cycle core's outputs start at '0'.

## The pause

12. **Rule 4 of MICROARCH.md §5.3 exempts an instruction that has issued
    a data read.** As written, the rule would stop the second read of an
    instruction such as `ADD R1, @R2, @R3` if `pause_i` rose after the
    first. But the first read committed the core to the instruction, so
    the core cannot pause before it, and would wait for ever. An
    instruction that has made a read, or whose first micro-operation has
    retired, is exempt, and so is the first step after a pause: `pause_ok`
    in PREPARE. MICROARCH.md §5.3 says so.
13. **`after_go` marks the first step after a pause.** WRITE sets it when it
    leaves `PAUSED_ST`, and clears it when it reports a step. While it is 1, WRITE does not pause,
    so that one cycle of `pause_i` = 0 runs exactly one step. WRITE leaves
    `PAUSED_ST` when `pause_i` is 0 whether or not `paused_o` had risen,
    so a fall while the core still waits for its ACKs runs one step too.
    It leaves with a flush to R15, so that FETCH fetches again what a
    system may have written meanwhile.
## The breakpoints

14. **DECODE compares the breakpoints** with the address of each
    instruction it takes, and the flag `brk` goes with the instruction
    (MICROARCH.md §6.1). The compare runs from FETCH's address and the
    breakpoint inputs into `dec_r` and `dec_q`, off WRITE's paths. A
    breakpoint written while the core runs therefore misses the
    instructions that DECODE holds already, as DEBUG.md §6 allows. While
    the core is paused, the pipeline is empty, so a breakpoint written
    then is exact.
15. **WRITE takes the flag from PREPARE when it holds no micro-op.**
    PREPARE holds back the data read of a flagged instruction, so such an
    instruction never reaches WRITE, and WRITE would wait for ever. While
    WRITE is empty, `prep_r` holds the oldest instruction in flight, if
    any, so its flag is that of the next step. `prep_r` is a register.
    Dropping this fails `breaks` and `breaks_stall`.
## The register writes

16. **A register write goes in only while paused**, in WRITE's arm of
    `PAUSED_ST` with `pause_i` = 1 (DEBUG.md §6). The pipeline is empty
    there, FETCH waits at R15 with no request, and the go on flushes to
    `w_r.regs(15)`, so the write needs no path to FETCH, DECODE, PREPARE,
    or DBUS. A pulse in the cycle that `pause_i` falls is dropped, since
    the go on would fetch from the old R15 while the register took the
    new one. The debug link never sends one then. `formal_pipe_write`
    proves the write while paused, but not that a write elsewhere changes
    nothing: a second copy of WRITE to compare with was too slow to
    prove. PREPARE's model lets SR change in `PAUSED_ST`, where a write
    may set R14.

## The watchpoints

17. **WRITE checks the watchpoints, as it runs each micro-op**, against
    the addresses of its reads that PREPARE formed, and its store
    (MICROARCH.md §6.1). Only there is it known
    that the access belongs to a step that runs: PREPARE's reads are
    committed, but a skipped instruction makes none. The inputs are
    registered in `pipeline.vhd`, so the compares start at flip-flops,
    and their result feeds only the D inputs of `w_r.wch` and of
    `w_r.wch_any`, its OR. `w_r.wch_pc` follows the address of each step
    until the first hit, so that no compare drives the enable of its 32
    flip-flops. With the compares on an enable, the worst slack of
    `make timing` fell from 0.42 ns to 0.21 ns.
18. **PREPARE holds back the next instruction's reads while a watchpoint
    is enabled.** A hit stops the core after its step, so no read of the
    next instruction may be on the bus by then, as a read of the I/O
    range has side effects. While any enable bit is set, PREPARE issues
    no first data read while an older instruction is in WRITE, nor
    while `w_r.wch` has a bit set. The cost is a cycle or more for each
    instruction with a data read, and only while a watchpoint is
    enabled. Dropping the term fails `watches`.
19. **A hit goes before a pause request**, and the first step after a go
    on is not exempt (DEBUG.md §6). The hit is of the step just ended,
    and its stop is what niceemu reports, whatever else is pending. WRITE
    treats `w_r.wch_any` as if `pause_i` were 1, in the one term
    `rpause_v`, so the hit adds no term to the paths from the pause to
    `done_o` and `instret_o`. A term of its own cost `instret_o` 0.9 ns
    in `make timing`. The term keeps the exemption of `after_go`, but a
    hit cannot be pending while `after_go` is 1: the go on clears it,
    and the step that hits is reported before the next boundary. The
    exemption makes that inductive for `formal_pipe_write`.
