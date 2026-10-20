; Stores into fetched code from late shifts and two-cycle instructions, and
; stores into the constant words of early jumps and of late shifts.
        MOVE    R1, 0
        MOVE    R2, cnt
        0<0     @R15, R1, @cnt      ; a three-cycle store (late count) into the next word
        HALT
        C>C     @R15++, R1, @R2     ; into the next word, and jump over it
        HALT
        0<0     @2[R15], R1, R2++   ; the HALT two words on, count with a side effect
        MOVE    R3, 1
        HALT
        MOVE    @e1+1, good1        ; the constant of an early jump already in DECODE
e1      MOVE    R15, bad
        HALT
good1   MOVE    @e2+1, 4            ; the offset of an early relative jump
e2      ADD     R15, R15, 1
        HALT
        HALT
        HALT
        HALT
        MOVE    @s1+2, 4            ; the constant count of the next shift
s1      0<0     R4, R3, 1           ; R4 = 1 << 4
        MOVE    @s2+1, 0x10         ; the constant s0 of a late shift
s2      0<0     R4, 0x1, @cnt       ; R4 = 0x10 << 5
        MOVE    R5, s3+1
        MOVE    @R5++, 0x20         ; through a register just written, into the next instruction's constant
s3      MOVE    R6, 0x2
        MOVE    R5, s4+1
        0<0     @R5, R3, @cnt       ; late store into the next constant: 1 << 5
s4      MOVE    R6, 0x2
        MOVE    R7++, s5+1          ; two-cycle write of the address
        MOVE    @R7, 0x40           ; R7 = s5 + 2: the constant of s5
s5      MOVE    R6, 0x2
        ADD[M]  R0, R0, R0          ; Z = 1
        ?Z MOVE @s6+1, 0x50         ; a conditional store into fetched code
s6      MOVE    R6, 0x2
        ?!Z MOVE @s7+1, 0x60        ; skipped
s7      MOVE    R6, 0x2
        MOVE    R8, 0x0C000000
        MOVE    @h1, 0              ; the HALT after a late shift becomes a NOP
        0<0     R9, R1, @cnt
h1      HALT
        MOVE    @h2, 0
        MOVE    R9++, 1             ; a two-cycle instruction before the hit
h2      HALT
        0<0     R9, R1, @cnt
        MOVE    @h3, R1             ; the stored value is 0 (R1)
h3      HALT
        MOVE    R9++, 1
        MOVE    @h4, R1
h4      HALT
        MOVE    R9, 0x0C000000
        MOVE    @h5, R1             ; a store followed by a jump over a HALT
        MOVE    R15, h6
h5      HALT
h6      HALT
cnt     .DAT    5
bad     .DAT    0x0FE00000
