; The math unit at 0xFFFFFF20 (SYSTEM.md §2). For each pair A, B in the
; table, the loop writes A and B and copies the eight results, SMUL_LO to
; UDIV_R, to one dump line at 0x200 + 8k. In hex:
;
;   A           B           SMUL_LO  SMUL_HI  UMUL_LO  UMUL_HI  SDIV_Q   SDIV_R   UDIV_Q   UDIV_R
;   7           3           15       0        15       0        2        1        2        1
;   -7          2           fffffff2 ffffffff fffffff2 1        fffffffd ffffffff 7ffffffc 1
;   7           -2          fffffff2 ffffffff fffffff2 6        fffffffd 1        0        7
;   -7          -2          e        0        e        fffffff7 3        ffffffff 0        fffffff9
;   -1          -1          1        0        1        fffffffe 1        0        1        0
;   0x80000000  -1          80000000 0        80000000 7fffffff 80000000 0        0        80000000
;   0x80000000  0x80000000  0        40000000 0        40000000 1        0        1        0
;   0x7fffffff  0x7fffffff  1        3fffffff 1        3fffffff 1        0        1        0
;   -5          0           0        0        0        0        ffffffff fffffffb ffffffff fffffffb
;
; -7 * 2 = -14. 0xFFFFFFF9 * 2 = 0x1_FFFFFFF2. -7 / 2 = -3 rem -1: the
; quotient rounds toward zero and the remainder has the sign of A.
; 7 * 0xFFFFFFFE = 7 * 2^32 - 14 = 0x6_FFFFFFF2. 7 / -2 = -3 rem 1.
; (2^32 - 7)(2^32 - 2) = 2^64 - 9 * 2^32 + 14. -7 / -2 = 3 rem -1.
; (2^32 - 1)^2 = 0xFFFFFFFE_00000001.
; -2^31 * -1 = 2^31, and 2^31 * (2^32 - 1) = 0x7FFFFFFF_80000000. The
; signed -2^31 / -1 overflows: Q = 0x80000000, R = 0.
; 2^31 * 2^31 = 2^62 both ways, and -2^31 / -2^31 = 1.
; (2^31 - 1)^2 = 2^62 - 2^32 + 1 = 0x3FFFFFFF_00000001.
; Division by zero gives Q = 0xFFFFFFFF and R = A.
;
; After the loop: a write to UMUL_LO is ignored, so it still reads
; -5 * 0 = 0 (R1 = 0). The spare word 0xFFFFFF2A reads 0 (R2 = 0). Then
; A = 6 and B = 7 give UMUL_LO = 42 = 0x2a (R3), and A and B read back
; (R4 = 6, R5 = 7). The MPU stores nothing in memory. The dump of its
; words shows A, B, and the results for 6 and 7: 0x2a, 0, 0x2a, 0, 0, 6,
; 0, 6, then 0 in the six spare words.
;
; Steps: 3 + 9 * 13 + 9 = 129. R6 = 0x200 + 72 = 0x248, R7 = 0 with Z set
; (R14 = 0x09000000), R8 = CASES + 18 = 0x3d, and R9 = MPU + 10.
MPU     .EQU    0xFFFFFF20
        MOVE    R8, CASES
        MOVE    R6, 0x200
        MOVE    R7, 9
LOOP    MOVE    @MPU, @R8++
        MOVE    @MPU+1, @R8++
        MOVE    R9, MPU+2
        MOVE    @R6++, @R9++
        MOVE    @R6++, @R9++
        MOVE    @R6++, @R9++
        MOVE    @R6++, @R9++
        MOVE    @R6++, @R9++
        MOVE    @R6++, @R9++
        MOVE    @R6++, @R9++
        MOVE    @R6++, @R9++
        DEC[M]  R7, R7
    ?!Z MOVE    R15, LOOP
        MOVE    @MPU+4, 5
        MOVE    R1, @MPU+4
        MOVE    R2, @MPU+10
        MOVE    @MPU, 6
        MOVE    @MPU+1, 7
        MOVE    R3, @MPU+4
        MOVE    R4, @MPU
        MOVE    R5, @MPU+1
        HALT
CASES   .DAT    7, 3
        .DAT    0xFFFFFFF9, 2
        .DAT    7, 0xFFFFFFFE
        .DAT    0xFFFFFFF9, 0xFFFFFFFE
        .DAT    0xFFFFFFFF, 0xFFFFFFFF
        .DAT    0x80000000, 0xFFFFFFFF
        .DAT    0x80000000, 0x80000000
        .DAT    0x7FFFFFFF, 0x7FFFFFFF
        .DAT    0xFFFFFFFB, 0
