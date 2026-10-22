; The character screen at 0xFFFF0000 (README.md, Memory map), printed by
; -s. "Hi" goes to row 0, columns 0 and 1, with a color above bit 7 that
; -s ignores. "!" goes to row 1, column 79, the last column, at 0xFFFF0000 +
; 80 + 79 = 0xFFFF009F. The "X" at 0x400, the 2004 screen, is not shown.
SCREEN  .EQU    0xFFFF0000
        MOVE    @SCREEN, 0xC80FF048     ; words 0-2: "H"
        MOVE    @0xFFFF0001, 0x69       ; words 3-5: "i"
        MOVE    @0xFFFF009F, 0x21       ; words 6-8: "!"
        MOVE    @0x400, 0x58            ; words 9-11: "X"
        HALT                            ; word 12
