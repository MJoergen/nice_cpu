; The whole address space exists (ISA.md §1.1): execution and writes wrap
; from 0xFFFFFFFF to 0, and a stack at a high address keeps its contents.
        ?!Z MOVE R15, top       ; 0,1: Z = 0 after reset, so jump
        MOVE    R3, 0xFFFFFFFF  ; 2,3
        MOVE    @1[R3], 7       ; 4..6: writes address 0
        MOVE    R13, 0x200000
        MOVE    @--R13, 42
        MOVE    R4, @R13        ; R4 = 42
        HALT
        .ORG    0xFFFFFFFC
top     MOVE    R1, 5           ; FFFFFFFC,D
        SUB[M]  R2, R1, R1      ; FFFFFFFE: Z = 1
        MOVE    R5, R15         ; FFFFFFFF: R5 = 0, then on to word 0
