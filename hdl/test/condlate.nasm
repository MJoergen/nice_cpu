; Conditional late shifts whose condition PREPARE cannot know, two-cycle
; destinations in R14 with late counts, HALT and INT right after two-cycle
; flag writes, never-executed instructions with every hazard, and a few
; more R15 forms.
        MOVE    R15, start
        .ORG    4
        .DAT    isr
        .ORG    0x100
start   MOVE    R1, 0x9ABCDEF1
        MOVE    R10, scratch
        SUB[M]  R2, R0, R0          ; Z = 1, R2 = 0
        ?Z 0<0  R3, R1, R2          ; count from the value written last, condition in WRITE
        ADD[M]  R2, R0, 3           ; Z = 0
        ?Z C<C  R3, R1, R2          ; skipped: three cycles, not taken
        ?!Z C<C R3, R1, R2          ; three cycles, R2 is the value written last
        ADD[M]  R2, R0, 34
        ?!Z C>C R3, @R10, R2        ; a read waits for the condition, then a late count
        SUB[M]  R2, R0, R0          ; Z = 1
        ?Z 0<0  R3, R1, 1[R2]       ; an adder on the value written last
        SUB[M]  R2, R2, 1           ; R2 = -1, X = 1, C = 1
        ?X C>C  R3, R1, R2          ; count 0xFFFFFFFF
        ?C 0<0  R3, R1, --R2        ; count 0xFFFFFFFE, R2 = -2
        MOVE    R2, 3
        0<0[M]  R14++, R1, R2       ; late count, two-cycle destination R14: no flags
        MOVE    R4, R14
        MOVE    R14, 0x01000000
        MOVE    R2, 1
        C<C[M]  R14--, R1, R2       ; three cycles plus the adjustment
        MOVE    R4, R14
        MOVE    R14, 0x01000000
        MOVE    R2, 2
        0<0     R2++, R1, R2        ; the count register is the two-cycle destination
        0<0     R2--, R2, R2
        C>C     R2++, R2++, R2++    ; everything on R2
        ADD[M]  R5++, R0, R0        ; Z = 1 from r = 0, R5 = 1
        ?!Z HALT                    ; skipped
        ?Z INT  4                   ; taken: the routine clears Z, RTI restores it
        ?Z MOVE R6, 1
        ADD[M]  R5--, R0, 1         ; Z = 0, R5 = 0
        ?Z HALT
        ?Z INT  4                   ; skipped
        ?!Z MOVE R6, 2
        ?!1 C<C R2++, @R2++, @--R2  ; never: no reads, no side effects, no two cycles
        ?!1 0<0 R15, R1, @R10
        ?!1 MOVE R14++, 0
        ?!1 INT 4
        ?!1 RTI
        ?!1 HALT
        MOVE    R7, R2
        MOVE    R15++, R15          ; R15 = next, then next + 1
        HALT
        ADD     R15, 1, R15         ; early, the constant first
        HALT
        ADD[M]  R15, 2, R15         ; early with flags
        HALT
        HALT
        MOVE    R2, 4
        C<0     R15, 1[R0], R2      ; s0 = 1 shifted by 4 = 0x10: a two-cycle jump to 0x10, late count
        HALT
        .ORG    0x10
        MOVE    R8, 0x10
        MOVE    R15, next
next    MOVE    R2, 0x100
        0<0     R15++, R2, 1        ; R15 = 0x200, then 0x201
        HALT
        .ORG    0x200
        HALT
        MOVE    R2, 0x300
        0<0     R15, R2, R0         ; count 0: R15 = 0x300
        HALT
        .ORG    0x300
        MOVE    R1--, j9+1
        MOVE    R15, R1             ; the target is the adjusted value written last
        HALT
j9      MOVE    R1++, 1
        ADD     R15, R15, R1        ; two-cycle jump by the adjusted value: over two words
        HALT
        HALT
        MOVE    R9, 0x300
        HALT
isr     ADD[M]  R0, R0, 1
        RTI
        .ORG    0x1000
scratch .DAT    0x111, 0x222
