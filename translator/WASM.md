# NICE WebAssembly mapping

How nicewasm, the translator, maps WebAssembly to NICE. It builds on the C
ABI of [ABI.md](../runtime/ABI.md). The instruction set is
[ISA.md](../doc/ISA.md), and "ISA §8.2" refers to a section of it.

Rust and Zig assume 8-bit bytes, so they cannot use the C ABI's one-word `char` ([ABI.md](../runtime/ABI.md)). Instead, their compilers emit a wasm32 WebAssembly module, and a translator turns the module into NICE assembly. Clang can do the same for C code that needs 8-bit bytes. These rules say how a module maps onto NICE, so that translated code, C code, and assembly code can work together.

The WebAssembly specification defines what each wasm instruction does. A translator must keep those results, except where this section says otherwise. Which wasm features a translator supports is up to the translator, and its README must list them. A program contains at most one wasm module, not counting library modules.

**Library modules.** Runtime routines ([ABI.md](../runtime/ABI.md)) may be compiled to wasm, for example from compiler-rt, and translated as a library module. A library module differs from a program's module in these ways:

- The translator is given a name for it, which is a C identifier. The labels the translator makes for itself start with `WL.name.` instead of `W.`, for example `WL.float.f3`, so that the labels of two library modules cannot clash.
- Each exported function gets the label `_name`, including when the name starts with `_`. So the export `__divdi3` gets the label `___divdi3`.
- It has no start function, it does not export `__wasm_call_ctors`, and it uses neither `memory.size` nor `memory.grow`. The translator rejects one that does, and it emits no `___wasm_start`.
- Its memory and its globals are its own, separate from those of the program's module. Compilers use them for a stack, for example to pass 128-bit values. The memory is at the label `WL.name.memory`. Its words are part of the program image, with the values that its data segments give and 0 elsewhere, like C static data ([ABI.md](../runtime/ABI.md)).
- The translator reserves only the start of the memory, as much as the module's stack and data need. It chooses the size, for example from the initial value of the stack pointer. A whole page of 16384 words would cost more RAM than the routines themselves. An access past the reserved part traps as out of bounds (code 2), unless the bounds checks are left out.

A program may contain any number of library modules. They go with the runtime library, after the program's module.

**Values.**

| Wasm type | Words | Same as the C type ([ABI.md](../runtime/ABI.md)) |
|---|---|---|
| `i32` | 1 | `int` or `unsigned int` |
| `i64` | 2 | `long long` or `unsigned long long` |
| `f32` | 1 | `float` |
| `f64` | 2 | `double` |

**Linear memory.** Linear memory is byte-addressed. It is stored four bytes to a word, starting at a word address chosen by the translator:

- Byte address *b* is bits 8·(*b* mod 4) + 7 to 8·(*b* mod 4) of the word at `MEMBASE` + ⌊*b* / 4⌋. Byte 0 of a word is its least significant byte, as in `.ASCII_B` (ISA §10.3).
- Wasm is little-endian, so an `i32` at a byte address that is a multiple of 4 is exactly one NICE word. An `i64` there is two words, low word first, as in [ABI.md](../runtime/ABI.md).
- A page is 65536 bytes, or 16384 words. The translator reserves words for the memory up to a cap. The cap is at least the module's initial size and at most its maximum size, if it declares one. The translator chooses it, for example by an option, because a module may declare a maximum that no NICE system has room for. `memory.grow` returns −1 if the new size would pass the cap.
- The words that active data segments set are part of the program image, like C static data ([ABI.md](../runtime/ABI.md)). The translator reserves the rest of the memory with `.RES` (ISA §10.3), so it is not in the image. Wasm requires new memory to be 0, so `___wasm_start` sets the initial pages to 0, except the words that data segments set, and `memory.grow` sets each new page to 0.
- The label `___wasm_memory` is `MEMBASE`, so C code can declare the memory as `extern unsigned __wasm_memory[];`.

Memory accesses must give the results wasm defines:

- An access may be at any byte address. The alignment hint in the instruction is not a promise, so an access that crosses a word boundary must still work. A translator may use a faster path when the address turns out to be a multiple of 4.
- A store that changes only part of a word reads the word, changes the bytes, and writes it back. Narrow stores do this, and so do `i32` and `i64` stores that are not at a multiple of 4. The read and the write are two accesses, so an interrupt routine that writes the same word between them loses its write.
- An access that goes past the end of the current memory size traps. A translator may offer an option to leave out these checks. Then the byte address *b* is (base + offset) mod 2³², and the word address `MEMBASE` + ⌊*b* / 4⌋ also wraps modulo 2³².

**Hardware access.** Linear memory cannot reach I/O devices or the rest of NICE memory. A module reaches them through these imports from the module `nice`. The translator replaces each call with code that performs the access shown:

| Import | Wasm type | Code |
|---|---|---|
| `nice.peek` | `(i32) -> i32` | `MOVE R1, @R1`: read the NICE word at the given word address. |
| `nice.poke` | `(i32, i32) -> ()` | `MOVE @R1, R2`: write the second argument to the NICE word at the first. |

These exist to reach devices, so the ISA §8.2 rule for data accesses applies to them as to any instruction. Each call is performed exactly once and in program order, even when the result of a `peek` is not used.

In Rust, they are declared in an `extern "C"` block with `#[link(wasm_import_module = "nice")]`. In Zig, they are `extern "nice" fn peek(addr: u32) u32` and `extern "nice" fn poke(addr: u32, val: u32) void`. Zig must use `u32`, because the I/O addresses `0xFFFFFF00`–`0xFFFFFFFF` do not fit in an `i32`. Both types become `i32` in wasm.

**Functions and calls.** A wasm function is a [ABI.md](../runtime/ABI.md) function whose parameter and result types are the C types in the table above:

- Parameters go in R1–R4 and on the stack, by the [ABI.md](../runtime/ABI.md) rules for a function that is not variadic.
- Results go in registers by the same rules that would apply if they were arguments. A function with no result returns nothing. The translator rejects a function type whose results do not all fit in R1–R4.
- R7–R13 and SR's I, E, and VBASE are preserved, as in [ABI.md](../runtime/ABI.md).
- Wasm locals and the wasm operand stack live in registers and in the function's frame on the NICE stack (R13).

The module's own stack is separate. Compilers for wasm keep the variables whose address is taken in linear memory, below the global `__stack_pointer`. That stack is ordinary module data, and the translator gives it no special treatment.

**Globals.** Each global is one word, or two for `i64` and `f64`, at a fixed address chosen by the translator. It starts with the value the module gives it.

**Tables and indirect calls.**

- Each entry of table 0 is two words: the address of a function, and a number for the function's type. Two types with the same parameters and results get the same number. An empty entry has address 0.
- `call_indirect` traps if the index is past the end of the table, if the entry is empty, or if its type number differs from the type of the call. Otherwise it calls the address with the "through a register" sequence of [ABI.md](../runtime/ABI.md).
- A wasm function pointer is an index into this table, not a NICE address.

**Traps.** A trap jumps through the word `___wasm_trap_vector`, with `MOVE PC, @___wasm_trap_vector`. R1 holds a code, and R2 holds the address of the first NICE instruction of the code for the wasm instruction that trapped:

| R1 | Cause |
|---|---|
| 1 | `unreachable` |
| 2 | Memory access out of bounds |
| 3 | Integer division or remainder by zero |
| 4 | Integer overflow: `div_s` of the most negative value by −1 |
| 5 | Conversion of a float to an integer that cannot represent it |
| 6 | `call_indirect`: index past the end of the table, or an empty entry |
| 7 | `call_indirect`: type mismatch |

The runtime library defines `___wasm_trap_vector` and starts it with the address of its default handler, `___wasm_trap`. The handler is the reserved control word `0x0FE00000` (ISA §5.3), so the processor halts with R1 and R2 as the trap left them. Unlike a `HALT`, this halt cannot be mistaken for the normal end of the program. The emulator reports it as an abnormal halt. A label may be defined only once ([ABI.md](../runtime/ABI.md)), so a program cannot replace `___wasm_trap`. Instead, it installs its own handler at run time by storing the handler's address in the vector. From C, that is:

    extern void (*__wasm_trap_vector)(int code, unsigned addr);
    ...
    __wasm_trap_vector = my_trap;

A handler is entered by a jump, not a call, so mem[SP] is not a return address, and SP is wherever the trapping function left it. A handler must therefore not return.

Running out of NICE stack is not detected, unlike in wasm. What happens then is undefined.

**Imports and exports.**

- An exported function or global whose name is a C identifier gets the label `_name`, as in [ABI.md](../runtime/ABI.md). So C code calls an exported wasm function `sum` as `sum`. Names that start with `_` are reserved for the runtime library ([ABI.md](../runtime/ABI.md)), so they get no label, and neither do names that are not C identifiers.
- A function imported from the module `env` is the [ABI.md](../runtime/ABI.md) function `name`, at the label `_name`. Rust, Zig, and clang put their `extern` functions in `env` unless told otherwise.
- The translator rejects an import from `env` whose name starts with `_`. Such names are reserved for the runtime library ([ABI.md](../runtime/ABI.md)), and the translator calls the routines it needs itself. Clang imports them for routines that the runtime library does not have, such as `__multi3` for `__int128` and `__addtf3` for `long double`.
- The translator accepts only function imports from `env`, and only `peek` and `poke` from `nice`. It rejects every other import. This includes imported globals, memories, and tables, such as those that `--import-memory` or position-independent code produce.
- Labels that the translator makes for itself start with `W.`, for example `W.f12` for function 12. They cannot clash with C names, or with the C compiler's labels, which start with `L.`.

**Pointers at the boundary with C.** A wasm pointer is a byte address in linear memory. A C pointer is a word address. Wasm has no pointer type, so the translator cannot tell a pointer from a number, and it converts nothing. A pointer from wasm reaches C as an integer that holds a byte address, and the C code converts it:

- The C address of wasm byte address *p* is `__wasm_memory + p / 4`. This works only if *p* is a multiple of 4. C then sees the data packed four bytes to a word.
- To pass C data to wasm, it must be in linear memory. The byte address of the word at C address *q* is (*q* − `__wasm_memory`) × 4.
- Wasm code cannot reach C data outside linear memory, except through `nice.peek` and `nice.poke`.
- Only `i32`, `i64`, `f32`, and `f64` values cross the boundary. Clang and Rust pass a structure with a single scalar member in an `extern "C"` signature as that scalar. They pass any other structure as a pointer into linear memory, so C receives a byte address there too.
- Function pointers do not cross the boundary. A wasm function pointer is a table index, and a C function pointer is a NICE address.

**Runtime routines.** The translator uses the runtime library of [ABI.md](../runtime/ABI.md), which it shares with the C compiler. For `i32.mul`, and the `div` and `rem` of `i32` and `i64`, it uses the math unit of [SYSTEM.md §2](../doc/SYSTEM.md#2-math-unit) directly: it writes the operands to A and B, or C and D, and reads the result. With an option, for systems without the math unit, it calls `__mul`, `__div`, `__mod`, `__udiv`, `__umod`, and the `64` versions of the last four instead. Before a division or remainder, it checks the cases that wasm defines but C leaves undefined:

- division or remainder by zero traps (code 3)
- `div_s` of the most negative value by −1 traps (code 4)
- `rem_s` of the most negative value by −1 is 0.

Before it converts a float to an integer with `trunc`, it checks that the result fits. A NaN, or a value whose integer part does not fit, traps (code 5).

The routines for `i64` and floating point are in the same library and listed in its README.

**Other differences from NICE.**

- Wasm takes shift and rotate counts modulo 32, or 64 for `i64`. NICE uses the full count (ISA §5.2), so the translator must mask it first.
- NICE has no arithmetic right shift, so `i32.shr_s` becomes the two-instruction sequence of ISA §5.2.

**Start-up.** The start-up code is that of [ABI.md](../runtime/ABI.md). For a program with a wasm module, it calls `___wasm_start` before `_main`.

- The translator always emits `___wasm_start`, a [ABI.md](../runtime/ABI.md) function with no arguments and no result. First it sets the memory to 0, as described under Linear memory. Then it calls the module's start function, if there is one. Then it calls `__wasm_call_ctors`, if the module exports a function of that name. Otherwise it just returns. The name starts with `_`, so the export gets no label of its own (see Imports and exports), and the translator calls it by its `W.` label.
- Clang, Rust, and Zig emit no start function. Clang puts the calls to C++ constructors and `__attribute__((constructor))` functions in `__wasm_call_ctors`. Link with `--export=__wasm_call_ctors`, so that `___wasm_start` calls it once. Without the export, wasm-ld wraps each exported function in one that calls `__wasm_call_ctors` first, so the constructors run again on each call of an exported function. Rust and Zig need neither.
- Rust and Zig code supply `main` as an exported function, for example `#[no_mangle] pub extern "C" fn main() -> i32` in Rust or `export fn main() i32` in Zig.
- Clang and Zig both rename a `main` with no parameters to `__original_main`, and export a wrapper `main` of type `(i32, i32) -> i32` that ignores its arguments and calls it. So `_main` is the wrapper, and `__original_main` gets no label.

**Example.** With R1 holding a byte address *b*, and no bounds check:

    ; i32.load8_u
            SHR  R5, R1, 2               ; word index b / 4
            MOVE R5, @___wasm_memory[R5] ; the word that holds byte b
            AND  R6, R1, 3               ; b mod 4
            SHL  R6, R6, 3               ; bit position 8 * (b mod 4)
            SHR  R5, R5, R6
            AND  R1, R5, 0xFF

    ; i32.load, when b is a multiple of 4
            SHR  R5, R1, 2
            MOVE R1, @___wasm_memory[R5]
