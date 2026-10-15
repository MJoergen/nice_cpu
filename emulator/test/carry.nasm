; The carry input is the C flag as step 5 left it (ISA.md §5.1).
        MOVE    R14, 0x03FFFFFF ; C = 0
        ADD[C]  R1, R14++, 0    ; R14++ carries into bit 26: C = 1, R1 = 0x04000000
        HALT
