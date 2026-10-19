# hdl

The FPGA implementation of NICE, in VHDL-2008. The design follows
[doc/MICROARCH.md](../doc/MICROARCH.md), and [doc/ISA.md](../doc/ISA.md) is
the specification.

This directory holds two cores, and the test setup that checks them
(MICROARCH.md §9): a memory model, a console, and a trace writer whose
output can be compared with `niceemu --trace`. The pipelined core is the
one of MICROARCH.md. The simple multi-cycle core came first, and is the
working reference for it. [ASSUMPTIONS.md](ASSUMPTIONS.md) lists where the
pipelined core settles a question that MICROARCH.md leaves open, or
departs from it.

## Contents

| Path | What it is |
|---|---|
| [CODING_STYLE.md](CODING_STYLE.md) | The style of the VHDL. |
| [vsg.yml](vsg.yml) | The rules of CODING_STYLE.md for vsg, which `make lint` runs. |
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
| [src/trace_pkg.vhd](src/trace_pkg.vhd) | `t_retire`, the record in which the core reports each step to the trace writer. |
| [sim/trace.vhd](sim/trace.vhd) | The trace writer. Simulation only. |
| [sim/wb_mem.vhd](sim/wb_mem.vhd) | The memory model, with the console and the read counter. Simulation only. |
| [test/tb_mem.vhd](test/tb_mem.vhd) | A self-checking test of the memory model, which loads [test/mem.bin](test/mem.bin) and reads [test/mem.input](test/mem.input) as its console input. |
| [test/tb_shift.vhd](test/tb_shift.vhd) | A self-checking test of the ALU and the shifter of `src/nice_pkg.vhd`: the shifter the pipelined core uses, from a prepared count, against the one the multi-cycle core uses, and the ALU against the operations written out. |
| [test/tb_mpu.vhd](test/tb_mpu.vhd) | A self-checking test of the math unit. |
| [test/tb_perf.vhd](test/tb_perf.vhd) | A self-checking test of the performance counters. |
| [test/tb_timer.vhd](test/tb_timer.vhd) | A self-checking test of the timer. |
| [test/tb_fetch_stats.vhd](test/tb_fetch_stats.vhd) | A self-checking test of the fetch statistics. |
| [test/fstats.nasm](test/fstats.nasm) | A program that reads the fetch statistics on the pipelined core, and checks itself. |
| [test/tb_wb_dmux.vhd](test/tb_wb_dmux.vhd) | A self-checking test of the data bus decoder. |
| [test/tb_trace.vhd](test/tb_trace.vhd) | A test of the trace writer, which stands in for the core and runs [test/trace.nasm](test/trace.nasm). |
| [test/tb_core.vhd](test/tb_core.vhd) | Runs a program on a core, which its generic `G_CORE` names, with an interrupt source, and writes its trace. |
| [test/shift.nasm](test/shift.nasm) | Every shift, with the counts that are hard to get right. |
| [test/irqwave.nasm](test/irqwave.nasm) | The program of the interrupt timing diagram, doc/interrupt.tex. |
| [test/instret.nasm](test/instret.nasm) | Reads of the instruction counter right after a store, after a read, and twice in one instruction. |
| [test/hazard.nasm](test/hazard.nasm) | The hazards of MICROARCH.md §5, each with no padding. It checks itself. |
| [test/programs.py](test/programs.py) | Runs the programs in some directories on the core and on the emulator, for `make programs`. |
| [test/core_runs.py](test/core_runs.py) | Runs a program on the core, or on the emulator, for `irq_sweep.py` and `programs.py`. |
| [test/irq_compare.py](test/irq_compare.py) | Compares a run with interrupt requests against the emulator, from the steps where the core took them. |
| [test/irq_sweep.py](test/irq_sweep.py) | Runs a program with an NMI before each of its steps, and with an IRQ before each. |
| [test/sidefx_prog.py](test/sidefx_prog.py) | Writes a program with every pair of side effects on one register. |
| [test/smc_prog.py](test/smc_prog.py) | Writes a program that stores into its own code 1 to 40 words ahead. |
| [test/random_prog.py](test/random_prog.py) | Writes random programs, and random interrupt requests for them. |
| [test/random_stats.py](test/random_stats.py) | Shows how the random programs spend their steps, and how often they make each hazard. |
| [test/trace_reads.py](test/trace_reads.py) | Finds the first line where two traces differ, and shows the data reads of that instruction. |
| [formal/wb_master_check.vhd](formal/wb_master_check.vhd) | Formal properties of a Wishbone master port. |
| [formal/handshake_check.vhd](formal/handshake_check.vhd) | Formal properties of a valid/ready port that takes requests. |
| [formal/formal_multicycle.vhd](formal/formal_multicycle.vhd) | The multi-cycle core with a checker on each of its four ports. |
| [formal/multicycle.sby](formal/multicycle.sby) | The SymbiYosys job for it. |
| [formal/formal_timer.vhd](formal/formal_timer.vhd) | The timer with checks of its bus and interrupt ports. |
| [formal/timer.sby](formal/timer.sby) | The SymbiYosys job for it. |
| [formal/formal_wb_dmux.vhd](formal/formal_wb_dmux.vhd) | The data bus decoder with checks of its master and slave ports. |
| [formal/wb_dmux.sby](formal/wb_dmux.sby) | The SymbiYosys job for it. |
| [formal/formal_pipe_fetch.vhd](formal/formal_pipe_fetch.vhd) | FETCH of the pipelined core, whose properties are in `src/pipe_fetch.vhd`. |
| [formal/pipe_fetch.sby](formal/pipe_fetch.sby) | The SymbiYosys job for it. |
| [formal/formal_pipe_prepare.vhd](formal/formal_pipe_prepare.vhd) | PREPARE of the pipelined core, whose properties are in `src/pipe_prepare.vhd`. |
| [formal/pipe_prepare.sby](formal/pipe_prepare.sby) | The SymbiYosys job for it. |
| [formal/formal_pipe_dbus.vhd](formal/formal_pipe_dbus.vhd) | DBUS of the pipelined core, whose properties are in `src/pipe_dbus.vhd`. |
| [formal/pipe_dbus.sby](formal/pipe_dbus.sby) | The SymbiYosys job for it. |
| [formal/formal_pipeline.vhd](formal/formal_pipeline.vhd) | The pipelined core with a checker on each of its four ports. |
| [formal/pipeline.sby](formal/pipeline.sby) | The SymbiYosys job for it. |

## Running the tests

You need GHDL, Python 3, and Zig 0.15 for the emulator. Tested with
GHDL 6.0.0-dev and GHDL 4.1.0 (mcode backend). CI installs 4.1.0, the
`ghdl` package of Ubuntu 24.04. The memory model and the trace writer also
run under nvc.

    cd hdl && make test

`make test` builds the emulator, analyses the VHDL, checks that GHDL can
synthesise both cores, the math unit, the performance counters, the timer,
the fetch statistics, and the data bus decoder (`ghdl --synth`), and runs the tests, those of
the cores once for each core. Everything it makes goes in `build/`.
`make clean` removes it.

`make lint` checks the style of every VHDL file against
[CODING_STYLE.md](CODING_STYLE.md), as far as
[vsg](https://vhdl-style-guide.readthedocs.io/) can, with the rules in
[vsg.yml](vsg.yml). It needs `pip install vsg`. It fails on errors and only
warns about lines over 100 columns.

`make timing` runs Vivado on the pipelined core alone, out of context, as
[doc/review/pipeline-timing.md](../doc/review/pipeline-timing.md)
measures it ([timing.tcl](timing.tcl)): synthesis, placement, and routing
for the part of the MEGA65 with a 10 ns clock. It prints the worst
register-to-register path and leaves the 50 worst in `build/timing.rpt`.
It takes about 10 minutes, and `VIVADO` names the executable.

`tb_mpu` checks every word of the math unit against `numeric_std`: for 20
corner cases and 2000 random pairs of A and B, and for 16 corner cases and
4000 random pairs of C and D. It also checks that a read of a result waits
for the computation, exactly as long as it should, that a write restarts
it, that the two halves and the units in each do not wait for each other, that a write and a read in back-to-back cycles see
each other in order, and that reset clears the operands.

`tb_perf` starts the counters just below a wrap of their low words. It
checks that the cycle counter counts every cycle, that the instruction
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

`tb_trace` runs four times, each against the emulator on the same program
with the same NMI: with the full trace, without the trace, and stopped at two
step limits. The output and exit status of each run must match the
emulator's exactly.

`tb_core` runs these programs on the core that its generic `G_CORE` names:
`multicycle` by default, or `pipeline`. Both cores have the same ports,
but for the pipelined core's `stats_o`, and the rest of the testbench
serves them both. `make test` runs them on
each core in `CORES`, both by default, and `make test CORES=pipeline` on
one. `make random` and `make programs` run the core in `CORE`, and pass it
on to `test/irq_sweep.py` and `test/programs.py` with their option
`--core`. The PASS and FAIL lines name the core. The trace, the output,
and the exit status of each must match those of `niceemu -t` on the same
program, with the same interrupt requests. The pipelined core may take a
request later than the emulator (MICROARCH.md §6), so its runs with
requests are compared only by `test/irq_compare.py --read-delay`, below.

- The three 2004 examples `count`, `replicate`, and `print`, and `wrap`, from
  `assembler/test/`.
- The emulator's probes in `emulator/test/`, `cputest` among them, with the
  interrupt options that `emulator/Makefile` gives them. Their memory dumps
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
  interrupt source share the core's IRQ port, with the interrupt source's
  vector when both are raised, as the emulator merges them.
- `test/shift.nasm`.
- `test/irqwave.nasm`, with two IRQs: one that comes before an instruction
  that has not begun, and one that comes just after the next instruction
  has issued its data read, which the pipelined core takes after that
  instruction. Its values are those of the timing diagram
  [doc/interrupt.png](../doc/interrupt.png).
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
  `test/smc_prog.py` writes a program that stores a NOP over a `HALT` 1
  to 40 words ahead, from the next word to beyond FETCH's buffer and its
  requests in flight, so that some store lands in the pair whose fetch
  the bus accepts in the same cycle (MICROARCH.md §5.5): three of its
  forty stores do with no stalls, and two with 30%. It checks itself:
  R12 is 0 at the end only if every `HALT` was passed.
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
  cores; set the number with `-j`. Each worker runs GHDL in its own
  directory under `build/sweep`, because the LLVM and GCC backends of GHDL
  write an executable where they run.
- `cputest`, `reads`, `mpu`, `mpu64`, `perf`, and `timer` again, on a memory that
  stalls in 30% of the cycles.
- On the pipelined core only, `test/fstats.nasm`, also on a memory that
  stalls in 30% of the cycles. It reads the fetch statistics around a
  loop of jumps, and checks what any run must give: the histogram adds up
  to the cycles, `FS_MIN` ≤ `FS_MAX` ≤ `FS_HELD_MAX` ≤ 16, at least one
  jump and flush per round, and cycles in which DECODE waited. The
  emulator has no fetch statistics, so the run is not compared with it:
  it must end with R12 = 0 and exit status 0.
- 30 random programs from `test/random_prog.py`, each stopped at 3000 steps,
  on a memory that stalls in 30% of the cycles. Besides random ALU and
  shift instructions, they use R15 with every side effect, `HALT`, `RTI`,
  `INT`, reserved control words, and the read counter. Most jumps skip
  only a few instructions, sources often read a register that one of the
  last three instructions wrote, and each interrupt vector leads to a
  short routine that ends with `RTI`. A random program may read any address, and now and then one reaches the cycle counter at
  `0xFFFFFF40`, where the core counts cycles and the emulator counts steps
  (SYSTEM.md §3). So these runs make its two words ordinary memory on both
  sides, with the generic `G_CYCLE_COUNTER` and the emulator's
  `--no-cycle-counter`. The instruction counter and the math unit stay,
  because both sides agree on them.

`test/random_stats.py` shows how well the random programs test the core
(MICROARCH.md §9, step 7). It runs a range of seeds on the emulator, as
`make test` does, and reports where the steps run, how much of each
program runs, how many interrupt requests are taken, how the runs end, and
how often they make the hazards of MICROARCH.md §5, beside the benchmark's
shares. With `--generator`, it measures another version of
`random_prog.py`.

`make programs` runs the test programs of the runtime and of the
translator on the core (MICROARCH.md §9, step 6). It is not part of
`make test`, because it takes minutes: about 2 million steps in 196
programs, at GHDL's 3300 steps a second, on all cores. CI runs it on
both. `make test KEEP=DIR`
in `runtime/` and `test/run.py --keep DIR` in `translator/` run their
tests and leave the programs in `build/programs`, with the console input
of those that read one. Then `test/programs.py` runs each on the core and
on the emulator and compares them, as `make test` does, with the console
input on both sides. The runtime's clock reads the cycle counter, so these
runs make its two words memory, as the random programs do.

`make random` runs more random programs, with the seeds, step count, and
stall rate given as variables:

    make random RANDOM_SEEDS="$(seq 31 90)" RANDOM_STALL=60 RANDOM_STEPS=5000

When a run fails, `test/trace_reads.py` helps to see why. It takes the
program and the two traces, replays the emulator's trace to the first
line that differs, and prints the data reads of that instruction, with
the names of the I/O words it knows:

    test/trace_reads.py build/random_65.bin build/random_65.expected build/random_65.out

## The formal checks

`make formal` runs the SymbiYosys jobs in `formal/`. It is not part of
`make test`, because it needs more tools: Yosys with the GHDL plugin,
SymbiYosys, and the solvers Yices 2 and Boolector. Tested with Yosys 0.33,
the plugin and GHDL 4.1.0 of Ubuntu 24.04 (packages `yosys`,
`yosys-plugin-ghdl`, and `ghdl-gcc`, whose libraries the plugin loads),
SymbiYosys at its tag `yosys-0.33`, Yices 2.6.4, and Boolector 3.2.3. CI
installs the same. Boolector is built from source, with the scripts in its
`contrib/` for CaDiCaL and btor2tools: the `boolector` package of Ubuntu
24.04 is version 1.5, which SymbiYosys cannot drive.

`formal_multicycle` connects the multi-cycle core to four checkers. Every
input is free, apart from a reset in the first cycle, so the solver plays
every slave, every interrupt source, and every program. Each checker
assumes the rules of the other side of its port and asserts the core's:

- The instruction bus and the data bus (`wb_master_check`), as pipelined
  Wishbone B4 masters. Generics set the widths of the address and the data,
  so one checker serves both buses. The checker assumes that a slave sends
  ACK only while CYC is high and only for an accepted request. It asserts
  that STB is high only with CYC, that a stalled request is held with WE,
  ADDR, and DATA unchanged, that CYC stays high while a request waits for
  its ACK, that at most one request waits at a time, and that reset drops
  CYC and STB.
- The NMI and IRQ ports (`handshake_check`), with the AXI handshake. The
  checker assumes that a device holds `valid` and the vector until `ready`.
  It asserts that the core raises `ready` only for a request, and never in
  reset.

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
device, and that the bus port acknowledges each request in the next cycle
and never stalls.

The `prove` task proves the assertions for every cycle by k-induction. The
induction needs invariants that tie the ports to the core's state: the state
is one of its 12 values, and each bus has CYC high exactly in its wait
states. The core asserts them itself when its generic `G_FORMAL` is true;
`formal_multicycle` sets it, and the other users leave it false. The
`cover` task shows that each port can do what the properties talk about: a
read, a write, a stalled request, and each kind of interrupt taken. For
the timer, it shows a request taken, and one that waits while the timer
counts on.

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
the range that `end_o` closes, which the core compares with each store,
and they check the bus port as `wb_master_check` does, but on the
counter of requests in flight. The invariants tie that counter, the
requests to drop, the next pair to request, the buffer, and `end_o` to
each other, which makes the assertions inductive in one step. Boolector
proves them in about a minute; Yices does not finish. Breaking the drop
of stale words, or of an odd address's low word, fails the proof.

`formal_pipe_prepare` proves PREPARE for every cycle. Its inputs are
free, within assumptions that model DECODE and WRITE as far as PREPARE
relies on them: DECODE emits the micro-operations of each instruction in
order, with the fields it decodes agreeing with the instruction word
(`decoded_ok` in `src/pipe_pkg.vhd`, which `pipeline` also asserts in
simulation), WRITE takes what PREPARE moves on, SR and WRITE's condition of the
instruction change only when WRITE retires a micro-operation that may
change them, and WRITE neither flushes nor takes an interrupt while
PREPARE holds an instruction that has made a data read. The assertions
say that the read request is held while the bus stalls it, that it never
goes out with `C_MAX_OUT` requests in flight, that a micro-operation makes
all its reads and no more before it moves on unless its condition is
false, and that PREPARE never finds the condition false of an instruction
that has made a data read (MICROARCH.md §5.3).  PREPARE counts a store that
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
bus while the read is stalled.

The assumptions of each proof that name another stage are checked in the
whole core by `p_check` in `src/pipeline.vhd`, on every simulation and in
`formal_pipeline`.

`formal_pipeline` puts the four checkers on the pipelined core, with
`G_MAX_PENDING` 8 on the instruction bus and 4 on the data bus. The core's
own assertions hold there too: those of `pipe_fetch`, and those of its
process `p_check`, among them the data access rule of MICROARCH.md §9,
that no flush leaves read data owed. The pipeline is too deep for
k-induction without many more invariants, so its `bmc` task checks only
the first 8 cycles after reset, which hold an interrupt entry and a first
store, as its covers show. A 9th cycle did not finish in 20 minutes. The
simulation tests check the same assertions on every run.

## The multi-cycle core

`multicycle` runs one step at a time, either one instruction or one interrupt
entry, in the order of ISA.md §5. It is meant to be simple and obviously
right, not fast: an instruction takes about ten cycles.

| State | What it does |
|---|---|
| `BOUNDARY` | Takes a pending NMI or IRQ (ISA.md §7.1), or starts an instruction. |
| `FETCH` | Reads the instruction word, then each constant word, and increments R15 after each. |
| `COND` | Tests the condition, and runs a control instruction. |
| `SRC` | Evaluates s0, then s1, with their side effects. |
| `MOD33` | For `C<C` and `C>C` only, reduces the count mod 33. |
| `EXEC` | Computes the result, writes the destination, and updates the flags. |
| `DEST_ADJ` | For a register destination with mode 001 or 010 only, steps the register after the result. |
| `VEC` | Reads the vector table entry for IRQ, NMI, and `INT`. |
| `RETIRE` | Reports the step on `retire_o`. |

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

`halted_o` is 1 once the core has halted. Only reset restarts it.

In `tb_core`, the generic `G_CYCLE_COUNTER` set to false sends the
two words of the cycle counter to the memory model instead of `perf`, as
`--no-cycle-counter` does in the emulator. The generic `G_INTERRUPTS` takes the emulator's options,
for example `--nmi 2:1 --irq 2:2`. A request for step S is raised once S
steps have retired, as the emulator raises it before step S. A second request
of the same kind replaces the vector of one still pending, as the emulator
merges them.

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
| DECODE | `pipe_decode` | Takes one whole instruction, with one more behind it, decodes its fields, and splits it into micro-operations, one per cycle (MICROARCH.md §4). Redirects FETCH at once for `MOVE R15, c` and `ADD R15, R15, c` with condition "always". |
| PREPARE | `pipe_prepare` | Reads the registers and forms every operand value and address, reduces the shift count, tests the condition when it can, and issues the data reads. |
| WRITE | `pipe_write` | Computes, writes the registers and SR, issues the store, takes interrupts, and runs the control instructions. Its one bypass is the value it wrote last. |
| DBUS | `pipe_dbus` | The data bus port, with the tags and the read data of the requests in flight. |

`pipeline` connects the parts.
Each stage holds one item and passes it on when the next stage frees
itself. Each part keeps its state in registers, but some of the signals
between them are combinational, as each part's header lists: PREPARE
decides on a data read with WRITE's decisions of the same cycle, a flush
reaches every stage at once, and WRITE drives its stores onto the bus. In the best case one micro-operation retires each cycle.
`cputest` takes about 1.2 cycles per instruction on memory that never
stalls, and `hazard.nasm`, which is all hazards, 1.9. The benchmark of
[bench/](../bench/README.md) runs like this, against the
multi-cycle core's numbers there:

| Program | Instructions | Cycles | Cycles per instruction | Multi-cycle core |
|---|---|---|---|---|
| `bench.c` through nicewasm | 1730635 | 2275410 | 1.31 | 11.3, 8.6 times slower |
| `hand.nasm` | 491617 | 1216653 | 2.47 | 11.4, 4.6 times slower |

The instruction counts equal the emulator's. In `hand.nasm`, `vm` (4.5
cycles per instruction) ends each handler of three or four instructions
with a jump through a table, whose address PREPARE must wait for, since
the instruction before loads its index, and which flushes the pipeline;
`strings` (2.9) and `bst` (2.3) read the math unit right after writing
its operands.  `make -C bench compare` puts the estimate of
`bench/pipecycles.py` beside these cycles, phase by phase.

WRITE is the only stage that writes registers, and in order. PREPARE
reads them, one stage earlier, and forms the operand values and
addresses. A field that is the register the micro-operation in WRITE
writes takes the value WRITE wrote last, WRITE's one bypass; a field
that needs an adder on it, or a read address, waits a cycle
(ASSUMPTIONS.md, item 1; MICROARCH.md §7.4). Three rare cases take WRITE
two cycles: a destination adjusted by one, a jump to a computed target,
and a shift by a count from memory (MICROARCH.md §7.4).

The condition is tested once per instruction, in PREPARE if no older
micro-operation may still change SR, otherwise in WRITE. A data read waits
in PREPARE until the core is certain to run its instruction, as
MICROARCH.md §5.3 asks: the condition is true, the older micro-operation
in WRITE cannot jump, halt, or store into fetched code and has issued its
store, no interrupt can be taken first, and every older instruction is
counted on `instret_o`. Stores and vector reads leave from WRITE. The ACKs
come back in order, and at most 4 data requests are in flight, so the
core needs the data bus decoder of `src/wb_dmux.vhd`, which `tb_core`
has.

WRITE flushes the pipeline after a jump that DECODE did not resolve, after
`RTI`, `INT`, an interrupt entry, and a halt, and after a store into a word
fetched but not retired: the range of words that `pipe_fetch` holds or
will receive, and the instructions in DECODE's and PREPARE's registers
(MICROARCH.md §5.5).

An interrupt is taken in WRITE before an instruction, unless the
instruction has issued a data read. Then it is taken after it. `instret_o`
counts an instruction in the cycle the bus accepts its last data read, or
when it retires if it reads nothing. So a read of `INSTR_LO` counts every
older instruction and not its own (SYSTEM.md §3).

The core reports each step in the cycle it retires. Its process `p_check`
asserts, in simulation, the invariants that its design relies on.

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

## The memory model

`wb_mem` holds all 2³² words sparsely, as the emulator does, and loads a
`.bin` file (ISA.md §10.4) at time 0. A word never written reads 0.

It has a read-only Wishbone port for the instruction bus and a read-write
port for the data bus. The instruction port is 64 bits wide. Its address a
names the aligned pair of words 2a and 2a + 1, and it returns word 2a in
bits 31..0 and word 2a + 1 in bits 63..32. The data port is 32 bits wide.
Both are pipelined Wishbone slaves that acknowledge each request in the
cycle after they accept it. By default they never stall. The generic
`G_STALL` makes each port stall in that percentage of the cycles, at
random, from the seed `G_SEED`, so that the tests check that the core
waits for a request to be accepted. When both ports reach one word in one
cycle, the instruction port reads the old value.

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
result words and the spare words are ignored.

## The performance counters

`perf` holds the performance counters of SYSTEM.md §3: `CYCLE_LO` and
`CYCLE_HI` at offsets 0 and 1, and `INSTR_LO` and `INSTR_HI` at 2 and 3. It
is a pipelined Wishbone slave with a 4-bit address. It never stalls, and it
acknowledges each request in the next cycle. The bus decoder selects it for
`0xFFFFFF40`–`0xFFFFFF4F`.

The cycle counter counts every clock cycle after reset. The instruction
counter counts the core's `instret_o`, which the multi-cycle core raises for
one cycle in `RETIRE` after each instruction, but not after an interrupt
entry. An instruction makes its data reads before its own `RETIRE`, so a
read of `INSTR_LO` returns the number of instructions before it, as SYSTEM.md
§3 requires. A read of a low word copies its 64-bit counter into a
snapshot, and a read of the high word returns the snapshot's high word.

The generic `G_RESET` sets the counters' value after reset. It is 0, as
SYSTEM.md §3 requires, except in `tb_perf`, which starts near a wrap.

## The timer

`timer` holds the timer of SYSTEM.md §4: `TIMER_PERIOD`, `TIMER_COUNT`, and
`TIMER_VECTOR` at offsets 0, 1, and 2. Its bus port is a pipelined Wishbone
slave with a 4-bit address, like that of the performance counters. The bus
decoder selects it for `0xFFFFFF10`–`0xFFFFFF1F`.

It counts down in each cycle with `tick_i` high. A system ties `tick_i` to
`'1'`, so that the timer counts clock cycles. `tb_core` connects it to
the core's report of each step, so that it counts as the emulator does.
Its request goes to the core's IRQ port, with the valid/ready handshake of
`src/multicycle.vhd`. It holds `valid` and the vector until `ready`, and a
request raised while one waits merges with it. While no request is raised,
`ready` has no effect, so `ready` may go to more than one device.

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
and the words it takes. `pipeline` adds the jumps that DECODE resolves and
the flushes of WRITE. The multi-cycle core has no such port, and `tb_core`
gives the device `C_FETCH_EVENTS_NONE` with it.

With the generic `G_ENABLE` false there are no counters, and every word
reads 0. `tb_core` passes its generic `G_FETCH_STATS` on to it.

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
