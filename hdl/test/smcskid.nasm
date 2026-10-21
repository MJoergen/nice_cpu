; Stores into the target of an early jump that waits in PREPARE behind
; the store (MICROARCH.md §5.5). The store waits in WRITE, so the jump waits
; in PREPARE, and DECODE goes on with the jump's target. Each target is the
; last word of a block of 32, so that FETCH has moved on to the next block,
; and the jump's own block is far away. The first three stores come while
; the target is in dec_r. The last, a rotation through C that takes three
; cycles in WRITE, comes when the target waits in DECODE's skid_r, which
; only the compare with skid_r covers. If a store is missed, the old
; instruction runs, and the trace differs from the emulator's.
        MOVE    R9, 1
        MOVE    R1, x1
        MOVE    R2, t1
        MOVE    @R1, @R2            ; MOVE R4, R9 over MOVE R3, R9
        MOVE    R15, x1
        HALT

        .ORG    0x3F
x1      MOVE    R3, R9
        MOVE    R5, R9
        MOVE    R1, x2
        MOVE    R2, t2
        MOVE    R6, R9
        MOVE    @R1, @R2            ; the same, with one instruction in between
        MOVE    R15, x2
        HALT

        .ORG    0x7F
x2      MOVE    R7, R9
        MOVE    R10, R9
        MOVE    R1, x3
        MOVE    R12, @t3
        0<0     @R1, R12, @zero     ; a late shift by 0: a store two cycles in WRITE
        MOVE    R15, x3
        HALT

        .ORG    0xBF
x3      MOVE    R11, R9
        MOVE    R1, x4
        C>C     @R1, @t4, @zero     ; a rotation through C by 0 from memory: three cycles
        MOVE    R15, x4
        HALT

        .ORG    0xFF
x4      MOVE    R3, R9
        HALT

t1      MOVE    R4, R9
t2      MOVE    R8, R9
t3      MOVE    R13, R9
t4      MOVE    R7, R9
zero    .DAT    0
