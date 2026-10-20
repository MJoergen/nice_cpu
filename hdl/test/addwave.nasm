; The program of the timing diagram doc/flow.tex: the worked
; example of ISA.md §11, "?!Z ADD[M] @R3++, --R2, @0x12345678[R1]",
; between plain instructions. Z is 0 after reset, so it runs. R2 = 0x31,
; so s0 = 0x30. R1 + 0x12345678 = 0x20, so s1 = mem[0x20] = 0x100. It
; stores 0x130 at R3 = 0x100, and leaves R3 = 0x101 and R2 = 0x30.
        MOVE    R1, 0xEDCBA9A8  ; words 0,1: 0x20 - 0x12345678
        MOVE    R2, 0x31        ; words 2,3
        MOVE    R3, 0x100       ; words 4,5
        ADD     R4, R4, 1       ; words 6,7
        ?!Z ADD[M] @R3++, --R2, @0x12345678[R1] ; words 8,9
        ADD     R4, R4, 1       ; words A,B
        ADD     R4, R4, 1       ; words C,D
        ADD     R4, R4, 1       ; words E,F
        HALT                    ; word 10

        .ORG    0x20
        .DAT    0x100
