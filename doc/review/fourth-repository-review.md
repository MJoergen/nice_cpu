# Fourth review of the repository, at commit b7b46f4

Reviewed on 2026-10-20: the state of the repository at commit b7b46f4 ("ISA: SYSTEM.md §1 says this repository has no UART"), six commits after the fixes of [third-repository-review.md](third-repository-review.md) were closed. Little changed since, so the question asked this time was a different one: not whether the parts fit, but what the tests do not reach. For each rule of ISA.md, SYSTEM.md, ABI.md, and WASM.md: is there a test that would fail if the rule were broken? For each tool: which lines and branches does `make test` never run, and which inputs would run them? And for the cores: what could the formal checks prove that they do not?

**How it was checked.** Five readers worked in clones of their own, one for each tool and one for the devices of the FPGA core, and I took the cores. Each tool's reader measured the coverage of its tests, line and branch coverage with coverage.py for the Python tools, with the subprocesses the test scripts start hooked in; the Zig emulator by reading, since no coverage tool for Zig is installed, and by a mutation check, each new test against a plausible one-line bug. Each made a table of every rule of the specification against the test that would fail without it, hunted corner cases against the code, wrote tests for the gaps with expected values worked out by hand and explained in the tests' comments, and reported bugs without fixing them. For the cores I read every formal job and every stage against the properties that no job states, and wrote the jobs of §6. Then I ran `make test`, `make typecheck`, `make -C hdl lint`, `make -C hdl formal`, and `make -C hdl programs` on both cores, with the new tests in.

The tests are in the repository now, in the directories of their tools, and `make test` runs them. Four of them fail, one in `assembler/` and three in `runtime/libc/`, because they found bugs (§1.2, §3.2 to §3.4); they are written to the correct expectation, and pass once the bugs are fixed.

## Summary

**Four bugs, at the edges of the tools, none in the cores, the emulator, or the translator.** The assembler prints a Python traceback for an output file it cannot open (§1.2). In the C library, `snprintf(NULL, 0, ...)` prints to the console (§3.2), `malloc` of a size near 2³² returns a pointer into the heap (§3.3), and `strtoul` does not negate a value that is exactly `ULONG_MAX` (§3.4). Each is a few lines, and each has a test now.

**The tests were already good where they looked, and did not look everywhere.** Line coverage of the assembler and the translator was 97% and 99% before, so the gaps were not in the lines but in what the lines were given: operands in registers where the tests used constants, modes and options never combined, edge values, and rules with no test that would fail. The readers closed 29 gaps in the assembler, 17 in the emulator, 22 in the translator, and 11 in the runtime (§1 to §4), each a test with a hand-derived expectation. Thirteen supported wasm instructions had no test at all, all float conversions (§4.1). The fuzzer of the translator now makes globals, bulk memory, `return`, `nop`, and typed `select`, and runs in two more modes (§4.3). Eight of the new emulator probes run on both cores too (§5.1).

**The formal checks grew where TODO.md said they were missing.** DECODE of the pipelined core is proven for every cycle, and its proof discharges what the proof of PREPARE assumed of it (§6.2). The shifter, the ALU, and the flags are proven against ISA.md §5 and §6 for every input, as is the pipelined core's shifter against the multi-cycle core's, and the block compares behind the store-into-fetched-code flush against the ranges they stand for (§6.1). A halted pipelined core makes no data read and no new fetch, for every cycle, and no store, for the bounded cycles (§6.3). The devices have jobs of their own (§6.5). With the Yosys of today the bounded check of the whole core reaches 12 cycles, where the README said 9 did not finish (§6.4). One thing to know about the tools: Yosys models a ROM as state, so in an induction step its contents are free, which made a true lemma fail until the table was mapped to logic (§6.6).

Every finding has a fix. The four bugs change what a program computes only at the edges named; nothing else does.

## 1. The assembler

### 1.1 Coverage

| | Statements missed | Branches partial | Coverage |
|---|---|---|---|
| Before | 9 of 481 | 14 of 274 | 97% |
| After | 2 of 481 | 5 of 274 | 99% |

What remains is code no input reaches: four defensive branches (`check_equs` with a name already marked bad, `not allowed here` for a directive rejected earlier, `unexpected character` where every failed match is an unterminated string, and an empty token list without a label) and the import guard of the module. The nine lines a test now reaches were error messages: a bad symbol name, `$` and `#` prefixes, `--` and `++` on a non-register, a bad index, a missing constant, an unknown mnemonic after a condition, `.EQU` with no or two values, and an input file that cannot be read.

The gaps that the lines did not show: s1 was tested in three of its eight modes; no instruction had three constant words, so the order dest, s0, s1 of ISA.md §2.3 was checked for two at most; `c` alone as a destination, `R15++` in every field, tabs, upper-case `0X` and `0B`, `08` (decimal, where the 2004 emulator read octal, Appendix B), a leading `+`, chains of `+` and `-`, wrap in both directions, `.ASCII_B` with one to three characters, a quote of the other kind inside a string, `*` and `,` inside a string, lower-case conditions and modifiers, `INT 255` and `INT` with an expression, `.EQU` for a whole operand in each field and after `@`, used twice in one value, before its definition, and naming a later label, a label alone with `:`, a label before a condition, and a `*` comment after an operand. `encoding.nasm` has 59 new words at `.ORG 0x400`, each derived in a comment, and `errors.py` has 59 new error cases, ten good programs, an empty file, a file with no final newline, the exact stderr of two errors, and eight command-line cases: 181 cases now. The README's table and its list of finer points say what the tests pin down.

### 1.2 An output file that cannot be opened gives a traceback

`main()` in `niceasm.py` opens the input inside a `try` that turns an `OSError` into the one-line `file: message` of the README, and opens the output outside it:

    $ echo ' HALT' > ok.nasm
    $ ./niceasm.py -o nodir/ok.bin ok.nasm
    Traceback (most recent call last):
      ...
    FileNotFoundError: [Errno 2] No such file or directory: 'nodir/ok.bin'

The same for `-o` naming a directory. The exit status is 1, as the README says, but the message is a traceback. **Fix:** open the output in the same `try`, or in one of its own with the same `except OSError`. Two cases of `errors.py` fail until then, and `make -C assembler test` ends in `FAIL errors (2 of 181)`.

**Resolved**: `main()` writes the output inside a `try` of its own, with the same `except OSError`, so both cases print `file: message` and exit with status 1. `errors.py` passes all 181 cases.

### 1.3 Behaviour that no document stated

The tests pinned down four things that the README now says: `*` starts a comment only at the start of a word, so `R2 *note` is `R2` and a comment while `R2*note` is an error; a line with one word that is not a mnemonic or a directive is a label even when indented, so a misspelt `HALT` alone on a line is silently a label, which follows ISA.md §10.1 to the letter; an undefined symbol in an `.EQU` value is reported only where the name is used; and the source is read as Latin-1, so a UTF-8 `é` in a string gives two words. Two of them are worth an item in TODO.md: a warning for a lone unknown word read as a label, and reporting an undefined symbol in an `.EQU` that nothing uses. One more: ISA.md §10.2 says a constant's value wraps modulo 2³², but `INT`, `.BLK`, and `.RES` use the unwrapped value, so `INT 0xFFFFFFFF+1` is "out of range" rather than vector 0, which the README states for `.BLK` and `.RES` and `errors.py` pins for `INT -1`. That looks intended. **Fix:** a sentence in ISA.md §10.2 or §10.3 that these three take the value before it wraps.

## 2. The emulator

No bug. The reader made the table of every rule of ISA.md §1 to §8 and of SYSTEM.md against the test that checks it, and found 17 gaps: rules with no test, or with a test that an injected bug would pass.

- **R0 as a destination** in modes 001, 100, 101, and 110 was never run; `r0dest` runs each.
- **R15 as `--R15` and `@--R15`, and as `@--R15`, `@R15++`, and `R15--` destinations**, never run; `r15modes` has them, with a jump back into a constant word and an instruction that overwrites itself.
- **R14 as an address**, `@--R14` reading word `0x01FFFFFF` as the example of §4.3 says, and a memory destination through R14 with M set, where the flags are written after the side effect; `r14mem`.
- **The constant words of skipped and control instructions**: a skipped shift with constants, a skipped ALU instruction with only a dest or s0 constant, and control words whose low bits look like constant fields, `INT 0x33` executed and `INT 0xFF` skipped; `skipconst`. Every constant word there is a `HALT`, so a core or emulator that took constants for a skipped `INT` would halt.
- **The carry input at the edges**: `SUB[C]` giving 0 with a borrow out, V from the borrow in, `ADD`, `MDBL`, and `DBL` with cin, and `IAND`, `IOR`, and `XNOR` with the C bit set; `carryin`. A borrow computed in 32 bits, with b + cin wrapping, fails here and nowhere else.
- **Shift counts at the edges**: the C of a C-writing shift with count 0 when step 5 changed C, `C<C` and `C>C` by 33, 65, and 66, `C<<` by 64 (n mod 32 = 0, but C is still written), rotations by 2³² − 1, and fixed fills by 32, 33, 34, and 64; `shiftc`, and a unit test that compares `shift()` with a literal run of the loop of §5.2 for every opcode, both values of C, and counts 0 to 99 and 2³² − 1.
- **Address wrap in `@Rx++` and `@--Rx`, and a run through the I/O range** that must not move the read counter; `wrapmem`.
- **An instruction that overwrites its own constant word**, run in a loop: 2, 4, 8; `smcown`. A stale constant would give 4.
- **The screen's bounds**, with `-s` and with `-2004 -s`; `scrbound`.
- **Unit tests** for a write to one half of C or D keeping the other, a timer period written while the timer runs, a halted processor ignoring an NMI, the 64-bit counters wrapping, the trace lines of `INT`, `RTI`, and the halts other than `HALT`, and console bytes 0xFF and 0.
- **`errors.py`**: the exit status and first line of every way to stop, `-n 0`, `-n 1` on a `HALT`, the step limit right after an NMI entry, `Pending:` at the step limit, the timer's request of the last step not listed, a `-d` dump that wraps, and the output flushed before a console read.

Each new test was run against an injected bug and failed on it, but `r0dest` and `r15modes`, whose value is for the cores (§5.1). The probes are 33 now, the unit tests 45, and the cases of `errors.py` 54.

One observation for SYSTEM.md §1: it says a console read with no byte waiting returns 0. The emulator never reaches that state, since a read waits for a byte or the end of the input, as the emulator's README says, and the simulation memory of the cores reads a file the same way. **Fix:** a sentence in SYSTEM.md §1 that the emulator and the simulation memory never return 0 there, so that only a UART does.

## 3. The runtime library and the C library

### 3.1 Coverage

The reader made the table of every routine of ABI.md and README.md, and of every function of the C library and of `nice.zig` and `nice.rs`, against the test that would fail if it were wrong. Without one before: division by zero and the most negative number divided by −1 in `__div`, `__mod`, `__div64`, `__mod64`, and the unsigned ones, in both `muldiv_mpu.nasm` and `muldiv_soft.nasm`; `__mul64` with negative operands whose high words are set; the trap vector as a vector that a program can replace; `abort`; `memmove` with the destination below the source; `memset`, `memchr`, and `strchr` with a value above 255; `strstr` with an empty needle; `strchr` and `strrchr` of `'\0'`; six of the `ctype` classes; `strtoul` with a minus sign; `atol`; `realloc` from `NULL`, to 0, to a smaller size, and in place; `free(NULL)`, `malloc(0)`, and the alignment of every block; the overflow check of `calloc`; `snprintf` with a size of 0 or 1; `%p` with a width; a negative `*` width or precision; and `sscanf`'s `%n` on empty input, its return values at the end of input, and the unsigned conversions. The new tests: `test/edge.nasm`, run with both muldiv files, `test/trapvec.nasm`, `test/zigpoll.zig`, and `libc/test/printf.c`, `strings.c`, `numbers.c`, `sscanf.c`, `malloc.c`, `abort.c`, and `limits.c`, each with a hand-derived `.expected` file. The step counts of `edge.nasm` were derived from the routines' step formulas and matched at the first run.

One difference between the two muldiv files came out: signed `__div` and `__div64` of a negative dividend by 0 give 1 in the software version, which divides |a| by 0 and negates, and −1 with the math unit, where SYSTEM.md §2 says the quotient is all ones. C leaves division by zero undefined, the translator checks for 0 before it calls them, and README.md says so now. Not a bug.

### 3.2 `snprintf(NULL, 0, ...)` prints to the console

C17 7.21.6.5 allows a null buffer with a size of 0, to measure the output. In `libc/src/printf.c`, `struct out` uses a null `buf` to mean the console, so `emit` calls `putchar`:

    int n = snprintf(NULL, 0, "%d", 12345);
    printf("[%d]\n", n);

prints `12345[5]` instead of `[5]`. The same for `vsnprintf`. **Fix:** a flag in `struct out` that `printf` and `vprintf` set, instead of the test of `buf`.

**Resolved**: `struct out` has a `console` flag, which only `vprintf` sets, and `finish` writes the final NUL only when `cap` is not 0, so a null buffer of size 0 is never touched.

### 3.3 `malloc` of a size near 2³² returns a pointer

In `libc/src/malloc.c`, `more()` computes `pages = (size - (heap_end - brk_) + PAGE - 1) / PAGE`. For `malloc(0xFFFFFFF0)` the rounded size is `0xFFFFFFF8`, the sum wraps, `pages` is 0, `memory.grow(0)` succeeds, and `brk_ += size` wraps back below itself. `malloc` returns a pointer into the heap, with a block size of `0xFFFFFFF8`; `calloc(1, 0xFFFFFFF0)` then writes past the memory and traps with code 2. Every size from about 2³² − 65536 + the free bytes at the end of the heap up to `0xFFFFFFF0` is affected. **Fix:** return `NULL` when `size - (heap_end - brk_)` would not fit a page count, that is, when it exceeds `SIZE_MAX - (PAGE - 1)`.

**Resolved**: `more()` returns `NULL` in that case, before it calls `memory.grow`.

### 3.4 `strtoul("-4294967295")` gives 4294967295, not 1

In `libc/src/stdlib.c`, `parse` returns `ULONG_MAX` both for an overflow and for a value that is exactly `ULONG_MAX`, and `strtoul` skips the negation when the value is `ULONG_MAX`. C17 7.22.1.4 negates the value in `unsigned long`, so −(2³² − 1) is 1. **Fix:** let `parse` report the overflow apart from the value, and negate unless it overflowed.

**Resolved**: `parse` sets a flag `*over` when the value saturates, and `strtoul` negates unless it is set. `strtol` takes the flag too and is unchanged otherwise.

`libc/test/limits.c` has the three cases of §3.2 to §3.4, runs last among the C library's tests, and fails until they are fixed, so `make -C runtime test` ends in `FAIL libc/limits`.

**Resolved** with §3.2 to §3.4: `libc.a` and the `.wasm` files of the C library's tests are rebuilt, and all twelve tests pass. `bench/bench.wasm` is not rebuilt: it calls `printf` only to print its results, outside the timed phases, and never with a null buffer.

### 3.5 Not closed

`nice.rs`'s `poke` and `pollc` returning a byte, since no rustc is installed to rebuild `nicers.wasm`; `pollc` returning "no byte waiting", which the emulator never gives (§2); the counters' low and high words across a wrap of the low word, which cannot be reached; and the float routines, which the translator's tests cover.

### 3.6 A failing C library test leaves its build files behind

`make -C runtime/libc test` removes each test's `.out.nasm`, `.full.nasm`, `.out.bin`, `.raw`, and `.status` after the last test, so a test that fails, as `limits` does now, stops make before the cleanup, and the files of every test stay in `test/`, where git does not ignore them. **Fix:** remove them before each test as well as after, or list the patterns in `.gitignore`.

## 4. The translator

### 4.1 Coverage

| | Lines | Branches |
|---|---|---|
| Before | 3383 of 3420 (98.9%) | 1659 of 1706 (97.2%) |
| After | 3398 of 3420 (99.4%) | 1674 of 1706 (98.1%) |

What remains is dead or defensive code, two sections with no entries, and the paths where an optimization pass gives up, each of which only declines an optimization, so that a fault there gives larger code, not wrong code, and which a test cannot reach without depending on the register allocator's choices.

The reader compared three lists: the instructions and module features that WASM.md and the README call supported, those the handlers implement, and those the tests use, from a census of the opcodes in every module the tests build or check in. The first two agree. Thirteen supported instructions appeared in no test at all: `f32.convert_i64_s` and `_u`, `f64.convert_i32_u`, `f64.eq`, `f64.gt`, `f64.reinterpret_i64`, `i32.trunc_sat_f64_s` and `_u`, `i64.trunc_f32_u`, `i64.trunc_f64_u`, and `i64.trunc_sat_f32_s`, `_f32_u`, and `_f64_u`. Every supported instruction appears in a test now.

### 4.2 The gaps, and the tests that close them

No bug. The gaps were in what the instructions were given, since the C modules use constant operands where a register operand takes other code. `run.py` has 44 new cases, each run with the math unit and with `--no-mpu`: division with both operands in locals, by −1, of the most negative value, with negative remainders, and with an i64 divisor that has −1 in one word only or a zero low word, and their traps from operands in parameters; the thirteen conversions, with saturation, NaN, and edge values, one of which checks that `f32.convert_i64_u` does not round twice; the trunc traps of the unsigned and i64 forms; blocks with two results and with parameters, `br`, `br_if`, `if`, `loop`, and `br_table` carrying two values, and a block parameter taken from a local that the block then changes; zero-length `memory.fill` and `memory.copy` ranges past the end, which trap, a range whose end passes 2³², and both under `--no-bounds-checks`; offsets past the memory with the base in a register, and offsets near 2³² that wrap under `--no-bounds-checks`, as WASM.md says; i32 shifts by counts in a register of 32, 33, 63, and −1; the bit counts at their edges; 50 values on the operand stack across a call; ten parameters of mixed types, with a stack parameter changed by the callee and passed on through `call_indirect`; recursion with stack arguments; `return` from inside loops; every form of element segment, `ref.null`, a later segment overwriting an earlier one, and a data segment with flags 2; `memory.grow` by −1 and by 2³¹ failing without changing the size, and a 0-page memory growing; `--no-bounds-checks` with `--memory-pages` and with `--library`; the start function seeing the data segments, or being an import; a name section cut short; immutable and i64 and f32 globals; and an `if` on a local that held a comparison result and was then overwritten. `errors.py` has four new cases, 156 now, and `passes.py` the two rules of `early_exit` that the README states.

### 4.3 The fuzzer

`fuzz.py` generated no globals, `return`, `nop`, typed `select`, bulk memory, or floats, and ran only with and without `--no-mpu`. It now makes mutable and immutable globals, folded into main's result, `memory.fill` and `memory.copy` in bounds with overlapping ranges, `return`, `nop`, and typed `select`, and has the options `--unchecked` and `--grow`; `make test` runs 20 seeds in each new mode, and the reader ran seeds 1 to 1500 in six modes, 9000 modules, with no failure. `diff_fuzz.py` runs with the new generator. Still outside its model: blocks with several values, and traps, which `run.py` and `diff_fuzz.py` cover.

### 4.4 Two small things in the README

It says errors print as `file: error: message`; an unreadable input prints `file: No such file or directory`, and the overwrite check omits `error:` too, both with exit status 1 as the README says. And `early_exit` has a length limit of about 11 instructions that the README does not state. **Fix:** the two sentences.

`make -C hdl programs` runs `run.py --keep`, so it now runs 88 more programs on each core.

## 5. The cores: simulation tests

### 5.1 The new probes on both cores

Eight of the nine new emulator probes depend on nothing the cores lack, and `PROBES` in `hdl/Makefile` lists them: `r15modes`, `r0dest`, `r14mem`, `skipconst`, `carryin`, `shiftc`, `wrapmem`, and `smcown`. Both cores pass them. `scrbound` checks the emulator's screen and stays out. `skipconst` is the one worth having most: a pipelined decode that took the constant words of a skipped `INT`, or of a control word whose low bits look like constant fields, would run a `HALT` word.

### 5.2 Not changed

The random programs of `random_prog.py` keep their known weaknesses (TODO.md), and `sidefx_prog.py`'s program is still not swept with interrupts, for the reason given there.

## 6. The cores: formal verification

### 6.1 The shared functions, for every input

`hdl/formal/formal_nice_pkg.vhd` with `nice_pkg.sby` proves the functions that both cores share, for every input. They are combinational, so a proof of depth 1 covers every value:

- **The shifter against ISA.md §5.2.** The loop of §5.2, "repeat n times", written out as it stands, run for counts up to 66, gives what `shift` gives (`f_loop`). For every larger count, `shift` gives what it gives for a smaller count that the loop would give the same for: 33 for a fixed fill, where nothing changes after 33 steps (`f_fill`), n − 32 for a 32-bit rotation (`f_rot32`), and n − 33 for a rotation through C (`f_rot33`), which checks the digit sum of `mod33`. So `shift` follows §5.2 for every count, by descent. The same statements cannot be made with `n mod 33` as the reference: the solver bit-blasts the modulo into a divider, and did not finish in ten minutes.
- **The pipelined core's shifter against the multi-cycle core's.** `shift_fast` of `shift_prep` gives what `shift` gives (`f_fast`), also when WRITE prepares the count in two steps, without the count mod 33 and then with it, as `pipe_write.vhd` does for a count it must reduce itself (`f_late`). `tb_shift` checks a sample of this by simulation.
- **The ALU against ISA.md §5.1, and the flags against §6.** The ALU with its one adder gives what the sixteen operations give written out one by one, with the 33-bit carry and borrow and the sign rules for the overflow (`f_alu`), and `flags` sets X, Z, N, C, and V and nothing else (`f_flags_*`).
- **The block compares of MICROARCH.md §5.5.** A word within 16 of FETCH's oldest word lies in one of the three blocks that WRITE tests, given that the oldest word's block is `blk_o` or the one before it (`f_near_fetch`), and a word within 4 of an instruction's address lies in its block or the next (`f_near_inst`). The given is proven in FETCH: the oldest word moves by at most four words a cycle (`f_blk` in `pipe_fetch.vhd`), and the range is at most 16 words (`f_span`). So the argument of §5.5 is in three proven pieces now, with the cycle after a redirect covered by `f_redirect` from the third review.

Boolector proves it in 37 seconds; Yices does not finish. The covers show the large counts and the ends of the ranges.

### 6.2 DECODE

`hdl/formal/formal_pipe_decode.vhd` with `pipe_decode.sby` proves DECODE for every cycle, by k-induction of depth 2, in two seconds. The properties are under a new `G_FORMAL` of `pipe_decode.vhd`, which stays off in the whole-core check, as PREPARE's does: the proof with free inputs covers everything the whole core can do, and the shadow registers only add time to the bounded check, a sixth in a trial (27.5 seconds against 23.5 for the 8 cycles). Every input is free: the words from FETCH and their count, at most four, PREPARE's ready, and WRITE's flush. The assertions are exactly what the proof of PREPARE assumes of DECODE (`f_emit` to `f_decoded` in `pipe_prepare.vhd`), so that assumption is discharged now: a micro-operation is emitted only when PREPARE takes it and no flush comes; the micro-operations of an instruction come in order, the first marked first and the last marked last, each with the same instruction; the instructions emitted since the last flush have consecutive ids; and the fields of each micro-operation agree with its instruction word, `next_pc` and the block among them. They also say that DECODE takes no more words than FETCH offers, and a whole instruction or nothing, with its constant words in the order dest, s0, s1 of ISA.md §2.3, and that it redirects FETCH only as it takes `MOVE R15, c` or `ADD R15, R15, c`, to c or to the next instruction's address plus c, as ISA.md §4.3 gives R15. The two forms are one function now, `early_form` in `pipe_pkg.vhd`, which DECODE and its proof share.

One assumption of PREPARE's proof is not DECODE's to discharge: that a new instruction's id differs from the last one emitted, also across a flush. DECODE proves consecutive ids only since the last flush, and the whole core keeps the rest because a flush empties WRITE. `p_check` in `pipeline.vhd` asserts what PREPARE relies on, that a new instruction in PREPARE never has the id of the one in WRITE, on every simulation run and in the bounded check.

### 6.3 A halted core, and two small invariants

That a halted core makes no bus request was proven for the multi-cycle core only (TODO.md). Now: `pipe_prepare.vhd` proves that a data read is on the bus only while the core runs (`f_rd_run`), under the assumption, checked by `p_check`, that no flush or interrupt comes while a read is on the bus or about to be loaded; `pipe_fetch.vhd` already proved that a stop ends the requests; and `formal_pipeline.vhd` asserts, for the bounded cycles, that a halted core has no data access on the bus and no new instruction fetch, a request still on the instruction bus being one the bus stalled before the halt (`f_halt_dbus`, `f_halt_ibus`), with a cover that shows a halt within the 8 cycles. What is left is WRITE's store and vector read for every cycle, which only a proof of WRITE would give (TODO.md).

`p_check` also asserts, with the flush, that no interrupt is taken while a read is on the bus or about to be loaded, which the proof of PREPARE now assumes.

### 6.4 The depth of the bounded check

`pipeline.sby` checks the whole core for 8 cycles after reset, and the README said a 9th did not finish in 20 minutes. With Yosys 0.56 and its ABC, 8 cycles take 32 seconds, 10 take 5 minutes, and 12 take 13 minutes, all passing with the new assertions. CI installs Yosys 0.33, which cannot be tried here, so the depth stays 8; the README and TODO.md record the figures for when CI's tools are newer. PDR (`abc pdr`) on the whole core proved 28 of its outputs in the first 10 minutes and then timed out on the rest; it would need the invariants that TODO.md names.

### 6.5 The devices

The math unit, the performance counters, and the fetch statistics had testbenches and no formal job, where the timer and the bus decoder had both. A reader wrote one for each in a clone, and each has a `prove` and a `cover` task now, all passing. No bug was found. The ports are checked as `formal_timer` checks the timer's: no stall where the device never stalls, an ACK in the next cycle for each accepted request and nothing else, and reset.

- **`perf.sby`** checks the counters against a model in the wrapper, `formal_perf.vhd`: two 64-bit counters and a snapshot of each. A read returns the low word of its counter, the high word of its snapshot, or 0 for a spare word, so `CYCLE_HI` after `CYCLE_LO` gives the value at the read of `CYCLE_LO` also when the low word wrapped in between, and writes change nothing. PDR (`abc pdr`) finds the invariant that the counters equal the model on its own, in five seconds, so `perf.vhd` is unchanged. The cover task sets `G_RESET` near a wrap, with a `-g` option in the job, and shows a read of `CYCLE_HI` after one. A mutation check: a `CYCLE_HI` read of the live counter instead of the snapshot fails the proof, but only with `G_RESET` near a wrap, since from 0 the counterexample is 2³² cycles deep.
- **`fetch_stats.sby`** connects two devices to the same inputs, one with `G_ENABLE` and one without, under the one assumption that the buffer holds no more words than are held. The one without returns 0 for every read. For the other, the properties are under a new `G_FORMAL` of `fetch_stats.vhd`: a read returns the word as it is when the read is accepted; a counted cycle adds one to `FS_CYCLES` and to the bin of its count; stopped counters keep their values, a write of 1 starts them without a clear, and a clear or a reset clears them; and the invariants that the bins of `FS_HIST` sum to `FS_CYCLES`, that `FS_MIN` is at most `FS_MAX` once a cycle has counted, and that `FS_MAX` is at most `FS_HELD_MAX`. One induction step over the flat sum of 32 counters did not finish, so ghost counters in a binary tree over the bins count the cycles of each subtree, each node asserted to be the sum of its two children, and the flat sum is written in the tree's order. Boolector proves it by k-induction of depth 1 in about three minutes; Yices does not finish in 15. Three mutations fail it: the wrong bin incremented, `FS_MIN` tracking the held count, and a clear that sets `FS_MAX` to 1.
- **`mpu.sby`** checks the port with a count of the ACKs owed, in `formal_mpu.vhd`, and the data under a new `G_FORMAL` of `mpu.vhd`. Proven for every cycle: at most one ACK is owed, and STALL is high exactly while a read waits; every read gets its ACK within 34 cycles for the 32-bit half and 66 for the 64-bit half, and the covers reach both limits; shadow operands follow the writes, and each ACK carries the right word; a product read comes from A and B as they were when the read was accepted, through ghost copies that follow the operands through the multiplier's two registers; and each of the four dividers keeps the loop invariant of a restoring divider, across the skip of 8 steps too. So at a read of a quotient or remainder, A = M + R with R < B, where M is Q times B formed by a ghost register by shift and add as each quotient bit is found, with the results of SYSTEM.md §2 for B = 0, the signs and the rounding toward zero of the signed results, and INT_MIN / −1. Five mutations fail it, a skip test with `<=` among them. Boolector proves it by k-induction of depth 1 in about two minutes.

**What is not proven, and why.** That the multiplier computes the product. Neither Yices nor Boolector can compare two 32-bit multipliers: the induction step of `mul_r = a_r * b_r` did not finish in ten minutes, and the combinational identity between the signed high word and the unsigned one, with no registers at all, did not finish in five. So the value of a product read stays with `tb_mpu`, and only its freshness is proven. The same limit leaves the textbook lemma that shift and add multiplies, M = Q × B, unproven: on its own, the 64-bit lemma did not finish in five minutes, and with M written as a product every divider invariant timed out at ten. A bounded check from a free operand pair was not tried, because its last step needs the same multiplication. **Fix:** none with these solvers. A solver with a multiplier theory, or the lemma proven by hand beside the job, would close it (TODO.md).

The three jobs ran with Yosys 0.56 and GHDL 6.0.0-dev here, as did those of §6.1 and §6.2. CI's Yosys 0.33 and GHDL 4.1 have not run them yet (TODO.md).

### 6.6 A ROM is state in an induction step

The first run of the lemmas of §6.1 failed `f_loop` on `C<C` by 58 with a counterexample that simulation contradicted. The table of `mod33`, a constant array that GHDL synthesises as a ROM, becomes a `$mem` cell in Yosys, whose contents are initial state: right from reset, so the bounded check of the whole core is exact, but free in the induction step of a k-induction, where the solver starts from any state. So the multi-cycle core's `prove` task, and PREPARE's, have been proving their properties for every table, which is sound and harmless there, and the lemma failed because it is about the table. `nice_pkg.sby` maps the table to logic with `memory_map`, which leaves nothing in the file that is state. Worth knowing for every future proof that depends on `C_MOD33`, and for a shadow memory in a wrapper.

## What is correct

- `make test` passed at b7b46f4 in 3 minutes 39 seconds, all 697 checks, and `make -C hdl formal` in 3 minutes 40. With the new tests, every check passes but the four that found the bugs of §1.2 and §3.2 to §3.4.
- The emulator agrees with ISA.md §1 to §8 and SYSTEM.md in every corner the reader tried, by reading and by 17 new tests, each of which fails on an injected bug.
- The translator agrees with WASM.md and the wasm semantics in 44 new cases, with the operands in registers, and in 9000 random modules in six modes.
- Both cores pass every test of `make -C hdl test` with the eight new probes and the properties of §6 in the code, 284 checks in 3 minutes 11 seconds, and the 448 programs of `make -C hdl programs`, 350 before the new translator cases, run with the C library's failing test left out, since the target runs the runtime's tests first.
- The proofs of §6.1 to §6.3 and §6.5 pass, and the covers of each job reach every statement: `make -C hdl formal` runs its twelve jobs, 24 tasks, in 12 minutes, beside the simulation tests.
- `make -C doc test` finds every section reference and link of the new text.
