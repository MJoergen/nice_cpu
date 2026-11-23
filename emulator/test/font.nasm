; The font of the window (DEVICES.md §1.8). The program reads row 6 of A
; from the character ROM, 0x0FF0, writes the row, which the ROM drops, and
; reads it again. It copies the 32 rows of A from the ROM to the font RAM,
; writes 0xFFFF8001 to row 0 of glyph 1, of which the RAM keeps bits
; 15..0, and selects the font RAM with the font base. Then it reads a row
; of six of the blocks and arrows at 0x80 to 0x99.
;
; Steps: 3, then 3 to set up the copy, 32 * 3 in the loop (the last ?!Z
; JMP is skipped, but is a step), 3, 6 reads, and the HALT: 112. R1 = R2 = 0x0FF0.
; R3 and R4 end one past A: 0xFFFE2840 and 0xFFFE0840. R5 = 0, and the
; last SUB[M] leaves Z, R14 = 0x09000000. R6 = 0x8001. The rows read:
; R7 = 0xFFFF, row 16 of the lower half block 0x84, R8 = 0xFFFF, row 28
; of the lower one eighth 0x81, R9 = 0xFF00, row 31 of the left half
; block 0x8C, R10 = 0xC000, row 0 of the left one eighth 0x8F, R11 =
; 0x7FFE, row 16 of the arrow left 0x90, the shaft, and R12 = 0x0180, row
; 25 of the arrow down 0x93, its tip.
;
; The dumps: the 32 rows of A in the RAM, as font.zig has them: 6 rows of
; 0, 0x0FF0, 0x1FF8, 0x381C, 6 rows of 0x300C, 0x3FFC twice, 9 rows of
; 0x300C, and 6 rows of 0. Then 0x8001 in the RAM, 0x0FF0 in the ROM, and
; the base, 0xFFFE0000. The upper half block 0x80, 16 rows of 0xFFFF and
; 16 of 0, so 0xFFFE3000 reads 0xFFFF. The north-east arrow 0x97, as
; gen_font.py has it: 9 rows of 0, 0x01FE twice, 0x000E, 0x001E, 0x0036,
; 0x0066, 0x00C6, 0x0186, 0x0300, 0x0600, 0x0C00, 0x1800, 0x3000, 0x6000,
; and 9 rows of 0. And row 0 of 0x9A, blank, 0.
FRAM            .EQU    0xFFFE0000
FROM            .EQU    0xFFFE2000
FBASE           .EQU    0xFFFFFF86
GLYPH_A         .EQU    0x820           ; 32 * 0x41
BLOCK           .EQU    0x1000          ; 32 * 0x80
                MOVE    R1, @FROM+GLYPH_A+6
                MOVE    @FROM+GLYPH_A+6, 0x1234
                MOVE    R2, @FROM+GLYPH_A+6
                MOVE    R3, FROM+GLYPH_A
                MOVE    R4, FRAM+GLYPH_A
                MOVE    R5, 32
:               MOVE    @R4++, @R3++
                SUB[M]  R5, R5, 1
        ?!Z     JMP     :-
                MOVE    @FRAM+32, 0xFFFF8001
                MOVE    R6, @FRAM+32
                MOVE    @FBASE, FRAM
                MOVE    R7, @FROM+BLOCK+32*0x04+16
                MOVE    R8, @FROM+BLOCK+32*0x01+28
                MOVE    R9, @FROM+BLOCK+32*0x0C+31
                MOVE    R10, @FROM+BLOCK+32*0x0F
                MOVE    R11, @FROM+BLOCK+32*0x10+16
                MOVE    R12, @FROM+BLOCK+32*0x13+25
                HALT
