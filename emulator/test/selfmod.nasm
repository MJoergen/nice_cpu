; Self-modifying code (ISA.md §8.2): a store changes the constant word of the
; next instruction.
                MOVE    @4, 0x0C000000  ; 0..2: word 4 = 0x0C000000
                MOVE    R1, 1           ; 3,4:  R1 = 0x0C000000
                HALT
