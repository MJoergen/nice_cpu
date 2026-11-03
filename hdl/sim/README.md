# hdl/sim

The parts of the test setup that are for simulation only (MICROARCH.md §9).

| File | What it is |
|---|---|
| [trace.vhd](trace.vhd) | The trace writer. Simulation only. |
| [wb_mem.vhd](wb_mem.vhd) | The memory model, with the console and the read counter. Simulation only. |
| [sd_sim.vhd](sd_sim.vhd) | The SD card engine of `tb_core`: two slots with the images of its generics, held in memory. Simulation only. |
