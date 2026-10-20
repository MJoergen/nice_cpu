; R15 as operand and destination (ISA.md §4.3).
        MOVE    R1, R15         ; 0:    R1 = 1
        ADD     R2, R15, 5      ; 1,2:  R15 reads 3, R2 = 8
        ADD     R4, R15++, R15  ; 3:    s0 = 4, R15 <- 5, s1 = 5: R4 = 9
        HALT                    ; 4:    jumped over
        MOVE    R15++, 8        ; 5,6:  R15 = 8, then 9
        HALT                    ; 7:    trap
        HALT                    ; 8:    trap
        MOVE    R3, 1           ; 9,10
        MOVE    R5, 0x10        ; 11,12
        0<0     R15, R5, 1      ; 13:   a shift into R15 jumps to its result, 0x20, not to s0
        HALT                    ; 14:   trap
        .ORG    0x10
        HALT                    ;       trap: s0
        .ORG    0x20
        MOVE    R6, 3           ; 0x20, 0x21
        MOVE    R5, 4           ; 0x22, 0x23
        0<0     R15, R6, R5     ; 0x24: the count written just before: R15 = 3 << 4 = 0x30
        HALT                    ; 0x25: trap
        .ORG    0x30
        MOVE    R7, 1           ; 0x30, 0x31
        HALT                    ; 0x32
