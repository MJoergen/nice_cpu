; The bit counts and the square root of the math unit (DEVICES.md §2). For
; each A in AS, the first loop writes A and copies A, CLZ, CTZ, and POPCNT
; to four words at 0x200 + 4k. In hex:
;
;   A           CLZ  CTZ  POPCNT
;   0           20   20   0
;   1           1f   0    1
;   0x80000000  0    1f   1
;   0xffffffff  0    0    20
;   0x00010000  f    10   1
;   0x00f00f00  8    8    8
;   0x7ffffffe  1    1    1e
;   0x12345678  3    3    d
;
; 0x00F00F00 has two runs of 4 ones, from bit 23 down and from bit 11
; down. 0x12345678 is 0001 0010 0011 0100 0101 0110 0111 1000, with
; 1 + 1 + 2 + 1 + 2 + 2 + 3 + 1 = 13 ones.
;
; For each C in CS, low word first, the second loop writes C and copies
; ISQRT64_Q, ISQRT64_R_LO, ISQRT64_R_HI, and the spare word after them to
; four words at 0x220 + 4k. Q = floor(sqrt(C)), and R = C - Q^2:
;
;   C                        Q         R
;   0                        0         0
;   1                        1         0
;   2                        1         1
;   99                       9         0x12 (99 = 81 + 18)
;   2^64 - 1                 ffffffff  1_fffffffe (2^64 - 1 = (2^32 - 1)^2 + 2 * (2^32 - 1))
;   (2^32 - 1)^2             ffffffff  0 (0xFFFFFFFE_00000001)
;   2^62                     80000000  0
;   10^18                    3b9aca00  0 (0x0DE0B6B3_A7640000 = (10^9)^2)
;
; The spare word reads 0 throughout.
;
; After the loops: a write to B leaves CLZ of A = 0x12345678 at 3 (R1), a
; write to D leaves ISQRT64_Q of C = 10^18 at 0x3B9ACA00 (R2), and a
; write to CLZ is ignored, so it still reads 3 (R3).
;
; Steps: 3 + 8 * 7 + 1 + 8 * 8 + 7 = 131. R6 = 0x240, R7 = 0 with Z set
; (R14 = 0x09000000), and R8 = CS + 16 = the end of the program.
MPU             .EQU    0xFFFFFF20
                MOVE    R8, AS
                MOVE    R6, 0x200
                MOVE    R7, 8
:               MOVE    @MPU, @R8++
                MOVE    @R6++, @MPU
                MOVE    @R6++, @MPU+10
                MOVE    @R6++, @MPU+11
                MOVE    @R6++, @MPU+12
                DEC[M]  R7, R7
        ?!Z     JMP     :-
                MOVE    R7, 8
:               MOVE    @MPU+0x10, @R8++
                MOVE    @MPU+0x11, @R8++
                MOVE    @R6++, @MPU+0x1C
                MOVE    @R6++, @MPU+0x1D
                MOVE    @R6++, @MPU+0x1E
                MOVE    @R6++, @MPU+0x1F
                DEC[M]  R7, R7
        ?!Z     JMP     :-
                MOVE    @MPU+1, 5
                MOVE    R1, @MPU+10
                MOVE    @MPU+0x12, 5
                MOVE    R2, @MPU+0x1C
                MOVE    @MPU+10, 7
                MOVE    R3, @MPU+10
                HALT
AS              .DAT    0, 1, 0x80000000, 0xFFFFFFFF, 0x00010000, 0x00F00F00, 0x7FFFFFFE
                .DAT    0x12345678
CS              .DAT    0, 0
                .DAT    1, 0
                .DAT    2, 0
                .DAT    99, 0
                .DAT    0xFFFFFFFF, 0xFFFFFFFF
                .DAT    0x00000001, 0xFFFFFFFE
                .DAT    0, 0x40000000
                .DAT    0xA7640000, 0x0DE0B6B3
