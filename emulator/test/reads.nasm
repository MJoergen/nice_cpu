; Data reads happen exactly once each, and in program order (ISA.md §8.2).
; The emulator's read counter at 0xFFFFFF01 (SYSTEM §1) shows them: a data read
; returns the number of data reads of it since the last write, and a write
; sets that number.
;
;   MOVE @R4, 0           a write: count 0
;   MOVE R1, @R4          R1 = 0, count 1
;   .DAT 0x000081C4       MOVE R2, R3 with the unused s1 field @R4 (§4.4):
;                         R2 = 0x33, and the read still happens: count 2
;   ADD R5, @R4, @R4      two reads, 2 + 3: R5 = 5, count 4
;   SUB R6, @R4, @R4      s0 is read first: 4 - 5 = 0xFFFFFFFF, count 6
;   ?Z MOVE R7, @R4       skipped (Z = 0 after reset): no read, R7 = 0
;   MOVE @R4, 100         the destination is written, never read: count 100
;   MOVE R8, @R4          R8 = 100 = 0x64, count 101
;   MOVE R10, @R11++      R10 = 0x65, R11 = 0xFFFFFF02, count 102
;   MOVE R12, @--R11      R11 = 0xFFFFFF01, R12 = 0x66, count 103
;   OR R14, R14, ...      VBASE = 0xFFFFFF, so vector 1 is the counter
;   INT 1                 the vector read: PC = 103 = 0x67, count 104
;   MOVE R13, @R4         at 0x67: R13 = 0x68, count 105
;
; Steps: 14 before INT, INT, and 2 in the routine: 17. PC = 0x69 after the
; HALT. R14 = 0x01FFFFFF with I set by INT: 0x81FFFFFF. The dump reads the
; counter without counting: 105 = 0x69.
COUNT   .EQU    0xFFFFFF01
        MOVE    R4, COUNT
        MOVE    R3, 0x33
        MOVE    @R4, 0
        MOVE    R1, @R4
        .DAT    0x000081C4
        ADD     R5, @R4, @R4
        SUB     R6, @R4, @R4
        ?Z MOVE R7, @R4
        MOVE    @R4, 100
        MOVE    R8, @R4
        MOVE    R11, R4
        MOVE    R10, @R11++
        MOVE    R12, @--R11
        OR      R14, R14, 0xFFFFFF
        INT     1
        .ORG    0x67
        MOVE    R13, @R4
        HALT
