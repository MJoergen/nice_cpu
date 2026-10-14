# Second article: what it resolves and what it contradicts

**Source.** B. Ulmann, *Designing a NICE processor*, Microprocessors and Microsystems 23 (1999) 257–264. Michael uploaded it in the thread as `1-s2.0-S0141933199000216-main.pdf`.

**Names used below.**
- **A1** is the 1997 article (Computer Architecture News).
- **A2** is this 1999 article. It says it describes "the NICE architecture as it was published in Ref. [10]", meaning A1.
- Item numbers refer to [nice-article-review.md](nice-article-review.md) and [gap-resolution.md](gap-resolution.md).

**Overall.** A2 is mostly a design tutorial with a restatement of A1. It fixes several of A1's typos and example bugs, and it explains *why* the ALU table looks the way it does. It also contradicts A1 in some places that matter, most importantly on what R15 reads as.

---

## 1. Gaps A2 resolves

| # | Item | What A2 says | Effect |
|---|---|---|---|
| 1 | `iand` = `ior` | Table 5: `iand` d = ¬s1 ∧ s2 and `ior` d = ¬s1 ∨ s2. | **Resolved.** It matches the recommendation. |
| 31 | `one`: 1 or all ones? | Table 5 still says d = 1. But §3.3.1 says the ALU ops are "a subset of the … MSI ALU 74181". The 74181 logic function this corresponds to is "logic 1", which is all ones. | **Resolved by inference: `$FFFFFFFF`.** Every NICE logic op (`not`, `nor`, `iand`, `nand`, `xor`, `ior`, `xnor`, `and`, `one`, `or`) is one of the 74181's logic functions, so "1" is the bitwise constant. |
| 32 | `mdbl` formula | Same formula, s1 + (s1 ∧ s2). On the 74181 it is the arithmetic function "A plus AB". | **Resolved: deliberate, not a typo.** It is spelled `mdb1` in A2, which is a typesetting slip. |
| 8 | `move` vs `mov` | A2 uses `move` consistently. | **Confirmed** `move`, which agrees with QNICE. |
| 10 | R13 wording | "Whenever an interrupt occurs, the current address of the program counter is copied to this register." | **Confirmed:** R13 is written on every interrupt, maskable or not. |
| 12, 14, 15 | Multiplication example bugs | The counter is initialised (`move r6, #$20`), r5 is cleared, and r3/r4 are stored. | **Fixed** in A2. Item 13 is not fixed (see §2). |
| 51 | Reset state | "On startup of the machine, this register [PC] is reset to zero." | **Confirmed** PC = 0, which agrees with QNICE. SR and the other registers are still unspecified. |
| 54 | Call/return | A2 gives a calling idiom (`add @--r12, #2, pc` then `move pc, #sub`, with return `move pc, @r12++`). Its stack grows **downwards**: push with `@--r12`, pop with `@r12++`. | **Partly resolved.** The stack direction now agrees with QNICE. The stack pointer is still R12, where QNICE uses R13. The idiom only works if R15 reads as the next instruction (see item 21). |
| 60 | Assembler directives | Defines `.org`, `.equ`, `.dat`, and `.reserve`; the label/condition/instruction/operand fields; `;` comments; and `?[!]bit` conditions. "When no condition is specified, the 1 bit … is used." | **Partly resolved.** |
| 35 | Purpose of X | X is "Set to 1 if the result … was $FFFFFFFF (this bit can be used in comparisons like a ≠ b)". | **The purpose is explained, but update timing is still open.** `xnor` yields all ones exactly when a = b, so X acts as an equality flag after `xnor`. The "≠" in A2 should read "=", or should mean "test !x". |

### Insight: the 74181 explains the carry rule (item 29)

A1's rule is "result + 1 if C". That is the 74181 convention, where every arithmetic function is "F plus carry-in". On a real 74181, subtraction is "A minus B minus 1" plus carry-in. That gives the ARM-style rule: subtract-with-carry is s1 − s2 − 1 + C, where C = 1 means *no* borrow. Multi-word subtraction works under that rule. It does not work under A1's literal wording, s1 − s2 + C.

That leaves two consistent choices for item 29:
- **QNICE:** s1 − s2 − C, where C = 1 means a borrow occurred. This is the current recommendation, following the "same semantics as QNICE" rule.
- **74181/ARM:** s1 − s2 − 1 + C, where C = 1 means no borrow. This is the one closer to the author's hardware.

A2 also drops A1's explicit "+1" wording. It says only "uses the current value of the carry". Either choice therefore fits A2.

---

## 2. Contradictions A2 introduces, or bugs it keeps

### Contradictions with A1 that matter

1. **What R15 reads as (item 21).** A1 says "the PC points to the actual instruction location during the whole execution cycle". A2 says the opposite:
   - §3.1.1: R15's "contents are used as the address of the **next** instruction to be fetched".
   - §4.3: "When the processor reaches the add instruction, the program counter points to the memory location of the next instruction".

   A2's subroutine idiom `add @--r12, #2, pc` depends on that. With PC = the word after the 2-word `add`, PC + 2 skips the 2-word `move pc, #sub`. A2 has also rewritten the self-replicating program to use `move r1, #start` instead of A1's `mov r1, r15`. So no A2 example depends on A1's rule any more.

   **Effect:** this item is now contested. A2 and QNICE agree, so I'm changing the recommendation to "R15 reads as the address of the next instruction, after all of the current instruction's constant words".
2. **The `dbl` operand.** A1 has d = 2·s1. A2 has d = 2·**s2**. The 74181 function is "A plus A", so **A1 is right and A2 is the typo.**
3. **Stack direction.** A1's examples push with `@r12++` and pop with `@--r12`, so the stack grows up. A2 pushes with `@--r12` and pops with `@r12++`, so it grows down. A2 agrees with QNICE. It is a convention, not an ISA rule, but the ISA document should pick one.
4. **Return from interrupt.** A2's handler ends with `move pc++, @r12++`. Its destination is `pc++`, and register-direct `++` as a destination means R15 = saved value + 1 (item 24). Under either PC rule, that resumes one word *after* the saved address and skips an instruction word. A1 returns with plain `mov r15, @--r12`. **This is probably a typo in A2.** If it isn't, it means IR holds the address of the last executed word, which would be wrong for multi-word instructions. Treat it as an error. It does not change items 24 or 47.
5. **The M bit and shifts that write C (item 40).** A1 says a shift that writes C modifies C "regardless of the state of the M-bit". A2 says only that the M bit "permits modification of the status bits … only if it is set", with no exception. Yet A2's own multiplication example needs A1's exception: `c<0 r2, r2, #1` has no `<m>`, and the following `0<c r5, r5, #1` consumes its carry. **A1's rule stands.**

### Bugs A2 keeps or adds

6. **Interrupt enable is still the wrong bit (item 2).** A2 enables interrupts with `or sr, sr, #$0100`, which is bit 8. A1 used `$0200` (bit 9). Both figures put I at bit 24 (`$01000000`). The two articles disagree with each other *and* with the figure.
7. **The IVT base is still shifted left (item 3).** It is still `0<0 sr, #ivt, #8`. It should be a right shift.
8. **Multiplication still adds the wrong register (item 13).** It still has `add<m> r3, r3, r1`, which should be `r2`.
9. **The stack pointer starts in the wrong place (new).** A2's stack grows down, but it initialises `r12` to `start_stack`, a label at the *start* of the `.reserve $1000` block. The first push therefore writes just below the block, over whatever precedes it (the IVT in the listing). The label should go at the end of the block. This happened because the stack direction changed without the label moving.
10. **`#` dropped from constants (new).** A1 says a constant always needs a leading `#`. A2 writes `?z move pc, $1234` (§3.2) and, in the design discussion, `move $1234, @r1--` (§2.3). The second example also:
    - puts the source first, the opposite of NICE's destination-first order;
    - uses `@r1--`, post-decrement indirect, which is not one of the eight addressing modes.

    It reads as PDP-11 syntax left over from the design discussion. The ISA document should not take anything from §2.3's example.
11. **Assembler inconsistencies (new).** The multiplication example uses `org $0` without the dot. `start_copy.equ #$1234` puts `#` inside the `.equ`, and the label is then used again as `#start_copy`, which leaves it unclear whether the `#` belongs to the value or to the use.
12. **The fixed-length claim is repeated (item 5).** §2.2 says "each instruction occupies one machine word of 32 bits". Two paragraphs later, §2.5 says "up to three following memory cells are occupied" by constants. The same contradiction as A1.

### Intent that affects an open decision

13. **Nested interrupts (items 45 and 46).** A2 says copying the PC to `ir` lets the routine "save the proper return address on a stack structure to allow handling of nested interrupt requests". So the author intended software-managed nesting. Taking QNICE's no-nesting model is a conscious departure from that intent, not a gap fill. A2 adds nothing about disabling I or clearing M on entry, so the race from item 45 is still there. The recommendation stays the same, but the departure should be stated in the ISA document.

---

## 3. Unchanged by A2

These items are the same in both articles, so their status in gap-resolution.md does not change:
- Instruction format, deselect bits, operand modes (Table 1 is identical) and SR layout.
- The 8-bit vector scheme, with the Fig. 7 adder.
- HALT format and extension space.
- Shift table.
- Condition select mapping.
- Unused operand fields.
- R0, R14, NMI handshake, I/O, and self-modifying code.
- The open items 24, 25, 26, 34, 38, and 58.

`bpl`/`bpr` are still not explained.
