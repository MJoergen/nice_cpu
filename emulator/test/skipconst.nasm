; A skipped instruction takes its constant words, in every class, and a
; control instruction takes none, even when its low bits look like operand
; fields that would take one (ISA.md §2.3, §3, §5 step 2). Every constant
; word here is H = 0x0C000000, a HALT, so a constant word that was not
; taken would run and end the program early. The skipped instructions also
; have side effects that must not happen.
;
;   words 0,1  R2 = 0x200
;   2,3        ?!1 SHL R1, R2, H          a SHIFT, s1 constant
;   4-6        ?!1 SHL @H, R2++, H        dest and s1 constants; no R2++
;   7-10       ?!1 ROL @H, H, H           three constants
;   11,12      ?!1 SHL @R2++, H, R2       s0 constant; no R2++
;   13,14      ?!1 MOVE @H, R2            an ALU, dest constant only
;   15,16      ?!1 MOVE R1, @H[R2]        s0 constant, mode 111
;   17         ?!1 0x8C4000FF             reserved command 2, with bits 6..0
;                                         = 111 1111
;   18         ?!1 0x8C0FFFFF             a reserved HALT with bits 20..8 set:
;                                         dest 011 1111, s0 and s1 111 1111
;   19         ?Z 0x3C800000              reserved command 4, Z = 0: skipped
;   20,21      MOVE R3, 1                 runs: R3 = 1
;   22         0x0C000033                 a reserved HALT with bits 6..0 =
;                                         011 0011, mode 011, which runs and
;                                         halts. It takes no constant, so
;                                         PC = 23 after it, not 24.
;   23         H                          never runs
;
; Steps: 1 + 9 skipped + 1 + 1 = 12. The halt is a reserved one, exit
; status 2. R1 = 0 and R2 = 0x200 show that no skipped instruction ran or
; applied a side effect.
H               .EQU    0x0C000000
                MOVE    R2, 0x200       ; words 0,1
        ?!1     SHL     R1, R2, H       ; words 2,3
        ?!1     SHL     @H, R2++, H     ; words 4-6
        ?!1     ROL     @H, H, H        ; words 7-10
        ?!1     SHL     @R2++, H, R2    ; words 11,12
        ?!1     MOVE    @H, R2          ; words 13,14
        ?!1     MOVE    R1, @H[R2]      ; words 15,16
                .DAT    0x8C4000FF      ; word 17
                .DAT    0x8C0FFFFF      ; word 18
                .DAT    0x3C800000      ; word 19
                MOVE    R3, 1           ; words 20,21
                .DAT    0x0C000033      ; word 22
                .DAT    H               ; word 23
