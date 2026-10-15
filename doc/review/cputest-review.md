# Review of cputest, the self-checking instruction set test

Reviewed on 2026-10-14: `emulator/test/cputest.nasm` at commit 821168a ("niceemu: add cputest, a self-checking test of the instruction set"), against `doc/ISA.md` §1 to §8.

**Status after commit f711ca8** ("niceemu: fix the findings of the cputest review"), checked the same day: every item in sections 1 to 4 is fixed. Section 6 is the second round against the new program.

**How it was checked.** I derived the result and the SR word of each of the 108 checks by hand from ISA.md and compared them with the values the program tests for, decoded the five hand-encoded `.DAT` words and word 0, and confirmed that `make test` passes. Then I ran the program with `--trace` and mapped every executed address back to its source line through the assembler: which lines ran, how often, and which were skipped. Finally I wrote the checks proposed below as a separate program, assembled it with `niceasm`, and ran it, so every expected value quoted here has been run on the emulator.

## Summary

**The test is correct.** Every one of the 108 expected values and flag words agrees with ISA.md. The claims in the header hold: the seven "never runs" lines never run, no other line in the body runs twice, the only skipped instructions are the `?!Z HALT` lines and the twenty-six intended skips in checks 98 to 102 and 106, and the 855 body lines plus the subroutine and four runs of the interrupt routine give exactly the 869 steps in the `.expected` file.

The findings are gaps: rules that ISA.md states and that no check pins down. A core could break each of them and still halt with R11 = `0x600D`.

- The checking method itself has a hole: nothing shows that a conditional `HALT` with a true condition runs (§1).
- Eight rules have no check: I, E, and VBASE surviving a flag update; the carry input timing for shifts; V cleared by a shift; R15 in the memory modes; `@--R0` and `@R0++`; the carry input taking part in the carry out; flags with a memory destination; and the full width of the `INT` vector (§2).
- Four smaller gaps, and one place where a failure is detected only by accident (§3).
- The header should say that no IRQ may be raised while the test runs (§4).

Section 5 lists what was checked and found right, so that a later round need not repeat it.

## 1. The checking method

Every check ends in `?!Z HALT`. Check 1 shows that `?!Z MOVE` runs when Z = 0, check 102 shows that `?!1 HALT` is skipped, and check 106 shows that `?Z INT` runs when Z = 1. None of these shows that a conditional `HALT` runs when its condition is true. A core that skipped every conditional control instruction, or every conditional `HALT`, would pass all 108 checks silently.

The program cannot test this in the middle, because the `HALT` would stop it. It can test it at the end, by making the final halt the same instruction that every check relies on:

```
pass    ...
        MOVE    R11, 0x600D
        MOVE    R14, 0
?!Z     HALT                    ; Z = 0: the HALT every check relies on
        MOVE    R11, 0          ; never runs
        HALT
```

If the conditional `HALT` is wrongly skipped, the program halts with R11 = 0. The final register state is unchanged, so only the PC in the `.expected` file moves.

## 2. Rules with no check

Each item gives the rule, why the present checks miss it, and a check that covers it. The checks were run as written.

### 2.1 I, E, and VBASE survive a flag update (§1.3)

"Instructions with the M bit set update only X, C, Z, N, and V." Every check that uses M starts from an SR with I, E, and VBASE clear, so a core that cleared all of R14's upper byte, or all of VBASE, on a flag update would pass. VBASE happens to be covered indirectly, because check 104's compare runs with VBASE = `0x0F` and check 105's `INT` would then jump through the wrong table, but nothing covers I and E.

```
        MOVE    R14, 0xC0FFFFFF ; I, E, and every VBASE bit
        ADD[M]  R1, 1, 1
        MOVE    R10, R14
        SUB[M]  R0, R10, 0xC1FFFFFF
?!Z     HALT
```

### 2.2 The carry input to a shift is C as step 5 left it (§5.2)

Check 37 tests the timing for `ADD[C]`. §5.2 states the same rule for the shifts, with its own wording, and a core could well read C at a different point for its shifter. The same construction works:

```
        MOVE    R14, 0x03FFFFFF ; C = 0
        0<C     R1, R14++, 1    ; R14++ carries into C, so the fill is 1
        SUB[M]  R0, R1, 0x07FFFFFF
?!Z     HALT
```

A core that reads C before the source operands gives `0x07FFFFFE`.

### 2.3 A shift with M clears V (§5.2)

"With M = 1, V = 0 after any shift." Every shift check starts from SR = 0 or SR = C only, so none of them can show V being cleared, and none shows a shift clearing N, Z, or X either. The ALU checks 3 to 13 start from `0x3E000000` for exactly this reason. Starting check 48 from the same value covers all four flags at no cost:

```
        MOVE    R14, 0x3E000000
        SHR[M]  R1, R2, 1       ; R2 = 0xC0000001
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x60000000
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT
```

### 2.4 R15 in the memory modes (§4.3)

Checks 91 to 94 read and write R15 in modes 000 and 010 only. "R15 read as an operand gives the address of the next instruction, after all of this instruction's constant words" also applies to `@R15++` and `@c[R15]`, and those are the modes a pipelined core is most likely to get wrong, because the address must be formed after the constant fetch. `@R15++` is the classic inline-constant idiom, and `@c[R15]` is PC-relative data.

```
        MOVE    R1, @R15++      ; reads the next word and skips it
        .DAT    0x1234          ; never runs: data
        SUB[M]  R0, R1, 0x1234
?!Z     HALT

        MOVE    R1, @1[R15]     ; the constant word of the SUB below
        SUB[M]  R0, R1, 0x5678
?!Z     HALT
```

### 2.5 `@--R0` and `@R0++` address word 0 (§4.3)

Check 79 reads `@R0`, and check 90 shows that `--R0` and `R0++` read 0 as values. Nothing reads through `@--R0` or `@R0++`. Appendix B records that the 2004 emulator read −1 for `--R0` within an instruction. A core with that bug reads address `0xFFFFFFFF`, which is in the I/O range, and the value it gets back depends on the device there.

```
        SUB[M]  R0, @--R0, 0x0003D800
?!Z     HALT
        SUB[M]  R0, @R0++, 0x0003D800
?!Z     HALT
```

### 2.6 The carry input takes part in the carry out (§5.1)

Checks 19, 25, 28, and 30 use the carry input, but only check 30 produces a carry out, and there the carry comes from the doubling, not from cin. A core that adds cin after computing the carry out, which is a common mistake in a two-stage adder, passes. Two checks close this:

```
        MOVE    R14, 0x04000000
        ADD[CM] R1, 0xFFFFFFFF, 0
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x0D000000 ; Z C
?!Z     HALT

        MOVE    R14, 0x04000000
        SUB[CM] R1, 5, 5
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFFFFFFFF
?!Z     HALT
        SUB[M]  R0, R10, 0x17000000 ; N C X
?!Z     HALT
```

### 2.7 Flags are updated when the destination is memory (§6)

The only M instruction with a memory destination is check 100's, and it is skipped. Every executed M instruction writes a register or R0. In a core whose memory write-back takes a different path, the flag update can be lost on that path.

```
        MOVE    R14, 0
        ADD[M]  @wdata, 0xFFFFFFFF, 1
        MOVE    R10, R14
        SUB[M]  R0, @wdata, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x0D000000 ; Z C
?!Z     HALT
```

This needs a word that no later check expects to be 0. Check 100 reads `wdata+8`, so either reuse another word or widen `wdata`.

### 2.8 All eight bits of the `INT` vector (§5.3, §7.2)

Every `INT` is `INT 3`, which exercises two bits of the vector field. `INT 255` with VBASE = `0x0F` reads the vector at `0xFFF`, which keeps the program under `0x1000`:

```
        MOVE    R4, 0
        MOVE    R14, 0x0000000F
        INT     255
        SUB[M]  R0, R4, 0x8100000F
?!Z     HALT
        ...
        .ORG    0xFFF
        .DAT    isr
```

## 3. Smaller gaps

### 3.1 A wrongly executed `?!1 INT 3` is detected only by accident

In check 102, `?!1 HALT`, `?!1 RTI`, and the two reserved words halt the processor if they wrongly run, so each is detected directly. `?!1 INT 3` is not: it enters the routine, which changes R4 and R6 and returns, and check 103 overwrites R4 before anything reads it.

I ran the program with the `?!1` removed from that line to see what happens. VBASE is 0 there, so the `INT` reads word 3, which is the constant 1 of `MOVE R12, 1`, and jumps to word 1. That word is the constant 2 of `MOVE PC, start`, and as an instruction it is `MOVE R0, R0, R2`, a NOP. So the test restarts from `start` inside the interrupt routine, passes checks 1 to 101 again, and halts at the same `INT` as a nested interrupt after 1610 steps, with R12 = 102 and R11 = 0. That is a detected failure, but only because words 1 and 3 happen to be harmless. Clearing R4 before the line and comparing it with 0 after makes the detection direct, as check 106 already does for its skipped `INT`.

### 3.2 R14 as a destination in modes 001 and 010 with M (§4.3, §6)

Check 97 covers mode 000. The rule names three modes, and the two others combine the no-flag rule with the two-writes rule of §4.2:

```
        MOVE[M] R14--, 0        ; R14 = 0x01FFFFFF, no flag update
        MOVE    R10, R14
        SUB[M]  R0, R10, 0x01FFFFFF
?!Z     HALT
        MOVE[M] R14++, 0        ; R14 = 0x01000001
        MOVE    R10, R14
        SUB[M]  R0, R10, 0x01000001
?!Z     HALT
```

### 3.3 No executed instruction has three constant words (§2.3)

Check 82 fixes the order dest before s0, and the two-constant compares fix s0 before s1, so the full order is covered only by combination. Check 101 has a three-constant instruction, but it is skipped and its three constants are equal. One executed instruction settles it:

```
        SUB     @wdata+1, 0x123, 0x23
        SUB[M]  R0, @wdata+1, 0x100
?!Z     HALT
```

### 3.4 The last write to R15 wins (§4.3)

Check 94 tests `MOVE R15++, pc5`, where the increment is the last write. The other order, a destination write after a source side effect, is untested:

```
        ADD     PC, PC++, 2     ; s0 = pcA, PC <- pcA + 1, then PC <- pcA + 2
pcA     HALT                    ; never runs: jumped over
        HALT                    ; never runs: jumped over
```

A core that lets the side effect win halts at `pcA + 1`.

### 3.5 Only `MOVE` and `DEC` are shown to ignore the C bit (§5.1)

"All other ALU operations ignore the C bit" covers the eleven others too. One logic operation with `[CM]` and C = 1, such as `AND[CM] R1, R2, R3` expecting `0x000F000F`, covers the rest of the rule.

## 4. Documentation

Check 98 writes `0xFF000000` to R14, which sets E, with VBASE = 0, and keeps it set for sixteen instructions. On the emulator nothing can happen. On hardware with an IRQ source, a request in that window is taken and jumps through the program's first words. The header says that the program needs no emulator options or I/O, which is true, but it should also say that no IRQ may be raised while the test runs. The check in §2.1 sets E as well.

## 5. What is correct

For a later round, these were checked and found right:

- **Every expected value.** Checks 3 to 15 pair every bit value of `0x00FF00FF` with every bit value of `0x0F0F0F0F`, as the comment says, and the nine logic results and their N flags are right. The arithmetic flag words in checks 16 to 39 are right, including the three that need thought: check 23 (V, N, and C from `0x7FFFFFFF − 0xFFFFFFFF`), check 27 (`MDBL` with `0xFFFFFFFF` doubling `0x80000000` to V, Z, and C), and check 30 (`DBL[CM]` of `0x80000001` to 3 with V and C). The sixteen shifts in checks 40 to 55 and the count rules in 56 to 71 match the loop of §5.2 and its closed forms: 32 leaves C as the last bit out, 33 leaves the fill bit, 36 and 33 reduce modulo 32 for the rotations, and 33 and 34 reduce modulo 33 for `C<C`.
- **The hand-encoded words.** `0x00004063` is `MOVE R1, R0, @R3++`, `0x01C05100` is `ONE R1, R2++, R0`, `0x00004030` is `MOVE R1, R0, c` with the following `HALT` as its constant, `0x8C600000` is `?!1` with command 3, and `0x8C000100` is `?!1 HALT` with bit 8 set. Word 0 is `0x0003D800`.
- **The R15 arithmetic.** Checks 91 to 94 expect `pc1`, `pc2 + 5`, `pc3`, and `2·pc4 + 1`, which follow from R15 reading as the address after the constant words and the side effect landing before s1.
- **The R14 bit 24 cases.** Checks 96 and 97 match §4.2 and §4.3 word for word.
- **The interrupt checks.** The saved SR, the I bit, the restored flags, the return address, and the skipped and taken conditional `INT` are all as §7 says.
- **The trace.** No "never runs" line executes, no body address executes twice, the interrupt routine runs four times, and the step count is 855 + 2 + 4 × 3 = 869.
- **The documentation.** The header, the emulator README, and the top-level README describe the program accurately.

## 6. Second round, commit f711ca8

The program now has 117 checks. I checked the nine new checks and the five extended ones by hand against ISA.md, confirmed that `make test` passes and that the committed `.bin` is what `niceasm` produces from the source, and mapped the new trace back to the source lines as in the first round.

### 6.1 Confirmed fixed

| Finding | Where it is now | Checked |
|---|---|---|
| §1, conditional `HALT` with a true condition | The final halt at `pass` is `?!Z HALT` with Z = 0, followed by two never-run lines | It is the only `HALT` in the trace, and the trace shows it as the `?!Z` encoding `0xBC000000` |
| §2.1, I, E, and VBASE survive M | Check 39 | `0xC0FFFFFF` becomes `0xC1FFFFFF` after `ADD[M]` |
| §2.2, carry input timing for shifts | Check 76 | `0<C R1, R14++, 1` gives `0x07FFFFFF` |
| §2.3, a shift clears V, N, Z, and X | Check 52 starts from `0x3E000000` | SR ends as `0x01000000` |
| §2.4, R15 in the memory modes | Check 101 | `@R15++` reads and skips the `.DAT`, and `@1[R15]` reads the next instruction's constant |
| §2.5, `@--R0` and `@R0++` | Check 97 | Both compare with word 0 |
| §2.6, carry input in the carry and borrow out | Checks 26 and 27 | Z C, and N C X |
| §2.7, flags with a memory destination | Check 92 | Overwrites `wdata`, which no later check reads; Z C |
| §2.8, eight-bit `INT` vector | Check 115, with a second vector at `0xFFF` | R4 = `0x8100000F` |
| §3.1, wrongly run `?!1 INT` | Check 110 clears R4 before and compares it after | Direct now |
| §3.2, R14 modes 001 and 010 with M | Check 105 | `0x01FFFFFF` and `0x01000001` |
| §3.3, three constant words | Check 93 | `0x123 − 0x23` lands at `wdata+1`, which no later check reads |
| §3.4, last write to R15 in both orders | Check 102 adds `ADD PC, PC++, 2` over two never-run `HALT`s | Jumped over |
| §3.5, a logic operation ignores the C bit | Check 37, `AND[CM]` | `0x000F000F`, SR `0x01000000` |
| §4, IRQs on hardware | The header and the emulator README say that no IRQ may be raised | |

The `.expected` file is right: 931 body lines, each executed once, plus the two lines of the subroutine and five runs of the three-line interrupt routine give 948 steps, and the PC is the address after the final `?!Z HALT`. The thirteen "never runs" lines never run, and the only skipped instructions are 214 of the 215 `?!Z HALT` lines and the twenty-six intended skips.

### 6.2 Nit

The header still says "Every other line up to the final HALT is one step." The final `HALT` line is now one of the two never-run lines after the `?!Z HALT` at `pass`. The sentence is still true, because the never-run lines are excluded first, but "up to the `?!Z HALT` at `pass`" would name the line that actually halts.
