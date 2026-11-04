; The font of the window (SYSTEM.md §1.8). The program reads row 6 of A
; from the character ROM, 0x0FF0, writes the row, which the ROM drops, and
; reads it again. It copies the 32 rows of A from the ROM to the font RAM,
; writes 0xFFFF8001 to row 0 of glyph 1, of which the RAM keeps bits
; 15..0, and selects the font RAM with the font base.
;
; Steps: 3, then 3 to set up the copy, 32 * 3 in the loop (the last ?!Z
; JMP is skipped, but is a step), and 4 at the end: 106. R1 = R2 = 0x0FF0.
; R3 and R4 end one past A: 0xFFFE2840 and 0xFFFE0840. R5 = 0, and the
; last SUB[M] leaves Z, R14 = 0x09000000. R6 = 0x8001.
;
; The dumps: the 32 rows of A in the RAM, as font.zig has them: 6 rows of
; 0, 0x0FF0, 0x1FF8, 0x381C, 6 rows of 0x300C, 0x3FFC twice, 9 rows of
; 0x300C, and 6 rows of 0. Then 0x8001 in the RAM, 0x0FF0 in the ROM, and
; the base, 0xFFFE0000.
FRAM            .EQU    0xFFFE0000
FROM            .EQU    0xFFFE2000
FBASE           .EQU    0xFFFFFF86
GLYPH_A         .EQU    0x820           ; 32 * 0x41
                MOVE    R1, @FROM+GLYPH_A+6
                MOVE    @FROM+GLYPH_A+6, 0x1234
                MOVE    R2, @FROM+GLYPH_A+6
                MOVE    R3, FROM+GLYPH_A
                MOVE    R4, FRAM+GLYPH_A
                MOVE    R5, 32
copy            MOVE    @R4++, @R3++
                SUB[M]  R5, R5, 1
        ?!Z     JMP     copy
                MOVE    @FRAM+32, 0xFFFF8001
                MOVE    R6, @FRAM+32
                MOVE    @FBASE, FRAM
                HALT
