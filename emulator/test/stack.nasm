; The lowest SP of --stack (README.md, Stack). R13 is 0 after reset, and
; the count starts at its first change, the MOVE of step 0, so the first
; SP is 0xFFFFFF00, not 0. Every change of R13 counts, a push or a SUB as
; well as a MOVE, and so does the push of a CALL. The steps:
;    0  R13 = FFFFFF00 (first)
;    1  push 1: FFFFFEFF
;    2  push 2: FFFFFEFE
;    3  R13 -= 5: FFFFFEF9 (lowest)
;    4  R13 += 5: FFFFFEFE
;    5  pop R1 = 2: FFFFFEFF
;    6  pop R2 = 1: FFFFFF00
;    7  CALL, one word that pushes: FFFFFEFF
;    8  RET: FFFFFF00
;    9  HALT, at word 0xD
; So the report is first FFFFFF00, lowest FFFFFEF9, 7 words below.
                MOVE    R13, 0xFFFFFF00
                MOVE    @--R13, 1
                MOVE    @--R13, 2
                SUB     R13, R13, 5
                ADD     R13, R13, 5
                MOVE    R1, @R13++
                MOVE    R2, @R13++
                CALL    func
                HALT
func            RET
