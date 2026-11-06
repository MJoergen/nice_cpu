; Echoes each input byte, and halts at the end of the input, with the
; number of bytes echoed in R2: the program of test/link.py's checks of
; the console and of the end of the input.
CONSOLE         .EQU    0xFFFFFF00

LOOP            MOVE    R1, @CONSOLE
                AND[M]  R0, R1, 0x200   ; bit 9: the end of the input
        ?!Z     HALT
                MOVE    @CONSOLE, R1
                ADD     R2, R2, 1
                MOVE    R15, LOOP
