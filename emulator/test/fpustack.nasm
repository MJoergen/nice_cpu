; The FPU's stack and flags (DEVICES.md §11.2, §11.4): the depth, the
; faults, the sticky flags, a save and a restore of them through STATUS,
; an instruction that reads and writes one register, and @R9++ over the
; eight words, which reads them all and changes nothing.
;
; The loop pushes 17, 16, ..., 1 through X_W. The 17th push, of 1, finds
; 16 values and drops the deepest, 17, with the stack fault. STATUS is then
; 0x00300810: depth 16, the stack fault (bit 11), and X = 1 whole and
; fitting (bits 20 and 21). The results go to 0x200 on:
;
;   0x200  STATUS after the loop                    0x00300810
;   0x201  PICK 15 copies the deepest, 16, and the
;          push drops it: X_W                       0x00000010
;   0x202  STATUS, saved in R8, then cleared        0x00300010
;   0x203  the word 0x07 is not valid: invalid;
;          NEG, valid, leaves it, X = -16:
;          negative too                             0x00310110
;   0x204  STATUS restored from R8: the stack fault
;          again, invalid gone                      0x00310810
;   0x205  CLEAR keeps the flags; cleared, a write
;          of X_HI on the empty stack sets the
;          fault again: depth 0, the class of the
;          canonical NaN (bit 19)                   0x00080800
;   0x206  CLEAR 1 clears them; ADD on the empty
;          stack pops two canonical NaNs, which are
;          quiet: the stack fault only, and a NaN   0x00080801
;   0x207  its X_HI                                 0x7FF80000
;   0x208  DROP 3 of one value; flags cleared;
;          5 pushed; ADD @X_W, @X_W, 1 reads 5 and
;          pushes 6; MOVE @X_LO, @X_LO reads the
;          low word of 6.0, 0, and pushes it: depth
;          3, X = +0, zero, whole, and fits         0x00320003
;
; DROP 3 empties the stack with no fault. 3 and -2.5 are pushed, and
; @R9++ reads the eight words to 0x209-0x210: X_LO 0, X_HI 0xC0040000,
; X_S 0xC0200000, X_W -2 = 0xFFFFFFFE, CMD 0, STATUS 0x00210002 (depth 2,
; negative, fits), REL 1 (Y = 3 > -2.5), and 0. STATUS again at 0x211 is
; the same, and so is the dump of the eight words.
;
; Steps: 2 + 17 * 3 in the loop, and 40 after it, 93 in all. PC = 99 =
; 0x63 after the HALT at 98. R6 = 0x212, R7 = 0 with Z set (R14 =
; 0x09000000), R8 = 0x00300810, and R9 = 0xFFFFFF90.
FPU             .EQU    0xFFFFFF88
FPU_X_LO        .EQU    0xFFFFFF88
FPU_X_HI        .EQU    0xFFFFFF89
FPU_X_S         .EQU    0xFFFFFF8A
FPU_X_W         .EQU    0xFFFFFF8B
FPU_CMD         .EQU    0xFFFFFF8C
FPU_STATUS      .EQU    0xFFFFFF8D
                MOVE    R6, 0x200
                MOVE    R7, 17
:               MOVE    @FPU_X_W, R7
                DEC[M]  R7, R7
        ?!Z     JMP     :-
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_CMD, 0x0F06  ; PICK 15
                MOVE    @R6++, @FPU_X_W
                MOVE    R8, @FPU_STATUS
                MOVE    @FPU_STATUS, 0
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_CMD, 0x07  ; not defined
                MOVE    @FPU_CMD, 0x15  ; NEG
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_STATUS, R8
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_CMD, 0x01  ; CLEAR
                MOVE    @FPU_X_HI, 5
                MOVE    @FPU_STATUS, 0
                MOVE    @FPU_X_HI, 5
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_CMD, 0x0101  ; CLEAR 1
                MOVE    @FPU_CMD, 0x10  ; ADD
                MOVE    @R6++, @FPU_STATUS
                MOVE    @R6++, @FPU_X_HI
                MOVE    @FPU_CMD, 0x0303  ; DROP 3
                MOVE    @FPU_STATUS, 0
                MOVE    @FPU_X_W, 5
                ADD     @FPU_X_W, @FPU_X_W, 1
                MOVE    @FPU_X_LO, @FPU_X_LO
                MOVE    @R6++, @FPU_STATUS
                MOVE    @FPU_CMD, 0x0303  ; DROP 3
                MOVE    @FPU_X_W, 3
                MOVE    @FPU_X_S, 0xC0200000  ; -2.5f
                MOVE    R9, FPU
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @R9++
                MOVE    @R6++, @FPU_STATUS
                HALT
