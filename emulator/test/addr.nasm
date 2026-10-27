; The whole address space exists (ISA.md §1.1): execution and writes wrap
; from 0xFFFFFFFF to 0, and a stack at a high address keeps its contents.
; Execution wraps through the I/O range, whose 256 words are fetched as 0,
; a NOP (§8.3). Steps: 1 + 3 + 256 + 7 = 267.
        ?!Z     MOVE    R15, top        ; 0,1: Z = 0 after reset, so jump
                MOVE    R3, 0xFFFFFFFF  ; 2,3: Z = 1 now, so the jump was skipped
                MOVE    @1[R3], 7       ; 4..6: writes address 0
                MOVE    R13, 0x200000
                MOVE    @--R13, 42
                MOVE    R4, @R13        ; R4 = 42
                HALT
                .ORG    0xFFFFFEFC
top             MOVE    R1, 5           ; FFFFFEFC,D
                SUB[M]  R2, R1, R1      ; FFFFFEFE: Z = 1
                MOVE    R5, R15         ; FFFFFEFF: R5 = 0xFFFFFF00, then NOPs to word 0
