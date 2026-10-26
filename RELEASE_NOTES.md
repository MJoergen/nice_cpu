# Release notes

The release candidates of nice_cpu, newest first. Each section lists the
changes since the one before that a user of the tools or the cores can see.
[doc/HISTORY.md](doc/HISTORY.md) has the full story.

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
  both cores (`make dhry`, `make core-dhry`). The pipelined core does 0.241
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
