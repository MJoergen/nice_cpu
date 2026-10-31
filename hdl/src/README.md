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
| [perf.vhd](perf.vhd) | The performance counters of SYSTEM.md §3, a Wishbone slave. |
| [timer.vhd](timer.vhd) | The timer of SYSTEM.md §4, a Wishbone slave with an interrupt request port. |
| [fetch_stats.vhd](fetch_stats.vhd) | The fetch statistics of MICROARCH.md §8.1, counters of FETCH and DECODE of the pipelined core, a Wishbone slave. |
| [wb_dmux.vhd](wb_dmux.vhd) | The data bus decoder, which keeps the ACKs of several slaves in order. |
| [debug_link.vhd](debug_link.vhd) | The byte-stream part of the debug link of DEBUG.md: packets, the debug registers, notices, and a Wishbone master. It returns the core's registers live while the core runs, has a side port for a client inside the system, and `rx_resume_i`, which starts the line's input anew after a break. |
| [trace_pkg.vhd](trace_pkg.vhd) | `t_retire`, the record in which the core reports each step to the trace writer, and `t_halt`, the type of the cores' `halt_reason_o`. |
