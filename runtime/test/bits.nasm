; Run after start.nasm. For each 64-bit number v in the table, calls
; __clz, __ctz, and __popcnt on its low word, then __clz64, __ctz64, and
; __popcnt64 on v, and stores the 9 result words in results (0x40-0x75):
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
; Code: start.nasm is words 0-7, with its vectors at 6-7, main 8-51,
; values 0x34-0x3F, and results 0x40.
; Steps, from the comments in lib.nasm, for the six routines on each value.
; __popcnt64 includes __popcnt on both words, for example 8 + 6 + 6 = 20
; for 0.
;   0:          3 + 3 + 6 + 9 + 10 + 20                   = 51
;   1:          19 + 6 + 6 + 25 + 11 + 20                 = 87
;   0x80000000: 19 + 130 + 99 + 25 + 135 + 113            = 521
;   2^48:       3 + 3 + 6 + 25 + 77 + 68                  = 182
;   all ones:   19 + 6 + 99 + 25 + 11 + 206               = 366
;   0x0F0F...:  19 + 22 + 27 + 25 + 27 + 122              = 242
; which sum to 1449. A pass takes 27 steps besides them. The total is 4
; (start up) + 6 (set up) + 6 * 27 + 1449 + 1 (return) + 1 (HALT) = 1623,
; with muldiv_soft.nasm (bits_soft.expected). With muldiv_mpu.nasm,
; __clz, __ctz, and __popcnt take 3 steps each, so the values take
; 3 + 3 + 3 + 9 + 10 + 14 = 42 when the low word is 0 (0 and 2^48), and
; 3 + 3 + 3 + 9 + 8 + 14 = 40 for the other four, 244 in all, and the
; total is 4 + 6 + 6 * 27 + 244 + 1 + 1 = 418 (bits.expected).
;
; At the end R1 = 12 and R2 = 0 from the last __popcnt64, which leaves the
; low word's count, 4, in R3, and the high word in R4. R10-R12 survive the
; calls. R14 = 0x09000000: Z from the last DEC[M].

_main           MOVE    R7, values
                MOVE    R8, results
                MOVE    R9, 6           ; number of values
                MOVE    R10, 0xA
                MOVE    R11, 0xB
                MOVE    R12, 0xC
loop            MOVE    R1, @R7
                CALL    __clz
                MOVE    @R8++, R1
                MOVE    R1, @R7
                CALL    __ctz
                MOVE    @R8++, R1
                MOVE    R1, @R7
                CALL    __popcnt
                MOVE    @R8++, R1
                MOVE    R1, @R7
                MOVE    R2, @1[R7]
                CALL    __clz64
                MOVE    @R8++, R1
                MOVE    @R8++, R2
                MOVE    R1, @R7
                MOVE    R2, @1[R7]
                CALL    __ctz64
                MOVE    @R8++, R1
                MOVE    @R8++, R2
                MOVE    R1, @R7
                MOVE    R2, @1[R7]
                CALL    __popcnt64
                MOVE    @R8++, R1
                MOVE    @R8++, R2
                ADD     R7, R7, 2
                DEC[M]  R9, R9
        ?!Z     JMP     loop
                RET

; Low word first.
values          .DAT    0, 0
                .DAT    1, 0
                .DAT    0x80000000, 0
                .DAT    0, 0x00010000
                .DAT    0xFFFFFFFF, 0xFFFFFFFF
                .DAT    0x000000F0, 0x0F0F0000
results         .BLK    54
