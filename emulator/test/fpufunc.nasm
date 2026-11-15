; The FPU's functions (DEVICES.md §11.3): SIN, COS, TAN, and ATAN2 of a
; value each, an operand beyond its bound, and a function whose frame
; does not fit above the stack. The values are those of the hand-checked
; cases of test/fpu_model_test.py, the exact ones rounded once. The
; results go to 0x200 on:
;
;   0x200  SIN 0.5, X_LO and X_HI                   0x744B05F0 0x3FDEAEE8
;   0x202  COS 0.5                                  0x065B7D50 0x3FEC1528
;   0x204  CLEAR 1, so that the frame of TAN, 14
;          values above its operand, fits; TAN
;          pi/4, the double below 1, of pi
;          divided by 4, which is exact             0xFFFFFFFF 0x3FEFFFFF
;   0x206  STATUS: depth 1, no flag, X fits         0x00200001
;   0x207  CLEAR 1, SIN 2^21, beyond 2^20 pi/2:
;          the canonical NaN, invalid (bit 8),
;          depth 1, X a NaN (bit 19)                0x00080101
;   0x208  CLEAR 1, 15 down to 1 pushed, then 0:
;          16 values. SIN 0 is 0, but its frame
;          takes five values above the full
;          stack, so the five deepest, 15 to 11,
;          go, with the stack fault (bit 11):
;          depth 11, X zero (bit 17), whole, and
;          fits                                     0x0032080B
;   0x209  PICK 10, the deepest: X_W                0x0000000A
;   0x20A  CLEAR 1, ATAN2 of Y = 1 and X = -1, the
;          one function of two operands: 3 pi/4    0x7F3321D2 0x4002D97C
;   0x20C  STATUS: depth 1, no flag, X fits         0x00200001
;
; 81 steps, and PC = 0x60 after the HALT at 0x5F. R6 = 0x200 + 13 = 0x20D.
FPU_X_LO        .EQU    0xFFFFFF88
FPU_X_HI        .EQU    0xFFFFFF89
FPU_X_S         .EQU    0xFFFFFF8A
FPU_X_W         .EQU    0xFFFFFF8B
FPU_CMD         .EQU    0xFFFFFF8C
FPU_STATUS      .EQU    0xFFFFFF8D

                MOVE    R6, 0x200
                MOVE    @FPU_X_S, 0x3F000000  ; 0.5
                MOVE    @FPU_CMD, 0x40  ; SIN
                MOVE    @R6++, @FPU_X_LO
                MOVE    @R6++, @FPU_X_HI
                MOVE    @FPU_X_S, 0x3F000000
                MOVE    @FPU_CMD, 0x41  ; COS
                MOVE    @R6++, @FPU_X_LO
                MOVE    @R6++, @FPU_X_HI
                MOVE    @FPU_CMD, 0x0101  ; CLEAR 1
                MOVE    @FPU_CMD, 0x0330  ; CONST 3, pi
                MOVE    @FPU_X_W, 4
                MOVE    @FPU_CMD, 0x13  ; DIV
                MOVE    @FPU_CMD, 0x42  ; TAN
                MOVE    @R6++, @FPU_X_LO
                MOVE    @R6++, @FPU_X_HI
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_CMD, 0x0101  ; CLEAR 1
                MOVE    @FPU_X_W, 0x200000  ; 2^21
                MOVE    @FPU_CMD, 0x40  ; SIN
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_CMD, 0x0101  ; CLEAR 1
                MOVE    R7, 15
:               MOVE    @FPU_X_W, R7
                DEC[M]  R7, R7
        ?!Z     JMP     :-
                MOVE    @FPU_X_W, 0
                MOVE    @FPU_CMD, 0x40  ; SIN
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_CMD, 0x0A06  ; PICK 10
                MOVE    @R6++, @FPU_X_W
                MOVE    @FPU_CMD, 0x0101  ; CLEAR 1
                MOVE    @FPU_X_W, 1
                MOVE    @FPU_X_W, -1
                MOVE    @FPU_CMD, 0x46  ; ATAN2
                MOVE    @R6++, @FPU_X_LO
                MOVE    @R6++, @FPU_X_HI
                MOVE    @R6++, @FPU_STATUS
                HALT
