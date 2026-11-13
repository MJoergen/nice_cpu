; Numbers printed through the FPU's DIGITS 15 (SYSTEM.md §11.3), and one
; read back through FROMBCD and SCALE10, so that the console's output can
; be checked by eye. PRINT writes X as d.ddddddddddddddE±eee and a line
; feed, and pops it: the sign from the class of X, the 15 digits from
; bits 63..4 of the BCD, and the exponent in three digits through the
; math unit's UDIV.
;
;   value                       its digits                  printed
;   π = 3.14159265358979|32...  rounds down                 3.14159265358979E+000
;   -0.1 = -0.10000000000000000555...                       -1.00000000000000E-001
;   2^-1074 = 4.94065645841246|54...e-324, rounds up        4.94065645841247E-324
;   MAX = 1.79769313486231|57...e308, rounds up             1.79769313486232E+308
;   -0: the digits of a zero are 0, and e = 0               -0.00000000000000E+000
;   2^-1022 = 2.22507385850720|14...e-308, rounds down      2.22507385850720E-308
;
; Then the digits 602214076000000 and e = 23, as BASIC keeps a typed
; constant: FROMBCD of them, with 0 in the 16th digit, is 6022140760000000,
; and SCALE10 by e - 15 = 8 multiplies by 10^8, rounded once, which prints
; as 6.02214076000000E+023.
;
; Steps: PRINT takes 12, 14 * 8 in its loop, and 15, 139 in all. The main
; loop takes 6 + 139 for each of the 6 values, the read back 5, the CALL
; 2, PRINT 139, and the HALT 1, and the start 3: 3 + 870 + 147 = 1020.
; PC = 37 = 0x25 after the HALT at 36, where PRINT starts, 84 words long,
; and VALUES at 121. After the last PRINT: R1 = '+' = 0x2B, R2 = 23 =
; 0x17, R3 and R4 = 0, as the 14 shifts of R3:R4 left by 4 leave its low
; byte, 0x00, on top, R5 = 0, R10 = VALUES + 12 = 0x85, R11 = 0, and
; R13 = 0x1000. The last flags are those of MOVE[M] R0, R2 with 23: none,
; so R14 = 0x01000000.
CONSOLE         .EQU    0xFFFFFF00
MPU_A           .EQU    0xFFFFFF20
MPU_B           .EQU    0xFFFFFF21
MPU_UDIV_Q      .EQU    0xFFFFFF28
MPU_UDIV_R      .EQU    0xFFFFFF29
FPU_X_LO        .EQU    0xFFFFFF88
FPU_X_HI        .EQU    0xFFFFFF89
FPU_X_W         .EQU    0xFFFFFF8B
FPU_CMD         .EQU    0xFFFFFF8C
FPU_STATUS      .EQU    0xFFFFFF8D
                MOVE    R13, 0x1000
                MOVE    R10, VALUES
                MOVE    R11, 6
:               MOVE    @FPU_X_LO, @R10++
                MOVE    @FPU_X_HI, @R10++
                CALL    PRINT
                DEC[M]  R11, R11
        ?!Z     JMP     :-
                MOVE    @FPU_X_LO, 0x60000000
                MOVE    @FPU_X_HI, 0x60221407
                MOVE    @FPU_CMD, 0x3B  ; FROMBCD
                MOVE    @FPU_X_W, 8
                MOVE    @FPU_CMD, 0x39  ; SCALE10
                CALL    PRINT
                HALT

PRINT           AND[M]  R0, @FPU_STATUS, 0x10000  ; X is negative
        ?!Z     MOVE    @CONSOLE, 0x2D  ; '-'
                MOVE    @FPU_CMD, 0x0F3A  ; DIGITS 15
                MOVE    R2, @FPU_X_W    ; e
                MOVE    @FPU_CMD, 0x03  ; DROP
                MOVE    R3, @FPU_X_HI   ; the digits in R3:R4
                MOVE    R4, @FPU_X_LO
                MOVE    @FPU_CMD, 0x03  ; DROP
                SHR     R1, R3, 28
                ADD     @CONSOLE, R1, 0x30
                MOVE    @CONSOLE, 0x2E  ; '.'
                MOVE    R5, 14
:               SHL     R3, R3, 4       ; R3:R4 left by a digit
                SHR     R1, R4, 28
                OR      R3, R3, R1
                SHL     R4, R4, 4
                SHR     R1, R3, 28
                ADD     @CONSOLE, R1, 0x30
                DEC[M]  R5, R5
        ?!Z     JMP     :-
                MOVE    @CONSOLE, 0x45  ; 'E'
                MOVE    R1, 0x2B        ; '+'
                MOVE[M] R0, R2
        ?N      MOVE    R1, 0x2D        ; '-'
        ?N      SUB     R2, R0, R2
                MOVE    @CONSOLE, R1
                MOVE    @MPU_A, R2
                MOVE    @MPU_B, 100
                ADD     @CONSOLE, @MPU_UDIV_Q, 0x30
                MOVE    @MPU_A, @MPU_UDIV_R
                MOVE    @MPU_B, 10
                ADD     @CONSOLE, @MPU_UDIV_Q, 0x30
                ADD     @CONSOLE, @MPU_UDIV_R, 0x30
                MOVE    @CONSOLE, 0x0A
                RET

; Each value as its low word, then its high word.
VALUES          .DAT    0x54442D18, 0x400921FB  ; π
                .DAT    0x9999999A, 0xBFB99999  ; -0.1
                .DAT    0x00000001, 0x00000000  ; 2^-1074
                .DAT    0xFFFFFFFF, 0x7FEFFFFF  ; MAX
                .DAT    0x00000000, 0x80000000  ; -0
                .DAT    0x00000000, 0x00100000  ; 2^-1022
