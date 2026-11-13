; The floating-point unit at 0xFFFFFF88 (DEVICES.md §11): the views, a few
; commands of each group, and the two examples of §11.5. Run with
; --step-time. Each step is one instruction, as the program has no jump;
; the step of each is in its comment. The results go to 0x200 on:
;
;   step  stack after, X last            stored
;    5    ADD.S of 1.5f and 2.25f         R3 = 3.75f = 0x40700000
;   10    IDIV -7, 2 = -3                 0x200: X_W = 0xFFFFFFFD
;   14    MOD -7, 2 = -1, the sign of Y   0x201: X_W = 0xFFFFFFFF
;   17    CONST 3, π                      0x202, 0x203: 0x54442D18, 0x400921FB
;                                         0x204: X_S, π as binary32 = 0x40490FDB
;                                         0x205: X_W = 3, rounded toward zero
;                                         0x206: STATUS = 0x00200001: depth 1,
;                                         no flag, X fits (bit 21), not whole
;   25    DIV 3, 10, under π              0x207, 0x208: 0x3FD33333_33333333, the
;                                         double nearest 0.3
;                                         0x209: REL, Y = π > X = 0.3: 1
;   29    CMP 4, Y > X, is true: -1       0x20A: X_W = 0xFFFFFFFF
;   33    SQRT 2                          0x20B, 0x20C: 0x3FF6A09E_667F3BCD
;   37    DUP, MUL: √2 · √2               0x20D, 0x20E: 0x40000000_00000001,
;                                         2 + 2^-51, as the root is above √2
;   43    FLOOR -2.5 = -3, under -2.5     0x20F: X_W = 0xFFFFFFFD
;   46    SWAP, NEAREST -2.5 = -2, even   0x210: X_W = 0xFFFFFFFE
;   51    SCALE10 3, -1 divides: 0.3      0x211: X_LO = 0x33333333
;   54    CONST 3, DIGITS 5: π is         0x212: X_W, e = 0
;         3.1416 · 10^0, as 31415.9...    0x213, 0x214: the digits after the
;         rounds to 31416                 DROP: 0x31416000_00000000
;   61    FROMBCD, SCALE10 by -15:        0x215, 0x216: 0x400921FF_2E48E8A7,
;         3141600000000000 / 10^15,       the double nearest 3.1416, rounded
;         one rounding                    down by 0.117 of an ulp
;   66    DIV 1, 0 = +inf, under 0.3 and  0x217: STATUS = 0x00040203: depth 3,
;         3.1416                          division by zero (bit 9), X is
;                                         infinite (bit 18)
;   70    The counter of §11.5: TIME_LO   R4 = X_W = 0x44
;         at step 68 reads 68 = 0x44,
;         TIME_HI 0, and UTOF gives 68
;
; 73 steps, and PC = 186 = 0xBA after the HALT at 185. R6 = 0x200 + 24 =
; 0x218. The dump of the FPU's words, with X = 68 = 1.0625 · 2^6 =
; 0x40510000_00000000 over +inf, 3.1416, and 0.3: X_LO 0, X_HI 0x40510000,
; X_S 0x42880000, X_W 0x44, CMD 0, STATUS 0x00300204 (depth 4, division by
; zero, X whole and fits), REL 1 (Y = +inf > 68), and 0. The flags are
; sticky, so the DIV's flag stays.
;
; test/fpu_mem.expected is this program with --no-fpu, where the eight
; words are ordinary memory.
FPU_X_LO        .EQU    0xFFFFFF88
FPU_X_HI        .EQU    0xFFFFFF89
FPU_X_S         .EQU    0xFFFFFF8A
FPU_X_W         .EQU    0xFFFFFF8B
FPU_CMD         .EQU    0xFFFFFF8C
FPU_STATUS      .EQU    0xFFFFFF8D
FPU_REL         .EQU    0xFFFFFF8E
TIME_LO         .EQU    0xFFFFFF44
TIME_HI         .EQU    0xFFFFFF45
                MOVE    R6, 0x200       ; 0
                MOVE    R1, 0x3FC00000  ; 1: 1.5f
                MOVE    R2, 0x40100000  ; 2: 2.25f
                MOVE    @FPU_X_S, R1    ; 3
                MOVE    @FPU_X_S, R2    ; 4
                MOVE    @FPU_CMD, 0x10010  ; 5: ADD, S
                MOVE    R3, @FPU_X_S    ; 6
                MOVE    @FPU_CMD, 0x03  ; 7: DROP
                MOVE    @FPU_X_W, 0xFFFFFFF9  ; 8: -7
                MOVE    @FPU_X_W, 2     ; 9
                MOVE    @FPU_CMD, 0x66  ; 10: IDIV
                MOVE    @R6++, @FPU_X_W  ; 11
                MOVE    @FPU_X_W, 0xFFFFFFF9  ; 12
                MOVE    @FPU_X_W, 2     ; 13
                MOVE    @FPU_CMD, 0x67  ; 14: MOD
                MOVE    @R6++, @FPU_X_W  ; 15
                MOVE    @FPU_CMD, 0x0203  ; 16: DROP 2
                MOVE    @FPU_CMD, 0x0330  ; 17: CONST 3
                MOVE    @R6++, @FPU_X_LO  ; 18
                MOVE    @R6++, @FPU_X_HI  ; 19
                MOVE    @R6++, @FPU_X_S  ; 20
                MOVE    @R6++, @FPU_X_W  ; 21
                MOVE    @R6++, @FPU_STATUS  ; 22
                MOVE    @FPU_X_W, 3     ; 23
                MOVE    @FPU_X_W, 10    ; 24
                MOVE    @FPU_CMD, 0x13  ; 25: DIV
                MOVE    @R6++, @FPU_X_LO  ; 26
                MOVE    @R6++, @FPU_X_HI  ; 27
                MOVE    @R6++, @FPU_REL  ; 28
                MOVE    @FPU_CMD, 0x041C  ; 29: CMP 4
                MOVE    @R6++, @FPU_X_W  ; 30
                MOVE    @FPU_CMD, 0x03  ; 31: DROP
                MOVE    @FPU_X_W, 2     ; 32
                MOVE    @FPU_CMD, 0x14  ; 33: SQRT
                MOVE    @R6++, @FPU_X_LO  ; 34
                MOVE    @R6++, @FPU_X_HI  ; 35
                MOVE    @FPU_CMD, 0x02  ; 36: DUP
                MOVE    @FPU_CMD, 0x12  ; 37: MUL
                MOVE    @R6++, @FPU_X_LO  ; 38
                MOVE    @R6++, @FPU_X_HI  ; 39
                MOVE    @FPU_CMD, 0x03  ; 40: DROP
                MOVE    @FPU_X_S, 0xC0200000  ; 41: -2.5f
                MOVE    @FPU_CMD, 0x02  ; 42: DUP
                MOVE    @FPU_CMD, 0x20  ; 43: FLOOR
                MOVE    @R6++, @FPU_X_W  ; 44
                MOVE    @FPU_CMD, 0x04  ; 45: SWAP
                MOVE    @FPU_CMD, 0x23  ; 46: NEAREST
                MOVE    @R6++, @FPU_X_W  ; 47
                MOVE    @FPU_CMD, 0x0203  ; 48: DROP 2
                MOVE    @FPU_X_W, 3     ; 49
                MOVE    @FPU_X_W, 0xFFFFFFFF  ; 50: -1
                MOVE    @FPU_CMD, 0x39  ; 51: SCALE10
                MOVE    @R6++, @FPU_X_LO  ; 52
                MOVE    @FPU_CMD, 0x0330  ; 53: CONST 3
                MOVE    @FPU_CMD, 0x053A  ; 54: DIGITS 5
                MOVE    @R6++, @FPU_X_W  ; 55
                MOVE    @FPU_CMD, 0x03  ; 56: DROP
                MOVE    @R6++, @FPU_X_HI  ; 57
                MOVE    @R6++, @FPU_X_LO  ; 58
                MOVE    @FPU_CMD, 0x3B  ; 59: FROMBCD
                MOVE    @FPU_X_W, 0xFFFFFFF1  ; 60: -15
                MOVE    @FPU_CMD, 0x39  ; 61: SCALE10
                MOVE    @R6++, @FPU_X_LO  ; 62
                MOVE    @R6++, @FPU_X_HI  ; 63
                MOVE    @FPU_X_W, 1     ; 64
                MOVE    @FPU_X_W, 0     ; 65
                MOVE    @FPU_CMD, 0x13  ; 66: DIV
                MOVE    @R6++, @FPU_STATUS  ; 67
                MOVE    @FPU_X_LO, @TIME_LO  ; 68
                MOVE    @FPU_X_HI, @TIME_HI  ; 69
                MOVE    @FPU_CMD, 0x29  ; 70: UTOF
                MOVE    R4, @FPU_X_W    ; 71
                HALT                    ; 72
