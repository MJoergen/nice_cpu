# NICE web page, nice_can.pdf, and the 2004 emulator

These are the four files Michael uploaded on 2026-10-13:
- `The NICE Processor Pages.html`, dated 13-OCT-2004 on the page itself.
- `nice_can.pdf`.
- `nice_source.zip`, containing `NICE.pm` v0.4 and `nice_ide.pl`, written by B. Ulmann and T. Kratz in 2004.
- `examples.zip`, containing `count`, `replicate`, and `print`, each as `.asm` and `.bin`.

**Abbreviations used below:**
- **A1** is the 1997 article.
- **A2** is the 1999 article.
- **WEB** is the 2004 web page.
- **EMU** is the Perl emulator and assembler in `NICE.pm`.
- Item numbers refer to [gap-resolution.md](gap-resolution.md).

**How the emulator was checked.** I read the code, and I also ran it under Perl with Bit::Vector 7.4 on small probe programs. The probe scripts were not kept.

## Summary

- **nice_can.pdf** is a clean, typeset copy of A1. The text matches the scan on every page I compared (1, 2, 3, and 5), including the `iand` typo, `$0200`, `0<0`, and the multiplication bugs. Use it instead of the scan from now on. It resolves nothing new.
- **WEB and EMU are later than both articles and agree with each other.** EMU is the only executable reference, and both are by the author. They settle several open items: what R15 reads as, the `Rx++`/`Rx--` destinations, the duplicate destination mode, R0 behaviour, reset, and number syntax.
- **They also contradict the articles on the encoding.** The condition field and the SR flag order are laid out differently (§1). This is now the biggest open decision. The WEB/EMU layout happens to be the QNICE layout, so following Michael's QNICE rule picks it.
- **EMU is buggy.** Several of its operations do not do what its code clearly intends (§4). Treat it as evidence of *intent*, not as a bit-exact golden model.

---

## 1. New contradiction: condition field and SR layout

| | A1, A2 (articles) | WEB, EMU, and the `.bin` files |
|---|---|---|
| Condition field | bits 31..29 = select, bit 28 = negate | **bit 31 = negate**, bits 30..28 = select |
| SR bits 31..24 | `1 X C Z N V M I` (bit 31 = always-1) | `I M V N Z C X 1` (**bit 24 = always-1**) |
| Select n tests | the n-th flag counting from bit 31 | SR bit 24 + n |
| `?!Z` encodes as | `011` + `1` = `0111` | `1` + `011` = `1011` (WEB's worked example, verified bit for bit) |

Both layouts give the same *flag order* for select values 0–7: `1, X, C, Z, N, V, M, I`. They differ in two ways:
- where the negate bit sits in the instruction;
- which end of SR's top byte the flags occupy.

**Interrupt flag names.** A1 and A2 define M as "a maskable interrupt occurred" and I as "maskable interrupts enabled". WEB swaps the meanings: I (bit 31) means "an interrupt occurred" and M (bit 30) means "maskable interrupts are accepted only if set". So select 6 and select 7 mean different things in the two sources.

**QNICE uses the WEB/EMU layout.** In QNICE the negate bit sits above the three select bits, and the always-1 bit is the lowest flag with X, C, Z, N, V above it. EMU also reads the carry-in from bit 29, which is C's position in the *article* layout (bug 4.1). That suggests the layout was moved after the articles, and one reference was missed.

**Recommendation:** adopt the WEB/EMU layout. It is the later design, it matches the author's own toolchain and binaries, and it equals QNICE. The I/M naming still has to be settled together with the interrupt model.

## 2. Open items this resolves

| # | Item | Evidence | Resolution |
|---|---|---|---|
| 21 | Value of R15 when read | EMU `step()` increments PC past the instruction word *and all of its constant words* before reading any operand. Probe: `ADD R2, R15, 0x100` at address 1 gives 0x103. `print.nasm` builds a return address with `ADD @--SP 10 PC`, which is only right under this rule. | **Resolved:** R15 reads as the address of the next instruction. This agrees with A2 and QNICE and overrides A1. |
| 24 | `Rx++`/`Rx--` as a destination | WEB: "Rxx++ as a destination operand will write the result … into Rxx and increment Rxx afterwards". EMU `_write_op` does exactly that. Probe: `MOVE R1++, 7` gives R1 = 8. | **Resolved:** Rx = result ± 1. |
| 25 | Destination mode 011 = 111 | EMU `_write_op` handles both modes in one branch (`/3|7/`). | **Resolved: alias.** It stays available as extension space only if Michael wants it. |
| 26 | R0 with side effects | EMU zeroes R0 before and after every step. | **Resolved:** R0 reads 0, writes are discarded, and so are increments. |
| 22 | Evaluation order | EMU reads the destination (with no side effects), then s0, then s1. Source side effects are visible to the destination. Probe: `MOVE @R1, R1++` with R1 = 0x40 writes to 0x41. | **Confirmed** QNICE's rule. |
| 20 | Skipped instruction | EMU consumes the constant words, then tests the condition; a skipped instruction has no side effects (probe confirmed). | **Confirmed.** |
| 4, 51 | Always-1 bit; reset state | EMU forces SR bit 24 to 1 after every step. `init_registers` sets all registers to 0 and R14 = `0x01000000`. PC starts at 0. | **Confirmed.** |
| 30 | Definition of V | EMU uses Bit::Vector's signed overflow. Probe: `0x7FFFFFFF + 1` sets V. | **Textbook V confirmed.** QNICE's quirk is not inherited. |
| 29 | Carry for subtraction | EMU `SUB` calls `subtract(s0, s1, carry)`, which computes s0 − s1 − C, and C after a SUB is a borrow (probe: 3 − 5 sets C). | **QNICE semantics confirmed as the author's intent.** (The carry-in itself is read from the wrong bit; see 4.1.) |
| 41, 43 | HALT's spare bits; conditional HALT | WEB: the remaining bits "have no meaning and should be zero". A HALT whose condition holds stops the CPU. EMU emits zeros and tests the condition before halting. | **Resolved** for HALT itself. Extension space (item 42) was resolved later: ISA.md §5.3 makes the HALT encoding a control group with `HALT`, `RTI`, and `INT`, and every other command halts. |
| 53 | I/O | The IDE maps a character screen into main memory at 0x400 (80×25, character plus colour in one word). | **Memory-mapped I/O confirmed.** The address is an IDE convention, not an ISA rule. |
| 54 | Call/return | `print.nasm` uses **R13 as the stack pointer** (`SP .EQU R13`), growing down. It calls with `ADD @--SP 10 PC` then `MOVE PC PRINT`, and returns with `MOVE PC @SP++`. | **Supports QNICE's convention** of R13 as SP growing down. Note that WEB still calls R13 the interrupt return register. |
| 58, 57, 60 | Assembler syntax | EMU accepts hex as `0x…`, binary as `0b…`, and plain decimal. A **leading 0 means octal**, via Perl's `oct`. There is **no `#`**: a bare number or label is a constant, and `@const` is an absolute address. Flags are written `[M]`, `[C]`, or `[CM]`. Directives are `.ORG .EQU .DAT .BLK .ASCII_B .ASCII_L`. Comments start with `;` or `*`. Operands are separated by commas or whitespace. Missing operands default to `R0`, so unused fields are `000 0000` (item 59). | **Resolved for the toolchain.** This replaces the articles' `#`, `$`, and `<m>`. The leading-zero-octal rule is a trap and should be dropped. |

## 3. Where EMU or WEB contradict decisions already made

| # | Item | What EMU/WEB do | Comment |
|---|---|---|---|
| 7 | Order of constant words | EMU and the `.bin` files store them as **destination, s0, s1** (probe: `MOVE @0x40, 0x41` emits `0x40` then `0x41`). A1 footnote 3 says s1, s2, destination. | **Needs a decision.** Recommended: follow EMU (field order, destination first), because the existing binaries depend on it. |
| 27 | Writing R14 with M = 1 | EMU applies the flags *after* the write and keeps only bit 24, so the written value and the vector-table address are lost (probe: `MOVE[M] R14, 0x12` gives `0x01000000`). | This is a bug, not a design. Keep QNICE's rule: the explicit write wins. |
| 28 | Which flags each op writes | With M set, EMU rewrites all five of X, C, Z, N, and V, so logic ops **clear** C and V. QNICE leaves C and V unchanged on logic ops. | **Needs a decision.** EMU's behaviour is simpler in hardware. QNICE's is more useful. |
| 31 | `one` | WEB says "d = 1". EMU intends the value 1 (`value = '1'`), but the program crashes when it executes `ONE`. | **Reopened.** The author's tools say 1; the 74181 lineage says all ones. Michael decides. |
| 33 | `move`/`dec` with C | EMU's `MOVE` and `DEC` ignore the C bit. `MDBL`, `ADD`, `DBL`, and `SUB` honour it. | Simplest choice: only `mdbl`, `add`, `dbl`, and `sub` use carry-in. |
| 36 | Shift count | EMU *intends* count mod 32 (`& 0x1F`), except `0<0` and `0>0`, which use the full count. QNICE uses the full count everywhere. | **Needs a decision.** Mod 32 is cheaper in hardware. QNICE's choice is consistent. |
| 40 | Shifts that write C when M = 0 | WEB and A1 say C is written regardless of M. EMU only writes C when M is set (probe: `C<0` without M leaves C at 0). | EMU contradicts its own documentation, and A2's multiplication example needs the documented rule. **Keep the documented rule.** |
| 2 | I/M meanings | WEB swaps them relative to A1 and A2 (§1). | Settle together with the interrupt model (items 45–50). |

**Interrupts:** EMU implements none. It has only placeholder comments for M and I. Items 45–50 are unchanged.

## 4. EMU bugs (do not copy)

1. **The carry-in is read from SR bit 29** (`bit_test(29)`), which is V in EMU's own layout. C is bit 26. So `ADD[C]` and `SUB[C]` never use the carry (probe: `0xFFFFFFFF + 1` sets C, then `ADD[C] 10, 4` gives 14 rather than 15).
2. **Shift counts are masked with the number 0x1F.** Bit::Vector's `in=hex` overload parses the literal as hex `0x31`, so the mask is really `& 0x31` (probe: `1>0 …, 4` does not shift at all). Only shifts by 1 work, and those are the only shifts the examples use.
3. **Sources are aliased.** Shifts, `IAND`, and `IOR` modify the *source register* in place (probe: `0<0 R2, R1, 1` also doubles R1; `IAND` inverts R1).
4. **X is never set,** because the comparison with 0xFFFFFFFF suffers the same hex-overload problem (probe: `NOT[M]` of 0 gives N but no X).
5. **`ONE` crashes** the emulator, because it assigns a plain string where a vector is expected.
6. **`1>0` and `C>0` fill the wrong end:** they OR the mask into the low bits instead of the high bits.
7. **Writing flags with M = 1 wipes the vector-table address field** and the M and I bits (see item 27).
8. **`DEC[M]` reports a borrow in V** and clears C.

## 5. Errors in WEB itself

- "Bit 23 of R14 contains the fixed value 1". WEB's own table, and EMU, put it at bit 24.
- "Bit 27 (the M bit)". The table on the same page shows M at bit 25.
- "ADD R3, R2, R1 … write the result into register R1". The destination is R3, as WEB's own next examples show.
- "The @ sign denotes relative addressing". It means indirect addressing.
- WEB's I/M meanings contradict the articles (§1).

## 6. The example programs

- **`count.nasm`** sums 1..0x1000. It starts with `MOVE R14, R0` to clear SR, which relies on the always-1 bit surviving a write.
- **`replicate.nasm`** is A2's self-copy program in 2004 syntax.
- **`print.nasm`** writes a string to the memory-mapped screen, with R13 as the stack pointer and the PC-relative call idiom described above. It is the best existing evidence for the calling convention.
- **Use as tests:** the `.bin` files are real assembler output, and they decode consistently with the WEB/EMU layout. They make good first test vectors for the FPGA core, once the encoding decision is made.
