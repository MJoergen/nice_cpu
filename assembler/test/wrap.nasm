; Address wrap: the constant of the first MOVE lands at address 0.
        .ORG    0xFFFFFFFF
        MOVE    R1, 5
        MOVE    R2, next
next    HALT
