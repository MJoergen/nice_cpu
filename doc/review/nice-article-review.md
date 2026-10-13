# NICE article review: inconsistencies, gaps and ambiguities

Source: B. Ulmann, *NICE – an elegant and powerful 32-bit architecture*, Sept 8 1997 (journal pages 30–35, uploaded as `Bernds-NICE.pdf`).

*Note: this review and the three files next to it record how the ISA decisions were reached. [../ISA.md](../ISA.md) is the specification and supersedes them.*

Purpose: list everything a complete, implementable ISA specification must settle that the article gets wrong, leaves out, or leaves open.
Page references are the journal page numbers printed at the bottom of each page (30–35).

The repository `MJoergen/nice_cpu` currently holds only a README, so there is no prior material to reconcile with.

---

## 0. What the article does define (baseline)

So the findings below have a reference point, this is the encoding as the article states it.

**Instruction word (Fig. 2, 6, 7, 8)**

| Bits | ALU (bit27=0) | SHIFT (bit27=1, bit26=0) | HALT (bit27=1, bit26=1) |
|---|---|---|---|
| 31..29 | condition select | condition select | condition select |
| 28 | negate (`/`, written `!`) | negate | negate |
| 27 | 0 | 1 | 1 |
| 26 | C (use carry-in) | 0 | 1 |
| 25 | M (modify flags) | M | unspecified |
| 24..21 | ALU opcode | SHIFT opcode | unspecified |
| 20..14 | destination operand | destination | unspecified |
| 13..7 | source 1 | source 1 | unspecified |
| 6..0 | source 2 | source 2 | unspecified |

**Operand field (Fig. 4):** 3 mode bits (bit 2 = indirect) + 4-bit register number.

| Mode | Destination | Source |
|---|---|---|
| 000 | `Rx` | `Rx` |
| 001 | `Rx--` (post-decrement, special case) | `--Rx` |
| 010 | `Rx++` | `Rx++` |
| 011 | `@#c[Rx]` (forced indirect) | `#c[Rx]` (= c + Rx) |
| 100 | `@Rx` | `@Rx` |
| 101 | `@--Rx` | `@--Rx` |
| 110 | `@Rx++` | `@Rx++` |
| 111 | `@#c[Rx]` | `@#c[Rx]` (= mem[c + Rx]) |

Constants `c` occupy the words following the instruction, ordered source 1, source 2, destination (footnote 3).

**SR = R14 (Fig. 1):** bit 31 `1`, 30 X, 29 C, 28 Z, 27 N, 26 V, 25 M, 24 I, bits 23..0 interrupt vector table base.
**Other registers:** R0 reads as 0, writes discarded; R13 = interrupt return address ("IR"); R15 = PC, and "PC points to the actual instruction location during the whole execution cycle" (p. 32).

---

## 1. Contradictions and errors

These are places where the article disagrees with itself. Each needs a decision.

1. **`iand` and `ior` have identical definitions** (ALU table, p. 32). Both read `d = ¬s1 ∨ s2`. One is a typo. Since `ior` = "inverted or" fits `¬s1 ∨ s2`, `iand` is almost certainly `d = ¬s1 ∧ s2`. Decide and fix.

2. **Setting the interrupt-enable flag uses the wrong bit** (p. 34, §5.3). The example enables interrupts with `or r14,r14,#$0200`, which sets bit 9. Figure 1 puts I at bit 24 (`$01000000`). Bit 9 lies inside the vector-table address field. The example appears to come from an older SR layout.

3. **Loading the vector table base shifts the wrong way** (p. 34, §5.3). `0<0 r14,#ivt,#8` shifts *left*. Footnote 5 and §4 say the *upper* 24 address bits go into SR bits 23..0, which needs a right shift (`0>0`). As written it would put address bits into the flag byte.

4. **That same example clobbers all flags, including the "always true" bit.** Any whole-register write to R14 (`0<0 r14,...`, or `0>0` if fixed) overwrites bits 31..24. If bit 31 is an ordinary storage bit, writing 0 there makes every unconditional instruction be skipped, and the machine locks up. The article never says bit 31 is hard-wired. It must be (read-only 1), or the "always" condition must be encoded some other way.

5. **"Fixed format, 32-bit instructions" vs. trailing constant words** (Abstract, §2 p. 31, footnote 3). Modes 011/111 each add a 32-bit constant word after the instruction, so an instruction is 1–4 words long. The format of the first word is fixed; the instruction length is not. The spec should say so explicitly, because fetch, PC update and conditional skip all depend on it.

6. **"PC points to the current instruction during the whole cycle" vs. using R15 with side effects.** The article also says every register can be used in every context without restrictions (p. 30). That collides with `R15++`, `--R15`, `@R15++`, R15 as a post-inc/dec destination, and with the need to read constant words that follow the instruction. Either those combinations get defined semantics or they are declared reserved/undefined.

7. **Order of the constants in the coding example** (p. 32). Footnote 3 says constants are stored s1 first, then s2, then the destination. For `add r1,@#10[PC],@#$11[PC]` that means `$10` first, then `$11`. The text says "the constants $11 and $10 are stored in the two memory locations directly following", which reads as the opposite order. The same example also writes `@#10` (no `$`) while the prose says `$10`, so it is unclear whether unprefixed numbers are decimal or hex.

8. **Mnemonic `move` vs. `mov`.** The ALU table defines `move`; the examples mostly use `mov`, and §5.3 mixes both in the same listing (`move r14,@--r12` in the handler, `mov r14,@--r12` in the macro text). Similarly `<M>`/`<CM>` in §5.1 vs. `<m>`/`<c>` in the code (case sensitivity is not stated).

9. **"Sixteen general purpose registers"** (Abstract) vs. §1, where only R1–R12 are general purpose and R0, R13, R14, R15 are special. Minor, but the ISA document should use one description.

10. **R13 wording.** §1 says R13 is loaded "after receiving a non masked interrupt request". §4 says R13 is loaded for *both* maskable and nonmaskable interrupts. "Non masked" probably means "not masked out", but it reads like "nonmaskable".

11. **Interrupt vector address: concatenation or addition?** §4 says the device number forms the low 8 bits and SR[23:0] the upper 24 bits (concatenation). Figure 9 draws an adder. They are equivalent only because the table is 256-word aligned. Pick the concatenation wording for the spec.

## 2. Bugs in the example programs

These don't change the ISA, but they matter because examples are often read as the semantic reference, and they will be used as early test programs.

12. **Multiplication (§5.2) never terminates as intended.** The counter is cleared with `mov r6,r0` and then decremented with `mov<m> r6,--r6` until zero. Starting from 0 it loops 2³² times. It should be initialized to 32 (`mov r6,#32`).
13. **Multiplication adds the wrong register.** `add<m> r3,r3,r1` adds the shifted multiplier. The comment and the algorithm require the multiplicand low word, `r2`.
14. **Multiplication doesn't clear r5** (multiplicand high word), although the comment says "clear all used registers".
15. **Multiplication stores the wrong registers.** The result is in r4:r3 (per the comments), but it stores `r4` to `result_lo` and `r5` to `result_hi`. It should store r3 and r4.
16. **Interrupt example:** see items 2–4 above (wrong bit for I, wrong shift direction, clobbered flags).
17. **Self-replicating program (§5.4)** works under the post-increment-destination reading (see item 24), but the copy is not position independent: `#loop` and `#end` are absolute, so the copy jumps back into the original. That is fine as an example, but it is the only example that exercises a `Rx++` destination, so its semantics should be stated in the spec rather than inferred from it.

## 3. Gaps: things a complete ISA must define and the article doesn't

### 3.1 Instruction fetch, length and PC update
18. **How PC advances.** Not stated. Needed: after an instruction that does not write R15, PC ← PC + 1 + (number of constant words).
19. **Writes to R15.** Writing R15 is the only jump mechanism (`mov r15,#label`). The spec must say that a write to R15 replaces the normal PC advance, and what happens with R15 in `++`/`--` modes and as an indirect base.
20. **Skipped instructions still have length.** When the condition is false, the CPU must still decode all three operand modes to skip the right number of constant words. Also: are side effects (`++`/`--`) suppressed on a skipped instruction? (Presumably yes.)
21. **Value of R15 as a source and in `#c[R15]`.** The article says it is the address of the current instruction (and §5.4 `mov r1,r15` relies on that). The spec should state this for all modes, including that constant words do not move it.

### 3.2 Operand evaluation order and side effects
22. **Order of operand evaluation** is not defined. Footnote 3 implies s1, s2, destination for constants. It needs to be stated for side effects too: when is a `++`/`--` written back, and does a later operand see it? Example: `add r1, r1++, r1`, or `mov @r2++, @r2++`.
23. **Unused operand fields.** `move`, `not`, `dbl`, `dec` ignore s2; `one` ignores both sources. If an unused field contains a constant or `++`/`--` mode, is the constant word consumed, is the side effect applied, is memory read? The spec should either define it or require unused fields to be `000 0000` (R0 direct) and call anything else reserved.
24. **Destination `Rx++` / `Rx--` (register direct).** The article only explains the `--` case ("postdecremented"). Read literally: the result is written to Rx and then Rx is incremented/decremented, so Rx = result ± 1. §5.4 (`mov r2++,#end` meaning r2 = end+1) confirms that for `++`. It's an odd operation and should be spelled out, or the encodings repurposed.
25. **Destination mode 011 duplicates mode 111.** Both mean `@#c[Rx]`. That is one free encoding, useful for an extension, or it should be documented as an alias.
26. **R0 with side effects.** `R0++`, `--R0`, `@R0++`: the increment is presumably discarded, and `@R0` reads address 0. Should be stated.
27. **Writing R14 with the M bit set.** If the destination is R14 and `<m>` is given, which wins: the computed flags or the written value? Same for SHIFT ops with carry as a destination, which update C regardless of M.

### 3.3 Arithmetic and flag semantics
28. **Flag definitions per instruction class.** C and V are only described loosely ("carry of the last ALU/SHIFT instruction", "an overflow condition"). Needed for each of the 32 operations: how C, V, N, Z, X are computed, and which flags logic and shift ops leave unchanged, clear, or set.
29. **Carry out of `sub`/`dec`, and multi-word subtraction.** The carry-in rule is "add 1 if C is set", so `sub<c>` computes s1 − s2 + C. A high-word subtract needs s1 − s2 − borrow, which no value of C can produce under that rule. So either multi-word subtraction is done by negating and adding, or `sub` gets a different carry-in rule (the common one is s1 + ¬s2 + C, with C = 1 meaning "no borrow"). The meaning of C after `sub`/`dec` (borrow or not-borrow) is also undefined. This needs a deliberate decision.
30. **Two's complement and V.** The article never says signed numbers are two's complement, nor that V is signed overflow. N = MSB implies it.
31. **`one`: value 1 or all ones?** The table says `d = 1`, but it sits among bitwise logic functions, where the constant-true function is `$FFFFFFFF`. The X flag ("result was $FFFFFFFF") hints all-ones matters. Decide.
32. **`mdbl` (`d = s1 + (s1 ∧ s2)`)** is unusual and unexplained. It is either a deliberate "conditional double" (s2 = all ones gives 2·s1, s2 = 0 gives s1) or a typo. Confirm the intended function.
33. **`move` and `dec` with the C bit.** They are classed arithmetic, so `move<c>` gives s1 + C (an add-carry-to-zero) and `dec<c>` gives s1 − 1 + C. Plausibly intentional; state it, plus the flags they produce.
34. **C bit on logic instructions.** "Not affected", but is an encoding with C = 1 on a logic op valid (identical behaviour) or reserved?
35. **X flag** is listed but its use is never explained. Define when it is updated (presumably with Z and N when M = 1).

### 3.4 Shift instructions
36. **Shift count range.** s2 is a full 32-bit value and shifts are described as "after each step". The spec must define counts of 0 (is C touched?), ≥ 32, and whether only the low 5 (or 6) bits are used. An iterative hardware shifter with count up to 2³²−1 is not acceptable.
37. **Notation.** The convention is consistent but never stated: for left shifts `A<B` means "MSB goes to A, B is shifted in"; for right shifts `A>B` means "A is shifted in, LSB goes to B". The spec should say this outright.
38. **`C<<` / `>>C` vs. `C<C` / `C>C`.** The first pair is a 32-bit rotate that also copies the rotated-out bit to C. The second pair is a 33-bit rotate through carry. Fine, but the alternative names `bpl`/`bpr` are never explained.
39. **No arithmetic shift right** (fill with the sign bit). Signed division by powers of two needs a multi-instruction sequence. Consider whether to add it.
40. **Flags after shifts** with M = 1: N, Z, X from the result; V undefined; C when carry is not a destination: unchanged or cleared?

### 3.5 HALT and the encoding space
41. **HALT's lower 26 bits** are unspecified: must be zero, or don't-care? What does the assembler emit?
42. **No reserved or illegal opcodes.** All 7-bit opcode values are taken (16 ALU × C, 16 SHIFT, HALT). The article claims the deselect scheme makes extension easy, but every code is already assigned. The ISA needs to carve out extension space, most naturally inside HALT (bit25..21 ≠ 0), and say what an unimplemented opcode does (trap, NOP, or halt).
43. **Conditional HALT** is encodable. Presumably allowed; state it.
44. **Condition select mapping.** The mapping from the 3 select bits to SR bits 31..24 is not given. The natural choice is select n → SR bit 24 + n (so `111` = always). With that mapping the all-zero word tests I, not "always", which is still harmless for footnote 4's "zero is a NOP" because `move r0,r0` has no effect either way. Also `?!1` gives a "never" condition; document it.

### 3.6 Interrupts
45. **No automatic disable on entry.** Nothing says the CPU clears I when it takes an interrupt. If it doesn't, a second maskable interrupt arriving before the handler's `mov @r12++,r13` overwrites R13 and the first return address is lost. NMIs have this problem regardless of I. The spec must say what entry does to I (and probably provide an NMI-safe way out).
46. **SR is not saved by hardware**, but hardware modifies it on entry (sets M). The handler then saves an already-modified SR, so the pre-interrupt M is lost and restoring SR leaves M = 1 in the main program. Who clears M, and does an NMI clear it? Otherwise M can't distinguish the two interrupt types after the first maskable interrupt.
47. **Which address goes into R13**: the interrupted (not yet executed) instruction, or the next one? With "PC = current instruction", it should be the next instruction to execute. State it, and state that interrupts are only taken between instructions (never between the words of a multi-word instruction).
48. **Interaction with HALT.** The article says only reset restarts a halted CPU, yet the §5.3 main program ends in `halt` with interrupts enabled. Does an interrupt wake a halted CPU or not?
49. **Edge vs. level, priority, acknowledge timing.** IRQ/NMI are described as a high-to-low change (edge). Priority when both are pending, whether NMI also supplies a vector (§4 says both are "serviced the same way", so yes), and the "special control line" for vector availability are hardware-interface details, but the FPGA implementation will need them.
50. **No software interrupt / trap instruction**, and no defined vector for faults (there are none defined yet either).

### 3.7 System-level items never mentioned
51. **Reset state:** initial PC (the examples use `.org $0`), initial SR (I cleared? vector base?), register contents.
52. **Address space:** 32-bit word addresses are implied (PC is 32 bits) but never stated. Behaviour of accesses to non-existent memory is undefined.
53. **I/O:** no I/O instructions, so memory-mapped I/O is implied but not stated.
54. **No subroutine call or return.** A call can be built from two instructions (`mov @r12++,#3[r15]` then `mov r15,#sub`, with the right offset for the constant words) and return is `mov r15,@--r12`. That works but is easy to get wrong; the ISA document should define the idiom (or pseudo-instructions `call`/`ret`) and the stack convention (R12, growing upward, as the examples use).
55. **No signed compare conditions.** Conditions test one flag only, so signed `<`, `≤`, `>` (which need N ⊕ V, Z ∨ (N ⊕ V)) need multi-instruction sequences. Not a contradiction, but a known cost of the design.
56. **Self-modifying code and memory ordering** (writing the next instruction or a constant word): not addressed. Matters for a pipelined FPGA implementation.

### 3.8 Assembler syntax gaps
57. `#c` without `[Rx]` (e.g. `mov r15,#skip`) is used everywhere but never defined; presumably `#c[R0]`.
58. Number syntax: `$` = hex; is a bare number decimal? (see item 7.)
59. Encoding of unused operand fields and HALT's spare bits (items 23, 41).
60. `.dat #label` uses `#` inside a data directive, which is not explained; `.org`, `.equ`, `.ivtable`, `.reserve` and macros are mentioned but not specified.

---

## 4. Suggested defaults (for the ISA draft)

See [gap-resolution.md](gap-resolution.md) for which items QNICE resolves; it supersedes these defaults where they differ.

These are my recommendations where the article is silent or contradicts itself. They are not in the article.

- `iand` = `¬s1 ∧ s2`; `one` = `$FFFFFFFF`; confirm `mdbl` as written.
- SR bit 31 hard-wired to 1 and read-only; condition select n → SR bit 31 − n (superseded, see gap-resolution.md item 44).
- Correct the §5.3 example to `0>0 r14,#ivt,#8` and `or r14,r14,#$01000000` (and preserve the flags when setting the base).
- PC advances by 1 + number of constant words unless R15 is written; skipped instructions skip their constants and have no side effects.
- Operands evaluated s1, s2, destination; each side effect visible to later operands.
- Unused operand fields must be `000 0000`; HALT spare bits must be 0; any other HALT-space value is reserved and traps.
- Shift count: superseded by gap-resolution.md item 36 (QNICE semantics: full count, no modulo).
- Interrupt entry: R13 ← address of next instruction, clear I, set M for maskable / clear M for NMI, jump through the vector. Interrupts are only taken between instructions. Whether an interrupt wakes a halted CPU is your call; the article says it does not.
- Reset: PC = 0, SR = `$80000000` (only bit 31 set, interrupts disabled).
