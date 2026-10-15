; R15 as operand and destination (ISA.md §4.3).
        MOVE    R1, R15         ; 0:    R1 = 1
        ADD     R2, R15, 5      ; 1,2:  R15 reads 3, R2 = 8
        ADD     R4, R15++, R15  ; 3:    s0 = 4, R15 <- 5, s1 = 5: R4 = 9
        HALT                    ; 4:    jumped over
        MOVE    R15++, 8        ; 5,6:  R15 = 8, then 9
        HALT                    ; 7:    trap
        HALT                    ; 8:    trap
        MOVE    R3, 1           ; 9,10
        HALT                    ; 11
