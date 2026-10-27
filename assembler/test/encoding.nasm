; Encoding test: covers every mode, condition, class and directive.
; The expected output in encoding.bin was checked by hand against doc/ISA.md.
SP              .EQU    R13
PC              .EQU    R15
TEN             .EQU    10

                .ORG    0
                MOVE    R0, R0          ; canonical NOP, all zero
        ?!Z     ADD[M]  @R3++, --R2, @0x12345678[R1]  ; ISA.md section 11
                ADD     @0x40, R1, 7    ; ISA.md section 2.3
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
        ?1      MOVE    R1, R2
        ?X      MOVE    R1, R2
        ?C      MOVE    R1, R2
        ?Z      MOVE    R1, R2
        ?N      MOVE    R1, R2
        ?V      MOVE    R1, R2
        ?E      MOVE    R1, R2
        ?I      MOVE    R1, R2
        ?!1     MOVE    R1, R2
        ?!M     MOVE    R1, R2
; control
                HALT
                RTI
                INT     0x21
        ?Z      HALT
; data and expressions
data:           .DAT    0b101, 0x10+TEN-1, -1, data
                .ASCII_L "Hi"
                .ASCII_B 'ABCDE'
                .ASCII_B 'ABCD'
                .ORG    0x100
                .BLK    2
                MOVE    R1, end-data
end
; aliases, conditions, modes and spellings not covered above
                .ORG    0x200
                ROL     R1, R2, R3
                BPL     R1, R2, R3
                SHR     R1, R2, R3
                BPR     R1, R2, R3
        ?!X     MOVE    R1, R2
        ?!C     MOVE    R1, R2
        ?!N     MOVE    R1, R2
        ?!V     MOVE    R1, R2
        ?!E     MOVE    R1, R2
        ?!I     MOVE    R1, R2
                MOVE    @3[R2], R1
                MOVE    R1, --R0
                MOVE    R00, R09
                AND     R10, R11, R12
                .ASCII_L ""
                .ASCII_B ''
                .ASCII_L "a;b"          ; a string containing ';'
* a comment starting with '*'
                .BLK    0
; .EQU chains, .EQU naming a label, .EQU standing for a whole operand
CHAIN_A         .EQU    CHAIN_B
CHAIN_B         .EQU    R1
LBL_EQU         .EQU    here
IND             .EQU    @R2
PINC            .EQU    R3++
IDX             .EQU    5[R4]
                MOVE    CHAIN_A, R2
here            MOVE    R1, LBL_EQU
                MOVE    IND, PINC
                MOVE    @IDX, R1
lbl             .ORG    0x300           ; the label names the new address
                .DAT    lbl
; .RES reserves words that are not in the .bin
                .RES    3               ; 0x301-0x303
res_end         .DAT    res_end         ; 0x304
                .RES    0
; Added by the coverage audit. Each comment gives the address and the words,
; derived by hand from ISA.md section 2: a field is mode<<4 | register, dest
; is bits 20..14, s0 13..7, s1 6..0, ADD is opcode 3 (0x00600000), and the
; constant words follow in field order dest, s0, s1.
                .ORG    0x400
; s1 in the modes not used there above (dest R1 = 0x4000, s0 R2 = 0x100)
                ADD     R1, R2, --R3    ; 400: s1 0x13: 00604113
                ADD     R1, R2, R3++    ; 401: s1 0x23: 00604123
                ADD     R1, R2, 6[R3]   ; 402: s1 0x33: 00604133, 403: 6
                ADD     R1, R2, @R3     ; 404: s1 0x43: 00604143
                ADD     R1, R2, @--R3   ; 405: s1 0x53: 00604153
                ADD     R1, R2, @R3++   ; 406: s1 0x63: 00604163
                ADD     R1, R2, @6[R3]  ; 407: s1 0x73: 00604173, 408: 6
                ADD     R1, R2, @6      ; 409: s1 0x70: 00604170, 40a: 6
; three constant words: 0x70<<14 | 0x30<<7 | 0x30
                ADD     @1, 2, 3        ; 40b: 007c1830, 40c-40e: 1, 2, 3
; c alone as a destination is mode 011 with R0: 0x30<<14 | 0x01<<7
                MOVE    5, R1           ; 40f: 000c0080, 410: 5
; R15++ in every field: 0x2f<<14 | 0x2f<<7 | 0x2f
                ADD     R15++, R15++, R15++  ; 411: 006bd7af
; tabs as separators: 0x0e<<14 | 0x04<<7
                MOVE    R14,    R4      ; 412: 00038200
; a leading 0 is decimal, upper case prefixes, signs, chains, and wrap
                .dat    08, 0XAB, 0B11, +5, 1-2-3, 0xFFFFFFFF+2, -0xFFFFFFFF
                ; 413-419: 8, ab, 3, 5, fffffffc, 1, 1
; .ASCII_B with 1 to 3 characters, the first in the low byte, padded with 0
                .ASCII_B 'A'            ; 41a: 00000041
                .ASCII_B "AB"           ; 41b: 00004241
                .ascii_b 'ABC'          ; 41c: 00434241
; a quote of the other kind, no escapes, and ',' and '*' in a string
                .ASCII_L "it's"         ; 41d-421: 69 74 27 73 0
                .ASCII_L '"\n*,'        ; 422-427: 22 5c 6e 2a 2c 0
; lower case condition and modifier, INT at its limit and with an expression
        ?!e     HALT                    ; 428: NEG 1, SEL 110: ec000000
                SHL[m]  R1, R2, R3      ; 429: 08000000 | M 02000000: 0a004103
                INT     255             ; 42a: 0c4000ff
VEC             .EQU    0x1F
                INT     VEC+1           ; 42b: 0c400020
; an .EQU standing for a whole operand, in both fields, and after @
OPW             .EQU    @4[R1]
PDEC            .EQU    --R2
RG              .EQU    R5
                MOVE    OPW, OPW        ; 42c: 0x71<<14 | 0x71<<7: 001c7880, 42d-42e: 4, 4
                MOVE    R1, @PDEC       ; 42f: 0x01<<14 | 0x52<<7: 00006900
                MOVE    @PINC, R1       ; 430: 0x63<<14 | 0x01<<7: 0018c080
                MOVE    RG--, @7[RG]    ; 431: 0x15<<14 | 0x75<<7: 00057a80, 432: 7
; an .EQU used twice in one value, used before its definition, naming a later label
DA              .EQU    3
DB              .EQU    DA+DA-1
                .DAT    DB              ; 433: 5
                .DAT    FWD             ; 434: 9
FWD             .EQU    9
FL              .EQU    flab
                .DAT    FL              ; 435: 436
flab            .DAT    0x55            ; 436: 55
; a label alone on a line, a label before a condition, a '*' comment after an operand
alone:
                .DAT    alone           ; 437: 437
clab    ?Z      HALT                    ; 438: 3c000000
                .DAT    clab            ; 439: 438
                MOVE    R1 ,R2 * comment  ; 43a: 00004100
