; Shift counts at the edges, and the C flag they leave (ISA.md §5.2, §6).
; Each case sets SR, runs one shift with M set, and stores the result and
; then SR at 0x200 onwards. SR flags as in carryin.nasm: V = 0x20000000,
; N = 0x10000000, Z = 0x08000000, C = 0x04000000, X = 0x02000000, and bit
; 24 = 0x01000000.
;
; Count 0 with a source that changes C. SR = 0x03FFFFFF has C = 0, and
; R14++ makes it 0x05000000, C = 1, in step 5.
;   C<0  0x03FFFFFF by 0: r = s0. C is written, so it is the C step 5
;        left, 1.                                   SR = 0x05000000 (C)
;   SHL  the same: C is not written, so C = 0.      SR = 0x01000000
;
; 33-bit rotations, where only n mod 33 counts.
;   C<C  0x12345678 by 66 = 2 * 33, C = 1: r = s0, C = 1. SR = 0x05000000
;   C>C  0x12345678 by 33, C = 1: r = s0, C = 1.          SR = 0x05000000
;   C>C  0x12345678 by 66, C = 0: r = s0, C = 0.          SR = 0x01000000
;   C<C  0x87654321 by 65 = 32 mod 33, C = 0. 32 steps left are one step
;        right in 33 bits: r = (C << 31) | (s0 >> 1) = 0x43B2A190, and
;        C = bit 0 of s0 = 1.                         SR = 0x05000000
;
; 32-bit rotations, where only n mod 32 counts, for n > 0.
;   >>C  0x40000001 by 2^32 - 1 = 31 mod 32, one step left: r =
;        0x80000002. C = bit 31 of r = 1.                 SR = 0x15000000
;   C<<  0x00000002 by 64 = 0 mod 32: r = s0, but n > 0, so C = bit 0 of
;        r = 0, not the C before, 1.                      SR = 0x01000000
;   <<<  0x80000001 by 2^32 - 1, C = 0: one step right, r = 0xC0000000.
;        C is not written: C = 0.                         SR = 0x11000000
;
; Fixed fills, where n >= 32 leaves all fill bits, n = 32 leaves C = the
; last bit of s0, and n > 32 leaves C = the fill bit.
;   C<1  0 by 2^32 - 1, C = 0: r = 0xFFFFFFFF, C = 1.     SR = 0x17000000
;   1>C  0 by 32, C = 1: r = 0xFFFFFFFF, C = bit 31 of s0 = 0.
;                                                         SR = 0x13000000
;   0>C  0xFFFFFFFF by 33, C = 1: r = 0, C = the fill, 0. SR = 0x09000000
;   0<1  0 by 64, C = 1: r = 0xFFFFFFFF, C = 0.           SR = 0x13000000
;   C>0  0x12345678 by 34, C = 1: the fill is the C before, so r =
;        0xFFFFFFFF, and C is not written: C = 0.         SR = 0x13000000
;
; Steps: 1 + 14 * 4 + 1 = 58. R13 = 0x200 + 28 = 0x21C, and R1 and R14
; hold the last case's values. HALT is word 0x62, so PC = 0x63. The dump
; shows the 14 pairs.
        MOVE    R13, 0x200
        MOVE    R14, 0x03FFFFFF
        C<0[M]  R1, R14++, 0
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x03FFFFFF
        SHL[M]  R1, R14++, 0
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        C<C[M]  R1, 0x12345678, 66
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        C>C[M]  R1, 0x12345678, 33
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0
        C>C[M]  R1, 0x12345678, 66
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0
        C<C[M]  R1, 0x87654321, 65
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0
        >>C[M]  R1, 0x40000001, 0xFFFFFFFF
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        C<<[M]  R1, 2, 64
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0
        <<<[M]  R1, 0x80000001, 0xFFFFFFFF
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0
        C<1[M]  R1, 0, 0xFFFFFFFF
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        1>C[M]  R1, 0, 32
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        0>C[M]  R1, 0xFFFFFFFF, 33
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        0<1[M]  R1, 0, 64
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        MOVE    R14, 0x04000000
        C>0[M]  R1, 0x12345678, 34
        MOVE    @R13++, R1
        MOVE    @R13++, R14
        HALT
