# Review of the repository at commit 88276db

Reviewed on 2026-10-15: everything that changed since commit ae490e6 ("Review: second review of the wasm path"), 46 commits, and the state of the repository as a whole at commit 88276db ("Rename NICE assembly files from .asm to .nasm"). The changes are the multi-cycle core with its memory model, trace writer, and testbenches (`hdl/`), the math unit and the performance counters in ISA.md §8.4 and §8.5 with their emulator and FPGA versions, the smaller code of `nicewasm` (deferred operands, inline memory accesses, shift helpers, locals in registers, jumps on the flags, and results written straight to locals), the runtime's two muldiv files and its C library, the Rust test modules, the beginner's slides, and the move of every open item into `TODO.md`.

**How it was checked.** I read ISA.md §1 to §8 against `hdl/src/multicycle.vhd`, `mpu.vhd`, and `perf.vhd`, and §8.3 to §8.5 against `emulator/src/cpu.zig`. I read the whole translator diff against §9.3 and §9.4 and traced the rules for deferred values, register locals, fused comparisons, and forwarded results by hand. I read the two muldiv files, the C library, the slides, and every README against the code. I ran every `make test` and `make typecheck`; all pass, and CI passes on `main`. Then I ran tests the repository does not have:

- **The core on more random programs:** 60 more seeds of `hdl/test/random_prog.py`, each for 5000 steps, with stall rates of 0, 30, and 60 percent: 180 runs.
- **The math unit** with three more seeds and 20000 random pairs each: 60000 pairs of A and B, and 120000 of C and D.
- **The memory model and the trace writer under nvc** 1.20-devel, with the output diffed against the emulator.
- **The translator against a Python model:** 300 random modules with the math unit and 300 with `--no-mpu`. Each has four functions with mixed `i32` and `i64` parameters, up to 12 locals so that some live in R7–R11 and some in the frame, loops, blocks, `if`, `br`, `br_if`, `br_table` with values, `select`, calls and `call_indirect`, every integer operation and comparison, `eqz` before `if` and `br_if`, `i64` shifts by constants and by variables, `div` and `rem` with nonzero divisors, loads and stores of every width at constant and at dynamic addresses, and `local.set` and `local.tee` of locals whose old value is still on the operand stack. `main` returns a fold of every local and of 18 memory words.
- **The C library's `printf` family against a model of C's `printf`:** 1500 random calls in five programs, with the flags `- + space # 0`, widths and precisions as numbers and as `*`, every length modifier, the conversions `d i u o x X c s %`, and `snprintf` with truncation.
- **The claims in TODO.md** that were not checked: nvc, the compiler versions recorded in the `.wasm` files, the GHDL version that CI installs, and the date of QNICE.

## Summary

**No bug was found in the core, the math unit, the counters, the emulator, the translator, the runtime, or the C library.** Every random test agreed with its model once the model itself was right. The findings are about tests and documents:

- `random_prog.py` can make the core and the emulator disagree by design, by reading the cycle counter, so the random test passes only for the seeds that happen not to (§1.2).
- A wasm program that overflows its shadow stack corrupts its data silently. `-Wl,--stack-first` turns that into a trap (§5.2).
- All four unchecked claims in TODO.md are now checked (§6.1).
- Stale sentences in three documents, and two small deviations in `printf` (§5.3, §6.2).

## 1. The multi-cycle core

### 1.1 What was checked

`multicycle.vhd` follows ISA.md §5 state by state. I checked each rule against the code: the condition test, the three control commands and the reserved words with their halt reasons, `RTI` and `INT` with `in_service` and `after_rti`, every source and destination mode with the R0 and R14 rules of §4.3 in `regval`, R15 as an operand after all constant words, the `cin` of §5.1 read after the sources, the flag update with the R14 exception of §6, the shifter's closed forms with the reduction modulo 33, NMI before IRQ with `after_rti`, the vector read at VBASE × 256 + v, and `instret_o` for every instruction but no interrupt entry. The report to the trace writer carries the committed registers, the last data access, and the halt reason. I found nothing wrong.

The 30 random programs of `make test` pass, and so do all 180 extra runs except the 13 of §1.2. The math unit testbench passed with 180000 more random pairs. The memory model and the trace writer run under nvc, and the trace matches the emulator's, which checks the README's claim.

### 1.2 The random programs can read the cycle counter

`random_prog.py` uses the read counter at `0xFFFFFF01` as a constant in 3% of the constant words, so that the number and order of data reads are compared. A register loaded with that address and used as `@Rx++` walks upward, and after 15 words it reaches `CYCLE_LO` at `0xFFFFFF10`. There the emulator counts steps and the core counts clock cycles, so the traces differ, and the run fails although the core is right.

With the seeds 1 to 30 and 3000 steps this does not happen. With seeds 31 to 90 and 5000 steps it happened in 5 of the 60 programs, 13 of the 180 runs. I replayed each failing trace and computed the data addresses of the first differing instruction: all 13 read `0xFFFFFF10`. A change of `RANDOM_SEEDS` or `RANDOM_STEPS` in `hdl/Makefile`, or any change to the emulator's step count, can therefore break the test.

**Fix.** Keep the counters out of the random programs. One way: in `random_prog.py`, use the `COUNTER` constant only as the address of a mode 111 field with R0 as the base, never as a value that a register can hold and increment. The random 32-bit constants can still hit the I/O range, but with a probability near 2⁻²⁴ per constant.

**Resolved**, but not that way. Steering the counter's address was not enough: in seed 34, a register reached `0xFFFFFF10` by shifting a small negative number, and any random arithmetic can. Instead, the random runs take the cycle counter out of both models: `niceemu --no-cycle-counter` makes `CYCLE_LO` and `CYCLE_HI` ordinary memory, and the testbench generic `G_CYCLE_COUNTER` sends those two words to the memory model. The instruction counter and the math unit stay, because both sides agree on them. The 30 programs of `make test` are unchanged and pass, and so do seeds 31 to 90 with a stall rate of 60% and 91 to 120 with none, all for 5000 steps. `make random` runs any seeds, stall rate, and step count, and `hdl/test/trace_reads.py` prints the data reads of the first differing instruction, which is how the 13 runs were classified.

## 2. The math unit and the performance counters

`mpu.vhd` is what §8.4 says. A write to an operand restarts the computation, a read of a result during a computation holds STALL and ACK, and a read of an operand or a spare word never waits. The signed results come from the unsigned ones as the header explains, and the two special cases fall out of the restoring divider and the negation of `0x80000000`. The emulator's `Mpu` computes the same values directly, and `tb_mpu` compares both halves with `numeric_std`. The random programs and `mpu.nasm` and `mpu64.nasm` run on the core with a memory that stalls, which exercises the wait path.

`perf.vhd` and the emulator's `Perf` match §8.5: the snapshot on a read of a low word, the high word from the snapshot, no writes, and both counters and snapshots cleared by reset. The emulator's cycle counter counts steps, as §8.5 says, and `perf.nasm` keeps it out of the registers so that the core's trace matches.

`muldiv_mpu.nasm` is right. `__mul64` forms the low 64 bits of the product from three 32-bit products and leaves A holding the old R1 for the second one, as its comment says. The `--no-mpu` tests run every translator case with `muldiv_soft.nasm` as well.

## 3. The emulator

The read counter, the math unit, and the counters are devices in `read`, `peek`, and `write`, and `fetch` now reads memory directly, so an instruction fetch has no device side effect, as §8.3 requires. `peek` reads the counters without taking a snapshot, so `--dump` is harmless. The step counter is incremented after `execute`, so an instruction that reads `INSTR_LO` sees the instructions before it. The five new probes have hand-checked expected files and run on the core as well.

## 4. The translator

### 4.1 The new code is correct

The 600 random modules all gave the model's result. They cover the rules of the README's "How functions are translated": a deferred constant or local as an operand, the settling of deferred values before a `local.set` or `local.tee` of the same local, at the start of a block for the values the block takes and for every local, and at `else` and `end` for the results; deferred values carried by `br`, `br_if`, and `br_table` and across calls; results written straight to a local, with other copies of the local's old value settled first; comparisons and `eqz` that set only the flags before `br_if` and `if`, including the signed ones through `?V XOR R14, R14, 0x10000000`; `i64` shifts by a constant inline and by a variable through the helpers; loads and stores of every width through the inline path, the helpers, and the constant-address path; `select`, `wrap`, `extend`, and `reinterpret` of deferred values; and locals in R7–R11 saved and restored across calls, with `i64` locals in register pairs and more locals than registers.

Three mismatches came up while the model was being written, and all three were bugs in the model, not in the translator: a `br_table` default that was modelled as the wrong label, a branch through a loop, and the labels around `br_table`. I mention them because they show what the test checks.

### 4.2 Notes

- Both passes over a function add to `self.t.helpers`. The first pass has no register locals, but it defers the same values and takes the same paths, so it asks for the same helpers. If that ever changes, the first pass could emit a helper that the second does not use, which costs words but nothing else.
- The README says the translated functions use R14 "for the trick above". That is the XOR of the signed comparison. Fine.

## 5. The runtime and the C library

### 5.1 The C library is correct for what it claims

The 1500 random `printf` cases all matched the model, including `snprintf` truncation and the return values, every length modifier, `*` widths and precisions with negative values, and the `#` forms of `o`, `x`, and `X`. The `string.h`, `stdlib.h`, and `ctype.h` functions read correctly against C, and the three test programs check them.

### 5.2 Shadow stack overflow is silent; `--stack-first` makes it trap

My first `printf` programs put 300 variadic calls in one `main`, linked with `-z stack-size=4096` as the READMEs show. Clang gives each call its own argument area in `main`'s frame, so the frame did not fit in 4 KB. The shadow stack then grew down into the data segment, `printf` read format strings and `va_list`s from overwritten memory, printed text from the stack, and finally trapped with code 2. Which call failed depended on the program's size, not on what it had run.

This is not a bug in the toolchain: wasm-ld places the stack after the data unless told otherwise, and the ISA does not promise to detect a stack overflow in linear memory. But the symptom is misleading. With `-Wl,--stack-first`, the stack is at the bottom of the memory, the overflow wraps the address below 0, and the bounds check traps at once with code 2, which `niceemu` reports as an abnormal halt. I confirmed this with the same program.

**Suggestion.** Add `-Wl,--stack-first` to the clang command lines in `translator/README.md`, `translator/Makefile`, `runtime/README.md`, and `runtime/libc/Makefile`, and say in the translator README that an overflow of the wasm stack then traps instead of corrupting the data. Zig's default layout already puts its stack first, as the `datazig` case notes.

**Resolved**: the four command lines have `-Wl,--stack-first`, and the translator README explains what it buys and that Zig and rustc do it by default. The C test modules and the C library's test modules were rebuilt with it; every case still passes, since the tests check results, not addresses.

### 5.3 Two small deviations in `printf`

- `%+u`, `% u`, `%+x`, and the like print a sign. The C standard defines the `+` and space flags for signed conversions only, and glibc ignores them for unsigned ones. Clang warns about the combination, so no correct program uses it. Harmless, but a one-line check in `number()` would make it match.
- `%p` of a null pointer prints `0`, where glibc prints `(nil)`. The README says `%p` prints `0x` and the address; for 0 it prints neither. Either is acceptable; the README could say so.

**Resolved**: `printf` ignores `+` and space for the unsigned conversions, and `%p` always starts with `0x`, so a null pointer is `0x0`. `stdio.c` tests both, the README says so, and `runtime/libc/test/fuzz_printf.py`, the model-based test of this review, is in the repository as `make -C runtime/libc fuzz`.

## 6. Documentation

### 6.1 The unchecked claims of TODO.md

- **nvc.** Checked: `tb_mem` passes and `tb_trace` matches the emulator under nvc 1.20-devel.
- **rustc 1.99.0.** Checked: the `producers` sections of `rust.wasm`, `rusttrap.wasm`, and `hellors.wasm` say `rustc 1.99.0 (b940084d7 2026-09-28)`. The C modules say `Ubuntu clang 18.1.3`.
- **GHDL in CI.** Checked indirectly. The CI log needs admin rights to read, but `ubuntu-latest` is Ubuntu 24.04, whose `ghdl` package is 4.1.0+dfsg-0ubuntu2.1 with the mcode backend. That is the "GHDL 4.1.0 (mcode backend)" of `hdl/README.md`. The README could say that this is what CI uses.
- **"2006" for QNICE.** Checked: the QNICE Processor Pages at vaxman.de, which `doc/REFERENCES.md` lists, say that QNICE's "initial phase which ran during 2006 has been completed", with a hardware implementation to begin in 2007. qnice.sourceforge.net is vaguer, "research done in the late 1990s and the following years", but does not contradict it. The slide's bibliography cites the QNICE-FPGA repository; the date comes from the vaxman.de page, which REFERENCES.md could note.

### 6.2 Stale sentences

- `translator/README.md` says "The code is about a third smaller than it was" and then reports 42% and 51%. `doc/REFERENCES.md` says the plan "made the translated code a third smaller", and `doc/review/code-size-plan.md` says "All three steps of the plan are done" and ends at 30% and 37%. The fourth step, locals in registers, jumps on the flags, and forwarded results, is not in the plan file.
- `README.md` says translated code uses the math unit "for `i32.mul`, or calls `__mul` with `--no-mpu`". It also uses it for `div` and `rem` of `i32` and `i64`.
- `TODO.md` said that every finding of the reviews is closed except the unchecked claims. It now lists the items of §1.2, §5.2, §5.3, and this section, dated 2026-10-15, and no longer lists the claims.

**Resolved**: the translator README says "about half the size it was, after four steps", `code-size-plan.md` has the fourth step with its numbers, the top-level README names the divisions, and `hdl/README.md` says which GHDL CI installs. Every item of this review is closed, and `TODO.md` says so.

## 7. What is correct

- **The core against the emulator**, on the 2004 examples, every probe, `cputest`, `shift.nasm`, five programs with a stalling memory, and 210 random programs with interrupts at random steps. The only differences are reads of the cycle counter, where the two must differ.
- **The math unit** on 20 corner cases and 62000 random pairs of A and B, and 16 corner cases and 124000 random pairs of C and D, with the waits, restarts, and pipelined requests of `tb_mpu`.
- **The counters**, including the snapshot across a wrap of the low word.
- **The translator** on 600 random modules in both math-unit modes, and on every checked-in case.
- **The runtime**: the two muldiv files on the same tests, the float library's division into the subnormals, and the C library on 1500 random `printf` calls.
- **The documents**: ISA.md §8.3 to §8.5, MICROARCH.md §8, `hdl/README.md`, `emulator/README.md`, `runtime/README.md`, and `translator/README.md` agree with the code everywhere I compared them, apart from §6.2. The slides' encodings and examples are right, and the example programs run.
