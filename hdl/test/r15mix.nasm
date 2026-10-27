; R15 in several fields of one instruction, with side effects, as a
; shift count, and as the base of a store (ISA.md §4.3).
                MOVE    R15, 0x200
                .ORG    0x200
                MOVE    R1, 0x9ABCDEF1
                MOVE    R10, scratch
a1              ADD     R4, R15++, R15  ; s0 = a1 + 1, R15 = a1 + 2, s1 = a1 + 2
                HALT
a2              ADD     R4, R15++, 1[R15]  ; s1 = R15 after the side effect, plus 1
                HALT
a3              SUB     R4, --R15, @1[R15]  ; R15 = a3 + 1 (the constant 1, a NOP), s1 = mem[a3 + 2]
                ADD     R4, R15, R15++  ; s0 = s1 = next, then R15 + 1
                HALT
                ADD     R4, R15++, R15++  ; both increment
                HALT
                HALT
                ADD     R4, R15++, @R15  ; s1 is the word R15 points at after the increment
                HALT
                ADD     R0, R0, R0      ; read as s1 above, then run
                ADD     R4, @R15++, R15  ; s0 = the next word, skipped
                .DAT    0x5555
                ADD     R4, 0[R15], @--R15  ; s0 = a + 2, then R15 = a + 1, s1 = mem[a + 1] = 0
                MOVE    R15, R15++      ; R15 = a + 2, then a + 1
                MOVE    R4, 0x66        ; runs
                ADD     R15, --R15, 2   ; R15 = a + 1, r = a + 3
                HALT
                MOVE    R15, @R15++     ; through the next word
                .DAT    b1
                HALT
b1              ADD     R15, R15++, R0  ; s0 = b1 + 1, R15 = b1 + 2, then R15 = b1 + 1: two cycles
                MOVE    R4, 0x77        ; b1 + 1, runs
                MOVE    @0x100[R15], R15++  ; store at next + 1 + 0x100, after the side effect
                HALT
                MOVE    @2[R15], 0      ; the HALT two words on becomes a NOP
                MOVE    R4, 0x88
                HALT
                0<0     R4, R1, R15     ; count = next: huge
                >>>     R4, R1, R15     ; next mod 32
                C<C     R4, R1, R15
                <<<     R4, R1, R15++   ; skips a word
                HALT
                0<0     R4, R15, 1
                0<0     R4, R15++, R0   ; s0 = next, then skips a word
                HALT
                C>C     R4, R15++, R15  ; s0 = next, count = next + 1
                HALT
                ADD     R4, R15++, R15++  ; then an instruction that reads R15 at once
                HALT
                HALT
                MOVE    R5, R15
                ADD     R6, R15, 3[R15]
                MOVE    R7, @R15        ; the word of the next instruction
                MOVE    R0, R0
                MOVE    R15, c1         ; a resolved jump, then R15 read at the target
c1              MOVE    R5, R15
                ADD     R15, R15, 0     ; an early jump to the next instruction
                MOVE    R6, R15
                ADD     R15, R15, R0    ; two cycles, to the next instruction
                MOVE    R7, 1[R15]
                MOVE    R15, 0x300
                .ORG    0x300
                ADD     R15++, R15++, R15  ; r = 2 * 0x300 + 3, R15 = 0x604
                HALT
                .ORG    0x310
                ADD     R15, R15, 0[R15]  ; r = 2 * (0x310 + 2) = 0x624
                HALT
                .ORG    0x604
                MOVE    R15, 0x310
                .ORG    0x624
                MOVE    R4, 0x99
                HALT
                .ORG    0x1000
scratch         .BLK    8
