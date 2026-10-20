; A skipped instruction takes its constant words, in every class, and a
; control instruction takes none, even when its low bits look like operand
; fields that would take one (ISA.md §2.3, §3, §5 step 2). Every constant
; word here is H = 0x0C000000, a HALT, so a constant word that was not
; taken would run and end the program early. The skipped instructions also
; have side effects that must not happen.
;
;   words 0-3  VBASE = 1, so the vector table is at 0x100; R2 = 0x200
;   4,5        ?!1 SHL R1, R2, H          a SHIFT, s1 constant
;   6-8        ?!1 SHL @H, R2++, H        dest and s1 constants; no R2++
;   9-12       ?!1 ROL @H, H, H           three constants
;   13,14      ?!1 SHL @R2++, H, R2       s0 constant; no R2++
;   15,16      ?!1 MOVE @H, R2            an ALU, dest constant only
;   17,18      ?!1 MOVE R1, @H[R2]        s0 constant, mode 111
;   19         ?!1 INT 0xFF               bits 6..0 = 111 1111
;   20         ?!1 0x8C0FFFFF             a reserved HALT with bits 20..8 set:
;                                         dest 011 1111, s0 and s1 111 1111
;   21         ?Z 0x3C600000              reserved command 3, Z = 0: skipped
;   22         INT 0x33                   runs; bits 6..0 = 011 0011, mode 011.
;                                         It takes no constant, so it saves
;                                         PC = 23 and goes to isr.
;   isr        MOVE R5, R15; RTI          isr = 0x1A, so R5 = 0x1B
;   23,24      MOVE R3, 1                 runs after RTI: R3 = 1
;   25         HALT
;
; If INT 0x33 took word 23 as a constant, RTI would return to word 24, the
; constant 1 of MOVE R3, 1, which runs as a NOP, and R3 would stay 0.
;
; Steps: 2 + 9 skipped + INT + 2 in isr + 2 = 16. PC = 0x1A after the
; HALT at 0x19. R1 = 0 and R2 = 0x200 show that no skipped instruction ran
; or applied a side effect. RTI restores R14 = 0x01000001.
H       .EQU    0x0C000000
        MOVE    R14, 1          ; words 0,1
        MOVE    R2, 0x200       ; words 2,3
?!1     SHL     R1, R2, H       ; words 4,5
?!1     SHL     @H, R2++, H     ; words 6-8
?!1     ROL     @H, H, H        ; words 9-12
?!1     SHL     @R2++, H, R2    ; words 13,14
?!1     MOVE    @H, R2          ; words 15,16
?!1     MOVE    R1, @H[R2]      ; words 17,18
?!1     INT     0xFF            ; word 19
        .DAT    0x8C0FFFFF      ; word 20
        .DAT    0x3C600000      ; word 21
        INT     0x33            ; word 22
        MOVE    R3, 1           ; words 23,24
        HALT                    ; word 25
isr     MOVE    R5, R15         ; word 26
        RTI                     ; word 27
        .ORG    0x133
        .DAT    isr
