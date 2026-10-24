# The clock of the pipelined core

NiceMonMEGA65 ran the multi-cycle core at 100 MHz. With the pipelined
core it met timing only at 33.3 MHz: its worst path was 29.1 ns over 43
logic levels, from WRITE to a register in nicemon. This file records why,
what each fix is worth in time and in cycles, the plan, and, in the
second measurement at the end, what the re-timing of the same day did:
the core alone now meets 10 ns. The first measurement was on
2026-10-19, at commit 0009a54. The open items are in
[TODO.md](../../TODO.md).

## Method

`pipeline` alone, out of context, in Vivado 2025.2, for the part of the
MEGA65 (`xc7a200tfbg484-2`): synthesis, `opt_design`, `place_design`,
`phys_opt_design`, and `route_design`, with a 10 ns clock. The figures
below are register-to-register paths, so the outputs that `pipeline`
drives combinationally, such as `retire_o`, do not count. A run takes
about 10 minutes, and runs differ by about ±0.7 ns from placement alone.
The script:

    read_vhdl -vhdl2008 { nice_pkg.vhd trace_pkg.vhd pipe_pkg.vhd pipe_fetch.vhd
      pipe_decode.vhd pipe_prepare.vhd pipe_dbus.vhd pipe_write.vhd pipeline.vhd }
    synth_design -top pipeline -part xc7a200tfbg484-2 -mode out_of_context
    create_clock -period 10.000 -name clk [get_ports clk_i]
    set_input_delay -clock clk 0 [get_ports -filter {DIRECTION == IN && NAME != clk_i}]
    set_output_delay -clock clk 0 [all_outputs]
    opt_design
    place_design
    phys_opt_design
    route_design
    report_timing -from [all_registers] -to [all_registers] -max_paths 50 -nworst 1

Each fix was tried as a stand-in: an edit of a copy of `hdl/src` that
keeps the timing of the fix but not its function. A value that another
stage would compute is taken from a register of the micro-operation, for
example. The stand-ins measure what a fix is worth, not what it costs to
build.

## Where the time goes

The core alone takes 24.3 to 25.0 ns, about 41 MHz. The worst path starts
at `w_r.uop.first` and runs through all of WRITE into FETCH:

| Segment | Arrival | Cost |
|---|---|---|
| Base register mux, `src_value` (`R + c`, a carry chain), select s1 | 6.2 ns | 6.2 ns |
| `mod33` of the shift count | 9.8 ns | 3.6 ns |
| Shifter, ALU, and result mux | 20.1 ns | 10.3 ns |
| Destination `regval(x, r) ± 1` (a carry chain), the register write, the new PC | 24.1 ns | 4.0 ns |
| `w_target` into the redirect adder of FETCH | 25.3 ns | 1.2 ns |

So four carry chains run in series in one cycle. Paths that end in
WRITE's own registers are only about 0.5 ns shorter.

In NiceMonMEGA65 the same chain ends in nicemon, which reads the
registers from `retire_o.regs`. That is `w_n.regs`, the registers WRITE
is about to write, not the registers themselves.

## What each fix is worth in time

The fixes:

- **noshift**: no shifter and no `mod33`, only the ALU.
- **shift2**: the shifter reads its operands from registers, as a shift
  over two cycles would.
- **ops**: every operand value and the destination address come from a
  register, as if PREPARE had computed them.
- **dest**: no ± 1 on the destination.
- **redir**: the redirect to FETCH is registered.
- **adder**: the ALU has one adder, as MICROARCH.md §7.2 describes,
  instead of one for each operation.

| Variant | Worst path | About | Ends in |
|---|---|---|---|
| As it is | 24.3 ns | 41 MHz | FETCH |
| redir | 23.7 ns | 42 MHz | WRITE |
| ops | 22.0 ns | 45 MHz | FETCH |
| shift2 | 18.9 ns | 53 MHz | FETCH |
| noshift | 14.7 ns | 68 MHz | FETCH |
| noshift, ops | 11.3 ns | 89 MHz | FETCH |
| noshift, ops, dest | 10.3 ns | 97 MHz | FETCH, through PREPARE |
| noshift, ops, dest, redir | 10.2 ns | 98 MHz | the same |
| noshift, ops, dest, redir, adder | 10.1 ns | 99 MHz | the same, and 280 LUTs fewer |

The shifter is the largest cost. From registered operands it still takes
about 14 ns: about 6 ns for `mod33`, and 8 ns for the shift and the
result mux. So a shift over two cycles that only registers its operands
is not enough.

With every fix, the limit is a control path: the store address, the
three `in_range` compares of a store into fetched code (MICROARCH.md
§5.5), `flush`, the handshake of PREPARE, `consume` of FETCH, and the
`head_r` adder.

## What each fix costs in cycles

The pipelined core runs the benchmark in 6,003,616 cycles for the code
that nicewasm translated (1.79 cycles per instruction), and in 1,541,542
for `hand.nasm` (3.14), from `make core CORE=pipeline` in `bench/`. Those
runs predate the commits that split the core into one entity for each
part, which did not change its cycles.

The cost of each fix comes from the emulator's traces, with the decoding
of `bench/hazards.py`. Each event costs one cycle, or two for a shift
over three cycles, and the counts are scaled to the timed phases. They
are added up, though some overlap, so the totals are upper bounds.

| Fix | Costs a cycle for | Translated | `hand.nasm` |
|---|---|---|---|
| dest | each `R++` or `R--` destination | 0: none occur | 0 |
| adder | nothing | 0 | 0 |
| redir | each jump that WRITE takes | +133 k (2.2%) | +51 k (3.3%) |
| A shift over two cycles | each shift | +437 k (7.3%) | +23 k (1.5%) |
| A shift over three cycles | each shift, twice | +873 k (14.5%) | +47 k (3.0%) |
| Shift counts reduced before WRITE | each shift by a register | +162 k (2.7%) | 0 |
| ops: every operand value from PREPARE | each operand that the previous instruction writes | +824 k (13.7%) | +102 k (6.6%) |
| Only `R + c`, `R - 1`, and the store address from PREPARE | the same, for those modes only | +56 k (0.9%) | +5 k (0.3%) |

13% of the translated instructions are shifts. Most are in the byte
access of the translated code: shift the address right by 2, mask the
byte index, multiply it by 8, and shift the word by that count. That last
shift is by a register that the instruction before it wrote. Every shift
in `hand.nasm` is by a constant. 25% of the translated instructions read
a register that the previous instruction writes, so taking every operand
value from PREPARE costs a lot, and taking only the sums costs little.

## The lean variant

So two plans were compared:

- **Fast clock**: a shift over three cycles, every operand value from
  PREPARE, dest, redir, and adder. +30% cycles for the translated code,
  +13% for `hand.nasm`.
- **Lean**: WRITE still reads the registers for mode 000 and for the
  bases of `@R` and `@R++`. Only `R + c`, `R - 1`, and the store
  addresses of modes 011, 101, and 111 come from PREPARE. The shifter
  stays in WRITE, but its three reduced counts (saturated to 33, mod 32,
  and mod 33) come from a register. With dest, redir, and adder. +6%
  cycles for the translated code, +4% for `hand.nasm`.

| Variant | Worst path | Into WRITE | Into PREPARE | About |
|---|---|---|---|---|
| Lean | 12.2 ns | 11.5 ns | 11.0 ns | 82 MHz |
| Lean, without the shifter | 11.7 ns | | | 86 MHz |
| Lean, every operand from a register | 10.5 ns | | | 95 MHz |
| Lean, without redir | 13.0 ns | | | 77 MHz |
| Lean, the `in_range` compares on a registered address | 11.3 ns | 10.7 ns | 9.7 ns | 88 MHz |
| Fast clock | 10.1 ns | | | 99 MHz |

The worst path of the lean variant is again the store into fetched code:
the base register mux of the store address, the `in_range` compares, and
`flush` into PREPARE and FETCH. Inside WRITE the worst path runs from the
instruction word through the shifter, the result mux, and the PC. The
shifter costs only 0.5 ns there, and redir is worth 0.8 ns.

The time for the translated part of the benchmark, cycles over clock:

| Plan | Translated | `hand.nasm` |
|---|---|---|
| As it is, at 33.3 MHz in NiceMonMEGA65 | 6.00 M cycles, 182 ms | 1.54 M cycles, 47 ms |
| Lean, 82 MHz | 6.35 M cycles, 77 ms | 1.60 M cycles, 19.5 ms |
| Lean with the compares moved, 88 MHz | about 6.35 M cycles, 72 ms | about 1.60 M cycles, 18.2 ms |
| Fast clock, 99 MHz | 7.83 M cycles, 79 ms | 1.74 M cycles, 17.6 ms |

The lean plan is as fast as the fast clock for the translated code, 10%
slower for `hand.nasm`, and a much smaller change: no shift over three
cycles, and few new waits. The cost in cycles of moving the compares is
not counted: PREPARE would need the base of `@R` and `@R++` too, and wait
when the previous instruction writes it.

## Plan

The lean plan, with an 80 MHz clock in NiceMonMEGA65: the full design
places worse than the core alone, and an MMCM makes 80 MHz from 100 MHz.
Each step starts in MICROARCH.md, runs `make test` and `make core
CORE=pipeline`, and is measured out of context as above. The real fixes
add muxes that the stand-ins leave out, so each step may give a little
less than the table says.

1. redir, adder, and dest. dest takes a cycle of its own, or a
   micro-operation of its own from DECODE.
2. `R + c`, `R - 1`, and the store addresses of modes 011, 101, and 111
   from PREPARE, which waits when the micro-operation in WRITE writes
   the register. PREPARE already does this for the addresses of reads
   (MICROARCH.md §5.1).
3. The shift counts reduced before WRITE, for a constant count in DECODE
   or PREPARE, and with one more cycle in WRITE for a count from a
   register.
4. In NiceMonMEGA65, nicemon reads the registers from a registered copy,
   not from `retire_o.regs`.

Beyond about 88 MHz, the store into fetched code needs a new design:
its flush would come a cycle later, or its compares be made before
WRITE. Today WRITE takes the next micro-operation in the cycle of the
store.

## The second measurement

The core was re-timed on 2026-10-19, after the measurements above,
with the method above, in Vivado 2025.1, and the script is now
`hdl/timing.tcl` (`make timing` in `hdl/`). The plan was not followed
step by step. Instead of moving only the sums to PREPARE, every operand
goes there, and WRITE keeps one bypass, the value it wrote last
(MICROARCH.md §7.4); and instead of registering the redirect, WRITE
finds a `MOVE`'s target in its source and takes a second cycle for any
other (§5.4). Each row is one run, and runs differ by a few tenths of a
nanosecond from placement alone:

| Step | Worst path | About | LUTs | Ends in |
|---|---|---|---|---|
| As it was, after the faster mod 33 | 20.4 ns | 49 MHz | 6154 | FETCH, through all of WRITE |
| 1. Operands, addresses, and shift counts from PREPARE; the value written last as the one bypass; the shifter from a prepared count, with no reverse; one adder in the ALU; the ± 1 of a destination, a computed jump target, and a shift count from memory in a second cycle; the store compare as a distance | 10.6 ns | 94 MHz | 5763 | FETCH, from the store address through the compare and the flush |
| 2. The compare on aligned blocks, with no subtraction; a second instruction slot in DECODE, so that FETCH's consume does not wait on WRITE; FETCH's next head from candidates; no count mod 33 in PREPARE | 9.7 ns | 103 MHz | 5491 | DECODE, from the flush through PREPARE's handshake |
| 3. The store address and compare off the kind decode; the count mod 33 of a late count in a cycle of its own | 9.6 ns | 104 MHz | 5485 | the same |
| 4. The jump flag from the decoded register, not the write mux | 9.7 ns | 103 MHz | 5470 | the same, and FETCH's head into DECODE |
| 5. The block after each fetched range computed ahead, in registers, so that the compare has no adder | 10.1 ns | 99 MHz | 5880 | FETCH's block register, from the redirect target through an adder |
| 6. FETCH's next block from candidates, like its next head | 10.2 ns | 98 MHz | 6018 | the same, from the flush |
| 7. FETCH's block a cycle late, from its head register alone, and WRITE comparing with the block after it too | 9.6 ns | 104 MHz | 6256 | DECODE, from the flush through PREPARE's handshake |

The first step took the clock from 49 to 94 MHz, and the rest is the
control path: the flush, which the store compare and WRITE's retire
decide, must reach PREPARE's read decision and DECODE's registers in
the same cycle. Steps 2 to 4 shortened it until several paths differ
only by placement, all within a few tenths of a nanosecond of 10 ns.
Step 5 took the adder out of the compare, which gave the handshake
paths a few tenths more, but put it on the redirect target instead;
step 7 took it off every path. `make timing` on the final code, a
second run of step 7, gave 9.7 ns with 6230 LUTs. What is left is in
TODO.md.

What it costs in cycles, by the model of `bench/pipecycles.py` with the
rules of the new core against those of the old (`--shift-mem 0
--shift-reg 0 --sum-wait 0 --dest-adjust 0`), on the benchmark as
translated the same day, whose byte accesses no longer shift by a
count from memory: 2199014 against 2197301 cycles for the translated
program, and 1122937 against 1121913 for `hand.nasm`, both under 0.1%.
Every case that takes a cycle more is rare in both programs
(`make hazards` in `bench/`): a sum on a register the previous
instruction writes, a shift by such a register or by a word in memory,
a destination adjusted by one, and a jump to a computed target.

## Read data

On 2026-10-20 NiceMonMEGA65 reached about 78 MHz with the core of the
second measurement (issue 34 on GitHub). The worst paths ran from the
block RAM's output into `dbus_data_i`, past DBUS's FIFO into WRITE's
operands, through the ALU, and into FETCH's redirect and WRITE's
registers. Out of context they were not seen, because the script
reported only the paths between registers. `hdl/timing.tcl` now also
reports the paths from the inputs and to the outputs. Their delays
outside the core are 0, so their slack is the time left to the system
around the core. At commit b7b46f4, the paths between registers had
0.20 ns of slack, `dbus_data_i` left 1.59 ns, and the store's
`dbus_addr_o` and `dbus_data_o` left 1.56 ns and 0.93 ns. A block RAM
without an output register takes 2.1 ns from its clock alone.

Two ways to take read data from the FIFO were tried. The cycles are the
core's, from `make core CORE=pipeline` in `bench/`, and the slack is from
one run of `make timing` each:

| WRITE takes read data from the bus | Translated | `hand.nasm` | Left to `dbus_data_i` |
|---|---|---|---|
| Always, as at b7b46f4 | 2241652 | 1215117 | 1.59 ns |
| Never | 2423723, +8.1% | 1392855, +14.6% | more than 3.75 ns, into the FIFO only |
| Only into a register | 2331640, +4.0% | 1288181, +6.0% | 6.50 ns, into WRITE's registers |

In each, the paths between registers had about 0.2 ns of slack. PREPARE
issues a read one stage before WRITE, so a read is rarely early enough to
hide the extra cycle. Most reads in `hand.nasm` are pops and loads into
a register, which the third way leaves as they were. The core takes the
third (MICROARCH.md §5.3). Against 78 MHz it pays off from about 81 MHz
for the translated program and 83 MHz for `hand.nasm`.

It adds a path from `dbus_ack_i` through WRITE's retire into FETCH,
with 2.80 ns left, enough for an ACK from a register. The store still
goes onto the bus from WRITE in the cycle it runs (hdl/ASSUMPTIONS.md,
item 7), with 1.15 ns left for the address and 1.43 ns for the data,
and is what TODO.md takes up next.

## Stores

On 2026-10-21 a fresh build of NiceMonMEGA65 missed 100 MHz on the
MEGA65 R6 by 0.205 ns, with nice_cpu at 68f40ee (issue 34 on GitHub).
The worst path ran from WRITE's micro-operation through its decision to
store, out of `dbus_addr_o` and `dbus_we_o`, and through the system's
address decode into the block RAM's write enable. The Nexys4DDR, a
slower part, ran at 75 MHz.

WRITE now puts a store into a register in DBUS, which drives the bus
from the next cycle on (MICROARCH.md §5.3). Three things follow:

- **A read after a store waits a cycle more**, since it can only go on
  the bus after the store (rule 3). An upper bound is the number of reads
  that PREPARE loaded in the cycle an older store retired: 11936 cycles
  of the translated benchmark (0.51%) and 39527 of `hand.nasm` (3.07%).
- **A store into the I/O range retires only when the bus accepts it**,
  a cycle later. The timer counts steps, and its rule that the write's
  step counts needs the write in the cycle the step is counted on
  `instret_o` (SYSTEM.md §4). Without this, the timer test ran for ever
  and interrupts landed on other instructions than in the emulator.
- **FETCH waits** while the store waits in the register after a redirect,
  or for more than a cycle, since WRITE's check of fetched code
  (MICROARCH.md §5.5) does not cover those fetches.

The cycles of `make core CORE=pipeline` in `bench/`:

| | Translated | `hand.nasm` |
|---|---|---|
| WRITE puts the store on the bus, as at 68f40ee | 2331640 | 1288181 |
| FETCH waits for every store in the register | 2359147, +1.18% | 1343206, +4.27% |
| FETCH waits only as above, as the core does | 2351908, +0.87% | 1333925, +3.55% |

Most of what is left over the bound is `rng64`, which writes the
operands of the math unit, in the I/O range, and reads the product right
after: +10.2% for the translated program and +7.5% for `hand.nasm`.

Out of context, one run of `make timing`:

| | 68f40ee | With the store register |
|---|---|---|
| Between registers | +0.20 ns | +0.20 ns, `w_r` to FETCH's `head_r` |
| `w_r` to DECODE's enables (the handshake) | +0.37 ns | +0.24 ns |
| Left to the system by `dbus_addr_o` | 1.15 ns | 4.52 ns |
| Left to the system by `dbus_data_o` | 1.43 ns | 4.82 ns |
| Worst output | the store | `instret_o`, 2.62 ns |

The store's address and data now come from a register and a mux. The
paths between registers are where they were, within placement. The
handshake into DECODE is next in TODO.md.

## The handshake

On 2026-10-21 NiceMonMEGA65 met 100 MHz on the MEGA65 R6 with the
default directives, once it read the registers from `regs_o`, but the
Nexys4DDR (`xc7a100tcsg324-1`) missed it by 0.27 ns (issue 34 on
GitHub). Every failing path started at WRITE. The largest group ran from
WRITE's state through PREPARE's decision to move on, into the enables of
DECODE's `dec_r` and `dec_q`. Three endpoints ran from WRITE's decision
to read the vector of an interrupt entry, through DBUS, into the block
RAM's address.

Two changes followed:

- **A skid register in DECODE.** DECODE splits off a micro-operation
  whenever its skid register is empty, whether PREPARE takes it or not,
  and keeps one that PREPARE does not take in the register. So the
  enables of DECODE's registers come from its own registers. PREPARE gets
  a micro-operation in every cycle it can take one, as before, and the
  benchmark's cycles barely move. WRITE's check of stores into fetched
  code (MICROARCH.md §5.5) covers the instruction in the skid register
  too, and `hdl/test/smcskid.nasm` fails without that.
- **The vector read through DBUS's register.** WRITE puts the read of an
  interrupt entry's vector into the register that its stores go through
  (Stores, above). An interrupt entry takes a cycle more.

`make timing` in `hdl/` now takes the part of either board and the
directives NiceMonMEGA65 built with then, the `timing` flow, and counts the
endpoints with less than 1 ns of slack by the registers they start and end
at. "NiceMonMEGA65's directives" below means that flow. Since its 671172e,
NiceMonMEGA65 uses it only for the Nexys4DDR. One run each:

| | Before | Skid register | And the vector read |
|---|---|---|---|
| R6 part, default directives | +0.131 ns, 0 failing | +0.326 ns, 0 failing | −0.224 ns, 8 failing |
| Endpoints under 1 ns there | 628 | 342 | 425 |
| Nexys4DDR part, NiceMonMEGA65's directives | −1.610 ns, 1015 failing | −1.135 ns, 644 failing | −1.538 ns, 623 failing |

The groups into DECODE's enables, 482 endpoints, are gone from every
run. What is left moves with placement by half a nanosecond: the eight
failing endpoints of the last R6 run are FETCH's next address, from its
ring through DECODE's instruction length into `head_r`, which neither
change touches. Out of context, the Nexys4DDR's part fails by about 1 ns
more than in NiceMonMEGA65, so there the figures only compare versions
of the core. The worst groups now are WRITE's flush and redirect into
PREPARE's `prep_r` and FETCH's `head_r`, WRITE's own next state, and
FETCH's next address.

## The redirect

On 2026-10-22 NiceMonMEGA65 measured the skid register in the system
(issue 34 on GitHub). The groups into DECODE were gone, but the
Nexys4DDR at 100 MHz missed by 0.395 ns, and the R6 with the default
directives by 0.257 ns. The worst groups ran from WRITE: its redirect
into FETCH's `head_r` and `pair_r`, its own next state, and the flush
into PREPARE's `prep_r`.

Three stand-ins, in the manner of the Method above, measured what each
fix would be worth: (a) FETCH's redirect and target from registers, (b)
WRITE's done, flush, and accept into PREPARE and DECODE from registers,
and (c) both. One run each, out of context:

| Version | Nexys4DDR part, NiceMonMEGA65's directives | R6 part, default directives |
|---|---|---|
| 8712ed0 | −1.538 ns, 623 failing | −0.224 ns, 8 failing |
| (a) | −1.253 ns, 650 failing | +0.152 ns, 0 failing |
| (b) | −1.589 ns, 201 failing | +0.027 ns, 0 failing |
| (c) | −1.202 ns, 57 failing | −0.039 ns, 2 failing |

With (c), what was left was FETCH's next address, from its ring through
DECODE's instruction length into `head_r`, then WRITE's ALU into its own
next state. (b) has no cheap real form: WRITE would have to know a cycle
ahead that it will be free, or a buffer between PREPARE and WRITE would
bring register hazards of its own. So the core took (a) and the next
address:

- **WRITE's redirect reaches FETCH a cycle after its flush**, from
  registers (MICROARCH.md §5.4). DECODE drops what it takes in that
  cycle, FETCH's wait for a store in DBUS (§5.5) covers the redirect
  after the store's own flush, and `halted_o` waits until FETCH has no
  request left, so that a halted core makes no new fetch. `tb_core` now
  runs a few cycles past the end of each run, so that `p_check` in
  `src/pipeline.vhd` sees the halted core; neither it nor the bounded
  check did before. A jump that WRITE resolves costs
  7 cycles over a fall-through, from 6 (`hdl/test/bubble.nasm`).
- **DECODE forms the address after an instruction of each length**
  beside the read of its words, and an early jump's target as the
  address plus 2 plus its constant word, so that one adder follows the
  words where there were two.

The cycles of `make core CORE=pipeline` in `bench/`, against those of
`bench/pipecycles.py --flush 8`, which estimated the cost first:

| | Translated | `hand.nasm` |
|---|---|---|
| 8712ed0 | 2349181 | 1333925 |
| With the registered redirect | 2384635, +1.51% | 1384879, +3.82% |
| The model's estimate | +1.6% | +4.2% |

Out of context, one run each:

| | 8712ed0 | Now |
|---|---|---|
| R6 part, default directives | −0.224 ns, 8 failing | −0.157 ns, 76 failing |
| R6 part, NiceMonMEGA65's directives | | +0.211 ns, 0 failing |
| Nexys4DDR part, NiceMonMEGA65's directives | −1.538 ns, 623 failing | −1.160 ns, 464 failing |

On 2026-10-22, at the release candidate, one run each: the R6 part met 10 ns with
NiceMonMEGA65's directives (+0.163 ns, 0 failing) and missed by 0.115 ns, on 4
endpoints, with the default directives. The Nexys4DDR part missed by 0.650 ns
(389 failing) with NiceMonMEGA65's directives and 1.262 ns (603 failing) with
the default ones.

The redirect is gone from the worst groups, and FETCH's next address
went from the R6's worst path to +0.40 ns. What is left is (b): the
flush, from the check of stores against FETCH's block, into the
enables of `prep_r` and `w_r`.

## In the system

NiceMonMEGA65 measured the core with the registered redirect at 20e9da1
and reported it in issue 34 on GitHub. These figures are its, not `make
timing`'s here, and they were not measured again at later commits. One
run each:

| Board and clock | Directives | Slack |
|---|---|---|
| R6, 100 MHz | NiceMonMEGA65's | +0.570 ns |
| R6, 100 MHz | default | +0.238 ns |
| Nexys4DDR, 90 MHz | NiceMonMEGA65's | +0.173 ns |
| Nexys4DDR, 100 MHz | NiceMonMEGA65's | −0.024 ns, 2 failing |

The two failing endpoints are FETCH's next address, from `ring_r` into
`head_r`. With set D (`-flatten_hierarchy full` and `ExtraNetDelay_high`)
the Nexys4DDR at 100 MHz was worse, −0.246 ns on 195 endpoints, so 100 MHz
on that part depends on placement. NiceMonMEGA65 runs it at 90 MHz. Before
the redirect change, at e693cb8 and 8712ed0, it met 83.33 MHz with +0.114
and +0.112 ns. `make hwtest` passed on both boards at 20e9da1.

NiceMonMEGA65 built the core again on 2026-10-23 at nice_cpu 4cd869e,
and `make hwtest` passed all 59 tests on both boards. One run each:

| Board and clock | Flow | Setup slack | Hold slack |
|---|---|---|---|
| R6, 100 MHz | default | +0.174 ns | +0.041 ns |
| Nexys4DDR, 90 MHz | timing | +0.043 ns | +0.030 ns |

The Nexys4DDR's margin is thin, and it was not tried at 100 MHz again.
