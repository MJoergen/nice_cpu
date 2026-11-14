# hdl/test

The testbenches, the test programs, and the scripts that run them. [hdl/README.md](../README.md#running-the-tests) says how to run them.

| File | What it is |
|---|---|
| [tb_mem.vhd](tb_mem.vhd) | A self-checking test of the memory model, which loads [mem.bin](mem.bin) and reads [mem.input](mem.input) as its console input. |
| [tb_shift.vhd](tb_shift.vhd) | A self-checking test of the ALU and the shifter of `src/nice_pkg.vhd`: the shifter the pipelined core uses, from a prepared count, against the one the multi-cycle core uses, and the ALU against the operations written out. |
| [tb_mpu.vhd](tb_mpu.vhd) | A self-checking test of the math unit. |
| [tb_fpu.vhd](tb_fpu.vhd) | A test of the FPU, which replays the vectors of `emulator/test/fpu_vectors.py` over its bus. |
| [tb_fpu_unit.vhd](tb_fpu_unit.vhd) | A test of the FPU's arithmetic unit, which replays the vectors of [fpu_unit_vectors.py](fpu_unit_vectors.py). |
| [fpu_unit_vectors.py](fpu_unit_vectors.py) | The vectors of `tb_fpu_unit`, from the model `emulator/test/fpu_model.py`: every operation on every operand or pair of a format of 8 bits, or with `--wide`, random operands of binary64. |
| [tb_perf.vhd](tb_perf.vhd) | A self-checking test of the performance counters. |
| [tb_perf_hz.vhd](tb_perf_hz.vhd) | A self-checking test of the microsecond counter at 33333333, 83333333, and 100000000 Hz, against the integer part of N·10⁶/`G_CLK_HZ`. |
| [tb_tod.vhd](tb_tod.vhd) | A self-checking test of the clock of the time of day, at 2 MHz, so that it counts a microsecond in two cycles. |
| [tb_timer.vhd](tb_timer.vhd) | A self-checking test of the timer. |
| [tb_fetch_stats.vhd](tb_fetch_stats.vhd) | A self-checking test of the fetch statistics. |
| [fstats.nasm](fstats.nasm) | A program that reads the fetch statistics on the pipelined core, and checks itself. |
| [tb_wb_dmux.vhd](tb_wb_dmux.vhd) | A self-checking test of the data bus decoder. |
| [tb_sd_regs.vhd](tb_sd_regs.vhd) | A self-checking test of the SD card controller's registers, with the test as its engine. |
| [tb_net_regs.vhd](tb_net_regs.vhd) | A self-checking test of the network station's registers. |
| [tb_eth_regs.vhd](tb_eth_regs.vhd) | A self-checking test of the port for Ethernet frames, as on a board. |
| [tb_debug_link.vhd](tb_debug_link.vhd) | A self-checking test of the debug link, with the byte streams of DEBUG.md §8 and its errors, notices, timeout, and console; the registers while the core runs; the side client beside the host; the resume of the line's input after a break; and a console byte that waits for room with `rx_flow_i`. |
| [tb_link.vhd](tb_link.vhd) | The debug link connected to a core, the data bus decoder, the memory model, and the math unit, as a board connects them. It loads and runs `test/linkecho.nasm` over the link, from `test/link_init.bin`, and steps it through a break, a resume, and a byte from the new host. |
| [linkecho.nasm](linkecho.nasm) | The program of `tb_link`, loaded over the link. It echoes each console byte, and halts at the end of the input with the number of bytes echoed in R2. |
| [link_init.bin](link_init.bin) | The memory image that `tb_link` starts with, its `G_INIT_FILE`, before the link loads `linkecho.nasm`. |
| [tb_trace.vhd](tb_trace.vhd) | A test of the trace writer, which stands in for the core and runs [trace.nasm](trace.nasm). |
| [tb_core.vhd](tb_core.vhd) | Runs a program on a core, which its generic `G_CORE` names, with an interrupt source, and writes its trace. |
| [shift.nasm](shift.nasm) | Every shift, with the counts that are hard to get right. |
| [irqwave.nasm](irqwave.nasm) | The program of the interrupt timing diagram, doc/interrupt.tex. |
| [addwave.nasm](addwave.nasm) | The program of the timing diagram of one instruction, doc/flow.tex. |
| [instret.nasm](instret.nasm) | Reads of the instruction counter right after a store, after a read, and twice in one instruction. |
| [hazard.nasm](hazard.nasm) | The hazards of MICROARCH.md §5, each with no padding. It checks itself. |
| [programs.py](programs.py) | Runs the programs in some directories on the core and on the emulator, for `make programs`. |
| [core_runs.py](core_runs.py) | Runs a program on the core, or on the emulator, for `irq_sweep.py` and `programs.py`, in GHDL or nvc. |
| [irq_compare.py](irq_compare.py) | Compares a run with interrupt requests against the emulator, from the steps where the core took them. |
| [irq_sweep.py](irq_sweep.py) | Runs a program with an NMI before each of its steps, and with an IRQ before each. |
| [sidefx_prog.py](sidefx_prog.py) | Writes a program with every pair of side effects on one register. |
| [pcfx_prog.py](pcfx_prog.py) | Writes a program with every pair of side effects on R15. |
| [smc_prog.py](smc_prog.py) | Writes a program that stores into its own code 1 to 40 words ahead. |
| [samereg_prog.py](samereg_prog.py) | Writes a program with one register in all three fields of a shift, for every pair of source modes. |
| [latecount.nasm](latecount.nasm) | Every shift count that WRITE reduces in a cycle of its own, and every reader of such a shift's result. |
| [twocycle.nasm](twocycle.nasm) | Register destinations adjusted by one, their readers, and two-cycle jumps. |
| [r15mix.nasm](r15mix.nasm) | R15 in several fields of one instruction, as a shift count, and as a store's base. |
| [r14cond.nasm](r14cond.nasm) | SR written by side effects and adjusted destinations, then conditional instructions and reads; `INT` and `RTI` with conditions. |
| [r0odd.nasm](r0odd.nasm) | R0 in every mode as count, source, and destination. |
| [smclate.nasm](smclate.nasm) | Stores into fetched code from late shifts and two-cycle instructions, and into the constants of early jumps. |
| [smcskid.nasm](smcskid.nasm) | Stores into the target of an early jump while it waits in DECODE, in `dec_r` and in `skid_r`. |
| [predict.nasm](predict.nasm) | Predicted jumps in the shapes of loops: two back to back, flags from the instruction before, stores into the target, into the jump's offset, and into the word after it, and a nested loop. |
| [readorder.nasm](readorder.nasm) | The number and order of the data reads of late shifts, adjusted destinations, and skipped instructions, through the read counter. |
| [instret_late.nasm](instret_late.nasm) | The instruction counter read right after late shifts, adjusted destinations, stores, skipped instructions, and `INT`. |
| [todbus.nasm](todbus.nasm) | Sets and reads the clock of the time of day through `tb_core`'s bus decoder, and reads `READ_LO`, the word after it. It reads only what the emulator and a core have in common. |
| [jumpwords.nasm](jumpwords.nasm) | Jumps into constant words and to the instruction itself, with conditions on I, and backward conditional jumps, which DECODE predicts taken. It ends at a reserved word. |
| [condlate.nasm](condlate.nasm) | Conditional late shifts, adjusted destinations in R14, `HALT` and `INT` right after two-cycle flag writes, and more forms of R15. |
| [irqhazard.nasm](irqhazard.nasm) | Late shifts, adjusted destinations, and side effects on R14 and R15, for a request before each step. |
| [timerwrite.nasm](timerwrite.nasm) | Writes to `TIMER_PERIOD` by instructions with a data read, which the pipelined core counts before their store, and reads of `TIMER_COUNT` after them. |
| [shiftjump.nasm](shiftjump.nasm) | Every shift with R15 as its destination, `0<0` among them, whose opcode is `MOVE`'s. |
| [rtiread.nasm](rtiread.nasm) | `RTI` that returns to instructions with data reads, run one step at a time. |
| [pausepatch.nasm](pausepatch.nasm) | A word of code that `tb_core` writes while the core is paused, with its hand-checked trace in [pausepatch.expected](pausepatch.expected). |
| [breaks.nasm](breaks.nasm) | Stops at breakpoints in a loop, at a data read, at a false condition, in an interrupt routine, after `RTI`, and with an IRQ pending at a jump target and at an instruction that the pipelined core holds already. |
| [watches.nasm](watches.nasm) | Stops at watchpoints: at a read and a write of one word, two reads in one step, a store into the math unit, a jump through a table, and the read of a vector by `INT` and by an IRQ entry. |
| [break_stops.py](break_stops.py) | Lists the stops of a program at its breakpoints and watchpoints on the emulator, over the debug link, as `tb_core` lists the core's. |
| [bubble.nasm](bubble.nasm) | Measures the bubbles of the pipelined core with the cycle counter, and checks itself. |
| [readwait.nasm](readwait.nasm) | Data reads that wait for their condition and for an older micro-operation, which `tb_core` counts on the pipelined core. |
| [random_prog.py](random_prog.py) | Writes random programs, and random interrupt requests for them. |
| [random_stats.py](random_stats.py) | Shows how the random programs spend their steps, and how often they make each hazard. |
| [trace_reads.py](trace_reads.py) | Finds the first line where two traces differ, and shows the data reads of that instruction. |
| [timing_budget.py](timing_budget.py) | Compares the reports of `make timing` with the budget of the unit and the board, and warns at a miss. With `--spread` it gives the least, the median, and the most of each slack over the runs of `make timing-spread`. |
