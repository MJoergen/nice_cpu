# TODO

This is the single list of open items for the repository: work not done
yet, questions not decided, claims not checked, and ideas for later. Each
item names where it comes from. Add new items here, not in other files.

Every finding of the reviews in [doc/review/](doc/review/) before
2026-10-19 is closed, those of
[doc/review/repository-review.md](doc/review/repository-review.md)
included. The open findings of the review of 2026-10-19 are the first
section below. The claims that the repository review of 2026-10-14 left
unchecked were checked on 2026-10-15 (repository-review.md §6.1). No code
has TODO or FIXME comments.

## Findings of the review of 2026-10-19

The open items of
[doc/review/second-repository-review.md](doc/review/second-repository-review.md),
added 2026-10-19. The section numbers are its.

- **The cycle model's counter address and math unit** (§3.1, §3.2).
  `bench/pipecycles.py` looks for `INSTR_LO` at `0xFFFFFF12`, which has
  been `TIMER_VECTOR` since the swap of 2026-10-17, so `make cycles` and
  `make profile` print no phase rows. It also holds every result of the
  math unit for 35 cycles, where the multiplier has taken 2 since
  2026-10-16 and the dividers skip runs of zero quotient bits. Fix the
  address, add a test that expects the phase rows of `bench.bin`, give
  the model the new math unit, and compare it with `make core
  CORE=pipeline` again (§3.3): today it is within 12% of the core on each
  phase of the translated benchmark, but 3.4 times too high on `rng64`
  of `hand.nasm`.
- **The tables of 2026-10-16** in `bench/README.md` and `hdl/README.md`
  pair the pipelined core's run of the old translator output with the
  multi-cycle core's run of the new. §3.4 has the numbers of 2026-10-19.
- **Documents that fell behind the pipelined core** (§2): README.md, the
  slides and `nice_intro.pdf`, `bench/README.md`, and the docstring of
  `pipecycles.py` say it is not written (§2.1); MICROARCH.md §8 describes
  the memory system as if it existed, §9 and ASSUMPTIONS.md item 14 do
  not know of the PREPARE and DBUS proofs, and §7.3 says PREPARE can
  reduce the shift count (§2.2, §2.3); hdl/README.md lost its `## The
  trace writer` heading (§2.4); the test order steps below say the
  multi-cycle core passes where both do (§2.5); ISA.md §8.3 says the
  simulation memory has no input (§2.6); CLAUDE.md's `make formal` line,
  REFERENCES.md without pipeline-timing.md, and the timer's range in the
  usage text of `main.zig` (§2.7).
- **CI runs `make programs` on the multi-cycle core only** (§4.1). The
  pipelined core passed all 350 programs on 2026-10-19, by hand.
- **The translator** (§5): the rules of commits fa3a8a7, 2e77769, and
  3e0a2c1 have no test, since no module reaches their shape; a test of
  the passes on hand-built instruction lists would (§5.2). `fuzz.py`
  checks neither traps, nor R7 to R13, nor the console, nor more than 18
  memory words, and runs the default options only; the review's
  differential check against the translator of 88276db did, on 1300
  modules, and found nothing (§5.3). The README says `test/safe.zig` is
  about 7100 words, where it is 5182, lists `i32.mul` among the results
  that go straight to a local, which the math unit path does not forward,
  and omits the second form of `invert_back_edges` (§5.4).
- **The emulator** (§6): `--input` with a directory runs as an ended
  input and exits 0, with no `errors.py` case; the README still says "No
  device raises IRQ or NMI yet"; the timer's "keeps its vector" rule has
  no test of its own; `--input -` is undocumented; and a comment in
  `cpu.zig` says a console read without input returns 0, where the code
  reads memory.

## FPGA core

- **The pipelined core: what is left.** `hdl/src/pipeline.vhd` passes
  every test that the multi-cycle core passes ([hdl/README.md](hdl/README.md)).
  [hdl/ASSUMPTIONS.md](hdl/ASSUMPTIONS.md) lists where it settles or
  departs from [doc/MICROARCH.md](doc/MICROARCH.md). Open:
  - The cost of the waits that MICROARCH.md §5.3 and §5.6 discuss, from
    the pipelined core's cycles for the benchmark (`make core
    CORE=pipeline` in `bench/`), to decide on speculative reads (below).
  - Speed: the core alone reaches about 49 MHz out of context (Vivado
    2025.1, 2026-10-19), up from about 39 MHz before the faster mod 33 and
    rotation in `nice_pkg`. NiceMonMEGA65 runs it at 33.3 MHz. See the
    clock items below.
- **Test order steps not done** (MICROARCH.md §9):
  - Step 4, hazard programs: `hdl/test/hazard.nasm`,
    `hdl/test/sidefx_prog.py`, and `hdl/test/smc_prog.py`, which the
    multi-cycle core passes. Left
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
- **Faster and smaller translated code.** The list from a look at the
  translated test programs on 2026-10-15 was done from 2026-10-16 to
  2026-10-19 ([translator/README.md](translator/README.md), How functions
  are translated): a register allocator in place of frame words, inline
  memory accesses with one compare for the bounds and the alignment, a
  constant offset in the word operand, one compare for a group of
  accesses, no compare for an index with a known bound, flags from the
  operation before a branch, no mask for a constant shift count,
  conditional instructions in place of short jumps, and multiplications
  and divisions by constants. `bench/` went from 3359061 to 1729523
  instructions, against 491617 for `hand.nasm`, and from about 5.55 to
  about 2.27 million cycles by `bench/pipecycles.py`, an estimate for
  the pipelined core of MICROARCH.md. Trusting the alignment hint would
  save nothing now, as one compare covers the bounds and the alignment.
  What is left, by the estimate:
  - *Taken jumps resolved in WRITE*, about a third of the cycles above
    one per instruction: the interpreter's table jumps, which no layout
    avoids, and `br_if`s whose common path is the taken one. nicewasm
    guesses that the shorter arm of a diamond is the rarer one; branch
    probabilities from a profile would do better.
  - *Waits on the math unit*, about a quarter: the interpreter's `MUL`,
    `__mul64` in `runtime/`, and `% 26` in strings read the result right
    after writing the operands. Hiding the 35 cycles needs independent
    work in between, which the translator rarely has without moving
    stores past loads. `__mul64` could overlap its partial products. The quarter is the model's figure with a
    35-cycle multiplier, which the math unit no longer has
    (second-repository-review.md §3.2).
  - *A read right after a skipped bounds-check jump*, about a tenth, in
    chains of dependent loads, where no instruction can fill the slot.
    Speculative reads (above) would remove it.
  - *The address register written by the instruction before*, about a
    tenth, in the inline byte loads, whose two address registers are both
    computed just before the read. A different byte-load sequence would
    be needed. MICROARCH.md §5 could state this stall in so many words;
    §3 implies it.
  - *Loop back edges* cost the two cycles of an early redirect each round.
  - *`@Rx++` for a pointer walk*, as `hand.nasm` does, needs a word
    pointer kept in step with the byte address, which is out of reach
    without loop analysis on an intermediate form.
  - *Range analysis* beyond the bounds nicewasm keeps (masks, byte loads,
    shifts, and remainders), to drop the bounds checks of counted loops.
  - ISA.md §9.4 could say where a trap's R2 points when nicewasm copies
    or moves code: at the first instruction of the original copy, and
    the code of a neighbouring access may lie between that instruction
    and the rest of the trapping instruction's code.
  - MICROARCH.md §5.6's table of 2026-10-15 predates these changes. A read
    after a conditional jump is now in most inline memory accesses, so
    speculative reads (above) matter more; `make -C bench hazards` gives
    the new shares.
  - *Two guesses that could become options.* The shorter arm of a diamond
    is taken for the rarer one, which cost 2500 cycles in `strstr`, where
    the short arm is the inner loop, and saved 51000 in heapsort. A group
    of accesses may share a compare if the copy of the slow path costs at
    most 20 words for each compare saved in a loop, twice that in two
    loops, and nothing outside loops (`SHARE_COST`, `SHARE_CHECKS` in
    `nicewasm.py`); 16 words loses the vm's groups, and 32 instructions
    between the accesses saves 2000 cycles for 3% more code in
    `test/safe.zig`. A profile, or a flag, would decide better than a
    constant.
  - *What `fuzz.py` cannot check.* Its model does not know a trap's code
    or R2, so every access it generates is in bounds, and the trap paths
    are tested by `run.py` only. The reviews of the 2026-10-19 work used
    a differential fuzzer instead, which runs two versions of nicewasm on
    the same random programs and compares R1, the memory, and the trap's
    R2 by wasm instruction; it found two bugs in the early return that
    the model-based fuzzer and `run.py` had missed. A mode like it in
    `fuzz.py`, with traps in the model, would catch such bugs before a
    review does.
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

- **Four ways to fewer pipeline stalls in translated code**, tried in the
  translator work of 2026-10-19 and dropped, measured with
  `bench/pipecycles.py`:
  - Moving an instruction up past a conditional jump, into the slot
    before a read, when its register is dead where the jump goes. It
    saved 3000 cycles, but the instruction then also runs on the taken
    path: bst ran 11116 more instructions, and strings took 1100 more
    cycles.
  - Sharing a compare by carrying the C flag to the next access, with no
    copy of the slow path. Other compares between the accesses mostly
    prevent it, and it saved 3000 cycles where the copy saves far more.
  - Hiding the math unit's wait on the interpreter's `MUL` by moving
    instructions between the operand writes and the result read. Only
    two or three register-only instructions can move, about 4000 of the
    70000 cycles, and they would cross a store and a trap's start label.
  - A pass that moves an earlier instruction down to break the address
    register and data bus stalls. It saved 721 cycles: the stalls that
    the model counts are the second table read of a byte load, which the
    bus delays anyway, and the pushes and pops of the hand-written
    runtime. Interleaving crc32's two byte loads gained nothing for the
    same reason.
- **A condition or instruction for signed comparison.** A signed a < b
  takes two instructions, `?V XOR R14, R14, 0x10000000` and then `?N`,
  as ISA.md §9.2 shows and nicewasm does. Michael decided on 2026-10-15
  to keep it that way.
- **Board synthesis and an example design in this repository.** This
  repository stays FPGA-agnostic. The MEGA65 example design, with its
  synthesis, size, and clock speed, lives in the
  [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
  repository (MICROARCH.md §10).
