# Decided against

Ideas that were weighed and dropped, with the reason, so that they are not
proposed again. The open items are the
[issues](https://github.com/MJoergen/nice_cpu/issues) of the repository.

- **One block per notice in `TX_IDLE_ST`** of `debug_link.vhd` (item 6 of
  #53, §2.1). Folding the five blocks into one that sends the chosen kind
  touches the `i_out_*` proofs, and gains a few lines.
- **PR #36** (`RDSPC`, `RDSSR`, `WRSPC`, and `WRSSR`, control commands 4 to 7,
  to read and write the saved PC and SR from an interrupt routine). Closed on
  2026-10-26: the debug link's pause and single step (DEBUG.md §6) cover
  breakpoints and stepping from the host. Its branch,
  `claude/project-thread-k4m3qt`, stays.
- **Annotated tags for `RC01` to `RC06`** (sixth review §1.1). They stay
  lightweight: re-tagging means force-pushing tags that others may have
  fetched. `RC06` was made by hand, before `release.py tag` was used. From
  `V1.0` on, `release.py tag` makes them, annotated.
- **Four ways to fewer pipeline stalls in translated code**, tried in the
  translator and dropped, measured with
  `bench/pipecycles.py`:
  - Moving an instruction up past a conditional jump, into the slot
    before a read, when its register is dead where the jump goes. It
    saved 3000 cycles, but the instruction then also runs on the taken
    path: bst ran 11116 more instructions, and strings took 1100 more
    cycles.
  - Sharing a compare by carrying the C flag to the next access, with no
    copy of the slow path. Other compares between the accesses mostly
    prevent it, and it saved 3000 cycles where the copy saves far more.
  - Hiding the math unit's wait on the interpreter's `MUL` by moving
    instructions between the operand writes and the result read. Only
    two or three register-only instructions can move, about 4000 of the
    70000 cycles, and they would cross a store and a trap's start label.
  - A pass that moves an earlier instruction down to break the address
    register and data bus stalls. It saved 721 cycles: the stalls that
    the model counts are the second table read of a byte load, which the
    bus delays anyway, and the pushes and pops of the hand-written
    runtime. Interleaving crc32's two byte loads gained nothing for the
    same reason.
- **Two simplifications of the pipelined stages** (issue #51, items 9 and
  10), each about three lines. WRITE's register write is in two
  branches, and merging them reshapes the re-timed WRITE paths; the
  second also keys the R15 flush on `u_v.wreg`, so that it does not wait
  for the write mux. DECODE's two refill branches could share a mux, but
  it would sit ahead of `first_kind` and lengthen the path from FETCH's
  words. Left alone in issue #54 for the same kind of reason: the math
  unit's two divide start blocks (a procedure would take six
  parameters), and reading the `_o` ports instead of their `_r` copies
  (it breaks the convention of every entity).
- **Speculative reads.** The waits they could remove are 0.006% and
  0.18% of the cycles (MICROARCH.md §5.3, HISTORY.md).
- **A store into the math unit that retires when it goes into the
  register**, as one into memory does. It saved 0.39% of the translated
  benchmark's cycles and 0.08% of `hand.nasm`'s, too little for a special
  case of the I/O range (HISTORY.md).
- **More timing fixes of the pipelined core** (issue #34): WRITE's
  decisions into the enables of PREPARE's and WRITE's registers, WRITE's
  ALU into its own next state, FETCH's next address from its ring, and
  `irq_ready_o` combinational from WRITE (HISTORY.md,
  [pipeline-timing.md](pipeline-timing.md)).
- **Python 3.7 for the hdl scripts.** They need Python 3.10 (`str | None`),
  as README.md says. Sixteen of them would need `from __future__ import
  annotations` for 3.7, and nothing asks for it (sixth review §1.5).
- **A condition or instruction for signed comparison.** A signed a < b
  takes two instructions, `?V XOR R14, R14, 0x10000000` and then `?N`,
  as ISA.md §9.2 shows and nicewasm does. It stays that way.
- **Board synthesis and an example design in this repository.** This
  repository stays FPGA-agnostic. The MEGA65 example design, with its
  synthesis, size, and clock speed, lives in the
  [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
  repository (MICROARCH.md §10).
