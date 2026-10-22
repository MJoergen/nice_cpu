; --invert-fg, which --color alone does not do (screencolor.nasm). The 2004
; IDE inverts the foreground components n to 0xF - n. "A" has foreground
; 0xFFF, which is 0,0,0 inverted. "B" has 0x07A, which is 255,136,85
; inverted. The background is not inverted. The escape sequence changes
; between the two, since the foreground does.
SCREEN  .EQU    0xFFFF0000
        MOVE    @SCREEN, 0xF00FFF41     ; words 0-2: "A"
        MOVE    @0xFFFF0001, 0x00007A42 ; words 3-5: "B"
        HALT                            ; word 6
