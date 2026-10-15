# NICE instruction set architecture

This document specifies the NICE ("NICE Is Charmingly Elegant") 32-bit processor designed by B. Ulmann. It is the reference for the FPGA implementation in this repository.

The sources are listed in [REFERENCES.md](REFERENCES.md). Where they disagree, this order applies:

1. The intended behaviour of the 2004 emulator `NICE.pm` and the 2004 web page. The emulator's bugs are not part of the ISA.
2. The 1999 and 1997 articles.
3. QNICE (as in [MJoergen/qnice_cpu](https://github.com/MJoergen/qnice_cpu)), for anything the NICE sources leave open, such as interrupts.

[Appendix B](#appendix-b-departures-from-the-sources) lists every place where this specification departs from a source.

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
| R13 | General purpose. By software convention it is the stack pointer, SP (§9.1). The hardware gives it no special meaning. |
| R14 | Status register, SR (§1.3). |
| R15 | Program counter, PC. Writing R15 is a jump. |

### 1.3 Status register (R14)

| Bit | 31 | 30 | 29 | 28 | 27 | 26 | 25 | 24 | 23..0 |
|---|---|---|---|---|---|---|---|---|---|
| Name | I | E | V | N | Z | C | X | 1 | VBASE |

| Field | Meaning |
|---|---|
| I (bit 31) | Set to 1 by the hardware when an interrupt is taken (§7). |
| E (bit 30) | Interrupts enabled: maskable interrupts are accepted only while E = 1. |
| V (bit 29) | Signed overflow. |
| N (bit 28) | Result was negative (bit 31 of the result). |
| Z (bit 27) | Result was zero. |
| C (bit 26) | Carry out of an addition, borrow out of a subtraction, or the bit shifted out by a shift. |
| X (bit 25) | Result was all ones (`0xFFFFFFFF`, that is −1). |
| 1 (bit 24) | Always 1, at every point within an instruction. No write clears it (§4.3). It makes condition select 0 mean "always" (§3). |
| VBASE (bits 23..0) | The upper 24 bits of the interrupt vector table address (§7.3). |

Software can read and write every bit except bit 24. Instructions with the M bit set update only X, C, Z, N, and V (§6). I, E, and VBASE change only when software writes R14, on interrupt entry (I), and on `RTI`.

### 1.4 Hidden state

These are not visible as registers. They exist for interrupts (§7) and halting:

| State | Meaning |
|---|---|
| `in_service` | 1 while an interrupt service routine runs, from interrupt entry until `RTI`. |
| `saved_pc`, `saved_sr` | The PC and SR saved on interrupt entry and restored by `RTI`. |
| `after_rti` | Set to 1 by `RTI`. Cleared to 0 when the next instruction completes, whether or not its condition is true. While it is 1, no IRQ or NMI is taken (§7.1). |
| `halted` | 1 after `HALT` or any other halt (§5.3, §7.2, §7.4). Only reset clears it. |

Pending interrupt requests (§7.1) are also state. How they are held is a hardware interface matter.

## 2. Instruction format

Every instruction is one **instruction word**, followed by zero to three **constant words**. An instruction is therefore 1 to 4 words long.

### 2.1 Instruction word

| Bits | 31 | 30..28 | 27 | 26 | 25 | 24..21 | 20..14 | 13..7 | 6..0 |
|---|---|---|---|---|---|---|---|---|---|
| ALU | NEG | SEL | 0 | C | M | opcode | dest | s0 | s1 |
| SHIFT | NEG | SEL | 1 | 0 | M | opcode | dest | s0 | s1 |

Control instructions divide the bits below the class differently:

| Bits | 31 | 30..28 | 27 | 26 | 25..21 | 20..8 | 7..0 |
|---|---|---|---|---|---|---|---|
| Control | NEG | SEL | 1 | 1 | command | 0 | vector |

- **NEG, SEL**: the condition (§3).
- **Bits 27..26** select the class: `0x` ALU, `10` SHIFT, `11` control.
- **C** (ALU only): use the C flag as carry or borrow input (§5.1).
- **M**: update the flags from the result (§6).
- **dest, s0, s1**: the three operand fields (§4).
- **command, vector**: the control instruction and, for `INT`, its vector number (§5.3).

The all-zero word is `MOVE R0, R0` with condition "always", so it does nothing. It is the canonical NOP.

### 2.2 Operand field

| Bits | 6..4 | 3..0 |
|---|---|---|
| | mode | register number |

For source operands, bit 6 of the field (mode bit 2) means "the operand is in memory". Destinations differ in one case: mode 011 has bit 6 clear but still writes memory, because it is an alias of mode 111 (§4.2).

### 2.3 Constant words

A field whose mode ends in `11` (modes 011 and 111) takes one constant word. Constant words follow the instruction word in **field order: dest, s0, s1**. Only the fields that use a constant take a word.

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
| 110 | E | `?E` | `?!E` |
| 111 | I | `?I` | `?!I` |

The condition is tested against SR as it was before the instruction started.

In this document, "the M bit" always means instruction bit 25 (modify flags), and "the E flag" means SR bit 30. The 2004 sources call SR bit 30 M, so the assembler also accepts `?M` and `?!M` as aliases for `?E` and `?!E`.

A skipped instruction still consumes its constant words, so PC moves past the whole instruction. A skipped instruction has no other effect: it reads no operand from memory, writes nothing, applies no increments or decrements, and changes no flags.

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
2. **Constants.** For ALU and SHIFT instructions, take one constant word for each field whose mode ends in `11`, in the order dest, s0, s1. For each: c ← mem[PC], then PC ← PC + 1. Control instructions take no constant words.
3. **Condition.** If the condition (§3) is false, the instruction ends here.
4. **Control.** If the instruction is in the control class, run the command (§5.3) and end.
5. **Sources.** Evaluate s0, then s1 (§4.1), including their side effects. Each step sees the registers as earlier steps left them.
6. **Operation.** Compute the result r, plus carry and overflow (§5.1–§5.3).
7. **Destination.** Write r and apply the destination's side effect exactly as §4.2 specifies for its mode, starting from the registers as step 5 left them.
8. **Flags.** Update the flags (§6).

Because step 5 runs before step 7, `MOVE @R1, R1++` with R1 = 0x40 stores 0x40 at address 0x41.

The next instruction is the one at PC as it stands after step 8. Interrupts are taken only between instructions (§7). Steps 1 and 2 are instruction fetches, and every other memory access is a data access. §8.2 defines the two kinds, and §8.3 says what a fetch from the I/O range reads.

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

`MDBL` doubles s0 where s1 has ones: s1 = `0xFFFFFFFF` gives 2·s0 and s1 = 0 gives s0. It comes from the 74181 ALU chip, as do `IAND`, `IOR`, and the other unusual operations.

### 5.2 SHIFT instructions (bits 27..26 = 10)

s0 is the value to shift. s1 is the count: the shift runs **n = s1** steps, using all 32 bits of s1 as an unsigned number (as in QNICE). There is no modulo.

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
| 00001 | `RTI` | `0x0C200000` | Return from interrupt (§7.4). |
| 00010 | `INT n` | `0x0C400000` + n | Software interrupt with vector n, 0–255 (§7.2). |
| others | | | Reserved. Executing one halts the processor. |

Bits 20..8 must be 0, and bits 7..0 must be 0 except in `INT`. An instruction that breaks this is reserved and halts the processor.

The condition field applies, so `?Z HALT` halts only when Z = 1. This includes reserved words: a reserved control word whose condition is false is skipped like any other instruction and does not halt the processor.

Control instructions have no M bit and never update X, C, Z, N, or V. `HALT` leaves SR unchanged, `INT` changes only I (§7.2), and `RTI` replaces SR with the saved copy (§7.4).

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

If M = 0, the flags do not change. This holds for every instruction, shifts included. Control instructions (§5.3) have no M bit and never compute flags from a result. `RTI` restores all of SR, the flags included, from the saved copy.

## 7. Interrupts

NICE has one maskable interrupt request (IRQ), one non-maskable interrupt request (NMI) and a software interrupt (`INT`). The model follows QNICE: the hardware saves PC and SR in hidden registers, `RTI` restores them, and interrupts do not nest.

### 7.1 When an interrupt is taken

Before each instruction, the first one after reset included, the processor checks for pending requests:
- **NMI** is taken if `in_service` = 0.
- **IRQ** is taken if `in_service` = 0 and E = 1.
- If both are pending, NMI goes first.
- A halted processor takes no interrupts.
- No IRQ or NMI is taken while `after_rti` = 1, so the instruction directly after an `RTI` always runs first. That instruction may itself be an `INT`, which works normally. This guarantees that the interrupted program makes progress. A deferred request is taken before the second instruction after `RTI`, unless the first one is an `INT` (then the request waits for that routine's `RTI` as well), halts the processor, or, for an IRQ, leaves E = 0 (then the IRQ waits until software sets E).

**Pending requests are deferred, never lost.** An NMI or IRQ that cannot be taken when it arrives stays pending until it is taken. That happens when `in_service` = 1, or for an IRQ when E = 0. Requests of the same kind that arrive while one is already pending may merge into one, so software must not rely on counting interrupts. A request still pending when the processor halts is never taken, because only reset restarts the processor.

When the processor accepts a request, the device supplies an 8-bit vector number v. The ISA does not say how requests are signalled and acknowledged: edge or level, the handshake, and how a request is held pending are hardware interface matters. The rules above are what software sees.

### 7.2 Interrupt entry

Entry is the same for IRQ, NMI, and `INT v`:

1. saved_pc ← PC, the address of the next instruction. For `INT`, that is the instruction after the `INT`.
2. saved_sr ← SR.
3. in_service ← 1.
4. SR.I ← 1.
5. PC ← mem[(VBASE << 8) + v].

`INT` executed while `in_service` = 1 halts the processor.

### 7.3 Vector table

The vector table has 256 words and starts at address VBASE × 256. Entry v holds the address of the routine for vector v. With VBASE in SR bits 23..0, the table always starts on a 256-word boundary.

To set the table address without touching the flags:

    AND  R14, R14, 0xFF000000        ; keep the flags
    OR   R14, R14, TABLE_ADDR_DIV_256 ; set VBASE

### 7.4 Return

`RTI` does:

1. SR ← saved_sr (bit 24 stays 1).
2. PC ← saved_pc.
3. in_service ← 0.
4. after_rti ← 1.

`RTI` executed while `in_service` = 0 halts the processor.

Because SR is restored, an interrupt routine may change any flag freely, E and I included. An interrupt routine must save and restore any other registers it uses.

## 8. Reset, memory, and I/O

### 8.1 Reset

| State | Value after reset |
|---|---|
| R0–R13, R15 | 0, so execution starts at address 0 |
| R14 | `0x01000000`: only bit 24 set, so E = 0 (maskable interrupts off) and VBASE = 0 |
| in_service, after_rti, halted | 0 |
| Pending interrupt requests | none |
| saved_pc, saved_sr | undefined |
| Memory | not changed by reset |

**NMI after reset.** E = 0 holds off IRQ, but nothing holds off NMI. After reset, VBASE = 0 and PC = 0, so word 0 is both the first instruction and vector table entry 0. An NMI that arrives before the boot code has set VBASE and filled the vector table jumps through whatever those words hold. The system must therefore keep NMI from being raised until software is ready for it. The ISA provides no mechanism for this.

### 8.2 Memory

- A read from an address with no memory or device behind it returns 0. A write to such an address is ignored.
- Each instruction runs with the words that memory held when the instructions before it had completed. So a store may change the next instruction or its constant words, and the change takes effect. An instruction that overwrites its own constant words does not see the change, because they were fetched in step 2.

Memory accesses are of two kinds. **Instruction fetches** read the instruction word and the constant words (steps 1 and 2 of §5). **Data accesses** are the operand reads, the destination writes, and the vector table reads.

**Data accesses are exact and in order.** Each data access named in this document is performed exactly once, as a separate access, and in program order. No data access is merged with another, dropped, repeated, reordered, or performed speculatively. I/O devices may rely on this. For one instruction the data accesses are:

1. None if the condition is false.
2. Read s0 if its mode is 100–111, then s1 if its mode is 100–111. This applies even when the operation ignores the operand (§4.4). So `ADD R1, @R2, @R2` reads mem[R2] twice, and a `MOVE` whose unused s1 field holds `@R3` also reads mem[R3].
3. Write the destination if its mode is 011–111. The destination is never read.

Interrupt entry (§7.2), including `INT`, makes one data access: the read of the vector table entry. Control instructions make no other data accesses.

**Instruction fetches are not ordered.** The processor may fetch instruction words and constant words early, more than once, or for instructions that never run. It may do so in any order relative to data accesses. Only the result is defined: each instruction runs with the words that memory held when the instructions before it had completed. This lets a pipelined processor fetch ahead, and lets instruction fetches and data accesses use separate buses.

### 8.3 Input and output

I/O is memory-mapped. There are no I/O instructions. Addresses `0xFFFFFF00`–`0xFFFFFFFF` are reserved for I/O devices.

Instruction fetches never reach I/O devices. An instruction fetch from `0xFFFFFF00`–`0xFFFFFFFF` reads 0, whatever a data read of the same address returns. The word 0 is a NOP (§2.1), so a program that runs into the I/O range runs through it and wraps to address 0.

The 2004 emulator maps a character screen at `0x400`. That is a property of the emulator, not of the ISA.

The emulator in this repository maps the screen at `0xFFFF0000` instead, so that it does not overlap the code of programs longer than 1024 words. Its option `-2004` puts the screen back at `0x400` for the 2004 programs. It also maps a console at `0xFFFFFF00`. Each write prints bits 7..0 of the word. Each data read takes the next input byte, if there is one, and returns it in bits 7..0 with bit 8 set. With no byte waiting, a read returns 0. When the emulator's input has ended, a read returns `0x200` (bit 9) instead; a UART's input never ends. The emulator reads its input from stdin, so stdin from `/dev/null` gives a console with no input. The simulation memory of the FPGA core has no input either: a read returns `0x200`. The FPGA implementation will have a UART at the same address, with the same bits. At `0xFFFFFF01` the emulator and the simulation memory of the FPGA core map a read counter for tests. A data read of it returns the number of data reads of it since the last write to it, and a write sets that number. Tests use it to count the data accesses of §8.2. These are properties of those systems too, not of the ISA. Programs use the console for input and output.

### 8.4 Math unit

The emulator and the FPGA implementation map a math unit, the MPU, at `0xFFFFFF20`–`0xFFFFFF3F`. It multiplies and divides 32-bit integers, and divides 64-bit integers. Like the console, it is a property of those systems, not of the ISA.

The first 16 words work on the 32-bit operands A and B:

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF20` | `A` | the left operand A | sets A |
| `0xFFFFFF21` | `B` | the right operand B | sets B |
| `0xFFFFFF22` | `SMUL_LO` | bits 31..0 of A · B, signed | is ignored |
| `0xFFFFFF23` | `SMUL_HI` | bits 63..32 of A · B, signed | is ignored |
| `0xFFFFFF24` | `UMUL_LO` | bits 31..0 of A · B, unsigned | is ignored |
| `0xFFFFFF25` | `UMUL_HI` | bits 63..32 of A · B, unsigned | is ignored |
| `0xFFFFFF26` | `SDIV_Q` | the quotient of A / B, signed | is ignored |
| `0xFFFFFF27` | `SDIV_R` | the remainder of A / B, signed | is ignored |
| `0xFFFFFF28` | `UDIV_Q` | the quotient of A / B, unsigned | is ignored |
| `0xFFFFFF29` | `UDIV_R` | the remainder of A / B, unsigned | is ignored |
| `0xFFFFFF2A`–`0xFFFFFF2F` | | 0 | is ignored |

The next 16 words work on the 64-bit operands C and D. Each 64-bit value takes two words, low word first, as in §9.3:

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF30`, `0xFFFFFF31` | `C_LO`, `C_HI` | the left operand C | sets that half of C |
| `0xFFFFFF32`, `0xFFFFFF33` | `D_LO`, `D_HI` | the right operand D | sets that half of D |
| `0xFFFFFF34`, `0xFFFFFF35` | `SDIV64_Q_LO`, `SDIV64_Q_HI` | the quotient of C / D, signed | is ignored |
| `0xFFFFFF36`, `0xFFFFFF37` | `SDIV64_R_LO`, `SDIV64_R_HI` | the remainder of C / D, signed | is ignored |
| `0xFFFFFF38`, `0xFFFFFF39` | `UDIV64_Q_LO`, `UDIV64_Q_HI` | the quotient of C / D, unsigned | is ignored |
| `0xFFFFFF3A`, `0xFFFFFF3B` | `UDIV64_R_LO`, `UDIV64_R_HI` | the remainder of C / D, unsigned | is ignored |
| `0xFFFFFF3C`–`0xFFFFFF3F` | | 0 | is ignored |

- Each result depends only on the operands of its half, A and B or C and D, as they are when it is read. A read has no side effect, so the results can be read in any order and any number of times.
- Signed operations treat the operands as two's complement. A signed product is exact in 64 bits.
- A signed quotient is rounded toward zero, and a signed remainder has the sign of the dividend, so A = Q · B + R and C = Q · D + R. This is C's `/` and `%`, and wasm's `div_s` and `rem_s`.
- Division by zero gives a quotient of all ones and a remainder equal to the dividend, signed and unsigned: Q = `0xFFFFFFFF` and R = A, or Q = `0xFFFFFFFF_FFFFFFFF` and R = C.
- The signed division of the most negative number by −1 gives Q = the most negative number and R = 0. That is `0x80000000 / 0xFFFFFFFF` = `0x80000000` for A and B, and −2⁶³ / −1 = −2⁶³ for C and D.
- Reset sets A, B, C, and D to 0.

These are RISC-V's results for the two special cases. Software never needs to wait for a result. The FPGA implementation starts a new computation at each write to an operand, which may take many cycles, and holds off the acknowledge of a read of a result until the result is ready.

A use of the MPU takes several instructions, and an interrupt may come between them. An interrupt service routine that uses the MPU must therefore read the operands it changes first, and write them back before `RTI`. The results depend only on the operands, so that restores the whole state.

### 8.5 Performance counters

The emulator and the FPGA implementation map two 64-bit performance counters at `0xFFFFFF10`–`0xFFFFFF1F`. Like the console, they are a property of those systems, not of the ISA.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF10` | `CYCLE_LO` | bits 31..0 of the cycle counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF11` | `CYCLE_HI` | bits 63..32 of the cycle counter's snapshot | is ignored |
| `0xFFFFFF12` | `INSTR_LO` | bits 31..0 of the instruction counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF13` | `INSTR_HI` | bits 63..32 of the instruction counter's snapshot | is ignored |
| `0xFFFFFF14`–`0xFFFFFF1F` | | 0 | is ignored |

- The **instruction counter** counts the instructions that have completed since reset. Every instruction counts, including one whose condition is false, a control instruction, and `INT`. An interrupt entry for IRQ or NMI does not count, because it is not an instruction. An instruction that reads `INSTR_LO` reads the number of instructions that completed before it.
- The **cycle counter** counts the clock cycles since reset. The emulator has no clock, so it counts one cycle for each instruction and each interrupt entry, that is, for each step. Its cycle counter is an approximation and differs from the FPGA implementation's.
- Reset sets both counters and both snapshots to 0. Neither counter can be written. A program measures an interval as the difference of two readings.
- A counter wraps from `0xFFFFFFFF_FFFFFFFF` to 0. At one count per cycle at 100 MHz that takes over 5000 years.

**Reading a counter.** Read the low word first, then the high word: `MOVE R1, @CYCLE_LO` then `MOVE R2, @CYCLE_HI`. The read of the low word copies the whole 64-bit counter into the snapshot, and the read of the high word returns the high half of the snapshot. So R2:R1 is the value at the time of the first read, even when the low word wraps from `0xFFFFFFFF` to 0 between the two reads. Each counter has its own snapshot.

An interrupt service routine that reads a counter's low word overwrites its snapshot. If the routine interrupted code between the two reads, that code then reads a high word that may not belong to its low word. So either interrupt service routines do not read the counters, or the code that reads them clears E around its two reads and NMI service routines do not read them.

## 9. Software conventions

These are conventions, not hardware rules.

### 9.1 Stack, call, and return

R13 is the stack pointer, SP. The stack grows down, and SP points at the last item pushed.

| Operation | Code |
|---|---|
| Push x | `MOVE @--SP, x` |
| Pop into x | `MOVE x, @SP++` |
| Call `sub` | `ADD @--SP, 2, PC` then `MOVE PC, sub` |
| Return | `MOVE PC, @SP++` |

The call works because PC reads as the address after `ADD`'s constant word, which is the start of the 2-word `MOVE PC, sub`. Adding 2 gives the address after the `MOVE`.

### 9.2 Jumps and comparisons

| Operation | Code |
|---|---|
| Jump | `MOVE PC, label` |
| Conditional jump | `?Z MOVE PC, label` |
| Relative jump | `ADD PC, PC, offset`. The offset is relative to the next instruction. |
| Compare a with b | `SUB[M] R0, a, b`. Then Z = 1 if a = b, and C = 1 if a < b unsigned. |
| Test a | `MOVE[M] R0, a`. Then Z, N, and X describe a. |

There is no condition or instruction for a signed comparison. A signed a < b is N XOR V after `SUB[M]`, and it is tested with two instructions:

        SUB[M] R0, a, b
    ?V  XOR R14, R14, 0x10000000    ; flip N when V is set
    ?N  MOVE PC, less               ; a < b signed; ?!N for a >= b

After the `XOR`, N is a < b. The write to R14 takes the written value, and leaves the other flags as they were (§4.3). For a > b or a <= b, swap the operands of `SUB[M]`.

### 9.3 C ABI

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
- The null pointer is 0. Word 0 holds the first instruction (§8.1), so no C object is ever at address 0.

**Registers.**

| Register | Use | Preserved across a call |
|---|---|---|
| R0 | Zero | — |
| R1–R4 | Arguments and return value | No |
| R5–R6 | Scratch | No |
| R7–R11 | Variables | Yes |
| R12 | Frame pointer, FP, when a function uses one; otherwise a variable | Yes |
| R13 | Stack pointer, SP (§9.1) | Yes |
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

- SP points at the last word pushed, and the stack grows down (§9.1). The ISA has no alignment rule, so neither does the stack.
- There is no red zone. An interrupt routine may push onto the stack at any time, so the words below SP may change between any two instructions.
- An interrupt routine must save and restore every register it uses (§7.4), R1–R6 included.
- So a C function cannot be an interrupt routine by itself: it may change R1–R6, and it returns with `MOVE PC, @SP++`, not `RTI`. An assembly wrapper saves R1–R6, calls the C function, restores R1–R6, and executes `RTI`.

**Frames.** A function needs no frame pointer. If it uses one, it must build the frame this way. A debugger can then follow the chain of frames through the functions that use one:

    MOVE @--SP, R12          ; save the caller's FP
    MOVE R12, SP             ; FP points at the saved FP
    SUB  SP, SP, n           ; n words for locals and saved registers
    ...
    MOVE SP, R12             ; drop the locals
    MOVE R12, @SP++          ; restore the caller's FP
    MOVE PC, @SP++           ; return

| Address | Contents |
|---|---|
| FP + 2 + k | Stack argument word k |
| FP + 1 | Return address |
| FP | The caller's FP |
| FP − 1 to FP − n | Locals and saved registers, in an order the function chooses |

**Variadic functions.** Since every argument is on the stack, `va_list` is a pointer to the next argument word. `va_start` sets it to the word after the last named argument. `va_arg` reads the argument there and advances the pointer by its size in words.

**Symbol names.** The assembler's labels are case-sensitive, but they may not be mnemonics or register names (§10.1).

- A C function or variable `name` with external linkage gets the label `_name`. So `main` is `_main`, and a C function called `move` does not clash with the mnemonic `MOVE`. Names with internal linkage are covered below.
- Every other label that the compiler emits contains a `.` (see Programs and units). No C identifier contains a `.`, so these cannot clash with external C names.

**Programs and units.** There is no linker. A program is one assembly file, made by joining these files in this order: the start-up code; the compiled units and hand-written assembly files, in any order; the translated wasm module if there is one (§9.4); and the runtime library. Every label and `.EQU` name must therefore be unique in the whole program. The assembler rejects a second definition.

- Only the start-up code may use `.ORG`, because a `.ORG` in one file moves every file after it. Anything that must sit at a fixed address, such as an interrupt vector table (§7.3), therefore belongs in the start-up code.

- Each compiled unit has a unit name, given when it is compiled, for example from the file name. It consists of letters, digits, and `_`, and it differs from the names of the other units in the program.
- The compiler's own labels are `L.unit.n`, for example `L.main.12`.
- A `static` function or variable at file scope gets the label `_name.unit`, for example `_count.main` for `static int count` in the unit `main`. A `static` variable inside a function gets one of the compiler's own labels.
- Two units that define the same external name both define `_name`, and the assembler rejects the program, as a linker would.
- Compiled and translated code writes R13 and R15 and defines no `.EQU` names. Hand-written files may define names such as `SP` and `PC`, but only one file may define each name. The examples in this section and in §9.4 use `SP` and `PC` for readability.

**Runtime routines.** NICE has no multiply or divide instruction, and no floating-point instructions. The compiler calls routines in the runtime library instead. They follow the rules above.

- There is one runtime library, shared by the C compiler and the wasm translator (§9.4).
- A routine may be written in assembly, or translated from a library module (§9.4).
- The labels of its routines start with `__`. Their C names start with `_`, which C reserves for the implementation at file scope. The labels inside a translated library module start with `WL.` (§9.4), which no C name can produce.
- The multiply and divide routines, for one-word integers and for `long long`, come in two versions: one that uses the math unit of §8.4, and one in software for systems without it. A program contains exactly one of the two.
- The table lists the routines for one-word integers. The runtime library's README lists all routines, including those for `long long`, floating point, and conversions between them.

| Label | Result in R1 |
|---|---|
| `__mul` | R1 × R2, the low 32 bits. The same routine serves signed and unsigned operands. |
| `__div`, `__mod` | Signed R1 / R2 and R1 % R2, rounding toward zero as C requires. |
| `__udiv`, `__umod` | Unsigned R1 / R2 and R1 % R2. |

Division by zero is undefined in C, so these routines may return any value for it.

**Start-up.** The start-up code sits at address 0. It sets SP to one past the highest word the program may use, so that the first push lands on that word. If the program has a wasm module, it then calls `___wasm_start` (§9.4). The runtime library has two versions of the start-up code, one with this call and one without, and a program uses the version that matches it. Then the start-up code calls `_main` with R1 = 0 and R2 = 0, so a `main(int argc, char **argv)` sees no arguments and a null `argv`. After `main` returns, the start-up code executes `HALT` with `main`'s return value still in R1. Static data gets its initial values when the program image is loaded. Reset does not restore them.

**Example.** This function and call:

    int f(int a, int b, int c, int d, int e) { return a + e; }
    ...
    x = f(1, 2, 3, 4, 5);

compile to:

    _f      ADD  R1, R1, @1[SP]  ; e is the first stack argument
            MOVE PC, @SP++       ; return
            ...
            MOVE @--SP, 5        ; e goes on the stack
            MOVE R1, 1           ; a to d go in registers
            MOVE R2, 2
            MOVE R3, 3
            MOVE R4, 4
            ADD  @--SP, 2, PC    ; call f
            MOVE PC, _f
            ADD  SP, SP, 1       ; remove e
            MOVE @_x, R1         ; x = f(...)

### 9.4 WebAssembly mapping

Rust and Zig assume 8-bit bytes, so they cannot use the C ABI's one-word `char` (§9.3). Instead, their compilers emit a wasm32 WebAssembly module, and a translator turns the module into NICE assembly. Clang can do the same for C code that needs 8-bit bytes. These rules say how a module maps onto NICE, so that translated code, C code, and assembly code can work together.

The WebAssembly specification defines what each wasm instruction does. A translator must keep those results, except where this section says otherwise. Which wasm features a translator supports is up to the translator, and its README must list them. A program contains at most one wasm module, not counting library modules.

**Library modules.** Runtime routines (§9.3) may be compiled to wasm, for example from compiler-rt, and translated as a library module. A library module differs from a program's module in these ways:

- The translator is given a name for it, which is a C identifier. The labels the translator makes for itself start with `WL.name.` instead of `W.`, for example `WL.float.f3`, so that the labels of two library modules cannot clash.
- Each exported function gets the label `_name`, including when the name starts with `_`. So the export `__divdi3` gets the label `___divdi3`.
- It has no start function, it does not export `__wasm_call_ctors`, and it uses neither `memory.size` nor `memory.grow`. The translator rejects one that does, and it emits no `___wasm_start`.
- Its memory and its globals are its own, separate from those of the program's module. Compilers use them for a stack, for example to pass 128-bit values. The memory is at the label `WL.name.memory`. Its words are part of the program image, with the values that its data segments give and 0 elsewhere, like C static data (§9.3).
- The translator reserves only the start of the memory, as much as the module's stack and data need. It chooses the size, for example from the initial value of the stack pointer. A whole page of 16384 words would cost more RAM than the routines themselves. An access past the reserved part traps as out of bounds (code 2), unless the bounds checks are left out.

A program may contain any number of library modules. They go with the runtime library, after the program's module.

**Values.**

| Wasm type | Words | Same as the C type (§9.3) |
|---|---|---|
| `i32` | 1 | `int` or `unsigned int` |
| `i64` | 2 | `long long` or `unsigned long long` |
| `f32` | 1 | `float` |
| `f64` | 2 | `double` |

**Linear memory.** Linear memory is byte-addressed. It is stored four bytes to a word, starting at a word address chosen by the translator:

- Byte address *b* is bits 8·(*b* mod 4) + 7 to 8·(*b* mod 4) of the word at `MEMBASE` + ⌊*b* / 4⌋. Byte 0 of a word is its least significant byte, as in `.ASCII_B` (§10.3).
- Wasm is little-endian, so an `i32` at a byte address that is a multiple of 4 is exactly one NICE word. An `i64` there is two words, low word first, as in §9.3.
- A page is 65536 bytes, or 16384 words. The translator reserves words for the memory up to a cap. The cap is at least the module's initial size and at most its maximum size, if it declares one. The translator chooses it, for example by an option, because a module may declare a maximum that no NICE system has room for. `memory.grow` returns −1 if the new size would pass the cap.
- The words that active data segments set are part of the program image, like C static data (§9.3). The translator reserves the rest of the memory with `.RES` (§10.3), so it is not in the image. Wasm requires new memory to be 0, so `___wasm_start` sets the initial pages to 0, except the words that data segments set, and `memory.grow` sets each new page to 0.
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

These exist to reach devices, so the §8.2 rule for data accesses applies to them as to any instruction. Each call is performed exactly once and in program order, even when the result of a `peek` is not used.

In Rust, they are declared in an `extern "C"` block with `#[link(wasm_import_module = "nice")]`. In Zig, they are `extern "nice" fn peek(addr: u32) u32` and `extern "nice" fn poke(addr: u32, val: u32) void`. Zig must use `u32`, because the I/O addresses `0xFFFFFF00`–`0xFFFFFFFF` do not fit in an `i32`. Both types become `i32` in wasm.

**Functions and calls.** A wasm function is a §9.3 function whose parameter and result types are the C types in the table above:

- Parameters go in R1–R4 and on the stack, by the §9.3 rules for a function that is not variadic.
- Results go in registers by the same rules that would apply if they were arguments. A function with no result returns nothing. The translator rejects a function type whose results do not all fit in R1–R4.
- R7–R13 and SR's I, E, and VBASE are preserved, as in §9.3.
- Wasm locals and the wasm operand stack live in registers and in the function's frame on the NICE stack (R13).

The module's own stack is separate. Compilers for wasm keep the variables whose address is taken in linear memory, below the global `__stack_pointer`. That stack is ordinary module data, and the translator gives it no special treatment.

**Globals.** Each global is one word, or two for `i64` and `f64`, at a fixed address chosen by the translator. It starts with the value the module gives it.

**Tables and indirect calls.**

- Each entry of table 0 is two words: the address of a function, and a number for the function's type. Two types with the same parameters and results get the same number. An empty entry has address 0.
- `call_indirect` traps if the index is past the end of the table, if the entry is empty, or if its type number differs from the type of the call. Otherwise it calls the address with the "through a register" sequence of §9.3.
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

The runtime library defines `___wasm_trap_vector` and starts it with the address of its default handler, `___wasm_trap`. The handler is the reserved control word `0x0FE00000` (§5.3), so the processor halts with R1 and R2 as the trap left them. Unlike a `HALT`, this halt cannot be mistaken for the normal end of the program. The emulator reports it as an abnormal halt. A label may be defined only once (§9.3), so a program cannot replace `___wasm_trap`. Instead, it installs its own handler at run time by storing the handler's address in the vector. From C, that is:

    extern void (*__wasm_trap_vector)(int code, unsigned addr);
    ...
    __wasm_trap_vector = my_trap;

A handler is entered by a jump, not a call, so mem[SP] is not a return address, and SP is wherever the trapping function left it. A handler must therefore not return.

Running out of NICE stack is not detected, unlike in wasm. What happens then is undefined.

**Imports and exports.**

- An exported function or global whose name is a C identifier gets the label `_name`, as in §9.3. So C code calls an exported wasm function `sum` as `sum`. Names that start with `_` are reserved for the runtime library (§9.3), so they get no label, and neither do names that are not C identifiers.
- A function imported from the module `env` is the §9.3 function `name`, at the label `_name`. Rust, Zig, and clang put their `extern` functions in `env` unless told otherwise.
- The translator rejects an import from `env` whose name starts with `_`. Such names are reserved for the runtime library (§9.3), and the translator calls the routines it needs itself. Clang imports them for routines that the runtime library does not have, such as `__multi3` for `__int128` and `__addtf3` for `long double`.
- The translator accepts only function imports from `env`, and only `peek` and `poke` from `nice`. It rejects every other import. This includes imported globals, memories, and tables, such as those that `--import-memory` or position-independent code produce.
- Labels that the translator makes for itself start with `W.`, for example `W.f12` for function 12. They cannot clash with C names, or with the C compiler's labels, which start with `L.`.

**Pointers at the boundary with C.** A wasm pointer is a byte address in linear memory. A C pointer is a word address. Wasm has no pointer type, so the translator cannot tell a pointer from a number, and it converts nothing. A pointer from wasm reaches C as an integer that holds a byte address, and the C code converts it:

- The C address of wasm byte address *p* is `__wasm_memory + p / 4`. This works only if *p* is a multiple of 4. C then sees the data packed four bytes to a word.
- To pass C data to wasm, it must be in linear memory. The byte address of the word at C address *q* is (*q* − `__wasm_memory`) × 4.
- Wasm code cannot reach C data outside linear memory, except through `nice.peek` and `nice.poke`.
- Only `i32`, `i64`, `f32`, and `f64` values cross the boundary. Clang and Rust pass a structure with a single scalar member in an `extern "C"` signature as that scalar. They pass any other structure as a pointer into linear memory, so C receives a byte address there too.
- Function pointers do not cross the boundary. A wasm function pointer is a table index, and a C function pointer is a NICE address.

**Runtime routines.** The translator uses the runtime library of §9.3, which it shares with the C compiler. For `i32.mul`, and the `div` and `rem` of `i32` and `i64`, it uses the math unit of §8.4 directly: it writes the operands to A and B, or C and D, and reads the result. With an option, for systems without the math unit, it calls `__mul`, `__div`, `__mod`, `__udiv`, `__umod`, and the `64` versions of the last four instead. Before a division or remainder, it checks the cases that wasm defines but C leaves undefined:

- division or remainder by zero traps (code 3)
- `div_s` of the most negative value by −1 traps (code 4)
- `rem_s` of the most negative value by −1 is 0.

Before it converts a float to an integer with `trunc`, it checks that the result fits. A NaN, or a value whose integer part does not fit, traps (code 5).

The routines for `i64` and floating point are in the same library and listed in its README.

**Other differences from NICE.**

- Wasm takes shift and rotate counts modulo 32, or 64 for `i64`. NICE uses the full count (§5.2), so the translator must mask it first.
- NICE has no arithmetic right shift, so `i32.shr_s` becomes the two-instruction sequence of §5.2.

**Start-up.** The start-up code is that of §9.3. For a program with a wasm module, it calls `___wasm_start` before `_main`.

- The translator always emits `___wasm_start`, a §9.3 function with no arguments and no result. First it sets the memory to 0, as described under Linear memory. Then it calls the module's start function, if there is one. Then it calls `__wasm_call_ctors`, if the module exports a function of that name. Otherwise it just returns. The name starts with `_`, so the export gets no label of its own (see Imports and exports), and the translator calls it by its `W.` label.
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

## 10. Assembler syntax

This follows the 2004 assembler in `NICE.pm`, with a few changes listed in Appendix B. The assembler's [README](../assembler/README.md) adds the finer points of the syntax and its error checks.

### 10.1 Statements

    [label]  [?cond]  MNEMONIC[mods]  dest, s0, s1    ; comment

- **Case.** Labels and `.EQU` names are case-sensitive. Mnemonics, register names, conditions, modifiers, and directives are not.
- **Comments.** A comment starts with `;` or `*` and runs to the end of the line.
- **Separators.** Operands are separated by whitespace or by one comma.
- **Labels.** A label is the first word on a line that is not a mnemonic or a directive. It may end with `:`, and so may an `.EQU` name. Its value is the address of what follows on that line; on a `.ORG` line, that is the new address. A label or `.EQU` name cannot be a mnemonic or a register name.
- **Conditions.** `?cond` is one of the condition codes in §3, such as `?Z` or `?!C`. Without one, the instruction is unconditional. `?M`/`?!M` are accepted as aliases for `?E`/`?!E`.
- **Modifiers.** `[M]` sets the M bit and `[C]` sets the C bit. `[CM]` and `[MC]` set both. `[C]` is accepted only on ALU instructions.
- **Operand counts.** The assembler expects exactly the operands the instruction uses:
  - `ONE` takes dest only.
  - `MOVE`, `DBL`, `DEC`, and `NOT` take dest and s0.
  - The other ALU and SHIFT instructions take dest, s0, and s1.
  - `HALT` and `RTI` take none, and `INT` takes the vector number.
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

- **Numbers and expressions.** `0x` hex, `0b` binary, and plain decimal. The prefix and the digits may be in either case. There is no `#` prefix and no `$`. A label or an `.EQU` name may appear wherever a number may. A constant may also be an expression: numbers and symbols joined with `+` and `-`, with an optional leading sign and no spaces, such as `end-data` or `-1`. The value wraps modulo 2³².
- **Register aliases.** Programs define them with `.EQU`, for example `SP .EQU R13` and `PC .EQU R15`.

### 10.3 Directives

| Directive | Effect |
|---|---|
| `NAME .EQU value` | Defines NAME. The value is a number, an expression, a register, or a complete operand. NAME is replaced by the value where it stands for a whole operand, a register, or a number in an expression. |
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

    ?!Z ADD[M] @R3++, --R2, @0x12345678[R1]

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
| 11 | command, bits 25..21 | | `HALT` (0), `RTI` (1), `INT` (2), reserved (3–31) |

## Appendix B: Departures from the sources

| Topic | This specification | Sources that disagree |
|---|---|---|
| Condition field and SR layout | NEG at bit 31, SEL at 30..28; SR bits 31..24 = `I E V N Z C X 1` (2004 web page and emulator, same as QNICE) | Both articles: SEL at 31..29, NEG at 28, SR bit 31 = 1 |
| Meaning of SR bits 31 and 30 | I = an interrupt was taken, E = maskable interrupts enabled (web page) | Articles: M = maskable interrupt occurred, I = enabled |
| Name of SR bit 30 | E, so that M only ever means the instruction's modify-flags bit | Web page and emulator call it M, with condition `?M` |
| Order of constant words | dest, s0, s1 (emulator and its binaries) | 1997 article: s1, s2, dest |
| R15 as an operand | Address of the next instruction (1999 article, emulator, QNICE) | 1997 article: the current instruction |
| Interrupt model | Hidden saved PC and SR, `RTI`, `INT`, no nesting (QNICE) | Articles and web page: R13 receives the return address and software nests interrupts |
| HALT encoding space | Control group with `HALT`, `RTI`, `INT`; reserved commands halt | Web page: spare bits "have no meaning and should be zero" |
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
| Interrupt entry details | Entry sets I; NMI is taken before IRQ; NMI does not nest either (§7.1, §7.2) | Not specified anywhere. The articles have NMI and IRQ serviced "the same way". |
| Pending interrupt requests | Deferred, never lost; same-kind requests may merge (§7.1) | Not specified anywhere |
| Interrupts right after `RTI` | No IRQ or NMI until the instruction after `RTI` completes (`after_rti`, §7.1) | Not specified anywhere. QNICE guarantees the same progress. |
| Memory access order | Each data access exactly once, unmerged, and in program order. Instruction fetches may run ahead, repeat, or be wasted (§8.2) | Not specified anywhere |
| Instruction fetches from the I/O range | Read 0 and never reach a device (§8.3) | Not specified anywhere |
| Carry input timing | The C flag as step 5 of §5 left it (§5.1, §5.2) | Not specified anywhere. The emulator also reads C after the source operands. |
| Assembler numbers | `0x`, `0b`, decimal | The emulator reads a leading 0 as octal; the articles use `#` and `$` |
| Assembler directives and constants | `.DAT` takes several values, a constant may be an expression, and a string may use `"..."` (§10) | `NICE.pm` takes one value per directive, a number or a symbol only, and `'...'` only |
| `.RES` directive | Reserves words that are not in the program image (§10.3) | The 2004 assembler has no such directive. Every word it reserves, with `.BLK`, is in the image. |

The emulator also has bugs that this specification does not copy. Its carry input comes from the wrong SR bit, its 5-bit count mask is wrong, it modifies source registers, it never sets X, `ONE` crashes, `1>0` and `C>0` fill the wrong end, and `DEC` reports a borrow in V. See [review/emulator-and-webpage-review.md](review/emulator-and-webpage-review.md) §4.
