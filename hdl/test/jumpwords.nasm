; Jumps into constant words, to the instruction itself, and reads of R15
; around early and late jumps, with conditions on I, and backward
; conditional jumps, which DECODE predicts taken.
                MOVE    R14, 0x81000000  ; I = 1
                ADD     R15, R15, -1    ; to the constant word, 0xFFFFFFFF: ?!I reserved, skipped
                MOVE    R1, 1
                MOVE    R15, k1+1       ; to a constant word that is a MOVE R2, 7
k1              MOVE    R3, 0x8080      ; the constant word is MOVE R2, R1
                MOVE    R4, R15
                ADD     R15, R15, R0    ; two cycles to the next instruction
                MOVE    R5, R15
                ADD     R15, R15, 0     ; early to the next
                MOVE    R6, R15
        ?I      ADD     R15, R15, 1     ; not early: conditional
                HALT
        ?!I     ADD     R15, R15, 1     ; skipped
                MOVE    R7, 7
; Backward conditional jumps, which DECODE predicts taken
                MOVE    R8, 3
                MOVE    R11, 0x200
l1              SUB[M]  R8, R8, 1
        ?!Z     ADD     R15, R15, l1-n1  ; a counted loop: taken twice, then skipped
n1              MOVE    R9, @R11        ; a read after the skipped jump
        ?I      ADD     R15, R15, -1    ; taken, to its constant word: ?!I reserved, skipped
        ?!I     ADD     R15, R15, -2    ; skipped, to itself
                MOVE    @R11, R15       ; a store after it
        ?I      ADD[M]  R15, -1, R15    ; taken, the sources the other way round, M set
        ?I      ADD[C]  R15, R15, -1    ; the C bit: resolved in WRITE
                MOVE    R14, 0x01000000
                ADD     R15, R15, -1    ; now the reserved word runs: halts with status 2
                HALT
