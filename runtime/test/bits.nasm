; Run after start.nasm. For each 64-bit number v in the table, calls
; __clz, __ctz, and __popcnt on its low word, then __clz64, __ctz64, and
; __popcnt64 on v, and stores the 9 result words in results (0x54-0x89):
;
;   v                       clz ctz popcnt  clz64 ctz64 popcnt64
;   0                       32  32  0       64    64    0
;   1                       31  0   1       63    0     1
;   0x80000000              0   31  1       32    31    1
;   0x00010000_00000000     32  32  0       15    48    1
;   0xFFFFFFFF_FFFFFFFF     0   0   32      0     0     64
;   0x0F0F0000_000000F0     24  4   4       4     4     12
;
; The 64-bit results are pairs, so R2 = 0 follows each.
;
; Code: start.nasm is words 0-8, main 9-71, values 0x48-0x53, results 0x54.
; Steps, from the comments in lib.nasm, for the six routines on each value.
; __popcnt64 includes __popcnt on both words, for example 10 + 6 + 6 = 22
; for 0.
;   0:          3 + 3 + 6 + 10 + 11 + 22                  = 55
;   1:          7 + 6 + 6 + 14 + 12 + 22                  = 67
;   0x80000000: 100 + 130 + 99 + 107 + 136 + 115          = 687
;   2^48:       3 + 3 + 6 + 62 + 78 + 70                  = 222
;   all ones:   100 + 6 + 99 + 107 + 12 + 208             = 532
;   0x0F0F...:  28 + 22 + 27 + 95 + 28 + 124              = 324
; which sum to 1887. A pass takes 33 steps besides them. The total is 5
; (start up) + 6 (set up) + 6 * 33 + 1887 + 1 (return) + 1 (HALT) = 2098.
;
; At the end R1 = 12 and R2 = 0 from the last __popcnt64, which leaves the
; low word's count, 4, in R3, and the high word in R4. R10-R12 survive the
; calls. R14 = 0x09000000: Z from the last DEC[M].

_main   MOVE    R7, values
        MOVE    R8, results
        MOVE    R9, 6                   ; number of values
        MOVE    R10, 0xA
        MOVE    R11, 0xB
        MOVE    R12, 0xC
loop    MOVE    R1, @R7
        ADD     @--R13, 2, R15
        MOVE    R15, __clz
        MOVE    @R8++, R1
        MOVE    R1, @R7
        ADD     @--R13, 2, R15
        MOVE    R15, __ctz
        MOVE    @R8++, R1
        MOVE    R1, @R7
        ADD     @--R13, 2, R15
        MOVE    R15, __popcnt
        MOVE    @R8++, R1
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __clz64
        MOVE    @R8++, R1
        MOVE    @R8++, R2
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __ctz64
        MOVE    @R8++, R1
        MOVE    @R8++, R2
        MOVE    R1, @R7
        MOVE    R2, @1[R7]
        ADD     @--R13, 2, R15
        MOVE    R15, __popcnt64
        MOVE    @R8++, R1
        MOVE    @R8++, R2
        ADD     R7, R7, 2
        DEC[M]  R9, R9
        ?!Z MOVE R15, loop
        MOVE    R15, @R13++

; Low word first.
values  .DAT    0, 0
        .DAT    1, 0
        .DAT    0x80000000, 0
        .DAT    0, 0x00010000
        .DAT    0xFFFFFFFF, 0xFFFFFFFF
        .DAT    0x000000F0, 0x0F0F0000
results .BLK    54
