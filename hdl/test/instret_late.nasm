; The instruction counter (SYSTEM.md §3) read right after two-cycle
; destinations, late shifts, stores, skipped instructions, and INT.
INSTR           .EQU    0xFFFFFF42
                MOVE    R15, start
                .ORG    4
                .DAT    isr
                .ORG    0x100
start           MOVE    R4, INSTR
                MOVE    R1, 0x9ABCDEF1
                MOVE    R2, @R4         ; 2
                MOVE    R3++, 1
                MOVE    R2, @R4         ; 4
                MOVE    R3++, @R4       ; 5
                MOVE    R2, @R4         ; 6
                0<0     R5, R1, @R4     ; 7
                MOVE    R2, @R4         ; 8
                C>C     R5, @R4, @R4    ; 9, 9
                MOVE    R2, @R4         ; 10
                MOVE    @scratch, 1
                MOVE    R2, @R4         ; 12
                SUB[M]  R0, R0, R0
        ?!Z     MOVE    R2, @R4         ; skipped
                MOVE    R2, @R4         ; 15
        ?Z      MOVE    R2, @R4         ; 16
                INT     4
                MOVE    R2, @R4         ; 20: INT, isr's MOVE, RTI count
                MOVE    R15, j1
j1              MOVE    R2, @R4         ; 22
                ADD     R15, R15, R0
                MOVE    R2, @R4         ; 24
                MOVE    R6, R15++
                HALT
                MOVE    R2, @R4         ; 26
                MOVE    @j2, 0
j2              HALT
                MOVE    R2, @R4         ; 29
                ADD     R2, @R4, R4++   ; 30
                MOVE    R2, @0xFFFFFF43  ; the high word
                HALT
isr             MOVE    R7, @R4         ; 18
                RTI
                .ORG    0x1000
scratch         .BLK    4
