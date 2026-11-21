; The chunky mode of the screen (doc/DEVICES.md §1.10). The mode word is 0,
; the text, at the start, keeps a write of 1, and writes 0 for 2, a mode the
; emulator lacks: R1 = 0, R2 = 1, R3 = 0, R4 = 1, and the dump of the mode
; word is 1. In the mode, pixel (x, y) is the word at 0xFFFF0000 + 160*y + x,
; colored by bits 31..20. --color prints two rows of pixels to a line, as
; upper half blocks, the top pixel in the foreground and the bottom one in
; the background. Line 0 has (0, 0) and (1, 0) red over black, then (2, 1)
; green under black, whose character, bits 7..0, is not shown. Lines 1 to
; 54 are black, and so empty. Line 55 has 159 blocks of black, then (159,
; 111), the last pixel, white under black. --screen prints only the size,
; and with -2004 the 160x100 that cover the 25 rows of its text.
SCREEN          .EQU    0xFFFF0000
MODE            .EQU    0xFFFFFF87
                MOVE    R1, @MODE       ; 0
                MOVE    @MODE, 1
                MOVE    R2, @MODE       ; 1
                MOVE    @MODE, 2
                MOVE    R3, @MODE       ; 0
                MOVE    @MODE, 1
                MOVE    R4, @MODE       ; 1
                MOVE    @SCREEN, 0xF0000000  ; (0, 0) red
                MOVE    @0xFFFF0001, 0xF0000000  ; (1, 0) red
                MOVE    @0xFFFF00A2, 0x0F0FFF41  ; (2, 1) = 160 + 2, green
                MOVE    @0xFFFF45FF, 0xFFF00000  ; (159, 111) white
                HALT
