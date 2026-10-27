; The emulator's console at 0xFFFFFF00 (README.md, Memory map). Each write
; prints the low byte of the word, so "Hi!\n" comes out before the
; registers. The bits above bit 7 are ignored, and the console stores
; nothing. make test runs it with stdin from /dev/null, so the read of the
; console finds the input ended: R1 = 0x200.
CONSOLE         .EQU    0xFFFFFF00
                MOVE    @CONSOLE, 0x48  ; words 0-2: "H"
                MOVE    @CONSOLE, 0x12345669  ; words 3-5: "i"
                MOVE    R2, 0x21        ; words 6,7
                MOVE    @CONSOLE, R2    ; words 8,9: "!"
                MOVE    @CONSOLE, 10    ; words 10-12: newline
                MOVE    R1, @CONSOLE    ; words 13,14
                HALT                    ; word 15
