# hdl/formal

The formal checks: the checkers of the ports, and a wrapper and a SymbiYosys job for each unit. [hdl/README.md](../README.md#the-formal-checks) says how to run them and what each proves.

| File | What it is |
|---|---|
| [wb_master_check.vhd](wb_master_check.vhd) | Formal properties of a Wishbone master port. |
| [wb_slave_check.vhd](wb_slave_check.vhd) | Formal properties of a Wishbone slave port that never stalls and answers in the next cycle. |
| [handshake_check.vhd](handshake_check.vhd) | Formal properties of a valid/ready port that takes requests. |
| [core_check.vhd](core_check.vhd) | Formal properties of the ports of a core: a checker on each of its four ports, and the rules of a stopped core. |
| [formal_multicycle.vhd](formal_multicycle.vhd) | The multi-cycle core with `core_check`. |
| [multicycle.sby](multicycle.sby) | The SymbiYosys job for it. |
| [formal_timer.vhd](formal_timer.vhd) | The timer with checks of its bus and interrupt ports. |
| [timer.sby](timer.sby) | The SymbiYosys job for it. |
| [formal_wb_dmux.vhd](formal_wb_dmux.vhd) | The data bus decoder with checks of its master and slave ports. |
| [wb_dmux.sby](wb_dmux.sby) | The SymbiYosys job for it. |
| [formal_nice_pkg.vhd](formal_nice_pkg.vhd) | The functions of `src/nice_pkg.vhd` and the block compares of `src/pipe_pkg.vhd`, against ISA.md and MICROARCH.md for every input. |
| [nice_pkg.sby](nice_pkg.sby) | The SymbiYosys job for it. |
| [formal_pipe_fetch.vhd](formal_pipe_fetch.vhd) | FETCH of the pipelined core, whose properties are in `src/pipe_fetch.vhd`. |
| [pipe_fetch.sby](pipe_fetch.sby) | The SymbiYosys job for it. |
| [formal_pipe_decode.vhd](formal_pipe_decode.vhd) | DECODE of the pipelined core, whose properties are in `src/pipe_decode.vhd`. |
| [pipe_decode.sby](pipe_decode.sby) | The SymbiYosys job for it. |
| [formal_pipe_prepare.vhd](formal_pipe_prepare.vhd) | PREPARE of the pipelined core, whose properties are in `src/pipe_prepare.vhd`. |
| [pipe_prepare.sby](pipe_prepare.sby) | The SymbiYosys job for it. |
| [formal_pipe_dbus.vhd](formal_pipe_dbus.vhd) | DBUS of the pipelined core, whose properties are in `src/pipe_dbus.vhd`. |
| [pipe_dbus.sby](pipe_dbus.sby) | The SymbiYosys job for it. |
| [formal_pipe_write.vhd](formal_pipe_write.vhd) | WRITE of the pipelined core, with the properties of its halt, its pause, and its breakpoints, and PREPARE's assumptions about it. |
| [pipe_write.sby](pipe_write.sby) | The SymbiYosys job for it. |
| [formal_pipeline.vhd](formal_pipeline.vhd) | The pipelined core with `core_check`. |
| [pipeline.sby](pipeline.sby) | The SymbiYosys job for it. |
| [formal_perf.vhd](formal_perf.vhd) | The performance counters with checks of their bus port against a model of the counters. |
| [perf.sby](perf.sby) | The SymbiYosys job for it. |
| [formal_fetch_stats.vhd](formal_fetch_stats.vhd) | The fetch statistics, with and without counters, whose properties are in `src/fetch_stats.vhd`. |
| [fetch_stats.sby](fetch_stats.sby) | The SymbiYosys job for it. |
| [formal_mpu.vhd](formal_mpu.vhd) | The math unit with checks of its bus port, whose other properties are in `src/mpu.vhd`. |
| [mpu.sby](mpu.sby) | The SymbiYosys job for it. |
| [formal_debug_link.vhd](formal_debug_link.vhd) | The debug link with checks of its ports, whose other properties are in `src/debug_link.vhd`. |
| [debug_link.sby](debug_link.sby) | The SymbiYosys job for it: the proofs with a free side client, and the covers without one (`cover`) and with one (`cover_side`). |
