; Two-cycle destinations (Rx++ and Rx-- as a register destination) followed
; by every kind of reader, with flags, with conditions, in chains, on R14,
; and two-cycle jumps (an operation other than MOVE on R15).
        MOVE    R10, scratch
        MOVE    @scratch, 0x111
        MOVE    @scratch+1, 0x222
        MOVE    @scratch+2, 0x333
        MOVE    R1++, R10       ; R1 = scratch + 1
        MOVE    R2, R1          ; plain
        MOVE    R1++, R10
        ADD     R2, 3[R1], R0   ; adder
        MOVE    R1--, R10
        MOVE    R2, @1[R1]
        MOVE    R1++, R10
        MOVE    R2, @R1         ; read address
        MOVE    R1++, R10
        MOVE    R2, @--R1
        MOVE    R1++, R10
        MOVE    R2, @R1++
        MOVE    R1++, R10
        MOVE    @R1, 0x333      ; store address
        MOVE    R1++, R10
        MOVE    @R1++, 0x444
        MOVE    R1++, R10
        MOVE    @--R1, 0x555
        MOVE    R1++, R10
        MOVE    @2[R1], 0x666
        MOVE    R1++, R10
        MOVE    1[R1], 0x777
        MOVE    R1++, R10
        MOVE    R2, --R1
        MOVE    R1++, R10
        MOVE    R2, R1++
        MOVE    R1++, 2
        0<0[M]  R2, R10, R1     ; shift count from a two-cycle write
        MOVE    R1--, 34
        C>C[M]  R2, R10, R1
        MOVE    R1++, R10
        ADD     R2, R1, R1      ; both sources
        MOVE    R1++, R10
        ADD     R2, @R1, @--R1
        MOVE    R1++, R10
        MOVE    R1++, R1        ; two-cycle on its own result: scratch + 3
        MOVE    R1--, R1
        MOVE    R2, R1
; flags of a two-cycle destination come from r, not from the adjusted value
        ADD[M]  R1--, R1, R1
        ?Z MOVE R2, 0x77
        ADD[M]  R1--, R0, 1     ; r = 1: Z = 0, R1 = 0
        ?Z MOVE R2, 0x88        ; skipped
        ?!Z MOVE R2, 0x99
        MOVE[M] R1++, 0xFFFFFFFF ; X = 1, N = 1, R1 = 0
        ?X MOVE R2, @scratch    ; a conditional read after a two-cycle flag write
        ?Z MOVE R2, @scratch+1  ; skipped, no read
        ?N MOVE @scratch+3, R2
        SUB[M]  R1++, R0, R0    ; Z = 1, R1 = 1
        ?Z MOVE R2, @R1         ; read through the register just adjusted
; chains of two-cycle destinations
        MOVE    R1++, 1
        MOVE    R1++, R1
        MOVE    R1++, R1
        ADD     R1--, R1, R1
        MOVE    R2++, R1
        MOVE    R3--, R2
        ADD     R4, R2, R3
        ADD     R4++, R4++, R4  ; s1 reads the incremented R4, dest adjusted
        SUB     R4--, --R4, R4++
; two-cycle destination R14, then readers
        MOVE    R14++, 0x40000010 ; 0x41000011
        MOVE    R2, R14
        ?E MOVE R3, 1[R14]
        ?!E MOVE R3, 0xBAD
        MOVE    R14--, 0x4A000000 ; 0x4AFFFFFF with bit 24: 0x4BFFFFFF
        ?Z ADD  R2, R14, 1
        ?C MOVE R2, --R14
        ?X MOVE R2, R14++
        ?!X MOVE R2, 0xBAD
        MOVE    R14, 0x40000000
; conditional two-cycle destinations right after the flag setters
        SUB[M]  R0, R0, R0      ; Z = 1
        ?Z MOVE R5++, 9         ; R5 = 10
        ?!Z MOVE R5++, 11       ; skipped
        ADD[M]  R0, R0, 1       ; Z = 0
        ?Z MOVE R5--, 20        ; skipped
        MOVE    R6, R5
        ?!Z ADD[M] R5--, R5, R5 ; 20, then 19; flags of 20
        ?Z MOVE R6, 0xBAD
        ?!Z MOVE R6, R5
; two-cycle jumps: an operation other than MOVE with R15 as destination
        MOVE    R1, 2
        ADD     R15, R15, R1    ; over two words
        HALT
        HALT
        MOVE    R1, t1
        ADD     R15, R1, 0      ; the target is the value written last
        HALT
t1      MOVE    R1, t2
        SUB     R15, R1, R0
        HALT
t2      MOVE    R1, t3
        MOVE    R15, R1         ; one cycle, target = value written last
        HALT
t3      MOVE    R1, t4
        OR      R15, R1, R1
        HALT
t4      MOVE    R1, t5-1
        ADD     R15, R1, 1[R0]
        HALT
t5      MOVE    R1, t6
        MOVE    R15, @R1        ; through memory: scratch+4 holds t6? no: R1 = t6, read mem[t6]
t6      .DAT    t7              ; the word at t6 is the target itself
t7      ADD[M]  R15, R15, 2     ; early with M: flags of the target
        HALT
        HALT
        ?N MOVE R2, 0xBAD
        ?!Z MOVE R2, 0x11
        MOVE[M] R15, t8         ; not early: flags from the target
        HALT
t8      ?Z MOVE R2, 0xBAD
        ?!N MOVE R2, 0x22
        SUB[M]  R0, R0, R0      ; Z = 1
        ?Z ADD  R15, R15, 2     ; conditional two-cycle jump
        HALT
        HALT
        ADD[M]  R0, R0, 1       ; Z = 0
        ?Z ADD  R15, R15, 2     ; skipped
        MOVE    R2, 0x33
        ?!Z ADD R15, R15, 1
        HALT
        ?!1 MOVE R15, 0         ; never
        ?!1 ADD  R15, R15, 0
; jumps through SR: the code at far has bit 24 set in its address
        MOVE    R14, far
        ADD     R15, R14, 0     ; two cycles, s0 is SR
        HALT
back1   MOVE    R14, far2
        MOVE    R15, R14        ; one cycle, s0 is SR
        HALT
back2   MOVE    R14, far3
        MOVE    R15, 0[R14]     ; adder on SR
        HALT
back3   MOVE    R14, tbl
        MOVE    R15, @R14       ; read through SR
        HALT
back4   MOVE    R14, tbl
        SUB[M]  R0, R0, 1       ; C, N, X = 1: SR changes before the read, to 0x17000106
        MOVE    R15, @1[R14]    ; reads 0x17000107
        HALT
back5   MOVE    R14, tbl+2
        ADD[M]  R0, R0, R0      ; Z = 1: the read must wait for this SR, 0x09000108
        MOVE    R15, @R14++     ; R14 incremented, then the jump
        HALT
back6   MOVE    R2, R14
        MOVE    R14, 0x01000000
; the destination R15++ and R15--, two cycles and a jump
        MOVE    R15++, j1       ; R15 = j1 + 1
j1      HALT
        MOVE    R15--, j2+1
        HALT
j2      ADD     R15++, R15, 1   ; r = next + 1, R15 = next + 2
        HALT
        HALT
        MOVE    R1, 1
        ADD     R15--, R15, R1  ; r = next + 1, R15 = next
        MOVE    R2, 0x44
        HALT
        .ORG    0x01000100
far     MOVE    R15, back1
far2    MOVE    R15, back2
far3    MOVE    R15, back3
tbl     .DAT    back4, back5, back6
        .ORG    0x17000107
        .DAT    back5
        .ORG    0x09000108
        .DAT    back6
        .ORG    0x1000
scratch .BLK    8
