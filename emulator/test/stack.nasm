; The lowest SP of --stack (README.md, Stack), run with --nmi 5:1.
; R13 is 0 after reset, and the count starts at its first change, the
; MOVE of step 1, so the first SP is 0xFFFFFF00, not 0. Every change of
; R13 counts, a push or a SUB as well as a MOVE, and so does the push of
; a CALL. The interrupt entry changes no register but R14 and R15. The
; steps:
;    0  VBASE = 1
;    1  R13 = FFFFFF00 (first)
;    2  push 1: FFFFFEFF
;    3  push 2: FFFFFEFE
;    4  R13 -= 5: FFFFFEF9 (lowest)
;    5  NMI entry
;    6  RTI
;    7  R13 += 5: FFFFFEFE
;    8  pop R1 = 2: FFFFFEFF
;    9  pop R2 = 1: FFFFFF00
;   10  CALL, its ADD: FFFFFEFF
;   11  CALL, its MOVE
;   12  RET: FFFFFF00
;   13  HALT
; So the report is first FFFFFF00, lowest FFFFFEF9, 7 words below.
                MOVE    R14, 1          ; VBASE = 1: the table is at 0x100
                MOVE    R13, 0xFFFFFF00
                MOVE    @--R13, 1
                MOVE    @--R13, 2
                SUB     R13, R13, 5
                ADD     R13, R13, 5
                MOVE    R1, @R13++
                MOVE    R2, @R13++
                CALL    func
                HALT
nmi             RTI
func            RET
                .ORG    0x101
                .DAT    nmi
