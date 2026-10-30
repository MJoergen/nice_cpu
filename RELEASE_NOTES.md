# Release notes

The releases of nice_cpu, newest first: the versions from `V1.0` on, and
the release candidates `RC01` to `RC06` before them. Each section lists the
changes since the one before that a user of the tools or the cores can see.
[doc/HISTORY.md](doc/HISTORY.md) has the full story.

The board repository [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
pins one of these. From `V1.0` on, its tag that moves the submodule, if
the tag meets timing on the MEGA65, has the same name, and its releases
that leave the submodule alone add a third number: `V1.0.1` and `V1.0.2`
pin `V1.0`
([release/RELEASE.md](release/RELEASE.md#version-names)). Its tag that
pins each is:

| nice_cpu | NiceMonMEGA65 |
|---|---|
| `V1.0` | `V1.0` |
| `RC06` | `RC06` |
| `RC05` | `RC05` |
| `RC04` | `RC04` |
| `RC03` | none |
| `RC02` | `RC02` |
| `RC01` | none |

The board's `RC02` pins `4cd869e`, a commit before nice_cpu's `RC02`.
The others pin the tagged commit.

## V1.2 (2026-10-30)

The emulator shows the screen in a window while the program runs, with a
keyboard, a cursor, and the pace of a board (#83). Programs that a monitor
in ROM runs, at `0x8000`, print on the monitor's screen (#87, #88), and
the end of a host's input no longer silences the keyboard (#89).

**Upgrade notes.**

- `_exit` moves from `lib.nasm` into the start-up files, so a program
  that joins `lib.nasm` without a start-up file of the runtime's, and
  calls `exit`, must define `_exit` itself. New global labels:
  `___putc_vector` and `___console_putc` in `lib.nasm`, and `___exit.sp`
  in the `_mon` start-up files (#87, #88).
- `nice_putc` and `nice_print` write through `___putc_vector`, and may
  change R1–R6 and the flags when another routine is behind it. With the
  console, `_nice_putc` still changes nothing, and `_nice_print` changes
  R1 and the flags, no longer R2. The trap report uses R9, not R3. Each
  character costs a step or two more.
- The C library's `nice_putc` is an import from `env`, so every `.wasm`
  file that links `libc.a` was rebuilt, and `make -C runtime/libc wasm`
  rebuilds a program's own.
- The end of the input is the line's. After a break on a board's UART, or
  a half-close or disconnect on the emulator's link, a keyboard's bytes
  still reach the program, and over TCP a new connection starts the input
  anew (#89). A board's FIFO should do the same (SYSTEM.md §5).
- The window is optional. `zig build -Dwindow`, or `make window` in
  `emulator/`, builds niceemu with it, and fetches SDL 3 and compiles it
  from source, with no system packages. A build without `-Dwindow`
  fetches nothing and needs only Zig, as before.
- SYSTEM.md §1 now defines the bytes of the keys, which NiceMonMEGA65's
  keyboards already send, and the cursor at `0xFFFFFF80`–`0xFFFFFF82`,
  numbered as the board's screen registers. In the emulator these words
  stay ordinary memory. The ports of both cores, `wb_dmux`, and the
  devices are as in V1.1.
- The debug link (`hdl/src/debug_link.vhd`) has a side port for a client
  inside the system (#86). Its inputs have defaults, so a board that
  does not connect it builds as before. The protocol is still version 5.
- Zig 0.17.0, as in V1.1.

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
- `--link ADDR:PORT` serves the debug link on ADDR, so that with
  `0.0.0.0` a host on another computer can connect (#84). `--link PORT`
  still serves it on `127.0.0.1` only. The link has no authentication.
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
- `make formal` proves the link with a free side client, and the covers
  run with and without one.

**Benchmarks**

- The cycle counts do not change: 2356816 estimated cycles in the phases
  of the translated benchmark on the pipelined core, as at V1.1. The
  output between the phases costs a call per byte now, outside them. The
  benchmark's module is 8531 words, from 8537, with `nice_putc` an
  import (#88).

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
