; With vector tables for every VBASE it uses, for runs with an NMI (vector
; 8) or an IRQ (vector 9) before each step, which test/irq_sweep.py makes;
; E = 1 at every step but those of the R14 section, so every request is
; taken.
        MOVE    R15, start
        .ORG    8
        .DAT    nmi, irq
        .ORG    0x108
        .DAT    nmi, irq
        .ORG    0x208
        .DAT    nmi, irq
        .ORG    0x308
        .DAT    nmi, irq
        .ORG    0x408
        .DAT    nmi, irq
        .ORG    0x500
nmi     ADD[M]  @nmis, @nmis, 1
        RTI
irq     SUB[M]  @irqs, @irqs, 1
        RTI
nmis    .DAT    0
irqs    .DAT    0
start   MOVE    R14, 0x40000000
; Shift counts PREPARE cannot reduce (MICROARCH.md §7.3): the count register
; written by the instruction before (SRC_LAST), by a two-cycle destination,
; by a late shift; counts through adders and memory on a register just
; written; counts in R14 and R15; the C flag of one late shift feeding the
; next; and a late shift's result read by every kind of field.
        MOVE    R1, 0x9ABCDEF1
        MOVE    R9, 0x12345678
        MOVE    R10, scratch
; count in a register the previous instruction writes
        MOVE    R2, 3
        0<0[M]  R3, R1, R2
        MOVE    R2, 33
        C<C[M]  R3, R1, R2
        MOVE    R2, 34
        C>C[M]  R3, R1, R2
        ADD     R2, R2, 30      ; 64
        <<<[M]  R3, R1, R2
        SUB     R2, R2, 1       ; 63
        >>C[M]  R3, R1, R2
        MOVE    R2, 1
        0>C[M]  R3, R1, R2
        MOVE    R2, 32
        1>C[M]  R3, R1, R2
        MOVE    R2, 33
        C<0[M]  R3, R1, R2
; count just loaded from memory
        MOVE    R2, @cnt
        0<1[M]  R3, R1, R2
        MOVE    R2, @cnt3
        C>C[M]  R3, R1, R2
; count register written by a two-cycle destination
        MOVE    R2++, 4         ; R2 = 5
        0<0[M]  R3, R1, R2
        MOVE    R2--, 33        ; R2 = 32
        C<0[M]  R3, R1, R2
        ADD     R2++, R2, 1     ; R2 = 34
        C>C[M]  R3, R1, R2
        MOVE    R2--, 1         ; R2 = 0
        C<C[M]  R3, R1, R2
; count written by a late shift, then used as the count
        0<0     R2, R9, @cnt    ; R2 = 0x12345678 << 5
        0>0[M]  R3, R1, R2      ; huge count
        C<C     R2, R0, @cnt2   ; R2 = C (rotate 0 by 1 through C)
        C<C[M]  R3, R1, R2
        MOVE    R2, 3
        >>>     R2, R2, R2      ; R2 = 3 ror 3 = 0x60000000
        <<<[M]  R3, R1, R2      ; count mod 32 = 0
        C>C     R2, R2, R2      ; late rotation whose count is its own s0
        C>C[M]  R3, R1, R2
; counts through adders and memory on a register just written
        MOVE    R2, 5
        0<0[M]  R3, R1, 1[R2]   ; 6
        MOVE    R2, 5
        0<0[M]  R3, R1, --R2    ; 4, R2 = 4
        MOVE    R2, 5
        0<0[M]  R3, R1, R2++    ; 5, R2 = 6
        MOVE    R2, cnt
        0<0[M]  R3, R1, @R2
        MOVE    R2, cnt+1
        0<0[M]  R3, R1, @--R2
        MOVE    R2, cnt
        0<0[M]  R3, R1, @R2++
        MOVE    R2, cnt-7
        0<0[M]  R3, R1, @7[R2]
        MOVE    R2, 34
        C>C[M]  R3, R1, 1[R2]   ; 35
        MOVE    R2, 34
        C>C[M]  R3, R1, --R2
        MOVE    R2, 34
        C>C[M]  R3, R1, R2++
        MOVE    R2, cnt3
        C>C[M]  R3, R1, @R2
        MOVE    R2, cnt3+1
        C>C[M]  R3, R1, @--R2
        MOVE    R2, cnt3
        C>C[M]  R3, R1, @R2++
        MOVE    R2, cnt3-7
        C>C[M]  R3, R1, @7[R2]
        MOVE    R2, cnt3
        C<C[M]  R3, @R2++, @R2  ; s0 from memory too, s1 after s0's side effect
        MOVE    R2, cnt
        <<<[M]  R3, @R2, @R2++
        MOVE    R2, cnt
        0<0[M]  R3, @R2++, R2   ; count = R2 after the increment: huge
        MOVE    R2, 3
        0<0[M]  R3, R2++, R2    ; 3 << 4
        MOVE    R2, 34
        C>C[M]  R3, R2, --R2    ; 34 rotated by 33 = 34 rotated by 0
; counts in R14 and R15
        MOVE    R14, 0x01000003
        0<0[M]  R3, R1, R14     ; count = SR, huge
        SUB[M]  R0, R0, 1       ; C = 1
        0<C[M]  R3, R1, R14
        C<C[M]  R3, R1, R14     ; SR mod 33
        C>C     R3, R1, --R14   ; count SR - 1, R14 decremented
        C>C[M]  R3, R1, R14++   ; R14 incremented
        <<<[M]  R3, R1, R15     ; next address mod 32
        C<C[M]  R3, R1, R15
        0<0[M]  R3, R1, 1[R15]
        >>>[M]  R3, R1, R15++   ; skips the next word
        HALT
        >>>[M]  R3, R15, R15    ; s0 and count both R15
        C>C[M]  R3, R15++, R15
        HALT
        SUB[M]  R0, R0, 1       ; C = 1
        C<C[M]  R3, R14, R14    ; s0 = SR, count = SR
        C<C[M]  R14, R0, 1      ; dest R14 register-direct: no flags; VBASE = 0 or 1
        ?C MOVE R4, 0xC1
        ?!C MOVE R4, 0xC0
        MOVE    R14, 0x41000000 ; E = 1 again, so that a request before any step is taken
; the C of one late shift feeds the next
        SUB[M]  R0, R0, 1       ; C = 1
        MOVE    R2, 1
        C<C[M]  R3, R1, R2      ; C = bit 31 of R1
        C>C[M]  R3, R3, R2
        0>C[M]  R3, R3, R2
        MOVE    R2, 0
        C<C[M]  R3, R1, R2      ; count 0: C unchanged
        C<C[M]  R3, R1, @cnt0
        MOVE    R2, 0
        C<<[M]  R3, R1, R2
        0<C     R3, R1, R2      ; M = 0: no flag change
        MOVE    R2, 40
        C<0[M]  R3, R1, R2      ; n > 32: C = fill
        MOVE    R2, 32
        C<0[M]  R3, R1, R2      ; n = 32: C = bit 0 of s0
        MOVE    R2, 32
        0>C[M]  R3, R1, R2      ; C = bit 31 of s0
; a late shift's result read by every kind of field
        MOVE    R2, 4
        0<0     R5, R1, R2
        MOVE    R6, R5          ; plain
        MOVE    R2, 4
        0<0     R5, R9, R2
        ADD     R6, 1[R5], R0   ; adder
        MOVE    R2, 32
        <<<     R5, R10, R2     ; R5 = scratch
        MOVE    R7, @R5         ; read address
        MOVE    R2, 32
        <<<     R5, R10, R2
        MOVE    @R5, R6         ; store address
        MOVE    R2, 32
        <<<     R5, R10, R2
        MOVE    @R5++, R6
        MOVE    R2, 32
        <<<     R5, R10, R2
        MOVE    @--R5, R6
        MOVE    R2, 32
        <<<     R5, R10, R2
        MOVE    @1[R5], R6
        MOVE    R2, 32
        <<<     R5, R10, R2
        MOVE    R6, @R5++
        MOVE    R2, 32
        <<<     R5, R10, R2
        MOVE    R6, @--R5
        MOVE    R2, 32
        <<<     R5, R10, R2
        MOVE    R6, @2[R5]
        MOVE    R2, 32
        <<<     R5, R10, R2
        0<0     R6, R1, @R5     ; count read through the late result
        MOVE    R2, 33
        C<C     R5, R10, R2     ; 33-bit rotation by 33: R5 = scratch
        C>C     R6, R1, @R5++   ; three-cycle shift with a read and a side effect
        MOVE    R2, 33
        C<C     R5, R10, R2
        MOVE    @R5++, R5       ; store through, and of, the late result
        HALT
cnt     .DAT    5
cnt0    .DAT    0
cnt2    .DAT    1
cnt3    .DAT    34
        .ORG    0x1000
scratch .DAT    0x111, 0x222, 0x333, 0x444
