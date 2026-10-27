; Every logic opcode, and SUB[C] with C = 0 (ISA.md §5.1).
                MOVE    R1, 0xF0F0F0F0
                MOVE    R2, 0xFF00FF00
                NOR     R3, R1, R2      ; 000f000f
                IAND    R4, R1, R2      ; 0f000f00
                NAND    R5, R1, R2      ; 0fff0fff
                XOR     R6, R1, R2      ; 0ff00ff0
                IOR     R7, R1, R2      ; ff0fff0f
                XNOR    R8, R1, R2      ; f00ff00f
                AND     R9, R1, R2      ; f000f000
                OR      R10, R1, R2     ; fff0fff0
                NOT     R11, R1         ; 0f0f0f0f
                ONE     R12             ; 00000001
                SUB[C]  R13, R1, R2     ; f1eff1f0
                HALT
