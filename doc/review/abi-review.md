# Review of the C ABI and the WebAssembly mapping

Reviewed on 2026-10-14: `doc/ISA.md` §9.3 and §9.4 at commit f1ec763 ("ISA: add the WebAssembly mapping"), against the rest of ISA.md, the C standard, and the toolchain in this repository.

**How it was checked.** I read both sections against §4, §5, §8, §9.1, and §10 of ISA.md, and traced every code sequence by hand: the call and return sequences, the frame layout, the stack argument addresses, and the two examples. I checked the data model and the argument rules against C17 (6.5.2.2 on default argument promotions, 7.20 on exact-width types). I checked the label rules, the `.BLK` output, and the single-file command line against `assembler/niceasm.py` and its README. For the wasm side I checked the claims about clang, Rust, and Zig against what their wasm32 targets actually emit.

## Summary

**The mechanics are right.** The call sequences push the correct return address for a 2-word and a 1-word jump, the frame table agrees with the prologue and epilogue, the first stack argument is at mem[SP + 1] on entry, both examples assemble to what the text says they do, the compiler's and translator's label prefixes are valid labels that cannot clash with C names, and `.BLK` zeros are in the `.bin`, so "static data gets its initial values when the image is loaded" holds for zero-initialised data too.

The problems are in the rules around the mechanics:

- Three bugs: `float` is not promoted in variadic calls, which breaks `printf` (§1.1); the trap label has one underscore fewer than the memory label, so its C name is not what the text implies (§1.2); and the read-modify-write rule misses unaligned 32-bit and 64-bit stores (§1.3).
- Seven gaps, of which the first two matter most: nothing says how separately compiled units are combined, and the label scheme is only unique within one compilation (§2.1); and the runtime routine list stops at 32-bit multiply and divide (§2.2).
- Eight smaller ambiguities (§3).

## 1. Bugs

### 1.1 `float` arguments are not promoted in variadic and unprototyped calls

ISA.md:483 says "A `float` argument stays a `float`, even in a call to a variadic or unprototyped function."

C17 6.5.2.2p6 and p7 define the default argument promotions: in a call without a prototype, and for the arguments after the ellipsis in a variadic call, the integer promotions are applied and `float` is converted to `double`. A `va_arg(ap, double)` in the callee must therefore read a value that was passed as a `float` in the caller. With this rule, `printf("%f", x)` with a `float` x pushes one word, and `printf` reads two. Every portable variadic function that takes a floating-point argument breaks.

The `char` and `short` remark on the same line is correct. Their promotions change the type, not the representation, so no code is needed.

**Fix.** Replace the sentence with: "In a call to a variadic or unprototyped function, a `float` argument is converted to `double` and passed as two words, as C requires. `char` and `short` arguments need no code, because they are already one word."

### 1.2 The trap label has the wrong number of underscores

ISA.md:574 defines the memory label as `___wasm_memory`, three underscores, and says C code sees it as `__wasm_memory`. ISA.md:608 defines the trap label as `__wasm_trap`, two underscores, and ISA.md:620 says "the program may supply its own". By the rule at ISA.md:517, the C name of `__wasm_trap` is `_wasm_trap`. A C programmer who defines `__wasm_trap` gets the label `___wasm_trap`, which nothing jumps to.

The same paragraph does not say what a replacement looks like. The code and the address arrive in R1 and R2, which is the argument convention, but the trap is reached by a jump, not a call. So mem[SP] is not a return address, and SP is wherever the trapping function left it. A C replacement works only because it never returns.

**Fix.** Rename the label to `___wasm_trap` so that its C name is `__wasm_trap`, matching the memory label. State the C signature, `void __wasm_trap(int code, unsigned addr)`, and say that it is entered by a jump with the stack as the trapping function left it, so it must not return.

### 1.3 The read-modify-write rule misses unaligned wide stores

ISA.md:579 says "A store of fewer than 32 bits reads the word, changes the bytes, and writes it back."

An `i32.store` at a byte address that is not a multiple of 4 changes part of two words, and so does an `i64.store`. Both need the same read-modify-write, but the sentence does not cover them. The sentence before it says that such stores "must still work", so the intent is clear, but the rule as written only says how to do the narrow case.

**Fix.** "A store that changes only part of a word reads the word, changes the bytes, and writes it back." It is worth adding that the read and the write are two accesses, so an interrupt routine that writes linear memory between them loses its write.

## 2. Gaps

### 2.1 Nothing says how separately compiled units are combined

ISA.md:430 says the rules "let separately written C and assembly code call each other". The toolchain has no linker and no object format beyond `.bin`: `niceasm` takes one input file, every label is global, and a second definition of a symbol is an error. So a program is one assembly file, and the only way to combine units is to concatenate their assembly. Under that model three things clash:

- The compiler's labels `L.12` (ISA.md:518) are unique within one compilation. Two compiled units both contain an `L.1`.
- Two units with `static int count` both produce `_count`.
- Every compiled unit, and every hand-written file that follows §9.1, defines `SP .EQU R13` and `PC .EQU R15`.

**Fix.** Say how units are combined. If it is by concatenation, make the compiler's labels unique per unit, for example `L.<unit>.12`, and give `static` names a per-unit suffix in the same style, for example `_count.3`. Labels may contain a `.`, and no C identifier does, so neither can clash with an external name. Let the compiler emit R13 and R15 rather than `SP` and `PC`, or specify that the `.EQU`s come from one place.

### 2.2 The runtime routine list is incomplete, and two tools may bring their own

ISA.md:520–528 lists `__mul`, `__div`, `__mod`, `__udiv`, and `__umod`. A C compiler also needs `long long` multiply, divide, remainder, and shifts; `float` and `double` arithmetic and comparison; and conversions between the floating and integer types. None of these is named, and nothing says where the rest of the list lives. ISA.md:643 says the translator's "other runtime routines ... also have names that start with `__`. The translator's README lists them." If the compiler and the translator each bring their own `__` routines, a program that uses both may link two routines of the same name with different contracts.

A related point: the label `__mul` is the C identifier `_mul`. C reserves identifiers that begin with an underscore at file scope, so no portable C program defines it, but a wasm export named `_mul` (ISA.md:626) would.

**Fix.** State that there is one runtime library, shared by the compiler and the translator, that all its labels start with `__`, and name the file or README that lists them. Say that export names beginning with `_` are reserved for it.

### 2.3 The start-up code cannot find the module's start function

ISA.md:647 says "If the module has a start function, the start-up code calls it before it calls `_main`." ISA.md:530 says the start-up code is fixed code at address 0. That code cannot know whether a module exists or what its start function is called.

Note also that none of clang, Rust, or Zig emits a wasm start section. Clang puts global constructors in a function `__wasm_call_ctors` and calls it from its exported `_start` or `_initialize`. Rust and Zig need no constructors.

**Fix.** Have the translator always emit a fixed label, for example `___wasm_start`, that runs the start function or returns at once, and have the start-up code for a program with a module call it. Or make the translator, not the start-up code, responsible for the call. Mention `__wasm_call_ctors` as the case that occurs in practice.

### 2.4 The pointer rules do not say who converts

ISA.md:631–635 gives the two conversion formulas but not which side applies them. Wasm has no pointer type, so the translator cannot tell an `i32` pointer from an `i32` count. A C function imported from `env` therefore receives the raw byte address as an integer and must convert it itself, or the wasm side must convert before the call.

Two related cases are not covered:

- Function pointers. A wasm function pointer is a table index (ISA.md:606), and the table has no label, so C cannot call one and wasm cannot call a C address.
- Aggregates. Clang and Rust lower a by-value struct in an `extern "C"` signature to a pointer into linear memory, so only `i32`, `i64`, `f32`, and `f64` ever cross the boundary.

**Fix.** Say that the translator converts nothing and that an `i32` pointer arrives in C as a byte address. Either give the table a label, such as `___wasm_table`, with its two-word entry format, or say that function pointers do not cross the boundary. Add one sentence on aggregates.

### 2.5 Non-function imports are not covered

ISA.md:627 covers functions imported from `env`, and ISA.md:628 rejects other modules. Nothing covers an imported global such as `__stack_pointer` or `__memory_base` in position-independent output, an imported memory from `--import-memory`, an imported table, or an import from `nice` other than `peek` and `poke`.

**Fix.** "The translator accepts only function imports from `env`, and only `peek` and `poke` from `nice`. It rejects every other import."

### 2.6 The hidden struct-return pointer in a variadic call

ISA.md:480 says that in a call to a variadic function "every argument goes on the stack, the named ones included". ISA.md:488 says the result address is "a hidden first argument, before all others". For a variadic function that returns a structure, it is not clear whether the hidden pointer is on the stack or in R1.

**Fix.** Pick one. Keeping it in R1 is simpler, because `va_start` then needs no special case, and the callee returns it in R1 anyway.

### 2.7 The memory reservation cannot be capped

ISA.md:572 says "The translator reserves enough words for the module's maximum memory size, or for a limit it chooses if the module sets none." A module that declares the wasm maximum of 65536 pages requires 2³⁰ words, which no target has. The translator may choose a limit only when the module sets none.

**Fix.** Let the translator cap the reservation below the declared maximum, with `memory.grow` returning −1 at the cap, exactly as it already does at the reservation.

## 3. Ambiguities and small points

### 3.1 The initial stack pointer

ISA.md:530: "sets SP to the top of the memory the program may use". A push is `@--SP`, and SP points at the last word pushed, so the first push lands at SP − 1. If "top" means the highest usable word, that word is never used. Say "one past the highest word the program may use".

### 3.2 The trap address in R2

ISA.md:608: "the address of the instruction that trapped". One wasm instruction becomes several NICE instructions. Say which NICE address R2 holds, for example the first instruction of the sequence.

### 3.3 Unchecked accesses

ISA.md:580: "such an access uses the word that the formula above gives, wrapping modulo 2³²". Wasm computes the effective address as base plus offset without wrapping, and an address at or above 2³² is out of bounds. Say whether the byte address or the word address wraps.

### 3.4 `nice.peek` and `nice.poke` are I/O

ISA.md:582–587 say the translator "replaces each call with the instruction shown". These imports exist to reach devices, so they need the §8.2 promise: each one is performed exactly once, in program order, even when the result is unused. As written, an optimising translator may drop a `peek` whose result is dead.

### 3.5 Exact-width types

With `CHAR_BIT` 32, `int8_t`, `int16_t`, and their unsigned forms cannot exist, `int32_t` is `int`, and `int64_t` is `long long`. Code being ported hits this first, so it belongs in the data types table at ISA.md:434.

### 3.6 Bit-fields

ISA.md:447 does not cover a zero-width bit-field, which ends the current word, or a non-bit-field member that follows a partly used word, which starts a new word. The unused bits sit uneasily with "no padding" at ISA.md:446.

### 3.7 The frame chain

ISA.md:496 requires the frame layout "so that a debugger can follow the chain of frames", but a function "needs no frame pointer". A debugger can follow the chain only through functions that use one. Say so.

### 3.8 Interrupt routines in C

A C function cannot be an interrupt routine directly. It must save and restore R1–R6 (ISA.md:494) and end in `RTI`, and a C function does neither. One line about an assembly wrapper that saves R1–R6, calls the C function, restores them, and executes `RTI` would close this.

### 3.9 Other differences from NICE

ISA.md:645 lists only the shift count. NICE also has no arithmetic right shift, so `shr_s` is the two-instruction sequence of §5.2. That is a consequence of "a translator must keep those results", not an error, but it is as much a difference as the count.

## 4. What is correct

- **Calls.** `ADD @--SP, 2, PC` takes one constant word, so PC reads as the start of the 2-word `MOVE PC, label`, and adding 2 gives the address after it. The 1-word `MOVE PC, Rx` form adds 1. The return pops it, so SP is back where it was.
- **Frames.** After `MOVE @--SP, R12` and `MOVE R12, SP`, FP points at the saved FP, FP + 1 is the return address, and FP + 2 is the first stack argument, which agrees with "mem[SP + 1] on entry". `SUB SP, SP, n` leaves SP at FP − n, the lowest local, which agrees with §9.1.
- **Argument registers.** Because allocation is in order and stops at the first argument that does not fit, the free registers are always a contiguous suffix of R1–R4, so "the next two free registers" is well defined.
- **The C example.** `@1[SP]` is mem[SP + 1], the first stack argument. The call pushes the address of `ADD SP, SP, 1`. The flags are untouched because no `[M]` is used.
- **The wasm example.** `SHR` and `SHL` are the aliases of `0>0` and `0<0` in §5.2 and in the assembler. `@___wasm_memory[R5]` is mode 111 with a label as the constant, which §10.2 allows. The byte extraction matches the formula at ISA.md:570, and it uses only the scratch registers R5 and R6.
- **Labels.** The assembler accepts `[A-Za-z_][A-Za-z0-9_.]*`, so `_main`, `___wasm_memory`, `L.12`, and `W.f12` are all valid, none is a mnemonic or register, and a `_`-prefixed name can never be one.
- **Zero-initialised data.** `.BLK` ranges are expanded into zero words in the `.bin`, so the loader sets them.
- **The data model.** Every type's size is a multiple of `char`, `long` holds at least 32 bits, and `long long` holds 64, so the model is permitted by C17 5.2.4.2.1. `unsigned char` promotes to `unsigned int`, which is also permitted.
- **Return values.** The register rules for single-word and two-word results agree between §9.3 and §9.4, and "the lower-numbered register holds the low word" matches R1 low, R2 high.

## 5. Second round

Reviewed on 2026-10-14: `doc/ISA.md` §9.3 and §9.4 at commit da65885 ("ISA: fix the findings of the ABI review"), which addresses every item in §1 to §3 above. Each change was checked against the rest of ISA.md and the assembler. The rules now agree with C17 6.5.2.2 on `float` promotion, keep the hidden result pointer in R1 in both the argument and the return-value rules, use labels `L.unit.n` and `_name.unit` that the assembler accepts and that cannot clash with external names or with each other, name the trap label so that its C name follows the `_name` rule, and say what the review asked for on partial stores, unchecked addresses, `peek` and `poke`, the memory cap, imports, pointer conversion, `shr_s`, exact-width types, bit-fields, the frame chain, interrupt routines, and the initial SP.

Three things in the new text need another pass, and there are three nits.

### 5.1 The trap override contradicts the no-linker rule

ISA.md:636 says `___wasm_trap` is in the runtime library with a `HALT` as its default, and that "a program may supply its own". ISA.md:522 says every label must be unique in the whole program, that the assembler rejects a second definition, and that the runtime library is always joined in. So a program that supplies its own `___wasm_trap` never assembles.

**Fix.** Put the default in its own file of the runtime library, joined only when the program defines no `___wasm_trap`. Or have the trap jump through a vector word, `___wasm_trap_vector`, that holds the default's address and that a program may overwrite at run time.

### 5.2 Hand-written files are missing from the join order

ISA.md:522 lists the start-up code, the compiled units, the wasm module, and the runtime library. ISA.md:528 then says what hand-written files may define, and they are the "assembly code" that §9.3 exists for, but the order does not say where they go.

The order also needs a rule on `.ORG`. A joined file that moves the location counter moves every file after it, the runtime library included.

**Fix.** Add hand-written files to the order, for example with the compiled units, and say that only the start-up code may use `.ORG`.

### 5.3 How the start-up code knows about the wasm module

ISA.md:544: the start-up code is one fixed file at address 0, yet it calls `___wasm_start` only "if the program has a wasm module". That needs either two versions of the start-up code or an option when the program is joined.

**Fix.** One sentence saying which.

### 5.4 Nits

- The examples at ISA.md:552 and the `i32.load` example still use `SP` and `PC`, though ISA.md:528 now says compiled code writes R13 and R15. Say the examples use the aliases for readability, or switch them.
- ISA.md:652: clang's wasm C ABI, and Rust's since the spec ABI became the default in 1.87, pass a structure with a single scalar member as that scalar. Only larger structures go by pointer. The claim that only the four scalar types cross the boundary stays true.
- ISA.md:670: `__wasm_call_ctors` starts with `_`, so by the export rule at ISA.md:640 it gets no label. The translator must call it by its own `W.` label. Worth a word, so that a reader does not look for `___wasm_call_ctors`.
