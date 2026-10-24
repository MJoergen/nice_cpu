# History

How the repository got to its present state, moved out of the other
documents so that they describe only what is true now. The specification
is [ISA.md](ISA.md). The reasoning behind each ISA decision and the reviews
of the tools are in [review/](review/). The open items are in
[../TODO.md](../TODO.md).

## The ISA for the pipelined core

ISA.md used to say that every memory access, instruction fetches included,
happened exactly once, in program order, and never speculatively. A pipeline
must fetch ahead, and a Harvard core cannot keep its two buses in one
order, so ISA §8.2 was split into instruction fetches and data accesses,
§8.3 was made to say that instruction fetches never reach I/O devices,
§7.1 was changed to check for interrupts "before each instruction" instead
of "before each instruction fetch", and §5 and §9.4 were made to name the
two kinds of access. §9.4, the mapping of WebAssembly, is
[translator/WASM.md](../translator/WASM.md) now. Appendix B records the two rules.

## The pipelined core

- The first version of the core read the registers in WRITE, with no bypass
  at all, and formed the sums there too. That put a register mux, an adder,
  the shifter or the ALU, and the register write in one cycle, and held the
  clock to about 49 MHz. It was re-timed for 100 MHz on 2026-10-19, so that
  PREPARE reads the registers and forms the operand values, addresses, and
  shift counts ([review/pipeline-timing.md](review/pipeline-timing.md)).
- Until 2026-10-20, WRITE took all read data in the cycle of its ACK,
  straight from the bus. In NiceMonMEGA65 the path from the block RAM
  through the ALU into FETCH held the clock to about 78 MHz. Now only data
  that goes into a register takes that way, and the rest comes from DBUS's
  FIFO a cycle later ([review/pipeline-timing.md](review/pipeline-timing.md),
  Read data).
- Until 2026-10-21, WRITE put each store straight onto the data bus, and
  held it there until the bus accepted it. In NiceMonMEGA65 the path from
  WRITE's decision to store through the system's address decode into the
  block RAM's write enable held the MEGA65 R6 just below 100 MHz. Now a
  store goes out from a register in DBUS a cycle later
  ([review/pipeline-timing.md](review/pipeline-timing.md), Stores). On
  2026-10-23 a store into the math unit was made to retire when it goes
  into the register, as one into memory does, which saved 0.39% of the
  translated benchmark's cycles and 0.08% of `hand.nasm`'s. It was
  reverted as a won't fix: too little for a special case of the I/O
  range.
- The timing of the pipelined core is closed. In NiceMonMEGA65 the R6
  meets 100 MHz and the Nexys4DDR 90 MHz, with 0.174 ns and 0.043 ns of
  slack at 4cd869e ([review/pipeline-timing.md](review/pipeline-timing.md),
  In the system). Further fixes are a won't fix: WRITE's decisions, the
  flush and the end of its micro-operation, into the enables of
  PREPARE's and WRITE's registers (a real fix needs WRITE to know a cycle
  ahead that it will be free, or a buffer between PREPARE and WRITE with
  its own register hazards), WRITE's ALU into its own next state, FETCH's
  next address from its ring, and `irq_ready_o` being combinational from
  WRITE.
- The same first version merged the adjusted destination of a register in
  mode 001 or 010 into one write, and found every jump target through the
  ALU. Now three rare cases take WRITE two cycles (MICROARCH.md §7.4).
- The first version had no speculative reads, and still has none. The
  numbers of MICROARCH.md §5.6, measured on 2026-10-15, decided that FETCH
  reads two words a cycle, that a register written by the previous
  instruction is read without a wait, and that R14 is too. The table was
  measured again on 2026-10-19, on the optimized translation: data reads
  went from 25.9% to 11.3% of the instructions, and a data read after a
  store from 15.3% to 0.3%, but a read after a conditional jump from 0.9% to
  5.5%. The decisions stand, and speculative reads are a won't fix.
- The proof of the data bus port found that a read could go out in the
  cycle WRITE puts a store on the bus with three requests in flight, which
  made five. It also found that the write data changed on the bus while a
  read was stalled. PREPARE now counts that store, and DBUS drives 0 for a
  read.
- Before the re-timing, the translated byte accesses read their shift count
  from a table in memory, which was 3% of the benchmark's instructions.
  They now compute it in a register ahead of the bounds check.
- The fetch statistics (MICROARCH.md §8.1) were a device of their own at
  `0xFFFFFF50`–`0xFFFFFF7F`, and ordinary memory in the emulator. On
  2026-10-20 they became part of the performance counters of SYSTEM.md §3,
  at the same addresses, and the emulator reads them as 0.
- MICROARCH.md §3 and §5.1 once had DECODE read three registers, with
  bypasses from WRITE. The core now reads them in PREPARE, one stage
  before WRITE (hdl/ASSUMPTIONS.md item 1).
- The pipelined core became the default core (753100a): `CORE` in `hdl/`
  and `bench/`, `G_CORE` of `tb_core`, the `--core` option of the test
  scripts, and the CI job default to it, and the documents call the
  multi-cycle core the variant. Before, the multi-cycle core was the
  default.
- Both cores give their registers on `regs_o` (77d6ac6). NiceMonMEGA65
  had read `retire_o.regs` of the pipelined core, which is WRITE's next
  state before the register, and a copy of it ended WRITE's longest paths.
  `regs_o` comes from the registers themselves.
- Until 2026-10-21, DECODE's enables came from PREPARE's decisions against
  WRITE in the same cycle, and WRITE read the vector of an interrupt entry
  straight from the bus. Now DECODE keeps a micro-operation that PREPARE
  does not take in a skid register (bb8fdb6), and WRITE issues the vector
  read through DBUS's register, as it does a store. An interrupt entry
  takes a cycle more, and the benchmark 0.12% fewer cycles.
- Until 2026-10-22, WRITE's redirect reached FETCH in the cycle of the
  flush. Now it comes from registers, a cycle later (1a41b0c), so that no
  path runs from WRITE's decisions through FETCH's adders. A jump that
  WRITE resolves costs 7 cycles over a fall-through, from 6.
- Until 2026-10-24, DECODE redirected FETCH only for jumps with the
  condition "always", and WRITE resolved every conditional jump (issue 46
  on GitHub). Now DECODE predicts a backward conditional `ADD PC, PC,
  offset` taken (MICROARCH.md §5.4), and `bench/hand.nasm` and
  `simple.nasm` close their loops with it, where they had `MOVE PC,
  label`. On the pipelined core the phases of `hand.nasm` went from
  1384879 to 1287563 cycles, 7.0% fewer, and by `bench/pipecycles.py`
  `simple.nasm` took 5.7% fewer. `bench.c` took the same. The model of
  `pipecycles.py` then gained the wait of a read for an older jump
  (MICROARCH.md §5.3, rule 2), which only an `ADD` into R15 that DECODE
  resolves makes cost a cycle.
- The assembler once took a lone word on an indented line, such as a
  misspelt `HALT`, as a label without a word. Now it warns, checks the
  symbols of every `.EQU` also when the name is never used, and lets
  `INT`, `.BLK`, and `.RES` take the value before it wraps (af454a6).

## The random test programs

`hdl/test/random_prog.py` was changed on 2026-10-15 to make jumps shorter,
registers more local, and interrupt routines return. These are the numbers
of `random_stats.py` for seeds 31 to 90 before and after:

| | before | after |
|---|---|---|
| Steps in the program, not in the low words or empty memory | 72% | 88% |
| Program instructions that run at least once | 24% | 56% |
| Interrupt requests taken, of those raised before the run ended | 19 of 115 | 90 of 195 |
| Runs that reach the step limit | 25 of 60 | 26 of 60 |

On seeds 1 to 30, a register read right after its write went from 16% to
33% of the instructions, and jumps from 16% to 24%.

On 2026-10-23 the program began with `?I RTI`, INT became `?!I` in 95% of
its uses, and RTI `?I` in 80%. A write of VBASE puts the vector table among
the low words, where an entry holds 0 or CODE, or a word that a store
changed, so that an interrupt did not return and the next INT halted. For
seeds 1 to 90, the INT halts fell from 15 to 2, and the interrupts taken
rose from 207 to 316 of about 405. The RTI halts rose from 1 to 15, and the
runs that halt before the step limit stayed at about 35 of 90. Seeds 1 to
1000 then passed on both cores, with `make random-sweep`.

## The size and speed of translated code

The code that the translator writes is about half the size it was, after four steps with no change
to WASM.md. Using locals and constants directly as
operands made `test/safe.zig` 19% smaller (12353 to 9941 words) and the
float library 31% smaller (29569 to 20317). A short inline path for
memory accesses made them 12% (to 8730) and 2.5% (to 19808) smaller
again. Helpers for `i64` shifts, and short inline code for a shift by a
constant, took them to 8670 and 18723. Locals in registers, jumps on the
flags after a comparison, and results written straight to a local took
them to 7139 (18% less) and 14565 (22% less). In all, `test/safe.zig` is
42% smaller and the float library 51%.
[doc/review/code-size-plan.md](../doc/review/code-size-plan.md) has the
measurements.

On 2026-10-16, virtual registers with a register allocator, and frames
without a frame pointer, took `test/safe.zig` from 7131 to 6338 words
(11% less) and the float library from 14308 to 8022 (44% less). They
took the benchmark in [bench/](../bench/) from 3359061 to 2539669
instructions (24% fewer).

Later on 2026-10-16, cheaper memory accesses took the benchmark from
2539669 to 1875636 instructions (26% fewer): one compare for the bounds
and the alignment of a word access, word indices computed from array
indices, and inline accesses of 1 and 2 bytes. Their stubs after the
epilogue made `test/safe.zig` larger, from 6338 to 6691 words (6% more),
and left the float library the same size.

After that, the work on the flags, on constants, and on jumps of the
README sections above took the benchmark from 1875636 to 1778350
instructions (5% fewer), and from about 2994000 to about 2634000 cycles
(12% fewer) on the pipelined core of doc/MICROARCH.md, by the estimate
of bench/pipecycles.py. The flags of a comparison or a load used directly, and
multiplications by constants as shifts, saved the most, and copies of
an interpreter's dispatch and conditional instructions in place of
short jumps the next most. `test/safe.zig` became smaller, from 6691 to
6577 words (2% less), and so did the float library, from 8028 to 7454
(7% less).

Then `i64.mul` by a constant inline, loop exits in place of a `br_if`
back, and helpers for traps and for the stubs of word accesses took the
benchmark to 1830683 instructions and about 2448000 cycles, and
`test/safe.zig` to 5242 words and the float library to 7149, counted as
the words of the translated module in a program.

On 2026-10-19, one compare for a group of word accesses, an early
return before the prologue, tail calls, and the longer arm of a diamond
as the one that falls through took the benchmark from 1830683 to
1785571 instructions (2.5% fewer), and from about 2448000 to about
2344000 cycles (4.3% fewer). The diamonds saved the most, in heapsort,
and the shared compares the next most. `test/safe.zig` became smaller,
from 5242 to 5215 words, and so did the float library, from 7149 to
7089, and the benchmark's module, from 8853 to 8632. Of that, 191 words
in the benchmark came from no longer copying short tails into the
stubs.

Later on 2026-10-19, instructions moved from after a data read to the
slot between it and a conditional jump just before it, mostly the jump
to the stub of a word access, took the benchmark from about
2344000 to about 2306000 cycles (1.6% fewer), with the same 1785571
instructions. The reads that wait for a skipped jump went from some
94500 to some 56800 cycles. The vm saved the most, then heapsort and
crc32. `test/safe.zig` became 5224 words, not 5215, the float library
7083, not 7089, and the benchmark's module 8658, not 8632.

After that on 2026-10-19, a constant word offset in the word operand of a
word access, in place of the `ADD` that computed its word index, took
the benchmark from 1785571 to 1737715 instructions (2.7% fewer), and
from about 2306000 to about 2283000 cycles (1.0% fewer). Heapsort saved
the most, then bst and crc32. The vm and strings took some 5000 cycles
more with the same instructions, since their code and data moved,
which changed the timing of fetches and reads. `test/safe.zig` and the
float library stayed 5224 and 7083 words, and the benchmark's module
became 8657, not 8658.

Last on 2026-10-19, no bounds check for an access whose index or base
has a known bound, and instructions moved to between the write of an
address register and the access that uses it, took the benchmark from
1737715 to 1729523 instructions (0.5% fewer), and from about 2283000
to about 2273000 cycles (0.4% fewer). All of the instructions, and
most of the cycles, are crc32's: its table lookup, `table[(crc ^ b) &
255]`, has no compare. `test/safe.zig` became 5182 words, not 5224,
the float library stayed 7083 words, and the benchmark's module became
8623, not 8657.

Then, still on 2026-10-19, the accesses of 1 and 2 bytes took their
shift count from a register, computed with the word index before the
bounds check, in place of a table in memory, and rotations in place of
shifts (below). That is for the core as it is since it was re-timed
for 100 MHz the same day, which forms every shift count in PREPARE: a
count read from memory costs a cycle more in WRITE. A store of 1 or 2 bytes is an
instruction longer, but one of a constant 0 is one shorter, and the
loads are as long as before. The benchmark ran 1730635
instructions in its phases, not 1729523. By `bench/pipecycles.py`, the
phases took 2128130 cycles, not 2154905 (1.2% fewer), with the model as
it was, `--flush 5`, and 2199014, not 2282080 (3.6% fewer), with the
rules of the re-timed core, `--shift-mem 1 --shift-reg 1 --sum-wait 1
--dest-adjust 1`. The byte loads no longer wait for their address
register or for a second read on the bus. `test/safe.zig` became 5171
words, not 5182, the float library stayed 7083 words, and the
benchmark's module became 8560, not 8623.

## The benchmark

- The list of improvements from a look at the translated test programs on
  2026-10-15 was done from 2026-10-16 to 2026-10-19: a register allocator
  in place of frame words, inline memory accesses with one compare for the
  bounds and the alignment, a constant offset in the word operand, one
  compare for a group of accesses, no compare for an index with a known
  bound, flags from the operation before a branch, no mask for a constant
  shift count, conditional instructions in place of short jumps,
  multiplications and divisions by constants, and shift counts of the byte
  accesses in registers. `bench/` went from 3359061 to 1730635
  instructions, and from about 5.55 to about 2.20 million cycles by
  `bench/pipecycles.py`, 2.28 million on the pipelined core.
- A differential fuzzer (`translator/test/diff_fuzz.py`) built in the
  reviews of 2026-10-19 also compared a trap's R2 by wasm instruction. It
  found two bugs in the early return that `fuzz.py` and `run.py` had
  missed.

- On 2026-10-15, before the translator's register allocator and inline
  memory accesses, the hand-written program was 6.8 times shorter in
  instructions and 7.3 times faster in cycles on the multi-cycle core, and
  the translated code took 12.6 cycles per instruction, because more of its
  instructions had constant words and memory operands.
- Before the re-timing of the core, on the older translation of 1729523
  instructions, the pipelined core took 2330619 cycles for `bench.c` and
  1214194 for `hand.nasm`. The new byte accesses saved cycles in `crc32`,
  `vm`, and `strings`, and the re-timing's new waits cost `hand.nasm` 0.2%.
- `rng64` in `hand.nasm` ran at 1.5 cycles per instruction on the pipelined
  core when the multiplier still took longer than two cycles.
- With a bubble of 5 after a jump taken in WRITE, as the model of
  `bench/pipecycles.py` had before, its totals were 7.5% and 15.7% below
  the pipelined core's.
- Until 2026-10-21 the model charged a jump taken in WRITE 7 cycles,
  where the core's bubble was 6, because 7 brought its totals closer to
  the core's: 3.1% and 7.6% below them, against 4.7% and 11.8% with 6.
  The core's retire log (`G_RETIRE_LOG` of `hdl/test/tb_core.vhd`),
  compared with the model step by step (`pipecycles.py --retires`),
  showed that the extra cycle stood in for five rules the model lacked: a
  read is on the bus a cycle after PREPARE loads it, since the request is
  a register; a jump that DECODE resolves costs 3 cycles, not 2, which
  `hdl/test/bubble.nasm` measures as 2 behind its read of the cycle
  counter; every data read waits for an older write of SR, not only a
  conditional one; an access to another slave of the data bus waits a
  cycle after the last ACK; and FETCH's buffer holds 16 words, not 8. A
  read after a skipped jump, which the model had made wait a cycle, may
  go in the cycle the jump leaves WRITE, at no cost. With these, and a
  bubble of 6, the model was within 0.03% of the core at e8c36af in every
  phase of both programs.
- Meanwhile the core gained DBUS's store register, DECODE's skid
  register, and WRITE's redirect from a register, which made its bubble
  7, and the model, with the old rules, fell 5.2% and 13.1% below it.
  The retire log showed what to add: FETCH starts a cycle later after
  reset; a store into the I/O range retires when the bus takes it; FETCH
  waits for a store in DBUS after DECODE's redirect; and DECODE takes an
  instruction once the last micro-op before is split off into skid_r.

## The assembler's checks

On 2026-10-20 (af454a6) the assembler began to warn about a lone word on
an indented line that it reads as a label, such as a misspelled `HALT`. It
checks the symbols of every `.EQU` value once the labels are known, also
when the name is never used, and reports each on the `.EQU` line. `INT`,
`.BLK`, and `.RES` take their value before it wraps.

## The start-up code for a monitor

The runtime library once had `start_mon.nasm` and `start_wasm_mon.nasm`,
start-up code for a program that a monitor in ROM loads at `0x8000` and
calls as a subroutine. ABI.md described them under "Programs under a
monitor". They were removed, because the monitor and the system around
the core belong in [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65).

## The debug link's proof

The formal proof of `hdl/src/debug_link.vhd`, added on 2026-10-24, found
these ways for the link to use the memory when it may not:

- A request waited only for the answer to the last one. A `W` writes each
  word as it arrives, so a `W` that started a clear and was then dropped
  left no answer to wait for, and the next request could use the memory
  while the board cleared it. Now a request also waits for the clear
  (DEBUG.md §6).
- Error `02` was decided only while the program ran. A `W` sent while it
  was held could write the control register, to start it or to clear,
  and then wrap past `0xFFFFFFFF` to address 0, which the board wrote
  while the program ran or the memory cleared. Now a `W` that wraps is
  answered with `e02`, in the emulator too (DEBUG.md §3).
