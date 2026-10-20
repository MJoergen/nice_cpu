# TODO

This is the single list of open items for the repository: work not done
yet, questions not decided, claims not checked, and ideas for later. Each
item names where it comes from. Add new items here, not in other files.

No code has TODO or FIXME comments.

## From the fourth repository review (2026-10-20)

The findings of [doc/review/fourth-repository-review.md](doc/review/fourth-repository-review.md)
that are not closed yet. Every finding of the earlier reviews is closed.

- **Documents** (§1.3, §2, §4.4): ISA.md §10 could say that `INT`,
  `.BLK`, and `.RES` take a value before it wraps; SYSTEM.md §1 that the
  emulator and the simulation memory never return 0 for a console read
  with no byte waiting; and the translator's README that an unreadable
  input and the overwrite check print without `error:`, and that
  `early_exit` has a length limit.
- **A failing C library test** stops `make -C runtime/libc test` before
  the line that removes the tests' build files, which git does not
  ignore (§3.6).
- **`nice.rs`** has no test of `poke` and of `pollc` returning a byte,
  until a rustc is at hand to rebuild `runtime/test/nicers.wasm` (§3.5).
- **The fuzzer of the translator** still has no blocks with several
  values and no traps in its model (§4.3).
- **The math unit's products** (§6.5): `hdl/formal/mpu.sby` proves that a
  product read is never stale, not that `*` and the signed correction
  compute the product, and the dividers up to the lemma that shift and
  add multiplies, because neither Yices nor Boolector can compare two
  32-bit multipliers. A solver with a multiplier theory, or the lemma
  proven by hand beside the job, would close it.
- **CI's formal tools** (§6.5): the jobs of the shared functions, DECODE,
  the performance counters, the fetch statistics, and the math unit ran
  with Yosys 0.56 and GHDL 6.0 only. CI's Yosys 0.33 and GHDL 4.1 have
  not run them.

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
    In NiceMonMEGA65 it reached about 78 MHz before WRITE stopped taking
    read data from the bus into the ALU
    ([doc/review/pipeline-timing.md](doc/review/pipeline-timing.md), Read
    data). See the items under "Pipelined core" below.
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
- **Formal checks with SymbiYosys** (MICROARCH.md §9). `make formal` proves
  the ports of the multi-cycle core and the data bus decoder, the timer,
  the math unit, the performance counters, the fetch statistics, and
  FETCH, DECODE, PREPARE, and DBUS of the pipelined core, for every
  cycle, and the shifter, the ALU, and the block compares of the store
  check for every input. For the whole pipelined core it checks the ports
  and the core's own assertions, the data access rule among them, only
  for the first 8 cycles after reset ([hdl/README.md](hdl/README.md)).
  Open: WRITE is mostly ISA semantics, which the trace diff checks
  better, and only the bounded check covers it, so that a halted core
  makes no store or vector read is proved for 8 cycles only, where
  PREPARE's reads and FETCH's requests are proved for every cycle. A
  proof of the whole core for every cycle, which needs invariants that
  tie the stages together; and the order of the data accesses checked
  against a model of the program, not only through the tests. With Yosys
  0.56 the bounded check reaches 12 cycles in 13 minutes, where CI's
  Yosys 0.33 did not finish 9 in 20; the depth can grow when CI's tools
  do.

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
  inputs arrive at time 0 and the outputs are due at time 10 ns, so
  `make timing` in `hdl/` reports their slack as the time left to the
  system. Read data goes into WRITE only for a register write (6.5 ns
  left), but `dbus_ack_i` goes into WRITE's retire and so into FETCH
  (2.8 ns left), and the store goes onto the bus from WRITE in the cycle
  it runs (1.2 ns left for the address, 1.4 ns for the data). Next: the
  store from a register in DBUS, which costs a cycle for a read right
  after a store (MICROARCH.md §5.3, rule 3), and a skid buffer between
  DECODE and PREPARE for the handshake. Measure each in NiceMonMEGA65.
  `retire_o` is combinational and is not counted.
- **NiceMonMEGA65 reads the registers from `retire_o.regs`**, which is
  `w_n.regs` of WRITE, before the register. Its worst path ends there. A
  registered copy is enough for nicemon. Fix in NiceMonMEGA65, and say in
  `hdl/src/trace_pkg.vhd` that `retire_o` is for simulation and is slow.

- **The cycle the model lacks.** `bench/pipecycles.py` charges a jump
  taken in WRITE 7 cycles, where the core's bubble is 6
  (`hdl/test/bubble.nasm`), because 7 brings the model closer to the
  core on the benchmark, which it still underestimates by 3% and 7%
  (`make compare` in `bench/`). Find what the extra cycle stands for,
  for example by printing each retire's cycle from a scratch copy of the
  core and comparing it with the model's, instruction by instruction
  (doc/review/third-repository-review.md §3.1).
- **Speculative reads of RAM** (MICROARCH.md §5.3). Data reads wait until
  the instruction is certain to run. The waits are a conditional read
  after a write of SR, 0.0% of the translated benchmark's instructions and
  3.8% of the hand-written one's, and a read after a conditional jump,
  5.6% and 7.6% (MICROARCH.md §5.6). Allowing speculative reads of RAM, but
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
