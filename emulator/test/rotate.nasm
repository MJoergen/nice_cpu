; 33-bit rotations and a count of 2^32-1 (ISA.md §5.2).
                MOVE    R14, 0x04000000  ; C = 1
                MOVE    R1, 0x80000000
                C<C[M]  R2, R1, 1       ; R2 = 1, C = 1
                MOVE    R3, 0xFFFFFFFF  ; n = 2^32-1, which is 3 mod 33
                C>C     R4, R1, R3      ; R4 = 0x30000000, C unchanged without M
                0<0[M]  R5, R1, R3      ; R5 = 0, Z = 1, C = 0
                HALT
