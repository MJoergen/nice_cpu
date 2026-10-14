# Review of the wasm path: translator, runtime, and §9.4

Reviewed on 2026-10-14: `translator/nicewasm.py`, `runtime/`, and `doc/ISA.md` §9.3 and §9.4 at commit 8752ac9 ("ISA: reserve wasm memory with .RES instead of .BLK"). The goal of the review was to find what must be settled now, before more of the translator is written, so that Zig programs can run on the emulator and later on the FPGA.

**How it was checked.** I read the translator, the runtime, the tests, the assembler, and the emulator's loader against §9.3 and §9.4, and traced the frame layout, the call sequence, the stack-argument addresses, and the zero loop by hand. I ran every `make test`. Then I compiled five Zig programs (bytes and strings, a function pointer, `@memset`, `u64`, `std.fmt`, an allocator, a failing safety check, and `f32` arithmetic) with Zig 0.15.2 in Debug, ReleaseSafe, ReleaseSmall, and ReleaseFast, with and without the README's memory options, plus one C program with clang 18, and listed what each module contains. I ran the translator on all of them, and on a few hostile modules. I timed the assembler on a 196000-line program and the emulator on 20 million steps.

## Summary

**The mechanics are right.** Everything the translator emits today is correct. The frame layout, the register and stack arguments in both directions, the return path, the zero loop, the LEB128 reader (including the 5-byte padded encodings that LLVM emits), the section order check, and negative constants were all traced and tested. Translated code preserves R7–R13 as §9.3 requires. The toolchain scales: the assembler takes 7.5 s for 196000 lines, and the emulator runs about 70 million steps per second, so zeroing Zig's default memory takes 5 ms.

The problems are in what the design does not yet say, now that real modules show what Zig emits:

- Six decisions to make now (§1). The first three are forced by every real Zig module: the operand stack must carry types because `i64` is everywhere, the translator must target Zig's default feature set, and `call_indirect` and traps are needed by every ReleaseSafe or Debug program. The other three are a way to see a program's output and to tell a trap from a normal exit, whether a second module may be translated as a library, and the memory budget.
- One bug in the translator, confirmed: a name section can inject assembly (§2.1). Four smaller ones.
- Five small points in §9.4 (§3).

## 1. Decisions to make now

### 1.1 The operand stack must track types, not only depth

`FunctionTranslator` gives every operand-stack depth one frame word, and `slot(d)` is `FP − 1 − n_slots − d`. That works while every value is one word. It stops working with `i64`, which is two words, and `i64` is not a rare type:

| Module | Instructions | `i64` instructions |
|---|---|---|
| bytes, ReleaseSmall (one `u64` variable) | 101 | 10 |
| fmt, ReleaseSmall (`std.fmt.bufPrint`) | 3240 | about 520 |
| alloc, ReleaseSmall (`std.heap.wasm_allocator`) | 725 | about 60 |

LLVM copies 8-byte structures with `i64.load` and `i64.store` even in code with no 64-bit variables, so no useful module avoids them.

The next step for the translator is blocks and branches, and the branch arity rules need the same thing: at a `br`, the values that the label takes must be moved to the label's slots, and their types decide how many words to move. So the depth counter should become the typed operand stack of the wasm validation algorithm before blocks are added, not after. Decide the frame layout for two-word values at the same time. One word per `i32` and two per `i64`, low word first as §9.3 says for register pairs, keeps the frame small. Two words for every entry is simpler but wastes a word per `i32`.

### 1.2 Target Zig's default feature set

Zig 0.15.2 compiles for a default wasm32 CPU with these features: `bulk-memory-opt`, `call-indirect-overlong`, `extended-const`, `multivalue`, `mutable-globals`, `nontrapping-fptoint`, and `sign-ext`. Clang 18 uses only `mutable-globals` and `sign-ext`. What this means for the translator:

- `memory.fill` and `memory.copy` (`0xFC` prefix) appear in the smallest programs. The 430-byte ReleaseSmall module of a program with one `@memset` has one `memory.fill`. ReleaseSafe modules have five to eleven of each, from the standard library.
- `@intFromFloat` becomes `i32.trunc_sat_f32_s` and friends (`0xFC` 0–7), not the trapping `i32.trunc_f32_s`. Trap code 5 of §9.4 is rarely reached by Zig code.
- `call-indirect-overlong` only affects the encoding, and the reader already accepts it.
- `extended-const` lets a global's initial value and a data segment's offset be an expression with `i32.add`, `i32.sub`, and `i32.mul`. Zig emits plain `i32.const` today, but the translator must reject the others clearly rather than assume them away.
- `multivalue` is enabled, but neither Zig's nor clang's ABI uses it. None of the 24 modules has a type with more than one result.

`-mcpu=mvp` removes the bulk-memory instructions, and the module then has byte loops instead. That is an escape hatch, not a target: `memory.fill` and `memory.copy` are easier to translate well than the loops they replace. §9.4 says the README must list the supported features. The cleanest statement is "the default feature set of Zig 0.15 for wasm32", with the list above, and the decode of the `0xFC` prefix should be designed in now.

### 1.3 Every real Zig program needs `call_indirect`, element segments, and traps

A module with no function pointers in the source still has them. The `panic.zig` test has none, and its ReleaseSafe module has a table of 4 entries, an element segment, 6 `call_indirect`, and 22 `unreachable`, because the panic machinery of the standard library calls through function pointers and safety checks trap. Debug modules have about 150 `unreachable`. So the order of work is `i64`, blocks and branches, memory accesses, then `call_indirect` and traps, and only then is any program compiled with safety on translatable. Nothing here changes the design of §9.4, which already covers tables and traps, but it rules out treating them as late features.

### 1.4 Output and exit status

Two things stand between a translated Zig program and a test that checks it:

- **There is no output device.** `nice.poke` to the I/O range writes ordinary memory in the emulator, so a program's output vanishes. The only visible target is the 2004 screen at `0x400`, which the emulator prints with `-s`. That screen overlaps the code of any program longer than 1024 words, which is every Zig program. A console device at a fixed I/O address, documented in the emulator's README as an emulator property like the screen, and matched later by the FPGA's UART, is the smallest useful step. The 2004 screen then stays only for the example programs.
- **A trap looks like success.** §9.4 makes the default trap handler a `HALT`. The emulator then exits with status 0, exactly as it does after `main` returns, and R1 holds a code from 1 to 7 that looks like a return value. The runtime test harness cannot tell the two apart without knowing the handler's address. §5.3 already defines an abnormal halt: a reserved control word halts the processor, the emulator reports "reserved control instruction", and it exits with status 2. The default handler can end in one, written as a `.DAT`, with one sentence in §9.4. If writing a reserved word deliberately is unwelcome, the alternative is to define a `TRAP` command in §5.3 next to `HALT`, which is a larger change to the ISA.

### 1.5 Decide whether a second module may be translated as a library

§9.4 says a program contains at most one wasm module. §9.3 says the runtime library's labels start with `__`, and §9.4 says an export whose name starts with `_` gets no label. Together these make it impossible to build any part of the runtime library from Zig or C.

The runtime library still needs integer division and remainder, `i64` multiply, divide, and remainder, `clz`, `ctz`, and `popcnt` for both widths, and floating point. The float test program alone needs `f32.add`, `f32.mul`, `f32.div`, `f32.convert_i32_u`, `f64.promote_f32`, `f64.sqrt`, and the saturating conversions. A complete `f32` and `f64` library is about 70 routines, and IEEE 754 rounding is hard to get right by hand in assembly. Compiler-rt, which ships with Zig, implements most of them with integer operations on the bit patterns. Compiled to wasm and translated, they would become NICE routines with no new assembly. A few routines, such as the rounding functions, use float arithmetic internally and would need integer-only versions.

That route needs a translator mode for a library module: no memory, no globals, no `___wasm_start`, a label prefix other than `W.`, and exports that get `__` labels. It needs one sentence in §9.3 or §9.4 that allows it. It costs nothing to allow now and would be awkward to retrofit after the label rules are relied on.

### 1.6 The memory budget

Zig's default layout is 17 pages: a 1 MiB stack at byte 0, then the data segment at byte 1048576. The translator reserves that as 278528 words and clears them in about 313000 steps. On the emulator that is 5 ms, so the README's warning about start-up time overstates the cost. The real constraint is the FPGA's RAM: linear memory costs one word for every four bytes, and the NICE stack and the program need room as well. `--stack` and `--initial-memory` are the knobs, and the README's values are right for tests.

Two things follow:

- `std.heap.wasm_allocator` grows the memory. The alloc test has `memory.grow`. §9.4 says the translator caps the reservation and that `memory.grow` returns −1 at the cap. With the cap equal to the initial size, every allocation fails. The option that sets the cap should exist before the first allocator-using program is tried.
- The zero loop must skip the data segment, as §9.4 says. With Zig's layout that is two ranges, below and above the data. A data segment that ends inside a word shares that word with the zero region, so the second range starts at the next word.

## 2. Bugs

### 2.1 A name section can inject assembly

`parse_custom` takes function names from the name section, and `wrap` writes them into a comment: `; Function 3: name`. Nothing checks the name. A module whose name section holds `f\n        HALT` produces a comment line followed by a `HALT` line, which assembles and runs: I confirmed it with a 60-byte module, and the program halted after 15 steps where the `HALT` was placed. The name section is attacker-controlled in the sense that matters here: the translator promises to translate nothing wrongly, and a comment must not become code.

**Fix.** Keep only printable ASCII in names used in comments, or drop the name when it contains anything else. The `; Translated from {source}` line has the same hole through the file name. Add an `errors.py` or `run.py` case with a newline in a name.

### 2.2 `__wasm_call_ctors` is not type-checked

`Translator.__init__` checks that the start function has no parameters and no results, but it takes `__wasm_call_ctors` as it comes. A module that exports a function with parameters under that name is called with whatever R1 and R2 hold. Clang's `__wasm_call_ctors` has no parameters, so this is only a missing check, but it should mirror the start function's.

### 2.3 `global.set` on an immutable global is accepted

The `Global` dataclass records `mutable`, and nothing reads it. An invalid module that sets an immutable global translates and runs. Minor, but it is one line.

### 2.4 Duplicate export names reach the assembler

Two exports with the same name are invalid wasm. The translator emits the label twice, and the assembler reports the duplicate with line numbers in the joined file, which the user never sees. A check in `Translator.__init__` would name the export.

### 2.5 `main` is called with undefined arguments

Both clang and Zig export `main` as `(i32, i32) -> i32`. LLVM renames the user's `main` to `__original_main` and synthesizes the wrapper, which is why `answer.wasm` has two functions. The wrapper ignores its arguments, but a C `main(int argc, char **argv)` would read R1 and R2, and R1 holds whatever `___wasm_start` left. §9.3 should say the start-up code passes R1 = 0 and R2 = 0, and the two start-up files should do it. That is two instructions and an update to three `.expected` files.

## 3. Small points in §9.4

### 3.1 `peek` and `poke` take `i32`, so Zig cannot write an I/O address

The I/O range `0xFFFFFF00`–`0xFFFFFFFF` is negative as `i32`, and Zig rejects `poke(0xFFFFFF00, c)` with "type 'i32' cannot represent integer value". The wasm type is right, but the text should say that Zig code declares the imports as `extern "nice" fn poke(addr: u32, val: u32) void` and `extern "nice" fn peek(addr: u32) u32`, which gives the same wasm type.

### 3.2 "Replaces each call with the instruction shown"

With the operand stack in frame words, `peek` is not one instruction: the address must be fetched into a register first, and the result stored. Say "performs the access shown" so that the §8.2 promise, one access per call in program order, stays the rule and the instruction stays an illustration.

### 3.3 Say what the exported `main` looks like

§9.4 says Zig code supplies `main` as `export fn main() i32`. True, but the module's export `main` is the two-argument wrapper, and the user's function is `__original_main`, which gets no label. A sentence here saves the reader from looking for `___original_main`.

### 3.4 The self-hosted Zig backend is not usable yet

With `-fno-llvm`, Zig 0.15.2 writes the `__stack_pointer` global as `41 80 80 40 0b`. By the LEB128 rules the last byte's sign bit makes that −1048576, and both my decoder and `nicewasm.py` read it so. Every stack access in such a module is then out of bounds. The LLVM backend is the default in every optimize mode, so nothing in this repository needs to change, but the README should not suggest `-fno-llvm`, and a module from it should not be used as a test vector.

### 3.5 Strip debug sections

ReleaseSafe and Debug modules carry DWARF custom sections that make up almost all of the file: `fmt.zig` in ReleaseSafe is 447 KB, and 12 KB with `-fstrip`. The translator skips them, but the README's command line should include `-fstrip`.

## 4. What the modules look like

For planning, the shape of real modules from Zig 0.15.2:

| Module | Mode | Functions | Instructions | Declared locals | Data (bytes) |
|---|---|---|---|---|---|
| bytes | ReleaseSmall | 4 | 101 | 4 | 12 |
| bytes | ReleaseSafe | 16 | 1936 | 61 | 342 |
| bytes | Debug | 41 | 9567 | 2046 | 582 |
| fmt | ReleaseSmall | 23 | 3240 | 91 | 3840 |
| fmt | ReleaseSafe | 23 | 5161 | 100 | 370 |
| alloc | ReleaseSmall | 9 | 725 | 24 | 40 |

- `local.get`, `local.set`, `local.tee`, and `i32.const` are half of all instructions in release builds and 70% in Debug. With the current scheme each is a 3-word `MOVE`, so a Debug module of 9567 instructions becomes roughly 30000 words. That fits the emulator with room to spare. Whether it fits the FPGA depends on its RAM, and a later translator that keeps the top of the stack in registers can shrink it without any change to §9.4.
- Wide accesses (`i32` and `i64` loads and stores) outnumber byte and halfword accesses ten to one in release builds. The fast path for an address that is a multiple of 4, which §9.4 allows, is where the time goes, not the byte extraction.
- Every ReleaseSafe and Debug module has a table, an element segment, `call_indirect`, `br_table`, `select`, `unreachable`, `memory.copy`, and `memory.fill`. Every module has `__stack_pointer` as global 0 and exports `memory`.

## 5. What is correct

- **Frames.** `MOVE @--R13, R12` and `MOVE R12, R13` put the saved FP at FP, the return address at FP + 1, and the first stack argument at FP + 2, which is where `local` puts parameter 4 and up. `SUB R13, R13, n_slots + max_depth` leaves R13 at the lowest frame word, so an interrupt routine's pushes land below every live word.
- **Calls.** Stack arguments are pushed last to first from frame words addressed by R12, so the pushes cannot disturb them. Register arguments come after, the return address is pushed with `ADD @--R13, 2, R15` before a 2-word `MOVE`, and the caller removes the stack arguments. The result is written to the slot of the first argument after the call. The `params` and `sum5` tests cover six and five arguments.
- **ALU operations.** `ADD @a, @a, @b` with the destination equal to s0 is safe because §5 evaluates both sources before the destination is written.
- **The zero loop** clears exactly `pages × 16384` words: 16 per pass, and the count divides. The `zero` test checks the word after the memory. Writing 0 to an untouched emulator page allocates nothing, so the loop is free on the emulator.
- **The reader** rejects 5-byte LEB128 values that do not fit, accepts the padded encodings LLVM uses for `call` and `call_indirect`, and handles `i32.const −2147483648`.
- **Labels.** `W.f12`, `W.f12.ret`, `W.g0`, `W.zero`, and `_name` are valid assembler symbols that cannot clash with each other, with C names, or with a mnemonic. `__original_main` and other `_` exports correctly get no label.
- **Section order** follows the specification, with the data count section before code.
- **Scale.** The assembler takes 7.5 s for 196000 lines, the emulator loads a 614000-word `.bin` in 0.1 s and runs 20 million steps in 0.3 s.

## 6. Resolution

Resolved on 2026-10-14:

- §1.1: the operand stack is typed, with one word per `i32` and two per `i64`, low word first. `i64` works in parameters, results, locals, globals, and a few instructions.
- §1.2: the translator's README states Zig 0.15's default feature set as the target. The `0xFC` instructions are decoded, so far only to name them in an error.
- §1.3: `unreachable` traps. The README lists the order of the next features.
- §1.4: the emulator has a console at `0xFFFFFF00` (ISA.md §8.3). The default trap handler is the reserved control word `0x0FE00000`, so the emulator exits with status 2 after a trap.
- §1.5: ISA.md §9.3 and §9.4 allow library modules, with their own label rules. The translator does not implement them yet.
- §2.1–§2.4: fixed, each with a test.
- §2.5: the start-up code passes R1 = 0 and R2 = 0 to `main`.
- §3.1–§3.3: ISA.md §9.4 updated. §3.4 and §3.5: the translator's README updated.

Left for later:

- §1.6: an option for the memory cap, needed with `memory.grow`, and the zero loop's skipping of data segments. Neither instruction nor data segments are supported yet.

## 7. Second round, commit 377a620

Reviewed on 2026-10-14: `translator/nicewasm.py`, its tests and README, `runtime/`, and ISA.md §8.3, §9.3, and §9.4 at commit 377a620 ("Review: record how the wasm review was resolved"), which resolves §1 to §3 above as §6 says. The diff from the first version of the translator was read line by line for regressions, each resolved item was checked against the code and its test, every `make test` and `make typecheck` was run, and the translator was run on about twenty hostile or odd modules: padded and overlong LEB128 numbers, a memory of 0 pages, invalid mutability and export kinds, a start function that is an import, dead code after `unreachable` and `return`, an `i64` argument that would need R4 and R5, `local.set` on a stack parameter, and an import and an export of the same name.

### 7.1 Confirmed fixed, with no regressions

Every item in §6 is done as described. The typed operand stack puts an `i64` in two frame words, low word first, and `i32.wrap_i64` and the two extends write the words in the right order when the value stays in place. `assign_args` gives `i32` arguments the same places as the old code, and puts an `i64` on the stack when it would need R4 and R5, as §9.3 requires. The call sequence pushes stack arguments from frame words that the pushes cannot disturb. The trap sequence leaves R2 at its own first instruction, and the default handler halts the emulator with status 2. Names from the module and the file name reach comments only as printable ASCII. The four checks of §2 each have an `errors.py` case, and the start-up code passes R1 = 0 and R2 = 0. The old test cases pass unchanged.

### 7.2 Bug: a 10-byte negative `i64` constant is rejected

`Reader.leb` sign-extended the result only while the shift was below 64. A signed LEB128 number of 64 bits may take 10 bytes, and after the tenth the shift is 70, so the extension was skipped, the result was a positive number of 70 bits, and the range check reported "integer too large". The most negative `i64`, −2⁶³, has no shorter encoding, so `i64.const -9223372036854775808` and an `i64` global with that initial value could not be translated at all. Any negative constant padded to 10 bytes failed the same way. The guard is older than this review and did no harm while only 32-bit numbers were read.

**Fixed** in this round: the guard is gone. The `i64min` case in `run.py` has the most negative `i64` as a constant and as a global's initial value, and −1 and 3 padded to 10 bytes. `errors.py` checks that a padding that does not repeat the sign is still "integer too large", for a 5-byte `i32` and a 10-byte `i64`, and that an eleventh byte is "integer too long".

### 7.3 The library-module rules need two changes

- §9.4 says a library module has no globals, and the translator rejects one that does. Both test modules, `sum5.wasm` from clang and `answer.wasm` from Zig, have `__stack_pointer` as global 0, although no function in either touches the shadow stack. Compiler-rt built by either toolchain will have it too, so the rule as written rejects every library module. The rule should allow globals that no instruction reads or writes.
- §9.4 allows any number of library modules but gives the translator the fixed prefix `WL.`, so two modules both define `WL.f0`. The prefix needs the module's name, as `L.unit.n` has for C. §9.3 also still says that all the runtime library's labels start with `__`, which the `WL.` labels will not.

Both are left for when library modules are implemented.

### 7.4 Nits

- An import and an export of the same name both become `_name`. Calls to the import then reach the module's own function, and a hand-written `_name` is a duplicate that the assembler reports with line numbers in the joined file, as duplicate exports were before §2.4. No toolchain produces this, and a check would cost one line.
- Some invalid modules are accepted: a mutability byte other than 0 or 1, a memory or table export whose index does not exist, and untyped code after `return` or `unreachable`, which wasm validation still checks. None produces wrong code, but the README's claim that an invalid module is an error overstates it, and the dead-code case matters once blocks are added.
- The README says translated code uses only R1–R4, R12, R13, and R15. The zero loop uses R5 and R6, and the `[M]` instructions write the flags. That is within §9.3, but the sentence is no longer true. The README also does not say that memory and table exports are ignored, and Zig always exports `memory`.
