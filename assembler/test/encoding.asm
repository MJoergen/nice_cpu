; Encoding test: covers every mode, condition, class and directive.
; The expected output in encoding.bin was checked by hand against doc/ISA.md.
SP      .EQU    R13
PC      .EQU    R15
TEN     .EQU    10

        .ORG    0
        MOVE    R0, R0                  ; canonical NOP, all zero
        ?!Z ADD[M] @R3++, --R2, @0x12345678[R1]    ; ISA.md section 11
        ADD     @0x40, R1, 7            ; ISA.md section 2.3
; source modes
        MOVE    R1, R2
        MOVE    R1, --R2
        MOVE    R1, R2++
        MOVE    R1, 5[R2]
        MOVE    R1, @R2
        MOVE    R1, @--R2
        MOVE    R1, @R2++
        MOVE    R1, @-1[R2]
; destination modes
        MOVE    R3, R1
        MOVE    R3--, R1
        MOVE    R3++, R1
        MOVE    TEN[R3], R1
        MOVE    @R3, R1
        MOVE    @--R3, R1
        MOVE    @R3++, R1
        MOVE    @data, R1
; all ALU opcodes, modifiers, register spellings and aliases
        sub[c]  r1, r2, r3
        MDBL[MC] R1, R2, R3
        DBL[CM] R1, R2
        DEC     R1, R2
        NOT     R1, R2
        NOR     R1, R2, R3
        IAND    R1, R2, R3
        NAND    R1, R2, R3
        XOR     R1, R2, R3
        IOR     R1, R2, R3
        XNOR    R1, R2, R3
        AND     R1, R2, R3
        ONE     R01
        OR      R1, R2, R3
        MOVE    PC, SP
; shifts
        0<0     R1, R2, 1
        0<1     R1, R2, R3
        0<C     R1, R2, R3
        C<0[M]  R1, R2, R3
        C<1     R1, R2, R3
        C<C     R1, R2, R3
        <<<     R1, R2, R3
        C<<     R1, R2, R3
        0>0     R1, R2, R3
        1>0     R1, R2, R3
        C>0     R1, R2, R3
        0>C     R1, R2, R3
        1>C     R1, R2, R3
        C>C     R1, R2, R3
        >>>     R1, R2, R3
        >>C     R1, R2, R3
        SHL     R1, R2, R3
        ROR     R1, R2, R3
; conditions
        ?1  MOVE R1, R2
        ?X  MOVE R1, R2
        ?C  MOVE R1, R2
        ?Z  MOVE R1, R2
        ?N  MOVE R1, R2
        ?V  MOVE R1, R2
        ?E  MOVE R1, R2
        ?I  MOVE R1, R2
        ?!1 MOVE R1, R2
        ?!M MOVE R1, R2
; control
        HALT
        RTI
        INT     0x21
        ?Z HALT
; data and expressions
data:   .DAT    0b101, 0x10+TEN-1, -1, data
        .ASCII_L "Hi"
        .ASCII_B 'ABCDE'
        .ASCII_B 'ABCD'
        .ORG    0x100
        .BLK    2
        MOVE    R1, end-data
end
