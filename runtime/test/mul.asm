; Run after start.asm. Calls __mul on each pair in the table and stores the
; products in results (0x32-0x3B):
;
;   6 * 7                   = 0x0000002A
;   0 * 5                   = 0
;   5 * 0                   = 0
;   0xFFFFFFFF * 0xFFFFFFFF = 1             (-1 * -1)
;   0x10000 * 0x10000       = 0             (2^32 wraps to 0)
;   0xFFFFFFFF * 7          = 0xFFFFFFF9    (-1 * 7 = -7)
;   0x80000000 * 3          = 0x80000000
;   1 * 0x80000000          = 0x80000000
;   0xFFFFFFFD * 0xFFFFFFFB = 0x0000000F    (-3 * -5 = 15)
;   0x12345678 * 0x9ABCDEF0 = 0x242D2080
;
; R10-R12 must survive the calls. Each __mul takes 3 + 4k steps, where k is
; the number of bits in R2: 3, 3, 1, 32, 17, 3, 2, 32, 32, and 32, which
; sum to 157. A pass of the loop takes 7 steps besides __mul. So the total is
; 3 (start up) + 6 (set up) + 10 * (7 + 3) + 4 * 157 + 1 (return) + 1 (HALT)
; = 739.
;
; At the end R2 = 0 and R3 = 0, because the last R2 has 32 bits, so both
; were shifted 32 times. R14 = 0x09000000: Z from the last DEC[M].

_main   MOVE    R7, pairs
        MOVE    R8, results
        MOVE    R9, 10                  ; number of pairs
        MOVE    R10, 0xA
        MOVE    R11, 0xB
        MOVE    R12, 0xC
loop    MOVE    R1, @R7++
        MOVE    R2, @R7++
        ADD     @--R13, 2, R15
        MOVE    R15, __mul
        MOVE    @R8++, R1
        DEC[M]  R9, R9
        ?!Z MOVE R15, loop
        MOVE    R15, @R13++

pairs   .DAT    6, 7
        .DAT    0, 5
        .DAT    5, 0
        .DAT    0xFFFFFFFF, 0xFFFFFFFF
        .DAT    0x10000, 0x10000
        .DAT    0xFFFFFFFF, 7
        .DAT    0x80000000, 3
        .DAT    1, 0x80000000
        .DAT    0xFFFFFFFD, 0xFFFFFFFB
        .DAT    0x12345678, 0x9ABCDEF0
results .BLK    10
