; Run after start.asm. Calls __udiv, __umod, __div, and __mod on each pair
; in the table and stores the four results in results (0x4B-0x6A):
;
;                            __udiv      __umod      __div       __mod
;   100 / 7                  0x0000000E  0x00000002  0x0000000E  0x00000002
;   0xFFFFFFF9 / 2           0x7FFFFFFC  0x00000001  0xFFFFFFFD  0xFFFFFFFF
;                            (4294967289 = 2 * 2147483644 + 1; -7 / 2 = -3 rem -1)
;   7 / 0xFFFFFFFE           0x00000000  0x00000007  0xFFFFFFFD  0x00000001
;                            (7 / -2 = -3 rem 1)
;   0xFFFFFFFF / 0xFFFFFFFF  0x00000001  0x00000000  0x00000001  0x00000000
;   0x80000000 / 0xC0000000  0x00000000  0x80000000  0x00000002  0x00000000
;                            (-2^31 / -2^30 = 2)
;   0xFFFFFFFF / 0x80000001  0x00000001  0x7FFFFFFE  0x00000000  0xFFFFFFFF
;                            (-1 / -2147483647 = 0 rem -1)
;   0x12345678 / 0x1000      0x00012345  0x00000678  0x00012345  0x00000678
;   1000000007 / 13          0x0495C0C5  0x00000006  0x0495C0C5  0x00000006
;                            (13 * 76923077 = 1000000001)
;
; The divisors 0xC0000000 and 0x80000001 are above 2^31, so the remainder
; needs its bit 32 there.
;
; Code: start.asm is words 0-8, main 9-58, pairs 0x3B-0x4A, results 0x4B.
; Each call takes 5 steps besides the routine, which takes 292, 295, 301,
; and 302 steps, and the loop 3 more, so a pass takes 20 + 1190 + 3 = 1213.
; The total is 5 (start up) + 6 (set up) + 8 * 1213 + 1 (return) + 1 (HALT)
; = 9717.
;
; At the end R1 = R3 = 6, the last remainder, and R2 = 13. R4 = 0 after 32
; passes. The last quotient bit is 1, so the last pass subtracted: R5 = 6,
; and R6 = 0, as no remainder needed bit 32. R10-R12 survive the calls.
;
; That is div_soft.expected, with muldiv_soft.asm. With muldiv_mpu.asm,
; each routine takes 4 steps, so a pass takes 20 + 16 + 3 = 39, and the
; total is 5 + 6 + 8 * 39 + 1 + 1 = 325. R3-R6 stay 0 (div.expected).
; R14 = 0x09000000: Z from the last DEC[M].

_main   MOVE    R7, pairs
        MOVE    R8, results
        MOVE    R9, 8                   ; number of pairs
        MOVE    R10, 0xA
        MOVE    R11, 0xB
        MOVE    R12, 0xC
loop    MOVE    R1, @R7
        MOVE    R2, @1[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __udiv
        MOVE    @R8++, R1
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __umod
        MOVE    @R8++, R1
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __div
        MOVE    @R8++, R1
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __mod
        MOVE    @R8++, R1
        ADD     R7, R7, 2
        DEC[M]  R9, R9
        ?!Z MOVE R15, loop
        MOVE    R15, @R13++

pairs   .DAT    100, 7
        .DAT    0xFFFFFFF9, 2
        .DAT    7, 0xFFFFFFFE
        .DAT    0xFFFFFFFF, 0xFFFFFFFF
        .DAT    0x80000000, 0xC0000000
        .DAT    0xFFFFFFFF, 0x80000001
        .DAT    0x12345678, 0x1000
        .DAT    1000000007, 13
results .BLK    32
