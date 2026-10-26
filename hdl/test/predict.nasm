; Predicted jumps in the shapes of loops: two back to back, flags set by
; the instruction before, a store into the target, into the jump's own
; offset, and into the word after it, and a nested loop. The runs are
; compared with the emulator.
        MOVE    R11, 0x200
        MOVE    R8, 3
; Flags from the instruction right before: taken twice, then skipped
a1      SUB[M]  R8, R8, 1
        ?!Z ADD R15, R15, a1-a2
a2      MOVE    @R11, R8
; Two predicted jumps back to back: the first is skipped, the second taken
        MOVE    R7, 2
b1      SUB[M]  R7, R7, 1
        ?V ADD  R15, R15, b1-b2
b2      ?!Z ADD R15, R15, b1-b3
b3      MOVE    @R11, R7
; A store into the constant of the instruction at the target
        MOVE    R6, 2
c1      SUB[M]  R6, R6, 1
        MOVE    @R11, R6
        ?!Z ADD R15, R15, c1-c2
c2      MOVE    R9, @R11
; A store into the jump's own offset, and into the word after it
        MOVE    R5, 2
        MOVE    R10, d2+1
d1      SUB[M]  R5, R5, 1
        MOVE    @R10, R5           ; the offset of the jump after it
d2      ?!Z ADD R15, R15, d1-d3
d3      MOVE    R4, @R11
        MOVE    R10, d3
        MOVE    @R10, 0x1000       ; a store into the word after the jump
; A nested loop with a jump at each end
        MOVE    R1, 2
e1      MOVE    R2, 2
e2      SUB[M]  R2, R2, 1
        ?!Z ADD R15, R15, e2-e3
e3      SUB[M]  R1, R1, 1
        ?!Z ADD R15, R15, e1-e4
e4      HALT
