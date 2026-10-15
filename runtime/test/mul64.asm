; Run after start.asm. Calls __mul64 on each pair of 64-bit numbers in the
; table and stores the products, low word first, in results (0x48-0x57):
;
;   6 * 7                                   = 42
;   0 * 5                                   = 0
;   5 * 0                                   = 0
;   -1 * -1                                 = 1
;   2^32 * 2^32                             = 0     (2^64 wraps to 0)
;   0xFFFFFFFF * 0xFFFFFFFF                 = 0xFFFFFFFE_00000001
;                                             (2^64 - 2^33 + 1)
;   -3 * 5                                  = -15 = 0xFFFFFFFF_FFFFFFF1
;   0x123456789ABCDEF0 * 0x0FEDCBA987654321 = 0x2236D88F_E5618CF0 (mod 2^64)
;
; Code: start.asm is words 0-8, main 9-39, pairs 0x28-0x47, results 0x48.
; __mul64 takes 5 + 7k + 2j steps, where k is the number of bits in the
; second operand (1 if it is 0) and j its number of 1 bits: k = 3, 3, 1,
; 64, 33, 32, 3, 60 and j = 3, 2, 0, 64, 1, 32, 2, 32. So the calls take
; 8 * 5 + 7 * 199 + 2 * 136 = 1705 steps. A pass takes 11 steps besides
; __mul64. The total is 5 (start up) + 6 (set up) + 8 * 11 + 1705 + 1
; (return) + 1 (HALT) = 1806.
;
; At the end R1:R2 and R5:R6 hold the last product, and R3:R4 = 0, shifted
; out. R10-R12 survive the calls. R14 = 0x09000000: Z from the last DEC[M].
;
; That is mul64_soft.expected, with muldiv_soft.asm. With muldiv_mpu.asm,
; __mul64 takes 10 steps, so the total is 5 + 6 + 8 * (11 + 10) + 1 + 1
; = 181 (mul64.expected). R3:R4 keep the last operand, 0x0FEDCBA9_87654321,
; R6 = 0, and R5 = the high word of 0x9ABCDEF0 * 0x87654321 plus the low
; word of 0x9ABCDEF0 * 0x0FEDCBA9, mod 2^32: 0xB17E4B17.

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
        MOVE    R15, __mul64
        MOVE    @R8++, R1
        MOVE    @R8++, R2
        ADD     R7, R7, 4
        DEC[M]  R9, R9
        ?!Z MOVE R15, loop
        MOVE    R15, @R13++

; Each pair is a then b, each low word first.
pairs   .DAT    6, 0, 7, 0
        .DAT    0, 0, 5, 0
        .DAT    5, 0, 0, 0
        .DAT    0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
        .DAT    0, 1, 0, 1
        .DAT    0xFFFFFFFF, 0, 0xFFFFFFFF, 0
        .DAT    0xFFFFFFFD, 0xFFFFFFFF, 5, 0
        .DAT    0x9ABCDEF0, 0x12345678, 0x87654321, 0x0FEDCBA9
results .BLK    16
