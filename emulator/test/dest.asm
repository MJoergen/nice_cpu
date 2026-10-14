; Destination modes 001, 110, 011 and 111 (ISA.md §4.2), and unused operand
; fields (§4.4). The two .DAT words are hand-encoded, because the assembler
; refuses three operands for MOVE and ONE.
        MOVE    R1, 0x100
        MOVE    R1--, 5         ; R1 = 4
        MOVE    R2, 0x200
        MOVE    @R2++, 7        ; mem[0x200] = 7, R2 = 0x201
        MOVE    @0x10[R2], 9    ; mem[0x211] = 9
        MOVE    0x20[R2], 11    ; mode 011: mem[0x221] = 11
        MOVE    R3, 0x300
        .DAT    0x0000C0E2      ; MOVE R3, R1, @R2++: s1 reads and bumps R2
        .DAT    0x01C148E2      ; ONE R5, --R1, @R2++: s0 and s1 both apply
        HALT                    ; R1 = 3, R2 = 0x203, R3 = 4, R5 = 1
