# hdl

The FPGA implementation of NICE, in VHDL-2008. The design follows
[doc/MICROARCH.md](../doc/MICROARCH.md), and [doc/ISA.md](../doc/ISA.md) is
the specification.

So far this directory holds a simple multi-cycle core, and the test setup
that checks it (MICROARCH.md §9): a memory model, a console, and a trace
writer whose output can be compared with `niceemu --trace`. The pipelined core
of MICROARCH.md is not written yet. The multi-cycle core comes first, as a
working reference for it.

## Contents

| Path | What it is |
|---|---|
| [src/multicycle.vhd](src/multicycle.vhd) | The multi-cycle core. |
| [src/mpu.vhd](src/mpu.vhd) | The math unit of ISA.md §8.4, a Wishbone slave. |
| [src/trace_pkg.vhd](src/trace_pkg.vhd) | `t_retire`, the record in which the core reports each step to the trace writer. |
| [sim/trace.vhd](sim/trace.vhd) | The trace writer. Simulation only. |
| [sim/wb_mem.vhd](sim/wb_mem.vhd) | The memory model, with the console and the read counter. Simulation only. |
| [test/tb_mem.vhd](test/tb_mem.vhd) | A self-checking test of the memory model, which loads [test/mem.bin](test/mem.bin). |
| [test/tb_mpu.vhd](test/tb_mpu.vhd) | A self-checking test of the math unit. |
| [test/tb_trace.vhd](test/tb_trace.vhd) | A test of the trace writer, which stands in for the core and runs [test/trace.asm](test/trace.asm). |
| [test/tb_multicycle.vhd](test/tb_multicycle.vhd) | Runs a program on the multi-cycle core, with an interrupt source, and writes its trace. |
| [test/shift.asm](test/shift.asm) | Every shift, with the counts that are hard to get right. |
| [test/random_prog.py](test/random_prog.py) | Writes random programs, and random interrupt requests for them. |

## Running the tests

You need GHDL, Python 3, and Zig 0.15 for the emulator. Tested with
GHDL 6.0.0-dev and GHDL 4.1.0 (mcode backend). The memory model and the trace
writer also run under nvc.

    cd hdl && make test

`make test` builds the emulator, analyses the VHDL, checks that GHDL can
synthesise the core and the math unit (`ghdl --synth`), and runs the tests. Everything it makes
goes in `build/`. `make clean` removes it.

`tb_mpu` checks every word of the math unit against `numeric_std`: for 20
corner cases and 2000 random pairs of A and B, and for 16 corner cases and
4000 random pairs of C and D. It also checks that a read of a result waits
for the computation, that a write restarts it, that the two halves do not
wait for each other, that a write and a read in back-to-back cycles see
each other in order, and that reset clears the operands.

`tb_trace` runs four times, each against the emulator on the same program
with the same NMI: with the full trace, without the trace, and stopped at two
step limits. The output and exit status of each run must match the
emulator's exactly.

`tb_multicycle` runs these programs on the core. The trace, the output, and
the exit status of each must match those of `niceemu -t` on the same program,
with the same interrupt requests:

- The three 2004 examples `count`, `replicate`, and `print`, and `wrap`, from
  `assembler/test/`.
- The emulator's probes in `emulator/test/`, `cputest` among them, with the
  interrupt options that `emulator/Makefile` gives them. Their memory dumps
  are left out, because the trace lists every memory write. The trace does
  not list data reads, but `reads` counts them with the read counter, so
  its registers show whether the core made each read exactly once and in
  order (ISA.md §8.2). `mpu` and `mpu64` read every word of the math unit.
- `test/shift.asm`.
- `cputest`, `reads`, `mpu`, and `mpu64` again, on a memory that stalls in
  30% of the cycles.
- 30 random programs from `test/random_prog.py`, each stopped at 3000 steps,
  on a memory that stalls in 30% of the cycles. Besides random ALU and
  shift instructions, they use R15 with every side effect, `HALT`, `RTI`,
  `INT`, reserved control words, and the read counter.

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
| `EXEC` | Computes the result, writes the destination, and updates the flags. |
| `VEC` | Reads the vector table entry for IRQ, NMI, and `INT`. |
| `RETIRE` | Reports the step on `retire_o`. |

It has the two Wishbone ports of the memory model: a read-only instruction
bus and a data bus. Each access waits for its ACK before the core moves on.
So data accesses are exact and in program order (ISA.md §8.2), and a store
takes effect before the next instruction is fetched, which makes
self-modifying code work.

The registers are flip-flops. Every register write goes through one function
that keeps R0 at 0 and bit 24 of R14 at 1 (ISA.md §4.3). The shifter uses the
closed forms of ISA.md §5.2, and reduces the count mod 33 as MICROARCH.md
§7.3 describes.

Interrupt requests use valid/ready ports, with an 8-bit vector each. A device
holds `valid` and the vector until the core raises `ready`. The core raises it
for one cycle, in `BOUNDARY`, when it takes the request. `ready` depends
combinationally on `valid`, so a device must not make `valid` depend
combinationally on `ready`.

`halted_o` is 1 once the core has halted. Only reset restarts it.

In `tb_multicycle`, the generic `G_INTERRUPTS` takes the emulator's options,
for example `--nmi 2:1 --irq 2:2`. A request for step S is raised once S
steps have retired, as the emulator raises it before step S. A second request
of the same kind replaces the vector of one still pending, as the emulator
merges them.

## The memory model

`wb_mem` holds all 2³² words sparsely, as the emulator does, and loads a
`.bin` file (ISA.md §10.4) at time 0. A word never written reads 0.

It has a read-only Wishbone port for the instruction bus and a read-write
port for the data bus. Both are pipelined Wishbone slaves that acknowledge
each request in the cycle after they accept it. By default they never
stall. The generic `G_STALL` makes each port stall in that percentage of the
cycles, at random, from the seed `G_SEED`, so that the tests check that the
core waits for a request to be accepted. When both ports reach one word in
one cycle, the instruction port reads the old value.

The I/O range follows ISA.md §8.3. The instruction port reads 0 there. The
console is at `0xFFFFFF00`. A write sends bits 7..0 to the trace writer in
the cycle the write is accepted, and stores nothing, and a read returns 0.
The read counter is at `0xFFFFFF01`, as in the emulator. A data read returns
the number of data reads of it since the last write, and a write sets that
number. The rest of the I/O range is plain memory, as in the emulator.

## The math unit

`mpu` is the math unit of ISA.md §8.4. Offsets 0 to 15 hold A, B, and the
signed and unsigned products, quotients, and remainders of A and B.
Offsets 16 to 31 hold the 64-bit C and D, and the signed and unsigned
quotients and remainders of C and D. It is a pipelined Wishbone slave with
a 5-bit address. The bus decoder selects it for `0xFFFFFF20`–`0xFFFFFF3F`
and passes address bits 4..0 as the offset. In `tb_multicycle`,
that decoder is an address compare on the data bus.

A write to A or B starts a computation that takes 33 cycles. A
shift-and-add multiplier and two restoring dividers run side by side, one
bit per cycle: one divider for A / B, and one for |A| / |B|. The signed
results are formed from those, as the header of `src/mpu.vhd` explains. A
write to C or D starts the same computation with two 64-bit dividers,
which takes 65 cycles. The two halves run independently.

A read of a result while the computation runs is accepted, then STALL stays
high and ACK waits until the result is ready. Reads of A, B, and the spare
words, and all writes, are acknowledged in the next cycle. Writes to the
result words and the spare words are ignored.

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
