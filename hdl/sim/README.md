# hdl/sim

The parts of the test setup that are for simulation only (MICROARCH.md §9).

| File | What it is |
|---|---|
| [trace.vhd](trace.vhd) | The trace writer. Simulation only. |
| [wb_mem.vhd](wb_mem.vhd) | The memory model, with the console, the read counter, and the byte windows of DEVICES.md §9. Simulation only. |
| [sd_sim.vhd](sd_sim.vhd) | The SD card engine of `tb_core`: two slots with the images of its generics, held in memory. Simulation only. |
| [eth_sim.vhd](eth_sim.vhd) | The station of `tb_core`'s port for Ethernet frames: the frames of a file in, the frames sent to a file, and ARP and ping answered, as the emulator's `--eth-in` and `--eth-out`. Simulation only. |
