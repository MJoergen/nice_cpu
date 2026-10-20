; Shifts with R15 as the destination in mode 000: the jump's target is the
; shifted value, not s0 (ISA.md §4.3). 0<0 has the opcode of MOVE, 0000, in
; the shift class, which WRITE must not take for a MOVE when it picks the
; target it can redirect to at once (MICROARCH.md §5.4, §7.4); the other
; shifts take a second cycle. Each wrong target holds a HALT, so a core
; that jumps to s0 stops early. The emulator's trace is the reference.
        MOVE    R1, 0x80
        0<0     R15, R1, 1          ; R15 = 0x100
        HALT
        .ORG    0x80
        MOVE    R2, 0x80            ; wrong target: s0
        HALT
        .ORG    0x100
        MOVE    R2, 0x100           ; right target: s0 << 1
        MOVE    R1, 0x200
        0<0     R15, R1, R0         ; count 0: R15 = 0x200, s0 = 0x200 too
        HALT
        .ORG    0x200
        MOVE    R3, 0x200
        MOVE    R1, 0x10
        MOVE    R2, 6
        0<0     R15, R1, R2         ; a late count: R15 = 0x400
        HALT
        .ORG    0x400
        MOVE    R4, 0x400
        MOVE    R1, 0x1000
        0>0     R15, R1, 1          ; opcode 1000: two cycles, R15 = 0x800
        HALT
        .ORG    0x800
        MOVE    R5, 0x800
        MOVE    R1, 0x300
        C<C     R15, R1, 1          ; opcode 0101: two cycles, R15 = 0x600 (C = 0)
        HALT
        .ORG    0x600
        MOVE    R6, 0x600
        MOVE    R1, 0x600
        0<0[M]  R15, R1, 1          ; with flags: R15 = 0xC00
        HALT
        .ORG    0xC00
        MOVE    R7, 0xC00
        MOVE    R1, 0x700
        SUB[M]  R0, R0, R0          ; Z = 1
        ?Z 0<0  R15, R1, 1          ; conditional: R15 = 0xE00
        HALT
        .ORG    0xE00
        MOVE    R8, 0xE00
        MOVE    R1, 0x780
        0<0     R15++, R1, 1        ; mode 010: R15 = 0xF00, then 0xF01
        HALT
        .ORG    0xF00
        HALT                        ; jumped over
        MOVE    R9, 0xF01
        HALT
