; Instruction fetches from the I/O range read 0 (ISA.md §8.3). The program
; stores HALT words at 0xFFFFFF80 and 0xFFFFFFFF and jumps to the first.
; Both are fetched as 0, a NOP, so the 128 words run as NOPs, and PC wraps
; to 0. On the second pass R3 = 1, so the jump to done is taken.
;
; Steps: 7 on the first pass (the ?!Z jump is skipped), 128 NOPs, and 3 on
; the second pass: 138. R1 = 0x0C000000, because a data read sees the
; stored word. R3 = 1. MOVE[M] R0, R3 with R3 = 1 clears every flag, so
; R14 = 0x01000000. Both dumps show 0c000000.
        MOVE[M] R0, R3                  
        ?!Z MOVE R15, done
        MOVE    R3, 1
        MOVE    @0xFFFFFF80, 0x0C000000
        MOVE    @0xFFFFFFFF, 0x0C000000
        MOVE    R1, @0xFFFFFF80
        MOVE    R15, 0xFFFFFF80
done    HALT
