; R14 in the memory modes (ISA.md §4.3, §6). Bit 24 is 1 at every point
; within an instruction, so R14 as an address always has it, and every
; write to R14, a side effect included, sets it. With a memory destination
; the flags are updated after the write and the side effect.
;
;   MOVE @0x01FFFFFF, 0x99
;   MOVE R14, 0              R14 = 0x01000000
;   MOVE R1, @--R14          R14 = 0x01FFFFFF, and R1 = mem[0x01FFFFFF] = 0x99
;   MOVE R2, R14             R2 = 0x01FFFFFF
;   MOVE R14, 0x10           R14 = 0x01000010
;   MOVE R3, @R14++          R3 = mem[0x01000010] = 0x5A, R14 = 0x01000011
;   MOVE R4, R14             R4 = 0x01000011
;   MOVE @R14++, 0x66        mem[0x01000011] = 0x66, R14 = 0x01000012
;   MOVE R5, R14             R5 = 0x01000012
;   MOVE R14, 0              R14 = 0x01000000
;   SUB[M] @--R14, R0, 1     R14 = 0x01FFFFFF, then mem[0x01FFFFFF] =
;                            0 - 1 = 0xFFFFFFFF, a borrow. The flags X, N,
;                            and C replace bits 29..25 of 0x01FFFFFF:
;                            R14 = 0x17FFFFFF
;   MOVE R6, R14             R6 = 0x17FFFFFF
;   MOVE R14, 0x10           R14 = 0x01000010
;   ADD[M] @R14, R0, 0       mem[0x01000010] = 0, then Z: R14 = 0x09000010
;   MOVE R7, R14             R7 = 0x09000010
;   MOVE R8, @0x01000010     R8 = 0
;
; Steps: 17. HALT is word 0x1A, so PC = 0x1B. The dumps show 0 and 0x66 at
; 0x01000010, and 0xFFFFFFFF at 0x01FFFFFF.
        MOVE    @0x01FFFFFF, 0x99
        MOVE    R14, 0
        MOVE    R1, @--R14
        MOVE    R2, R14
        MOVE    R14, 0x10
        MOVE    R3, @R14++
        MOVE    R4, R14
        MOVE    @R14++, 0x66
        MOVE    R5, R14
        MOVE    R14, 0
        SUB[M]  @--R14, R0, 1
        MOVE    R6, R14
        MOVE    R14, 0x10
        ADD[M]  @R14, R0, 0
        MOVE    R7, R14
        MOVE    R8, @0x01000010
        HALT
        .ORG    0x01000010
        .DAT    0x5A
