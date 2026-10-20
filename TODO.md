# TODO

This is the single list of open items for the repository: work not done
yet, questions not decided, claims not checked, and ideas for later. Each
item names where it comes from. Add new items here, not in other files.

Every finding of the reviews in [doc/review/](doc/review/) before
2026-10-20 is closed. The open findings of the review of 2026-10-20 are
the first section below. No code has TODO or FIXME comments.

## Findings of the review of 2026-10-20

The open items of
[doc/review/third-repository-review.md](doc/review/third-repository-review.md),
added 2026-10-20. The section numbers are its.

- **The cycle model's bubble after a jump taken in WRITE** (§3.1).
  `bench/README.md` and the docstring of `bench/pipecycles.py` explain
  `--flush 7` with a registered flush that the core does not have: the
  flush is combinational, and the measured bubble is 6 cycles, for an
  aligned target and for one that spans two pairs alike (§1.2). Say that
  7 is the value that fits the benchmark, or find the cycle the model
  lacks; the hand-counted cases of `pipecycles.py --test` and
  `cycprof.py --test` encode the 7.
- **Rules of `hazards.py` and the model that are not the core's** (§3.2,
  §3.3): a jump through a register counts as one DECODE resolves, and
  `MOVE R15, Rx` as a two-cycle jump; a shift count through an adder
  (`c[R]`, `--R`), which the translator's signed byte loads use 4175
  times in the benchmark, is not charged the cycle WRITE spends on it.
  The translator could avoid that count too, at an instruction or a
  register.
- **The `hand.nasm` rows of the benchmark tables** (§1.3) in
  `bench/README.md` and `hdl/README.md` give 1216653 cycles on the
  pipelined core, with 60191 for `rng64` and 262436 for `bst`; the core
  at 69405dd, whose logic is that of the commit of the tables, gives
  1215117, 59679, and 261412. The translated program's rows reproduce
  exactly. Measure again, and name the commit beside each table.
- **The four options of the re-timed core** are documented as off by
  default in `pipecycles.py`; they are on (§3.4). `hazards.py` and
  `pipecycles.py` count the same trace differently, 1775455 against
  1775661 instructions, since one skips a trace line that the program's
  console output precedes (§3.5).
- **The moves left text behind** (§2): the memory map of SYSTEM.md is two tables
  (§2.2); the slides send a C compiler to ISA.md for its calling
  convention, which is in ABI.md (§2.6); HISTORY.md calls the translated
  code "the code of the translator", cites a section of ISA.md that is
  now WASM.md, and gives the core's cycles as the model's (§2.5); the review notes cite ISA.md
  §8.4, §8.6, and §9.4 by their old numbers (§2.7, §5.1).
- **MICROARCH.md and ASSUMPTIONS.md lag the re-timing** (§2.3, §2.4):
  §3 and §4 give the words and micro-operations per instruction of the
  old table; §7.4 says two cycles where a rotation through C takes
  three; §5.5 and `pipe_fetch.vhd` say no store retires in the cycle
  after a redirect, which DECODE's redirect does not guarantee, and the
  compare is safe for another reason; ASSUMPTIONS.md item 6 names
  `w_r.cnt_done`, which does not exist, and item 1 has a paragraph
  Markdown renders as code. Smaller ones in §2.7: "some five cycles" in
  `translator/README.md`, the third two-cycle case in `hdl/README.md`,
  a done sub-item below, and the header of `tb_shift.vhd`.
- **The diagrams of MICROARCH.md** (§2.8): `interrupt.tex` shows the
  dropped instruction's address on `target_o` in the cycle of the take,
  where the re-timed core puts the next instruction's, 0014 and 0020 in
  place of 0012 and 001E, which FETCH never fetches; and the header of
  `pipeline.tex` does not name DECODE's second slot, `dec_q`, and draws
  the flush to FETCH alone. Fix the values and `make diagrams`.
- **Multiplication by a constant is tuned to the 35-cycle multiplier**
  (§4.1). The comments at `MUL_STEPS` and `MUL64_STEPS` and
  `translator/README.md` justify the budgets with a product that took
  35 cycles until 2026-10-16; it takes 3. By the model, `MUL_STEPS` = 2
  saves 0.2% of the benchmark's cycles, and `rng64`'s 28 steps beside
  one product could be three products of the math unit.

## FPGA core

- **The pipelined core: what is left.** `hdl/src/pipeline.vhd` passes
  every test that the multi-cycle core passes ([hdl/README.md](hdl/README.md)).
  [hdl/ASSUMPTIONS.md](hdl/ASSUMPTIONS.md) lists where it settles or
  departs from [doc/MICROARCH.md](doc/MICROARCH.md). Open:
  - The cost of the waits that MICROARCH.md §5.3 and §5.6 discuss, from
    the pipelined core's cycles for the benchmark (`make core
    CORE=pipeline` in `bench/`), to decide on speculative reads (below).
  - Speed: the core alone meets a 10 ns clock out of context (Vivado
    2025.1, `make timing` in `hdl/`), with a margin of a few tenths of a
    nanosecond ([doc/review/pipeline-timing.md](doc/review/pipeline-timing.md)).
    NiceMonMEGA65 still runs it at
    33.3 MHz, and must be tried at 100 MHz. See the clock items below.
- **Test order steps not done** (MICROARCH.md §9):
  - Step 4, hazard programs: `hdl/test/hazard.nasm`,
    `hdl/test/sidefx_prog.py`, and `hdl/test/smc_prog.py`, which both
    cores pass. Left
    out so far: pairs of side effects on R15, which only some cases of
    `hazard.nasm` and the random programs have. `hazard.nasm` tests a
    flag set by a side effect on R14 only for a destination, because a
    source side effect needs VBASE = 0xFFFFFF before the instruction,
    and its vector table would then be in the I/O range.
  - Step 5: `hdl/test/irq_sweep.py` runs `hazard.nasm` with an NMI before
    each step, and with an IRQ before each, and both cores pass, and
    `irqhazard.nasm` too. `latecount.nasm` was swept the same way by hand
    on 2026-10-20, and both cores pass. Not swept: the program of `sidefx_prog.py`, which writes R14
    with any value, so E and VBASE too. For the pipelined core, the sweep
    compares with `irq_compare.py --read-delay`, and both cores are swept
    with the request raised up to a few cycles late as well.
  - Step 6: `make programs` in `hdl/` runs the runtime's and the
    translator's test programs on the core, and both cores pass. Left out: the random modules of `translator/test/fuzz.py`,
    `runtime/libc/test/fuzz_printf.py`, which needs clang, and the
    benchmark, which `make core` in `bench/` runs already.
  - Step 7: `hdl/test/random_prog.py` was tuned with
    `hdl/test/random_stats.py`, and both cores pass seeds 1 to 90, with
    the shift jumps it makes since 2026-10-20. Still weak: a conditional instruction right after a write of
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
  set, or 0 (SYSTEM.md §1). `wb_mem.vhd` reads a file, as the emulator's
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
  program, not only through the tests. That a halted core makes no data
  bus request is proved for the multi-cycle core only. In the pipelined
  core, PREPARE and WRITE start a data access only in `RUN_ST`, but no
  proof says so.

## Devices

- **An interrupt controller.** The timer (SYSTEM.md §4) is the only device
  that raises IRQ, so it drives the core's IRQ port directly. A second
  device needs a controller that merges the requests and says which vector
  goes first. No device raises NMI.

## Pipelined core

- **The margin at 100 MHz is thin** (pipeline-timing.md). The worst paths out of context are within a few tenths
  of a nanosecond of 10 ns, and several differ only by placement: the
  flush, through PREPARE's handshake, into DECODE's registers; the store
  address through the block compare into the flush; and the next
  address of an instruction from FETCH's head into DECODE. The full
  design places worse than the core alone. Ideas, each worth a few
  tenths: a second slot in PREPARE, so that DECODE's emit does not wait
  on WRITE's decision; the condition and the data count of WRITE's
  micro-operation tested a cycle ahead; DECODE's next address from
  FETCH's precomputed heads. Decide after NiceMonMEGA65 has been tried
  at 100 MHz.
- **What the system adds to the core's paths.** Out of context, the
  inputs arrive at time 0. In the system, the data bus's read data goes
  straight into WRITE's operands in the cycle of the ACK, and
  `dbus_stall_i` into WRITE's retire and so into the flush; the memory
  and the decoder must register what they drive. `retire_o` and the bus
  outputs are combinational and were never counted.
- **NiceMonMEGA65 reads the registers from `retire_o.regs`**, which is
  `w_n.regs` of WRITE, before the register. Its worst path ends there. A
  registered copy is enough for nicemon. Fix in NiceMonMEGA65, and say in
  `hdl/src/trace_pkg.vhd` that `retire_o` is for simulation and is slow.

- **Speculative reads of RAM** (MICROARCH.md §5.3). Data reads wait until
  the instruction is certain to run. The waits are a conditional read
  after a write of SR, 0.0% of the translated benchmark's instructions and
  3.8% of the hand-written one's, and a read after a conditional jump,
  5.5% and 7.6% (MICROARCH.md §5.6). Allowing speculative reads of RAM, but
  not of the I/O range, needs a change to ISA.md §8.2 and a check of each
  read against older stores. Decide once the pipelined core shows what the
  waits cost. The bypasses and the slow path for R14 were decided from the
  same measurements (MICROARCH.md §5.6).

## Toolchain

- **A C compiler for NICE.** None targets NICE directly. ABI.md
  defines the C ABI for one. Until then, C reaches NICE through wasm
  ([README.md](README.md), Compilers).
- **A linker.** There is none. Programs are joined with `cat` and
  assembled at once, so every label is global (ABI.md).
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
  What happens then is undefined (WASM.md). An idea: a check against a
  stack limit in each function's prologue, at a cost in code size.
- **Faster and smaller translated code.** `bench/` runs 1730635
  instructions, against 491617 for `hand.nasm`, and takes about 2.28
  million cycles on the pipelined core (`make compare`), 2.20 million by
  the estimate of `bench/pipecycles.py`
  ([translator/README.md](translator/README.md), How functions are
  translated). Trusting the alignment hint would save nothing, as one
  compare covers the bounds and the alignment. What is left, by the
  estimate:
  - *Taken jumps resolved in WRITE*, about half of the cycles
    above one per instruction: the interpreter's table jumps, which no layout
    avoids, and `br_if`s whose common path is the taken one. nicewasm
    guesses that the shorter arm of a diamond is the rarer one; branch
    probabilities from a profile would do better.
  - *Waits on the math unit*, about 4% now that the multiplier takes
    two cycles: the interpreter's `MUL`, `__mul64` in `runtime/`, and
    `% 26` in strings read the result right after writing the operands,
    and a division still takes up to 34 cycles. Hiding a wait needs
    independent work in between, which the translator rarely has without
    moving stores past loads. `__mul64` could overlap its partial
    products.
  - *A read right after a skipped bounds-check jump*, about a fifth, in
    chains of dependent loads, where no instruction can fill the slot,
    and in the byte accesses, whose word index and shift count now come
    before the compare. Speculative reads (above) would remove it.
  - *The address register written by the instruction before*, about 3%
    now that the byte accesses compute theirs before the compare
    (MICROARCH.md §5.1).
  - *Loop back edges* cost the two cycles of an early redirect each round.
  - *`@Rx++` for a pointer walk*, as `hand.nasm` does, needs a word
    pointer kept in step with the byte address, which is out of reach
    without loop analysis on an intermediate form.
  - *Range analysis* beyond the bounds nicewasm keeps (masks, byte loads,
    shifts, and remainders), to drop the bounds checks of counted loops.
  - WASM.md could say where a trap's R2 points when nicewasm copies
    or moves code: at the first instruction of the original copy, and
    the code of a neighbouring access may lie between that instruction
    and the rest of the trapping instruction's code.
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
    are tested by `run.py`, and by `make diff` (`test/diff_fuzz.py`),
    which runs two versions of nicewasm on the same random modules, with
    statements that may trap, and compares the console output, the halt,
    the registers, and the memory. A model with traps in `fuzz.py` is still an idea.
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
  translator and dropped, measured with
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
  as ISA.md §9.2 shows and nicewasm does. It stays that way.
- **Board synthesis and an example design in this repository.** This
  repository stays FPGA-agnostic. The MEGA65 example design, with its
  synthesis, size, and clock speed, lives in the
  [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
  repository (MICROARCH.md §10).
