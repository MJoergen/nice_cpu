; The carry input at the edges of carry, borrow, and overflow (ISA.md §5.1,
; §6). Each case sets SR, runs one instruction with C = 1 and the C and M
; bits set, and stores the result and then SR at 0x200 onwards. The flags
; in SR: V = 0x20000000, N = 0x10000000, Z = 0x08000000, C = 0x04000000,
; X = 0x02000000, and bit 24 = 0x01000000.
;
;   SUB[CM]  0 - 0xFFFFFFFF - 1   = 0, unsigned -2^32: borrow. Signed
;            0 - (-1) - 1 = 0, no overflow.          r = 0, SR = 0x0D000000 (Z C)
;   SUB[CM]  0x80000000 - 0 - 1  = 0x7FFFFFFF, no borrow. Signed -2^31 - 1
;            overflows: a and b differ in sign, r differs from a.
;                                                    SR = 0x21000000 (V)
;   ADD[CM]  0xFFFFFFFF + 0xFFFFFFFF + 1 = 0x1_FFFFFFFF: r = 0xFFFFFFFF with
;            a carry. Signed -1 + -1 + 1 = -1.       SR = 0x17000000 (N C X)
;   MDBL[CM] 0x7FFFFFFF + (0x7FFFFFFF AND 0xFFFF) + 1 = 0x8000FFFF. No
;            carry. Both addends positive, r negative. SR = 0x31000000 (V N)
;   DBL[CM]  0x80000000 + 0x80000000 + 1 = 0x1_00000001: r = 1, a carry,
;            and both addends negative with r positive. SR = 0x25000000 (V C)
;   IAND[CM] (NOT 0x0F0F0F0F) AND 0xFFFF0000 = 0xF0F00000. The C bit is
;            ignored and C is cleared.               SR = 0x11000000 (N)
;   IOR[CM]  (NOT 0xFFFFFFFF) OR 0 = 0.              SR = 0x09000000 (Z)
;   XNOR[CM] NOT (0x12345678 XOR 0x12345678) = 0xFFFFFFFF.
;                                                    SR = 0x13000000 (N X)
;
; Steps: 1 + 8 * 4 + 1 = 34. R13 = 0x210, and R1 and R14 hold the last
; case's values. HALT is word 0x39, so PC = 0x3A. The dump shows the
; eight pairs of result and SR.
        MOVE    R13, 0x200
        MOVE    R14, 0x04000000
        SUB[CM] R1, 0, 0xFFFFFFFF
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        SUB[CM] R1, 0x80000000, 0
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        ADD[CM] R1, 0xFFFFFFFF, 0xFFFFFFFF
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        MDBL[CM] R1, 0x7FFFFFFF, 0x0000FFFF
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        DBL[CM] R1, 0x80000000
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        IAND[CM] R1, 0x0F0F0F0F, 0xFFFF0000
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        IOR[CM] R1, 0xFFFFFFFF, 0
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        XNOR[CM] R1, 0x12345678, 0x12345678
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        HALT
