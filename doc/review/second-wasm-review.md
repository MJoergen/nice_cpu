# Second review of the wasm path: translator, float library, and §9.4

Reviewed on 2026-10-14: `translator/nicewasm.py`, its tests and README, `runtime/` with the float library, and `doc/ISA.md` §9.3 and §9.4 at commit 5449ef1 ("nicewasm: record the plan for smaller code in TODO.md"). At this commit the translator supports every wasm feature that clang and Zig emit by default, and the float library is in place. The goal was to find what is wrong or missing before the work on smaller code in `TODO.md` starts.

**How it was checked.** I read the translator against §9.3 and §9.4 and traced by hand the frame layout, the argument assignment for `i64` and `f64` pairs, the call and return sequences, the bounds checks, the unaligned loads and stores, the `i64` shifts and rotates, the signed comparisons, the division special cases, the trap stubs, the moves that branches make, and the parsing of element and data segments. I ran every `make test` and `make typecheck`. Then I ran the whole pipeline, translator, assembler, and emulator, on inputs the tests do not cover:

- Hand-written modules for edge cases: `i64` shifts by 0, 1, 31, 32, 33, 63, 64, and 65, `i64` comparisons with equal high words, division of the extreme values, `i64` and `f64` parameters on the stack, `local.set` to a stack parameter, `call_indirect` with five arguments, an `if` with a parameter, a `loop` with an `i64` parameter, recursion, and float conversions at the limits.
- Random tests against a Python model: 750 `i32` and `i64` operations; 12 memory scripts of 60 stores, fills, and overlapping copies each, followed by 30 loads of every width and a checksum of 256 bytes; and 5400 `f32` and `f64` operations, including every arithmetic, rounding, comparison, and conversion instruction, checked against numpy and Python's IEEE 754 arithmetic.
- Fresh compiler output: a C program with varargs, a structure passed by value, function pointers, bit-fields, a switch that clang turns into a lookup table, `__builtin_bswap32`, `long long` shifts, and float conversions, built with clang 18.1.3 at -O0, -O1, -O2, and -Os, with `-mcpu=mvp`, and with the default memory. Zig 0.15.2 programs with `std.fmt.bufPrint` of a `u64` and an `f64`, with `u128` and `f128` arithmetic, and with the integer builtins, in Debug, ReleaseSafe, ReleaseSmall, and ReleaseFast, with and without `-fstrip`.
- Options: `--no-bounds-checks` on the real programs, `memory.grow` from C with `--memory-pages`, and C constructors with and without `--export=__wasm_call_ctors`.

## Summary

**The translator is correct.** Every hand-written case, every random test of the integer and memory instructions, and every compiled program gave the result worked out by hand or by the model. The only wrong results came from the float library, and they have one cause.

- One bug in the float library, inherited from compiler_rt: `f32.div` and `f64.div` give 0 whenever the exact quotient is subnormal (§1).
- Two gaps in what the documented toolchain can build: struct copies in C need `-mbulk-memory`, and `long double` and `__int128` have no runtime routines (§2).
- One place where the translator is stricter than §9.4, one inaccurate reason in §9.4, stale text in three files, and six untested error paths (§3 and §4).

## 1. Bug: division flushes subnormal results to zero

`f32.div` and `f64.div` call `___divsf3` and `___divdf3`, which come unchanged from Zig's compiler_rt. Both return 0 when the exact quotient is in the subnormal range. The source says so: "Flush denormals to zero. In the future, it would be nice to add code to round them correctly." (`compiler_rt/divsf3.zig` line 192 and `compiler_rt/divdf3.zig` line 211 in Zig 0.15.2). Examples, as bits:

| Operation | Gives | Should give |
|---|---|---|
| `f32.div 0x00FFFFFF, 2.0` | `0x00000000` | `0x00800000`, the smallest normal |
| `f32.div 0x00800000, 2.0` | `0x00000000` | `0x00400000` |
| `f32.div 0x00000001, 1.5` | `0x00000000` | `0x00000001` |
| `f64.div 1.0, DBL_MAX` | `0` | `0x0004000000000000` |
| `f64.div 0x0000000000000003, 2.0` | `0` | `0x0000000000000002` |

Of 60 random divisions, the 22 whose result was subnormal were all wrong, and the 38 with a normal result were all right. In 5400 random float operations, the four failures were all divisions with subnormal results, and 3600 random operations without division all passed. Addition, subtraction, multiplication, `sqrt`, `demote`, and `promote` handle subnormal operands and results correctly, including the carry from the largest subnormal into the smallest normal.

The WebAssembly specification requires IEEE 754 results with subnormals, and §9.4 says a translator must keep them. The runtime README says the division routines round to nearest, which is not true for these results.

**Fix.** Either add a correctly rounded subnormal path to the two routines in `float.zig`, as `float.zig` already does for `sqrt` and the roundings, or record the departure in ISA.md Appendix B and the runtime README. In both cases add the first two lines of the table to the `float32` and `float64` cases in `run.py`, which have no division with a subnormal result today.

**Resolved**: `float.zig` now has its own `__divsf3` and `__divdf3`, which divide the significands bit by bit and round once, also into the subnormals. They replace compiler_rt's and make `float.asm` about 1200 words smaller. They agreed with the host's division on 20 million random operands of each type, many of them subnormal, and with numpy on 797 random divisions through the translator, assembler, and emulator. `run.py` has the first two lines of the table for `f32`, and the last two for `f64`.

## 2. Gaps in the C toolchain

### 2.1 Struct copies import `memcpy`

Clang 18's default wasm32 features are `mutable-globals` and `sign-ext`, without bulk memory, as the translator's README says. The consequence is not said: every copy that LLVM does not inline becomes a call to `memcpy`, which `-nostdlib` and `--allow-undefined` turn into the import `env.memcpy`. A 400-byte structure assignment at -O2 did this, with and without `-mcpu=mvp`. The translator accepts the import, because `memcpy` is a C identifier, and the assembler then stops with `undefined symbol '_memcpy'`. The same happens with `memset` and `memmove`. A routine in `lib.asm` could not serve these imports anyway, because they take byte addresses in linear memory and a C-ABI routine would take word addresses.

With `-mbulk-memory`, LLVM emits `memory.copy` and `memory.fill` instead, and the same program translates and runs correctly. Zig is not affected, because its compiler_rt is inside the module.

**Fix.** Add `-mbulk-memory` to the clang command line in the translator's README and in the `wasm` target of its Makefile, and say why. The test programs happen not to need it, so `make wasm` does not catch the omission.

**Resolved**: the README and the Makefile use `-mbulk-memory` and say why. Rebuilt with it, the C test modules differ only in their `target_features` section.

### 2.2 `long double` and `__int128` have no runtime routines

In wasm32, `long double` is a 128-bit float and `__int128` exists, so clang imports `__addtf3`, `__multi3`, `__udivti3`, `__floatsitf`, `__fixtfsi`, and the like from `env`. The translator accepts them and the assembler fails on `___addtf3`. The failure is late and cryptic, and nothing in the README says these types are unsupported. Zig programs with `u128` and `f128` are fine, again because compiler_rt is inside the module.

**Fix.** Say in the README that `long double` and `__int128` are not supported from C. §9.3 reserves names that start with `_` for the runtime library, so an `env` import whose name starts with `__` is a request for a runtime routine, and the translator could reject it with a message that names the type.

**Resolved**: ISA.md §9.4 now says the translator rejects an `env` import whose name starts with `_`, and the translator names both types in the message. The README says they are not supported.

## 3. The specification and the translator

### 3.1 Results that would fit in registers are rejected

§9.4 says results go in registers by the rules for arguments, and that the translator rejects a function type whose results do not all fit in R1–R4. The translator rejects every type with more than one result, for functions, imports, and `call_indirect`; a block type with several results is fine. §9.4 leaves the supported features to the translator, so this is allowed, but the README lists "a function has at most one result" under the supported features and not under "not supported yet". Neither clang nor Zig emits such a type today, so this is a documentation point.

**Resolved**: the README lists function types with more than one result under "not supported yet".

### 3.2 The reason given for `--export=__wasm_call_ctors` is wrong

§9.4 says that clang puts constructor calls in `__wasm_call_ctors`, "so link with `--export=__wasm_call_ctors` to have them run". They run without the export: with `--no-entry` and no export, wasm-ld wraps every exported function in a function that calls `__wasm_call_ctors` first, visible in the name section as `main.command_export`. The constructors then run on every call of an exported function, which matters when C code calls more than one. With the export, wasm-ld does not wrap, and `___wasm_start` calls the constructors once. The advice is right and the reason should be this one. I confirmed both with a constructor that adds to a counter: it ran once in both builds.

A library module may also export `__wasm_call_ctors`. The translator gives it the label `___wasm_call_ctors`, as it does every export of a library, and never calls it. Two library modules with constructors would define the label twice. No library module has constructors today, but the translator could reject the export as it rejects a start function.

**Resolved**: §9.4 gives the reason above, and the translator README says it too. §9.4 and the translator now reject a library module that exports `__wasm_call_ctors`.

## 4. Documentation and tests

### 4.1 Stale text

- The docstring of `nicewasm.py` still gives the usage without `--memory-pages`, `--library`, and `--library-memory`, and says the tool supports "some integer instructions, and only the i32 and i64 types".
- The README's "Globals" bullet says the initial value is an `i32.const` or `i64.const`. `f32.const` and `f64.const` are accepted, and the `floatdata` case tests them.
- The README's "Memory" bullet says the memory is "at its initial size", which the "Memory instructions" bullet above it contradicts. The `--memory-pages` paragraph also leaves out that the value must be below 65536.
- The comment in `test/control.c` says nicewasm does not support a switch that clang turns into a table in linear memory. It does, since data segments were added: the lookup-table switch in my C program ran correctly at -O2.

**Resolved**: all four are fixed. `test/data.c` now has a switch that clang turns into a lookup table, so the claim is tested.

### 4.2 Error paths without a test

CLAUDE.md asks for a test for every rule. These messages have no case in `errors.py`: "unexpected end of data", "name is not valid UTF-8", "expected a function type (0x60)", "function body runs past the end of the section", "too many locals", and the command-line check "the output file would overwrite the input; use -o". The `WasmError` for `--memory-pages` with a library in `Translator.__init__` cannot be reached, because `main` exits with the same message first.

**Resolved**: `errors.py` has a case for each message, and the unreachable check is gone.

### 4.3 Rust

The top-level README says Rust has a wasm32 target and has not been tried. There was no Rust toolchain on the review machine either, so this stays untested.

**Resolved** in 91e9be2: three `no_std` Rust programs, built with rustc 1.99.0 for `wasm32-unknown-unknown`, are now test modules. The translator README gives the Rust build.

## 5. What is correct

- **Frames and arguments.** Register parameters are copied below FP, stack parameters are read at FP + 2 and up, and an `i64` that would need R4 and R5 goes on the stack with everything after it, in both the caller and the callee. A `local.set` to a stack parameter writes the caller's argument word, which the caller never reads again. Confirmed with a six-parameter function of mixed `i32` and `i64`, and with `call_indirect` of five arguments.
- **Memory.** Every width at every byte offset, loads that cross one or two word boundaries, stores that change part of a word, fills and overlapping copies in both directions, and the bounds checks at the last bytes of the memory, with and without `memory.grow`, all agree with a byte-array model over about 1000 random operations.
- **Integers.** Shifts and rotates by every count class, including 32, 64, and counts whose low word is 0, division and remainder of the extreme values, signed comparisons through N XOR V after a borrow chain, and the bit counts and sign extensions all agree with the model over 750 random operations.
- **Floats** other than subnormal division: the arithmetic, `sqrt`, the four roundings with ties to even, `min` and `max` with NaN and signed zeros, `copysign`, the comparisons with NaN, the saturating and trapping conversions at their limits, `convert` from all four integer types with ties to even, `demote`, and `promote`.
- **Control.** `br`, `br_if`, and `br_table` move values down over other values without overwriting a word still to be read, an `if` passes its parameters to both branches, a `loop` takes its parameters back from a branch, and code after a branch is skipped up to the right `end` or `else`.
- **Real programs.** Clang output at -O0, which keeps every local in the shadow stack, and Zig Debug output, 65 KB stripped and 580 KB with its name and DWARF sections, translate and run with the expected console output. The names from the name section appear only in comments.
- **Options.** `--no-bounds-checks` changes no result on the real programs. `memory.grow` from C returns the old size, sets the new pages to 0, and returns −1 at the cap.
