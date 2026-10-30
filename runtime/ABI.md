# NICE C ABI

The calling conventions of the software for NICE, which the runtime library
implements. They are conventions, not hardware rules. The instruction set
is [ISA.md](../doc/ISA.md), and "ISA §9.1" refers to a section of it. The
WebAssembly mapping is [WASM.md](../translator/WASM.md).

These rules let separately written C and assembly code call each other. Compilers, runtime libraries, and assembly code that calls or is called from C must follow them.

**Data types.** A byte is one word, so `CHAR_BIT` is 32 and `sizeof` counts words.

| Type | Words | Notes |
|---|---|---|
| `char`, `signed char`, `unsigned char` | 1 | Plain `char` is signed. |
| `short`, `int`, `long`, and their unsigned forms | 1 | |
| `_Bool` | 1 | 0 or 1. |
| Enumerations | 1 | Same as `int`. |
| Pointers, `size_t`, `ptrdiff_t` | 1 | A pointer is a word address. `size_t` is `unsigned int`, and `ptrdiff_t` is `int`. |
| `long long`, `unsigned long long` | 2 | |
| `float` | 1 | IEEE 754 single precision. |
| `double`, `long double` | 2 | IEEE 754 double precision. |

- No type has exactly 8 or 16 bits, so `<stdint.h>` has no `int8_t`, `int16_t`, `uint8_t`, or `uint16_t`. `int32_t` is `int`, and `int64_t` is `long long`.
- A value of two words has its low word at the lower address. In a register pair, the lower-numbered register holds the low word.
- Every type has an alignment of one word. Structure members follow each other in declaration order. The only padding is the unused part of a word that holds bit-fields. A union's size is the size of its largest member.
- Bit-fields are allocated from bit 0 upward within a word. A bit-field that does not fit in the rest of the current word starts a new word, and so does a member that is not a bit-field. A bit-field of width 0 ends the current word. A plain `int` bit-field is signed.
- The null pointer is 0. Word 0 holds the first instruction (ISA §8.1), so no C object is ever at address 0.

**Registers.**

| Register | Use | Preserved across a call |
|---|---|---|
| R0 | Zero | — |
| R1–R4 | Arguments and return value | No |
| R5–R6 | Scratch | No |
| R7–R11 | Variables | Yes |
| R12 | Frame pointer, FP, when a function uses one; otherwise a variable | Yes |
| R13 | Stack pointer, SP (ISA §9.1) | Yes |
| R14 | SR: the flags X, C, Z, N, and V | No |
| R14 | SR: I, E, and VBASE | Yes |
| R15 | PC | — |

A function may change a preserved register only if it restores it before it returns. Only code whose purpose is to change I, E, or VBASE, such as a routine that enables interrupts, may leave them changed.

**Calls.** A call pushes the address of the instruction after the jump and then jumps. A return pops it into PC. The pushed address depends on the size of the jump instruction:

| Call | Code |
|---|---|
| To a label | `ADD @--SP, 2, PC` then `MOVE PC, label` |
| Through a register | `ADD @--SP, 1, PC` then `MOVE PC, Rx` |
| Return | `MOVE PC, @SP++` |

On entry to a function, mem[SP] is the return address. The return pops it, so after the call SP is the same as it was just before the call sequence.

**Arguments.**

- Arguments are assigned in order. A one-word argument goes in the next free register of R1–R4. A two-word argument goes in the next two free registers if both are free.
- Once an argument does not fit, it and all later arguments go on the stack. A structure or union argument always goes on the stack, so all arguments after it do too.
- In a call to a variadic function, every argument goes on the stack, the named ones included. The one exception is the hidden result address, which is always in R1 (see Return values).
- The caller pushes the stack arguments from last to first, so the first one ends up at the lowest address. A structure argument is copied onto the stack whole, with its first word at the lowest address. On entry, the first stack argument starts at mem[SP + 1], just above the return address.
- The caller removes the stack arguments after the call, for example with `ADD SP, SP, n`.
- In a call to a variadic or unprototyped function, a `float` argument is converted to `double` and passed as two words, as C requires. This applies to the arguments after the `...` and to every argument of an unprototyped call. `char` and `short` arguments need no code, because they are already one word.

**Return values.**

- A one-word value is returned in R1. A two-word value is returned in R1 (low word) and R2 (high word).
- For a function that returns a structure or a union, the caller passes the address of space for the result in R1, as a hidden first argument. The other arguments then start at R2, or on the stack in a call to a variadic function. The callee stores the result there and returns that address in R1.

**The stack.**

- SP points at the last word pushed, and the stack grows down (ISA §9.1). The ISA has no alignment rule, so neither does the stack.
- There is no red zone. An interrupt routine may push onto the stack at any time, so the words below SP may change between any two instructions.
- An interrupt routine must save and restore every register it uses (ISA §7.4), R1–R6 included.
- So a C function cannot be an interrupt routine by itself: it may change R1–R6, and it returns with `MOVE PC, @SP++`, not `RTI`. An assembly wrapper saves R1–R6, calls the C function, restores R1–R6, and executes `RTI`.

**Frames.** A function needs no frame pointer. If it uses one, it must build the frame this way. A debugger can then follow the chain of frames through the functions that use one:

                    MOVE    @--SP, R12      ; save the caller's FP
                    MOVE    R12, SP         ; FP points at the saved FP
                    SUB     SP, SP, n       ; n words for locals and saved registers
                    ...
                    MOVE    SP, R12         ; drop the locals
                    MOVE    R12, @SP++      ; restore the caller's FP
                    MOVE    PC, @SP++       ; return

| Address | Contents |
|---|---|
| FP + 2 + k | Stack argument word k |
| FP + 1 | Return address |
| FP | The caller's FP |
| FP − 1 to FP − n | Locals and saved registers, in an order the function chooses |

**Variadic functions.** Since every argument is on the stack, `va_list` is a pointer to the next argument word. `va_start` sets it to the word after the last named argument. `va_arg` reads the argument there and advances the pointer by its size in words.

**Symbol names.** The assembler's labels are case-sensitive, but they may not be mnemonics or register names (ISA §10.1).

- A C function or variable `name` with external linkage gets the label `_name`. So `main` is `_main`, and a C function called `move` does not clash with the mnemonic `MOVE`. Names with internal linkage are covered below.
- Every other label that the compiler emits contains a `.` (see Programs and units). No C identifier contains a `.`, so these cannot clash with external C names.

**Programs and units.** There is no linker. A program is one assembly file, made by joining these files in this order: the start-up code; the compiled units and hand-written assembly files, in any order; the translated wasm module if there is one ([WASM.md](../translator/WASM.md)); and the runtime library, which is `lib.nasm`, one of the muldiv files, `float.nasm` if the program uses it, and `trapmsg.nasm` if the start-up code installs the trap report ([runtime README](README.md)), in this order. Every label and `.EQU` name must therefore be unique in the whole program. The assembler rejects a second definition.

- Only the start-up code may use `.ORG`, because a `.ORG` in one file moves every file after it. Anything that must sit at a fixed address, such as an interrupt vector table (ISA §7.3), therefore belongs in the start-up code.

- Each compiled unit has a unit name, given when it is compiled, for example from the file name. It consists of letters, digits, and `_`, and it differs from the names of the other units in the program.
- The compiler's own labels are `L.unit.n`, for example `L.main.12`.
- A `static` function or variable at file scope gets the label `_name.unit`, for example `_count.main` for `static int count` in the unit `main`. A `static` variable inside a function gets one of the compiler's own labels.
- Two units that define the same external name both define `_name`, and the assembler rejects the program, as a linker would.
- Compiled and translated code writes R13 and R15 and defines no `.EQU` names. Hand-written files may define names such as `SP` and `PC`, but only one file may define each name. The examples in this section and in [WASM.md](../translator/WASM.md) use `SP` and `PC` for readability.

**Runtime routines.** NICE has no multiply or divide instruction, and no floating-point instructions. The compiler calls routines in the runtime library instead. They follow the rules above.

- There is one runtime library, shared by the C compiler and the wasm translator ([WASM.md](../translator/WASM.md)).
- A routine may be written in assembly, or translated from a library module ([WASM.md](../translator/WASM.md)).
- The labels of its routines start with `__`. Their C names start with `_`, which C reserves for the implementation at file scope. The labels inside a translated library module start with `WL.` ([WASM.md](../translator/WASM.md)), which no C name can produce.
- The multiply and divide routines, for one-word integers and for `long long`, come in two versions: one that uses the math unit of [SYSTEM.md §2](../doc/SYSTEM.md#2-math-unit), and one in software for systems without it. A program contains exactly one of the two.
- The table lists the routines for one-word integers. The runtime library's README lists all routines, including those for `long long`, floating point, and conversions between them.

| Label | Result in R1 |
|---|---|
| `__mul` | R1 × R2, the low 32 bits. The same routine serves signed and unsigned operands. |
| `__div`, `__mod` | Signed R1 / R2 and R1 % R2, rounding toward zero as C requires. |
| `__udiv`, `__umod` | Unsigned R1 / R2 and R1 % R2. |

Division by zero is undefined in C, so these routines may return any value for it.

**Device routines.** The runtime library also has routines for the devices of the emulator and the FPGA implementation, so that programs need not use their addresses. They are the console ([SYSTEM.md §1](../doc/SYSTEM.md#1-console-screen-and-read-counter)), the performance counters ([SYSTEM.md §3](../doc/SYSTEM.md#3-performance-counters)), and the emulator's character screen at `0xFFFF0000` ([SYSTEM.md §1](../doc/SYSTEM.md#1-console-screen-and-read-counter)). Unlike the routines above, a program calls them by name, so they are ordinary C functions: `nice_putc` has the label `_nice_putc`. External C names that start with `nice_` are reserved for them.

| C declaration | What it does |
|---|---|
| `void nice_putc(int c)` | Writes bits 7..0 of `c` to the console, through `___putc_vector` (below). |
| `int nice_getc(void)` | Waits for the next input byte from the console and returns it, 0 to 255. Returns −1 once the line's input has ended ([SYSTEM.md §1](../doc/SYSTEM.md#1-console-screen-and-read-counter)); a keyboard's bytes may still come after that. |
| `int nice_pollc(void)` | Like `nice_getc`, but returns −2 at once if no byte is waiting. |
| `void nice_print(const char *s)` | Writes the characters of `s` up to its first 0 to the console, with no newline, through `___putc_vector`. In assembly, one character per word. The C library's `nice_print` takes the bytes of a C string instead (runtime/README.md). |
| `unsigned long long nice_cycles(void)` | The cycle counter. |
| `unsigned long long nice_instructions(void)` | The instruction counter. |
| `void nice_screen_put(int col, int row, int c)` | Writes `c`, the character in bits 7..0 and its colors above ([SYSTEM.md](../doc/SYSTEM.md) §1), to column `col`, 0 to 79, of row `row`, 0 to 24. |
| `void nice_screen_clear(void)` | Writes a blank, `0x20`, to each of the screen's 2000 words. |

- Each routine makes the data accesses that its device needs, and no others. `nice_getc` reads the console until a byte is there or the input has ended; `nice_pollc` reads it once.
- `nice_putc` and `nice_print` write through `___putc_vector`, a word in `lib.nasm` that holds the address of the routine that writes one character. It starts as `___console_putc`, which writes bits 7..0 of R1 to the console, and the start-up code of a program under a monitor (below), or an assembly program itself, may store another routine in it. That routine follows these rules, takes the character in bits 7..0 of R1, and may change R1–R6 and the flags, so `nice_putc` and `nice_print` may too; `___console_putc` changes nothing. The input has no vector: the console's input is the line and the keyboard both, in the emulator's window and on a board.
- `nice_cycles` and `nice_instructions` read the low word and then the high word, as [SYSTEM.md §3](../doc/SYSTEM.md#3-performance-counters) describes. The rule there for interrupt service routines applies to them.
- The screen routines write ordinary memory on the emulator. On a system without a screen, the writes are ignored or land in RAM. With the emulator's option `-2004`, the screen is at `0x400`, and these routines do not reach it.

**Start-up.** The start-up code sits at address 0. It sets SP to one past the highest word the program may use, so that the first push lands on that word. If the program has a wasm module, it then calls `___wasm_start` ([WASM.md](../translator/WASM.md)). The runtime library has two versions of the start-up code, one with this call and one without, and a program uses the version that matches it. A third, `start_wasm_trap.nasm`, is the one with the call and also stores the address of the trap report of `trapmsg.nasm` in `___wasm_trap_vector` ([runtime README](README.md)). Then the start-up code calls `_main` with R1 = 0 and R2 = 0, so a `main(int argc, char **argv)` sees no arguments and a null `argv`. After `main` returns, the start-up code executes `HALT` with `main`'s return value still in R1. `exit(status)` is the routine `_exit`, which every start-up file defines: in these three, that same `HALT`, with the status in R1, so a program ends the same way from anywhere. Static data gets its initial values when the program image is loaded. Reset does not restore them.

**Programs under a monitor.** A system may boot from a monitor in a ROM at the bottom of memory and load programs into the RAM above it, as QNICE-FPGA does and as the monitor of [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65) will (MJoergen/NiceMonMEGA65#24). The ROM takes `0x0000`–`0x7FFF`, and a program for the monitor is assembled at `0x8000`, with `start_mon.nasm`, `start_wasm_mon.nasm`, or `start_wasm_trap_mon.nasm` in place of the three files above. The monitor's loader puts the image in memory, which initializes the static data and the wasm linear memory, so a program runs once per load. The monitor runs the program as a subroutine (ISA §9.1) on its own stack: it pushes a return address and jumps to `0x8000`, with E = 0 and these registers:

| Register | At entry |
|---|---|
| SP | The monitor's stack. The program may use the words from `0x8000` up to, but not including, this SP, and must leave room below it for the stack, which it shares with the monitor. The monitor says how much. |
| R1 | The monitor's putc routine, or 0 to leave the output on the console. The start-up code stores a nonzero R1 in `___putc_vector` (Device routines), so that `nice_putc`, `nice_print`, and the C library's output, `printf` included, reach the monitor's screen. |
| R2, R3 | `argc` and `argv`, which the start-up code passes to `main` in R1 and R2, where the start-up code at 0 passes 0 and 0. |

So the start-up code does not set SP: it saves it, and after `main` returns it returns to the monitor with `MOVE PC, @SP++`, with `main`'s return value in R1, instead of executing `HALT`, which would stop the processor until reset. `exit(status)` restores the saved SP and returns the same way, from anywhere, with the status in R1. On either return the monitor may rely on SP and R1 and on nothing else: `exit` discards the frames below it, so R7–R12 are not restored, and the flags, I, E, and VBASE may have changed. The monitor clears E, stops the timer, and resets VBASE itself, so a program may own the interrupts outright: it sets VBASE to a page of its own image and restores nothing. A wasm trap halts the processor, as elsewhere, after the trap report's line through `___putc_vector` if the program has the report; a program that wants the monitor back instead stores a handler of the monitor's in `___wasm_trap_vector` ([WASM.md](../translator/WASM.md)). The program may use nothing below `0x8000`: a write to the ROM is dropped, so a stack or data there is lost. What else the monitor offers, such as its routines, is documented with the monitor; a program calls them through stubs in a file of the monitor's, joined with the program. `nicebuild.py --monitor` builds such a program ([translator README](../translator/README.md)).

**Example.** This function and call:

    int f(int a, int b, int c, int d, int e) { return a + e; }
    ...
    x = f(1, 2, 3, 4, 5);

compile to:

    _f              ADD     R1, R1, @1[SP]  ; e is the first stack argument
                    MOVE    PC, @SP++       ; return
                    ...
                    MOVE    @--SP, 5        ; e goes on the stack
                    MOVE    R1, 1           ; a to d go in registers
                    MOVE    R2, 2
                    MOVE    R3, 3
                    MOVE    R4, 4
                    ADD     @--SP, 2, PC    ; call f
                    MOVE    PC, _f
                    ADD     SP, SP, 1       ; remove e
                    MOVE    @_x, R1         ; x = f(...)
