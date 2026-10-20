; Addresses wrap from 0xFFFFFFFF to 0 in the register side effects of the
; memory modes (ISA.md §1.1, §4.1, §4.2), and instruction fetches from the
; I/O range never reach a device (§8.3): running through the read counter
; at 0xFFFFFF01 does not count.
;
; First pass, with R6 = 0: SUB[M] gives 0xFFFFFFFF, so Z = 0 and the ?Z
; jump is skipped. R6 = 1, the read counter is set to 0x50, and the program
; jumps to 0xFFFFFF00. The 256 words of the I/O range are fetched as 0, a
; NOP, and PC wraps to 0. Second pass: SUB[M] gives 0, Z = 1, and the jump
; to second is taken. Then:
;
;   MOVE R7, @COUNT          R7 = 0x50: the fetches did not count. Now 0x51.
;   MOVE @0xFFFFFFFF, 0x77
;   MOVE R2, 0xFFFFFFFF
;   MOVE R1, @R2++           R1 = 0x77, and R2 wraps to 0
;   MOVE R3, 0xFFFFFFFF
;   MOVE @R3++, 0x88         mem[0xFFFFFFFF] = 0x88, and R3 wraps to 0
;   MOVE R4, @--R5           R5 = 0 - 1 = 0xFFFFFFFF, R4 = 0x88
;   MOVE @--R9, 0x99         R9 = 0xFFFFFFFF, mem[0xFFFFFFFF] = 0x99
;   MOVE R10, @0xFFFFFFFF    R10 = 0x99
;
; Steps: 5 + 256 + 2 + 10 = 273. HALT is word 0x1C, so PC = 0x1D. The
; flags are those of the second SUB[M]: Z, R14 = 0x09000000. The dumps show
; the read counter, 0x51, without counting, and 0x99 at 0xFFFFFFFF.
COUNT   .EQU    0xFFFFFF01
        SUB[M]  R0, R6, 1
?Z      MOVE    R15, second
        MOVE    R6, 1
        MOVE    @COUNT, 0x50
        MOVE    R15, 0xFFFFFF00
second  MOVE    R7, @COUNT
        MOVE    @0xFFFFFFFF, 0x77
        MOVE    R2, 0xFFFFFFFF
        MOVE    R1, @R2++
        MOVE    R3, 0xFFFFFFFF
        MOVE    @R3++, 0x88
        MOVE    R4, @--R5
        MOVE    @--R9, 0x99
        MOVE    R10, @0xFFFFFFFF
        HALT
