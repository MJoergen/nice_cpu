; The emulator's console input (README.md, Memory map), run with
; --input test/input.txt, which holds the two bytes "Hi". Each read of
; 0xFFFFFF00 returns 0x100 plus the next byte: R1 = 0x148 ("H") and
; R2 = 0x169 ("i"). After the last byte every read returns 0x200: R3 and
; R4. The two bytes are echoed, with the bits above bit 7 ignored, so
; "Hi\n" comes out before the registers. 8 steps; HALT is word 15.
CONSOLE .EQU    0xFFFFFF00
        MOVE    R1, @CONSOLE            ; words 0,1
        MOVE    R2, @CONSOLE            ; words 2,3
        MOVE    R3, @CONSOLE            ; words 4,5
        MOVE    R4, @CONSOLE            ; words 6,7
        MOVE    @CONSOLE, R1            ; words 8,9: "H"
        MOVE    @CONSOLE, R2            ; words 10,11: "i"
        MOVE    @CONSOLE, 10            ; words 12-14: newline
        HALT                            ; word 15
