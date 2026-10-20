; Two-cycle destinations, late shifts, R14 and R15 side effects, and
; conditional reads, for runs with an NMI (vector 8) or an IRQ (vector 9)
; before each step. The routines count and change the flags; RTI restores
; them. VBASE stays 0.
        MOVE    R15, start
        .ORG    8
        .DAT    nmi, irq
        .ORG    0x108
        .DAT    nmi, irq            ; the table for VBASE = 1
        .ORG    0x300
start   MOVE    R13, stack
        MOVE    R14, 0x40000000
        MOVE    R1, 0x9ABCDEF1
        MOVE    R10, scratch
        MOVE    R2, 4
        0<0[M]  R3, R1, R2
        MOVE    R2++, 33
        C<C[M]  R3, R1, R2
        ADD[M]  R4--, R2, R2
        ?Z MOVE R5, @R10
        ?!Z MOVE R5, @1[R10]
        C>C     R6, @R10++, @R10
        MOVE    R7, @--R10
        MOVE    R15++, j1
j1      HALT
        MOVE    R14++, 0x40FFFFFF   ; 0x41FFFFFF then 0x42000000 | bit 24
        ?X MOVE R5, @R10
        MOVE    R14, 0x40000000
        MOVE    R8, R14++           ; E = 1, R14 = 0x41000001: VBASE = 1
        MOVE    R14, 0x40000000
        SUB[M]  R0, R0, R0
        ?Z ADD  R15, R15, 2
        HALT
        HALT
        MOVE    R2, 34
        C>C[M]  R9--, R1, R2        ; late shift with a two-cycle destination
        ADD[M]  @--R13, R9, R2
        MOVE    R11, @R13++
        0<0     @R15, R0, @cnt      ; a store into the next word
        HALT
        MOVE    @h1, 0
        MOVE    R9++, 1
h1      HALT
        ADD     R4, R15++, R15
        HALT
        MOVE    R2, 1
        C<C[M]  R3, R1, R2
        C>C[M]  R3, R3, R2
        MOVE    R2, 0
        C<C[M]  R3, R1, R2
        ?C MOVE R5, @R10
        ?!C MOVE R5, @1[R10]
        INT     8
        ?I MOVE R5, 0xBAD
        MOVE    R12, 0
        HALT
nmi     ADD[M]  @nmis, @nmis, 1
        MOVE    R2++, R2
        RTI
irq     SUB[M]  @irqs, @irqs, 1
        C<C[M]  R3, R3, @cnt
        RTI
cnt     .DAT    5
nmis    .DAT    0
irqs    .DAT    0
        .ORG    0x1000
scratch .DAT    0x111, 0x222
        .BLK    16
stack
