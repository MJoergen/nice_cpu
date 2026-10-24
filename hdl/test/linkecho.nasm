; The program of tb_link, loaded over the debug link. It echoes each
; console byte, and halts at the end of the input, with the number of
; bytes echoed in R2. A console read returns 0 while no byte waits
; (SYSTEM.md §1), so then it reads again.
CONSOLE .EQU    0xFFFFFF00
loop    MOVE    R1, @CONSOLE
        AND[M]  R0, R1, 0x200
        ?!Z HALT
        AND[M]  R0, R1, 0x100           ; no byte waiting: read again
        ?Z MOVE R15, loop
        MOVE    @CONSOLE, R1
        ADD     R2, R2, 1
        MOVE    R15, loop
