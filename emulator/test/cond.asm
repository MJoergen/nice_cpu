; All sixteen conditions (ISA.md §3). Each condition sets its own bit, so a
; wrong one shows which.
        MOVE    R14, 0xFF000000 ; every flag set
?1      OR      R1, R1, 0x01
?X      OR      R1, R1, 0x02
?C      OR      R1, R1, 0x04
?Z      OR      R1, R1, 0x08
?N      OR      R1, R1, 0x10
?V      OR      R1, R1, 0x20
?E      OR      R1, R1, 0x40
?I      OR      R1, R1, 0x80    ; R1 = ff
?!1     OR      R2, R2, 0x01
?!X     OR      R2, R2, 0x02
?!C     OR      R2, R2, 0x04
?!Z     OR      R2, R2, 0x08
?!N     OR      R2, R2, 0x10
?!V     OR      R2, R2, 0x20
?!E     OR      R2, R2, 0x40
?!I     OR      R2, R2, 0x80    ; R2 = 0
        MOVE    R14, 0          ; every flag clear
?1      OR      R3, R3, 0x01
?X      OR      R3, R3, 0x02
?C      OR      R3, R3, 0x04
?Z      OR      R3, R3, 0x08
?N      OR      R3, R3, 0x10
?V      OR      R3, R3, 0x20
?E      OR      R3, R3, 0x40
?I      OR      R3, R3, 0x80    ; R3 = 01
?!1     OR      R4, R4, 0x01
?!X     OR      R4, R4, 0x02
?!C     OR      R4, R4, 0x04
?!Z     OR      R4, R4, 0x08
?!N     OR      R4, R4, 0x10
?!V     OR      R4, R4, 0x20
?!E     OR      R4, R4, 0x40
?!I     OR      R4, R4, 0x80    ; R4 = fe
        HALT
