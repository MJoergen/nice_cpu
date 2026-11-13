# hdl/src

The synthesizable VHDL: the two cores, their shared packages, and the devices. [hdl/README.md](../README.md) describes each.

| File | What it is |
|---|---|
| [multicycle.vhd](multicycle.vhd) | The multi-cycle core. |
| [pipeline.vhd](pipeline.vhd) | The pipelined core: its stages connected, and the invariants they keep. |
| [pipe_fetch.vhd](pipe_fetch.vhd) | FETCH of the pipelined core. |
| [pipe_decode.vhd](pipe_decode.vhd) | DECODE of the pipelined core. |
| [pipe_prepare.vhd](pipe_prepare.vhd) | PREPARE of the pipelined core, with its data read request. |
| [pipe_dbus.vhd](pipe_dbus.vhd) | DBUS, the data bus port of the pipelined core, with the tags and the read data of the requests in flight. |
| [pipe_write.vhd](pipe_write.vhd) | WRITE of the pipelined core, with the architectural state. |
| [pipe_pkg.vhd](pipe_pkg.vhd) | The micro-operations of the pipelined core, what each reads and writes, and WRITE's state record. |
| [nice_pkg.vhd](nice_pkg.vhd) | The parts of the ISA that the cores share: the operand fields, the register value rule, the condition, the ALU, the shifter, and the flags. |
| [mpu.vhd](mpu.vhd) | The math unit of SYSTEM.md §2, a Wishbone slave. |
| [fpu.vhd](fpu.vhd) | The FPU of SYSTEM.md §11, a Wishbone slave: the stack, the views, and the commands, as sequences of operations of `fpu_unit.vhd`. |
| [fpu_pkg.vhd](fpu_pkg.vhd) | The operations of the FPU's arithmetic unit, and the bits of its flags. |
| [fpu_unit.vhd](fpu_unit.vhd) | The arithmetic unit of the FPU of SYSTEM.md §11: one operation at a time, on a binary format whose widths are generics. |
| [perf.vhd](perf.vhd) | The performance counters of SYSTEM.md §3, a Wishbone slave. |
| [tod.vhd](tod.vhd) | The clock of the time of day of SYSTEM.md §10, a Wishbone slave that its own reset, the system's, alone sets to 0. |
| [timer.vhd](timer.vhd) | The timer of SYSTEM.md §4, a Wishbone slave with an interrupt request port. |
| [console_irq.vhd](console_irq.vhd) | The console's receive interrupt of SYSTEM.md §1.9, a Wishbone slave of one word with an interrupt request port, told of the console's input by its system. |
| [irq_merge.vhd](irq_merge.vhd) | The merge of the timer's and the console's IRQ into the core's one IRQ port, the timer's first (SYSTEM.md §4). |
| [sd_regs.vhd](sd_regs.vhd) | The registers and the buffer of the SD card controller of SYSTEM.md §5, a Wishbone slave with a port to a protocol engine. |
| [net_regs.vhd](net_regs.vhd) | The registers of the network station of SYSTEM.md §6, a Wishbone slave with the addresses as outputs and the counts and status as inputs. |
| [eth_regs.vhd](eth_regs.vhd) | The port for Ethernet frames of SYSTEM.md §7: the registers, the queue of 4 frames, and the send buffer, a Wishbone slave with a port to the station. |
| [fetch_stats.vhd](fetch_stats.vhd) | The fetch statistics of MICROARCH.md §8.1, counters of the causes of the pipelined core's cycles and flushes, a Wishbone slave. |
| [wb_dmux.vhd](wb_dmux.vhd) | The data bus decoder, which keeps the ACKs of several slaves in order. |
| [debug_link.vhd](debug_link.vhd) | The byte-stream part of the debug link of DEBUG.md: packets, the debug registers, notices, and a Wishbone master. It returns the core's registers live while the core runs, has a side port for a client inside the system, `rx_resume_i`, which starts the line's input anew after a break, and `rx_flow_i`, with which a console byte waits for room on a transport with flow control. |
| [trace_pkg.vhd](trace_pkg.vhd) | `t_retire`, the record in which the core reports each step to the trace writer, and `t_halt`, the type of the cores' `halt_reason_o`. |
