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
