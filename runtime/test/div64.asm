; Run after start.asm. Calls __udiv64, __umod64, __div64, and __mod64 on
; each pair of 64-bit numbers in the table, and stores the four results,
; low word first, in results (0x6F-0xAE):
;
;   a / b                     __udiv64  __umod64  __div64  __mod64
;   100 / 7                   14        2         14       2
;   -7 / 2                    2^63 - 4  1         -3       -1
;                             (2^64 - 7 = 2 * (2^63 - 4) + 1)
;   2^32 / 3                  0x55555555, rem 1, both ways
;   0x123456789ABCDEF0 / 2^32 0x12345678, rem 0x9ABCDEF0, both ways
;   2^63 / 0xC000000000000000 0         2^63      2        0
;                             (-2^63 / -2^62 = 2)
;   (2^64 - 1) / (2^63 + 1)   1         2^63 - 2  0        -1
;                             (-1 / -(2^63 - 1) = 0 rem -1)
;   (10^18 + 7) / (10^9 + 7)  999999993 = 0x3B9AC9F9, rem 56, both ways
;                             ((10^9 + 7)(10^9 - 7) = 10^18 - 49)
;   7 / -2                    0         7         -3       1
;
; The divisors 0xC000000000000000 and 2^63 + 1 are above 2^63, so the
; remainder needs its bit 64 there.
;
; Code: start.asm is words 0-8, main 9-78, pairs 0x4F-0x6E, results 0x6F.
; Each call takes 8 steps besides the routine, and the loop 3 more. The
; routines take 839 (__udiv64), 843 (__umod64), and for __div64 and
; __mod64 1 + a + b + 2 + 838 + q and 1 + a + b + 2 + 838 + 2 + q (see
; muldiv_soft.asm). So the passes take 3378, 3388, 3378, 3378, 3389, 3389, 3378,
; and 3385 steps in the routines, 27063 in all, plus 8 * 35 = 280. The
; total is 5 (start up) + 6 (set up) + 27063 + 280 + 1 (return) + 1 (HALT)
; = 27356.
;
; At the end R1:R2 = 1, the last remainder, which R5:R6 also holds, and
; R3:R4 = 2, the divisor's absolute value. R10-R12 survive the calls. R14 =
; 0x09000000: Z from the last DEC[M].
;
; That is div64_soft.expected, with muldiv_soft.asm. With muldiv_mpu.asm,
; each routine takes 7 steps, so the total is 5 + 6 + 8 * (35 + 4 * 7) + 1
; + 1 = 517. R3:R4 keep the last divisor, -2, and R5:R6 stay 0
; (div64.expected).

_main   MOVE    R7, pairs
        MOVE    R8, results
        MOVE    R9, 8                   ; number of pairs
        MOVE    R10, 0xA
        MOVE    R11, 0xB
        MOVE    R12, 0xC
loop    MOVE    R1, @R7
        MOVE    R2, @1[R7]
        MOVE    R3, @2[R7]
        MOVE    R4, @3[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __udiv64
        MOVE    @R8++, R1
        MOVE    @R8++, R2
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        MOVE    R3, @2[R7]
        MOVE    R4, @3[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __umod64
        MOVE    @R8++, R1
        MOVE    @R8++, R2
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        MOVE    R3, @2[R7]
        MOVE    R4, @3[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __div64
        MOVE    @R8++, R1
        MOVE    @R8++, R2
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        MOVE    R3, @2[R7]
        MOVE    R4, @3[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __mod64
        MOVE    @R8++, R1
        MOVE    @R8++, R2
        ADD     R7, R7, 4
        DEC[M]  R9, R9
        ?!Z MOVE R15, loop
        MOVE    R15, @R13++

; Each pair is a then b, each low word first.
pairs   .DAT    100, 0, 7, 0
        .DAT    0xFFFFFFF9, 0xFFFFFFFF, 2, 0
        .DAT    0, 1, 3, 0
        .DAT    0x9ABCDEF0, 0x12345678, 0, 1
        .DAT    0, 0x80000000, 0, 0xC0000000
        .DAT    0xFFFFFFFF, 0xFFFFFFFF, 1, 0x80000000
        .DAT    0xA7640007, 0x0DE0B6B3, 1000000007, 0
        .DAT    7, 0, 0xFFFFFFFE, 0xFFFFFFFF
results .BLK    64
