; The bounds of the character screen (README.md, Memory map). make test
; runs this program twice: with -s, which prints the 2000 words from
; 0xFFFF0000 as 25 rows of 80, and with -2004 -s, which prints those from
; 0x400 instead. Each region gets a character in its first word, in its
; last word (row 24, column 79, at base + 1999 = base + 0x7CF), and in the
; words just before and after it, which are not shown.
;
; Row 0 of the screen at 0xFFFF0000 also shows what is printed as a blank:
; 0x7F (DEL), 0xC1 (bits 7..0 above 0x7E), and a space. Bits above bit 7
; are a color and are ignored, so 0x141 prints "A".
;
;   -s:        row 0 "  A !", rows 1-23 empty, row 24 "Z" in column 79.
;              "X" at 0xFFFEFFFF and "Y" at 0xFFFF07D0 are not shown.
;   -2004 -s:  row 0 "a", rows 1-23 empty, row 24 "z" in column 79.
;              "x" at 0x3FF and "y" at 0xBD0 are not shown.
;
; Rows 1-23 print as "|", because only blank rows at the bottom are
; dropped. Steps: 12 + 1 = 13. HALT is word 36 = 0x24, so PC = 0x25.
        MOVE    @0xFFFF0000, 0x7F
        MOVE    @0xFFFF0001, 0xC1
        MOVE    @0xFFFF0002, 0x141
        MOVE    @0xFFFF0003, 0x20
        MOVE    @0xFFFF0004, 0x21
        MOVE    @0xFFFF07CF, 0x5A
        MOVE    @0xFFFF07D0, 0x59
        MOVE    @0xFFFEFFFF, 0x58
        MOVE    @0x400, 0x61
        MOVE    @0xBCF, 0x7A
        MOVE    @0xBD0, 0x79
        MOVE    @0x3FF, 0x78
        HALT
