                .ORG    0
I               .EQU    0x1000
                MOVE    R14, R0
                MOVE    R1, R0
                MOVE    R2, I
LOOP            ADD     R1, R1, R2
                DEC[M]  R2, R2
        ?!Z     MOVE    R15, LOOP
                HALT




