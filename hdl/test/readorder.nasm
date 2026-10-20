; The number and order of data reads (ISA.md §8.2) through the read counter,
; with late shifts, two-cycle destinations, skipped instructions, and
; interrupt vectors. Every read of COUNT returns the reads of it so far.
COUNT   .EQU    0xFFFFFF01
        MOVE    R15, start
        .ORG    4
        .DAT    isr
        .ORG    0x100
start   MOVE    R4, COUNT
        MOVE    @R4, 0
        MOVE    R1, 0x9ABCDEF1
        0<0     R2, @R4, @R4        ; s0 = 0, s1 = 1
        C>C     R2, @R4, @R4        ; s0 = 2, s1 = 3
        C<C     R2, @R4++, @--R4    ; 4, 5
        >>>     R2, @--R4, @R4++    ; reads 0xFFFFFF00 (console: 0x200), then 6
        ADD     R2, @R4, @R4        ; 7, 8
        MOVE    R2, @R4             ; 9
        MOVE    R3, R4
        MOVE    R2++, @R4           ; 10, two cycles
        ADD     R3--, @R4, @R4      ; 11, 12
        SUB[M]  R0, R0, R0          ; Z = 1
        ?!Z 0<0 R2, @R4, @R4        ; no reads
        ?!Z MOVE R2++, @R4
        ?Z 0<0  R2, @R4, R2         ; 13
        0<0     R2, R1, @R4         ; 14
        0<0     @R4, R1, @R4        ; 15, and a write that resets the counter
        MOVE    R2, @R4             ; 1
        MOVE    R5, R4
        0<0     R2, @R5++, @R4      ; 2, 3
        C>C     R2, @--R5, @R5++    ; 4, 5
        INT     4                   ; the vector read is a data access, not of COUNT
        MOVE    R2, @R4             ; 6
        MOVE    R14, 0x40000000     ; E = 1
        MOVE    R2, @R4             ; 7
        MOVE    R6, @R4             ; 8
        HALT
isr     MOVE    R7, @R4
        RTI
