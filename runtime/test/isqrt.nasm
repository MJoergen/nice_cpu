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
; Code: start.nasm is words 0-7, with its vectors at 6-7, main
; 0x08-0x23, values 0x24-0x3B, and results 0x3C-0x47.
;
; Steps: a pass of the loop is 7 steps besides the routine. With
; muldiv_soft.nasm (isqrt_soft.expected), _nice_isqrt64 takes 584 steps,
; so the total is 4 (start up) + 3 (set up) + 12 * (7 + 584) + 6 (clear)
; + 1 (return) + 1 (HALT) = 7107. With muldiv_mpu.nasm (isqrt.expected),
; it takes 4, and the total is 4 + 3 + 12 * 11 + 6 + 2 = 147.
;
; At the end R7 = 0x3C, the end of the table, R8 = 0x48, that of
; results, and R9 = 0, with Z set (R14 = 0x09000000). R13 = 0xFFFFFF00:
; the routine leaves the stack as it found it.

_main           MOVE    R7, values
                MOVE    R8, results
                MOVE    R9, 12          ; number of values
:               MOVE    R1, @R7
                MOVE    R2, @1[R7]
                CALL    _nice_isqrt64
                MOVE    @R8++, R1
                ADD     R7, R7, 2
                DEC[M]  R9, R9
        ?!Z     JMP     :-
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
