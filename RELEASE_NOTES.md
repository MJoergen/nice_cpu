# Release notes

The releases of nice_cpu, newest first: the versions from `V1.0` on, and
the release candidates `RC01` to `RC06` before them. Each section lists the
changes since the one before that a user of the tools or the cores can see.
[doc/HISTORY.md](doc/HISTORY.md) has the full story.

The board repository [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
pins one of these. From `V1.0` on, its tag that moves the submodule, if
the tag meets timing on the MEGA65, has the same name, and its releases
that leave the submodule alone add a third number: `V1.2.1` pins `V1.2`
([release/RELEASE.md](release/RELEASE.md#version-names)). Its tags that
pin each are:

| nice_cpu | NiceMonMEGA65 |
|---|---|
| `V2.0` | none yet |
| `V1.9` | none yet |
| `V1.8` | none yet |
| `V1.7` | none yet |
| `V1.6` | none yet |
| `V1.5` | none yet |
| `V1.4` | none yet |
| `V1.3` | none yet |
| `V1.2` | `V1.2`, `V1.2.1` |
| `V1.1` | `V1.1` |
| `V1.0` | `V1.0` |
| `RC06` | `RC06` |
| `RC05` | `RC05` |
| `RC04` | `RC04` |
| `RC03` | none |
| `RC02` | `RC02` |
| `RC01` | none |

The board's `RC02` pins `4cd869e`, a commit before nice_cpu's `RC02`.
The others pin the tagged commit.

## V2.1 (2026-11-10)

The assembler has the pseudo-instruction `JMPR`, a relative jump
(#154).

**Upgrade notes.**

- `JMPR` is a mnemonic, in any case, so a program that uses it as a
  label or an `.EQU` name does not assemble. No file of the repository
  did.

**Specification and documents**

- ISA.md §10.1: `JMPR target` is `ADD R15, R15, target-next`, where next
  is the address after it, so a loop's back edge that DECODE predicts
  needs no label after the jump. It takes an address, a condition, and
  no modifier. §9.2 and Appendix B name it, and `doc/review/decisions.md`
  no longer lists a relative branch as decided against (#154).

**Assembler (`niceasm`, `nicedis`)**

- `JMPR target` (#154). `nice.vim` shows it.
- `nicedis` writes `ADD R15, R15, c`, with no modifier, as `JMPR` to its
  target, which is a label where the symbols name one. So does
  `disassemble()`, and with it nicedbg's listing. Any other `ADD` to R15
  stays an `ADD`.

**Translator (`nicewasm`)**

- The predicted jump back at the end of a loop is `JMPR top`, where it
  was `ADD R15, R15, top-next` with a label after it, and a short loop
  names its top `:-` (#154). The words are the same.

**Runtime (`runtime/`)**

- The ten loops of `lib.nasm`, `muldiv_soft.nasm`, and `trapmsg.nasm`
  close with `JMPR`, which the pipelined core predicts taken, where they
  closed with `JMP` (#60, #154). The words change, the addresses and the
  steps do not.

## V2.0 (2026-11-09)

`WAIT` waits for an interrupt (#133). Five byte windows let a data
access take a byte address, and nicewasm uses them with
`--byte-windows` (#112). The assembler has anonymous labels (#145), and
the system has a clock of the time of day (#122). The debug link,
version 7, shows the wait and the hidden state of ISA §1.4 (#109), and
has watchpoints (#146). niceemu reports the lowest SP with `--stack`
(#132).

**Upgrade notes.**

- `WAIT` is a mnemonic (ISA §7.5), so a program with a label or an
  `.EQU` name `WAIT`, in any case of letters, no longer assembles until
  it is renamed. The slides' `irq.nasm`, the demo, and the emulator's
  tests renamed theirs. NiceMonMEGA65 follows with
  MJoergen/NiceMonMEGA65#92.
- The word `0x0C600000`, a reserved control command, is `WAIT` now,
  where it was reserved.
- Both cores have new ports, all with defaults that keep a system of
  V1.9 working: `waiting_o` and `wstep_o` for the wait; `in_service_o`,
  `after_rti_o`, `saved_pc_o`, and `saved_sr_o` for the hidden state;
  and the generic `G_WATCHES`, 0 to 4, default 0, with the inputs
  `wch_addr_i` and `wch_en_i` and the outputs `wch_hit_o` and
  `wch_pc_o` for the watchpoints. `debug_link.vhd` takes them on
  inputs that default to 0. NiceMonMEGA65 follows with
  MJoergen/NiceMonMEGA65#93, MJoergen/NiceMonMEGA65#98, and
  MJoergen/NiceMonMEGA65#99.
- The debug link is version 7, a new minor of major 0 (DEBUG.md §9).
  Its registers start at `0xFFFFFFD0`, where they started at
  `0xFFFFFFE0`, so a link request to `0xFFFFFFD0`–`0xFFFFFFDF` reaches
  the link, where it reached the system's words, which SYSTEM.md
  reserved for I/O and no system used. A host of version 6 works
  unchanged.
- SYSTEM.md has two new parts of the address map: the clock at
  `0xFFFFFF46`–`0xFFFFFF49` (§10), `hdl/src/tod.vhd` on the cores, and
  the byte windows of §9, data addresses with top nibble 1 to 5. The
  windows are a property of the memory, in `hdl/sim/wb_mem.vhd`, and
  leave `hdl/src` as it is. A program whose data is at an address of
  top nibble 1 to 5, as R14 with E = 1 or with N set as a pointer, or a
  VBASE of `0x100000`–`0x5FFFFF`, reaches the windows there.
  NiceMonMEGA65 follows with MJoergen/NiceMonMEGA65#90 and
  MJoergen/NiceMonMEGA65#97.
- `nice_screen_clear` writes `0x000FFF20`, white on black, where it
  wrote `0x20` (#148). A program that reads a cleared word back sees
  the difference.
- With 4 watchpoints, the pipelined core misses the budget of its
  inputs and outputs in the `timing` flow on the MEGA65 (#149). With
  none, the default of `G_WATCHES`, it meets it in both flows. So
  NiceMonMEGA65, which does not wire the watchpoints yet, keeps the
  slack of its ports until it turns them on.
- Zig 0.17.0, as in V1.9.

**Specification and documents**

- ISA §7.5: `WAIT`, control command 3. It completes, and the processor
  runs no instruction until an NMI or IRQ is pending, also while E = 0
  or `in_service` = 1. Then the request is taken if it can be, and
  otherwise the instruction after the `WAIT` runs, so a test of a flag
  with E = 0 followed by `?Z WAIT` loses no wakeup (#133).
- ISA §10: anonymous labels. A lone `:` is a label, `:-` refers to the
  nearest one above, `:+` to the nearest one below, and each more sign
  to one further (#145). Appendix B has a row for them.
- ISA §8.2: a store through another address to a word that is fetched,
  as aliasing and the windows allow, leaves undefined which value runs.
- SYSTEM.md §9: the byte windows. A data access at A with top nibble 1
  to 5 reaches word (A >> 2) AND `0x03FFFFFF`, whole, as a byte, or as
  a halfword, zero- or sign-extended, and a write through a byte or
  halfword window changes only that part (#112).
- SYSTEM.md §10: the clock of the time of day, the seconds since the
  Unix epoch in 64 bits and the microseconds within the second, with a
  snapshot on a read of `CLOCK_USEC` and a set of all three at once. It
  runs while the processor is held, paused, halted, or waiting, and
  only a reset of the system sets it to 0 (#122).
- SYSTEM.md §3: a waiting processor runs, so the cycle counter, the
  microsecond counter, and the timer count on.
- DEBUG.md, version 7: bit 6 of the control register reads the wait;
  bits 7 and 8 `in_service` and `after_rti`; bits 9 and 10 the pending
  NMI and IRQ; `0xFFFFFFD0` and `0xFFFFFFD1` `saved_pc` and `saved_sr`
  (#109). Four watchpoints at `0xFFFFFFD4`–`0xFFFFFFDB`, each an address
  with an enable for reads and one for writes, stop the processor after
  the step that hit, with the notice `w` and bit 9 of the stop register
  (#146).
- decisions.md records the operand variants of #112, the bank select
  weighed against #109, a watchpoint that stops before the access, and
  Embench-IoT.

**Assembler (`niceasm`, `nicedis`)**

- `WAIT`, with no operands, and `nicedis` disassembles it (#133).
- Anonymous labels, `:` with `:-` and `:+` (#145). They are not in
  `--symbols`. `nice.vim` shows them, and `WAIT`.
- A `:` in a string or inside a term keeps the message it had before.

**Emulator (`niceemu`)**

- `WAIT`. A wait step counts in the cycle counter and the timer, and
  with `--step-time` in the microsecond counter. The emulator jumps
  over wait steps at once, with the same result as one by one. A wait
  that no request can end stops a run with "Stopped: waiting with no
  request to come", exit status 2, unless the run has the window or the
  link (#133).
- The byte windows of SYSTEM.md §9 (#112), and the clock of §10, on the
  host's time, or with `--step-time` one microsecond per step from 0
  (#122).
- `--link` serves version 7: the wait, the hidden state, and the
  watchpoints (#109, #146).
- `--stack` prints the lowest value of R13 since its first change, and
  the words between it and the first value (#132).
- The report names the trap code 8 of nicewasm.
- The version is 2.0.0.

**Debugger (`nicedbg`)**

- `status` shows a wait for an interrupt, and a line for the interrupt
  state: in a routine, with `saved_pc` and `saved_sr`, after `RTI`, and
  the pending NMI and IRQ (#109, #133).
- `wp` sets a watchpoint on writes, reads, or both, and lists them, and
  `wpd` disables them. The `w` notice shows the instruction that hit
  (#146).

**Runtime (`runtime/`)**

- `nice.h` has `nice_clock`, `nice_clock_isset`, and `nice_clock_set`,
  and `time()` returns the clock's seconds, or −1 while it holds no
  time (#122).
- `nice_screen_clear`, and `screenClear` and `screen_clear` of the Zig
  and Rust wrappers, write a blank in white on black, `0x000FFF20`,
  where they wrote `0x20`, black on black, on which the cursor of
  SYSTEM.md §1.4 could not show (#148). `NICE_SCREEN_BLANK`,
  `screen_blank`, and `SCREEN_BLANK` name the word.

**Translator (`nicewasm`)**

- `--byte-windows` accesses the memory through the windows. A byte
  load or store is one `MOVE`, and so is a halfword or a word whose
  alignment `--trust-alignment` trusts or the translator knows (#112).
  `nicebuild.py` passes the option on. In niceemu steps, with bounds
  checks and `--trust-alignment`, `bench` takes 1451191, from 1697021,
  and Dhrystone 199384, from 256400.
- With `--byte-windows`, nicewasm refuses a memory of more than 4096
  pages, and `___wasm_start` traps with code 8 if the memory ends past
  the windows' reach.

**FPGA cores (`hdl/`)**

- Both cores run `WAIT`: the pipelined core in a new mode with FETCH
  stopped, the multi-cycle core in BOUNDARY. A pause goes first and
  returns to the wait, and a step of a waiting core is one wait step
  (#133).
- `tod.vhd` is the clock of SYSTEM.md §10, a Wishbone slave of four
  words, proven by `formal/tod.sby` (#122).
- `debug_link.vhd` is version 7, with the hidden state (#109) and the
  watchpoints (#146). With `G_WATCHES` above 0, each data access is
  checked, the vector read of an entry included, and a hit goes ahead
  of a pause request and an interrupt in WRITE. While a watchpoint is
  enabled, PREPARE holds the first read of an instruction until the one
  before has left WRITE, which costs speed only then.
- `make sweep` with one interrupt per run passes on both cores at
  5423a5b: pcfx in 4132 runs, with an NMI before each of its 2066
  steps and an IRQ before 2054 (12 have E = 0); sidefx in 14537 runs,
  with an NMI before 7168 of 7444 steps and an IRQ before 6701 (668
  have E = 0; 276 and 75 steps have no vector table and were left
  out).
- `make timing` on the MEGA65, in the default flow, with 4 breakpoints
  and 4 watchpoints: the core alone has +0.396 ns of slack, from
  +0.219 ns, and its inputs and outputs leave 2.251 and 2.539 ns, from
  2.503 and 2.674 ns. In the `timing` flow they leave 1.174 and 2.035
  ns, which misses the budget of 1.5 and 2.2 ns, with the core at
  +0.102 ns. The worst paths run from `pause_i` and from the
  watchpoints' `w_r.wch_any`, which fa8b2fa added (#149). With no
  watchpoints the `timing` flow leaves 2.176 and 2.422 ns, with the
  core at +0.077 ns, which meets it.

**Benchmarks**

- No change for `bench.c` as built by default: 2339271 estimated
  cycles on the pipelined core, as in V1.9.

## V1.9 (2026-11-07)

The math unit counts the bits of A and takes the square root of C
(#129), and the float library uses it. The C library gets `math.h`
from musl (#130) and the float conversions of `printf`, `scanf`, and
`strtod` (#68). Zig and Rust programs can use floats and their math
functions (#142). The pipelined core meets the input budget on the
MEGA65 again (#141).

**Upgrade notes.**

- The math unit's words `0xFFFFFF2A`–`0xFFFFFF2C` and
  `0xFFFFFF3C`–`0xFFFFFF3E`, which read 0, now hold `CLZ`, `CTZ`, and
  `POPCNT` of A, and the square root of C with its remainder. The
  ports of both cores, `wb_dmux`, the devices, and the debug link are
  as in V1.8. A system that instantiates `mpu.vhd` gets the words by
  rebuilding.
- `lib.nasm` now needs `muldiv_mpu.nasm` or `muldiv_soft.nasm` after
  it: `__clz`, `__ctz`, and `__popcnt` moved there, and `__clz64`,
  `__ctz64`, and `__popcnt64` call them. A program joined with
  `lib.nasm` alone no longer assembles. NiceMonMEGA65 follows with
  MJoergen/NiceMonMEGA65#89.
- Every program that calls `printf` grows by 3085 words. Every program
  that calls `scanf`, even for integers alone, is joined with
  `float.nasm`, as `nicebuild.py` and the test Makefiles now do.
- In the `timing` flow on the MEGA65, `dbus_ack_i` is within the
  budget of 1.5 ns again, so the miss in the V1.8 notes no longer
  holds.
- Zig 0.17.0, as in V1.8.

**Specification and documents**

- SYSTEM.md §2 has the new words of the math unit: the bit counts of
  A, with 32 for `CLZ` and `CTZ` of 0, and `ISQRT64_Q`, `ISQRT64_R_LO`,
  and `ISQRT64_R_HI`, the root of C and its 33-bit remainder (#129).
- ABI.md and `nice.h` have `nice_isqrt64`, floor(√x) of a 64-bit
  value, on the math unit or in software.
- decisions.md records why there is no `long double`.

**Emulator (`niceemu`)**

- It computes the new words of the math unit. The probe
  `test/mpubits.nasm` checks them against a hand table, and `mpu` and
  `mpu64` read the words that were spare.
- The version is 1.9.0.

**Runtime (`runtime/`)**

- `__clz` searches by halves, in 19 steps for any value but 0, from up
  to 100. `__clz`, `__ctz`, and `__popcnt` are 3 steps on the math unit
  in `muldiv_mpu.nasm`. `_nice_isqrt64` is 4 steps there, and 584 in
  `muldiv_soft.nasm`.
- The float library takes its f32 quotient from one 64-bit divide and
  its f32 square root from `nice_isqrt64`. It is translated with
  `--no-mpu`, so it joins with either muldiv file. It is 6578 words,
  from 6583.
- The C library has `math.h`: musl 1.2.5's functions, unchanged, in
  double and float, within 1 ulp of the true value but `atan2f`'s 1.5,
  and the classification macros. No function sets `errno`. All 56
  functions are 23392 words (#130).
- `printf` has `%e`, `%f`, `%g`, and `%a`, and their capitals, by
  musl's `fmt_fp`, which needs no float library. `scanf` has the same
  conversions, and `stdlib.h` has `strtod`, `strtof`, and `atof`, by
  musl's `floatscan` in double, with five fixes listed in
  `floatscan.c` (#68).
- `nice.rs` has the trait `Float`, which gives a `no_std` program the
  math methods of `std` for `f64` and `f32`. Zig needs nothing (#142).
- `make -C runtime/libc fuzz` checks `printf`'s floats against Python,
  `strtod` and `strtof` against exact arithmetic, and the math
  functions against musl on the host and the true values.

**FPGA cores (`hdl/`)**

- `mpu.vhd` computes the new words in both cores. The bit counts are
  registered from A each cycle, and a read of one waits as a product
  does. The square root takes 2 bits of C a cycle, 33 cycles from a
  write to C or D. `tb_mpu` checks them against a model written
  another way, and `make formal` proves them for every A and every C.
  The probe `mpubits` runs on both cores, also on a memory that
  stalls.
- WRITE reports its cause to the fetch statistics without the paths
  from `dbus_ack_i`, and the pipeline derives it a cycle later, the
  same cycle for cycle. `make timing` on the MEGA65, in the default
  flow: the core alone has +0.219 ns of slack, from +0.343 ns, and its
  inputs and outputs leave 2.503 and 2.674 ns, from 2.524 and 2.715 ns.
  In the `timing` flow the inputs leave 1.683 ns, from 1.344 ns, which
  meets the budget, and NiceMonMEGA65 V1.8 meets 100 MHz on the R6 by
  +0.040 ns, from −0.135 ns (#141).

**Benchmarks**

- `float.c` is a benchmark of float code, in five phases with known
  results, checked against `floatexpected.py`. Against the library of
  V1.8 it takes 1058329 instructions, −15.3%, and 1917617 cycles on
  the pipelined core, −16.7% (#129).
- `make words` prints the size of the math module too.
- No change for `bench.c`: 2339271 estimated cycles on the pipelined
  core, as in V1.8.

## V1.8 (2026-11-07)

The performance counters count five events of a program, the same on
the emulator and both cores (#126), and the pipelined core's fetch
statistics say where its cycles go, by cause (#125, #137). The
debugger on the link moves here from NiceMonMEGA65, to `debugger/`
(#134). A program's code can run from a ROM (#138).

**Upgrade notes.**

- The fetch statistics move from `0xFFFFFF50`–`0xFFFFFF7F` to
  `0xFFFFFF60`–`0xFFFFFF7F`, 32 words with new meanings. The event
  counters take `0xFFFFFF4A`–`0xFFFFFF53`, which read 0 before.
- `stats_o` of the pipelined core has new fields: the cause of each
  cycle and of each flush, and the stalls of both buses. Its old
  fields for FETCH's buffer are gone. `perf.vhd` has 32 words, from
  16, and new inputs for the core's `retire_o` and data bus, which
  default to no events. `fetch_stats.vhd` has 32 words, from 48. The
  ports of both cores but `stats_o`, `wb_dmux`, the other devices, and
  the debug link are as in V1.7. NiceMonMEGA65 follows the new map
  with MJoergen/NiceMonMEGA65#85.
- The pipelined core leaves a system less time on `dbus_ack_i` and
  `instret_o`. In the `timing` flow on the MEGA65 it misses the input
  budget (FPGA cores below, #141).
- `nicedbg.py --port` runs at 230400 baud by default, as macOS has no
  higher rate. NiceMonMEGA65 runs its UART at 2000000 until
  MJoergen/NiceMonMEGA65#88, so it needs `--baud 2000000` until then.
- The start-up files of the runtime define `___wasm_trap_vector` and
  `___putc_vector`, which left `lib.nasm`. A program that joins
  `lib.nasm` with start-up code of its own defines them.
- Zig 0.17.0, as in V1.7.

**Specification and documents**

- SYSTEM.md §3 has the event counters: the data reads, the stores, the
  skipped instructions, the jumps, and the interrupt entries and
  `INT`, each a 64-bit counter with a snapshot. They count what the
  program does, not what the processor does (#126).
- MICROARCH.md §8.1 describes the new fetch statistics: 15 causes
  that sum to the cycles, the flushes by cause, and the stalls of both
  buses (#125).
- WASM.md has the rules for a module whose code runs from a ROM: its
  mutable globals and memory go in RAM, and `___wasm_start` copies
  their initial values there at every start (#138).
- SYSTEM.md §5 says that NiceMonMEGA65 has the font RAM, the character
  ROM, and the base from its V1.6 (#136).

**Emulator (`niceemu`)**

- It counts the five events of SYSTEM.md §3. The probe
  `test/events.nasm` checks them against hand-worked counts.
- `--no-font` makes the font RAM and the character ROM ordinary
  memory, to compare a run with a core, whose test memory has
  neither.
- `tools/nicetap.py` joins the UDP socket of `--eth-udp` to a TAP
  device on Linux, so that a program in the emulator is on a real
  network (#135).
- `make test` runs `zig fmt --check` (#139).
- The version is 1.8.0.

**Debugger (`debugger/`)**

- `nicedbg.py` is the generic part of NiceMonMEGA65's `tools/mon.py`:
  the shell, with `--tcp` and `--port`. `nicelink.py` is the link and
  its transports, and `nicebin.py` loads a `.bin` and its `.sym`. A
  board imports them, with hooks for its own transports and memory
  (#134). `make test` runs them on `niceemu --link`.
- Fixed since the move: a second eof no longer kills it, `bd` refuses
  a number that is no breakpoint, a notice that arrives while
  `pending()` reads the PC is no longer lost, and a send to a full
  input buffer gives up after 2 s instead of hanging.

**Translator (`nicewasm`, `nicebuild.py`)**

- `nicewasm --ram ADDR` translates a program's module whose code runs
  from a ROM, with `--ram-bytes` for the size of its memory.
  `nicebuild.py --ram ADDR` builds such a program from C, Zig, or Rust.
  A program that uses floats, `--monitor`, and `--memory-pages` are
  errors with it (#138).

**Runtime (`runtime/`)**

- The trap and putc vectors are in the start-up code, so that the
  library holds no word that is written. The start-up code grows by
  two words.

**FPGA cores (`hdl/`)**

- `perf.vhd` has the event counters, from the core's `retire_o` and
  its own data bus, and `make formal` proves them.
- The pipelined core reports a cause for each cycle on `stats_o`,
  through two stages of registers, and `fetch_stats.vhd` counts them.
  On cputest the causes match the cycle model of `bench/pipecycles.py`.
- `make random-sweep` passes on both cores, seeds 1 to 1000: the
  random programs halt less often, and the testbench's timer and
  `irq_compare.py` were wrong, not the cores (#58, #140).
- `make timing` on the MEGA65 meets the budget in the default flow:
  the core alone has +0.343 ns of slack, from +0.503 ns in V1.7, and
  its inputs and outputs leave 2.524 and 2.715 ns, from 3.056 and
  2.836 ns. The `timing` flow, which NiceMonMEGA65 builds with, leaves
  the inputs 1.344 ns, from 2.204 ns, which misses the budget of 1.5
  ns. The fetch statistics by cause (179d19e, #125) took the
  difference. #141 is to win it back. `hdl/README.md` has the new
  slacks of the ports on both boards.

**Benchmarks**

- `make compare` sets the model's cycles beside the pipelined core's
  by cause, in 12 groups, which agree to the cycle but for two pairs
  counted on the other side of a boundary (#137).
- No change: 2339271 estimated cycles on the pipelined core, as in
  V1.7.

## V1.7 (2026-11-05)

The network station and a port for Ethernet frames join the I/O
range, in SYSTEM.md, the emulator, and as devices of the cores (#124,
#121). The demo of NiceMonMEGA65's ROM moves here, to `demo/`, and
runs in `niceemu --window` (#91).

**Upgrade notes.**

- `0xFFFFFFB0`–`0xFFFFFFBF` is the network station, and
  `0xFFFFFFC0`–`0xFFFFFFCF` the port for Ethernet frames. Both were
  reserved words, ordinary memory in the emulator. A program that kept
  data there loses it. No program of the repository did.
- SYSTEM.md's "Systems built on the FPGA core" is §8, from §6. The
  ninth review keeps its references to §6, with a note that says so.
- The I/O address map changes, and there are two new devices,
  `hdl/src/net_regs.vhd` and `hdl/src/eth_regs.vhd`, for a board to
  connect. The ports of both cores, `wb_dmux`, the other devices, and
  the debug link are as in V1.6. NiceMonMEGA65 has the station at
  `0xFFFFFF98`–`9D` and moves it with MJoergen/NiceMonMEGA65#78.
- Zig 0.17.0, as in V1.6.

**Specification and documents**

- SYSTEM.md §6 is the network station: the IP and MAC addresses, the
  counts of frames received and sent, and `NET_STATUS`, with the TCP
  port of the debug link and a bit for a connected host. Only a system
  reset sets the addresses, not a start or the link's clear (#124).
- SYSTEM.md §7 is the port for Ethernet frames: a queue of 4 frames
  received, one send buffer, and one window of 8 words into them, which
  `ETH_CHUNK` moves. A frame starts at byte 2 of its buffer, so that the
  fields of IPv4 and UDP fall on words. The station keeps ARP for its
  address, the pings to it, and the TCP of the link, and the program
  gets the other frames for it (#121).
- DEBUG.md's start names the station, which keeps its addresses and
  counts, and the port, whose frame being sent finishes first.
- decisions.md records why `NET_IP` does not give the address of
  `--link`, why the port has one window and not two, the features of
  wasm that the translator will not support (#104), no stack check in
  each prologue (#72), and no `long double` or `__int128` from C (#70).

**Emulator (`niceemu`)**

- The station's addresses are registers with their reset values. The
  counts read 0, and `NET_STATUS` follows `--link`. The probe
  `test/net.nasm` and `test/link.py` check them.
- The port takes frames from `--eth-in FILE`, at the write that enables
  it and at each send, so a run is the same each time, and from a UDP
  socket with `--eth-udp` and `--eth-peer`. `--eth-out FILE` writes the
  frames sent. The station answers ARP and ping before the queue. The
  probe `test/eth.nasm` and `test/udp.py` check it.
- The version is 1.7.0.

**Translator (`nicewasm`, `nicebuild.py`)**

- Function types with more than one result, passive segments, the
  table instructions, and the reference instructions in code are not
  planned. Their error messages, and those of any other unsupported
  opcode, drop "yet" (#104).

**FPGA cores (`hdl/`)**

- `net_regs` holds the station's addresses for the board, and takes
  the counts and the status from it. `eth_regs` has the port's
  registers and buffers, with a port to the board's station. The net
  and eth probes run on both cores against `niceemu`, with
  `sim/eth_sim.vhd` as the station, and `make formal` proves both.
- The cores do not change. `make timing` on the MEGA65 meets the budget
  with V1.6's figures: the core alone has +0.503 ns of slack, and its
  inputs and outputs leave 3.056 and 2.836 ns to the system around it.

**Demo (`demo/`)**

- The demo moves here from NiceMonMEGA65: the typewriter, the key
  codes, the font and colors, the counters, the comet, and F11's
  self-test, which shows the station's addresses and `NET_STATUS`. It
  runs in `niceemu` behind the runtime's stand-in for a monitor, and
  `build/demo.bin` is the program alone, for a board to join behind
  its own. A board gives its own text with `TEXT=`. `make test`
  compares its screens with the hand-checked `test.expected` (#91).

**Benchmarks**

- No change: 2339271 estimated cycles on the pipelined core, as in
  V1.6.

## V1.6 (2026-11-05)

The emulator's window draws from a font in the address space: a font
RAM of 256 glyphs that a program writes, Spleen as a character ROM
beside it, and a font base that selects which the window shows (#115).
The translator writes a source operand 0 as R0, which saves its
constant word (#127), and its output uses the pseudo-instructions of
ISA.md §10.1 (#128).

**Upgrade notes.**

- In the emulator, `0xFFFE0000`–`0xFFFE1FFF` is the font RAM, which keeps
  only bits 15..0 of a write, and `0xFFFE2000`–`0xFFFE3FFF` is the
  character ROM, which reads Spleen and drops a write. Both were
  ordinary memory. A program that kept data there loses it. No program
  of the repository did.
- `0xFFFFFF86` is the font base, among the words reserved for I/O. In
  the emulator it is ordinary memory that the window reads, as the
  cursor's words are. It is 0 at the start, so the window shows Spleen,
  as before, until a program writes it.
- The ports of both cores, `wb_dmux`, the devices, and the debug link are
  as in V1.5.
- Zig 0.17.0, as in V1.5.

**Specification and documents**

- SYSTEM.md §1.8 is the font: the layout of a glyph, 32 words of 16
  pixels with the leftmost in bit 15, the font RAM, the character ROM,
  and the base, whose value 0 shows the ROM and `0xFFFE0000` the RAM.
  The other values are reserved, and show the ROM. The font RAM and the
  base are 0 at the start and after the link's clear (#115).
- SYSTEM.md's memory map has the two ranges and the base, and §6 says
  that a board draws from the same font, and that until
  MJoergen/NiceMonMEGA65#71 the ranges alias NiceMonMEGA65's RAM.

**Emulator (`niceemu`)**

- `--window` draws each cell from the font that the base selects, and
  redraws a cell when its word, its cursor, or its glyph changes. A
  write to a glyph shows at the next redraw, and a write to the base
  changes the whole screen (#115).
- Instruction fetches, `--dump`, and the debug link see the font RAM and
  the ROM as a data access does. `--screen` and `--color` still print
  the screen's codes as text.
- The probe `test/font.nasm` reads the ROM, copies a glyph into the font
  RAM, and selects it.

**Translator (`nicewasm`, `nicebuild.py`)**

- A source operand 0 is written as R0, which reads 0 without a constant
  word: `MOVE x, 0` is `MOVE x, R0`, the `CLR x` of #117, in one word.
  The benchmark's module is 8438 words, from 8531, Dhrystone's 12360,
  from 12517, `test/safe.zig` 5903, from 5932, and the float library
  6583, from 6895. The steps do not change (#127).
- The output writes the idioms as the pseudo-instructions of ISA.md
  §10.1: `JMP`, `CMP`, `TST`, `PUSH`, `POP`, `CLR`, `NOP`, `RET`, and
  `CALL`, in the functions, the helpers, and the start code. Each
  assembles to the same words, so the `.bin` files do not change (#128).

**FPGA cores (`hdl/`)**

- The cores do not change. `make timing` on the MEGA65 meets the budget
  with the figures of V1.5.

**Benchmarks**

- The phases of the translated benchmark take 2339271 estimated cycles
  on the pipelined core, from 2356816, 0.7% fewer, since fewer
  constant words leave fetch behind. The steps do not change (#127).
- `cycprof.py` counts the runs of a `CALL` line, two instructions, once
  for each call (#128).

## V1.5 (2026-11-04)

The emulator and the FPGA have an SD card controller at
`0xFFFFFFA0`–`0xFFFFFFAF` (#107). A program reads and writes the
sectors of a card through a buffer of one sector, and `niceemu` gives a
slot an image file. SYSTEM.md's memory map assigns a block of the I/O
range to each device that is planned (#123).

**Upgrade notes.**

- In the emulator, the 16 words at `0xFFFFFFA0`–`0xFFFFFFAF` are the SD
  card's registers, where they were memory. A program that kept data
  there loses it. No program of the repository did.
- `0xFFFFFFB0`–`0xFFFFFFCF` and `0xFFFFFF46`–`0xFFFFFF49` are reserved
  for the network station (#124), Ethernet frames (#121), and the clock
  of the time of day (#122). The emulator keeps them as memory until
  each device lands.
- The ports of both cores, `wb_dmux`, and the debug link are as in V1.4.
  A start of the processor resets the SD card controller with the other
  devices, but lets a Write that has begun finish.
- Zig 0.17.0, as in V1.4.

**Specification and documents**

- SYSTEM.md §5 is the SD card controller: the registers `SD_CSR`,
  `SD_LBA`, `SD_CHUNK`, `SD_ERROR`, `SD_SELECT`, `SD_LAST`, and
  `SD_SLOTS`, and the buffer of 128 words, read and written 8 at a time
  through `SD_BUF0`–`SD_BUF7`. The commands are Init, Read, and Write.
  No read has a side effect, so the debug link needs no rule for it. It
  says what busy, the slots, reset, the debug link, and interrupts do to
  the controller (#107).
- SYSTEM.md: the former §5, the systems built on the FPGA core, is §6,
  and lists the SD card slots of the MEGA65 and the Nexys4DDR.
- SYSTEM.md's memory map: `0xFFFFFFA0`–`AF` for the SD card,
  `0xFFFFFFB0`–`BF` for the network station, `0xFFFFFFC0`–`CF` for
  Ethernet frames, and `0xFFFFFF46`–`49` for the clock. `0xFFFFFFD0`–`DF`
  stays free (#123).
- DEBUG.md §6 and §7.3: a start resets the controller, but a Write that
  has begun finishes first, and the controller runs on while the
  processor is paused.
- `doc/review/decisions.md`: a data port with a cursor, a buffer mapped
  as 128 words, a DMA engine, and commands that take time in the
  emulator were decided against.

**Emulator (`niceemu`)**

- `--sd0 FILE` and `--sd1 FILE` put a card in slot 0 or 1, whose
  sectors are the file's. The emulator has 2 slots, with images or
  without. A card is SDHC, write-protected when the file cannot be
  written, and "changed" at the start. A command ends in the write that
  starts it, and a Write goes to the file at once (#107).
- niceemu refuses to start with an image that is empty or whose size is
  not a multiple of 512 bytes. A failed read or write of the file is
  error 5.

**FPGA cores (`hdl/`)**

- `src/sd_regs.vhd` is the controller's registers and buffer, for
  `G_SLOTS` slots. It passes a command to a protocol engine of the
  board: a start with the command, the slot, and the sector, a byte port
  into the buffer, and done with the error. `busy_o` is high while a
  command runs. With `G_HOLD_ACK`, the ACK of the write that starts a
  command waits for its end (#107).
- `sim/sd_sim.vhd` is an engine over image files, held in memory and
  never written back. `tb_core` maps the controller with it, and the
  probe `emulator/test/sd.nasm` runs on both cores against niceemu, also
  on a stalling memory and with held pauses.
- `make formal` proves the bus and engine ports of `sd_regs`, with the
  held ACK and without it, and `tb_sd_regs` tests a reset during a
  command and a card taken out.
- The cores do not change. `make timing` on the MEGA65 meets the budget
  with V1.4's figures: the core alone has +0.503 ns of slack, and its
  inputs and outputs leave 3.056 and 2.836 ns to the system around it.

**Benchmarks**

- The cycle counts do not change.

## V1.4 (2026-11-03)

The assembler has the pseudo-instructions `JMP`, `CMP`, `TST`, `PUSH`,
`POP`, `CLR`, and `NOP` (#117), and products in expressions (#118).
Without bounds checks, the translator folds an access's offset into the
word operand (#119), and its random test checks the memory at the end
(#120). The emulator's README names a host tool for the debug link (#92).

**Upgrade notes.**

- `JMP`, `CMP`, `TST`, `PUSH`, `POP`, `CLR`, and `NOP` are mnemonics, in
  any case, so a program that uses one as a label or an `.EQU` name does
  not assemble. No file of the repository did. Nothing else changes: the
  ports of both cores, `wb_dmux`, the devices, the address map of
  SYSTEM.md, and the debug link are as in V1.3.
- `*` in an operand that follows a space still starts a comment, so
  `4 * x` assembles as `4`. The assembler now warns about it (#118).
- Without bounds checks, WASM.md no longer defines an access past the
  end of the memory, also when base + offset passes 2^32, which used to
  wrap to the bottom of the memory (#119). An access in the memory is as
  before.
- Zig 0.17.0, as in V1.3.

**Specification and documents**

- ISA.md §10.1 defines the seven, each one instruction: `JMP target` is
  `MOVE R15, target`, `CMP a, b` is `SUB[M] R0, a, b`, `TST a` is
  `MOVE[M] R0, a`, `PUSH x` is `MOVE @--R13, x`, `POP x` is
  `MOVE x, @R13++`, `CLR x` is `MOVE x, R0`, and `NOP` is `MOVE R0, R0`.
  None takes a modifier. §9.1, §9.2, and Appendix B name them (#117).
- `doc/review/decisions.md`: `INC`, a signed compare, and a relative
  branch were decided against.
- ISA.md §10.2: a constant may be an expression of `+`, `-`, and `*`.
  `*` binds tighter, a leading sign is on the first product, and an
  `.EQU` name is its value as a whole, so with `N .EQU 2+3`, `4*N` is
  20. §10.1 says that `4 *x` is `4` and a comment (#118).
- WASM.md: without bounds checks, an access whose bytes are all in the
  memory is as with them, and one past the end reads or writes NICE
  words that it does not define (#119).
- `doc/review/decisions.md`: dropping the `AND` that takes a word index
  modulo 2^30 without bounds checks was decided against. It would save
  about 6% of the benchmark's steps, but it is needed when the `i32.add`
  of an address wraps and still gives one in the memory (#119).
- DEBUG.md and `emulator/README.md`, Debug link: NiceMonMEGA65's
  `tools/mon.py --tcp` is a host tool for the link that works with
  `niceemu --link`: it loads, runs, pauses, steps, sets breakpoints, and
  disassembles, with labels from `--symbols` (#92).

**Assembler (`niceasm`)**

- The seven assemble as ISA.md §10.1 says, with their operands checked
  as those of the instruction (#117). `nicedis` writes the instructions,
  never the pseudo-instructions. `nice.vim` highlights them.
- Expressions take `*`, as in `4*label` or `.BLK 2*N`. `INT`, `.BLK`,
  and `.RES` check the value before it wraps, as before. A `*` comment
  after a constant operand gives a warning, since a product has no
  spaces (#118).

**Translator (`nicewasm`, `nicebuild.py`)**

- With `--no-bounds-checks`, an offset that is a multiple of 4 goes into
  the word operand, and the word index and the byte in the word come
  from the base, with no `ADD`: for byte and halfword accesses, and for
  word accesses on the fast path. The benchmark takes 0.3% fewer steps
  in 0.9% fewer words, and with `--trust-alignment` too, 0.4% fewer steps
  in 3.4% fewer words (#119).
- `test/fuzz.py` compares the linear memory at the halt with the model's,
  word for word. The memory starts with a pattern in which no two words
  are alike, and `main` starts with accesses at array addresses that
  wrap. A translator that drops the `AND` of #119 now fails every seed
  that `make test` runs, where it passed all of them (#120).

**FPGA cores (`hdl/`)**

- `hdl/src` does not change. `make timing` on the MEGA65 meets the
  budget with V1.3's figures: the core alone has +0.503 ns of slack, and
  its inputs and outputs leave 3.056 and 2.836 ns to the system around
  it.

**Benchmarks**

- The cycle counts do not change: 2356816 estimated cycles in the phases
  of the translated benchmark on the pipelined core, as at V1.3, and the
  benchmark's module is 8531 words. The sources use the new
  pseudo-instructions, which assemble to the same words (#117).

## V1.3 (2026-11-03)

The assembler has `CALL` and `RET` (#93). Debug link version 6 lets a
host write R1–R15 while the processor is paused (#102), and over TCP
holds a host back instead of losing its console bytes (#110). Rust and Zig
programs have a heap (#69, #105) and read console input a line at a time
(#106). The translator handles tail calls (#103) and can trust the
alignment hints (#113). The emulator's microsecond counter keeps the
host's time (#114), and its window runs as fast as the host can (#116).

**Upgrade notes.**

- `CALL` and `RET` are mnemonics, so a program that uses either as a
  label or an `.EQU` name does not assemble. No file of the repository
  did.
- The debug link is version 6 (#102). A write of R0–R15 while the
  processor is not paused gets `e04`, where it got `k`, and a `W` that runs
  from the devices into R0–R15 while held or halted writes nothing. A host
  of version 5 never wrote these words, which were read only, so it works
  as before.
- Over TCP, a console byte that finds the input buffer full waits up to
  50 ms for room, and the bytes behind it wait too, before it is lost with
  `o` (#110). A host that sends no more than the free-space register
  allows never sees the wait. One that sends requests behind unpaced
  console bytes may wait longer than 100 ms for the answer.
- `debug_link` has the input `rx_flow_i` and the generic `G_WAIT`
  (#110). The input defaults to 0, so a board that does not connect it
  loses a byte at once, as before. A board ties it high while it serves
  the link over TCP.
- Both cores have the inputs `reg_we_i`, `reg_idx_i`, and `reg_data_i`,
  and `debug_link` the outputs `reg_we_o`, `reg_idx_o`, and `reg_data_o`
  (#102). The inputs default to 0, so a system that does not connect them
  works as before, but a host's write of R1–R15 does not reach the
  core. A board connects the link's outputs to the core's inputs.
- The emulator's microsecond counter counts the host's time, not one
  microsecond per step (#114). A test whose expected output has a count
  of it worked out by hand needs `--step-time`. A program that divides
  the cycle counter by the microsecond counter gets the host's rate of
  steps, which varies.
- With `--window`, the emulator runs as fast as the host can, where it
  ran one step per microsecond (#116). A program that keeps time by the
  timer or by counting steps runs tens of times faster; `--speed 1000000`
  gives it the old pace. A program that waits on the microsecond counter
  runs as before. While a program polls the console or `TIME_LO` in a
  loop, niceemu sleeps, so a wait on the counter may end up to 1 ms late.
- `wb_dmux`, the devices, and the address map of SYSTEM.md are as in V1.2.
- Zig 0.17.0, as in V1.2.

**Specification and documents**

- ISA.md §10.1 defines the pseudo-instructions `CALL target` and `RET`:
  `ADD @--R13, n, R15` then `MOVE R15, target`, where n is the size of
  the `MOVE` in words, and `MOVE R15, @R13++`. A condition applies to
  both words of a call. §9.1 says the constant is the size of the jump,
  and Appendix B lists them (#93).
- `doc/review/decisions.md`: a macro facility was decided against, since
  a text macro cannot pick the constant of a call.
- DEBUG.md: debug link version 6. R1–R15 take a write while the
  processor is paused, with the rules of a register-direct write of ISA
  §4.3, and leave the hidden state of ISA §1.4 alone. A write of R0–R15
  while not paused is answered with the new error `04` (#102).
- DEBUG.md §1, §4, §5, §7, and §9: on a transport with flow control, a
  console byte that finds the input buffer full waits up to 50 ms for
  room before it is lost with `o`, and after that `o` the bytes are lost
  at once until the buffer has room. A packet with no console byte ahead
  of it is never held. SYSTEM.md §5 says so for a board's FIFO (#110).
- SYSTEM.md §5 describes the aliasing of a RAM of 2^N words, with 64K
  and 128K words as the examples, and says how a program learns the
  size. ABI.md says what "up to the SP" means under a monitor on such
  a system (#111).
- SYSTEM.md §3: the emulator's microsecond counter counts the host's
  monotonic time while the processor runs, and with `--step-time` one
  microsecond per step (#114). §1.6: the window runs as fast as the host
  can and sleeps in a wait loop, and `--speed` paces it (#116).

**Assembler (`niceasm`)**

- `CALL target` and `RET` assemble as ISA.md §10.1 says, with 1 or 2 for
  the constant from the target's mode, so `CALL R2` is right where the
  written idiom needs `ADD @--SP, 1, PC` (#93). `nicedis` writes the two
  instructions, never `CALL` or `RET`. `nice.vim` highlights them.

**Emulator (`niceemu`)**

- `--link` serves debug link version 6: R1–R15 take a write while the
  processor is paused, and a write of R0–R15 while it is not gets `e04`
  (#102).
- A console byte that finds the input buffer full waits up to 50 ms for
  room, and niceemu reads nothing more from the connection meanwhile, so
  a flood of console bytes to a program that reads loses nothing (#110).
- The microsecond counter counts the host's time, less the time the
  processor is held, paused, or halted, so a program that waits on it
  waits real time with or without `--window`. `--step-time` counts one
  microsecond per step, as before (#114).
- `--window` runs as fast as the host can by default, as without the
  window, and sleeps while the program polls the console or `TIME_LO` in
  a loop, so a program that waits for a key leaves the host's cores idle.
  `--speed N` paces the run, for a program that keeps time by the timer
  or by counting steps (#116).

**Runtime and C library**

- `nice.rs` has `Heap`, a `GlobalAlloc`, so a `#![no_std]` Rust program
  can use `Vec`, `String`, `Box`, and the rest of the `alloc` crate: first
  fit, as the C library's `malloc`, with alignments above 8, and growth
  with `memory.grow` up to `--memory-pages` (#69).
- `nice.zig` has `nice.heap`, a `std.mem.Allocator` that works as
  `nice::Heap` does, for `ArrayList` and the rest of the standard
  library. Zig's own `wasm_allocator` takes a 64 KB page per size class,
  too much for a board with 64K words (#105).
- `nice.zig` has `readLine(buf)` and `nice.rs` has `read_line(buf)`. They
  read a line of console input into a buffer, without the `"\n"` and a
  `"\r"` just before it. A longer line is cut off and its rest dropped, and
  a last line with no `"\n"` is returned, then `null` or `None`. In Rust,
  bytes that are not UTF-8 end the string at the last whole character
  (#106).

**Translator (`nicewasm`, `nicebuild.py`)**

- `return_call` and `return_call_indirect` translate to a jump, after
  the stack arguments go into the function's own and the frame and the
  saved registers go, with the checks of `call_indirect` (traps 6 and 7).
  A callee with more words of stack arguments than the function is
  called instead. A callee whose results differ from the function's is
  an error (#103).
- `nicebuild.py` turns on the tail-call feature of clang, Zig, and rustc,
  so `[[clang::musttail]]` and `@call(.always_tail, ...)` compile. The
  compilers then also emit `return_call` for a call just before a
  return (#103).
- `--trust-alignment`, for `nicewasm` and `nicebuild.py`: an access of 4
  or 8 bytes whose alignment hint is 4 bytes or more is taken to be at a
  multiple of 4, without the test of DESIGN.md. A misaligned access then
  reads or writes the word that holds its first byte. With
  `--no-bounds-checks`, the benchmark takes 13% fewer steps and 10% fewer
  cycles in 28% fewer words, and Dhrystone 11%, 8%, and 34% (#113).

**FPGA cores (`hdl/`)**

- Both cores take a register write while paused, with R0 unchanged and
  bit 24 of R14 set, and go on from a written R15 (#102). The pipelined
  core takes it in WRITE's `PAUSED_ST`.
- `debug_link` is version 6: a write of R1–R15 while paused drives the
  core's register write and the copy that a read returns, and a write of
  R0–R15 while not paused gets `e04`. The side client gets `side_err_o`
  for it (#102).
- The proofs of both cores, of WRITE, and of the link cover the writes,
  and `tb_link` and `tb_debug_link` test them (#102).
- `debug_link` holds a console byte that finds `free_i` at 0 for up to
  `G_WAIT` cycles, 50 ms, while `rx_flow_i` is high, with `rx_ready_o`
  low. Its proof bounds the wait, and `tb_debug_link` and `tb_link` test
  it (#110).
- `make timing` on the MEGA65 meets the budget: the core alone has
  +0.503 ns of slack, and its inputs and outputs leave 3.056 and 2.836 ns
  to the system around it, where V1.2's release check had 0.314, 2.254,
  and 2.456 ns.

**Benchmarks**

- The cycle counts do not change: 2356816 estimated cycles in the phases
  of the translated benchmark on the pipelined core, as at V1.2, and the
  model agrees with the core. The benchmark's module is 8531 words, as at
  V1.2. `hand.nasm` and `simple.nasm` use `CALL` and `RET`, which
  assemble to the same words as before (#93).

## V1.2 (2026-10-31)

The emulator shows the screen in a window while the program runs, with a
keyboard, a cursor, and the pace of a board (#83). Programs that a monitor
in ROM runs, at `0x8000`, print on the monitor's screen (#87, #88), and
the end of a host's input no longer silences the keyboard (#89).

**Upgrade notes.** A program that runs on the emulator with the
runtime's start-up files needs no change, and a C program only a
rebuild. In the order of who must act:

- `_exit` moves from `lib.nasm` into the start-up files, so a program
  that joins `lib.nasm` without a start-up file of the runtime's, and
  calls `exit`, must define `_exit` itself. New global labels:
  `___putc_vector` and `___console_putc` in `lib.nasm`, and `___exit.sp`
  in the `_mon` start-up files (#87, #88).
- The C library's `nice_putc` is an import from `env`, so every `.wasm`
  file that links `libc.a` was rebuilt, and `make -C runtime/libc wasm`
  rebuilds a program's own.
- `nice_putc` and `nice_print` write through `___putc_vector`, and may
  change R1–R6 and the flags when another routine is behind it. With the
  console, `_nice_putc` still changes nothing, and `_nice_print` changes
  R1 and the flags, no longer R2. The trap report uses R9, not R3. Each
  character costs a step or two more.
- The end of the input is the line's. After a break on a board's UART, or
  a half-close or disconnect on the emulator's link, a keyboard's bytes
  still reach the program, and over TCP a new connection starts the input
  anew (#89). A board's FIFO should do the same (SYSTEM.md §5).
- With `--window`, the emulator runs one step per microsecond, so a
  timer period of P cycles lasts P microseconds, not P/100 as at 100 MHz,
  and `--speed` sets another rate. Without `--window` it runs as fast as
  the host can, as before.
- The window is optional. `zig build -Dwindow`, or `make window` in
  `emulator/`, builds niceemu with it, and fetches SDL 3 and compiles it
  from source, with no system packages. A build without `-Dwindow`
  fetches nothing and needs only Zig, as before. Zig 0.17.0, as in V1.1.
- `--link ADDR:PORT` serves the debug link on another address than
  `127.0.0.1`, so that a host on another computer can connect (#84).
- For a board: SYSTEM.md §1 now defines the bytes of the keys, which NiceMonMEGA65's
  keyboards already send, and the cursor at `0xFFFFFF80`–`0xFFFFFF82`,
  numbered as the board's screen registers. In the emulator these words
  stay ordinary memory. The ports of both cores, `wb_dmux`, and the
  devices are as in V1.1.
- For a board: the debug link (`hdl/src/debug_link.vhd`) has a side port for a client
  inside the system (#86), and `rx_resume_i`, a pulse that starts the
  line's input anew after a break, for a board that serves the link over
  TCP (#90). The new inputs have defaults, so a board that does not
  connect them builds as before. The protocol is still version 5.

**Specification and documents**

- SYSTEM.md §1 specifies the window: the screen in 16×32 characters, the
  cursor, the keys, and the pace of one step per microsecond. With the
  window, a console read returns 0 while no byte waits, as a board's
  does. With `--link`, the keys and the host's bytes share the input
  buffer, as a board's keyboard and UART share its FIFO. DEBUG.md §7 says
  that a read does not wait then.
- DEBUG.md §7: the emulator serves the link on `127.0.0.1` unless it is
  given another address (#84).
- DEBUG.md §6: while the processor runs, a system should return the
  current R0–R15, as the emulator always did (#85). §3: a system may have
  a client of its own for the debug registers and the memory, with no
  lock between it and the host (#86).
- ABI.md, "Programs under a monitor": a program that a monitor in ROM
  loads at `0x8000` and calls on its stack, with R1 = its putc routine
  or 0, R2 = `argc`, and R3 = `argv`, returns to it with `main`'s result
  in R1, and may use the memory from `0x8000` up to the SP it was called
  with. At the return the monitor may rely on SP and R1 only (#87).
  Device routines: `___putc_vector`, which `nice_putc` and `nice_print`
  write through (#88).
- SYSTEM.md §1 and §5, and DEBUG.md §1 and §7: a break, a half-close, or
  a disconnect ends the line's input, not the keyboard's, and over TCP
  the connection is the line (#89).
- Two documents are new. doc/TOOLCHAIN.md has the tools, what each reads
  and writes, the steps that build a program, and the host tools they
  need; it was the README's Toolchain section. CONTRIBUTING.md has the
  tests and the rules for a change, for human contributors. The README is
  for users: it sums up the emulator, says how to build it, and runs a
  worked example. `hdl/src/`, `sim/`, `test/`, and `formal/` each have a
  README that lists their files.
- A second worked example in the README runs
  `doc/intro/examples/keys.nasm` in the window. It writes a title in
  color, and echoes the keys typed on the screen with a blinking cursor.
  `make -C doc/intro test` runs it from a file of keys.

**Emulator (`niceemu`)**

- `--window` shows the screen in a window of 1280×800 pixels, which
  scales when resized, with the font Spleen 16×32, as on NiceMonMEGA65.
  The console reads the file of `--input`, if given, then the keys typed
  into the window, and not stdin. A read returns 0 while no byte waits.
- The run is paced at one step per microsecond, so that the microsecond
  counter keeps the host's time. The timer still counts one cycle per
  step, so its period of P cycles lasts P microseconds, not P/100 as at
  100 MHz. `--speed N` sets another
  rate, and `--speed 0` runs as fast as the host can.
- At the halt or the step limit, the report is printed, and the window
  stays until it is closed. Closing it before ends the run with the new
  exit status 4.
- `--window` works with `--link`: the window shows the screen over every
  run, also while the processor is held, and closing it ends niceemu.
- `make window-test` runs `test/window.py` on SDL's dummy video driver,
  with no display, and CI runs it in a job of its own.
- `--link ADDR:PORT` serves the debug link on ADDR, an IPv4 address or an
  IPv6 one in brackets, so that with `0.0.0.0` a host on another computer
  can connect (#84). `--link PORT` still serves it on `127.0.0.1` only.
  The link has no authentication.
- With `--window --link`, keys typed after the host's input has ended
  reach the program, and a read returns `0x200` only while no byte
  waits. A new connection clears the end of the input, so a second host
  can type to a program that read the end (#89).

**Runtime and C library**

- `start_mon.nasm`, `start_wasm_mon.nasm`, and `start_wasm_trap_mon.nasm`:
  the start-up code for a program under a monitor (#87). `exit` is the
  `_exit` of the start-up file: the `HALT` after `main` in the plain
  files, and a return to the monitor in these. `test/monitor.nasm` stands
  in for a monitor in the tests, which `make programs` in `hdl/` runs on
  the cores too.
- `___putc_vector`: `nice_putc`, `nice_print`, and the C library's
  output, `printf` included, go through it, so that the start-up code
  under a monitor sends them to its screen (#88). The trap report follows
  it too. `nice.h` declares `nice_putc` as an import from `env`, as it
  does `exit`.
- `nice_getc`, `getchar`, and the `getc` of `nice.zig` and `nice.rs`
  return the end once the line's input has ended; a keyboard's bytes may
  still come after it (#89).

**Translator (`nicewasm`, `nicebuild.py`)**

- `nicebuild.py --monitor` builds a program for a monitor, with
  `start_wasm_trap_mon.nasm`, or `start_wasm_mon.nasm` with
  `--no-trap-report` (#87). `test/build.py` runs one after the runtime's
  stand-in for a monitor.

**FPGA cores**

- The debug link returns the core's registers while the processor runs,
  not those of the last stop, so a host sees R15 move (#85).
- The debug link has a side port, word by word, for a client inside the
  system, such as an on-board debugger: `side_valid_i`, `side_we_i`,
  `side_addr_i`, `side_data_i`, `side_done_o`, `side_err_o`, and
  `side_data_o` (contract g in its header). The host keeps the UART or
  TCP line while the client works, and gets the notices of its stops
  (#86). A host's word now waits for the link to take it, so a word that
  comes during another client's access is not lost.
- The debug link has `rx_resume_i`, a pulse that starts the line's input
  anew after a break: `eoi_o` falls, and the host's console bytes reach
  the program again. A board that serves the link over TCP pulses it when
  a host connects, as the emulator starts the line anew at a connection
  (#90). Nothing else changes: the breakpoints, the hold, and the pause
  stay. A resume wins over a break in the same cycle. DEBUG.md §7 lists
  it among the rules the link asks of its board, and says which of its
  TCP rules are the emulator's.
- `make formal` proves the link with a free side client, and the covers
  run with and without one. It proves that `eoi_o` is low in the cycle
  after `rx_resume_i`.
- `hdl/Makefile` keeps `/opt/Xilinx/2025.1/Vivado/bin/vivado` as the
  default of `VIVADO`, so that `make timing` works as is on the machine
  that has it; another machine sets `VIVADO` (#61).

**Benchmarks**

- The cycle counts do not change: 2356816 estimated cycles in the phases
  of the translated benchmark on the pipelined core, as at V1.1. The
  output between the phases costs a call per byte now, outside them. The
  benchmark's module is 8531 words, from 8537, with `nice_putc` an
  import (#88).

**Release**

- Each release has niceemu for x86_64 Linux as files to download: a
  static build without the window, and a build with it for glibc 2.31
  or later (#101). `.github/workflows/release.yml` builds them with
  `make -C emulator dist`, runs the tests on each, and creates the
  release from the tag's section of these notes.
- `release.py tag` refuses a tag whose version differs from that in
  `emulator/build.zig.zon`, and `release.py section` prints the section
  of a tag.

## V1.1 (2026-10-28)

A disassembler, `errno` in the C library, and debug link version 5, in
which a clear ends the halt. The long simulations run in nvc, so
`make slow` takes 4 minutes instead of about 8 hours at V1.0.

**Upgrade notes.**

- The debug link is now version 5: when a clear starts, bit 1 of the
  control register, the halt reason, and the stop register read 0
  (#79). `debug_link.vhd` and `niceemu --link` both do this. Its ports
  do not change, and a host of versions 1 to 4 works with it. This is a
  new minor of major 0 (DEBUG.md §9).
- No other interface change: the ports of both cores, `wb_dmux`, the
  devices, and the address map of SYSTEM.md are as in V1.0. A system
  built for V1.0 needs no change in its VHDL.
- `make slow` and `release.py check` need nvc, tested with 1.20 here
  and 1.23 in CI. `make slow SIM=ghdl` runs them in GHDL instead.
- Zig 0.17.0, as in V1.0.

**Specification and documents**

- DEBUG.md §9 sets the rules for versions (#81). The version byte is a
  major in bits 7–4 and a minor in bits 3–0. A new minor keeps every
  host of an older minor of its major working. The table of versions
  moves to §9.
- WASM.md, "Traps", installs a trap handler in NICE assembly, not in C
  code that does not build (#75).
- The seventh review, `doc/review/seventh-repository-review.md`, of the
  changes since V1.0. Its fixes are in the sections below.
- Open items, undecided questions, and ideas are GitHub issues.
  `TODO.md` only points there, and `doc/review/decisions.md` lists what
  was decided against.

**Emulator (`niceemu`)**

- With `--link`, a pause ends a console read that waits for input
  (#56). The processor pauses before the read, with nothing taken, and
  a go on runs it again. A step at such a read pauses again at once. An
  instruction that reads the console twice gets back the byte its first
  read took.
- `--link` serves debug link version 5.

**Assembler (`niceasm`)**

- `nicedis.py` disassembles a `.bin` file into `.nasm` in the layout of
  `nicefmt.py`, which `niceasm` assembles back to the same words (#80).
  With `--symbols` it uses the labels of a symbol file, read as
  `niceemu --symbols` reads it. `--start` and `--end` are decimal, or
  hex with `0x`.

**Runtime and C library**

- `errno.h`, with `EINVAL`, `EDOM`, `ERANGE`, and `EILSEQ` (#82).
  `strtol` and `strtoul`, and so `atoi` and `atol`, set `errno` to
  `ERANGE` on an overflow.
- `strtol` and `strtoul` convert nothing for a base other than 0 and 2
  to 36, and set `errno` to `EINVAL`. Before, a base above 36 read past
  the end of the string.

**FPGA cores**

- `debug_link.vhd` follows version 5. No other change to `hdl/src` but
  in `G_FORMAL` and comments.
- `make timing` has its own budgets for the inputs and the outputs of
  the core: 1.5 and 2.2 ns, from what NiceMonMEGA65 measured in its
  system at V1.0 (#57).
- `SIM=nvc` runs the core simulations in nvc, with the same traces as
  GHDL (#77). `make test` stays in GHDL, which is faster on short runs.
- `make strides` sweeps the interrupt programs with strides 17, 31, and
  64 in minutes. `make sweep`, one interrupt per run, takes hours and is
  run only after a change to the interrupt path.
- `make formal` proves every assumption of a stage proof of the stage
  it names. CI runs it with the OSS CAD Suite, and the bounded check of
  the whole pipelined core covers 12 cycles, not 8.

**Benchmarks**

- The cycle counts do not change: 2356816 estimated cycles in the phases
  of the translated benchmark on the pipelined core, as at V1.0.

**Release**

- `make slow` runs both cores at once, in nvc, and leaves `hdl make
  programs` to CI (#76). It took 4 minutes on 20 CPUs.
- CI runs the programs in nvc, one job per core, on Node 24 actions and
  Ubuntu 24.04. It checks the digest of the OSS CAD Suite it downloads.
- The checklist names the debug link's version among the interface
  changes, and its row in DEBUG.md §9 among the documents.
- A release here that misses timing on the MEGA65 gets no release of
  NiceMonMEGA65.

## V1.0 (2026-10-27)

The first release that is not a candidate. The cores, the debug link, and
the address map are those of RC06; this release moves the tools to Zig
0.17, lays out NICE assembly in columns, and names the releases as
versions.

**Upgrade notes.**

- Zig 0.17.0 is now the only supported version. Zig 0.15 no longer builds
  `niceemu` or the Zig runtime modules.
- No interface changes: the ports of both cores, `wb_dmux`, the devices,
  `debug_link.vhd`, and the address map of SYSTEM.md are as in RC06. A
  system built for RC06 needs no change in its VHDL.
- Releases are now named `Vmajor.minor`. NiceMonMEGA65's release with
  the same name pins this one, and its releases that keep the submodule
  add a third number, such as `V1.0.1`
  ([release/RELEASE.md](release/RELEASE.md#version-names)).

**Specification and documents**

- DEBUG.md's table of protocol versions lists version 4, the breakpoints
  of RC06.
- All NICE assembly in the documents and the slides is laid out in
  columns.

**Emulator (`niceemu`)**

- Builds with Zig 0.17.0, on its `std.Io` interface. Its behavior, the
  trace format, and the debug link do not change.

**Assembler (`niceasm`)**

- Every `.nasm` file in the repository is laid out in columns: the label
  in column 0, the condition in column 8, the mnemonic in column 16, the
  operands in column 24, and the comment in column 40, with spaces only.
  The binaries do not change.
- `nicefmt.py` checks that layout, and with `--write` fixes a file. It
  keeps every word and comment. `make test` checks every `.nasm` file.
- `nice.vim` is a Vim syntax file for `.nasm` files (assembler/README.md).

**Runtime and C library**

- The Zig modules are rebuilt with Zig 0.17. The float library is 6895
  words, not 7079, and `test/safe.zig` 5932, not 5156.

**Translator (`nicewasm`, `nicebuild.py`)**

- The output of `nicewasm` follows the column layout.
- The README no longer warns against Zig's own wasm backend
  (`-fno-llvm`): with Zig 0.17, `runtime/test/nicezig.zig` built with it
  prints the same as with LLVM.

**FPGA cores**

- No change to `hdl/src`. `make timing` compares the MEGA65 slacks with a
  budget in `hdl/test/timing_budget.py`: the core alone meets 10 ns, and
  its ports leave 1.5 ns to the system around it. A miss warns and fails
  nothing.
- README.md shows a badge for 100 MHz on the MEGA65, which NiceMonMEGA65
  writes for its last tag. RC06 met it there: WNS +0.376 ns.

**Benchmarks**

- The cycle counts do not change: 2356816 estimated cycles in the phases
  of the translated benchmark on the pipelined core, as at RC06.

**Release**

- `release.py tag` names the tag `V1.0`, then the next minor version, and
  refuses a name that is not `Vmajor.minor` or does not come after the
  last tag.
- `release.py check` runs `make timing` and records the budget result in
  the stamp, without gating on it. NiceMonMEGA65 (RELEASE.md step 7)
  follows the tag and gates nothing.

## RC06 (2026-10-26)

**Upgrade notes.**

- Both cores have two new inputs without defaults, `brk_addr_i` and
  `brk_en_i`, and a generic `G_BREAKS` (0 to 8, default 0). A system
  without breakpoints ties `brk_en_i` to all zeros. Otherwise connect them
  to the new outputs `brk_addr_o` and `brk_en_o` of `debug_link.vhd`, with
  the same `G_BREAKS` on both.
- A core with breakpoints can pause on its own: `paused_o` rises while
  `pause_i` is 0. It goes on only after `pause_i` has been 1 and is 0
  again. `debug_link.vhd` does this.
- `run_i` of the performance counters and the fetch statistics must now
  be low while the core is paused, too: drive it with
  `not paused_o and not halted_o` of the core, and low while it is held.
- The debug link is now version 4. A host checks the version register at
  `0xFFFFFFF2` before it uses a breakpoint.

**Specification and documents**

- DEBUG.md: debug link version 4 adds up to eight breakpoints (#55), the
  notice `x`, and the stop register, which lasts until the next go on. A
  connection clears the breakpoints.
- SYSTEM.md: the cycle and microsecond counters stop while the core is
  paused. The microsecond counter is exact for any clock of 1 MHz or more.

**Emulator (`niceemu`)**

- `--link` serves debug link version 4, with four breakpoints.
- A signal ends a console read, so Ctrl-C works while a program waits for
  input.

**Assembler (`niceasm`)**

- `--symbols` is refused when it names the input or the output.

**Runtime and C library**

- The trap report prints `trap ?: unknown trap` for a code above 7.
- `CLOCKS_PER_SEC` is a `clock_t`.

**Translator (`nicewasm`, `nicebuild.py`)**

- `nicebuild.py` has `--asm`, rejects a stack or memory size that is not
  positive, checks the output path early, names the failing script, and
  says so when the compiler is not installed.

**FPGA cores**

- Both cores and `debug_link.vhd` have breakpoints (#55). DECODE of the
  pipelined core compares the addresses ahead, so the cycle counts do not
  change.
- `debug_link.vhd` drops a packet whose checksum has a high digit that is
  not hex, and none of its bytes reaches the program, as in niceemu.
- The formal checks prove the multi-cycle core's ports by k-induction, and
  WRITE's interrupt ports of the pipelined core for every cycle.

**Benchmarks**

- The cycle counts do not change: 2356816 estimated cycles in the phases
  of the translated benchmark on the pipelined core, as at RC05.

**Release**

- `release/RELEASE.md` is the release checklist, and `release/release.py`
  scripts its mechanical parts. `make release-check` runs the gates.
- `make wasmcheck` rebuilds the checked-in `.wasm` files and compares them.
- CI runs the programs on each core in three shards.

## RC05 (2026-10-26)

**Upgrade notes.**

- Both cores have a new input, `pause_i`. Tie it to `'0'` if the system does
  not pause the core.
- `debug_link.vhd` has three new ports without defaults: the output
  `pause_o`, and the inputs `paused_i` and `halt_reason_i`. Connect them to
  the core's `pause_i`, `paused_o`, and `halt_reason_o`.
- `halted_o` of both cores now rises only once no bus cycle is open, as
  `paused_o` does, so a system can take over the buses when it rises.
- The debug link is now version 3. A host checks the version register at
  `0xFFFFFFF2` before it uses the pause or the single step.

**Specification and documents**

- DEBUG.md: debug link version 2 adds a pause, and version 3 adds a single
  step (#53). A counter snapshot may be taken on a link read while the core
  is paused (#52). The debug UART runs at 2 Mbaud.

**Emulator (`niceemu`)**

- `--link` serves debug link version 3, with the pause and the single step.

**Runtime and C library**

- `fgets` with `n` = 1 stores `""` and returns `s`.
- `stdlib.h` defines `EXIT_SUCCESS` and `EXIT_FAILURE`.
- The trap report names the traps as the emulator does.

**Translator (`nicewasm`, `nicebuild.py`)**

- `nicebuild.py --symbols` keeps the names of a Zig program.
- `nicebuild.py` no longer passes the caller's `MAKEFLAGS` to the commands
  it runs.

**FPGA cores**

- Both cores have `pause_i`, `paused_o`, and `halt_reason_o` (#48). While
  `pause_i` is 1, the core stops at the next step boundary. One cycle of
  `pause_i` = 0 while paused runs exactly one step. `paused_o` and
  `halted_o` rise only once no bus cycle is open, so a system can take over
  the buses. `halt_reason_o` gives the reason of the halting step.
- `debug_link.vhd` serves the pause and the single step.
- Inside the pipelined core, DECODE, PREPARE, and WRITE now hand over with
  valid/ready handshakes. The cycle counts do not change.

**Benchmarks**

- Dhrystone refuses fewer than one run.

## RC04 (2026-10-24)

**Upgrade notes.**

- `fetch_stats.vhd` has a new input, `run_i`, which defaults to `'1'`. Drive
  it with "the core is running", as for `perf.vhd`, so that the statistics
  stop while the core is held or halted.

**Specification and documents**

- DEBUG.md specifies the debug link, a byte protocol to load, run, halt,
  and inspect a program over a UART or TCP.
- SYSTEM.md: the input FIFO of a system drops input that arrives while the
  processor is held or halted, and a full FIFO sends the link's `o` notice
  (#47).
- A `W` request that wraps past `0xFFFFFFFF` is answered with error `02`.

**Emulator (`niceemu`)**

- `--link PORT` serves the debug link over TCP instead of running the
  program once. With PORT 0, it picks a free port.

**Translator (`nicewasm`)**

- A loop now closes with a conditional `ADD R15, R15, offset`, which the
  pipelined core predicts taken. The benchmark takes 1.2% fewer cycles.

**FPGA cores**

- `debug_link.vhd`, the byte-stream part of the debug link, with a formal
  proof.
- The pipelined core predicts a backward conditional `ADD PC, PC` taken.
- The fetch statistics stop while the core is held or halted, as the other
  counters do.
- Fixed: a request of the debug link could start a memory access while the
  board was still clearing memory, after a dropped `W` started the clear.

**Benchmarks**

- `simple.nasm` is `hand.nasm` with `vm` and `strings` as a simple C compiler
  would emit them.
- `hand.nasm` and `simple.nasm` close their loops so the predictor takes
  them.

## RC03 (2026-10-24)

**Upgrade notes.**

- `niceemu` has no step limit by default. It was 100000000. Use `-n N` to
  set one.
- `perf.vhd` has a new generic, `G_CLK_HZ`, which defaults to 100000000.
  Set it to the system's clock frequency, or the microsecond counter runs
  at the wrong rate.
- New global labels in the runtime: `_exit`, `___trap_report`, and the
  `___trap.*` labels of `trapmsg.nasm`. A program that defines one of them
  does not assemble together with the runtime. `start_wasm_trap.nasm` is a
  new start-up file.

**Specification and documents**

- SYSTEM.md adds a microsecond counter, `TIME_LO` and `TIME_HI` at
  `0xFFFFFF44` and `0xFFFFFF45`.
- The reserved I/O words are ordinary memory for data accesses in the
  emulator.

**Assembler (`niceasm`)**

- `--symbols FILE` writes the labels to a file.

**Emulator (`niceemu`)**

- The microsecond counter, which counts one microsecond per step.
- `--symbols FILE` reads the labels from `niceasm --symbols`. After a halt
  other than `HALT`, it prints the location by label, and after a wasm
  trap, the trap code and its location.

**Runtime and C library**

- New: `assert.h`, `time.h` with `clock`, `exit`, `rand`, `srand`, `stdin`,
  `stdout`, `stderr`, and the `FILE` functions, and `strcspn`.
- `trapmsg.nasm` prints the code and address of a wasm trap.
- mchess, a chess engine, is a test of the C library.

**Translator (`nicewasm`)**

- `nicebuild.py` builds C, Zig, or Rust sources into a `.bin` file in one
  step. It installs the trap report and can write a `.sym` file.

**FPGA cores**

- The microsecond counter, derived from the clock frequency `G_CLK_HZ`, so
  that it is exact at any frequency.

**Benchmarks**

- Dhrystone 2.1 runs on the C library and is checked on the emulator and
  both cores (`make dhry`, `make core-dhry`). The pipelined core does 0.247
  DMIPS/MHz.

## RC02 (2026-10-23)

**Upgrade notes.**

- Interrupt requests of one kind that merge now keep the vector of the
  first request. Before, which vector was kept was left open.
- `perf.vhd` has a new input, `run_i`, which defaults to `'1'`. Drive it
  with "the core is running", so that the cycle counter stops while the
  core is held or halted.

**Specification and documents**

- ISA.md states the memory model: data accesses are sequentially
  consistent, and no fence or barrier is needed.
- ISA.md states that same-kind interrupt requests merge, that each number
  in a program must be below 2^32, the syntax of symbols and the stricter
  rule for labels, that `*` starts a comment only at the start of a word,
  and that control instructions take no constant words. SYSTEM.md says the
  read counter is 0 at the start of a run, and that a reset does not
  clear it.
- SYSTEM.md says how a system built on the FPGA core may differ from the
  emulator.
- The cycle counter and the timer's COUNT stop when the core halts.
- The repository is under the MIT license. The terms of the 2004 example
  programs are recorded.

**Assembler (`niceasm`)**

- Fixed: an operand with many `[` took quadratic time.
- The README documents the overlap rule, the size of `.BLK`, the output
  order, and other behavior.

**Emulator (`niceemu`)**

- A request that finds one of its kind pending keeps the older vector.
- The console is flushed after each write on a terminal, and the output is
  flushed on SIGINT, SIGTERM, and SIGHUP.
- The README documents the exit statuses, the loader, the dump format, and
  memory use.

**Translator (`nicewasm`)**

- Rejects more invalid modules, and a negative `--library-memory`.
- No traceback for a long name subsection or an output that cannot be
  written.
- Fixed: nested blocks took quadratic time.

**FPGA cores**

- Both cores follow the rule that merged requests keep the first vector.
- `hdl/README.md` states the rules for driving the pipelined core, and what
  a system may add to its paths.
- The performance counters have `run_i`, and the cycle counter stops while
  it is low.

## RC01 (2026-10-22)

The first release candidate. It holds:

- **The specification**, [doc/ISA.md](doc/ISA.md): the programmer's model,
  instruction format, addressing modes, interrupts, memory, assembler
  syntax, and `.bin` format. [doc/SYSTEM.md](doc/SYSTEM.md) gives the
  devices in the I/O range: console, math unit, performance counters, and
  timer.
- **`niceasm`**, the assembler, one Python 3 script with no dependencies. It
  reproduces the 2004 example `.bin` files byte for byte.
- **`niceemu`**, the emulator, in Zig 0.15, with a trace format for
  comparing it with the cores, and `--color` for the screen colors.
- **The runtime library**: start-up code, integer and floating-point
  routines, and a small C library (`printf`, `string.h`, `malloc`, and a
  few more). [runtime/ABI.md](runtime/ABI.md) gives the C ABI.
- **`nicewasm`**, which translates WebAssembly into NICE assembly, so C,
  Zig, and Rust programs run on NICE.
- **Two FPGA cores** in VHDL-2008: a simple multi-cycle core and the
  pipelined core of [doc/MICROARCH.md](doc/MICROARCH.md). Both pass every
  comparison with the emulator in GHDL, and formal checks cover their ports,
  four stages of the pipeline, the devices, the shifter, and the ALU. The
  example board design is in
  [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65).
- **A benchmark**, six kernels timed with the performance counters, in
  translated C and written by hand.
- **A beginner's introduction** in slides, [doc/intro/](doc/intro/).
