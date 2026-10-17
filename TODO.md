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

- **The pipelined core: what is left.** `hdl/src/pipeline.vhd` passes
  every test that the multi-cycle core passes ([hdl/README.md](hdl/README.md)).
  [hdl/ASSUMPTIONS.md](hdl/ASSUMPTIONS.md) lists where it settles or
  departs from [doc/MICROARCH.md](doc/MICROARCH.md). Open:
  - The cost of the waits that MICROARCH.md §5.3 and §5.6 discuss, from
    the pipelined core's cycles for the benchmark (`make core
    CORE=pipeline` in `bench/`), to decide on speculative reads (below).
  - Speed: the core alone reaches about 41 MHz, and NiceMonMEGA65 runs
    it at 33.3 MHz. See the clock items below.
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
    compares with `irq_compare.py --read-delay`, and both cores are swept
    with the request raised up to a few cycles late as well.
  - Step 6: `make programs` in `hdl/` runs the runtime's and the
    translator's test programs on the core, and the multi-cycle core
    passes. Left out: the random modules of `translator/test/fuzz.py`,
    `runtime/libc/test/fuzz_printf.py`, which needs clang, and the
    benchmark, which `make core` in `bench/` runs already.
  - Step 7: `hdl/test/random_prog.py` was tuned with
    `hdl/test/random_stats.py`, and the multi-cycle core passes seeds 1
    to 90. Still weak: a conditional instruction right after a write of
    SR is 10% of the instructions, against 15 to 20% in the benchmark,
    and about half of the runs halt before the step limit, mostly at a
    word that a store changed, or after an interrupt that a write of VBASE
    sent astray. `make random` runs one seed at a time; `programs.py`
    could run them in parallel.
- **The system around the core** (MICROARCH.md §8): dual-port RAM, the bus
  decoders, a default slave that reads 0 and drops writes, and the console
  UART at `0xFFFFFF00`, with generics for the memory map. The data bus
  decoder, which keeps the ACKs in order when requests to different slaves
  are in flight (MICROARCH.md §8), exists: `hdl/src/wb_dmux.vhd`. The
  instruction bus decoder does not. The UART must receive too: a read returns the next byte with bit 8
  set, or 0 (ISA.md §8.3). `wb_mem.vhd` reads a file, as the emulator's
  `--input` does. Today
  `hdl/sim/wb_mem.vhd` stands in for the rest, in simulation only, and
  `hdl/test/tb_core.vhd` computes the data bus decoder's select with an
  address compare.
- **Formal checks with SymbiYosys** (MICROARCH.md §9). `make formal` proves
  the ports of the multi-cycle core, the timer, and the data bus decoder,
  and FETCH of the pipelined core, for every cycle. For the
  whole pipelined core it checks the ports and the core's own assertions,
  the data access rule among them, only for the first 8 cycles after
  reset ([hdl/README.md](hdl/README.md)). FETCH, PREPARE,
  and DBUS are also proved alone, for every cycle. Open: a proof of
  DECODE alone (its handshake with FETCH and PREPARE); WRITE is mostly ISA
  semantics, which the trace diff checks better. A proof of the whole core
  for every cycle, which needs invariants that tie the stages together;
  and the order of the data accesses checked against a model of the
  program, not only through the tests.

## Devices

- **An interrupt controller.** The timer (ISA.md §8.6) is the only device
  that raises IRQ, so it drives the core's IRQ port directly. A second
  device needs a controller that merges the requests and says which vector
  goes first. No device raises NMI.

## Pipelined core: after the first version

- **A faster clock: the lean plan**
  ([doc/review/pipeline-timing.md](doc/review/pipeline-timing.md)). WRITE
  runs four carry chains in series in one cycle: the operand sum, the
  shift count mod 33, the ALU or shifter, and the ± 1 of the
  destination. Stand-ins of the fixes reach about 82 MHz out of context,
  for about 6% more cycles in the translated benchmark and 4% in
  `hand.nasm`. Each step starts in MICROARCH.md:
  1. Register the redirect to FETCH, share one adder in the ALU
     (MICROARCH.md §7.2), and give the ± 1 of a destination a cycle or a
     micro-operation of its own.
  2. Compute `R + c`, `R - 1`, and the store addresses of modes 011, 101,
     and 111 in PREPARE, which waits when WRITE writes the register.
  3. Reduce the shift counts before WRITE (MICROARCH.md §7.3), with one
     more cycle for a count from a register.
- **The store into fetched code limits the clock beyond about 88 MHz**
  (pipeline-timing.md). Its three `in_range` compares feed `flush`, which
  feeds the handshake of PREPARE and FETCH in the same cycle. Open: a
  flush a cycle later, or compares made before WRITE, and what either
  costs in cycles.
- **The clock of the fast-clock plan** (pipeline-timing.md): a shift over
  three cycles and every operand value from PREPARE reach about 99 MHz,
  for 30% more cycles in the translated benchmark. Not planned, since the
  lean plan runs it about as fast. Decide again if the lean plan falls
  short.
- **NiceMonMEGA65 reads the registers from `retire_o.regs`**, which is
  `w_n.regs` of WRITE, before the register. Its worst path ends there. A
  registered copy is enough for nicemon. Fix in NiceMonMEGA65, and say in
  `hdl/src/trace_pkg.vhd` that `retire_o` is for simulation and is slow.
- **An out-of-context timing check in the repository.** The measurements
  of pipeline-timing.md used a Vivado script outside it. Board synthesis
  stays in the example design (below, Decided against), but a script that
  reports the core's worst path would catch regressions. Decide whether
  it belongs in `hdl/`.
- **Count the cycles of the timing fixes in `bench/hazards.py`.** The
  counts of pipeline-timing.md (shifts by a register, operands that the
  previous instruction writes, by mode, and jumps that WRITE takes) came
  from a script outside the repository.

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
