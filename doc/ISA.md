# NICE instruction set architecture

This document specifies the NICE ("NICE Is Charmingly Elegant") 32-bit processor designed by B. Ulmann. It is the reference for the FPGA implementation in this repository.

The sources are listed in [REFERENCES.md](REFERENCES.md). Where they disagree, this order applies:

1. The intended behavior of the 2004 emulator `NICE.pm` and the 2004 web page. The emulator's bugs are not part of the ISA.
2. The 1999 and 1997 articles.
3. QNICE, the 16-bit descendant of NICE, as implemented in [MJoergen/qnice_cpu](https://github.com/MJoergen/qnice_cpu), for anything the NICE sources leave open, such as the shift count.

[Appendix B](#appendix-b-departures-from-the-sources) lists every place where this specification departs from a source.

## Contents

- [1. Programmer's model](#1-programmers-model)
  - [1.1 Data and addresses](#11-data-and-addresses)
  - [1.2 Registers](#12-registers)
  - [1.3 Status register (R14)](#13-status-register-r14)
  - [1.4 Hidden state](#14-hidden-state)
- [2. Instruction format](#2-instruction-format)
  - [2.1 Instruction word](#21-instruction-word)
  - [2.2 Operand field](#22-operand-field)
  - [2.3 Constant words](#23-constant-words)
- [3. Conditional execution](#3-conditional-execution)
- [4. Addressing modes](#4-addressing-modes)
  - [4.1 Source operands (s0, s1)](#41-source-operands-s0-s1)
  - [4.2 Destination operand (dest)](#42-destination-operand-dest)
  - [4.3 Special registers in operands](#43-special-registers-in-operands)
  - [4.4 Unused operand fields](#44-unused-operand-fields)
- [5. Instruction execution](#5-instruction-execution)
  - [5.1 ALU instructions (bit 27 = 0)](#51-alu-instructions-bit-27--0)
  - [5.2 SHIFT instructions (bits 27..26 = 10)](#52-shift-instructions-bits-2726--10)
  - [5.3 Control instructions (bits 27..26 = 11)](#53-control-instructions-bits-2726--11)
- [6. Flags](#6-flags)
- [7. No interrupts](#7-no-interrupts)
- [8. Reset, memory, and I/O](#8-reset-memory-and-io)
  - [8.1 Reset](#81-reset)
  - [8.2 Memory](#82-memory)
  - [8.3 Input and output](#83-input-and-output)
- [9. Software conventions](#9-software-conventions)
  - [9.1 Stack, call, and return](#91-stack-call-and-return)
  - [9.2 Jumps and comparisons](#92-jumps-and-comparisons)
  - [9.3 C ABI and WebAssembly mapping](#93-c-abi-and-webassembly-mapping)
- [10. Assembler syntax](#10-assembler-syntax)
  - [10.1 Statements](#101-statements)
  - [10.2 Operands](#102-operands)
  - [10.3 Directives](#103-directives)
  - [10.4 Object format](#104-object-format)
- [11. Worked example](#11-worked-example)
- [Appendix A: Opcode map](#appendix-a-opcode-map)
- [Appendix B: Departures from the sources](#appendix-b-departures-from-the-sources)

## 1. Programmer's model

### 1.1 Data and addresses

- A word is 32 bits. Memory is **word-addressed**: address *a* names one 32-bit word.
- There are 2³² addresses. Address and register arithmetic wraps modulo 2³².
- Signed values are two's complement.

### 1.2 Registers

There are sixteen 32-bit registers, R0 to R15. Every register can be used with every instruction and every addressing mode. Four have a fixed role:

| Register | Role |
|---|---|
| R0 | Always reads as 0. Writes to it, and increments or decrements of it, are discarded. |
| R1–R12 | General purpose. |
| R13 | The stack pointer, SP (§9.1). The one-word `CALL` pushes the return address through it (§5.3). Every other instruction uses it as a general-purpose register. |
| R14 | Status register, SR (§1.3). |
| R15 | Program counter, PC. Writing R15 is a jump. |

### 1.3 Status register (R14)

| Bit | 31 | 30 | 29 | 28 | 27 | 26 | 25 | 24 | 23..0 |
|---|---|---|---|---|---|---|---|---|---|
| Name | F1 | F0 | V | N | Z | C | X | 1 | U |

| Field | Meaning |
|---|---|
| F1 (bit 31) | A flag for software. The hardware gives it no meaning and never writes it. |
| F0 (bit 30) | A flag for software, as F1. |
| V (bit 29) | Signed overflow. |
| N (bit 28) | Result was negative (bit 31 of the result). |
| Z (bit 27) | Result was zero. |
| C (bit 26) | Carry out of an addition, borrow out of a subtraction, or the bit shifted out by a shift. |
| X (bit 25) | Result was all ones (`0xFFFFFFFF`, that is −1). |
| 1 (bit 24) | Always 1, at every point within an instruction. No write clears it (§4.3). It makes condition select 0 mean "always" (§3). |
| U (bits 23..0) | 24 bits for software, as F1. |

Software can read and write every bit except bit 24. Instructions with the M bit (instruction bit 25, §2.1) set update only X, C, Z, N, and V (§6). F1, F0, and U change only when software writes R14. A condition tests F0 and F1 as it tests the flags (§3), so they are two flags that software sets and any instruction tests.

### 1.4 Hidden state

One bit of state is not visible as a register:

| State | Meaning |
|---|---|
| `halted` | 1 after `HALT` or any other halt (§5.3). Only reset clears it. |

## 2. Instruction format

Every instruction is one **instruction word**, followed by zero to three **constant words**. An instruction is therefore 1 to 4 words long.

### 2.1 Instruction word

| Bits | 31 | 30..28 | 27 | 26 | 25 | 24..21 | 20..14 | 13..7 | 6..0 |
|---|---|---|---|---|---|---|---|---|---|
| ALU | NEG | SEL | 0 | C | M | opcode | dest | s0 | s1 |
| SHIFT | NEG | SEL | 1 | 0 | M | opcode | dest | s0 | s1 |

Control instructions divide the bits below the class differently:

| Bits | 31 | 30..28 | 27 | 26 | 25..21 | 20..0 |
|---|---|---|---|---|---|---|
| Control | NEG | SEL | 1 | 1 | command | d, or 0 |

- **NEG, SEL**: the condition (§3).
- **Bits 27..26** select the class: `0x` ALU, `10` SHIFT, `11` control.
- **C** (ALU only): use the C flag as carry or borrow input (§5.1).
- **M**: update the flags from the result (§6).
- **dest, s0, s1**: the three operand fields (§4).
- **command, d**: the control instruction, and for a jump or a call its distance d, a signed 21-bit number (§5.3).

The all-zero word is `MOVE R0, R0` with condition "always", so it does nothing. It is the canonical NOP, and the assembler writes it for `NOP` (§10.1).

### 2.2 Operand field

| Bits | 6..4 | 3..0 |
|---|---|---|
| | mode | register number |

For source operands, bit 6 of the field (mode bit 2) means "the operand is in memory". Destinations differ in one case: mode 011 has bit 6 clear but still writes memory, because it is an alias of mode 111 (§4.2).

### 2.3 Constant words

A field whose mode ends in `11` (modes 011 and 111) takes one constant word. Constant words follow the instruction word in **field order: dest, s0, s1**. Only the fields that use a constant take a word. Control instructions (§5) take none.

Example: `ADD @0x40, R1, 7` is three words: the instruction word, `0x00000040` (dest) and `0x00000007` (s1).

## 3. Conditional execution

Every instruction, including control instructions, is conditional. It executes only if

    SR[24 + SEL] XOR NEG = 1

| SEL | Flag tested | Assembler | With NEG = 1 |
|---|---|---|---|
| 000 | 1 (always) | `?1` or nothing | `?!1` (never) |
| 001 | X | `?X` | `?!X` |
| 010 | C | `?C` | `?!C` |
| 011 | Z | `?Z` | `?!Z` |
| 100 | N | `?N` | `?!N` |
| 101 | V | `?V` | `?!V` |
| 110 | F0 | `?F0` | `?!F0` |
| 111 | F1 | `?F1` | `?!F1` |

The condition is tested against SR as it was before the instruction started.

In this document, "the M bit" always means instruction bit 25 (modify flags). The assembler also accepts the older names of SR bits 30 and 31 (Appendix B), with their `!` forms: `?E` and `?M` for `?F0`, and `?I` for `?F1`.

A skipped instruction still consumes its constant words (a control instruction has none), so PC moves past the whole instruction. A skipped instruction has no other effect: it reads no operand from memory, writes nothing, applies no increments or decrements, and changes no flags.

## 4. Addressing modes

### 4.1 Source operands (s0, s1)

`c` is the constant word that belongs to the field.

| Mode | Assembler | Value | Side effect |
|---|---|---|---|
| 000 | `Rx` | Rx | |
| 001 | `--Rx` | Rx after the decrement | Rx ← Rx − 1 first |
| 010 | `Rx++` | Rx before the increment | Rx ← Rx + 1 afterwards |
| 011 | `c[Rx]`, or `c` for `c[R0]` | Rx + c | |
| 100 | `@Rx` | mem[Rx] | |
| 101 | `@--Rx` | mem[Rx], read after the decrement | Rx ← Rx − 1 first |
| 110 | `@Rx++` | mem[Rx] | Rx ← Rx + 1 afterwards |
| 111 | `@c[Rx]`, or `@c` for `@c[R0]` | mem[Rx + c] | |

Mode 011 with R0 is how an immediate constant is written: `MOVE R1, 5`.

### 4.2 Destination operand (dest)

`r` is the result of the operation.

| Mode | Assembler | Effect |
|---|---|---|
| 000 | `Rx` | Rx ← r |
| 001 | `Rx--` | Rx ← r − 1 (the result is written, then Rx is decremented) |
| 010 | `Rx++` | Rx ← r + 1 (the result is written, then Rx is incremented) |
| 011 | `c[Rx]` | mem[Rx + c] ← r. This is an alias of mode 111. |
| 100 | `@Rx` | mem[Rx] ← r |
| 101 | `@--Rx` | Rx ← Rx − 1, then mem[Rx] ← r |
| 110 | `@Rx++` | mem[Rx] ← r, then Rx ← Rx + 1 |
| 111 | `@c[Rx]`, or `@c` for `@c[R0]` | mem[Rx + c] ← r |

The destination is never read.

In modes 001 and 010 the write of r and the decrement or increment are two writes to Rx. For R14, each one sets bit 24 (§4.3), so `MOVE R14--, 0` leaves R14 = `0x01FFFFFF`, not `0xFFFFFFFF`.

### 4.3 Special registers in operands

- **R0** reads as 0 in every mode, at every point within an instruction. Writes to R0 and side effects on R0 are discarded. So `--R0` and `R0++` read 0; `@R0`, `@--R0`, and `@R0++` all address word 0, as source or destination; and `c[R0]` is c.
- **R15** read as an operand gives the address of the **next instruction**, after all of this instruction's constant words. The exception is when an earlier operand of the same instruction has already changed R15 with a side effect.
- **R15** is an ordinary register in every mode. Any write to it is a jump, including a side effect such as `R15++`. If one instruction writes R15 more than once, the last write in the order of §5 wins.
- **R14 bit 24** reads as 1 at every point within an instruction. Every write to R14, a side effect included, sets bit 24 to 1. So after reset (R14 = `0x01000000`), `MOVE R1, --R14` sets R14 and R1 to `0x01FFFFFF`, and `@--R14` addresses word `0x01FFFFFF`.
- **R14** written as a register-direct destination (modes 000, 001, and 010) takes the written value, except that bit 24 stays 1. The flag update is skipped in that case (§6).

### 4.4 Unused operand fields

Some operations ignore an operand: `MOVE`, `DBL`, `DEC`, and `NOT` ignore s1, and `ONE` ignores s0 and s1. The field is still evaluated in full: it takes its constant word, reads memory, and applies its side effect. The assembler encodes unused fields as `000 0000` (R0), so they have no effect.

## 5. Instruction execution

An instruction runs in this order:

1. **Fetch.** IW ← mem[PC], then PC ← PC + 1.
2. **Constants.** For ALU and SHIFT instructions, take one constant word for each field whose mode ends in `11`, in the order dest, s0, s1. For each: c ← mem[PC], then PC ← PC + 1. Control instructions take no constant words, so for them PC is now the address of the next instruction.
3. **Condition.** If the condition (§3) is false, the instruction ends here.
4. **Control.** If the instruction is in the control class, run the command (§5.3) and end.
5. **Sources.** Evaluate s0, then s1 (§4.1), including their side effects. Each step sees the registers as earlier steps left them.
6. **Operation.** Compute the result r, plus carry and overflow (§5.1–§5.3).
7. **Destination.** Write r and apply the destination's side effect exactly as §4.2 specifies for its mode, starting from the registers as step 5 left them.
8. **Flags.** Update the flags (§6).

Because step 5 runs before step 7, `MOVE @R1, R1++` with R1 = 0x40 stores 0x40 at address 0x41.

The next instruction is the one at PC as it stands after step 8. Steps 1 and 2 are instruction fetches, and every other memory access is a data access. §8.2 defines the two kinds, and §8.3 says what a fetch from the I/O range reads.

### 5.1 ALU instructions (bit 27 = 0)

`cin` is the C flag as step 5 of §5 left it, if the instruction's C bit is set, and 0 otherwise. Only `SUB`, `MDBL`, `ADD`, and `DBL` use it. All other ALU operations ignore the C bit.

| Opcode | Mnemonic | Result r | C (if M = 1) | V (if M = 1) |
|---|---|---|---|---|
| 0000 | `MOVE` | s0 | 0 | 0 |
| 0001 | `SUB` | s0 − s1 − cin | borrow out | signed overflow |
| 0010 | `MDBL` | s0 + (s0 AND s1) + cin | carry out | signed overflow |
| 0011 | `ADD` | s0 + s1 + cin | carry out | signed overflow |
| 0100 | `DBL` | s0 + s0 + cin | carry out | signed overflow |
| 0101 | `DEC` | s0 − 1 | borrow out | signed overflow |
| 0110 | `NOT` | NOT s0 | 0 | 0 |
| 0111 | `NOR` | NOT (s0 OR s1) | 0 | 0 |
| 1000 | `IAND` | (NOT s0) AND s1 | 0 | 0 |
| 1001 | `NAND` | NOT (s0 AND s1) | 0 | 0 |
| 1010 | `XOR` | s0 XOR s1 | 0 | 0 |
| 1011 | `IOR` | (NOT s0) OR s1 | 0 | 0 |
| 1100 | `XNOR` | NOT (s0 XOR s1) | 0 | 0 |
| 1101 | `AND` | s0 AND s1 | 0 | 0 |
| 1110 | `ONE` | 1 | 0 | 0 |
| 1111 | `OR` | s0 OR s1 | 0 | 0 |

**Carry and borrow:**
- For an addition a + b + cin, C = 1 when the unsigned sum exceeds `0xFFFFFFFF`.
- For a subtraction a − b − cin, C = 1 when the unsigned result is negative, that is, a borrow. `DEC` is a − 1, so C = 1 when s0 = 0.
- Multi-word arithmetic: `ADD` the low words with M set, then `ADD[C]` the high words. Subtraction works the same way with `SUB` and `SUB[C]`.

**Signed overflow:**
- Addition: V = 1 when both addends have the same sign and r has the other sign. For `MDBL` the addends are s0 and (s0 AND s1). For `DBL` both addends are s0.
- Subtraction a − b: V = 1 when a and b have different signs and r's sign differs from a's. For `DEC`, b = 1, so V = 1 only when s0 = `0x80000000`.

`MDBL` doubles s0 where s1 has ones: s1 = `0xFFFFFFFF` gives 2·s0 and s1 = 0 gives s0. It comes from the 74181, a 4-bit ALU chip of the 1970s, as do `IAND`, `IOR`, and the other unusual operations.

### 5.2 SHIFT instructions (bits 27..26 = 10)

s0 is the value to shift. s1 is the count: the shift runs **n = s1** steps, using all 32 bits of s1 as an unsigned number. There is no modulo.

The mnemonic shows the direction and where bits come from and go to:
- **Left shifts `A<B`**: B is the fill bit shifted into bit 0 (0, 1, or C), and A is where bit 31 goes (0 = discarded, C = the carry flag).
- **Right shifts `A>B`**: A is the fill bit shifted into bit 31, and B is where bit 0 goes.
- `<<<` and `>>>` are rotations, and `C<<` and `>>C` are rotations that also copy the rotated bit into C.

| Opcode | Mnemonic | Alias | Fill bit | Bit shifted out goes to |
|---|---|---|---|---|
| 0000 | `0<0` | `SHL` | 0 | discarded |
| 0001 | `0<1` | | 1 | discarded |
| 0010 | `0<C` | | C | discarded |
| 0011 | `C<0` | | 0 | C |
| 0100 | `C<1` | | 1 | C |
| 0101 | `C<C` | | C | C (33-bit rotation through carry) |
| 0110 | `<<<` | `ROL` | the bit shifted out | discarded |
| 0111 | `C<<` | `BPL` | the bit shifted out | C |
| 1000 | `0>0` | `SHR` | 0 | discarded |
| 1001 | `1>0` | | 1 | discarded |
| 1010 | `C>0` | | C | discarded |
| 1011 | `0>C` | | 0 | C |
| 1100 | `1>C` | | 1 | C |
| 1101 | `C>C` | | C | C (33-bit rotation through carry) |
| 1110 | `>>>` | `ROR` | the bit shifted out | discarded |
| 1111 | `>>C` | `BPR` | the bit shifted out | C |

Bit 24 of the instruction (the top opcode bit) gives the direction: 0 = left, 1 = right.

**Exact definition.** Let d = s0 and c = the C flag as step 5 of §5 left it. Repeat n times:

- Left: out = d[31], d = (d << 1) OR fill.
- Right: out = d[0], d = (d >> 1) OR (fill << 31).
- Here `<<` and `>>` are logical shifts of the 32-bit value d: both shift in 0, and `>>` does not copy the sign bit.
- Here fill is 0, 1, c, or out (for the rotations), as the table says.
- If the bit shifted out goes to C, then c ← out.

r = d. Note that for `0<C` and `C>0`, c never changes, so every fill bit is the original C.

The loop defines the result for every count, but hardware need not run it n times. The same results in closed form:

- **Shifts with a fixed fill** (0, 1, or the original C; that is, every shift except the rotations and `C<C`/`C>C`):
  - For n ≥ 32, the result is all fill bits.
  - Where the bit shifted out goes to C, n = 32 leaves C = the last bit of s0 shifted out (bit 0 for a left shift, bit 31 for a right shift), and n > 32 leaves C = the fill bit.
- **`<<<`, `C<<`, `>>>`, and `>>C`** are 32-bit rotations, so only n mod 32 matters for the result. For `C<<` and `>>C` with n > 0, C ends up equal to the bit that was rotated last: bit 0 of r for `C<<`, and bit 31 of r for `>>C`.
- **`C<C` and `C>C`** are 33-bit rotations of C and s0 together, so only n mod 33 matters.

**The C flag after a shift:**
- If M = 0, no shift changes C. The fill still reads C, but c is not written back.
- If M = 1, the eight shifts whose bit shifted out goes to C set the C flag to c. With n = 0, C is set to the value it had after step 5.
- If M = 1, the other eight shifts set C = 0.

With M = 1, V = 0 after any shift.

Arithmetic shift right is two instructions: `C<0[M] R0, Rx, 1` copies the sign bit into C, then `C>0 Rx, Rx, n` shifts it in.

### 5.3 Control instructions (bits 27..26 = 11)

| Command (bits 25..21) | Mnemonic | Encoding (with condition "always") | Effect |
|---|---|---|---|
| 00000 | `HALT` | `0x0C000000` | halted ← 1. The processor stops. Only reset restarts it. |
| 00100 | `JMP` | `0x0C800000` + d | PC ← PC + d. |
| 00101 | `JMPR` | `0x0CA00000` + d | PC ← PC + d, as `JMP`. |
| 00110 | `CALL` | `0x0CC00000` + d | R13 ← R13 − 1, then mem[R13] ← PC, then PC ← PC + d. |
| 00001–00011, 00111–11111 | | | Reserved. Executing one halts the processor. |

For `JMP`, `JMPR`, and `CALL`, bits 20..0 hold d, a signed distance of 21 bits in two's complement, sign-extended to 32 bits. PC is the address of the next instruction, the word after this one (step 2 of §5), so d = 0 goes on to the next instruction, and d = −1 jumps to the instruction itself. The sum wraps modulo 2³². So a jump or a call reaches 2²⁰ words back and 2²⁰ − 1 words forward from the next instruction. A farther target, and a target in a register or in memory, take the long forms of §9.

- `JMP` and `JMPR` do the same thing. They differ only as a hint to a pipelined processor: it may predict a `JMPR` with a condition and d < 0 as taken, as for the back edge of a loop, and it predicts no `JMP` (§10.1).
- `CALL` pushes the address of the next instruction through R13, as `ADD @--R13, 2, R15` does in the long form (§9.1), and jumps. Its write of memory is a data access (§8.2). The write may change the words of the `CALL` itself, which have been fetched, so the `CALL` still jumps by its own d (§8.2).

For `HALT`, bits 20..0 must be 0. An instruction that breaks this is reserved and halts the processor.

The condition field applies, so `?Z HALT` halts only when Z = 1. This includes reserved words: a reserved control word whose condition is false is skipped like any other instruction and does not halt the processor.

Control instructions have no M bit and never change SR. `JMP` and `JMPR` change only R15, and `CALL` only R13, R15, and one word of memory.

## 6. Flags

If M = 1, and the destination is not R14 in a register-direct mode (000, 001, or 010), then after the destination is written:

| Flag | New value |
|---|---|
| X | 1 if r = `0xFFFFFFFF` |
| Z | 1 if r = 0 |
| N | bit 31 of r |
| C | as given in §5.1 and §5.2 |
| V | as given in §5.1, and 0 for shifts |

The flags are computed from the result r of the operation, not from the value stored by a `Rx++` or `Rx--` destination.

If M = 0, the flags do not change. This holds for every instruction, shifts included. Control instructions (§5.3) have no M bit and never change the flags.

## 7. No interrupts

NICE has no interrupts: no interrupt request, no software interrupt, and no instruction that waits for one. A program learns of an event by polling, that is, by reading the status of a device in a loop (§8.3).

A system with a NICE processor is built so that it needs none:

- **Input is not lost while the processor is busy.** The devices hold it in buffers in hardware, such as the console's input buffer and the queue of Ethernet frames, until the program reads it.
- **Work that cannot wait is done in hardware.** On NiceMonMEGA65, the TCP engine runs in the FPGA beside the processor.
- **A debugger breaks into any program.** The debug link ([DEBUG.md](DEBUG.md)) pauses the processor in hardware, at any instruction, and the program does nothing for it.
- **A program that must react to a key, such as an interpreter that stops on a break key, polls the console between its statements.**

Processors without interrupts are not new. The central processor of the CDC 6600 left all I/O to peripheral processors, which polled, and the eight cores of the Parallax Propeller poll or wait on a pin. An interrupt is one way among several to react to an event, and it costs state in the processor: a saved PC and SR, a vector table, a return instruction, and the rules of when a request is taken.

Polling has its own cost, which falls on the program:

- A program that waits for an event spins in a loop of reads. The emulator does not spin the host's CPU for such a loop ([DEVICES.md §1.6](DEVICES.md#16-pacing)).
- Work that must run at a regular time, such as music or a change of the screen in mid-frame, fits into the main loop, which reads a counter to know the time ([DEVICES.md §3](DEVICES.md#3-performance-counters)).

## 8. Reset, memory, and I/O

### 8.1 Reset

| State | Value after reset |
|---|---|
| R0–R13, R15 | 0, so execution starts at address 0 |
| R14 | `0x01000000`: only bit 24 set, so F1, F0, and U are 0 |
| halted | 0 |
| Memory | not changed by reset |

### 8.2 Memory

- A read from an address with no memory or device behind it returns 0. A write to such an address is ignored.
- Each instruction runs with the words that memory held when the instructions before it had completed. So a store may change the next instruction or its constant words, and the change takes effect. An instruction that overwrites its own constant words does not see the change, because they were fetched in step 2.
- A system may let more than one address reach the same word, as the aliasing and the byte windows of [DEVICES.md](DEVICES.md) do. The rule above then holds for a store to the address that the word is fetched from. A store through another address leaves undefined which value runs.

Memory accesses are of two kinds. **Instruction fetches** read the instruction word and the constant words (steps 1 and 2 of §5). **Data accesses** are the operand reads and the destination writes.

**Data accesses are exact and in order.** Each data access named in this document is performed exactly once, as a separate access, and in program order. No data access is merged with another, dropped, repeated, reordered, or performed speculatively. I/O devices may rely on this. For one instruction the data accesses are:

1. None if the condition is false.
2. Read s0 if its mode is 100–111, then s1 if its mode is 100–111. This applies even when the operation ignores the operand (§4.4). So `ADD R1, @R2, @R2` reads mem[R2] twice, and a `MOVE` whose unused s1 field holds `@R3` also reads mem[R3].
3. Write the destination if its mode is 011–111. The destination is never read.

`CALL` makes one data access: the write of the return address to mem[R13], after the decrement (§5.3). The other control instructions make none.

**Instruction fetches are not ordered.** The processor may fetch instruction words and constant words early, more than once, or for instructions that never run. It may do so in any order relative to data accesses. Only the result is defined: each instruction runs with the words that memory held when the instructions before it had completed. This lets a pipelined processor fetch ahead, and lets instruction fetches and data accesses use separate buses.

**Memory model.** The memory model is strong: data accesses are sequentially consistent. Loads and stores are never reordered with each other, so no fence or barrier is needed, and the ISA has none. Self-modifying code needs no cache flush or barrier either. The ISA describes one processor. It does not specify what happens with a second bus master.

### 8.3 Input and output

I/O is memory-mapped. There are no I/O instructions. Addresses `0xFFFFFF00`–`0xFFFFFFFF` are reserved for I/O devices. The ISA defines no device. The devices of the emulator and the FPGA implementation are in [DEVICES.md](DEVICES.md).

Instruction fetches never reach I/O devices. An instruction fetch from `0xFFFFFF00`–`0xFFFFFFFF` reads 0, whatever a data read of the same address returns. The word 0 is a NOP (§2.1), so a program that runs into the I/O range runs through it and wraps to address 0.

## 9. Software conventions

These are conventions, built on the instructions of §5. The one-word `CALL` fixes one of them in hardware: its stack pointer is R13.

### 9.1 Stack, call, and return

R13 is the stack pointer, SP. The stack grows down, and SP points at the last item pushed.

| Operation | Code |
|---|---|
| Push x | `MOVE @--SP, x` |
| Pop into x | `MOVE x, @SP++` |
| Call `sub` | `CALL sub`, one word (§5.3) |
| Call `sub`, the long form | `ADD @--SP, 2, PC` then `MOVE PC, sub` |
| Return | `MOVE PC, @SP++` |

The one-word `CALL` reaches 2²⁰ words either way, and the long form any address. The long form works because PC reads as the address after `ADD`'s constant word, which is the start of the 2-word `MOVE PC, sub`. Adding 2 gives the address after the `MOVE`. Both push the address of the word after the call, so `RET` returns from either.

The constant is the size of the `MOVE` in words. A call through a register, `MOVE PC, Rx`, is one word, so it pushes with `ADD @--SP, 1, PC`. The assembler writes `CALL target` and `RET` for these (§10.1), and the push and pop for `PUSH x` and `POP x`.

### 9.2 Jumps and comparisons

| Operation | Code |
|---|---|
| Jump | `JMP label`, one word (§5.3) |
| Conditional jump | `?Z JMP label` |
| Jump back in a loop | `?!Z JMPR label`, one word, which a pipelined processor may predict taken (§5.3) |
| Jump to any address, the long form | `MOVE PC, label` |
| Relative jump, the long form | `ADD PC, PC, offset`. The offset is relative to the next instruction. |
| Compare a with b | `SUB[M] R0, a, b`. Then Z = 1 if a = b, and C = 1 if a < b unsigned. |
| Test a | `MOVE[M] R0, a`. Then Z, N, and X describe a. |

The assembler writes `JMP` and `JMPR` with an address as the one-word instructions, `JMP` with a register or memory operand as a `MOVE`, and the pseudo-instructions `CMP a, b` and `TST a` as the comparisons (§10.1).

There is no condition or instruction for a signed comparison. A signed a < b is N XOR V after `SUB[M]`, and it is tested with two instructions:

                    SUB[M]  R0, a, b
            ?V      XOR     R14, R14, 0x10000000  ; flip N when V is set
            ?N      MOVE    PC, less        ; a < b signed; ?!N for a >= b

After the `XOR`, N is a < b. The write to R14 takes the written value, and leaves the other flags as they were (§4.3). For a > b or a <= b, swap the operands of `SUB[M]`.

### 9.3 C ABI and WebAssembly mapping

The C ABI, the runtime library's conventions, is in [ABI.md](../runtime/ABI.md). The mapping of WebAssembly to NICE is in [WASM.md](../translator/WASM.md). They are software conventions that build on this section, not part of the ISA.

## 10. Assembler syntax

This follows the 2004 assembler in `NICE.pm`, with a few changes listed in Appendix B. The assembler's [README](../assembler/README.md) adds the finer points of the syntax and its error checks.

### 10.1 Statements

    [label]  [?cond]  MNEMONIC[mods]  dest, s0, s1    ; comment

- **Case.** Labels and `.EQU` names are case-sensitive. Mnemonics, register names, conditions, modifiers, and directives are not.
- **Comments.** A comment starts with `;` anywhere outside a string, or with `*` at the start of a word, and runs to the end of the line. So `4 *x` is `4` and a comment, and `4*x` is a product (§10.2).
- **Separators.** On a line with a comma between its operands, the operands are separated by commas only, so an operand may hold spaces, as in `MOVE R1, end - data`. Its words are joined, and two of them with no `+`, `-`, or `*` between them are an error, so `ADD R1 R2, R3` is an error. An instruction or directive that takes one operand, such as `JMP`, `.ORG`, or an `.EQU` value, takes all of its words as that operand, joined the same way: `JMP end + 2`, `N .EQU 2 + 3`. On a line without a comma, the operands are separated by whitespace, so `.DAT 1 +5` is two words, 1 and 5, but `.DAT 1 +5, 3` is 6 and 3.
- **Labels.** A label is the first word on a line that is not a mnemonic or a directive. It may end with `:`, and so may an `.EQU` name. Its value is the address of what follows on that line; on a `.ORG` line, that is the new address. A label or `.EQU` name is an ASCII letter or `_` followed by ASCII letters, digits, `_`, and `.`. It cannot be a mnemonic, a register name, or look like one: `R` followed by digits, so `R16` is rejected too.
- **Anonymous labels.** A lone `:` as the label is an anonymous label, for a short loop that needs no name. It stands where a label may, also on a line of its own and on a `.ORG` line, and has the value a label there would have. `:-` refers to the nearest anonymous label above, and `:--` to the one before it, one more for each `-`. A label on the line of the reference counts as above. `:+` refers to the nearest anonymous label below, and `:++` to the one after it. They count in source order, not by address, so a `.ORG` does not change them. An anonymous label cannot be an `.EQU` name, and `niceasm --symbols` does not write it.

      :               SUB[M]  R1, R1, 1
              ?!Z     JMP     :-              ; back to the SUB
- **Conditions.** `?cond` is one of the condition codes in §3, such as `?Z` or `?!C`. Without one, the instruction is unconditional. `?E` and `?M` are accepted as aliases for `?F0`, and `?I` for `?F1`, each with its `!` form.
- **Modifiers.** `[M]` sets the M bit and `[C]` sets the C bit. `[CM]` and `[MC]` set both. `[C]` is accepted only on ALU instructions.
- **Operand counts.** The assembler expects exactly the operands the instruction uses:
  - `ONE` takes dest only.
  - `MOVE`, `DBL`, `DEC`, and `NOT` take dest and s0.
  - The other ALU and SHIFT instructions take dest, s0, and s1.
  - `HALT` takes none.
- **No interrupt instructions.** `RTI`, `INT`, and `WAIT` are not mnemonics, as NICE has no interrupts (§7). The assembler rejects each of them with an error where a mnemonic stands, and none can be a label or an `.EQU` name, so an old source that uses them does not assemble by accident.
- **Jumps and calls to an address.** `JMP target`, `JMPR target`, and `CALL target`, where target is an address expression (§10.2), such as a label, a number, or `:-`, assemble as the one-word instruction of §5.3, with d = target − next, where next is the address of the word after it. They are always one word: the size of a statement depends only on its operand modes, never on the value of a label. A target out of reach, with d outside −2²⁰ to 2²⁰ − 1, is an error, and the source then writes the long form: `MOVE R15, target`, or `ADD @--R13, 2, R15` and `MOVE R15, target` for a call. A condition applies as usual, and none takes a modifier.
- **Pseudo-instructions.** `CALL target` with a register or memory operand assembles as `ADD @--R13, n, R15` followed by `MOVE R15, target`, where n is the size of the `MOVE` in words: 2 when target has a constant word, else 1. `RET` assembles as `MOVE R15, @R13++`. These are the call and return of §9.1, so R13 is the stack pointer. A condition applies to every instruction of the expansion: `?Z CALL @vector` calls only when Z is set, since `ADD` without `[M]` leaves the flags for the `MOVE`. Neither takes a modifier. `CALL`, `JMP`, `JMPR`, and `RET` are mnemonics, so none can be a label or an `.EQU` name.
- **One-instruction pseudo-instructions.** These are the other idioms of §9 and two common moves, each one instruction:

  | Pseudo | Assembles as |
  |---|---|
  | `JMP target`, with a register or memory operand | `MOVE R15, target` |
  | `CMP a, b` | `SUB[M] R0, a, b` |
  | `TST a` | `MOVE[M] R0, a` |
  | `PUSH x` | `MOVE @--R13, x` |
  | `POP x` | `MOVE x, @R13++` |
  | `CLR x` | `MOVE x, R0` |
  | `NOP` | `MOVE R0, R0` |

  `CLR x` is one word, where `MOVE x, 0` takes a constant word for the 0. The operands are checked as those of the instruction, so `JMP R2--` is an error. A condition applies as usual. None takes a modifier: `CMP` and `TST` set the flags because `[M]` is part of what they mean. All are mnemonics, so none can be a label or an `.EQU` name.
- **`JMP` or `JMPR`.** They assemble to the same jump but for the command, and run the same. A pipelined core may predict a backward `JMPR` with a condition taken, and predicts no `JMP` (§5.3). So `JMPR` suits the back edge of a loop that is mostly taken, and `JMP` the rest. The target of `JMPR` is always an address expression: a register or memory operand, such as `JMPR R3` or `JMPR @x`, is an error.

      :               SUB[M]  R1, R1, 1
              ?!Z     JMPR    :-              ; back to the SUB
- **Unused fields** are encoded as R0 (`000 0000`).

### 10.2 Operands

| Syntax | Meaning |
|---|---|
| `R0`–`R15` (also `R00`–`R09`) | A register. |
| `--Rx`, `Rx++` | A source with pre-decrement or post-increment. |
| `Rx--`, `Rx++` | A destination with post-decrement or post-increment. |
| `@Rx`, `@--Rx`, `@Rx++` | Indirect. |
| `c`, `c[Rx]` | A constant, mode 011. As a source its value is Rx + c. As a destination it writes mem[Rx + c]. |
| `@c`, `@c[Rx]` | Memory at Rx + c, mode 111. |

- **Numbers and expressions.** `0x` hex, `0b` binary, and plain decimal. The prefix and the digits may be in either case. There is no `#` prefix and no `$`. A label or an `.EQU` name may appear wherever a number may. A constant may also be an expression: numbers and symbols joined with `+`, `-`, and `*`, with an optional leading sign, such as `end-data`, `-1`, or `4*label`. It may hold spaces where the operand may (§10.1), as in `end - data`, but a product has none before its `*`: a word that starts with `*` starts a comment, so `4 * x` is `4` and a comment, while `4* x` is the product. `*` binds tighter than `+` and `-`, a leading sign is on the first product, and there are no parentheses. An `.EQU` name in an expression stands for its value as a whole, so with `N .EQU 2+3`, `4*N` is 20. An anonymous label reference (§10.1) is a term too, as in `@:-` or `4*:+`. All the signs after its `:` are part of it, so an offset goes before it, as in `2+:-`, and `:++2` is an error. It cannot appear in an `.EQU` value. Each number must be below 2³², so `4294967296` and `0x100000000` are errors. The value of an expression wraps modulo 2³², except for `.BLK` and `.RES`, which take it before it wraps and reject it out of range, so `.RES 0xFFFFFFFF+1` is an error, not 0 words.
- **Register aliases.** Programs define them with `.EQU`, for example `SP .EQU R13` and `PC .EQU R15`.

### 10.3 Directives

| Directive | Effect |
|---|---|
| `NAME .EQU value` | Defines NAME. The value is a number, an expression, a register, or a complete operand. NAME is replaced by the value where it stands for a whole operand, a register, or a number in an expression. Every symbol in the value must be defined, also when NAME is never used. |
| `.ORG addr` | Continue assembling at addr. |
| `.DAT value, ...` | One word for each value. |
| `.BLK n` | n words of 0. |
| `.RES n` | Reserves n words. They are not part of the program image (§10.4), so their contents are undefined when the program starts. |
| `.ASCII_L 'text'` | One character per word, followed by a 0 word. |
| `.ASCII_B 'text'` | Four characters per word, with the first character in the least significant byte. The last word is padded with 0 bytes. No terminator is added when the length is a multiple of 4. |

Strings may be quoted with `'` or `"`.

### 10.4 Object format

The `.bin` format is plain text with one line per assembled word: an 8-digit hex address, a space, and the 8-digit hex word. Lines are in address order, for example `00000002 0077580f`. Addresses skipped by `.ORG` and words reserved by `.RES` are not listed.

## 11. Worked example

From the 2004 web page:

            ?!Z     ADD[M]  @R3++, --R2, @0x12345678[R1]

| Part | Bits |
|---|---|
| Condition `?!Z` | NEG = 1, SEL = 011 |
| Class ALU, C = 0, M = 1 | `0 0 1` |
| `ADD` | `0011` |
| dest `@R3++` | `110 0011` |
| s0 `--R2` | `001 0010` |
| s1 `@0x12345678[R1]` | `111 0001`, plus one constant word |

The result is the instruction word `0xB278C971`, followed by the constant `0x12345678`.

It executes as follows:
1. R2 ← R2 − 1, then s0 = R2.
2. s1 = mem[R1 + 0x12345678].
3. mem[R3] ← s0 + s1, then R3 ← R3 + 1.
4. X, C, Z, N, and V are updated.
5. All of this happens only if Z was 0.

## Appendix A: Opcode map

| Bits 27..26 | Bit 25 | Bits 24..21 | Instruction |
|---|---|---|---|
| 0, C | M | 0000–1111 | `MOVE SUB MDBL ADD DBL DEC NOT NOR IAND NAND XOR IOR XNOR AND ONE OR` |
| 10 | M | 0000–1111 | `0<0 0<1 0<C C<0 C<1 C<C <<< C<< 0>0 1>0 C>0 0>C 1>C C>C >>> >>C` |
| 11 | command, bits 25..21 | | `HALT` (0), `JMP` (4), `JMPR` (5), `CALL` (6), reserved (1–3, 7–31) |

## Appendix B: Departures from the sources

| Topic | This specification | Sources that disagree |
|---|---|---|
| Condition field and SR layout | NEG at bit 31, SEL at 30..28; SR bits 29..24 = `V N Z C X 1` (2004 web page and emulator, same as QNICE) | Both articles: SEL at 31..29, NEG at 28, SR bit 31 = 1 |
| SR bits 31 and 30 | F1 and F0, two flags for software with no meaning to the hardware, tested by the conditions `?F1` and `?F0` (§1.3, §3). The assembler accepts `?I`, `?E`, and `?M` for them. | Web page: I = an interrupt was taken, E = maskable interrupts enabled, and the emulator calls E M, with condition `?M`. Articles: M = maskable interrupt occurred, I = enabled. |
| SR bits 23..0 | U, 24 bits for software (§1.3) | Not specified anywhere |
| Order of constant words | dest, s0, s1 (emulator and its binaries) | 1997 article: s1, s2, dest |
| R15 as an operand | Address of the next instruction (1999 article, emulator, QNICE) | 1997 article: the current instruction |
| Interrupts | None: no interrupt request, `INT`, `RTI`, or `WAIT` (§7) | Articles and web page: a maskable interrupt and an NMI, with R13 receiving the return address. QNICE has interrupts, `INT`, and `RTI`. |
| HALT encoding space | Control group with `HALT`, `JMP`, `JMPR`, and `CALL`; the other commands are reserved and halt (§5.3) | Web page: spare bits "have no meaning and should be zero" |
| Jumps and calls in one word | `JMP`, `JMPR`, and `CALL` in the control class, with a signed distance of 21 bits in the instruction word (§5.3) | Not in the sources, where a jump is a `MOVE` or an `ADD` to PC with a constant word, and a call is two instructions |
| R13 | The stack pointer of the one-word `CALL` (§1.2, §5.3) | The sources give R13 no meaning in hardware. QNICE's `ASUB` and `RSUB` push through its R13 the same way. |
| Carry input to `SUB` | Subtracts C (borrow) | 1997 article: every arithmetic op adds C. The emulator subtracts it, as here. |
| `MOVE`, `DEC` with the C bit | C bit ignored (emulator) | 1997 article: adds C |
| `ONE` | r = 1 (emulator and web page) | The 74181 background suggests all ones |
| Flags with M = 1 | X, C, Z, N, V all rewritten, so logic ops clear C and V (emulator) | QNICE leaves C and V unchanged on logic ops |
| Shift count | The full 32-bit count, no modulo (QNICE) | The emulator masks the count to 5 bits for every shift except `0<0` and `0>0` |
| Shifts writing C | Only when M = 1 (emulator) | The articles and the web page say the shifts that send their bit shifted out to C write it whatever M is. The 1999 multiplication example relies on that, so it needs `[M]` on its shifts. |
| Writing R14 with M = 1 | The written value wins | The emulator overwrites it with the flags |
| R0 | Always 0, even within an instruction | In the emulator, `--R0` reads −1 within one instruction |
| Unused operand fields | Evaluated in full (emulator) | QNICE ignores them |
| Missing memory, I/O | Reads return 0; I/O at `0xFFFFFF00`–`0xFFFFFFFF` | Not specified anywhere |
| SR bit 24 within an instruction | Always 1; every write to R14, side effects included, sets it (§4.3) | Not specified anywhere. The emulator forces it only before and after each instruction. |
| `R14--` and `R14++` as destinations | r is written, then decremented or incremented, and each write sets bit 24 (§4.2) | Not specified anywhere |
| Memory access order | Each data access exactly once, unmerged, and in program order. Instruction fetches may run ahead, repeat, or be wasted (§8.2) | Not specified anywhere |
| Instruction fetches from the I/O range | Read 0 and never reach a device (§8.3) | Not specified anywhere |
| Carry input timing | The C flag as step 5 of §5 left it (§5.1, §5.2) | Not specified anywhere. The emulator also reads C after the source operands. |
| Assembler numbers | `0x`, `0b`, decimal | The emulator reads a leading 0 as octal; the articles use `#` and `$` |
| Assembler directives and constants | `.DAT` takes several values, a constant may be an expression of `+`, `-`, and `*`, and a string may use `"..."` (§10) | `NICE.pm` takes one value per directive, a number or a symbol only, and `'...'` only |
| Operand separators | On a line with a comma between its operands, commas only, so an operand may hold spaces; an instruction or directive with one operand takes all of its words (§10.1) | `NICE.pm` separates operands by whitespace or by one comma |
| `.RES` directive | Reserves words that are not in the program image (§10.3) | The 2004 assembler has no such directive. Every word it reserves, with `.BLK`, is in the image. |
| `CALL` and `RET` | `CALL` to an address is an instruction (§5.3). `CALL` through a register or memory, and `RET`, are pseudo-instructions for the call and return of §9.1 (§10.1). | `NICE.pm` has no such names. The 2004 programs write the two instructions. |
| `JMP`, `JMPR`, `CMP`, `TST`, `PUSH`, `POP`, `CLR`, and `NOP` | `JMP` and `JMPR` to an address are instructions (§5.3). The rest, and `JMP` through a register or memory, are pseudo-instructions for the idioms of §9 (§10.1). | `NICE.pm` has no such names. The 2004 programs write the instructions. |
| Anonymous labels | `:` labels a line, and `:-` and `:+` refer to the nearest one above and below, as in ca65 (§10.1) | `NICE.pm` has named labels only |

The emulator also has bugs that this specification does not copy. Its carry input comes from the wrong SR bit, its 5-bit count mask is wrong, it modifies source registers, it never sets X, `ONE` crashes, `1>0` and `C>0` fill the wrong end, and `DEC` reports a borrow in V. See [review/emulator-and-webpage-review.md](review/emulator-and-webpage-review.md) §4.
