; Run after start.nasm. The corner cases of the multiply and divide
; routines: division by zero, the most negative number divided by -1 and
; by 1, operands at the sign boundary, and __mul64 with high words set and
; negative operands. Calls __udiv, __umod, __div, and __mod on each pair of
; pairs32, then __udiv64, __umod64, __div64, and __mod64 on each pair of
; pairs64, then __mul64 on each pair of pairs_mul, and stores the results
; in that order in results (0xD8-0x153).
;
; One word, M = 0x80000000, the most negative number:
;
;   a / b                    __udiv      __umod      __div       __mod
;   7 / 0                    0xFFFFFFFF  0x00000007  0xFFFFFFFF  0x00000007
;   -7 / 0                   0xFFFFFFFF  0xFFFFFFF9  0xFFFFFFFF  0xFFFFFFF9
;   0 / 0                    0xFFFFFFFF  0x00000000  0xFFFFFFFF  0x00000000
;   M / 0                    0xFFFFFFFF  0x80000000  0xFFFFFFFF  0x80000000
;   M / -1                   0x00000000  0x80000000  0x80000000  0x00000000
;   M / 1                    0x80000000  0x00000000  0x80000000  0x00000000
;   M / M                    0x00000001  0x00000000  0x00000001  0x00000000
;   0x7FFFFFFF / -1          0x00000000  0x7FFFFFFF  0x80000001  0x00000000
;   (M + 1) / 2              0x40000000  0x00000001  0xC0000001  0xFFFFFFFF
;   M / 0x7FFFFFFF           0x00000001  0x00000001  0xFFFFFFFF  0xFFFFFFFF
;   5 / M                    0x00000000  0x00000005  0x00000000  0x00000005
;
; Division by zero: the math unit gives a quotient of all ones and a
; remainder equal to the dividend, signed and unsigned (SYSTEM.md §2).
; muldiv_soft.nasm gives the same for __udiv, __umod, and __mod. Its __div
; divides the absolute values, which gives all ones, and negates that when
; the signs differ. The sign of 0 counts as positive, so for a negative
; dividend, -7 and M, __div gives -0xFFFFFFFF = 1 instead. C leaves the
; result undefined, and README.md says only that it is some value, so both
; are right; they just differ. __mod of M by 0 is M in both: |M| = M.
;
; M / -1 is M rem 0 in both, as README.md says. In muldiv_soft.nasm, |M| =
; M as an unsigned number, M / 1 = M, and negating M gives M. Then
; 0x7FFFFFFF / -1 = -0x7FFFFFFF = 0x80000001. (M + 1) / 2 is -2147483647 /
; 2 = -1073741823 = 0xC0000001 rem -1; unsigned, 0x80000001 = 2 *
; 0x40000000 + 1. M / 0x7FFFFFFF is -1 rem -1 signed and 1 rem 1 unsigned.
; 5 / M is 0 rem 5 both ways.
;
; Two words, with N = 2^63, the most negative number. Each result is
; shown high word first; results holds it low word first.
;
;   a / b                    __udiv64             __umod64
;   7 / 0                    0xFFFFFFFF_FFFFFFFF  7
;   -7 / 0                   0xFFFFFFFF_FFFFFFFF  0xFFFFFFFF_FFFFFFF9
;   N / 0                    0xFFFFFFFF_FFFFFFFF  0x80000000_00000000
;   N / -1                   0                    0x80000000_00000000
;   N / 1                    0x80000000_00000000  0
;   (N - 1) / -1             0                    0x7FFFFFFF_FFFFFFFF
;   (N + 1) / 2              0x00000000_40000000  1
;   -2^32 / 3                0x55555555_00000000  0
;   -1 / 2^32                0x00000000_FFFFFFFF  0x00000000_FFFFFFFF
;
;   a / b                    __div64              __mod64
;   7 / 0                    0xFFFFFFFF_FFFFFFFF  7
;   -7 / 0                   0xFFFFFFFF_FFFFFFFF  -7
;   N / 0                    0xFFFFFFFF_FFFFFFFF  0x80000000_00000000
;   N / -1                   0x80000000_00000000  0
;   N / 1                    0x80000000_00000000  0
;   (N - 1) / -1             0x80000000_00000001  0
;   (N + 1) / 2              0xC0000000_00000001  -1
;   -2^32 / 3                0xFFFFFFFF_AAAAAAAB  -1
;   -1 / 2^32                0                    -1
;
; As with one word, muldiv_soft.nasm's __div64 gives 1 = 0x00000000_00000001
; for -7 / 0 and N / 0. (N + 1) / 2 is -(2^63 - 1) / 2 = -(2^62 - 1) rem
; -1, as 2^63 - 1 = 2 * (2^62 - 1) + 1; unsigned, 2^63 + 1 = 2 * 2^62 + 1.
; -2^32 / 3: 3 * 0x55555555 = 2^32 - 1, so the quotient is -0x55555555 =
; 0xFFFFFFFF_AAAAAAAB rem -1; unsigned, 0xFFFFFFFF_00000000 / 3 =
; 0x55555555_00000000 rem 0. Its absolute value 2^32 has a low word of 0,
; so negating it in muldiv_soft.nasm borrows nothing from the high word.
; -1 / 2^32 unsigned is (2^64 - 1) / 2^32 = 2^32 - 1 rem 2^32 - 1.
;
; __mul64, the low 64 bits, high word first:
;
;   0xFFFFFFFE_00000003 * 0x00000002_00000005 = 0xFFFFFFFC_0000000F
;       ((3 - 2^33) * (5 + 2^33) = 15 - 2^34 - 2^66, and 2^66 = 0 mod 2^64)
;   -1 * N                                    = 0x80000000_00000000 (-N = N)
;   N * 2                                     = 0                   (2^64)
;   0x00000001_FFFFFFFF ^ 2                   = 0xFFFFFFFC_00000001
;       ((2^33 - 1)^2 = 2^66 - 2^34 + 1)
;
; In muldiv_mpu.nasm, the last one adds the high word of 0xFFFFFFFF *
; 0xFFFFFFFF, 0xFFFFFFFE, and the low words of 0xFFFFFFFF * 1, twice:
; 0xFFFFFFFE + 0xFFFFFFFF + 0xFFFFFFFF = 0xFFFFFFFC mod 2^32.
;
; Steps with muldiv_mpu.nasm: 5 (start up), 10 to set up the three loops,
; 11 passes of 20 + 4 * 4 + 3 = 39, 9 passes of 32 + 4 * 7 + 3 = 63, 4
; passes of 11 + 10 = 21, the return, and HALT: 5 + 10 + 429 + 567 + 84 +
; 1 + 1 = 1097. At the end R1:R2 = the last product, R3:R4 its second
; operand, and R5 = 0xFFFFFFFE + 0xFFFFFFFF = 0xFFFFFFFD, as in __mul64 of
; muldiv_mpu.nasm. R6 stays 0 (edge.expected).
;
; Steps with muldiv_soft.nasm, from the comments there. A pass of the
; first loop takes 20 + 292 + 295 + 301 + 302 + 3 = 1213 steps, whatever
; the operands, so 11 take 13343. The second loop takes 9 * 35 = 315
; besides the routines, 9 * 839 = 7551 in __udiv64, and 9 * 843 = 7587 in
; __umod64. __div64 takes 1 + a + b + 2 + 838 + q, and __mod64 2 more,
; with a and b 2 for an operand that is not negative and 4 for one that
; is, and q 2 for a result that is not negated and 5 for one that is:
; __div64 negates when the signs differ, __mod64 when the dividend is
; negative. So:
;
;   7 / 0           a 2  b 2  __div64 q 2: 847   __mod64 q 2: 849
;   -7 / 0          a 4  b 2  q 5: 852           q 5: 854
;   N / 0           as -7 / 0: 852               854
;   N / -1          a 4  b 4  q 2: 851           q 5: 856
;   N / 1           852                          854
;   (N - 1) / -1    a 2  b 4  q 5: 852           q 2: 851
;   (N + 1) / 2, -2^32 / 3, -1 / 2^32: 852 each  854 each
;
; which sum to 7662 and 7680. So the second loop takes 315 + 7551 + 7587 +
; 7662 + 7680 = 30795 steps. __mul64 takes 5 + 7k + 2j, where k is the
; number of bits of the second operand and j its number of 1 bits: k = 34,
; 64, 2, 33 and j = 3, 1, 1, 33, so 249 + 455 + 21 + 302 = 1027, and the
; third loop 4 * 11 + 1027 = 1071. The total is 5 + 10 + 13343 + 30795 +
; 1071 + 1 + 1 = 45226. At the end R1:R2 and R5:R6 hold the last product,
; and R3:R4 = 0, shifted out (edge_soft.expected).
;
; Code: start.nasm is words 0-8, main 9-0x8D, pairs32 0x8E, pairs64 0xA4,
; pairs_mul 0xC8, and results 0xD8. Both: R7 = 0xD8, the end of pairs_mul,
; R8 = 0x154, the end of results, R9 = 0, and
; R10-R12 survive the calls. R14 = 0x09000000: Z from the last DEC[M].

_main           MOVE    R7, pairs32
                MOVE    R8, results
                MOVE    R9, 11          ; number of pairs
                MOVE    R10, 0xA
                MOVE    R11, 0xB
                MOVE    R12, 0xC
loop32          MOVE    R1, @R7
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
        ?!Z     MOVE    R15, loop32

                MOVE    R7, pairs64
                MOVE    R9, 9
loop64          MOVE    R1, @R7
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
        ?!Z     MOVE    R15, loop64

                MOVE    R7, pairs_mul
                MOVE    R9, 4
loopmul         MOVE    R1, @R7
                MOVE    R2, @1[R7]
                MOVE    R3, @2[R7]
                MOVE    R4, @3[R7]
                ADD     @--R13, 2, R15
                MOVE    R15, __mul64
                MOVE    @R8++, R1
                MOVE    @R8++, R2
                ADD     R7, R7, 4
                DEC[M]  R9, R9
        ?!Z     MOVE    R15, loopmul
                MOVE    R15, @R13++

pairs32         .DAT    7, 0
                .DAT    0xFFFFFFF9, 0
                .DAT    0, 0
                .DAT    0x80000000, 0
                .DAT    0x80000000, 0xFFFFFFFF
                .DAT    0x80000000, 1
                .DAT    0x80000000, 0x80000000
                .DAT    0x7FFFFFFF, 0xFFFFFFFF
                .DAT    0x80000001, 2
                .DAT    0x80000000, 0x7FFFFFFF
                .DAT    5, 0x80000000

; Each pair is a then b, each low word first.
pairs64         .DAT    7, 0, 0, 0
                .DAT    0xFFFFFFF9, 0xFFFFFFFF, 0, 0
                .DAT    0, 0x80000000, 0, 0
                .DAT    0, 0x80000000, 0xFFFFFFFF, 0xFFFFFFFF
                .DAT    0, 0x80000000, 1, 0
                .DAT    0xFFFFFFFF, 0x7FFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
                .DAT    1, 0x80000000, 2, 0
                .DAT    0, 0xFFFFFFFF, 3, 0
                .DAT    0xFFFFFFFF, 0xFFFFFFFF, 0, 1

pairs_mul
                .DAT    3, 0xFFFFFFFE, 5, 2
                .DAT    0xFFFFFFFF, 0xFFFFFFFF, 0, 0x80000000
                .DAT    0, 0x80000000, 2, 0
                .DAT    0xFFFFFFFF, 1, 0xFFFFFFFF, 1
results         .BLK    124
