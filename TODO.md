# TODO

This is the single list of open items for the repository: work not done
yet, questions not decided, claims not checked, and ideas for later. Each
item names where it comes from. Add new items here, not in other files.

Every finding of the reviews in [doc/review/](doc/review/) is closed or
listed here, the last ones under "Left from the sixth review" and "Left
from the fifth review". No code has TODO or FIXME comments.

## FPGA core

- **Test order steps not done** (MICROARCH.md §9):
  - Step 7: `hdl/test/random_prog.py` is tuned with
    `hdl/test/random_stats.py`, and both cores pass seeds 1 to 1000
    (`make random-sweep`). Still weak: about a third of the runs halt
    before the step limit (seeds 1 to 90: 35 of 90): 16 at a reserved
    word, which has not been traced, 15 at an RTI outside a routine (the
    `?I RTI` that starts the program, with I set by a write of SR), 2 at an
    INT, and 2 at a HALT.
- **Formal checks with SymbiYosys** (MICROARCH.md §9). `make formal`
  proves the ports of the multi-cycle core and the data bus decoder, the
  timer, the math unit, the performance counters, the fetch statistics,
  the debug link, and FETCH, DECODE, PREPARE, and DBUS of the pipelined
  core, for every cycle, WRITE's halt (it stays halted until reset and
  makes no store, vector read, interrupt entry, or accept) and its pause
  (the same, and a step reported after each pause), and the
  shifter, the ALU, and the block compares of the store check for every
  input. For the whole pipelined core it checks the ports and the core's
  own assertions, the data access rule among them, only for the first 8
  cycles after reset ([hdl/README.md](hdl/README.md)). WRITE's other
  behavior is ISA semantics, which the trace diff checks better, so no
  proof of it is planned. Open: a proof of the whole core for every cycle,
  which needs invariants that tie the stages together and is not planned;
  and the order of the data accesses checked against a model of the
  program, not only through the tests. With Yosys 0.56 the bounded check
  reaches 12 cycles in 13 minutes, where CI's Yosys 0.33 did not finish 9
  in 20; the depth can grow when CI's tools do.

- **Jumps that DECODE predicts** (MICROARCH.md §5.4). It predicts a
  backward conditional `ADD PC, PC, offset` taken, and `bench/hand.nasm`
  and `simple.nasm` close their loops with it. Open:
  - A mnemonic in niceasm for a relative jump, so that a program need not
    label the instruction after the jump. It would change the encoding of
    what the programmer wrote, so it needs a decision first.
  - The runtime's loops: `runtime/lib.nasm`, `muldiv_soft.nasm`, and
    `trapmsg.nasm` have nine conditional jumps back, all `MOVE PC, label`.
  - A branch-target buffer, for the indirect jumps that no static rule
    predicts, such as the `vm` phase's dispatch: 28001 flushes in each
    benchmark program, 8% of the translated one's cycles.

## Left from the sixth review

([doc/review/sixth-repository-review.md](doc/review/sixth-repository-review.md),
2026-10-26, at b2ac5a5, one commit after RC05. Nothing of it is fixed yet;
the section numbers are the review's.)

- **The release gate.** Tag after the push's CI run is green, with an
  annotated tag whose message is the tag's section of RELEASE_NOTES.md.
  Rebase and merge `origin/release-script` after its six fixes (§10). Move
  NiceMonMEGA65's pin to RC05 and tag it there (§1.1, §1.2). Close PR #35,
  delete `origin/claude/project-thread-cmdpdw`, and keep PR #36 and
  `origin/read-waits` until decided (§1.3).
- **Three behavior edges.** `debug_link.vhd` lets the second checksum byte
  of a dropped packet through to the program (§3.1); `niceasm.py
  --symbols` can overwrite its input (§4.1); `niceemu` ignores Ctrl-C while
  it waits for console input (§4.2). Each with a test.
- **Issue #53's seven simplifications** of `debug_link.vhd`: do them, or
  drop them here (§2.1). The won't-do items of #51, #54, and 2026-10-23
  go under "Decided against" (§2.2).
- **The predictor in random code.** A template with backward conditional
  jumps in `random_prog.py`, and a predictor program in `HAZARD_PROGS`
  (§7.2). A second loop shape in the translator's `gen_loop` (§6.2).
- **The microsecond counter** proven and tested at 1.5 MHz only: a
  `tb_perf` run at 33333333 Hz, and SYSTEM.md §3 says "the integer part of
  N·10⁶/G_CLK_HZ, for 1 MHz and up" (§7.3). `run_i` as a rule of
  MICROARCH.md §8, and the counters in `tb_core` (§7.4, §3.4).
- **The figures of the predictor's era.** The translated column of
  MICROARCH.md §5.6, two percentages of §5.3, the quoted outputs, the
  ratio table, and the Dhrystone table of bench/README.md, HISTORY.md's
  predictor entry, and the word counts (§8.2 to §8.6, §6.5, §9.2). One
  pass of `make hazards`, `make cycles`, `make compare`, `make words`,
  `make dhry`, and `make core-dhry`, with the commit named.
- **Speculative reads.** The figures of `origin/read-waits` into
  MICROARCH.md §5.3 and HISTORY.md, then the branch can go (§2.3). A row
  per out-of-context timing figure in pipeline-timing.md, and an
  in-system build at RC05 (§2.4).
- **The debug link's documents.** The board contracts, the bad-checksum
  `W` difference, and a table of the versions in DEBUG.md; the proof's
  wording; the untested halt reasons and `link.py` cases (§3.2 to §3.7).
- **Stale text.** "Condition always" in `pipe_decode.vhd`, `pipeline.vhd`,
  and hdl/README.md; the cycle counter at hdl/README.md:1180; the step
  numbers of §9 in five places; HISTORY.md's missing entries;
  RELEASE_NOTES.md's missing upgrade notes and labels; README.md's "four
  stages" and "four tools"; CLAUDE.md's Layout; DEBUG.md in
  `check_refs.py` (§7.5, §9).
- **Smaller.** `llvm-ar` checked and named (§1.4); the `.wasm` executable
  bits and `.mypy_cache` (§1.5); terms for Dhrystone and `mchess.c`, and
  `mchess.expected`'s provenance (§1.5, §5.2); the Zig library size claim
  (§5.1); `--stack` needs `--memory` (§5.3); `trapmsg.nasm` for codes
  above 7, `CLOCKS_PER_SEC`, the reserved labels, ABI.md's join order
  (§5.4); the wall-clock limit of `errors.py` (§6.3); `nicebuild.py`'s
  `--allow-undefined`, `--stack 0`, and messages (§6.4); `--irq` against
  the timer at one step (§4.3).

## Left from the fifth review

([doc/review/fifth-repository-review.md](doc/review/fifth-repository-review.md))

- **The Vivado path** is machine-specific in `hdl/Makefile` and
  `hdl/CLAUDE.md`. Keep it as the default, or take it from the
  environment only (§1.6).
- **The 2004 example programs** (`count`, `replicate`, `print`) have no
  license. The MIT license excludes them. Ask B. Ulmann (§1.6).

## Devices

- **An interrupt controller.** The timer (SYSTEM.md §4) is the only device
  that raises IRQ, so it drives the core's IRQ port directly. A second
  device needs a controller that merges the requests and says which vector
  goes first. No device raises NMI.
- **A real-time clock.** The microsecond counter (SYSTEM.md §3) counts
  running time since reset, so `time.h` has `clock` but no calendar: `time`
  returns −1, and `difftime`, `gmtime`, `mktime`, and `strftime` are
  missing. A device with the date, set by the board, would let `time` work.
- **Run control in the debug link** (DEBUG.md). Version 3 has the pause and
  the single step, in niceemu and in `src/debug_link.vhd`. A board must stop
  the counters and the timer while `paused_o` is 1 (NiceMonMEGA65). DEBUG.md
  version 4 specifies the breakpoints (stage 4, #55), which niceemu, both
  cores, and `src/debug_link.vhd` do not have yet. Still to do after them:
  watchpoints, and writable registers and a
  port for the hidden state of ISA.md §1.4 (stage 6). A step is one per
  write; a count of steps, and a read-only register that counts them so a
  host can tell whether a step ran when both the `k` and the `p` were lost,
  can come with the breakpoints if a host needs them. A pause cannot
  interrupt a console read that waits in niceemu (DEBUG.md §7); a board's
  read does not wait.

## Toolchain

- **A C compiler for NICE.** None targets NICE directly. ABI.md
  defines the C ABI for one. Until then, C reaches NICE through wasm
  ([README.md](README.md), Compilers).
  [doc/review/c-compiler-plan.md](doc/review/c-compiler-plan.md) has the
  expected gain and the decisions taken: the goal is cycles on the
  pipelined core; `CHAR_BIT` is 32; the front end is our own, in
  Python; the intermediate form is SSA from the start; the C accepted at
  first is C89 with `long long` and variadic functions; the C library is
  compiled natively from the same sources; and there is no linker. Still
  open:
  - The float library, once there is float arithmetic: called in wasm
    across the pointer boundary of WASM.md, or compiled natively.
  - An optional check mode for accesses out of bounds.
  - The tests: against the host, the benchmark, Dhrystone, and a fuzzer.
- **A linker.** There is none. Programs are joined with `cat` and
  assembled at once, so every label is global (ABI.md). The C compiler
  does without one (c-compiler-plan.md, decision 7). Short of a linker,
  the C library could be split into one file per function, and only the
  files whose labels a program uses joined.
- **The C library is small** ([runtime/README.md](runtime/README.md#c-library)).
  Missing: float conversions in `printf` and `scanf`, which would pull in
  the float library; and `errno`.
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
  `table.get` and `table.grow`, `ref.func` outside element segments, `ref.null` and
  `ref.is_null`, the tail calls `return_call` and `return_call_indirect`, SIMD, and
  exceptions.
- **Stack overflow** is not detected in translated code, unlike in wasm.
  What happens then is undefined (WASM.md). An idea: a check against a
  stack limit in each function's prologue, at a cost in code size.
- **Faster and smaller translated code.** `bench/` runs 1652811
  instructions, against 491309 for `hand.nasm`, and takes about 2.36
  million cycles in its phases on the pipelined core, as the estimate of
  `bench/pipecycles.py` does (`make compare`)
  ([translator/README.md](translator/README.md), How functions are
  translated). Trusting the alignment hint would save nothing, as one
  compare covers the bounds and the alignment. What is left, by the
  estimate:
  - *Taken jumps resolved in WRITE*, about a third of the cycles
    above one per instruction: the interpreter's table jumps, which no layout
    avoids, and `br_if`s whose common path is the taken one. nicewasm
    guesses that the shorter arm of a diamond is the rarer one; branch
    probabilities from a profile would do better.
  - *Read data that goes into the ALU or a store*, which WRITE takes a
    cycle after its ACK, about a quarter (MICROARCH.md §5.3).
  - *Waits on the math unit*, about 6% now that the multiplier takes
    two cycles: the interpreter's `MUL`, `__mul64` in `runtime/`, and
    `% 26` in strings read the result right after writing the operands,
    and a division still takes up to 34 cycles. Hiding a wait needs
    independent work in between, which the translator rarely has without
    moving stores past loads. `__mul64` could overlap its partial
    products.
  - *Reads that PREPARE loads in the cycle it gets them*, about 15%: the
    request is a register, so the data comes two cycles later, one more
    than WRITE needs, unless a stall let the read go out early. A read
    right after a skipped bounds-check jump costs no more than another,
    since it loads in the cycle the jump leaves WRITE, so speculative
    reads (above) would not save that cycle.
  - *The address register written by the instruction before*, almost
    nothing now that the byte accesses compute theirs before the compare
    (MICROARCH.md §5.1).
  - *Loop back edges* cost the three cycles of an early redirect each round.
  - *`@Rx++` for a pointer walk*, as `hand.nasm` does, needs a word
    pointer kept in step with the byte address, which is out of reach
    without loop analysis on an intermediate form.
  - *Range analysis* beyond the bounds nicewasm keeps (masks, byte loads,
    shifts, and remainders), to drop the bounds checks of counted loops.
  - WASM.md could say where a trap's R2 points when nicewasm copies
    or moves code: at the first instruction of the original copy, and
    the code of a neighboring access may lie between that instruction
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
  - *What `fuzz.py` cannot check.* Its model knows a trap's code but not
    R2, the address of the code that trapped, so R2 is tested only by
    `run.py`, and by `make diff` (`test/diff_fuzz.py`), which runs two
    versions of nicewasm on the same random modules, with statements that
    may trap, and compares the console output, the halt, the registers,
    and the memory. The model has no `memory.grow`, no floats, and no
    functions with several results; `make diff` covers the first.
- **Benchmarks beyond [bench/](bench/README.md)** and its Dhrystone. A
  subset of Embench-IoT, such as `crc32`, `matmult-int`, `huffbench`, and
  `nettle-sha256`, has published results for small RISC-V and Arm cores,
  but its harness is GPL-3, so it would live outside this repository.
  `bench/` has no float phase, because one would measure the float library
  more than the translator.
- **WASM.md, "Traps", shows C code that does not build.** It stores a
  function pointer in `extern void (*__wasm_trap_vector)(int, unsigned)`.
  clang reports the symbol undefined, and a C function pointer is a table
  index, not the NICE address that the vector holds. A handler has to be
  assembly, such as `trapmsg.nasm`. Reword the paragraph, or add a
  runtime routine that installs a C handler through a trampoline.

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
