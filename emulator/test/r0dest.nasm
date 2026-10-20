; R0 as a destination in the modes that cputest leaves out (ISA.md §4.3):
; R0--, @R0, @--R0, and @R0++. The write to R0 and every side effect on it
; are discarded, so R0 stays 0, and the three memory modes all write word 0.
; Word 0 is the first instruction, which runs only once, so it may be
; overwritten. Word 1 is its constant, start = 2.
;
;   MOVE R0--, 5       discarded, and so is the decrement
;   ADD R1, R0, 7      R1 = 7, as R0 is still 0
;   MOVE @--R0, 0x22   no decrement: mem[0] = 0x22, not mem[0xFFFFFFFF]
;   MOVE R2, @0        R2 = 0x22
;   MOVE R3, @-1       R3 = mem[0xFFFFFFFF] = 0, never written
;   MOVE @R0++, 0x33   mem[0] = 0x33, and no increment
;   MOVE R4, @0        R4 = 0x33
;   MOVE @R0, 0x44     still word 0, not word 1: mem[0] = 0x44
;   MOVE R5, @0        R5 = 0x44
;   MOVE R6, @1        R6 = 2, word 1 unchanged
;
; Steps: 12. PC = 0x17 after the HALT at 0x16. No flags change. The dump
; shows 0x44 and 2.
        MOVE    R15, start      ; words 0,1
start   MOVE    R0--, 5         ; words 2,3
        ADD     R1, R0, 7       ; words 4,5
        MOVE    @--R0, 0x22     ; words 6,7
        MOVE    R2, @0          ; words 8,9
        MOVE    R3, @-1         ; words 10,11
        MOVE    @R0++, 0x33     ; words 12,13
        MOVE    R4, @0          ; words 14,15
        MOVE    @R0, 0x44       ; words 16,17
        MOVE    R5, @0          ; words 18,19
        MOVE    R6, @1          ; words 20,21
        HALT                    ; word 22
