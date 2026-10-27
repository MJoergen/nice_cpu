; Add the numbers 1 to 0x1000. The sum, 0x800800, ends up in R1.
PC              .EQU    R15
                .ORG    0
                MOVE    R1, 0           ; R1 holds the sum
                MOVE    R2, 0x1000      ; R2 counts down from 0x1000
LOOP            ADD     R1, R1, R2      ; R1 = R1 + R2
                DEC[M]  R2, R2          ; R2 = R2 - 1, and update the flags
        ?!Z     MOVE    PC, LOOP        ; jump back unless R2 is now zero
                HALT
