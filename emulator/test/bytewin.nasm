; The byte windows of SYSTEM.md §9. Word 0x200 holds the bytes 01, 7F, FF,
; and 80, byte 0 first, and word 0x201 the halfwords 7FFF and 8001. The
; windows reach word (A >> 2) AND 0x03FFFFFF of an address A.
;
; Reads: R1 = 0x00000001 (byte 0), R2 = 0xFFFFFF80 (byte 3, signed),
; R3 = 0x000000FF (byte 2), R4 = 0x0000007F (byte 1, signed),
; R5 = 0xFFFF8001 (halfword 1, signed), R6 = 0x00007FFF (halfword 0, bit 0
; of A ignored), R7 = 0x80017FFF (the word, bits 1..0 of A ignored), and
; R8 = 0x00007FFF (halfword 0, signed and positive).
;
; Writes: word 0x202 gets byte 1 = 0x78 and byte 3 = 0xAB, the rest of
; each value dropped: 0xAB007800. Word 0x203 gets halfword 0 = 0x1234 and
; halfword 1 = 0xCAFE: 0xCAFE1234. Word 0x204 gets 0x11223344, whose
; byte 2 reads back as R9 = 0x00000022.
;
; 0x1FFFFFFC reaches word 0x03FFFFFF, the last a window reaches, so it
; holds 0x55, which R10 reads back. 0x60000000 is no window, so the HALT
; stored there lands in that word. With R11 = 9, the indexed operand of
; 0x20000800 reaches byte 9, byte 1 of word 0x202: R12 = 0x00000078.
;
; Then the jump to 0x5FFFFFFE. A fetch from a window reads 0, a NOP, so
; the HALT that the image puts at 0x5FFFFFFF does not run, nor does 0x55
; from word 0x03FFFFFF, which a data read of 0x5FFFFFFC to 0x5FFFFFFF
; reaches. The HALT at 0x60000000 does: PC = 0x60000001. Steps: 20
; instructions here, 2 NOPs, and the HALT: 23. No instruction sets flags,
; so R14 keeps 0x01000000.
;
; The dumps read through the windows as data reads do: 0x20000809 shows
; byte 9, 0x00000078, and 0x5000080E halfword 1 of word 0x203, 0xFFFFCAFE.
                MOVE    R1, @0x20000800
                MOVE    R2, @0x30000803
                MOVE    R3, @0x20000802
                MOVE    R4, @0x30000801
                MOVE    R5, @0x50000806
                MOVE    R6, @0x40000805
                MOVE    R7, @0x10000807
                MOVE    R8, @0x50000804
                MOVE    @0x20000809, 0x12345678
                MOVE    @0x3000080B, 0xAB
                MOVE    @0x4000080D, 0xFFFF1234
                MOVE    @0x5000080E, 0xCAFE
                MOVE    @0x10000810, 0x11223344
                MOVE    R9, @0x30000812
                MOVE    @0x1FFFFFFC, 0x55
                MOVE    R10, @0x2FFFFFFC
                MOVE    @0x60000000, 0x0C000000
                MOVE    R11, 9
                MOVE    R12, @0x20000800[R11]
                JMP     0x5FFFFFFE

                .ORG    0x200
                .DAT    0x80FF7F01
                .DAT    0x80017FFF

                .ORG    0x5FFFFFFF
                HALT
