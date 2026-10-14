; A self-checking test of the instruction set (ISA.md §2-§7).
;
; Each check sets R12 to its number, runs an instruction, and compares the
; result, and often SR, with the value ISA.md gives. On a mismatch it halts
; right there, so PC points just after the failing check, R12 holds its
; number, and R11 is 0. When every check passes, the program clears R1-R10
; and R13, sets R11 = 0x600D, and halts with R12 = 117, the number of checks.
; That final halt is a ?!Z HALT with Z = 0, the same instruction every check
; relies on, so a core that skipped it would end with R11 = 0.
;
; The program uses no I/O and no memory above 0x1000, so it can run on the
; FPGA core as well as on the emulator. External interrupts are tested by
; irq.asm and merge.asm instead, because they need the emulator's options.
; No IRQ may be raised while the test runs: some checks set E with the
; vector table not in place.
;
; SR values in the comments: 0x01000000 is bit 24 alone, and the flags are
; V = 0x20000000, N = 0x10000000, Z = 0x08000000, C = 0x04000000, and
; X = 0x02000000. E, I, and VBASE are 0, except where a check sets them.
;
; Lines whose comment starts with "never runs" are not executed, not even
; as a skipped instruction. Every other line up to the ?!Z HALT at pass is
; one step. Run make bins after changing this file.

SP      .EQU    R13
PC      .EQU    R15

        MOVE    PC, start       ; word 0 is 0x0003D800, read by checks 84 and 97

; ---- 1. The checking method itself (§3, §9.2) ---------------------------
start   MOVE    R12, 1
        SUB[M]  R0, 5, 6        ; Z = 0
?!Z     MOVE    PC, ok1         ; so this jumps
        HALT                    ; never runs: jumped over
ok1     MOVE    R12, 2
        SUB[M]  R0, 5, 5        ; Z = 1
?!Z     HALT
?Z      MOVE    PC, ok2         ; so this jumps
        HALT                    ; never runs: jumped over
ok2

; ---- 2. ALU operations (§5.1, §6) --------------------------------------
; The logic operations run on a = 0x00FF00FF and b = 0x0F0F0F0F, which
; pair every bit value of a with every bit value of b. SR is set to every
; flag first, so each check also shows the flags it clears.
        MOVE    R2, 0x00FF00FF
        MOVE    R3, 0x0F0F0F0F

        MOVE    R12, 3
        MOVE    R14, 0x3E000000
        MOVE[M] R1, R2
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x00FF00FF
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 4
        MOVE    R14, 0x3E000000
        NOT[M]  R1, R2
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFF00FF00
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 5
        MOVE    R14, 0x3E000000
        NOR[M]  R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xF000F000
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 6
        MOVE    R14, 0x3E000000
        IAND[M] R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x0F000F00
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 7
        MOVE    R14, 0x3E000000
        NAND[M] R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFFF0FFF0
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 8
        MOVE    R14, 0x3E000000
        XOR[M]  R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x0FF00FF0
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 9
        MOVE    R14, 0x3E000000
        IOR[M]  R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFF0FFF0F
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 10
        MOVE    R14, 0x3E000000
        XNOR[M] R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xF00FF00F
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 11
        MOVE    R14, 0x3E000000
        AND[M]  R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x000F000F
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 12
        MOVE    R14, 0x3E000000
        ONE[M]  R1
        MOVE    R10, R14
        SUB[M]  R0, R1, 1
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 13
        MOVE    R14, 0x3E000000
        OR[M]   R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x0FFF0FFF
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 14         ; X and N on an all-ones result
        NOT[M]  R1, 0
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFFFFFFFF
?!Z     HALT
        SUB[M]  R0, R10, 0x13000000 ; N X
?!Z     HALT

        MOVE    R12, 15         ; Z on a zero result
        AND[M]  R1, R2, 0xFF00FF00
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x09000000 ; Z
?!Z     HALT

; Arithmetic. SR is cleared first unless the check needs C = 1.
        MOVE    R12, 16
        MOVE    R14, 0
        ADD[M]  R1, 0x7FFFFFFF, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000000
?!Z     HALT
        SUB[M]  R0, R10, 0x31000000 ; V N
?!Z     HALT

        MOVE    R12, 17
        MOVE    R14, 0
        ADD[M]  R1, 0xFFFFFFFF, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x0D000000 ; Z C
?!Z     HALT

        MOVE    R12, 18
        MOVE    R14, 0
        ADD[M]  R1, 0x80000000, 0x80000000
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x2D000000 ; V Z C
?!Z     HALT

        MOVE    R12, 19         ; ADD[C] adds C
        MOVE    R14, 0x04000000
        ADD[CM] R1, 5, 6
        MOVE    R10, R14
        SUB[M]  R0, R1, 12
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 20         ; ADD without [C] ignores C
        MOVE    R14, 0x04000000
        ADD[M]  R1, 5, 6
        SUB[M]  R0, R1, 11
?!Z     HALT

        MOVE    R12, 21
        MOVE    R14, 0
        SUB[M]  R1, 5, 6
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFFFFFFFF
?!Z     HALT
        SUB[M]  R0, R10, 0x17000000 ; N C X
?!Z     HALT

        MOVE    R12, 22
        MOVE    R14, 0
        SUB[M]  R1, 0x80000000, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x7FFFFFFF
?!Z     HALT
        SUB[M]  R0, R10, 0x21000000 ; V
?!Z     HALT

        MOVE    R12, 23
        MOVE    R14, 0
        SUB[M]  R1, 0x7FFFFFFF, 0xFFFFFFFF
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000000
?!Z     HALT
        SUB[M]  R0, R10, 0x35000000 ; V N C
?!Z     HALT

        MOVE    R12, 24
        MOVE    R14, 0
        SUB[M]  R1, 7, 7
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x09000000 ; Z
?!Z     HALT

        MOVE    R12, 25         ; SUB[C] subtracts C
        MOVE    R14, 0x04000000
        SUB[CM] R1, 10, 3
        MOVE    R10, R14
        SUB[M]  R0, R1, 6
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 26         ; the carry input takes part in the carry out
        MOVE    R14, 0x04000000
        ADD[CM] R1, 0xFFFFFFFF, 0
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x0D000000 ; Z C
?!Z     HALT

        MOVE    R12, 27         ; ... and in the borrow out
        MOVE    R14, 0x04000000
        SUB[CM] R1, 5, 5
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFFFFFFFF
?!Z     HALT
        SUB[M]  R0, R10, 0x17000000 ; N C X
?!Z     HALT

        MOVE    R12, 28         ; MDBL: s0 + (s0 AND s1)
        MOVE    R14, 0
        MDBL[M] R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x010E010E
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 29
        MOVE    R14, 0
        MDBL[M] R1, 0x80000000, 0xFFFFFFFF
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x2D000000 ; V Z C
?!Z     HALT

        MOVE    R12, 30         ; MDBL[C]: 3 + (3 AND 1) + 1
        MOVE    R14, 0x04000000
        MDBL[CM] R1, 3, 1
        SUB[M]  R0, R1, 5
?!Z     HALT

        MOVE    R12, 31
        MOVE    R14, 0
        DBL[M]  R1, 0x40000000
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000000
?!Z     HALT
        SUB[M]  R0, R10, 0x31000000 ; V N
?!Z     HALT

        MOVE    R12, 32         ; DBL[C]: 2 * 0x80000001 + 1
        MOVE    R14, 0x04000000
        DBL[CM] R1, 0x80000001
        MOVE    R10, R14
        SUB[M]  R0, R1, 3
?!Z     HALT
        SUB[M]  R0, R10, 0x25000000 ; V C
?!Z     HALT

        MOVE    R12, 33
        MOVE    R14, 0
        DEC[M]  R1, 0
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFFFFFFFF
?!Z     HALT
        SUB[M]  R0, R10, 0x17000000 ; N C X
?!Z     HALT

        MOVE    R12, 34
        MOVE    R14, 0
        DEC[M]  R1, 0x80000000
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x7FFFFFFF
?!Z     HALT
        SUB[M]  R0, R10, 0x21000000 ; V
?!Z     HALT

        MOVE    R12, 35         ; DEC ignores [C]
        MOVE    R14, 0x04000000
        DEC[CM] R1, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x09000000 ; Z
?!Z     HALT

        MOVE    R12, 36         ; MOVE ignores [C]; C is cleared
        MOVE    R14, 0x04000000
        MOVE[CM] R1, 0x80000000
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000000
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 37         ; AND ignores [C], as do the other logic ops
        MOVE    R14, 0x04000000
        AND[CM] R1, R2, R3
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x000F000F
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 38         ; without M, no flag changes
        MOVE    R14, 0x3E000000
        ADD     R1, 0xFFFFFFFF, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x3F000000
?!Z     HALT

        MOVE    R12, 39         ; M leaves I, E, and VBASE alone
        MOVE    R14, 0xC0FFFFFF ; I, E, and every VBASE bit
        ADD[M]  R1, 1, 1
        MOVE    R10, R14
        SUB[M]  R0, R10, 0xC1FFFFFF
?!Z     HALT

        MOVE    R12, 40         ; flags come from r, not from what Rx++ stores
        MOVE    R14, 0
        ADD[M]  R1++, 0xFFFFFFFE, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x13000000 ; N X
?!Z     HALT

        MOVE    R12, 41         ; the carry input is C as step 5 left it
        MOVE    R14, 0x03FFFFFF ; C = 0
        ADD[C]  R1, R14++, 0    ; R14++ carries into C
        SUB[M]  R0, R1, 0x04000000
?!Z     HALT

        MOVE    R12, 42         ; 64-bit add: 0x1FFFFFFFF + 0x200000001
        MOVE    R2, 0xFFFFFFFF
        MOVE    R3, 1
        ADD[M]  R2, R2, 1
        ADD[C]  R3, R3, 2
        SUB[M]  R0, R2, 0
?!Z     HALT
        SUB[M]  R0, R3, 4
?!Z     HALT

        MOVE    R12, 43         ; 64-bit subtract: 0x500000000 - 0x100000001
        MOVE    R2, 0
        MOVE    R3, 5
        SUB[M]  R2, R2, 1
        SUB[C]  R3, R3, 1
        SUB[M]  R0, R2, 0xFFFFFFFF
?!Z     HALT
        SUB[M]  R0, R3, 3
?!Z     HALT

; ---- 3. Shifts (§5.2) ---------------------------------------------------
; Each of the 16 shifts once by 1, on 0xC0000001. A left shift moves out
; bit 31 = 1 and leaves 0x80000002 before the fill. A right shift moves out
; bit 0 = 1 and leaves 0x60000000 before the fill. C is set to the opposite
; of what the shift should leave.
        MOVE    R2, 0xC0000001

        MOVE    R12, 44
        MOVE    R14, 0x04000000
        SHL[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000002
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 45
        MOVE    R14, 0x04000000
        0<1[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000003
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 46         ; fill C = 1, C then cleared
        MOVE    R14, 0x04000000
        0<C[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000003
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 47
        MOVE    R14, 0
        C<0[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000002
?!Z     HALT
        SUB[M]  R0, R10, 0x15000000 ; N C
?!Z     HALT

        MOVE    R12, 48
        MOVE    R14, 0
        C<1[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000003
?!Z     HALT
        SUB[M]  R0, R10, 0x15000000 ; N C
?!Z     HALT

        MOVE    R12, 49         ; fill C = 0, C becomes 1
        MOVE    R14, 0
        C<C[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000002
?!Z     HALT
        SUB[M]  R0, R10, 0x15000000 ; N C
?!Z     HALT

        MOVE    R12, 50
        MOVE    R14, 0x04000000
        ROL[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000003
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 51
        MOVE    R14, 0
        C<<[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x80000003
?!Z     HALT
        SUB[M]  R0, R10, 0x15000000 ; N C
?!Z     HALT

        MOVE    R12, 52         ; every flag set: V, N, Z, and X are cleared too
        MOVE    R14, 0x3E000000
        SHR[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x60000000
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 53
        MOVE    R14, 0x04000000
        1>0[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xE0000000
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 54         ; fill C = 1, C then cleared
        MOVE    R14, 0x04000000
        C>0[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xE0000000
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 55
        MOVE    R14, 0
        0>C[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x60000000
?!Z     HALT
        SUB[M]  R0, R10, 0x05000000 ; C
?!Z     HALT

        MOVE    R12, 56
        MOVE    R14, 0
        1>C[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xE0000000
?!Z     HALT
        SUB[M]  R0, R10, 0x15000000 ; N C
?!Z     HALT

        MOVE    R12, 57         ; fill C = 0, C becomes 1
        MOVE    R14, 0
        C>C[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x60000000
?!Z     HALT
        SUB[M]  R0, R10, 0x05000000 ; C
?!Z     HALT

        MOVE    R12, 58
        MOVE    R14, 0x04000000
        ROR[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xE0000000
?!Z     HALT
        SUB[M]  R0, R10, 0x11000000 ; N
?!Z     HALT

        MOVE    R12, 59
        MOVE    R14, 0
        >>C[M]  R1, R2, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xE0000000
?!Z     HALT
        SUB[M]  R0, R10, 0x15000000 ; N C
?!Z     HALT

; Counts of 0, 32, and more, and counts that rotations reduce.
        MOVE    R12, 60         ; n = 0 leaves s0, and C for a C shift
        MOVE    R14, 0x04000000
        C<0[M]  R1, 5, 0
        MOVE    R10, R14
        SUB[M]  R0, R1, 5
?!Z     HALT
        SUB[M]  R0, R10, 0x05000000 ; C
?!Z     HALT

        MOVE    R12, 61         ; n = 0 still clears C for the other shifts
        MOVE    R14, 0x04000000
        SHL[M]  R1, 5, 0
        MOVE    R10, R14
        SUB[M]  R0, R1, 5
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 62         ; n = 32: C is the last bit out, bit 0
        MOVE    R14, 0
        C<0[M]  R1, 1, 32
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x0D000000 ; Z C
?!Z     HALT

        MOVE    R12, 63         ; n = 33: C is the fill bit
        MOVE    R14, 0x04000000
        C<0[M]  R1, 0xFFFFFFFF, 33
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x09000000 ; Z
?!Z     HALT

        MOVE    R12, 64
        MOVE    R14, 0
        C<1[M]  R1, 0, 40
        MOVE    R10, R14
        SUB[M]  R0, R1, 0xFFFFFFFF
?!Z     HALT
        SUB[M]  R0, R10, 0x17000000 ; N C X
?!Z     HALT

        MOVE    R12, 65         ; n = 32: C is the last bit out, bit 31
        MOVE    R14, 0
        0>C[M]  R1, 0x80000000, 32
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x0D000000 ; Z C
?!Z     HALT

        MOVE    R12, 66         ; all 32 bits of the count: no modulo
        SHL     R1, 0xFFFFFFFF, 0x80000000
        SUB[M]  R0, R1, 0
?!Z     HALT

        MOVE    R12, 67         ; 36 = 4 mod 32
        ROL     R1, 0x12345678, 36
        SUB[M]  R0, R1, 0x23456781
?!Z     HALT

        MOVE    R12, 68
        ROR     R1, 0x12345678, 4
        SUB[M]  R0, R1, 0x81234567
?!Z     HALT

        MOVE    R12, 69         ; 33 = 1 mod 32; C = bit 0 of r
        MOVE    R14, 0
        C<<[M]  R1, 0x80000000, 33
        MOVE    R10, R14
        SUB[M]  R0, R1, 1
?!Z     HALT
        SUB[M]  R0, R10, 0x05000000 ; C
?!Z     HALT

        MOVE    R12, 70         ; 33-bit rotation by 33 changes nothing
        MOVE    R14, 0x04000000
        C<C[M]  R1, 0x12345678, 33
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x12345678
?!Z     HALT
        SUB[M]  R0, R10, 0x05000000 ; C
?!Z     HALT

        MOVE    R12, 71         ; 34 = 1 mod 33: C = 1 in, bit 31 = 0 out
        MOVE    R14, 0x04000000
        C<C[M]  R1, 0x12345678, 34
        MOVE    R10, R14
        SUB[M]  R0, R1, 0x2468ACF1
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 72
        MOVE    R14, 0
        C>C[M]  R1, 1, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x0D000000 ; Z C
?!Z     HALT

        MOVE    R12, 73         ; without M: no flags, C unchanged
        MOVE    R14, 0
        C<0     R1, 0x80000000, 1
        MOVE    R10, R14
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 74         ; each fill is the original C, without M too
        MOVE    R14, 0x04000000
        0<C     R1, 0, 3
        MOVE    R10, R14
        SUB[M]  R0, R1, 7
?!Z     HALT
        SUB[M]  R0, R10, 0x05000000 ; C
?!Z     HALT

        MOVE    R12, 75         ; without M, C<C uses c inside the shift only:
        MOVE    R14, 0x04000000 ; 0x80000000 -> 1 (c = 1) -> 3 (c = 0)
        C<C     R1, 0x80000000, 2
        MOVE    R10, R14
        SUB[M]  R0, R1, 3
?!Z     HALT
        SUB[M]  R0, R10, 0x05000000 ; C
?!Z     HALT

        MOVE    R12, 76         ; the fill C is C as step 5 left it
        MOVE    R14, 0x03FFFFFF ; C = 0
        0<C     R1, R14++, 1    ; R14++ carries into C, so the fill is 1
        SUB[M]  R0, R1, 0x07FFFFFF
?!Z     HALT

        MOVE    R12, 77         ; arithmetic shift right by 4
        MOVE    R1, 0xFFFFFF00
        C<0[M]  R0, R1, 1
        C>0     R1, R1, 4
        SUB[M]  R0, R1, 0xFFFFFFF0
?!Z     HALT

; ---- 4. Addressing modes (§4) -------------------------------------------
; Source modes, with R2 as the register. rdata holds 0x11, 0x22, 0x33, and
; 0x44.
        MOVE    R12, 78         ; 001 --Rx
        MOVE    R2, 10
        MOVE    R1, --R2
        SUB[M]  R0, R1, 9
?!Z     HALT
        SUB[M]  R0, R2, 9
?!Z     HALT

        MOVE    R12, 79         ; 010 Rx++
        MOVE    R2, 10
        MOVE    R1, R2++
        SUB[M]  R0, R1, 10
?!Z     HALT
        SUB[M]  R0, R2, 11
?!Z     HALT

        MOVE    R12, 80         ; 011 c[Rx]
        MOVE    R2, 10
        MOVE    R1, 5[R2]
        SUB[M]  R0, R1, 15
?!Z     HALT

        MOVE    R12, 81         ; 100 @Rx
        MOVE    R2, rdata
        MOVE    R1, @R2
        SUB[M]  R0, R1, 0x11
?!Z     HALT

        MOVE    R12, 82         ; 101 @--Rx
        MOVE    R2, rdata+2
        MOVE    R1, @--R2
        SUB[M]  R0, R1, 0x22
?!Z     HALT
        SUB[M]  R0, R2, rdata+1
?!Z     HALT

        MOVE    R12, 83         ; 110 @Rx++
        MOVE    R2, rdata+2
        MOVE    R1, @R2++
        SUB[M]  R0, R1, 0x33
?!Z     HALT
        SUB[M]  R0, R2, rdata+3
?!Z     HALT

        MOVE    R12, 84         ; 111 @c[Rx] and @c; @R0 is word 0
        MOVE    R2, 1
        MOVE    R1, @rdata[R2]
        SUB[M]  R0, R1, 0x22
?!Z     HALT
        SUB[M]  R0, @rdata+3, 0x44
?!Z     HALT
        SUB[M]  R0, @R0, 0x0003D800
?!Z     HALT

        MOVE    R12, 85         ; s0's side effect comes before s1
        MOVE    R2, 10
        ADD     R1, R2++, R2++  ; 10 + 11
        SUB[M]  R0, R1, 21
?!Z     HALT
        SUB[M]  R0, R2, 12
?!Z     HALT
        MOVE    R2, rdata
        ADD     R1, @R2++, @R2++ ; 0x11 + 0x22
        SUB[M]  R0, R1, 0x33
?!Z     HALT
        SUB[M]  R0, R2, rdata+2
?!Z     HALT
        MOVE    R2, 10
        SUB     R1, --R2, R2    ; 9 - 9
        SUB[M]  R0, R1, 0
?!Z     HALT

; Destination modes, with R3 as the register, writing to wdata.
        MOVE    R12, 86         ; 001 Rx-- and 010 Rx++
        MOVE    R3--, 10
        SUB[M]  R0, R3, 9
?!Z     HALT
        MOVE    R3++, 10
        SUB[M]  R0, R3, 11
?!Z     HALT

        MOVE    R12, 87         ; 011 c[Rx] writes memory
        MOVE    R3, wdata
        MOVE    1[R3], 0x55
        SUB[M]  R0, @wdata+1, 0x55
?!Z     HALT

        MOVE    R12, 88         ; 100 @Rx
        MOVE    @R3, 0x66
        SUB[M]  R0, @wdata, 0x66
?!Z     HALT

        MOVE    R12, 89         ; 101 @--Rx
        MOVE    R3, wdata+3
        MOVE    @--R3, 0x77
        SUB[M]  R0, @wdata+2, 0x77
?!Z     HALT
        SUB[M]  R0, R3, wdata+2
?!Z     HALT

        MOVE    R12, 90         ; 110 @Rx++
        MOVE    R3, wdata+3
        MOVE    @R3++, 0x88
        SUB[M]  R0, @wdata+3, 0x88
?!Z     HALT
        SUB[M]  R0, R3, wdata+4
?!Z     HALT

        MOVE    R12, 91         ; 111 @c[Rx] and @c
        MOVE    R3, 4
        MOVE    @wdata[R3], 0x99
        SUB[M]  R0, @wdata+4, 0x99
?!Z     HALT
        MOVE    @wdata+5, 0xAA
        SUB[M]  R0, @wdata+5, 0xAA
?!Z     HALT

        MOVE    R12, 92         ; M with a memory destination sets the flags
        MOVE    R14, 0
        ADD[M]  @wdata, 0xFFFFFFFF, 1 ; overwrites 0x66
        MOVE    R10, R14
        SUB[M]  R0, @wdata, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x0D000000 ; Z C
?!Z     HALT

        MOVE    R12, 93         ; three constant words, in order dest, s0, s1
        SUB     @wdata+1, 0x123, 0x23
        SUB[M]  R0, @wdata+1, 0x100
?!Z     HALT

        MOVE    R12, 94         ; the destination uses R3 as step 5 left it
        MOVE    R3, wdata+6
        MOVE    @R3, R3++       ; mem[wdata+7] = wdata+6
        SUB[M]  R0, @wdata+7, wdata+6
?!Z     HALT
        SUB[M]  R0, R3, wdata+7
?!Z     HALT

        MOVE    R12, 95         ; Rx-- after a source Rx++: R2 = 10+5-1
        MOVE    R2, 10
        ADD     R2--, R2++, 5
        SUB[M]  R0, R2, 14
?!Z     HALT

        MOVE    R12, 96         ; unused fields are still evaluated (§4.4)
        MOVE    R3, 10
        .DAT    0x00004063      ; MOVE R1, R0, @R3++
        SUB[M]  R0, R3, 11
?!Z     HALT
        MOVE    R2, 10
        .DAT    0x01C05100      ; ONE R1, R2++, R0
        SUB[M]  R0, R1, 1
?!Z     HALT
        SUB[M]  R0, R2, 11
?!Z     HALT
        .DAT    0x00004030      ; MOVE R1, R0, c: c is taken, not run
        HALT                    ; never runs: it is the constant word
        SUB[M]  R0, R1, 0
?!Z     HALT

; R0, R15, and R14 (§4.3).
        MOVE    R12, 97         ; R0 reads 0 in every mode
        MOVE    R0, 5
        MOVE    R0++, 5
        ADD     R1, R0, 0
        ADD     R1, R1, --R0
        ADD     R1, R1, R0++
        ADD     R1, R1, R0
        SUB[M]  R0, R1, 0
?!Z     HALT
        SUB[M]  R0, @--R0, 0x0003D800 ; @--R0 and @R0++ are word 0
?!Z     HALT
        SUB[M]  R0, @R0++, 0x0003D800
?!Z     HALT

        MOVE    R12, 98         ; R15 reads the address after the constants
        MOVE    R1, R15
pc1     SUB[M]  R0, R1, pc1
?!Z     HALT
        ADD     R1, 5, R15
pc2     SUB[M]  R0, R1, pc2+5
?!Z     HALT

        MOVE    R12, 99         ; a source side effect on R15 is a jump
        MOVE    R1, R15++
pc3     HALT                    ; never runs: jumped over
        SUB[M]  R0, R1, pc3
?!Z     HALT

        MOVE    R12, 100        ; after R15++, a later operand sees the new PC
        ADD     R1, R15++, R15
pc4     HALT                    ; never runs: jumped over
        SUB[M]  R0, R1, pc4+pc4+1
?!Z     HALT

        MOVE    R12, 101        ; R15 in the memory modes
        MOVE    R1, @R15++      ; reads the next word and skips it
        .DAT    0x1234          ; never runs: data
        SUB[M]  R0, R1, 0x1234
?!Z     HALT
        MOVE    R1, @1[R15]     ; the constant word of the SUB below
        SUB[M]  R0, R1, 0x5678
?!Z     HALT

        MOVE    R12, 102        ; R15 written twice: the last write wins
        MOVE    R15++, pc5      ; dest, then its increment
pc5     HALT                    ; never runs: jumped over
        ADD     PC, PC++, 2     ; s0's increment, then dest: PC = pcA + 2
pcA     HALT                    ; never runs: jumped over
        HALT                    ; never runs: jumped over
        ADD     PC, PC, 1       ; relative jump
        HALT                    ; never runs: jumped over

        MOVE    R12, 103        ; call and return through the stack (§9.1)
        MOVE    SP, stack
        ADD     @--SP, 2, PC
        MOVE    PC, subr
        SUB[M]  R0, R1, 0x5B
?!Z     HALT
        SUB[M]  R0, SP, stack
?!Z     HALT

        MOVE    R12, 104        ; R14 bit 24 is always 1
        MOVE    R14, 0
        MOVE    R1, R14
        SUB[M]  R0, R1, 0x01000000
?!Z     HALT
        MOVE    R14--, 0        ; two writes, each sets bit 24
        MOVE    R1, R14
        SUB[M]  R0, R1, 0x01FFFFFF
?!Z     HALT
        MOVE    R14, 0
        MOVE    R1, --R14
        SUB[M]  R0, R1, 0x01FFFFFF
?!Z     HALT

        MOVE    R12, 105        ; M with R14 as register destination: no flags
        MOVE[M] R14, 0
        MOVE    R10, R14
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT
        MOVE[M] R14--, 0        ; R14 = 0x01FFFFFF, no flag update
        MOVE    R10, R14
        SUB[M]  R0, R10, 0x01FFFFFF
?!Z     HALT
        MOVE[M] R14++, 0        ; R14 = 0x01000001
        MOVE    R10, R14
        SUB[M]  R0, R10, 0x01000001
?!Z     HALT

; ---- 5. Conditions (§3) -------------------------------------------------
; As in cond.asm: each condition sets its own bit of R1 to R4.
        MOVE    R12, 106
        MOVE    R1, 0
        MOVE    R2, 0
        MOVE    R3, 0
        MOVE    R4, 0
        MOVE    R14, 0xFF000000 ; every flag set
?1      OR      R1, R1, 0x01
?X      OR      R1, R1, 0x02
?C      OR      R1, R1, 0x04
?Z      OR      R1, R1, 0x08
?N      OR      R1, R1, 0x10
?V      OR      R1, R1, 0x20
?E      OR      R1, R1, 0x40
?I      OR      R1, R1, 0x80
?!1     OR      R2, R2, 0x01
?!X     OR      R2, R2, 0x02
?!C     OR      R2, R2, 0x04
?!Z     OR      R2, R2, 0x08
?!N     OR      R2, R2, 0x10
?!V     OR      R2, R2, 0x20
?!E     OR      R2, R2, 0x40
?!I     OR      R2, R2, 0x80
        MOVE    R14, 0          ; every flag clear
?1      OR      R3, R3, 0x01
?X      OR      R3, R3, 0x02
?C      OR      R3, R3, 0x04
?Z      OR      R3, R3, 0x08
?N      OR      R3, R3, 0x10
?V      OR      R3, R3, 0x20
?E      OR      R3, R3, 0x40
?I      OR      R3, R3, 0x80
?!1     OR      R4, R4, 0x01
?!X     OR      R4, R4, 0x02
?!C     OR      R4, R4, 0x04
?!Z     OR      R4, R4, 0x08
?!N     OR      R4, R4, 0x10
?!V     OR      R4, R4, 0x20
?!E     OR      R4, R4, 0x40
?!I     OR      R4, R4, 0x80
        SUB[M]  R0, R1, 0xFF
?!Z     HALT
        SUB[M]  R0, R2, 0
?!Z     HALT
        SUB[M]  R0, R3, 0x01
?!Z     HALT
        SUB[M]  R0, R4, 0xFE
?!Z     HALT

        MOVE    R12, 107        ; the condition uses SR from before
        MOVE    R14, 0x08000000 ; Z
?Z      MOVE[M] R1, 5           ; runs, and clears Z
?Z      MOVE    R1, 6           ; skipped
        SUB[M]  R0, R1, 5
?!Z     HALT

        MOVE    R12, 108        ; a skipped instruction has no effect
        MOVE    R14, 0
        MOVE    R2, wdata+8
        MOVE    R3, 10
?!1     ADD[M]  @R2++, R3++, 1
        MOVE    R10, R14
        SUB[M]  R0, R2, wdata+8
?!Z     HALT
        SUB[M]  R0, R3, 10
?!Z     HALT
        SUB[M]  R0, @wdata+8, 0
?!Z     HALT
        SUB[M]  R0, R10, 0x01000000
?!Z     HALT

        MOVE    R12, 109        ; but it takes its constant words
?!1     MOVE    R1, 0x0C000000  ; the constant is HALT
?!1     ADD     @0x0C000000, 0x0C000000, 0x0C000000

        MOVE    R12, 110        ; skipped control words do nothing
        MOVE    R4, 0
?!1     HALT
?!1     RTI
?!1     INT     3               ; would set R4 in isr
        .DAT    0x8C600000      ; ?!1 reserved command 00011
        .DAT    0x8C000100      ; ?!1 HALT with bit 8 set: reserved
        SUB[M]  R0, R4, 0
?!Z     HALT

; ---- 6. Interrupts (§7) -------------------------------------------------
; The vector table is at 0xF00, so VBASE = 0x0F. isr records SR in R4,
; changes the flags, and returns.
        MOVE    R12, 111        ; INT saves SR and sets I
        MOVE    R14, 0x3E00000F ; every flag, VBASE = 0x0F
        INT     3
        SUB[M]  R0, R4, 0xBF00000F
?!Z     HALT

        MOVE    R12, 112        ; RTI restores SR, flags included
        MOVE    R14, 0x3E00000F
        INT     3
        MOVE    R10, R14
        SUB[M]  R0, R10, 0x3F00000F
?!Z     HALT

        MOVE    R12, 113        ; RTI returns to the instruction after INT
        MOVE    R5, 0
        INT     3
        ADD     R5, R5, 1       ; runs once, after the return
        SUB[M]  R0, R5, 1
?!Z     HALT

        MOVE    R12, 114        ; a conditional INT
        MOVE    R4, 0
        MOVE    R14, 0x0800000F ; Z, VBASE = 0x0F
?!Z     INT     3               ; skipped
        SUB[M]  R0, R4, 0
?!Z     HALT
        MOVE    R14, 0x0800000F
?Z      INT     3
        SUB[M]  R0, R4, 0x8900000F
?!Z     HALT

        MOVE    R12, 115        ; all eight bits of the vector: entry 0xFFF
        MOVE    R4, 0
        MOVE    R14, 0x0000000F
        INT     255
        SUB[M]  R0, R4, 0x8100000F
?!Z     HALT
        MOVE    R14, 0

; ---- 7. Memory (§8.2) ---------------------------------------------------
        MOVE    R12, 116        ; a store changes the next instruction
        MOVE    @patch+1, 0x77
patch   MOVE    R1, 0x11
        SUB[M]  R0, R1, 0x77
?!Z     HALT

        MOVE    R12, 117        ; ... and the next instruction word
        MOVE    @patch2, 0      ; a NOP
patch2  HALT                    ; replaced by the NOP, which runs

; ---- All checks passed --------------------------------------------------
pass    MOVE    R1, 0
        MOVE    R2, 0
        MOVE    R3, 0
        MOVE    R4, 0
        MOVE    R5, 0
        MOVE    R6, 0
        MOVE    R7, 0
        MOVE    R8, 0
        MOVE    R9, 0
        MOVE    R10, 0
        MOVE    R11, 0x600D
        MOVE    R13, 0
        MOVE    R14, 0
?!Z     HALT                    ; Z = 0: the HALT every check relies on
        MOVE    R11, 0          ; never runs
        HALT                    ; never runs

; ---- Routines and data --------------------------------------------------
subr    MOVE    R1, 0x5B        ; called by check 103
        MOVE    PC, @SP++

isr     MOVE    R4, R14         ; vectors 3 and 255, for checks 111-115
        MOVE[M] R6, 0           ; Z
        RTI

rdata   .DAT    0x11, 0x22, 0x33, 0x44
wdata   .BLK    9
        .BLK    4
stack

        .ORG    0xF03
        .DAT    isr
        .ORG    0xFFF
        .DAT    isr
