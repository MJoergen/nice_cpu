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

Software can read and write every bit except bit 24. Instructions with the M bit set update only X, C, Z, N and V (§6). I, E and VBASE change only when software writes R14, on interrupt entry (I), and on `RTI`.

### 1.4 Hidden state

These are not visible as registers. They exist for interrupts (§7) and halting:

| State | Meaning |
|---|---|
| `in_service` | 1 while an interrupt service routine runs, from interrupt entry until `RTI`. |
| `saved_pc`, `saved_sr` | The PC and SR saved on interrupt entry and restored by `RTI`. |
| `after_rti` | Set to 1 by `RTI`. Cleared to 0 when the next instruction completes. While it is 1, no IRQ or NMI is taken (§7.1). |
| `halted` | 1 after `HALT`. Only reset clears it. |

Pending interrupt requests (§7.1) are also state. How they are held is a hardware interface matter.

## 2. Instruction format

Every instruction is one **instruction word**, followed by zero to three **constant words**. An instruction is therefore 1 to 4 words long.

### 2.1 Instruction word

| Bits | 31 | 30..28 | 27 | 26 | 25 | 24..21 | 20..14 | 13..7 | 6..0 |
|---|---|---|---|---|---|---|---|---|---|
| ALU | NEG | SEL | 0 | C | M | opcode | dest | s0 | s1 |
| SHIFT | NEG | SEL | 1 | 0 | M | opcode | dest | s0 | s1 |
| Control | NEG | SEL | 1 | 1 | command (bits 25..21) | | must be 0 (bits 20..8) | | vector (bits 7..0) |

- **NEG, SEL**: the condition (§3).
- **Bits 27..26** select the class: `0x` ALU, `10` SHIFT, `11` control.
- **C** (ALU only): use the C flag as carry or borrow input (§5.1).
- **M**: update the flags from the result (§6).
- **dest, s0, s1**: the three operand fields (§4).

The all-zero word is `MOVE R0, R0` with condition "always", so it does nothing. It is the canonical NOP.

### 2.2 Operand field

| Bits | 6..4 | 3..0 |
|---|---|---|
| | mode | register number |

Bit 6 of the field (mode bit 2) means "the operand is in memory".

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

A skipped instruction still consumes its constant words, so PC moves past the whole instruction. A skipped instruction has no other effect: it reads no memory, writes nothing, applies no increments or decrements and changes no flags.

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

### 4.3 Special registers in operands

- **R0** reads as 0 in every mode, at every point within an instruction. Writes to R0 and side effects on R0 are discarded. So `--R0` and `R0++` read 0, `@R0`, `@--R0` and `@R0++` all address word 0, as source or destination, and `c[R0]` is c.
- **R15** read as an operand gives the address of the **next instruction**, after all of this instruction's constant words. The exception is when an earlier operand of the same instruction has already changed R15 with a side effect.
- **R15** is an ordinary register in every mode. Any write to it is a jump, including a side effect such as `R15++`. If one instruction writes R15 more than once, the last write in the order of §5 wins.
- **R14 bit 24** reads as 1 at every point within an instruction. Every write to R14, a side effect included, sets bit 24 to 1. So after reset (R14 = `0x01000000`), `MOVE R1, --R14` sets R14 and R1 to `0x01FFFFFF`, and `@--R14` addresses word `0x01FFFFFF`.
- **R14** written as a register-direct destination (modes 000, 001 and 010) takes the written value, except that bit 24 stays 1. The flag update is skipped in that case (§6).

### 4.4 Unused operand fields

Some operations ignore an operand: `MOVE`, `DBL`, `DEC` and `NOT` ignore s1, and `ONE` ignores s0 and s1. The field is still evaluated in full: it takes its constant word, reads memory and applies its side effect. The assembler encodes unused fields as `000 0000` (R0), so they have no effect.

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

The next instruction is fetched from PC as it stands after step 8. Interrupts are taken only between instructions (§7).

### 5.1 ALU instructions (bit 27 = 0)

`cin` is the C flag if the instruction's C bit is set, and 0 otherwise. Only `SUB`, `MDBL`, `ADD` and `DBL` use it. All other ALU operations ignore the C bit.

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

`MDBL` doubles s0 where s1 has ones: s1 = `0xFFFFFFFF` gives 2·s0 and s1 = 0 gives s0. It comes from the 74181 ALU chip, as do `IAND`, `IOR` and the other unusual operations.

### 5.2 SHIFT instructions (bits 27..26 = 10)

s0 is the value to shift. s1 is the count: the shift runs **n = s1** steps, using all 32 bits of s1 as an unsigned number (as in QNICE). There is no modulo.

The mnemonic shows the direction and where bits come from and go to:
- **Left shifts `A<B`**: B is the fill bit shifted into bit 0 (0, 1 or C), and A is where bit 31 goes (0 = discarded, C = the carry flag).
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

**Exact definition.** Let d = s0 and c = the C flag. Repeat n times:

- Left: out = d[31], d = (d << 1) OR fill.
- Right: out = d[0], d = (d >> 1) OR (fill << 31).
- Here fill is 0, 1, c, or out (for the rotations), as the table says.
- If the bit shifted out goes to C, then c ← out.

r = d. Note that for `0<C` and `C>0`, c never changes, so every fill bit is the original C.

The loop defines the result for every count, but hardware need not run it n times. The same results in closed form:

- **Shifts with a fixed fill** (0, 1, or the original C; that is, every shift except the rotations and `C<C`/`C>C`):
  - For n ≥ 32, the result is all fill bits.
  - Where the bit shifted out goes to C, n = 32 leaves C = the last bit of s0 shifted out (bit 0 for a left shift, bit 31 for a right shift), and n > 32 leaves C = the fill bit.
- **`<<<`, `C<<`, `>>>` and `>>C`** are 32-bit rotations, so only n mod 32 matters for the result. For `C<<` and `>>C` with n > 0, C ends up equal to the bit that was rotated last: bit 0 of r for `C<<`, and bit 31 of r for `>>C`.
- **`C<C` and `C>C`** are 33-bit rotations of C and s0 together, so only n mod 33 matters.

**The C flag after a shift:**
- If M = 0, no shift changes C. The fill still reads C, but c is not written back.
- If M = 1, the eight shifts whose bit shifted out goes to C set the C flag to c. With n = 0, c is the old C, so C is unchanged.
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

The condition field applies, so `?Z HALT` halts only when Z = 1.

Control instructions have no M bit and never update X, C, Z, N or V. `HALT` leaves SR unchanged, `INT` changes only I (§7.2), and `RTI` replaces SR with the saved copy (§7.4).

## 6. Flags

If M = 1, and the destination is not R14 in a register-direct mode (000, 001 or 010), then after the destination is written:

| Flag | New value |
|---|---|
| X | 1 if r = `0xFFFFFFFF` |
| Z | 1 if r = 0 |
| N | bit 31 of r |
| C | as given in §5.1 and §5.2 |
| V | as given in §5.1, and 0 for shifts |

The flags are computed from the result r of the operation, not from the value stored by a `Rx++` or `Rx--` destination.

If M = 0, the flags do not change. This holds for every instruction, shifts included. Control instructions (§5.3) have no M bit and never update the flags.

## 7. Interrupts

NICE has one maskable interrupt request (IRQ), one non-maskable interrupt request (NMI) and a software interrupt (`INT`). The model follows QNICE: the hardware saves PC and SR in hidden registers, `RTI` restores them, and interrupts do not nest.

### 7.1 When an interrupt is taken

Before each instruction fetch, the processor checks for pending requests:
- **NMI** is taken if `in_service` = 0.
- **IRQ** is taken if `in_service` = 0 and E = 1.
- If both are pending, NMI goes first.
- A halted processor takes no interrupts.
- No IRQ or NMI is taken while `after_rti` = 1, so the instruction directly after an `RTI` always runs first. That instruction may itself be an `INT`, which works normally. This guarantees that the interrupted program makes progress. A deferred NMI waits at most one instruction after `RTI`. A deferred IRQ does the same if E = 1 in the restored SR, and otherwise waits until software sets E.

**Pending requests are deferred, never lost.** An NMI or IRQ that cannot be taken when it arrives stays pending until it is taken. That happens when `in_service` = 1, or for an IRQ when E = 0. Requests of the same kind that arrive while one is already pending may merge into one, so software must not rely on counting interrupts. A request still pending when the processor halts is never taken, because only reset restarts the processor.

When the processor accepts a request, the device supplies an 8-bit vector number v. The ISA does not say how requests are signalled and acknowledged: edge or level, the handshake, and how a request is held pending are hardware interface matters. The rules above are what software sees.

### 7.2 Interrupt entry

Entry is the same for IRQ, NMI and `INT v`:

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

## 8. Reset, memory and I/O

### 8.1 Reset

| State | Value after reset |
|---|---|
| R0–R13, R15 | 0, so execution starts at address 0 |
| R14 | `0x01000000`: only bit 24 set, so E = 0 (maskable interrupts off) and VBASE = 0 |
| in_service, after_rti, halted | 0 |
| Pending interrupt requests | none |
| saved_pc, saved_sr | undefined |
| Memory | not changed by reset |

### 8.2 Memory

- A read from an address with no memory or device behind it returns 0. A write to such an address is ignored.
- Every instruction fetch sees all earlier writes. A store may change the next instruction or its constant words, and the change takes effect. An instruction that overwrites its own constant words does not see the change, because they were fetched in step 2.

### 8.3 Input and output

I/O is memory-mapped. There are no I/O instructions. Addresses `0xFFFFFF00`–`0xFFFFFFFF` are reserved for I/O devices.

The 2004 emulator maps a character screen at `0x400`. That is a property of the emulator, not of the ISA.

## 9. Software conventions

These are conventions, not hardware rules.

### 9.1 Stack, call and return

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
| Test a | `MOVE[M] R0, a`. Then Z, N and X describe a. |

No single flag gives a signed comparison. A signed a < b is N XOR V after `SUB[M]`, which takes more than one conditional instruction to test.

## 10. Assembler syntax

This follows the 2004 assembler in `NICE.pm`, with a few changes listed in Appendix B.

### 10.1 Statements

    [label]  [?cond]  MNEMONIC[mods]  dest, s0, s1    ; comment

- **Case.** Mnemonics, register names and directives are case-insensitive.
- **Comments.** A comment starts with `;` or `*` and runs to the end of the line.
- **Separators.** Operands are separated by commas or whitespace.
- **Labels.** A label is the first word on a line that is not a mnemonic or a directive. Its value is the address of what follows on that line.
- **Conditions.** `?cond` is one of the condition codes in §3, such as `?Z` or `?!C`. Without one, the instruction is unconditional. `?M`/`?!M` are accepted as aliases for `?E`/`?!E`.
- **Modifiers.** `[M]` sets the M bit and `[C]` sets the C bit. `[CM]` and `[MC]` set both. `[C]` is accepted only on ALU instructions.
- **Operand counts.** The assembler expects exactly the operands the instruction uses:
  - `ONE` takes dest only.
  - `MOVE`, `DBL`, `DEC` and `NOT` take dest and s0.
  - The other ALU and SHIFT instructions take dest, s0 and s1.
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

- **Numbers.** `0x` hex, `0b` binary, and plain decimal. There is no `#` prefix and no `$`. A label or an `.EQU` name may appear wherever a number may.
- **Register aliases.** Programs define them with `.EQU`, for example `SP .EQU R13` and `PC .EQU R15`.

### 10.3 Directives

| Directive | Effect |
|---|---|
| `NAME .EQU value` | Defines NAME. It is substituted textually, so it can stand for a number or a register. |
| `.ORG addr` | Continue assembling at addr. |
| `.DAT value` | One word holding value. |
| `.BLK n` | n words of 0. |
| `.ASCII_L 'text'` | One character per word, followed by a 0 word. |
| `.ASCII_B 'text'` | Four characters per word, with the first character in the least significant byte. The last word is padded with 0 bytes. No terminator is added when the length is a multiple of 4. |

### 10.4 Object format

The `.bin` format is plain text with one line per assembled word: an 8-digit hex address, a space, and the 8-digit hex word. Lines are in address order, for example `00000002 0077580f`.

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
4. X, C, Z, N and V are updated.
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
| Assembler numbers | `0x`, `0b`, decimal | The emulator reads a leading 0 as octal; the articles use `#` and `$` |

The emulator also has bugs that this specification does not copy. Its carry input comes from the wrong SR bit, its 5-bit count mask is wrong, it modifies source registers, it never sets X, `ONE` crashes, `1>0` and `C>0` fill the wrong end, and `DEC` reports a borrow in V. See [review/emulator-and-webpage-review.md](review/emulator-and-webpage-review.md) §4.
