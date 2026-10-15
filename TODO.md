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
  First come the next three items, which give it tests that the
  multi-cycle core passes today, so that a failure blames the core and not
  the test, and the bus decoder of the system item. Its instruction port
  is 64 bits wide (MICROARCH.md §3), so `hdl/sim/wb_mem.vhd` needs a
  generic for the width of its instruction port, and `wb_master_check` one
  for the width of the data.
- **A testbench for any core.** `hdl/test/tb_multicycle.vhd` holds the bus
  decoder, the interrupt source, the timer, the trace writer, and the
  watchdog, and names the core. Factor them into one testbench that takes
  the core as a generic, so that the pipelined core runs the same tests
  with one line changed in `hdl/Makefile`.
- **Test order steps not done** (MICROARCH.md §9):
  - Step 4, hazard programs: `hdl/test/hazard.nasm` and
    `hdl/test/sidefx_prog.py`, which the multi-cycle core passes. Left
    out so far: pairs of side effects on R15, which only some cases of
    `hazard.nasm` and the random programs have. `hazard.nasm` tests a
    flag set by a side effect on R14 only for a destination, because a
    source side effect needs VBASE = 0xFFFFFF before the instruction,
    and its vector table would then be in the I/O range.
  - Step 5: `hdl/test/irq_sweep.py` runs `hazard.nasm` with an NMI before
    each step, and with an IRQ before each, and the multi-cycle core
    passes. Not swept: the program of `sidefx_prog.py`, which writes R14
    with any value, so E and VBASE too. For the pipelined core, the sweep
    must vary the cycle at which the request arrives, not the step, and
    needs the comparison script below.
  - Step 6, the runtime and translator test programs on the core. The hdl
    tests do not run them yet, not even on the multi-cycle core. GHDL runs
    the multi-cycle core at about 3300 instructions a second, from the
    times in [bench/README.md](bench/README.md).
- **An interrupt comparison script for the pipelined core** (MICROARCH.md
  §9). It reads from the core's trace where each interrupt was taken, and
  runs the emulator with the matching `--irq` or `--nmi` options. On the
  multi-cycle core it must give the same result as the fixed steps do,
  which checks the script before the pipelined core needs it.
- **The system around the core** (MICROARCH.md §8): dual-port RAM, the bus
  decoders, a default slave that reads 0 and drops writes, and the console
  UART at `0xFFFFFF00`, with generics for the memory map. The data bus
  decoder must keep the ACKs in order when requests to different slaves
  are in flight (MICROARCH.md §8); the pipelined core needs it before the
  rest. The UART must receive too: a read returns the next byte with bit 8
  set, or 0 (ISA.md §8.3). `wb_mem.vhd` always reads `0x200`, as with no
  input. Today
  `hdl/sim/wb_mem.vhd` stands in for all of it, in simulation only, and
  `hdl/test/tb_multicycle.vhd` decodes the math unit and the performance
  counters with an address compare.
- **Formal checks with SymbiYosys** (MICROARCH.md §9): each stage, and the
  data access rule of MICROARCH.md §5.3. So far `make formal` checks only
  the bus and interrupt ports of the multi-cycle core
  ([hdl/README.md](hdl/README.md)).

## Devices

- **An interrupt controller.** The timer (ISA.md §8.6) is the only device
  that raises IRQ, so it drives the core's IRQ port directly. A second
  device needs a controller that merges the requests and says which vector
  goes first. No device raises NMI.

## Pipelined core: after the first version

- **Speculative reads of RAM** (MICROARCH.md §5.3). Data reads wait until
  the instruction is certain to run. The waits are a conditional read
  after a write of SR, 1.1% of the translated benchmark's instructions and
  3.8% of the hand-written one's, and a read after a conditional jump,
  0.9% and 7.6% (MICROARCH.md §5.6). Allowing speculative reads of RAM, but
  not of the I/O range, needs a change to ISA.md §8.2 and a check of each
  read against older stores. Decide once the pipelined core shows what the
  waits cost. The bypasses and the slow path for R14 were decided from the
  same measurements (MICROARCH.md §5.6).

## Toolchain

- **A C compiler for NICE.** None targets NICE directly. ISA.md §9.3
  defines the C ABI for one. Until then, C reaches NICE through wasm
  ([README.md](README.md), Compilers).
- **A linker.** There is none. Programs are joined with `cat` and
  assembled at once, so every label is global (ISA.md §9.3).
- **The C library is small** ([runtime/README.md](runtime/README.md#c-library)).
  Missing: float conversions in `printf` and `scanf`, which would pull in
  the float library; `FILE`, `stdin`, and `stdout`; `errno`; and `exit`,
  which needs a way for wasm code to halt.
- **Heap support for Rust.** `runtime/nice.rs` has the device routines
  and the console ([runtime/README.md](runtime/README.md#zig-and-rust)),
  but no `#[global_allocator]` for `alloc`. Neither it nor `nice.zig` has
  formatted input, as `scanf` gives C.
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
- **Faster and smaller translated code.** From a look at the translated
  test programs on 2026-10-15. The inner loop of
  `translator/test/primes.c`, `composite[j] = 1; j += i`, takes 20
  instructions per iteration: 9 in the byte store helper, 2 to put the
  address in a frame word and reload it, 2 for the bounds check, 3 to pass
  the value and call, and 4 for the increment, compare, and branch. Six of
  the twenty are avoidable, in these ways. The options start in ISA.md
  §9.4, as `--no-bounds-checks` did.
  - *Trust the alignment hint, as an option.* An aligned word access
    costs 9 instructions, 3 of them the test of the address and the
    conditional call of the helper, whose skipped instructions still
    fetch their constant words (ISA.md §3). Clang, Zig, and Rust emit the
    natural alignment unless the source is packed or reads unaligned on
    purpose. With the hint trusted and the base in a register, an aligned
    `i32.load` is 4 instructions and 7 words. The hint is not a promise
    (ISA.md §9.4), so a misaligned access then gives a wrong value, as an
    access out of bounds does without the checks.
  - *The top of the operand stack in R1–R6.* An idea from
    [doc/review/wasm-review.md](doc/review/wasm-review.md). The deferred
    operands of [doc/review/code-size-plan.md](doc/review/code-size-plan.md)
    and the locals in R7–R11 ([translator/README.md](translator/README.md))
    already took part of the saving. In `test/safe.zig`, spills to frame
    words, reloads, and frame-to-frame moves are still 332 of 3596
    instructions, and they are in the hot paths. A value in a register
    would be a further kind of deferred value, written to its frame word
    before a call and at a block boundary.
  - *Flags from the operation before a branch.* `ADD R9, R9, -1`, then
    `MOVE[M] R0, R9` and a conditional jump, is in every counted loop.
    With `ADD[M]` the test goes, as in the `DEC[M]` loop of the intro
    slides. `fuses` in `nicewasm.py` already finds the pattern for
    comparisons.
  - *A constant offset folded into the operand.* `i32.load offset=12`
    costs an `ADD[M]` and a wrap check before the bounds check. With a
    fixed memory cap, one compare of the base against the limit minus the
    offset covers both, and the access is `@___wasm_memory+3[R2]`. Saves 2
    instructions for each field access.
  - *One bounds check for several accesses to the same base in a basic
    block.* Rust code stores to offsets 12, 16, and 20 of one pointer in a
    row, each with its own check of 4 instructions. One check up front,
    with the present sequence kept as the slow path, so that a trap still
    comes in order and with the right R2 (ISA.md §9.4).
  - *No mask for a constant shift count.* `i32.shl` by a constant emits
    `AND R1, 2, 31` and then the shift by R1, where `SHL d, a, 2` would do.
    Every array index computed as `i << 2` pays it. Seen in `bench/`, in
    the translated heapsort. `const_value` in `nicewasm.py` already tells
    whether the count is a constant.
  - *Conditional execution instead of a jump* for an `if` without `else`
    whose body is a few instructions with no call, no memory access, and
    no flag update. Worth more on the pipelined core than on the
    multi-cycle one.

  Out of reach without loop analysis on an intermediate form: `@Rx++` for
  a pointer walk, which needs a word pointer kept in step with the byte
  address, and bounds checks hoisted out of loops. A byte access stays at
  about 9 instructions whatever the translator does, because linear
  memory is byte-addressed (ISA.md §9.4).
- **Benchmarks beyond [bench/](bench/README.md).** Dhrystone 2.1 would
  give a number to compare the core with other small processors, once it
  runs on a board. It needs `malloc`, `strcpy`, `strcmp`, and `printf`
  from the small C library, and `nice_cycles` in place of its clock. A
  subset of Embench-IoT, such as `crc32`, `matmult-int`, `huffbench`, and
  `nettle-sha256`, has published results for small RISC-V and Arm cores,
  but its harness is GPL-3, so it would live outside this repository.
  `bench/` has no float phase, because one would measure the float library
  more than the translator.

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
- **Board synthesis and an example design in this repository.** This
  repository stays FPGA-agnostic. The MEGA65 example design, with its
  synthesis, size, and clock speed, lives in the
  [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
  repository (MICROARCH.md §10).
