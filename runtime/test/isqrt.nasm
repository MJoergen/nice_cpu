; Run after start.nasm. Calls _nice_isqrt64 on each 64-bit value in the
; table, low word first, and stores the 12 roots in results:
;
;   value                   floor(sqrt(value))
;   0, 1, 2, 3, 4           0, 1, 1, 1, 2
;   99                      9
;   2^64 - 1                0xFFFFFFFF
;   (2^32 - 1)^2            0xFFFFFFFF (0xFFFFFFFE_00000001)
;   (2^32 - 1)^2 - 1        0xFFFFFFFE (0xFFFFFFFE_00000000)
;   2^62                    0x80000000
;   10^18                   0x3B9ACA00 = 10^9 (0x0DE0B6B3_A7640000)
;   10^18 - 1               0x3B9AC9FF = 10^9 - 1
;
; The squares and the squares less 1 give the roots on either side of
; each step. main then clears R1-R6, which the routine may change, so
; that the registers do not show how it works.
;
; Code: start.nasm is words 0-10, with its vectors at 9-10, main
; 0x0B-0x2A, values 0x2B-0x42, and results 0x43-0x4E.
;
; Steps: a pass of the loop is 8 steps besides the routine. With
; muldiv_soft.nasm (isqrt_soft.expected), _nice_isqrt64 takes 584 steps,
; so the total is 5 (start up) + 3 (set up) + 12 * (8 + 584) + 6 (clear)
; + 1 (return) + 1 (HALT) = 7120. With muldiv_mpu.nasm (isqrt.expected),
; it takes 4, and the total is 5 + 3 + 12 * 12 + 6 + 2 = 160.
;
; At the end R7 = 0x43, the end of the table, R8 = 0x4F, that of
; results, and R9 = 0, with Z set (R14 = 0x09000000). R13 = 0xFFFFFF00:
; the routine leaves the stack as it found it.

_main           MOVE    R7, values
                MOVE    R8, results
                MOVE    R9, 12          ; number of values
loop            MOVE    R1, @R7
                MOVE    R2, @1[R7]
                CALL    _nice_isqrt64
                MOVE    @R8++, R1
                ADD     R7, R7, 2
                DEC[M]  R9, R9
        ?!Z     JMP     loop
                MOVE    R1, 0
                MOVE    R2, 0
                MOVE    R3, 0
                MOVE    R4, 0
                MOVE    R5, 0
                MOVE    R6, 0
                RET

values          .DAT    0, 0
                .DAT    1, 0
                .DAT    2, 0
                .DAT    3, 0
                .DAT    4, 0
                .DAT    99, 0
                .DAT    0xFFFFFFFF, 0xFFFFFFFF
                .DAT    0x00000001, 0xFFFFFFFE
                .DAT    0x00000000, 0xFFFFFFFE
                .DAT    0, 0x40000000
                .DAT    0xA7640000, 0x0DE0B6B3
                .DAT    0xA763FFFF, 0x0DE0B6B3
results         .BLK    12
