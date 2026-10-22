; The colors of the screen words, printed by --color (doc/SYSTEM.md §1).
; Bits 31..20 are the background R, G, and B, and bits 19..8 the foreground,
; 4 bits each, 0xF being full intensity (the 2004 IDE inverts the foreground).
; "A" and "B" have the same word but for the character, so one escape sequence
; covers both: background 255,0,0 and foreground 255,255,255. "C" has
; background 0,0,0 and foreground 255,255,0, so it gets another. Each row ends
; with a reset. A word with color 0 would be black on black.
SCREEN  .EQU    0xFFFF0000
        MOVE    @SCREEN, 0xF00FFF41     ; words 0-2: "A"
        MOVE    @0xFFFF0001, 0xF00FFF42 ; words 3-5: "B"
        MOVE    @0xFFFF0002, 0x000FF043 ; words 6-8: "C"
        HALT                            ; word 9
