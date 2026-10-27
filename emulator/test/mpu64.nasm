; The 64-bit division of the math unit at 0xFFFFFF30 (SYSTEM.md §2). For
; each pair C, D in the table, the loop writes C and D, low word first, and
; copies the eight result words, SDIV64_Q_LO to UDIV64_R_HI, to one dump
; line at 0x200 + 8k. In hex, each 64-bit result low word first:
;
;   C / D                        SDIV64_Q          SDIV64_R          UDIV64_Q          UDIV64_R
;   100 / 7                      e 0               2 0               e 0               2 0
;   -7 / 2                       fffffffd ffffffff ffffffff ffffffff fffffffc 7fffffff 1 0
;   7 / -2                       fffffffd ffffffff 1 0               0 0               7 0
;   -2^63 / -1                   0 80000000        0 0               0 0               0 80000000
;   -5 / 0                       ffffffff ffffffff fffffffb ffffffff ffffffff ffffffff fffffffb ffffffff
;   0x12345678_9abcdef0 / 2^32   12345678 0        9abcdef0 0        12345678 0        9abcdef0 0
;   (2^40 + 3) / 2^20            100000 0          3 0               100000 0          3 0
;   -(2^40 + 3) / 2^20           fff00000 ffffffff fffffffd ffffffff ffefffff fff      fffffd 0
;   (2^63 - 1) / 3               aaaaaaaa 2aaaaaaa 1 0               aaaaaaaa 2aaaaaaa 1 0
;
; -7 / 2 = -3 rem -1, rounding toward zero, and 2^64 - 7 = 2 *
; 0x7FFFFFFF_FFFFFFFC + 1. 7 / -2 = -3 rem 1, and 7 < 2^64 - 2. The signed
; -2^63 / -1 overflows: Q = -2^63, R = 0. Unsigned, 2^63 < 2^64 - 1.
; Division by zero gives Q = all ones and R = C. 2^40 + 3 = 2^20 * 2^20 + 3.
; -(2^40 + 3) / 2^20 = -2^20 rem -3. Unsigned, 2^64 - 2^40 - 3 =
; (2^44 - 2^20 - 1) * 2^20 + 2^20 - 3, and 2^44 - 2^20 - 1 =
; 0xFFF_FFEFFFFF. 3 * 0x2AAAAAAA_AAAAAAAA = 2^63 - 2.
;
; The dump of the MPU's 32 words then shows A = B = 0 and their results,
; which the 64-bit operands do not change: products 0, and 0 / 0 gives
; Q = 0xFFFFFFFF and R = 0. Then C and D of the last case and its results,
; and 0 in the four spare words.
;
; Steps: 3 + 9 * 15 + 1 = 139. R6 = 0x200 + 72 = 0x248, R7 = 0 with Z set
; (R14 = 0x09000000), R8 = CASES + 36, and R9 = MPU + 0x1C.
MPU             .EQU    0xFFFFFF20
                MOVE    R8, CASES
                MOVE    R6, 0x200
                MOVE    R7, 9
LOOP            MOVE    @MPU+0x10, @R8++
                MOVE    @MPU+0x11, @R8++
                MOVE    @MPU+0x12, @R8++
                MOVE    @MPU+0x13, @R8++
                MOVE    R9, MPU+0x14
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                DEC[M]  R7, R7
        ?!Z     MOVE    R15, LOOP
                HALT
CASES           .DAT    100, 0, 7, 0
                .DAT    0xFFFFFFF9, 0xFFFFFFFF, 2, 0
                .DAT    7, 0, 0xFFFFFFFE, 0xFFFFFFFF
                .DAT    0, 0x80000000, 0xFFFFFFFF, 0xFFFFFFFF
                .DAT    0xFFFFFFFB, 0xFFFFFFFF, 0, 0
                .DAT    0x9ABCDEF0, 0x12345678, 0, 1
                .DAT    3, 0x100, 0x100000, 0
                .DAT    0xFFFFFFFD, 0xFFFFFEFF, 0x100000, 0
                .DAT    0xFFFFFFFF, 0x7FFFFFFF, 3, 0
