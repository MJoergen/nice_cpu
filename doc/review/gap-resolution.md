# NICE gaps: which ones QNICE resolves

This file goes through the 60 items in [nice-article-review.md](nice-article-review.md) and checks each one against QNICE, as implemented in `MJoergen/qnice_cpu`. The rule is to use the same semantics as QNICE wherever QNICE has an answer that applies.

**Sources checked.** All of these follow the ISA as it is pinned in qnice_cpu, which is QNICE-FPGA `develop` at commit `b1fb36c`:

- `doc/intro/qnice_intro.tex`, the ISA slides.
- `emulator/qnice.c`, the reference emulator.
- `vhdl/alu.vhd`, the upstream ALU.
- The qnice_cpu RTL: `src/cpu_main/sub/alu_data.vhd`, `alu_flags.vhd`, and `write.vhd`.
- The qnice_cpu docs: `doc/README.md`, `doc/interrupts.md`, and `test/prog_r15.asm`.

## Summary

| Status | Count | Meaning |
|---|---|---|
| **QNICE** | 18 | QNICE answers the question directly. Use the same semantics. |
| **Article** | 21 | The author's own sources already give the answer: the 1997 or 1999 article, the 2004 web page (WEB) or the 2004 emulator (EMU). It needs an editorial fix (a typo or a broken example), not a design decision. |
| **Partial** | 18 | QNICE sets a precedent, but NICE differs enough that adopting it needs a decision. Most of these are interrupts and calls. |
| **Open** | 3 | QNICE has nothing equivalent. Michael decides. |

*Updated after the 1999 article* ([second-article-review.md](second-article-review.md)). That article resolves items 1, 31, and 32, which move to Article. It contradicts the 1997 article on item 21, which moves to Partial. It also confirms or refines items 8, 10, 29, 35, 51, 54, and 60.

*Updated after the 2004 web page and emulator* ([emulator-and-webpage-review.md](emulator-and-webpage-review.md)). They resolve items 21, 24, 25, 26, and 58, which move to Article. They reopen item 31 (they say `one` = 1). They contradict the articles on the condition-field and SR layout, so item 44 moves to Partial. They also bear on items 2, 4, 7, 22, 27, 28, 29, 30, 33, 36, 40, 41, 51, 53, 54, and 60; see the "2004:" notes in those rows.

### The decisions that matter most

1. **Interrupt model (items 45, 46, 54, 49, 50).** QNICE handles interrupts this way:
   - Hardware saves SR and PC into hidden latches.
   - A busy flag stops interrupts from nesting.
   - Software returns with `RTI`.
   - A rogue `RTI` or `INT` halts the CPU.

   The article's model saves only the return address, in R13, and has no RTI. Adopting QNICE's model fixes four gaps at once: the R13 clobber race, the lost M bit, the unsafe return, and the missing software interrupt. It also frees R13, which could then become the stack pointer as it is in QNICE. The cost is that the article's R13 = IR model changes, and new instructions (`RTI`, `INT`) need room in the HALT space. **Recommended: adopt it.**
2. **Extension space (items 41, 42, 59).** Do what QNICE does with opcode `E`: turn the HALT encoding into a control group, with HALT as command 0 followed by RTI, INT, and so on. Unknown commands halt. **Recommended.**
3. **Overflow flag on subtract (item 30).** QNICE computes V for SUB with the add formula, which is not textbook signed overflow. The emulator keeps this under `OLD_V_LOGIC` and admits it is "not by the book", and qnice_cpu copies it. **Recommended: do not inherit this; use textbook V.**
4. **The 3 open items.** They are small: `one` = 1 or all ones (31), the C bit on logic ops (34), and the `bpl`/`bpr` names (38). **Resolved** in ISA.md: `ONE` gives 1 (§5.1), every ALU operation other than `SUB`, `MDBL`, `ADD`, and `DBL` ignores the instruction's C bit (§5.1), and `BPL` and `BPR` are aliases of `C<<` and `>>C` (§5.2).
5. **What R15 reads as (item 21).** Settled: the 1999 article, the 2004 emulator, and QNICE all say R15 reads as the next instruction.
6. **Condition-field and SR layout (items 44, 2, 4, 51).** The articles put select in bits 31..29, negate in bit 28, and the always-1 bit at SR bit 31. WEB and EMU put negate in bit 31, select in bits 30..28, and SR bits 31..24 = `I M V N Z C X 1`, so select n tests SR bit 24 + n. That is the QNICE layout. **Recommended: adopt the WEB/EMU layout.**
7. **Order of constant words (item 7).** The 1997 article says s1, s2, destination. EMU and its binaries use destination, s0, s1. **Recommended: follow EMU.**
8. **Flag-write policy and shift count (items 28, 36).** EMU rewrites all flags when M is set and masks shift counts to 5 bits. QNICE leaves C and V alone on logic ops and uses the full count. Michael decides.

### Where the article and QNICE disagree, and the article wins

- **What R15 reads as.** *Superseded.* The 1999 article sides with QNICE (R15 reads as the next instruction), against the 1997 article. See item 21.
- **Carry-in on subtraction.** The article says "add 1 if C" for every arithmetic op. QNICE's `SUBC` subtracts C. Item 29 adopts QNICE, so this is a deliberate change to the article.

---

## Item by item

Item numbers match the review file.

### 1. Contradictions and errors

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 1 | `iand` = `ior` | Article | Resolved by the 1999 article (Table 5): `iand` = ¬s1 ∧ s2. |
| 2 | I flag set via bit 9 | Article | Fig. 1 wins (I = bit 24). Fix the example to `$01000000`. QNICE has no I flag in SR; it masks interrupts in an external device. 2004: WEB swaps the meanings (I = interrupt occurred, M = interrupts enabled) and, in its layout, I is bit 31. Settle with the interrupt model. |
| 3 | IVT base shifted left | Article | Use `0>0` (shift right), as footnote 5 and §4 require. |
| 4 | Bit 31 can be cleared | **QNICE** | The always-1 bit is hard-wired. Writes cannot clear it and reads return 1. Sources: emulator `read_register` (`| 1` for SR), `alu_flags.vhd` (`sr_i or X"0001"`), and the reset value `X"0001"`. 2004: EMU forces the always-1 bit to 1 after every step, but at SR bit 24 (WEB/EMU layout, item 44). |
| 5 | "Fixed length" vs. trailing constants | **QNICE** | QNICE immediates are extra words fetched through `@R15++`, so a QNICE instruction is 1–3 words. Document NICE instructions as 1–4 words. |
| 6 | R15 in `++`/`--` and indirect modes | Partial | QNICE treats R15 as an ordinary register in every mode, and any write to it is a jump. Adopting that means that, for example, a source `R15++` writes R15, so it is a jump. Decide whether to allow this or reserve it. Recommended: allow it, and let the last write to R15 win. |
| 7 | Constant order; `10` vs `$10` | Partial | Order: source 1, source 2, destination (footnote 3). This matches QNICE's source-then-destination order (item 22). Number syntax is still open (item 58). 2004: EMU and its `.bin` files store the constants as destination, s0, s1. Recommended: follow EMU, since the existing binaries depend on it. |
| 8 | `move` vs `mov` | **QNICE** | QNICE's mnemonic is `MOVE`. Make that canonical. Allowing `mov` as an assembler alias is optional. |
| 9 | "Sixteen GPRs" | Article | Editorial. QNICE's own wording is the model: 16 registers, some with special roles. |
| 10 | R13 "non masked" wording | Article | Editorial, but item 45 may remove R13's special role altogether. |
| 11 | IVT address: concatenation vs. adder | Article | Specify concatenation. The two are equivalent because the table is 256-aligned. |

### 2. Example bugs

| # | Item | Status | Resolution |
|---|---|---|---|
| 12–15 | Multiply: counter, wrong add register, r5 not cleared, wrong stores | Article | Fix the examples. Afterwards they can become the first test programs, as `test/*.asm` are in qnice_cpu. |
| 16 | Interrupt example | Article | See items 2–4. |
| 17 | Self-replicating program | Article | Its behaviour is correct. Use it to state the `Rx++` destination semantics (item 24). |

### 3.1 Fetch, length, and PC

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 18 | How PC advances | **QNICE** | PC advances past every word the instruction consumes. NICE: PC ← PC + 1 + (number of constant words). |
| 19 | Writes to R15 | **QNICE** | Any write to R15 is a jump and replaces the normal advance (`prog_r15.asm` T3; `write.vhd` redirects on any R15 write). |
| 20 | Skipped instructions | **QNICE** | When a QNICE branch is not taken, its immediate word is still consumed but the other register side effects are suppressed (emulator, branch arm: "We must always increment when it is the PC register"). NICE: a skipped instruction skips its constant words and has no other effect. |
| 21 | Value of R15 when read | Article | Resolved by the 2004 emulator: R15 reads as the address after the current instruction and all its constant words, as in the 1999 article and QNICE. `print.nasm` relies on it (`ADD @--SP 10 PC`). This overrides the 1997 article. |

### 3.2 Operand evaluation

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 22 | Evaluation order and side effects | **QNICE** | Operands are evaluated in order: source, then destination. Each side effect is visible to the operands evaluated after it. The emulator does this and qnice_cpu follows it (`prog_r15.asm` header). NICE order: s1, s2, destination. 2004: EMU confirms this. It reads the destination address first but applies its side effect only at the write, so source side effects are visible to the destination. |
| 23 | Unused operand fields | Partial | In QNICE, control instructions with no operands ignore their operand fields entirely: no reads, no side effects, no immediate words (`write.vhd`, "DECODE classifies every CTRL instruction as no source operand, no destination operand"). Recommended for NICE: ignore unused fields the same way, with the assembler emitting `000 0000`. |
| 24 | `Rx++`/`Rx--` as destination | Article | Resolved by WEB and EMU: the result is written to Rx, then Rx is incremented or decremented, so Rx = result ± 1. |
| 25 | Destination mode 011 = 111 | Article | Resolved by EMU: destination modes 011 and 111 are aliases. Reserve 011 only if an extension needs it. |
| 26 | R0 with side effects | Article | Resolved by EMU: R0 reads 0, and writes and increments are discarded. `@R0` addresses word 0. |
| 27 | R14 written while M = 1 | **QNICE** | The explicit write wins over the flag update. The emulator updates flags before `write_destination`, and qnice_cpu's `registers.vhd` "resolves its two write ports in favour of the ordinary one". 2004: EMU lets the flag update overwrite the explicit write. That is a bug, not a design; keep this rule. |

### 3.3 Arithmetic and flags

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 28 | Flags for each operation | Partial | QNICE's pattern (intro slides "Affected condition bits", `alu_flags.vhd`): add/sub write V, N, Z, C; MOVE, NOT, and the logic ops write only N and Z, leaving C and V unchanged; shifts write N, Z, and the shifted-out bit, leaving V unchanged. Map NICE's extra ops onto this pattern: `dbl`, `mdbl`, and `dec` count as arithmetic; `one`, `nor`, `nand`, `xnor`, and `iand` count as logic. 2004: with M set, EMU rewrites all of X, C, Z, N, and V, so logic ops clear C and V. Michael decides between that and QNICE's pattern. |
| 29 | Carry for sub/dec, multi-word subtraction | **QNICE** | `SUBC` computes dst − src − C, and C = 1 means an unsigned borrow (`alu_data.vhd`: addend `not src`, carry-in `not C`; emulator `source_0 - source_1 - C`). NICE: the C bit **adds** C for `move`, `mdbl`, `add`, and `dbl`, and **subtracts** C for `sub` and `dec`. This changes the article's "+1 if carry" rule for sub/dec. 2004: EMU computes s0 − s1 − C with C as borrow, confirming this as the author's intent (its carry-in is read from the wrong bit). |
| 30 | Two's complement, definition of V | Partial | QNICE: two's complement, with V meaning signed overflow on add/sub. Its SUB V uses the add formula, which is wrong for subtraction (emulator `OLD_V_LOGIC`; `alu_flags.vhd` copies it). Recommended: textbook V for NICE. 2004: EMU uses textbook signed overflow, confirming the recommendation. |
| 31 | `one` = 1 or all ones | **Open** | Contested. The 1999 article's 74181 lineage implies all ones (`$FFFFFFFF`). WEB says "d = 1", and EMU intends 1 (but crashes on it). Michael decides. |
| 32 | `mdbl` formula | Article | Resolved by the 1999 article: it is the 74181's "A plus AB", so s1 + (s1 ∧ s2) is deliberate. (`dbl` = 2·s1. The 1999 article's 2·s2 is a typo.) |
| 33 | `move`/`dec` with the C bit | Partial | Follows item 29: `move<c>` = s1 + C and `dec<c>` = s1 − 1 − C. 2004: EMU's `MOVE` and `DEC` ignore the C bit. The simpler choice is to follow EMU. |
| 34 | C bit on logic ops | **Open** | Either the C bit is ignored (identical behaviour) or the encoding is reserved. Recommended: ignored. |
| 35 | When X is updated | Partial | QNICE's X means something different (it is the bit shifted out on the right), so it gives no direct answer. Following the item 28 pattern, X is written whenever Z and N are written. |

### 3.4 Shifts

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 36 | Shift count range | **QNICE** | The full count is used, with no modulo. A count of 0 changes nothing, not even C. A count ≥ the word width gives a result made entirely of fill bits. At exactly the width, the carry is the last bit shifted out. Above the width, the carry is the fill bit (`alu_data.vhd`, `p_shift_left`/`p_shift_right`). For NICE the width is 32. *This replaces the "mod 32" default in the review.* 2004: EMU intends count mod 32 (except `0<0`, `0>0`). Michael decides between that and QNICE's full count. |
| 37 | Notation | Article | Editorial: state that `A<B` means the MSB goes to A and B fills in, and `A>B` means A fills in and the LSB goes to B. |
| 38 | `bpl`/`bpr` names | **Open** | Cosmetic. Keep or drop them. |
| 39 | No arithmetic shift right | **QNICE** | QNICE has no ASR either. It gets the same effect by setting C to the sign bit and shifting right with C as the fill. NICE can do the same in two instructions: `C<0 r0,rX,#1` (C ← sign bit), then `C>0 rX,rX,#n`. No new opcode is needed. |
| 40 | Flags after shifts | **QNICE** | N and Z come from the result and V is unchanged. The shifted-out bit goes to its named destination: C, or nowhere for `0<0`. If C is not the destination it is unchanged. 2004: EMU writes C only when M is set, contradicting WEB and the 1997 article. Keep the documented rule. |

### 3.5 HALT and the encoding space

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 41 | HALT's spare 26 bits | Partial | QNICE's opcode `E` is a control group: `HALT` is command 0 (`0xE000`), followed by RTI, INT, INCRB, and DECRB. Recommended: split the NICE HALT space into command and operand fields the same way. 2004: WEB says the spare bits "have no meaning and should be zero", and a HALT whose condition holds stops the CPU. The control-group idea is still open. |
| 42 | No reserved opcodes or illegal-opcode trap | Partial | QNICE precedent: there is a reserved opcode (`D`), and a reserved or unknown command halts the CPU (emulator: "Attempt to execute a reserved instruction", return 1; upstream VHDL: "illegal command: HALT"; qnice_cpu traps it in simulation). Recommended: unknown control commands halt. |
| 43 | Conditional HALT | Article | Fig. 8 includes the condition field, so HALT is conditional. QNICE control instructions are not conditional, so this is a NICE extra. |
| 44 | Mapping of the condition select bits | Partial | QNICE: select n tests SR bit n counting from the always-1 bit, so 000 = always, 001 = X, 010 = C, 011 = Z, 100 = N, 101 = V (intro example `ABRA LOOP, !Z` = `0xFF8B`). For NICE that is select n → SR bit 31 − n, so 110 = M and 111 = I, and the first six flags are in exactly QNICE's order. The all-zero word is then an unconditional `move r0,r0`, which matches footnote 4's "zero is a NOP". *This replaces the "24 + n" default in the review.* 2004: WEB and EMU use a different layout from the articles: negate in bit 31, select in bits 30..28, SR bits 31..24 = `I M V N Z C X 1`, and select n tests SR bit 24 + n. That is exactly QNICE's layout. Recommended: adopt it, which turns "SR bit 31 − n" above into "SR bit 24 + n". |

### 3.6 Interrupts

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 45 | No disable on entry (R13 clobbered) | Partial | QNICE: interrupts do not nest. An internal in-service flag refuses new requests until `RTI` (intro slides, `write.vhd` `irq_active`). Adopting this requires an `RTI` instruction (see item 41). See decision 1. |
| 46 | SR not saved, M lost | Partial | QNICE: hardware saves SR and PC into hidden latches and `RTI` restores both. qnice_cpu saves only R14 and R15, per the ISA slides; the upstream VHDL and emulator save R8–R15. Adopting this replaces the R13 = IR model. |
| 47 | Return address | **QNICE** | The saved address is where execution would have continued: the next instruction, or the target if the instruction was a taken branch. Interrupts are taken only between instructions (`doc/README.md`, "What a program sees"). |
| 48 | Interrupt vs. HALT | **QNICE** | qnice_cpu: HALT wins, and a halted CPU stays halted. This matches the article's "only reset restarts". (Upstream's FSM does the opposite; qnice_cpu chose this deliberately.) |
| 49 | Edge/level, priority, acknowledge | Partial | qnice_cpu: a valid/ready handshake with the ISR address on its own port; one device; a request may be withdrawn; the interrupted program is guaranteed progress. NICE differs in two ways: it sends an 8-bit vector number rather than an address, and it has an NMI, which QNICE does not. NMI priority and NMI nesting need a decision. |
| 50 | Software interrupt | **QNICE** | Add `INT`. A rogue `INT` (inside an ISR) and a rogue `RTI` (outside one) both halt, matching the emulator, upstream, and qnice_cpu. For NICE, `INT` takes a vector number. |

### 3.7 System level

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 51 | Reset state | **QNICE** | PC = 0, all registers 0, SR = only the always-1 bit (so interrupts are disabled). Sources: emulator `reset_machine`, qnice_cpu `f_sr_reset_priority`. NICE: SR = `$80000000`. 2004: EMU resets all registers to 0 and SR to `0x01000000`, the same state in the WEB/EMU layout (item 44). |
| 52 | Address space; accesses to non-existent memory | Partial | The article settles the 32-bit word addressing. QNICE leaves non-existent memory undefined too. Recommended: undefined, or reads return 0. |
| 53 | I/O | **QNICE** | Memory-mapped I/O, with the top 256 words reserved for I/O. NICE: `$FFFFFF00`–`$FFFFFFFF`. 2004: the IDE maps an 80×25 screen into memory at 0x400, confirming memory-mapped I/O. The address is an IDE convention. |
| 54 | No call/return | Partial | QNICE: `ASUB`/`RSUB` push PC onto `@--R13` (the stack grows down) and `MOVE @R13++, R15` returns. NICE has no opcode space for a call. If item 45 frees R13, adopt QNICE's convention (R13 = SP, growing down) and define `call`/`ret` macros. The article's examples use R12 growing up. 2004: `print.nasm` uses R13 as SP growing down, calls with `ADD @--SP 10 PC` + `MOVE PC target`, and returns with `MOVE PC @SP++`. This supports QNICE's convention. |
| 55 | No signed compare conditions | Partial | QNICE's `CMP` sets N to unsigned greater-than and V to signed greater-than, so a single flag test can express a signed compare. NICE could add a `cmp` in the control group, or live with `sub<m>` plus multi-instruction tests. |
| 56 | Self-modifying code | **QNICE** | Fully supported, with no latency requirement. A store may rewrite the instruction immediately after it (qnice_cpu, "Self-modifying code"). |

### 3.8 Assembler

| # | Item | Status | Resolution and source |
|---|---|---|---|
| 57 | `#c` without `[Rx]` | Article | Means `#c[R0]`. Editorial. |
| 58 | Bare numbers: decimal or hex? | Article | Resolved by EMU's assembler: `0x` hex, `0b` binary, bare numbers decimal, no `#` (a bare number is a constant, `@n` an absolute address). Drop EMU's leading-zero-means-octal rule. |
| 59 | Encoding of unused fields | Partial | Follows items 23 and 41: emit zeros. |
| 60 | Directives | Partial | QNICE's `qasm` (`.ORG`, `.EQU`, `.BLOCK`, `.DW`, ...) is the precedent. Specify NICE's assembler directives when the assembler is written. 2004: EMU's directives are `.ORG .EQU .DAT .BLK .ASCII_B .ASCII_L`. Use them as the starting set. |
