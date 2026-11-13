# Decided against

Ideas that were weighed and dropped, with the reason, so that they are not
proposed again. The open items are the
[issues](https://github.com/MJoergen/nice_cpu/issues) of the repository.

- **Other register designs for the SD card** (#107). A data port whose
  cursor moves on every access, as QNICE-FPGA has: a read with a side
  effect needs a rule of its own for the debug link, and a memory page of
  the on-board debugger shown over it would eat the program's buffer. The
  buffer mapped as 128 words: a board has only 64 words of I/O left. A DMA
  engine that copies the sector to memory: it would be a third master on
  the data bus, which the core and the link share.
- **SD card commands that take time in the emulator** (#107), so that a
  program that does not wait for busy fails there as on a board. The
  simulation of the cores could not match the emulator's steps, and the
  trace diff of `make -C hdl test` would break at the first command.
- **The emulator's `NET_IP` as the address of `--link`** (#124). The
  emulator listens on `127.0.0.1` unless told otherwise, so the word would
  mean little, and a program that wrote it could not move the listener.
  `NET_IP` is a register that keeps what a program writes (DEVICES.md §6).
- **Taking the Vivado path from the environment only** (#61). `hdl/Makefile`
  keeps `/opt/Xilinx/2025.1/Vivado/bin/vivado` as the default of `VIVADO`,
  so `make timing` works as is where Vivado is installed there, and
  `make timing VIVADO=...` or the environment names another.
- **Version negotiation on the debug link** (#81), where a host asks the
  system to act as an older version. The rules of DEBUG.md §9 keep older
  hosts working without it, and it would add state to `debug_link.vhd` and
  its proofs.
- **A watchpoint that stops before the access** (#146). In the pipelined
  core the compare would sit on PREPARE's address path, which sets the
  clock, and PREPARE and WRITE would have to hold the access back, as
  for a breakpoint. A stop after the step is exact without them, and a
  host that wants the old value reads it before it enables the
  watchpoint. Only a device read with a side effect, such as the
  console's, cannot be caught before it.
- **A bank select at `0xFFFFFFF7` on the debug link** (#109), to make room
  for the hidden state and watchpoints in major 0. There is no lock
  between the host and a client in the system, so one could switch the
  bank under the other, and on a UART no connection resets it for a new
  host. The link's registers grew down to `0xFFFFFFD0` instead. A new
  major for the same room was dropped too: every host would have had to
  move at once.
- **A timing budget for the Nexys4DDR** (#57). The core alone misses 90
  MHz there by about 0.3 ns out of context (hdl/README.md), so only the
  in-system result counts. Add a guard only if a change meets the MEGA65
  budget and costs the Nexys4DDR its 90 MHz.
- **One block per notice in `TX_IDLE_ST`** of `debug_link.vhd` (item 6 of
  #53, §2.1). Folding the five blocks into one that sends the chosen kind
  touches the `i_out_*` proofs, and gains a few lines.
- **PR #36** (`RDSPC`, `RDSSR`, `WRSPC`, and `WRSSR`, control commands 4 to 7,
  to read and write the saved PC and SR from an interrupt routine). Closed on
  2026-10-26: the debug link's pause and single step (DEBUG.md §6) cover
  breakpoints and stepping from the host. Its branch,
  `claude/project-thread-k4m3qt`, stays.
- **Annotated tags for `RC01` to `RC06`** (sixth review §1.1). They stay
  lightweight: re-tagging means force-pushing tags that others may have
  fetched. `RC06` was made by hand, before `release.py tag` was used. From
  `V1.0` on, `release.py tag` makes them, annotated.
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
- **Two simplifications of the pipelined stages** (issue #51, items 9 and
  10), each about three lines. WRITE's register write is in two
  branches, and merging them reshapes the re-timed WRITE paths; the
  second also keys the R15 flush on `u_v.wreg`, so that it does not wait
  for the write mux. DECODE's two refill branches could share a mux, but
  it would sit ahead of `first_kind` and lengthen the path from FETCH's
  words. Left alone in issue #54 for the same kind of reason: the math
  unit's two divide start blocks (a procedure would take six
  parameters), and reading the `_o` ports instead of their `_r` copies
  (it breaks the convention of every entity).
- **Further optimizations of nicewasm** (#73). Each needs more than
  the translator has, or gains too little:
  - Branch probabilities from a profile, to lay out diamonds and to
    decide which accesses share a compare. Nothing in the repository
    collects a profile or feeds one back.
  - Options for the two guesses that a profile would replace: the
    shorter arm of a diamond taken for the rarer one, and `SHARE_COST`
    and `SHARE_CHECKS` in `nicewasm.py`. An option that no one sets
    changes nothing, so one constant stays.
  - `@Rx++` for a pointer walk, as `hand.nasm` does, and range analysis
    to drop the bounds checks of counted loops. Both need loop analysis
    on an intermediate form, which nicewasm does not have. They belong
    in a compiler (#66).
  - Overlapping the partial products of `__mul64` in
    `runtime/muldiv_mpu.nasm`. The math unit has one multiplier, and the
    routine is nine instructions, so it would save a cycle or two.

  The cost of taken jumps and loop back edges is a matter of jump
  prediction in the core (#60).
- **Speculative reads.** The waits they could remove are 0.006% and
  0.18% of the cycles (MICROARCH.md §5.3, HISTORY.md).
- **A store into the math unit that retires when it goes into the
  register**, as one into memory does. It saved 0.39% of the translated
  benchmark's cycles and 0.08% of `hand.nasm`'s, too little for a special
  case of the I/O range (HISTORY.md).
- **More timing fixes of the pipelined core** (issue #34): WRITE's
  decisions into the enables of PREPARE's and WRITE's registers, WRITE's
  ALU into its own next state, FETCH's next address from its ring, and
  `irq_ready_o` combinational from WRITE (HISTORY.md,
  [pipeline-timing.md](pipeline-timing.md)).
- **Python 3.7 for the hdl scripts.** They need Python 3.10 (`str | None`),
  as README.md says. Sixteen of them would need `from __future__ import
  annotations` for 3.7, and nothing asks for it (sixth review §1.5).
- **A condition or instruction for signed comparison.** A signed a < b
  takes two instructions, `?V XOR R14, R14, 0x10000000` and then `?N`,
  as ISA.md §9.2 shows and nicewasm does. It stays that way.
- **Board synthesis and an example design in this repository.** This
  repository stays FPGA-agnostic. The MEGA65 example design, with its
  synthesis, size, and clock speed, lives in the
  [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
  repository (MICROARCH.md §10).
- **A macro facility in the assembler** (#93), `.MACRO` and `.ENDM`, so
  that a program could define `CALL` and `RET`. A text macro cannot pick
  the constant of a call, which is the size of the jump: 2 for a label
  and 1 for a register (ABI.md), so `CALL R2` would push the wrong return
  address. The two are pseudo-instructions of the assembler instead
  (ISA.md §10.1), which also settles the facility's open questions:
  names, conditions, labels in a body, nesting, and where an error is
  reported.
- **SIMD and exceptions in nicewasm** (#71). A `v128` would take four
  words and about 230 instructions, with nothing gained on a scalar
  32-bit CPU, and compilers emit SIMD only when asked (`-msimd128`).
  Exceptions come from C++ and from Rust with `panic=unwind`, which need a
  C++ library and Rust's std, neither of which the repository has.
  nicewasm rejects both.
- **C's `long double` and `__int128` in the runtime library** (#70). In
  wasm32 they are 128 bits, and clang calls routines such as `__addtf3`
  and `__multi3` for them. No program here uses them, Zig's `f128` and
  `u128` work because Zig puts its compiler_rt in the module, and the
  float routines alone would add much code to the library. nicewasm
  rejects the imports with a message that names the types
  (translator/README.md). The integer routines would be cheap to add from
  compiler_rt, as `float.zig` does, if a program ever needs `__int128`.
- **More pseudo-instructions** (#117): `INC` and a signed compare or
  branch. `INC x` would have to be `MOVE x++, x` to be one word, and
  with `[M]` its flags would describe the old value; `ADD x, x, 1` is
  right, and `DEC` is an instruction. A signed compare is three
  instructions and changes R14 through the `XOR` of ISA.md §9.2, too
  much to hide in one name. The assembler has `JMP`, `CMP`, `TST`,
  `PUSH`, `POP`, `CLR`, and `NOP` instead (ISA.md §10.1). #117 also
  left out a relative branch, which is two words as `JMP label` is;
  #154 added it as `JMPR`, since DECODE predicts only the relative form
  of a jump back (MICROARCH.md §5.4).
- **Dropping the `AND` of a word index without bounds checks** (#119).
  The `AND u, t, 0x3FFFFFFF` after t = i + c / 4 keeps an access right
  when the `i32.add` of `(i << s) + c` wraps modulo 2^32 and still gives
  an address in the memory, as with a negative c, or an i with high bits
  that the shift drops. Without it, bench.c would run about 6% fewer
  steps without checks, but WASM.md would have to let the translator
  assume that the arithmetic of an address does not wrap, which code with
  defined behavior in C, Rust, or Zig meets and wasm in general does not.
  The unchecked code stays exact for every access in the memory. What
  #119 took instead is the fold of an offset into the word operand
  (translator/DESIGN.md).
- **A stack check in each function's prologue** (#72), so that running
  out of NICE stack traps as in wasm. It costs code size and time in
  every call, and the stack has no fixed limit to check against: it runs
  from the start SP down to the end of the program image, which neither
  the core nor the tools know. The compiler's stack in linear memory has
  a size set at build time and lies below the module's data, so an
  overflow there wraps below 0 and traps as out of bounds while the
  bounds checks are on. Detecting a NICE stack overflow in the emulator,
  at no cost on the target, is #132.
- **Multi-result functions, passive segments, and reference types in
  nicewasm** (#104): function types with more than one result, passive
  data and element segments with `memory.init` and `data.drop`, the
  table instructions, and `ref.func`, `ref.null`, and `ref.is_null` in
  code. None of the toolchains of nicebuild.py emit them with its flags.
  Multi-result functions come only from LLVM's experimental multivalue
  ABI or hand-written wasm, passive segments from wasm-ld with threads,
  which NICE does not have, and the rest from Rust or Zig code that uses
  `externref` or tables directly. nicewasm rejects them with an error.
  Should a toolchain's wasm C ABI start to return several results, the
  issue holds the estimates and the design questions.
- **Two windows for the Ethernet frames** (#121), one on the frame at
  the head of the queue and one on the send buffer. Two windows of 8
  words fill the block of 16 and leave no word for the status, the
  lengths, and the chunk. One window with a select bit in `ETH_CHUNK`
  costs a program one write per 8 words when it copies a received frame
  into a reply (DEVICES.md §7).
- **`long double` as wasm32's binary128** (#130). Clang has no
  `-mlong-double-64` for wasm32, so the type is IEEE binary128, and each
  operation is a call such as `__multf3`. A prototype with Zig's
  compiler_rt routines linked into the program worked with no change to
  nicewasm, but all of them take 8210 words, and a divide 5100 steps.
  musl has true binary128 versions of the trigonometric functions only;
  its `expl`, `logl`, and `powl` call the double ones. Out of scope for a
  32-bit hobby CPU: `math.h` has no `long double` functions, and float
  formatting and parsing (#68) work in double.
- **A memory operand that takes a byte address** (#112), such as
  `@c[Rx>>2]` in the C bit of the ALU instructions that ignore it. It
  reaches only the word-index shift of word accesses and byte stores,
  about a third of the steps that the byte windows of DEVICES.md §9 save,
  and none of the cycles of byte loads, since a byte load is a SHIFT
  instruction, which has no C bit. It would be a further departure from
  the 1997 article, and a mux in PREPARE's address path. A mode bit in SR
  has no free bit, and a global mode would change `@R13++` too. The
  windows need no ISA change and leave `hdl/src` as it is.
- **Embench-IoT in `bench/`** (#74). Its harness and the benchmarks
  named in #74, such as `crc32` and `matmult-int`, are
  GPL-3.0-or-later, which the MIT license of this repository cannot take
  in. A port would live in a repository of its own. CoreMark (#143,
  Apache-2.0) gives the figure that small cores publish, and
  `bench/float.c` measures the float library.
- **A flag or an offset for local time in the clock** (#158). A bit of
  `CLOCK_STATUS` that says the clock keeps local time, or a register of
  the time zone's offset, would change `tod.vhd`, the emulator, and the
  boards, and NiceMonMEGA65 has no place to keep an offset across a
  reset. The system's documentation says which time it keeps (DEVICES.md
  §8 and §10). To revisit when a board gets NTP, which needs UTC.
- **A watchdog device that raises NMI** (#157). A system that runs
  unattended needs one to recover alone, and a NICE system runs with a
  person or a host on the debug link, which pauses a program that hangs
  or raises an NMI in it (DEBUG.md §6). It would cost a block of the I/O
  range, a device in the emulator and in `hdl/src` with its tests and
  proofs, and a merge of a second NMI source. A button that raises NMI is
  a board's (DEVICES.md §8). To revisit when a system runs unattended.
