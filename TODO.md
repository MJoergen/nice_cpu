# TODO

This is the single list of open items for the repository: work not done
yet, questions not decided, claims not checked, and ideas for later. Each
item names where it comes from. Add new items here, not in other files.

Every finding of the reviews in [doc/review/](doc/review/) is closed,
those of [doc/review/repository-review.md](doc/review/repository-review.md)
included. The claims that the repository review of 2026-10-14 left
unchecked were checked on 2026-10-15 (repository-review.md §6.1). No code
has TODO or FIXME comments.

## FPGA core

- **The pipelined core.** FETCH, ICACHE, DECODE, SEQUENCER, PREPARE, and
  WRITE, with micro-operations, as [doc/MICROARCH.md](doc/MICROARCH.md)
  describes. Only the multi-cycle core exists ([hdl/README.md](hdl/README.md)).
- **The system around the core** (MICROARCH.md §8): dual-port RAM, the bus
  decoders, a default slave that reads 0 and drops writes, and the console
  UART at `0xFFFFFF00`, with generics for the memory map. Today
  `hdl/sim/wb_mem.vhd` stands in for all of it, in simulation only, and
  `hdl/test/tb_multicycle.vhd` decodes the math unit and the performance
  counters with an address compare.
- **Synthesis for an FPGA.** Only `ghdl --synth` is run. Vivado has not
  been tried, so size and clock speed are unknown.
- **Formal checks with SymbiYosys** (MICROARCH.md §9): each stage, and the
  data access rule of MICROARCH.md §5.3. None are written.
- **Test order steps not done** (MICROARCH.md §9):
  - Step 4, hazard programs: back-to-back flag use, every pair of side
    effects on one register, R14 and R15 as pointers, stores into the next
    few instructions, and jumps over `HALT`.
  - Step 5 with requests at every point of a hazard program. The
    multi-cycle core passes the interrupt probes with requests at fixed
    steps.
  - Step 6, the runtime and translator test programs on the core. The hdl
    tests do not run them yet, not even on the multi-cycle core.
- **An interrupt comparison script for the pipelined core** (MICROARCH.md
  §9). It reads from the core's trace where each interrupt was taken, and
  runs the emulator with the matching `--irq` or `--nmi` options.

## Example design

- **A MEGA65 example design**, probably in a separate repository
  (MICROARCH.md §10). It sets the generics, adds the board's clocks and
  pins, and may map the screen at `0xFFFF0000` to video RAM.
- **Devices that raise interrupts.** No device raises IRQ or NMI yet, in
  the emulator or in hardware. Only the emulator's `--irq` and `--nmi`
  options and the testbench do ([emulator/README.md](emulator/README.md)).
  A timer would be a natural first one.

## Pipelined core: decide after measuring

- **Register bypasses** instead of stalls (MICROARCH.md §5.1).
- **Speculative reads of RAM** (MICROARCH.md §5.3). Data reads wait until
  the instruction is certain to run, which costs a cycle or two after
  conditional jumps and stores. Allowing speculative reads of RAM, but not
  of the I/O range, needs a change to ISA.md §8.2 and a check of each read
  against older stores.
- **R14 and R15 as operands** take a slow path (MICROARCH.md §5.4). Keep
  it slow unless programs turn out to use them.

## Toolchain

- **A C compiler for NICE.** None targets NICE directly. ISA.md §9.3
  defines the C ABI for one. Until then, C reaches NICE through wasm
  ([README.md](README.md), Compilers).
- **A linker.** There is none. Programs are joined with `cat` and
  assembled at once, so every label is global (ISA.md §9.3).
- **The C library is output only** ([runtime/README.md](runtime/README.md#c-library)).
  Missing: `getchar` and input, which need a console input register with
  a "byte ready" bit, in ISA.md §8.3, the emulator, and the FPGA UART;
  float conversions in `printf`, which would pull in the float library;
  `FILE` and `stdout`; `errno`; and `exit`, which needs a way for wasm
  code to halt.
- **Console and heap support for Zig and Rust.** They can call the C
  library, but that is not the preferred way
  ([runtime/README.md](runtime/README.md#c-library)). Wanted: a Zig module
  with a console writer for `std.fmt`, and a Rust crate with a
  `core::fmt::Write` console, `print!` and `println!`, and a global
  allocator. Both print through `nice.poke`.
- **C's `long double` and `__int128`.** Not supported, because the runtime
  library has no `__addtf3`, `__multi3`, and the like
  ([translator/README.md](translator/README.md)).
- **wasm features nicewasm does not support yet**
  ([translator/README.md](translator/README.md), Supported features):
  function types with more than one result, passive data and element
  segments, `memory.init`, `data.drop`, the table instructions such as
  `table.get` and `table.grow`, `ref.func` outside element segments, the
  tail calls `return_call` and `return_call_indirect`, SIMD, and
  exceptions.
- **Stack overflow** is not detected in translated code, unlike in wasm.
  What happens then is undefined (ISA.md §9.4). An idea: a check against a
  stack limit in each function's prologue, at a cost in code size.
- **Smaller translated code.** An idea from
  [doc/review/wasm-review.md](doc/review/wasm-review.md): keep the top of
  the wasm operand stack in registers. The deferred operands of
  [doc/review/code-size-plan.md](doc/review/code-size-plan.md), and the
  locals in R7–R11 ([translator/README.md](translator/README.md)), already
  took part of that saving. Byte loads and stores still call a helper.

## Decided against

Kept here so that they are not proposed again.

- **Shared trap stubs in nicewasm.** Sharing them would save about 4 words
  for each memory access. But ISA.md §9.4 says R2 holds the address of the
  first NICE instruction of the code that trapped, and a shared stub cannot
  easily know it ([doc/review/code-size-plan.md](doc/review/code-size-plan.md),
  Left as it is).
- **A condition or instruction for signed comparison.** A signed a < b
  takes two instructions, `?V XOR R14, R14, 0x10000000` and then `?N`,
  as ISA.md §9.2 shows and nicewasm does. Michael decided on 2026-10-15
  to keep it that way.
