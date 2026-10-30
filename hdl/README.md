# hdl

The FPGA implementation of NICE, in VHDL-2008. The design follows
[doc/MICROARCH.md](../doc/MICROARCH.md), and [doc/ISA.md](../doc/ISA.md) is
the specification.

This directory holds two cores, and the test setup that checks them
(MICROARCH.md §9): a memory model, a console, and a trace writer whose
output can be compared with `niceemu --trace`. The pipelined core is the
one of MICROARCH.md, and the default. The simple multi-cycle core came first,
and is the working reference for it. [ASSUMPTIONS.md](ASSUMPTIONS.md) lists where the
pipelined core settles a question that MICROARCH.md leaves open, or
departs from it.

- [Folder contents](#folder-contents)
- [Running the tests](#running-the-tests)
- [The formal checks](#the-formal-checks)
- [The multi-cycle core](#the-multi-cycle-core)
- [The pipelined core](#the-pipelined-core)
- [The data bus decoder](#the-data-bus-decoder)
- [The debug link](#the-debug-link)
- [The memory model](#the-memory-model)
- [The console](#the-console)
- [The timer](#the-timer)
- [The math unit](#the-math-unit)
- [The performance counters](#the-performance-counters)
- [The fetch statistics](#the-fetch-statistics)
- [The trace writer](#the-trace-writer)

## Folder contents

| Path | What it is |
|---|---|
| [CODING_STYLE.md](CODING_STYLE.md) | The style of the VHDL. |
| [vsg.yml](vsg.yml) | The rules of CODING_STYLE.md for vsg, which `make lint` runs. |
| [sim.mk](sim.mk) | The commands of the simulators, GHDL and nvc, for the Makefile and `bench/Makefile`. |
| [src/multicycle.vhd](src/multicycle.vhd) | The multi-cycle core. |
| [src/pipeline.vhd](src/pipeline.vhd) | The pipelined core: its stages connected, and the invariants they keep. |
| [src/pipe_fetch.vhd](src/pipe_fetch.vhd) | FETCH of the pipelined core. |
| [src/pipe_decode.vhd](src/pipe_decode.vhd) | DECODE of the pipelined core. |
| [src/pipe_prepare.vhd](src/pipe_prepare.vhd) | PREPARE of the pipelined core, with its data read request. |
| [src/pipe_dbus.vhd](src/pipe_dbus.vhd) | DBUS, the data bus port of the pipelined core, with the tags and the read data of the requests in flight. |
| [src/pipe_write.vhd](src/pipe_write.vhd) | WRITE of the pipelined core, with the architectural state. |
| [src/pipe_pkg.vhd](src/pipe_pkg.vhd) | The micro-operations of the pipelined core, what each reads and writes, and WRITE's state record. |
| [src/nice_pkg.vhd](src/nice_pkg.vhd) | The parts of the ISA that the cores share: the operand fields, the register value rule, the condition, the ALU, the shifter, and the flags. |
| [src/mpu.vhd](src/mpu.vhd) | The math unit of SYSTEM.md §2, a Wishbone slave. |
| [src/perf.vhd](src/perf.vhd) | The performance counters of SYSTEM.md §3, a Wishbone slave. |
| [src/timer.vhd](src/timer.vhd) | The timer of SYSTEM.md §4, a Wishbone slave with an interrupt request port. |
| [src/fetch_stats.vhd](src/fetch_stats.vhd) | The fetch statistics of MICROARCH.md §8.1, counters of FETCH and DECODE of the pipelined core, a Wishbone slave. |
| [src/wb_dmux.vhd](src/wb_dmux.vhd) | The data bus decoder, which keeps the ACKs of several slaves in order. |
| [src/debug_link.vhd](src/debug_link.vhd) | The byte-stream part of the debug link of DEBUG.md: packets, the debug registers, notices, and a Wishbone master. |
| [src/trace_pkg.vhd](src/trace_pkg.vhd) | `t_retire`, the record in which the core reports each step to the trace writer, and `t_halt`, the type of the cores' `halt_reason_o`. |
| [sim/trace.vhd](sim/trace.vhd) | The trace writer. Simulation only. |
| [sim/wb_mem.vhd](sim/wb_mem.vhd) | The memory model, with the console and the read counter. Simulation only. |
| [test/tb_mem.vhd](test/tb_mem.vhd) | A self-checking test of the memory model, which loads [test/mem.bin](test/mem.bin) and reads [test/mem.input](test/mem.input) as its console input. |
| [test/tb_shift.vhd](test/tb_shift.vhd) | A self-checking test of the ALU and the shifter of `src/nice_pkg.vhd`: the shifter the pipelined core uses, from a prepared count, against the one the multi-cycle core uses, and the ALU against the operations written out. |
| [test/tb_mpu.vhd](test/tb_mpu.vhd) | A self-checking test of the math unit. |
| [test/tb_perf.vhd](test/tb_perf.vhd) | A self-checking test of the performance counters. |
| [test/tb_perf_hz.vhd](test/tb_perf_hz.vhd) | A self-checking test of the microsecond counter at 33333333, 83333333, and 100000000 Hz, against the integer part of N·10⁶/`G_CLK_HZ`. |
| [test/tb_timer.vhd](test/tb_timer.vhd) | A self-checking test of the timer. |
| [test/tb_fetch_stats.vhd](test/tb_fetch_stats.vhd) | A self-checking test of the fetch statistics. |
| [test/fstats.nasm](test/fstats.nasm) | A program that reads the fetch statistics on the pipelined core, and checks itself. |
| [test/tb_wb_dmux.vhd](test/tb_wb_dmux.vhd) | A self-checking test of the data bus decoder. |
| [test/tb_debug_link.vhd](test/tb_debug_link.vhd) | A self-checking test of the debug link, with the byte streams of DEBUG.md §8 and its errors, notices, timeout, and console. |
| [test/tb_link.vhd](test/tb_link.vhd) | The debug link connected to a core, the data bus decoder, the memory model, and the math unit, as a board connects them. It loads and runs `test/linkecho.nasm` over the link, from `test/link_init.bin`. |
| [test/tb_trace.vhd](test/tb_trace.vhd) | A test of the trace writer, which stands in for the core and runs [test/trace.nasm](test/trace.nasm). |
| [test/tb_core.vhd](test/tb_core.vhd) | Runs a program on a core, which its generic `G_CORE` names, with an interrupt source, and writes its trace. |
| [test/shift.nasm](test/shift.nasm) | Every shift, with the counts that are hard to get right. |
| [test/irqwave.nasm](test/irqwave.nasm) | The program of the interrupt timing diagram, doc/interrupt.tex. |
| [test/addwave.nasm](test/addwave.nasm) | The program of the timing diagram of one instruction, doc/flow.tex. |
| [test/instret.nasm](test/instret.nasm) | Reads of the instruction counter right after a store, after a read, and twice in one instruction. |
| [test/hazard.nasm](test/hazard.nasm) | The hazards of MICROARCH.md §5, each with no padding. It checks itself. |
| [test/programs.py](test/programs.py) | Runs the programs in some directories on the core and on the emulator, for `make programs`. |
| [test/core_runs.py](test/core_runs.py) | Runs a program on the core, or on the emulator, for `irq_sweep.py` and `programs.py`, in GHDL or nvc. |
| [test/irq_compare.py](test/irq_compare.py) | Compares a run with interrupt requests against the emulator, from the steps where the core took them. |
| [test/irq_sweep.py](test/irq_sweep.py) | Runs a program with an NMI before each of its steps, and with an IRQ before each. |
| [test/sidefx_prog.py](test/sidefx_prog.py) | Writes a program with every pair of side effects on one register. |
| [test/pcfx_prog.py](test/pcfx_prog.py) | Writes a program with every pair of side effects on R15. |
| [test/smc_prog.py](test/smc_prog.py) | Writes a program that stores into its own code 1 to 40 words ahead. |
| [test/samereg_prog.py](test/samereg_prog.py) | Writes a program with one register in all three fields of a shift, for every pair of source modes. |
| [test/latecount.nasm](test/latecount.nasm) | Every shift count that WRITE reduces in a cycle of its own, and every reader of such a shift's result. |
| [test/twocycle.nasm](test/twocycle.nasm) | Register destinations adjusted by one, their readers, and two-cycle jumps. |
| [test/r15mix.nasm](test/r15mix.nasm) | R15 in several fields of one instruction, as a shift count, and as a store's base. |
| [test/r14cond.nasm](test/r14cond.nasm) | SR written by side effects and adjusted destinations, then conditional instructions and reads; `INT` and `RTI` with conditions. |
| [test/r0odd.nasm](test/r0odd.nasm) | R0 in every mode as count, source, and destination. |
| [test/smclate.nasm](test/smclate.nasm) | Stores into fetched code from late shifts and two-cycle instructions, and into the constants of early jumps. |
| [test/smcskid.nasm](test/smcskid.nasm) | Stores into the target of an early jump while it waits in DECODE, in `dec_r` and in `skid_r`. |
| [test/predict.nasm](test/predict.nasm) | Predicted jumps in the shapes of loops: two back to back, flags from the instruction before, stores into the target, into the jump's offset, and into the word after it, and a nested loop. |
| [test/readorder.nasm](test/readorder.nasm) | The number and order of the data reads of late shifts, adjusted destinations, and skipped instructions, through the read counter. |
| [test/instret_late.nasm](test/instret_late.nasm) | The instruction counter read right after late shifts, adjusted destinations, stores, skipped instructions, and `INT`. |
| [test/jumpwords.nasm](test/jumpwords.nasm) | Jumps into constant words and to the instruction itself, with conditions on I, and backward conditional jumps, which DECODE predicts taken. It ends at a reserved word. |
| [test/condlate.nasm](test/condlate.nasm) | Conditional late shifts, adjusted destinations in R14, `HALT` and `INT` right after two-cycle flag writes, and more forms of R15. |
| [test/irqhazard.nasm](test/irqhazard.nasm) | Late shifts, adjusted destinations, and side effects on R14 and R15, for a request before each step. |
| [test/shiftjump.nasm](test/shiftjump.nasm) | Every shift with R15 as its destination, `0<0` among them, whose opcode is `MOVE`'s. |
| [test/rtiread.nasm](test/rtiread.nasm) | `RTI` that returns to instructions with data reads, run one step at a time. |
| [test/pausepatch.nasm](test/pausepatch.nasm) | A word of code that `tb_core` writes while the core is paused, with its hand-checked trace in [test/pausepatch.expected](test/pausepatch.expected). |
| [test/breaks.nasm](test/breaks.nasm) | Stops at breakpoints in a loop, at a data read, at a false condition, in an interrupt routine, after `RTI`, and with an IRQ pending at a jump target and at an instruction that the pipelined core holds already. |
| [test/break_stops.py](test/break_stops.py) | Lists the stops of a program at its breakpoints on the emulator, over the debug link, as `tb_core` lists the core's. |
| [test/bubble.nasm](test/bubble.nasm) | Measures the bubbles of the pipelined core with the cycle counter, and checks itself. |
| [test/readwait.nasm](test/readwait.nasm) | Data reads that wait for their condition and for an older micro-operation, which `tb_core` counts on the pipelined core. |
| [test/random_prog.py](test/random_prog.py) | Writes random programs, and random interrupt requests for them. |
| [test/random_stats.py](test/random_stats.py) | Shows how the random programs spend their steps, and how often they make each hazard. |
| [test/trace_reads.py](test/trace_reads.py) | Finds the first line where two traces differ, and shows the data reads of that instruction. |
| [formal/wb_master_check.vhd](formal/wb_master_check.vhd) | Formal properties of a Wishbone master port. |
| [formal/wb_slave_check.vhd](formal/wb_slave_check.vhd) | Formal properties of a Wishbone slave port that never stalls and answers in the next cycle. |
| [formal/handshake_check.vhd](formal/handshake_check.vhd) | Formal properties of a valid/ready port that takes requests. |
| [formal/core_check.vhd](formal/core_check.vhd) | Formal properties of the ports of a core: a checker on each of its four ports, and the rules of a stopped core. |
| [formal/formal_multicycle.vhd](formal/formal_multicycle.vhd) | The multi-cycle core with `core_check`. |
| [formal/multicycle.sby](formal/multicycle.sby) | The SymbiYosys job for it. |
| [formal/formal_timer.vhd](formal/formal_timer.vhd) | The timer with checks of its bus and interrupt ports. |
| [formal/timer.sby](formal/timer.sby) | The SymbiYosys job for it. |
| [formal/formal_wb_dmux.vhd](formal/formal_wb_dmux.vhd) | The data bus decoder with checks of its master and slave ports. |
| [formal/wb_dmux.sby](formal/wb_dmux.sby) | The SymbiYosys job for it. |
| [formal/formal_nice_pkg.vhd](formal/formal_nice_pkg.vhd) | The functions of `src/nice_pkg.vhd` and the block compares of `src/pipe_pkg.vhd`, against ISA.md and MICROARCH.md for every input. |
| [formal/nice_pkg.sby](formal/nice_pkg.sby) | The SymbiYosys job for it. |
| [formal/formal_pipe_fetch.vhd](formal/formal_pipe_fetch.vhd) | FETCH of the pipelined core, whose properties are in `src/pipe_fetch.vhd`. |
| [formal/pipe_fetch.sby](formal/pipe_fetch.sby) | The SymbiYosys job for it. |
| [formal/formal_pipe_decode.vhd](formal/formal_pipe_decode.vhd) | DECODE of the pipelined core, whose properties are in `src/pipe_decode.vhd`. |
| [formal/pipe_decode.sby](formal/pipe_decode.sby) | The SymbiYosys job for it. |
| [formal/formal_pipe_prepare.vhd](formal/formal_pipe_prepare.vhd) | PREPARE of the pipelined core, whose properties are in `src/pipe_prepare.vhd`. |
| [formal/pipe_prepare.sby](formal/pipe_prepare.sby) | The SymbiYosys job for it. |
| [formal/formal_pipe_dbus.vhd](formal/formal_pipe_dbus.vhd) | DBUS of the pipelined core, whose properties are in `src/pipe_dbus.vhd`. |
| [formal/pipe_dbus.sby](formal/pipe_dbus.sby) | The SymbiYosys job for it. |
| [formal/formal_pipe_write.vhd](formal/formal_pipe_write.vhd) | WRITE of the pipelined core, with the properties of its halt, its pause, and its breakpoints, and PREPARE's assumptions about it. |
| [formal/pipe_write.sby](formal/pipe_write.sby) | The SymbiYosys job for it. |
| [formal/formal_pipeline.vhd](formal/formal_pipeline.vhd) | The pipelined core with `core_check`. |
| [formal/pipeline.sby](formal/pipeline.sby) | The SymbiYosys job for it. |
| [formal/formal_perf.vhd](formal/formal_perf.vhd) | The performance counters with checks of their bus port against a model of the counters. |
| [formal/perf.sby](formal/perf.sby) | The SymbiYosys job for it. |
| [formal/formal_fetch_stats.vhd](formal/formal_fetch_stats.vhd) | The fetch statistics, with and without counters, whose properties are in `src/fetch_stats.vhd`. |
| [formal/fetch_stats.sby](formal/fetch_stats.sby) | The SymbiYosys job for it. |
| [formal/formal_mpu.vhd](formal/formal_mpu.vhd) | The math unit with checks of its bus port, whose other properties are in `src/mpu.vhd`. |
| [formal/mpu.sby](formal/mpu.sby) | The SymbiYosys job for it. |
| [formal/formal_debug_link.vhd](formal/formal_debug_link.vhd) | The debug link with checks of its ports, whose other properties are in `src/debug_link.vhd`. |
| [formal/debug_link.sby](formal/debug_link.sby) | The SymbiYosys job for it. |

## Running the tests

You need GHDL, Python 3, and Zig 0.17 for the emulator. Tested with
GHDL 6.0.0-dev and GHDL 4.1.0 (mcode backend). CI installs 4.1.0, the
`ghdl` package of Ubuntu 24.04.

`SIM=nvc` runs the simulations in [nvc](https://www.nickg.me.uk/nvc/)
instead, tested with nvc 1.20 locally and 1.23.0 in CI. Its traces are byte for byte those of
GHDL, and it is several times faster on the long runs (`make programs`,
`make sweep`, and the benchmark in `bench/`). On short runs it is slower,
because its compiler takes about a second of CPU time on each: `make test`
took 15 minutes in nvc and 5 in GHDL on 20 CPUs. GHDL is still needed for
the synthesis check of `make test` and for `make formal`. The top-level
`make slow` runs in nvc.
[sim.mk](sim.mk) holds the commands of both: nvc analyzes into
`build/nvc`, and elaborates each run in memory. `make analyze` analyzes
for `SIM`.

    cd hdl && make test

`make test` builds the emulator, analyzes the VHDL, checks that GHDL can
synthesize both cores, the math unit, the performance counters, the timer,
the fetch statistics, and the data bus decoder (`ghdl --synth`), and runs the tests, those of
the cores once for each core. Everything it makes goes in `build/`.
`make clean` removes it.

The runs go in parallel, one per CPU, or as many as `-j` gives, and
their PASS and FAIL lines come in the order they finish. Each run leaves
its files in a directory of its own, `build/run/GROUP/NAME`, where GROUP
is `unit`, `trace`, or the core: for a run on a core, the core's trace
and output in `core.out`, the emulator's in `core.expected`, and the
simulator's messages in `core.log`. `make run/pipeline/NAME` repeats one run, for
example `make run/pipeline/hazard_stall`.

`test/programs.py` runs a `.bin` on a core in the simulator and compares its output
with the emulator's. `--sim` picks GHDL or nvc. `--stall PERCENT` sets `G_STALL` of the memory, and
`--core` picks the core (`make programs`).

`make lint` checks the style of every VHDL file against
[CODING_STYLE.md](CODING_STYLE.md), as far as
[vsg](https://vhdl-style-guide.readthedocs.io/) can, with the rules in
[vsg.yml](vsg.yml). It needs `pip install vsg==3.35.0`, the version CI uses. It fails on errors and only
warns about lines over 100 columns.

`make timing` runs Vivado on the pipelined core alone, out of context, as
[doc/review/pipeline-timing.md](../doc/review/pipeline-timing.md)
measures it ([timing.tcl](timing.tcl)): synthesis, placement, and routing
with a 10 ns clock. `BOARD` selects the part: `mega65` (the default,
`xc7a200tfbg484-2`) or `nexys4ddr` (`xc7a100tcsg324-1`). `FLOW` selects the
directives: `default`, or `timing`, those NiceMonMEGA65's Nexys4DDR build uses.
`PERIOD` sets the clock in ns, and `BREAKS` the number of breakpoints,
`G_BREAKS`, 4 by default as on the boards. The reports go to
`build/timing/BOARD-FLOW-BREAKS/`, so that runs for several boards can go at once.
It prints the worst register-to-register path and leaves the 50 worst in
`timing.rpt`. It does the same for the paths from an input, in
`timing_in.rpt`, and to an output, in `timing_out.rpt`, but for `retire_o`
and `stats_o`. Their delays outside the core are 0, so their slack is the
time left to the system around the core: for the data bus, its address
decode, its block RAMs, and its read mux. Last, it prints
`timing_groups.rpt`: the endpoints with less than 1 ns of slack, counted by
the register or port they start from and the one they end at, with the
worst slack of each group.
`timing_ack.rpt` has the 5 worst paths from `dbus_ack_i` alone, since `rst_i`
can fill the 50 of `timing_in.rpt`.
It takes about 3 minutes with the default flow. `VIVADO` names the
executable, `/opt/Xilinx/2025.1/Vivado/bin/vivado` unless the environment
or the command line sets it.

At the end it judges the slacks against the budget of the board in
[test/timing_budget.py](test/timing_budget.py), at a 10 ns clock: the core
alone must meet the clock, and the inputs and the outputs must leave the
system 1.5 and 2.2 ns (`mega65` only). The two come from the slack of the
ports inside NiceMonMEGA65 at `V1.0`, and keep about 0.2 ns of it. It prints the result, writes `budget.json` beside the
reports, and says `MISSED` on a miss, but exits 0. `release.py check` puts
the result in its stamp, and no release waits for it.

What a system may add to the core's ports, from `make timing` at 2026-10-23
(`timing` and `default` flows, one run each; a run varies by a few tenths of
a nanosecond with placement). The slack is the time left to the system at
the clock of the first column:

| Clock and part | `dbus_ack_i` | `instret_o` |
|---|---|---|
| 100 MHz, MEGA65 (-2) | 3.1 to 3.4 ns | 2.6 to 3.0 ns |
| 100 MHz, Nexys4DDR (-1) | 2.0 to 2.2 ns | 1.1 to 1.8 ns |
| 90 MHz, Nexys4DDR (-1) | 3.1 to 3.2 ns | 2.1 to 2.4 ns |

- `instret_o` has the least. It comes from WRITE's retire, and the counters
  of SYSTEM.md §3 must see it in that cycle (MICROARCH.md §8), so a system
  should not register it without changing that rule.
- `dbus_ack_i` goes into WRITE's retire and so into FETCH, through 10 LUT
  levels. A system should drive it from a register, or from little logic,
  not from an address decode and a wait-state mux.
- A store or a vector read leaves DBUS's register. `dbus_addr_o` and
  `dbus_data_o` have 2.6 ns or more in every run (the least is
  `dbus_data_o` on the MEGA65), and most have 4 ns or more. Read data goes
  into WRITE only for a register write.
- At 90 MHz on the Nexys4DDR the core alone still fails by 0.3 ns, on paths
  inside it (WRITE into PREPARE's enables), but NiceMonMEGA65 meets 90 MHz
  in the system ([pipeline-timing.md](../doc/review/pipeline-timing.md),
  In the system).

`tb_mpu` checks every word of the math unit against `numeric_std`: for 20
corner cases and 2000 random pairs of A and B, and for 16 corner cases and
4000 random pairs of C and D. It also checks that a read of a result waits
for the computation, exactly as long as it should, that a write restarts
it, that the two halves and the units in each do not wait for each other, that a write and a read in back-to-back cycles see
each other in order, and that reset clears the operands.

`tb_perf` starts the counters just below a wrap of their low words. It
checks that the cycle counter counts every cycle with `run_i` high and
stands still with it low, that the instruction
counter counts the cycles with `instret_i` high, and that a read of a high
word returns the snapshot of the last read of the low word, across the
wrap. It also checks the spare words, that writes change nothing, and reset.

`tb_timer` runs the timer on the clock, as a system does. It checks that a
write of P sets the period and the count, that the request comes at the end
of the P-th cycle counting the write's, and that the count stops while
`tick_i` is low. A raised request must keep its vector until `ready`, also
when the vector is written and more requests merge with it, and a check
in every cycle makes sure of that. It also checks a stop with a request
pending, P = 1 with `ready` high in every cycle, the spare words, and reset.

`tb_fetch_stats` drives the events of a few cycles by hand. It checks
that each counter counts its events from the cycle after a write that
clears and starts the counters, up to the write that stops them, that
`FS_MIN`, `FS_MAX`, and `FS_HELD_MAX` follow the words in the buffer,
that stopped counters keep their values, that a write of 1 starts them
again without a clear, the spare words, writes to other words, and reset.
A second instance, with `G_ENABLE` false, must read 0.

`tb_wb_dmux` sends 5000 random requests through the data bus decoder to
three slaves that stall at random and answer in order at their own pace:
one in the next cycle, one slowly, and one that stalls while it owes an
ACK, as the math unit does. It checks that each ACK reaches the master in
the order of the requests, with the data of the slave and the request it
answers, that a slave gets STB only for a request to it and only while no
other slave owes an ACK, and that a request that may pass is not stalled.

`tb_debug_link` plays a host and a board against the debug link, and
compares every byte that the link sends with a string whose checksum was
worked out by hand: the examples of DEBUG.md §8, the errors `e01` to `e03`,
the dropped packets, the timeout, console bytes both ways with ESC ESC, the
notices `b`, `h`, `o`, `p`, and `x`, the clear, one that a dropped packet started,
a `W` that wraps past `0xFFFFFFFF`, the hold and restart, and the pause: its
notice after and before the answer, the memory and registers while paused,
a hold and a start that keep or begin a pause, a go on, and a halt that
goes first; and the step: `pause_o` low for exactly one cycle, bit 4 and the
memory during the step, one `p` after it, a quick step, a hold during the
step, a write with bit 5 that does not step, and a step into a halt; and
the breakpoints: their registers and ports, `x` with the lowest number at a
start, a step, and a stop of the core's own, the stop register and how long
it lasts, `p` when no enabled breakpoint is at R15, and a reset that clears
them.

`tb_link` runs on each core of `CORES`. It is the debug link as a board
uses it: the link is a second master of the data bus, and owns it while
the processor is held, halted, or paused. The test reaches the memory model and the
math unit through `wb_dmux`, loads `test/linkecho.nasm` with a `W`, starts
it, and checks its echo of console bytes, `e02` while it runs, the halt
after a UART break with the registers it left, the restart of DEBUG.md §8,
a pause of the core with its registers, memory, and console, a hold
while it runs, the halt reasons 2 to 4, and the single step: R15 after each step of the echo program,
a step into `HALT`, the writes with bit 5 that do not step, and an `INT` with
the registers of each step as `niceemu --trace` shows them, and the
breakpoints, 4 on the link and the core: a stop before the echo, a step and
a go on from a breakpoint, and a breakpoint disabled while paused. The testbench shows three things a board must
do: each master sees only its own STALL and ACK; the devices are reset at
a start, when `hold_o` falls, and not while the processor is held, so that
the link can reach them; and an instruction ACK that comes after a hold
reset the core is ignored, as Wishbone ignores an ACK while CYC is low.

`tb_trace` runs four times, each against the emulator on the same program
with the same NMI: with the full trace, without the trace, and stopped at two
step limits. The output and exit status of each run must match the
emulator's exactly.

`tb_core` runs these programs on the core that its generic `G_CORE` names:
`pipeline` by default, or `multicycle`. Both cores have the same ports,
but for the pipelined core's `stats_o`, and the rest of the testbench
serves them both. `make test` runs them on
each core in `CORES`, both by default, and `make test CORES=pipeline` on
one. `make random`, `make programs`, `make sweep`, and `make strides` run the core in
`CORE`, and pass it on to `test/irq_sweep.py` and `test/programs.py` with
their option `--core`. `make random-sweep` runs seeds 1 to `RANDOM_LAST`
(1000) of `make random` on each core of `CORES` in turn. The PASS and FAIL lines name the core. The trace, the output,
and the exit status of each must match those of `niceemu -t` on the same
program, with the same interrupt requests. The pipelined core may take a
request later than the emulator (MICROARCH.md §6), so its runs with
requests are compared only by `test/irq_compare.py --read-delay`, below.

- The three 2004 examples `count`, `replicate`, and `print`, and `wrap`, from
  `assembler/test/`.
- The emulator's probes in `emulator/test/`, `cputest` among them, with the
  interrupt options that `emulator/Makefile` gives them, but `scrbound`,
  `screencolor`, and `screeninvert`, which check the emulator's screen and
  need `--color` and `--invert-fg`. Their memory dumps
  are left out, because the trace lists every memory write. The trace does
  not list data reads, but `reads` counts them with the read counter, so
  its registers show whether the core made each read exactly once and in
  order (ISA.md §8.2). `mpu` and `mpu64` read every word of the math unit.
  `perf` reads the instruction counter, with an NMI and an `INT`, and
  checks the cycle counter only through flags, because the emulator counts
  steps, not cycles. `timer` runs the timer, which counts steps here: its
  `tick_i` is the core's `instret_o` and its report of each interrupt
  entry, so that a read of `TIMER_COUNT` sees the ticks of every older
  instruction on any core. Its request and those of the
  interrupt source share the core's IRQ port, with the vector of the one raised first when both are pending, as the emulator merges them.
- `test/shift.nasm`.
- `test/irqwave.nasm`, with two IRQs: one that comes before an instruction
  that has not begun, and one that comes just after the next instruction
  has issued its data read, which the pipelined core takes after that
  instruction. Its values are those of the timing diagram
  [doc/interrupt.png](../doc/interrupt.png).
- `test/addwave.nasm`, the worked example of ISA.md §11 between plain
  instructions. Its values are those of the timing diagram
  [doc/flow.png](../doc/flow.png).
- `test/instret.nasm`, also on a memory that stalls in 30% of the cycles.
  It reads the instruction counter right after a store to RAM, which the
  data bus decoder makes the read wait for, after a read of RAM, as the
  source of a store, and twice in one instruction.
- The hazard programs of MICROARCH.md §9, step 4, each also on a memory
  that stalls in 30% of the cycles. `test/hazard.nasm` makes each hazard
  of MICROARCH.md §5 with no padding: flags tested by the next
  instruction, conditional reads and stores right after the write of SR,
  registers read by the next instruction, R14 and R15 as pointers, stores
  into the next few words, and jumps over `HALT`. It checks its own
  results, and a failed check ends at a reserved word, with R12 naming the
  section. So the emulator's run must end with R12 = 0 and exit status 0,
  which also shows that no jump fell into a `HALT`. `test/sidefx_prog.py`
  writes a program with every mode in every field of one `SUB`, all on R2
  or R14, which holds every pair of side effects on one register, and
  every pair of a `SUB` that writes the register and a `SUB` that uses it
  next, or one instruction later. It does not check itself.
  `test/pcfx_prog.py` does the same for R15, whose side effects are
  jumps, in one instruction only. Each instruction sits in a block of its
  own, with words around it that lead to the next block, and the script
  models each instruction to choose its operation, constants, and address
  so that it gets there. It checks itself: R12 is 0 at the end only if
  every block ran once.
  `test/smc_prog.py` writes a program that stores a NOP over a `HALT` 1
  to 40 words ahead, from the next word to beyond FETCH's buffer and its
  requests in flight, so that some store lands in the pair whose fetch
  the bus accepts in the same cycle (MICROARCH.md §5.5): three of its
  forty stores do with no stalls, and two with 30%. It checks itself:
  R12 is 0 at the end only if every `HALT` was passed. The programs
  `test/latecount.nasm` to `test/shiftjump.nasm` in the table above test
  the operand rules of MICROARCH.md §7.4: the shift counts WRITE reduces
  in a cycle of its own, the destinations adjusted by one, R14 and R15 in
  every field, R0, stores into fetched code from late instructions, the
  read counter and the instruction counter around them, jumps into
  constant words, and every shift into R15, `0<0` among them, whose
  opcode is `MOVE`'s. `test/samereg_prog.py` writes one more, with one
  register in all three fields of a shift, for every pair of source
  modes and six destination modes. None of them checks itself; the
  core's trace is compared with the emulator's.
- `test/hazard.nasm` with an interrupt request at every point (MICROARCH.md
  §9, step 5). `test/irq_sweep.py` runs it once for each step S, with
  `--nmi S:8`, and once more with `--irq S:9`, on a memory that stalls in
  30% of the cycles. Each run on the core must match the emulator's, and
  the emulator must take the request and still pass the program's checks.
  So `hazard.nasm` keeps E = 1 at all but one step, and has a vector
  table entry for each VBASE it uses. Each run is repeated with the
  request raised a few cycles late, with `--delays` and `tb_core`'s
  `G_INTR_DELAY`, so that it arrives at different points within an
  instruction: 3 and 7 cycles on the multi-cycle core, and 1, 2, and 3
  on the pipelined one. A delayed run is compared only through
  `test/irq_compare.py`. The runs go in parallel, on all
  cores; set the number with `-j`. Each worker runs the simulator in its own
  directory under `build/sweep`, because the LLVM and GCC backends of GHDL
  write an executable where they run. `test/irqhazard.nasm` and
  `test/latecount.nasm` are swept the same way, without the delays.
  For each kind, `irq_sweep.py` says how many steps no request came
  before because it had to wait (ISA.md §7): those of an `INT` routine
  and the step after its `RTI`, and for IRQ, those with E = 0.
- The programs of `test/pcfx_prog.py` and `test/sidefx_prog.py` swept
  with `--stride 16`: each run raises a request before every 16th step,
  from step k, and 16 runs, k = 0 to 15, cover every step. A request
  taken adds the steps of its entry and its routine, so `irq_sweep.py`
  shifts the later requests of a run by them, and counts the steps that a
  request came before. `sidefx_prog.py`'s program writes R14 with any
  value, so at some steps there is no vector table. `irq_sweep.py` drops
  a request whose entry finds no vector word that names the same routine
  as the one for VBASE = 0, and says how many steps it left out: about
  280 of 7444 for NMI, and 75 for IRQ. `make sweep` sweeps the two with
  one request per run instead.
- `cputest`, `reads`, `mpu`, `mpu64`, `perf`, and `timer` again, on a memory that
  stalls in 30% of the cycles.
- On the pipelined core only, `test/fstats.nasm`, also on a memory that
  stalls in 30% of the cycles. It reads the fetch statistics around a
  loop of jumps, and checks what any run must give: the histogram adds up
  to the cycles, `FS_MIN` ≤ `FS_MAX` ≤ `FS_HELD_MAX` ≤ 16, at least one
  jump and flush per round, and cycles in which DECODE waited. The
  emulator has no fetch statistics, so the run is not compared with it:
  it must end with R12 = 0 and exit status 0. `test/bubble.nasm` runs
  the same way: it reads the cycle counter before and after each kind of
  jump, and checks the bubbles below. `test/readwait.nasm` is compared
  with the emulator, and `tb_core`'s line of read waits (The pipelined
  core) must give 1 and 1 that went on, and 0 and 2 dropped.
- 30 random programs from `test/random_prog.py`, each stopped at 3000 steps,
  on a memory that stalls in 30% of the cycles. Besides random ALU and
  shift instructions, they use R15 with every side effect, `HALT`, `RTI`,
  `INT`, reserved control words, and the read counter. Most jumps skip
  only a few instructions, sources often read a register that one of the
  last three instructions wrote, and each interrupt vector leads to a
  short routine that ends with `RTI`. A random program may read any address, and now and then one reaches the cycle counter at
  `0xFFFFFF40`, where the core counts cycles and the emulator counts steps
  (SYSTEM.md §3). The microsecond counter at `0xFFFFFF44` differs likewise.
  So these runs make the words of both counters ordinary memory on both
  sides, with the generic `G_CYCLE_COUNTER` and the emulator's
  `--no-cycle-counter`. The generic `G_FETCH_STATS` false makes the
  fetch statistics read 0 and ignore writes, as in the emulator. The
  instruction counter and the math unit stay, because both sides agree
  on them.

`test/random_stats.py` shows how well the random programs test the core
(MICROARCH.md §9, step 8). It runs a range of seeds on the emulator, as
`make test` does, and reports where the steps run, how much of each
program runs, how many interrupt requests are taken, how the runs end, and
how often they make the hazards of MICROARCH.md §5, beside the benchmark's
shares. With `--generator`, it measures another version of
`random_prog.py`.

`make programs` runs the test programs of the runtime and of the
translator, and 10 random modules of `translator/test/fuzz.py` in each of
its four modes (`FUZZ_PROGRAMS`), on the core (MICROARCH.md §9, step 7). It is not part of
`make test`, because it takes 25 minutes on the pipelined core and 51 on the
multi-cycle one, on 20 CPUs: some 2 million steps in 490
programs, at GHDL's 3300 steps a second. In nvc, `SIM=nvc`, it took 5
and 3 minutes on 2026-10-28. CI runs it in nvc on
both cores, a job for each. `SHARD=I/N` runs the Ith of N shares of the
programs, of nearly equal steps, longest first. That run is the release's: the
top-level `make slow` leaves `make programs` out ([RELEASE.md](../release/RELEASE.md)). It does not run `runtime/libc/test/fuzz_printf.py`, which
needs clang, or the benchmark, which `make core` in `bench/` runs. `make test KEEP=DIR`
in `runtime/` and `test/run.py --keep DIR` and `test/fuzz.py --keep DIR` in `translator/` run their
tests and leave the programs in `build/programs`, with the console input
of those that read one. Then `test/programs.py` runs each on the core and
on the emulator and compares them, as `make test` does, with the console
input on both sides. The runtime's clock reads the cycle counter, so these
runs make its two words memory, as the random programs do.

`make sweep` sweeps the programs of `test/pcfx_prog.py` and
`test/sidefx_prog.py` on the core in `CORE` with one request per run, as
`hazard.nasm` is swept, but without the delays. A run of the whole
program for each of its 9500 steps and each kind of request makes some
19000 runs. On 20 CPUs, that took 3.8 hours on the pipelined core and 2
on the multi-cycle one on 2026-10-27, and both passed. Run it after a
change to the interrupt path: WRITE's interrupt entry, RTI, or the
request ports.

`make strides` sweeps the same two programs on `CORE` with each stride of
`SLOW_STRIDES`, 17, 31, and 64, in one pool of `SWEEP_JOBS` workers.
`make test` sweeps them with stride 16; 17 and 31 shift the requests
against those, and 64 leaves most of each run without one. That is 448
runs, which took 5.7 minutes on the pipelined core on 20 CPUs. `make slow`
at the top runs it, not `make sweep`.

`make random` runs more random programs, with the seeds, step count, and
stall rate given as variables:

    make random RANDOM_SEEDS="$(seq 31 90)" RANDOM_STALL=60 RANDOM_STEPS=5000

When a run fails, `test/trace_reads.py` helps to see why. It takes the
program and the two traces, replays the emulator's trace to the first
line that differs, and prints the data reads of that instruction, with
the names of the I/O words it knows:

    test/trace_reads.py build/random_65.bin build/run/multicycle/random_65/core.expected \
      build/run/multicycle/random_65/core.out

## The formal checks

`make formal` runs the SymbiYosys jobs in `formal/`. It is not part of
`make test`, because it needs more tools: Yosys with the GHDL plugin,
SymbiYosys, and the solvers Yices 2 and Boolector. CI installs the OSS
CAD Suite of 2026-09-30, which has them all: Yosys 0.69, GHDL 7.0.0-dev
with its plugin, Yices 2.7.0, and Boolector 3.2.4. It is also tested with
Yosys 0.56 and GHDL 6.0. GHDL 4.1, which CI used before, cannot
synthesize `shift_right` or `shift_left` of `numeric_std_unsigned` by an
amount that is not constant, so the formal code uses `srl` and `sll`
instead.

`formal_multicycle` connects the multi-cycle core to `core_check`, which
both cores share, and which puts a checker on each of four ports. Every
input is free, apart from a reset in the first cycle, so the solver plays
every slave, every interrupt source, and every program. Each checker
assumes the rules of the other side of its port and asserts the core's:

- The instruction bus and the data bus (`wb_master_check`), as pipelined
  Wishbone B4 masters. Generics set the widths of the address and the data,
  so one checker serves both buses. The checker assumes that a slave sends
  ACK only while CYC is high and only for an accepted request. It asserts
  that STB is high only with CYC, that a stalled request is held with WE,
  ADDR, and DATA unchanged, that CYC stays high while a request waits for
  its ACK, from the cycle after it is accepted on, that at most one
  request waits at a time, and that reset drops CYC and STB. A slave with
  a registered ACK relies on CYC in that first cycle, so dropping CYC then
  would be no clean way to abandon a request.
- The NMI and IRQ ports (`handshake_check`), with the AXI handshake. The
  checker assumes that a device holds `valid` and the vector until `ready`.
  It asserts that the core raises `ready` only for a request, and never in
  reset.

`core_check` also asserts the rules of a stopped core
(MICROARCH.md §6.1), with `pause_i` free, so that the system around the
core may take the buses over: a halted core has no bus cycle open and
stays halted until reset, with `halt_reason_o` other than `HALT_NONE`
exactly then; a core that is paused, with `pause_i` still 1, stays paused
with no bus cycle open and `regs_o` unchanged; it is never paused and
halted at once; and once `paused_o` falls, it reports a step on
`retire_o` before `paused_o` rises again. With two breakpoints, whose
addresses and enable bits are free, it asserts that the core pauses
without `pause_i` only when R15 was an enabled breakpoint, and then stays
paused until `pause_i` has been 1.

`formal_wb_dmux` checks the data bus decoder with three slaves and up to
three ACKs owed. Every input is free. It assumes that the master raises
STB only with CYC, and that a slave sends ACK only while CYC is high and
it owes one. It asserts that a slave gets STB only with the master's STB
and only when the select names it, that no slave gets STB while another
owes an ACK, that the master's request is accepted exactly when a slave
accepts it, and that the master's ACK and data are those of the slave
that owes ACKs, only while the master is owed one. So all the requests in
flight are at one slave, and the ACKs come back in order. Its `prove`
task uses PDR (`abc pdr`), which finds the invariants that tie the
decoder's count to the checker's, so the decoder needs no `G_FORMAL`.
The `cover` task shows a request that waits for another slave's ACKs,
the most ACKs owed, and a switch from one slave to another.

`formal_timer` checks the timer's ports from the other side. Every input
is free. It asserts that a raised request stays raised, with its vector,
until `ready` takes it, which is what `handshake_check` assumes of a
device, and, with `wb_slave_check`, that the bus port acknowledges each
request in the next cycle and never stalls.

The `prove` task proves the assertions for every cycle by k-induction of
depth 2, in a few seconds. The induction needs invariants that tie the ports to the core's state: the state
is one of its 14 values, and each bus has CYC high exactly in its wait
states. The core asserts them itself when its generic `G_FORMAL` is true;
`formal_multicycle` sets it, and the other users leave it false. The
`cover` task shows that each port can do what the properties talk about: a
read, a write, a stalled request, and each kind of interrupt taken. For
the timer, it shows a request taken, and one that waits while the timer
counts on.

`formal_nice_pkg` proves the functions that both cores share, for every
input. They are combinational, so a bounded check of depth 1 covers every
value, and the job needs no induction step.
The shift of ISA.md §5.2, written as the loop that repeats n times and run
for counts up to 66, gives what `shift` gives. Beyond that, `shift` gives
for n what it gives for a smaller count that the loop would give the same
for: 33 for a fixed fill, n − 32 for a 32-bit rotation, and n − 33 for a
rotation through C, which checks the digit sum of `mod33`. So the shifter
follows §5.2 for every count. `shift_fast` of `shift_prep`, the pipelined
core's shifter, gives what `shift` gives, also when WRITE prepares the
count in two steps, as it does for a count it must reduce itself. The ALU
with its one adder gives what the operations of ISA.md §5.1 give, written
out one by one with the carry and overflow rules of that section, and
`flags` sets the five flags of §6 and nothing else. The block compares of
MICROARCH.md §5.5 cover their ranges: a word within 16 of FETCH's oldest
word lies in one of the three blocks that WRITE tests, given that the
oldest word moves by at most four words a cycle, which `formal_pipe_fetch`
proves, and a word within 4 of an instruction's address lies in its block
or the next. `tb_shift` checks a sample of the same by simulation. The
table of `mod33` is mapped to logic in the job, which the solver takes in
half the time that it takes the ROM. Boolector proves it in under a
minute; Yices does not finish.

`formal_pipe_fetch` proves FETCH of the pipelined core for
every cycle. Every input is free: every slave, every redirect, and every
DECODE that takes no more words than it is offered. The properties are in
`src/pipe_fetch.vhd` under `G_FORMAL`, because their invariants name its
registers. Memory holds a free but constant value at a free but constant
address (`anyconst`), and any value elsewhere, in every ACK. The
assertions say that whenever DECODE sees that address, it sees that value:
the words come from the addresses that `addr_o` names, also after a
redirect, a redirect to an odd address, and a redirect with requests in
flight, whose words must be dropped. They also say that the words lie in
the range that FETCH's end register closes, which bounds the words the core compares with each store,
and they check the bus port as `wb_master_check` does, but on the
counter of requests in flight. `stop_i` is the halt of `pipeline.vhd`,
and after a cycle of it FETCH makes no new request: a request stays on
the bus only while it is stalled. So a halted pipelined core fetches
nothing from its second cycle on, if the bus does not stall. The range
is at most 16 words, and the oldest word moves by at most four words a
cycle, so its block is the one before `blk_o` or `blk_o` itself, which is
what WRITE's compare with the fetched words relies on (MICROARCH.md
§5.5). The invariants tie that counter, the
requests to drop, the next pair to request, the buffer, and that register to
each other, which makes the assertions inductive in two steps. Boolector
proves them in about a minute; Yices does not finish. Breaking the drop
of stale words, or of an odd address's low word, fails the proof.

`formal_pipe_decode` proves DECODE for every cycle. Every input is free:
the words from FETCH and their count, at most four, PREPARE's ready, and
WRITE's flush. The properties are in `src/pipe_decode.vhd` under
`G_FORMAL`. The assertions are what the proof of PREPARE assumes of
DECODE: a micro-operation is emitted only when PREPARE takes it and no
flush comes; the micro-operations of an instruction come in order, the
first marked first and the last marked last, each with the same
instruction; the instructions emitted since the last flush have
consecutive ids; and the fields of each micro-operation agree with its
instruction word, `next_pc` and the block among them. They also say that
DECODE takes no more words than FETCH offers, and a whole instruction or
nothing, with its constant words in the order dest, s0, s1 (ISA.md
§2.3), and that it redirects FETCH only as it takes `MOVE R15, c` or
`ADD R15, R15, c`, to the target that ISA.md §4.3 gives. The invariants
tie `dec_r`, `dec_q`, and the id counter to the last micro-operation
split off, and `skid_r` to it and to the last one emitted. PREPARE's proof assumes that a new instruction's id differs
from the last one emitted, also across a flush, where DECODE proves
consecutive ids only since the flush; `p_check` in the whole core asserts
what PREPARE relies on, that a new instruction in PREPARE never has the
id of the one in WRITE, which holds because a flush empties WRITE.

`formal_pipe_prepare` proves PREPARE for every cycle. Its inputs are
free, within assumptions that model DECODE and WRITE as far as PREPARE
relies on them: DECODE emits the micro-operations of each instruction in
order, with the fields it decodes agreeing with the instruction word
(`decoded_ok` in `src/pipe_pkg.vhd`, which `pipeline` also asserts in
simulation), WRITE holds what PREPARE moves on while it runs, SR and
WRITE's condition of the instruction change only while WRITE holds a
micro-operation that may change them, and WRITE neither flushes nor takes
an interrupt while PREPARE holds an instruction that has made a data
read. The assertions
say that the read request is held while the bus stalls it, that it never
goes out with `C_MAX_OUT` requests in flight, that a micro-operation makes
all its reads and no more before it moves on unless its condition is
false, that PREPARE never finds the condition false of an instruction
that has made a data read (MICROARCH.md §5.3), and that a read is on the
bus only while the core runs, so that a halted core makes no data read,
and that what PREPARE moves on agrees with its instruction word, which
the proof of WRITE assumes. PREPARE counts a store that
WRITE puts on the bus in the cycle of a read, so that no more than
`C_MAX_OUT` requests are in flight.

`formal_pipe_dbus` proves DBUS for every cycle, with a `wb_master_check`
on its bus port. Requests and read data are numbered in the order the bus
takes them. The solver picks one request and one read datum, of free but
constant numbers, and the datum has a free but constant value. The
assertions say that the request's ACK is taken for a read exactly when it
was one, and that WRITE finds the datum's value wherever DBUS shows that
datum, so the read data come in the order of their ACKs, none lost.  DBUS
drives 0 as the write data of a read, so that it does not change on the
bus while the read is stalled. It also proves PREPARE's assumptions about
DBUS: the count of requests in flight stays in its range, and grows by at
most the one request the bus accepts, and the bus accepts the access that
waits in `st_r` exactly when fewer than `C_MAX_OUT` are in flight and the
bus does not stall.

`formal_pipe_write` proves for every cycle, with every input free, that a
halted WRITE stays halted until reset, and that neither a halted nor a
paused WRITE makes a store or a vector read, takes an interrupt, or
accepts a micro-operation. It also proves that once WRITE leaves
`PAUSED_ST`, it reports a step before it pauses again, whether or not
`paused_o` had risen: it does not pause while `after_go` is 1, and only a
report clears it. And it pauses without `pause_i` only on the breakpoint
flag of the next instruction, in its own micro-operation or, while it
holds none, in PREPARE's, and then stays paused until `pause_i` has been
1. And it takes an interrupt only when one is requested, never in reset,
and never two at once. WRITE's takes are the core's `nmi_ready_o` and
`irq_ready_o`, so these are the assertions of `handshake_check`, for
every cycle and not only in `formal_pipeline`.

`formal_pipe_write` also proves PREPARE's assumptions about WRITE, with
the model registers of PREPARE's proof: while WRITE runs, it holds the
micro-operation PREPARE moved on until it retires it or flushes; SR
changes only while WRITE holds a micro-operation that may change it, or
with a flush, an interrupt entry, or a reset; WRITE's condition likewise,
while it holds an instruction's first micro-operation, or else to the
condition PREPARE found for the one it holds; and WRITE leaves `RUN_ST`
only with a flush, an interrupt entry, or a reset. These are weaker than
what PREPARE's proof assumed before: a micro-operation of two cycles
changes SR and the condition in its first, and WRITE clears only the
valid bit of a micro-operation it drops, and keeps that of INT through
`VEC_ST`. The proof of PREPARE holds with them, with one more invariant.
Its only assumption about PREPARE, that the micro-operation agrees with
its instruction word, is what PREPARE's proof asserts as `f_out_decoded`.

So every assumption of a stage proof is proven of the stage it names, or
checked in the whole core by `p_check` in `src/pipeline.vhd`, on every
simulation and in `formal_pipeline`. DECODE's proof discharges PREPARE's
assumptions about DECODE, and the proofs of WRITE and DBUS most of those
about them, all that need PREPARE's model registers among them. `p_check`
asserts the rest: `f_keep`, `f_keep_read`, `f_accept`, and `f_st_queue`.

`formal_pipeline` puts `core_check` on the pipelined core, with 8 requests
waiting at most on the instruction bus and 4 on the data bus. The core's
own assertions hold there too: those of `pipe_fetch`, and those of its
process `p_check`, among them the data access rule of MICROARCH.md §9,
that no flush leaves read data owed. The properties of DECODE and PREPARE
stay out of it: each is proven for every cycle with free inputs, which
covers everything the whole core can do, so their shadow registers would
add only time to the bounded check, a sixth with DECODE's in a trial. It
also asserts,
through `core_check`, what it asserts of the multi-cycle core about a
halted and a paused core, with `pause_i` free, and about two breakpoints.
Their addresses and enable bits are free, but change only in a reset,
since a change while the core runs may miss an instruction. It also
asserts that no instruction at an enabled breakpoint retires without a
stop first, but as the first step after `pause_i` was 1. The pipeline is too
deep for k-induction without many more invariants, so its `bmc` task
checks only the first 12 cycles after reset. They hold an interrupt
entry, a first store, and a pause, which its cover reaches at step 4, and
a halt and the first step after a pause, which it reaches at step 9. The
rules of a halted core and the report after a pause hold for every cycle
through `formal_pipe_write`. The 12 cycles take 3 minutes with Yosys 0.56
and its ABC, and each further cycle many times more. ABC refuses the
undefined bits that a read out of an index's range gives, which the
simulation never reaches, so the task makes them free in every cycle, as
`wb_dmux.sby` does. The simulation tests check the same assertions on
every run.

`formal_perf` checks the performance counters against a model in the
wrapper: three 64-bit counters, one of every cycle with `run_i` high, one of the cycles
with `instret_i` high, and one of microseconds at a clock of 1.5 MHz, which
the model counts as two in every three cycles, without `perf`'s
accumulator, so that the proof checks its arithmetic, and a snapshot of
each, which a read of its low word takes. It asserts that the port never stalls, that it acknowledges
each request in the next cycle (`wb_slave_check`), and that a read returns the low word of
its counter, the high word of its snapshot, or 0 for a spare word. So a
read of `CYCLE_HI` returns the high word of the counter as it was at the
last read of `CYCLE_LO`, also when the low word wrapped in between, and
writes change nothing. Its `prove` task uses PDR, which finds the
invariant that the counters equal the model, so `perf` needs no
`G_FORMAL`. It takes about half a minute. The `cover` task starts the counters
near a wrap, with `G_RESET`, and shows a read of `CYCLE_HI` after one.

`formal_fetch_stats` connects two fetch statistics to the same inputs,
one with `G_ENABLE` true and one with it false. Both ports never stall
and acknowledge each request in the next cycle (`wb_slave_check`), and every read of the
one without counters returns 0. The other properties are in
`src/fetch_stats.vhd` under `G_FORMAL`, because they name its counters. A
read returns the word as it is in the cycle the read is accepted. A cycle
counted adds one to `FS_CYCLES` and to the bin of its count. Stopped
counters keep their values, a write of 1 to `FS_CTRL` starts them without
a clear, and a clear or a reset clears them. The invariants are that the
bins of `FS_HIST` sum to `FS_CYCLES`, that `FS_MIN` is at most `FS_MAX`
once a cycle has counted, and that `FS_MAX` is at most `FS_HELD_MAX`.
The last needs the one assumption, that the buffer holds no more words
than are held. The sum of 32 counters is too much for the solver in one
step, so ghost counters in a binary tree over the bins count the cycles
of each subtree. The root is asserted to be `FS_CYCLES`, and each node
the sum of its two children, which gives the sum of the bins without
any one assertion adding 32 counters. Boolector proves it all by
k-induction in under a minute; Yices does not finish in 15.

`formal_debug_link` checks the debug link from the host, the program,
the core, and the board, with every input free. It assumes a Wishbone
slave as `wb_master_check` does, and a core whose halt ends only by a
reset, by `hold_o` or by `rst_i`, and a pause that lasts while `pause_o` is
high and the core is not reset. It asserts that the master keeps to the
rules of `wb_master_check` with one access at a time, only while
`hold_o`, `halted_i`, or `paused_i` is high, and never while `clear_o` is high; that
`con_in_valid_o` is high at most one cycle in three, only while the
program ran and `free_i` was not 0 the cycle before; that `clear_o` stays
high until `clear_done_i`; that `tx_valid_o` and `tx_data_o` hold until
the host takes the byte, and a console byte taken is the next one out;
and that `eoi_o` rises only after a break and falls only at a start or
reset. The properties under `G_FORMAL` in `src/debug_link.vhd` name its
registers: `pause_r` is low for exactly one cycle per step, only after a
cycle in which the link owned the paused core, and the link owns nothing
while it steps. A parser of the bytes the host takes asserts that every packet
is whole, a known tag, upper-case hex digits, `#`, and the right
checksum, that a console byte goes out only between packets, and that no
answer starts during a clear. `rx_ready_o` is low only for 2 cycles after
a byte, for the write of a data word, which waits only for the Wishbone
access and never for a clear, and for a tag that waits for an answer or a
clear. `hold_o` and `rom_hide_o` change only on a write to the control
register, at the end of a clear, or at reset, and `pause_o` also at a stop
of the core's own, which it then raises unless the processor is held. With
two breakpoints, their registers change only on a write and at reset, the
entries from `G_BREAKS` up stay 0, and the stop register names one of the
two. Invariants tie the
receiver, the accesses, the sender, and the parser together, so that
k-induction of depth 4 proves it all in a few seconds. `G_TIMEOUT` is 3, so the timeout is reached.
`prove_held` repeats the proof for a system without a ROM that boots
held, where `rom_hide_o` is always 1. The `cover` task shows a write to
the memory, a stalled request, an `h`, an `o`, the `p` of a stop of the
core's own, a console byte for the program, and the end of a clear, within
70 cycles. A read of the memory
needs a whole `R` and the start of its answer, about 90 cycles, so
`wb_master_check` leaves its read cover out with `G_COVER_READ`, and the
simulation tests show the read.

The proof does not cover everything the debug link promises. Console bytes
that the host sends after a halt are dropped (DEBUG.md §1), but
`con_in_valid_o` is asserted only against the hold and the end of the
input, not against `halted_i`, so only `tb_debug_link` checks the drop.
No cover reaches a `p`, a step, or a read of the memory. Contract (e) is
assumed of the core, and not proven of the pipelined core as a whole.

`formal_mpu` checks the bus port of the math unit with a count of the
ACKs owed: at most one, an ACK only when one is owed, STALL high exactly
while a read waits for its ACK, and an ACK in the next cycle for a write
and for a read of an operand or a spare word. The other properties are in
`src/mpu.vhd` under `G_FORMAL`. Shadow operands follow the writes. A
read waits no longer than its unit takes, so every request gets its ACK,
at most 34 cycles after it is accepted for the 32-bit half and 66 for the
64-bit half.
When a read of a result gets its data, the unit has computed it from the
operands as they are then, which a write cannot change while the read
waits. For the products, ghost copies of the operands follow them through
the multiplier's two registers. Neither Yices nor Boolector can compare
two 32-bit multipliers, not even without registers, so the two lemmas
below are proven by hand, and `tb_mpu` checks them on samples. For the
quotients and remainders, each of the four dividers has the loop
invariant of a restoring divider, with ghosts of the quotient bits found,
the dividend bits shifted out, and their product, which the ghosts form
by shift and add. So the solver needs no multiplier, and the proof shows
for every pair of operands that A = M + R with R < B, where M is Q times
B by shift and add, and Q and R of SYSTEM.md §2 for B = 0; for the
signed results, the same on the magnitudes, the signs of SYSTEM.md §2,
and the special case of the most negative number divided by −1; and the
same for C and D. Boolector proves it all by k-induction in about 2
minutes; Yices takes minutes for one divider alone. The covers show a
read that waits for each kind of unit, and reads that wait the longest a
division takes.

The two lemmas, proven by hand:

- **Shift and add multiplies: M = Q × B.** A start clears the ghosts q
  and m of a divider, and a write to the divisor also starts it, so the
  divisor d is the same in every step between two starts. A step that
  finds the quotient bit t sets q to 2q + t and m to 2m + t·d; a skip of
  8 steps sets q to 2⁸q and m to 2⁸m. If m = q·d before a step, then
  after it m = 2q·d + t·d = (2q + t)·d, and after a skip
  m = 2⁸q·d. So m = q·d modulo 2²ᴺ, the width of the ghosts, from the
  start on. After k steps q has k bits, so q < 2ᴺ and q·d < 2²ᴺ, and m
  = q·d exactly. At the end, A = M + R is A = Q·B + R.
- **The signed correction.** For 32-bit words A and B with sign bits a
  and b, the signed values are A − 2³²a and B − 2³²b, and their product
  is A·B − 2³²(a·B + b·A) + 2⁶⁴a·b. Modulo 2⁶⁴ the last term goes, and
  subtracting a multiple of 2³² leaves the low word as it is, so the low
  word of the signed product is that of the unsigned one, and the high
  word is the unsigned high word minus B if a = 1 and minus A if b = 1,
  modulo 2³². That is what `p_multiply` computes from `mul_r`, which is
  A·B by the definition of `*` in `numeric_std_unsigned`.

## The multi-cycle core

`multicycle` runs one step at a time, either one instruction or one interrupt
entry, in the order of ISA.md §5. It is meant to be simple and obviously
right, not fast: an instruction takes about ten cycles.

| State | What it does |
|---|---|
| `BOUNDARY` | Pauses while `pause_i` is 1, takes a pending NMI or IRQ (ISA.md §7.1), stops at a breakpoint, or starts an instruction. |
| `FETCH` | Reads the instruction word, then each constant word, and increments R15 after each. |
| `COND` | Tests the condition, and runs a control instruction. |
| `SRC` | Evaluates s0, then s1, with their side effects. |
| `MOD33` | For `C<C` and `C>C` only, reduces the count mod 33. |
| `EXEC` | Computes the result, writes the destination, and updates the flags. |
| `DEST_ADJ` | For a register destination with mode 001 or 010 only, steps the register after the result. |
| `VEC` | Reads the vector table entry for IRQ, NMI, and `INT`. |
| `RETIRE` | Reports the step on `retire_o`. |
| `FETCH_WAIT`, `SRC_WAIT`, `DEST_WAIT`, `VEC_WAIT` | Wait for the ACK of the read that `FETCH`, `SRC`, or `VEC` issued, or of the store that `EXEC` issued. |
| `PAUSED` | Waits while `pause_i` is 1, and after a breakpoint until `pause_i` has been 1, then goes back to `BOUNDARY` for one step (MICROARCH.md §6.1). |
| `HALTED` | Entered from `RETIRE` when the step halted. Only reset leaves it. |

It has the two Wishbone ports of the memory model: a read-only instruction
bus and a data bus. The instruction bus is 64 bits wide, as MICROARCH.md §1
requires of both cores. The core still reads one word at a time: it reads
the pair that holds the word at R15, and keeps the half that bit 0 of R15
selects. Each access waits for its ACK before the core moves on.
So data accesses are exact and in program order (ISA.md §8.2), and a store
takes effect before the next instruction is fetched, which makes
self-modifying code work.

The registers are flip-flops. Every register write goes through one function
that keeps R0 at 0 and bit 24 of R14 at 1 (ISA.md §4.3). The ALU and the
shifter are in `src/nice_pkg.vhd`. The shifter uses the
closed forms of ISA.md §5.2, and reduces the count mod 33 as MICROARCH.md
§7.3 describes, with a table for the last step. The reduced counts are
registers, set when s1 is known, and the mod 33 one in a state of its own.
That state and `DEST_ADJ` keep slow logic out of `EXEC`, so that the core
reaches 100 MHz on an Artix-7 (xc7a200t-2), at the cost of one more cycle
in a few instructions.

Interrupt requests use valid/ready ports, with an 8-bit vector each. A device
holds `valid` and the vector until the core raises `ready`. The core raises it
for one cycle, in `BOUNDARY`, when it takes the request. `ready` depends
combinationally on `valid`, so a device must not make `valid` depend
combinationally on `ready`.

`halted_o` is 1 once the core has halted and no bus cycle is open: CYC
is 0 on both buses, so every ACK owed has come. Only reset restarts it.
The multi-cycle core has no bus cycle open once it has halted. The
pipelined core may still have requests in flight, and may make one more
in the cycle it halts, so it waits. A system may then take the buses
over, and no late ACK of the core reaches its other master. Until
2026-10-24 the pipelined core's `halted_o` waited only for its last
request, not for the ACKs (doc/HISTORY.md). `tb_core` runs a few cycles
past the end of the trace, so that `p_check` in `src/pipeline.vhd` sees
the core halted.

`halt_reason_o` is the reason of the step that halted the core, a
`t_halt` of `src/trace_pkg.vhd`, while `halted_o` is 1, and `HALT_NONE`
before. A reset clears it. `halt_code` in `trace_pkg` gives its code in
DEBUG.md §6. So a system need not read the reason off `retire_o`.

`pause_i` and `paused_o` are for a debugger (MICROARCH.md §6.1). While
`pause_i` is 1, the core stops at the next step boundary, where it would
take an interrupt, whatever `in_service` and `after_rti` are, and ahead of
an interrupt. `paused_o` is 1 there once no bus cycle is open, as for
`halted_o`. When `pause_i` is 0 while the core is paused, it goes on and
runs one step, which may be an interrupt entry, whatever `pause_i` is
then. So one cycle of `pause_i` = 0 while the core is paused runs exactly one step, and `paused_o`
drops for at least a cycle. A halted core ignores `pause_i`, and
`paused_o` stays 0, so a system that raises `pause_i` waits for `paused_o`
or `halted_o`. `pause_i` must come from a flip-flop, and must not depend
combinationally on the core's outputs. With `pause_i` held at 1 through a
reset, the core pauses before its first step. While the core is paused, a
system may read `regs_o` and write memory: the core fetches from R15
again when it goes on. Both cores have the three ports, with the same
behavior.

Both cores have the breakpoints of DEBUG.md §6 (MICROARCH.md §6.1): the
generic `G_BREAKS`, from 0 to 8, and the ports `brk_addr_i`, a
`t_brk_addrs` of `src/trace_pkg.vhd`, and `brk_en_i`, one bit each, from
flip-flops. Breakpoints from `G_BREAKS` up are ignored. A breakpoint
fires after the checks for a pause and an interrupt, so an interrupt
entry goes first, as in niceemu. It does not depend on `in_service` or
`after_rti`, and the first step after a pause is exempt. The multi-cycle
core compares R15 in `BOUNDARY`. The pipelined core compares the address
of each instruction in DECODE, and pauses on the flag in WRITE, so a
breakpoint written while it runs may miss an instruction that DECODE
holds already (ASSUMPTIONS.md, items 20 to 22). At a breakpoint the core
pauses, and stays paused until `pause_i` has been 1 and is 0 again. So a
system sees `paused_o` rise while `pause_i` is 0, raises `pause_i`, and
then goes on or steps as after any pause. It finds the breakpoint by R15
on `regs_o`. With `G_BREAKS` = 0, the core is the one without
breakpoints.

`regs_o` gives R0 to R15 from the core's registers, for a monitor that
shows them. In the cycle after a step is reported on `retire_o`, they are
the registers of that report. `tb_core` and the formal checks of both
cores' ports check that. `retire_o` is for simulation: in the pipelined
core it comes from WRITE's next state, before the register, so a design
that reads it adds WRITE's longest paths to its own.

In `tb_core`, the generic `G_CYCLE_COUNTER` set to false sends the
two words of the cycle counter to the memory model instead of `perf`, as
`--no-cycle-counter` does in the emulator. The generic `G_INTERRUPTS` takes the emulator's options,
for example `--nmi 2:1 --irq 2:2`. A request for step S is raised once S
steps have retired, as the emulator raises it before step S. A second request
of the same kind merges with one still pending and leaves its vector, as the emulator
merges them.

With the generic `G_PAUSE` = P, `tb_core` raises `pause_i` in a random
P percent of the cycles. With `G_PAUSE_HOLD` = H as well, a pause starts
in P percent of the cycles and is held until the core has paused, then
for a random 0 to H - 1 cycles more, so that interrupt requests come
while the core is paused. With `G_SINGLE_STEP`, it holds `pause_i` at 1
from reset on, lowers it for one cycle each time the core has paused,
and checks that each such pulse runs exactly one step. None of them may
change the trace. With `G_PATCH_STEP` = S as well, `tb_core` writes
`G_PATCH_DATA`, a word in hex, to `G_PATCH_ADDR` through the data bus
while the core is paused after S steps, and hides the write's ACK from
the core. `make test` runs `test/pausepatch.nasm` so, and compares its
trace with the hand-checked `test/pausepatch.expected`, since the
emulator sees no such write. `tb_core` also checks that no bus cycle is
open while `paused_o` or `halted_o` is 1, that the two are never 1 at
once, that `regs_o` does not change while the core is paused, and that
`halt_reason_o` is the reason of the halting step. It also drives `run_i` of the
counters with `not paused_o and not halted_o`, and checks that the cycle counter
counts exactly the cycles after reset in which that is 1.

The generic `G_BREAK_AT` lists the addresses of breakpoints in hex,
between blanks, at most 8. `tb_core` gives the core them all enabled, and
goes on from each stop at one, with `pause_i` 1 for a cycle. With
`G_BREAK_LOG`, it writes `stop` and R0 to R15 in hex to that file at each
stop. `test/break_stops.py` writes the same list for the emulator, from
the `x` notices of its debug link, and `make test` compares the two for
`test/breaks.nasm`. A stop is not a step, so the trace stays the
emulator's.

With the generic `G_INTR_DELAY` = N, each request is raised N cycles
after its step would raise it, and none after the end of the run. The
core may have begun the step already, so the log gives such a request the
step after.

With the generic `G_INTR_LOG`, `tb_core` writes an interrupt log:
`raised S nmi V` when it raises a request after S steps, `accepted nmi`
when the core takes it with `ready`, which takes every request of the kind
raised before, and `taken S nmi V` when the core reports the interrupt
entry as step S, counting from 0. The same goes for `irq`. The timer's
requests are IRQs in the log too: `raised S irq V` when the timer raises
one while none of its own waits, with S its ticks so far, which is the
step the emulator's timer raises it for. `irq_compare.py` runs the
emulator with `--no-timer-irq`, so that the log's requests stand in for
those of its timer, and a core may take a timer request late like any
other. `make test` writes the log for the runs of `timer.nasm` too.

With the generic `G_RETIRE_LOG`, `tb_core` writes a retire log: a line
for each step the core reports, with the cycle it is reported in,
counting from the first cycle after reset, and the address of the
instruction in hex, or `intr` for an interrupt entry. `make -C bench
core` writes it, and `bench/pipecycles.py --retires` compares it with
the cycle model, step by step ([bench/README.md](../bench/README.md#the-cycle-estimate)).

`test/irq_compare.py` reads the log, for a core that may take a request
later than the step it was raised for, as the pipelined core may
(MICROARCH.md §6 and §9). It runs the emulator with each request that the
core took raised for the step where the core took it, and with each
request it never took raised as before, and compares the two runs. Then,
for each request taken, it runs the emulator with the request raised as
it was, stopped `--max-delay` steps (default 0) before the step where the
core took it, and the request must still be pending there. `make test`
runs it after each run with requests, the random programs included, and
`test/irq_sweep.py` after each of its runs. On the multi-cycle core it
agrees with the comparison that uses the steps the requests were raised
for.

With `--read-delay`, the number of steps a request may be late is worked
out for each request taken: the steps right before its interrupt entry
that are instructions with a data read, not skipped. A core that takes a
request at the first instruction boundary after it arrives, unless the
next instruction has already issued a data read (MICROARCH.md §6), passes
this. `test/irq_sweep.py` takes the same option, and then compares the
core's runs only through `irq_compare.py`, and checks the self-check of
`hazard.nasm` on the core's run.

## The pipelined core

`pipeline` is the core of MICROARCH.md, a pipeline of four stages and a
data bus port, each an entity of its own:

| Stage | Where | What it does |
|---|---|---|
| FETCH | `pipe_fetch` | Reads pairs of words ahead on the instruction bus, several requests in flight, into a ring of 16 words. Presents the next four to DECODE. |
| DECODE | `pipe_decode` | Takes one whole instruction, with one more behind it, decodes its fields, and splits it into micro-operations, one per cycle (MICROARCH.md §4), with a skid register for one that PREPARE does not take. Redirects FETCH at once for `MOVE R15, c` and `ADD R15, R15, c` with condition "always", and for a conditional `ADD R15, R15, c` with a negative `c`. |
| PREPARE | `pipe_prepare` | Reads the registers and forms every operand value and address, reduces the shift count, tests the condition when it can, and issues the data reads. |
| WRITE | `pipe_write` | Computes, writes the registers and SR, issues the store, takes interrupts, and runs the control instructions. Its one bypass is the value it wrote last. |
| DBUS | `pipe_dbus` | The data bus port, with the tags and the read data of the requests in flight, and the register from which a store or a vector read goes onto the bus. |

`pipeline` connects the parts.
Each stage holds one item and passes it on when the next stage frees
itself. DECODE keeps a micro-operation that PREPARE does not take in a
skid register, so that its own registers do not wait on PREPARE. Each part keeps its state in registers, but some of the signals
between them are combinational, as each part's header lists: PREPARE
decides on a data read with WRITE's decisions of the same cycle, a flush
reaches every stage at once. Its stores and vector reads go out from a
register in DBUS, a cycle later. In the best case one micro-operation retires each cycle.
`cputest` takes about 1.2 cycles per instruction on memory that never
stalls, and `hazard.nasm`, which is all hazards, 1.9. The benchmark of
[bench/](../bench/README.md) runs like this at commit 98d2bed
(bench/README.md has the multi-cycle core's numbers):

| Program | Instructions | Cycles | Cycles per instruction |
|---|---|---|---|
| `bench.c` through nicewasm | 1652811 | 2357155 | 1.43 |
| `hand.nasm` | 491309 | 1252613 | 2.55 |

The instruction counts equal the emulator's, counted in the phases. In `hand.nasm`, `vm` (5.4
cycles per instruction) ends each handler of three or four instructions
with a jump through a table, whose address PREPARE must wait for, since
the instruction before loads its index, and which flushes the pipeline;
`strings` (2.4) and `bst` (2.0) read the math unit right after writing
its operands.  `make -C bench compare` puts the estimate of
`bench/pipecycles.py` beside these cycles, phase by phase.

WRITE is the only stage that writes registers, and in order. PREPARE
reads them, one stage earlier, and forms the operand values and
addresses. A field that is the register the micro-operation in WRITE
writes takes the value WRITE wrote last, WRITE's one bypass; a field
that needs an adder on it, or a read address, waits a cycle
(ASSUMPTIONS.md, item 1; MICROARCH.md §7.4). Three rare cases take WRITE
two cycles: a destination adjusted by one, a jump to a computed target,
and a shift by a count that PREPARE cannot reduce, such as one from
memory or through an adder, which takes three for a rotation through C
(MICROARCH.md §7.3 and §7.4). `test/bubble.nasm`
measures what a jump costs, with the cycle counter on a memory that never
stalls: 7 cycles over a fall-through for a jump that WRITE resolves,
aligned or not, since its redirect reaches FETCH from a register, 2 for one that DECODE resolves, and one more for an
operation other than `MOVE` into R15. A backward conditional `ADD R15,
R15, offset`, which DECODE predicts taken, costs 2 when taken and 7 when
skipped (MICROARCH.md §5.4). Its read of the counter before the
jump holds the stream up a cycle, which hides one cycle of the early
bubble, 3 in a stream of instructions without reads. It also measures four reads in a
row: WRITE takes read data from DBUS's FIFO, a cycle after its ACK,
unless it only goes into a register (MICROARCH.md §5.3), so four `ADD`s
from memory take 2 cycles more than four `MOVE`s.

The condition is tested once per instruction, in PREPARE if no older
micro-operation may still change SR, otherwise in WRITE. A data read waits
in PREPARE until the core is certain to run its instruction, as
MICROARCH.md §5.3 asks: the condition is true, the older micro-operation
in WRITE cannot jump, halt, or store into fetched code and has issued its
store, no interrupt can be taken first, and every older instruction is
counted on `instret_o`. Stores and vector reads leave from WRITE, through
DBUS's register. The ACKs
come back in order, and at most 4 data requests are in flight, so the
core needs the data bus decoder of `src/wb_dmux.vhd`, which `tb_core`
has.

When the pipelined core halts, `tb_core` prints the cycles from reset, and
those in which a data read waited only for its condition or for an older
micro-operation in WRITE that is not a store: rule 1 or 2 of MICROARCH.md
§5.3. A wait for a store, an interrupt, an operand, or the bus does not
count. It charges each wait to the micro-operation in PREPARE, and adds it
up when that goes on to WRITE or is dropped by a flush or an interrupt:

    Read waits: C cycles; went on: S for the condition, W for an older micro-operation; dropped: S, W

Reading early could save at most the waits that went on. `make core
CORE=pipeline` in `bench/` prints the line for the benchmark
([bench/README.md](../bench/README.md)), and `test/readwait.nasm` checks
it.

WRITE flushes the pipeline after a jump that DECODE did not resolve, after
`RTI`, `INT`, an interrupt entry, and a halt, and after a store into a word
fetched but not retired: the range of words that `pipe_fetch` holds or
will receive, and the instructions in DECODE's and PREPARE's registers
(MICROARCH.md §5.5).

An interrupt is taken in WRITE before an instruction, unless the
instruction has issued a data read. Then it is taken after it. A pause is
taken at the same boundaries, and also inside an interrupt routine and
after `RTI`, ahead of an interrupt. It flushes the pipeline, so that FETCH
waits at R15, and WRITE waits in `PAUSED_ST`. PREPARE issues no first data
read of a new instruction while `pause_i` is 1, but for the first step
after a pause (MICROARCH.md §5.3, rule 4). `instret_o`
counts an instruction in the cycle the bus accepts its last data read, or
when it retires if it reads nothing. So a read of `INSTR_LO` counts every
older instruction and not its own (SYSTEM.md §3).

The core reports each step in the cycle it retires. Its process `p_check`
asserts, in simulation, the invariants that its design relies on.

### Integrating the core

The pipelined core needs more of its system than the multi-cycle core. The
rules are in full in MICROARCH.md §8, and the formal checkers and the header
of `src/pipeline.vhd` rely on them:

- A slave sends its ACK in a later cycle than the one that accepts the
  request, in the order of the requests, only while CYC is high, and only
  for a request the core made. Reset the slaves with the core. The core drops
  CYC in the reset cycle, and an ACK with nothing pending is a range error in
  simulation.
- A store that the data bus accepts in cycle c is seen by an instruction
  fetch accepted in cycle c + 1 or later, so a write buffer may not hold
  a store back past a later fetch.
- Up to 8 instruction requests and 4 data requests are in flight. A slave
  that cannot take more raises STALL.
- A device holds `valid` and the vector until `ready`, and `valid` may not
  depend combinationally on `nmi_ready_o` or `irq_ready_o`, which
  depend combinationally on `valid`.
- `pause_i` comes from a flip-flop, and does not depend combinationally on
  the core's outputs. It feeds the flush, `nmi_ready_o`, and
  `irq_ready_o`, and the core's timing at 100 MHz is tight. A system that
  raises it waits for `paused_o` or `halted_o`.

## The data bus decoder

`wb_dmux` connects the core's data bus, a pipelined Wishbone master, to
`G_SLAVES` slaves. The instantiator decodes the address into `sel_i`, the
index of the slave, so the decoder holds no address map. In `tb_core`,
slave 0 is the memory model, the default slave, then come the math unit,
the performance counters, and the timer. CYC, WE, ADDR, and the write
data go to every slave directly.

The slaves answer at their own pace: the math unit holds the ACK of a read
for up to 65 cycles. So a request to one slave passes only while no other
slave owes an ACK, and otherwise the master sees STALL. All the requests
in flight then go to one slave, which answers them in order, and the ACK
and the read data come back from that slave. The decoder counts the ACKs
owed, up to `G_MAX_PENDING` (default 4), beyond which the master sees
STALL too. A request to another slave waits one cycle after the last ACK
it waits for, because the choice depends only on registers and the select,
not on that cycle's ACK.

STB and STALL pass combinationally, so the decoder adds no cycle of
latency: a store accepted in cycle c reaches the memory in cycle c,
before an instruction fetch accepted in cycle c + 1.

## The debug link

`debug_link` is the part of the debug link of DEBUG.md that needs no FPGA
primitive: a byte stream in and out, with valid and ready, so a board puts
a UART receiver and transmitter on it. Its header lists the ports and what
the board's bus must do for a link access: a link read of the console or
the read counter returns 0 and has no side effect, and a link write is
ignored. It holds the debug registers of §6 itself, takes R0 to R15 and the
halt as inputs, drives `hold_o`, `rom_hide_o`, and `pause_o`, takes
`paused_i`, and asks the board to
clear the memory with `clear_o` and `clear_done_i`. A write with bits 4 and
5 to a paused core is a step: `pause_o` drops for one cycle and rises
again, and the link does not own the memory until the core has paused or
halted again. The board stops the counters and the timer while the core is
paused, and not during a step.

The generic `G_BREAKS`, from 0 to 8, gives the link the breakpoints of
DEBUG.md §6. It holds their enable bits and addresses, and drives them to
the core on `brk_en_o` and `brk_addr_o`, which connect to the core's
`brk_en_i` and `brk_addr_i`, with the same `G_BREAKS` on both. When the
core pauses on its own, with `pause_o` low, the link raises `pause_o`, so
the stop is a pause like any other. At every pause it compares R15 with the
enabled breakpoints, sends `x` with the lowest number that matches, or `p`,
and keeps the number in the stop register until the core goes on, steps, or
starts. A reset clears the breakpoints. A hold, a start, and a clear keep
them.
`formal/debug_link.sby` proves its ports and the guarantees of its
header (The formal checks).

## The memory model

`wb_mem` holds all 2³² words sparsely, as the emulator does, and loads a
`.bin` file (ISA.md §10.4) at time 0. A word never written reads 0.

It has a read-only Wishbone port for the instruction bus and a read-write
port for the data bus. The instruction port is 64 bits wide. Its address a
names the aligned pair of words 2a and 2a + 1, and it returns word 2a in
bits 31..0 and word 2a + 1 in bits 63..32. The data port is 32 bits wide.
Both are pipelined Wishbone slaves that acknowledge each request in the
cycle after they accept it, never later, so a delayed ACK reaches the core
only in the formal jobs, which let a slave answer at any pace. By default they never stall. The generic
`G_STALL` makes each port stall in that percentage of the cycles, at
random, from the seed `G_SEED`, so that the tests check that the core
waits for a request to be accepted. When both ports reach one word in one
cycle, the instruction port reads the old value.

## The console

The I/O range follows ISA.md §8.3. The instruction port reads 0 there. The
console is at `0xFFFFFF00`. A write sends bits 7..0 to the trace writer in
the cycle the write is accepted, and stores nothing. A read returns `0x100`
plus the next byte of the file that the generic `G_INPUT_FILE` names, and
`0x200` after its end, as the emulator's `--input` does. Without the
generic there is no input, and every read returns `0x200`, as for the
emulator with stdin from `/dev/null`. `tb_core` passes its own
`G_INPUT_FILE` on, and `make test` runs the emulator's `input` probe
with `emulator/test/input.txt`.
The read counter is at `0xFFFFFF01`, as in the emulator. A data read returns
the number of data reads of it since the last write, and a write sets that
number. The rest of the I/O range is plain memory, as in the emulator.

## The timer

`timer` holds the timer of SYSTEM.md §4: `TIMER_PERIOD`, `TIMER_COUNT`, and
`TIMER_VECTOR` at offsets 0, 1, and 2. Its bus port is a pipelined Wishbone
slave with a 4-bit address, like that of the performance counters. The bus
decoder selects it for `0xFFFFFF10`–`0xFFFFFF1F`.

It counts down in each cycle with `tick_i` high. A system drives `tick_i`
with "the core is running", so that the timer counts clock cycles and
stops at a halt. `tb_core` connects it to
the core's report of each step, so that it counts as the emulator does.
Its request goes to the core's IRQ port, with the valid/ready handshake of
`src/multicycle.vhd`. It holds `valid` and the vector until `ready`, and a
request raised while one waits merges with it. While no request is raised,
`ready` has no effect, so `ready` may go to more than one device.

## The math unit

`mpu` is the math unit of SYSTEM.md §2. Offsets 0 to 15 hold A, B, and the
signed and unsigned products, quotients, and remainders of A and B.
Offsets 16 to 31 hold the 64-bit C and D, and the signed and unsigned
quotients and remainders of C and D. It is a pipelined Wishbone slave with
a 5-bit address. The bus decoder selects it for `0xFFFFFF20`–`0xFFFFFF3F`
and passes address bits 4..0 as the offset.

A write to A or B starts a computation. A multiplier, which takes two
cycles, and two restoring dividers run side by side: one divider for
A / B, and one for |A| / |B|. Synthesis can map the multiplier to DSP
blocks. A divider computes one quotient bit per cycle, but skips 8 at once
when it can tell that they are all 0, so it takes 33 cycles at most, and
fewer for a small dividend or a large divisor. The signed
results are formed from those, as the header of `src/mpu.vhd` explains. A
write to C or D starts the same computation with two 64-bit dividers,
which takes 65 cycles at most. The two halves run independently.

A read of a result while the unit that computes it runs is accepted, then
STALL stays high and ACK waits until the result is ready. Reads of A, B, and the spare
words, and all writes, are acknowledged in the next cycle. Writes to the
result words and the spare words are ignored. `formal/mpu.sby` proves
the port, the waits, and the quotients and remainders for every pair of
operands, and that a product is never stale; the signed product's
correction is proven by hand, and `tb_mpu` checks the products' values
(The formal checks above).

## The performance counters

`perf` holds the performance counters of SYSTEM.md §3: `CYCLE_LO` and
`CYCLE_HI` at offsets 0 and 1, `INSTR_LO` and `INSTR_HI` at 2 and 3, and
`TIME_LO` and `TIME_HI` at 4 and 5. It
is a pipelined Wishbone slave with a 4-bit address. It never stalls, and it
acknowledges each request in the next cycle. The bus decoder selects it for
`0xFFFFFF40`–`0xFFFFFF4F`.

The cycle counter counts every clock cycle after reset in which `run_i` is
high. The instruction
counter counts the core's `instret_o`, which the multi-cycle core raises for
one cycle in `RETIRE` after each instruction, but not after an interrupt
entry. An instruction makes its data reads before its own `RETIRE`, so a
read of `INSTR_LO` returns the number of instructions before it, as SYSTEM.md
§3 requires. A read of a low word copies its 64-bit counter into a
snapshot, and a read of the high word returns the snapshot's high word.

The microsecond counter counts in the cycles that the cycle counter counts.
An accumulator adds 1000000 in each of them. When the sum reaches the
generic `G_CLK_HZ`, the clock frequency in hertz, the counter counts a
microsecond and the accumulator keeps the sum less `G_CLK_HZ`. So it is
exact at 100 MHz, 90 MHz, or any frequency of 1 MHz or more, with one adder
and no divider. `G_CLK_HZ` defaults to 100 MHz, and a system with another
clock sets it.

The generic `G_RESET` sets the counters' value after reset. It is 0, as
SYSTEM.md §3 requires, except in `tb_perf`, which starts near a wrap.
`formal/perf.sby` proves the port and the reads against a model of the
counters for every cycle, and its cover task starts near a wrap too.

## The fetch statistics

`fetch_stats` holds the fetch statistics of MICROARCH.md §8.1. Its bus
port is a pipelined Wishbone slave with a 6-bit address, bits 5..0 of the
address, so `FS_CTRL` is at offset `0x10` and `FS_HIST` at `0x20`. The bus decoder
selects it for `0xFFFFFF50`–`0xFFFFFF7F`.

It counts the events of a `t_fetch_events` (`src/pipe_pkg.vhd`), which the
pipelined core reports for each cycle on its port `stats_o`. FETCH fills in
the words in its buffer, the room held for the requests in flight, a
request held back for lack of room, a stalled request, and an arriving
pair. DECODE fills in the cycles it waits for words or holds them back,
and the words it takes. `pipeline` adds the jumps that DECODE redirects FETCH for and
the flushes of WRITE. The multi-cycle core has no such port, and `tb_core`
gives the device `C_FETCH_EVENTS_NONE` with it.

A cycle counts only while `run_i` is high, as in `perf`. A system drives it
with "the core is running", so that the counters stop while the core is
held, paused, or halted. It defaults to `'1'`. `tb_core` drives it with
`not paused_o and not halted_o`.

With the generic `G_ENABLE` false there are no counters, and every word
reads 0. `tb_core` passes its generic `G_FETCH_STATS` on to it.
`formal/fetch_stats.sby` proves the port, what each cycle does to the
counters, and the invariants that tie them, with and without `G_ENABLE`.

## The trace writer

The core reports each step in a `t_retire`: one instruction, skipped or not,
or one interrupt entry. A report carries the address, the instruction word,
whether it was skipped, the register values after the step, the memory
write, and the halt reason. The rules the core must keep are in the header of
`src/trace_pkg.vhd`.

The writer prints each step in the emulator's trace format
([emulator/README.md](../emulator/README.md), Trace format). It compares the
register values with those of the step before, so the core reports values,
not register writes. For a skipped instruction it still compares them, with
R15 moved past the instruction, and prints any change, memory write, or
halt after `skipped`. The emulator never prints those there, so a core that
changes anything on a skipped instruction fails the comparison, even on the
last step of a run. Console bytes go into the same file, as they do in the
emulator's output. At a halt, or at the step limit `G_MAX_STEPS`, it prints
the emulator's last lines: the `Halted` or `Stopped` line and the registers.
Then it gives the emulator's exit status: 0 after `HALT`, 2 after the other
halts, and 3 at the step limit.

With `G_TRACE` false, it prints only the console output and the last lines,
like `niceemu` without `--trace`.

After those lines, it prints a `Pending:` line for the interrupt requests
that were never taken, as the emulator does. The testbench gives it the
requests its interrupt source still holds.
