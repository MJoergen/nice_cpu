# hdl

The FPGA implementation of NICE, in VHDL-2008. The design follows
[doc/MICROARCH.md](../doc/MICROARCH.md), and [doc/ISA.md](../doc/ISA.md) is
the specification.

There is no core yet. So far this directory holds the test setup that the
core will be checked with (MICROARCH.md §9): a memory model, a console, and a
trace writer whose output can be compared with `niceemu --trace`.

## Contents

| Path | What it is |
|---|---|
| [src/trace_pkg.vhd](src/trace_pkg.vhd) | `t_retire`, the record in which the core reports each step to the trace writer. |
| [sim/trace.vhd](sim/trace.vhd) | The trace writer. Simulation only. |
| [sim/wb_mem.vhd](sim/wb_mem.vhd) | The memory model, with the console. Simulation only. |
| [test/tb_mem.vhd](test/tb_mem.vhd) | A self-checking test of the memory model, which loads [test/mem.bin](test/mem.bin). |
| [test/tb_trace.vhd](test/tb_trace.vhd) | A test of the trace writer, which stands in for the core and runs [test/trace.asm](test/trace.asm). |

## Running the tests

You need GHDL, Python 3, and Zig 0.15 for the emulator. Tested with
GHDL 6.0.0-dev (mcode backend). The VHDL also runs under nvc.

    cd hdl && make test

`make test` builds the emulator, analyses the VHDL, and runs both tests.
Everything it makes goes in `build/`. `make clean` removes it.

`tb_trace` runs four times, each against the emulator on the same program
with the same NMI: with the full trace, without the trace, and stopped at two
step limits. The output and exit status of each run must match the
emulator's exactly.

## The memory model

`wb_mem` holds all 2³² words sparsely, as the emulator does, and loads a
`.bin` file (ISA.md §10.4) at time 0. A word never written reads 0.

It has a read-only Wishbone port for the instruction bus and a read-write
port for the data bus. Both are pipelined Wishbone slaves that never stall
and acknowledge each request in the next cycle. When both ports reach one
word in one cycle, the instruction port reads the old value.

The I/O range follows ISA.md §8.3. The instruction port reads 0 there. The
console is at `0xFFFFFF00`. A write sends bits 7..0 to the trace writer in
the cycle the write is accepted, and stores nothing, and a read returns 0.
The rest of the I/O range is plain memory, as in the emulator.

## The trace writer

The core reports each step in a `t_retire`: one instruction, skipped or not,
or one interrupt entry. A report carries the address, the instruction word,
whether it was skipped, the register values after the step, the memory
write, and the halt reason. The rules the core must keep are in the header of
`src/trace_pkg.vhd`.

The writer prints each step in the emulator's trace format
([emulator/README.md](../emulator/README.md), Trace format). It compares the
register values with those of the step before, so the core reports values,
not register writes. Console bytes go into the same file, as they do in the
emulator's output. At a halt, or at the step limit `G_MAX_STEPS`, it prints
the emulator's last lines: the `Halted` or `Stopped` line and the registers.
Then it gives the emulator's exit status: 0 after `HALT`, 2 after the other
halts, and 3 at the step limit.

With `G_TRACE` false, it prints only the console output and the last lines,
like `niceemu` without `--trace`.

The emulator also prints a `Pending:` line for interrupt requests that were
never taken. The writer does not, because the testbench has no interrupt
source yet.
