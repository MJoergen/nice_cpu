; The program of tb_link, loaded over the debug link. It echoes each
; console byte, and halts at the end of the input, with the number of
; bytes echoed in R2. A console read returns 0 while no byte waits
; (DEVICES.md §1), so then it reads again. Its jumps are the long form,
; MOVE R15, of two words, so that the addresses and the length (15 words)
; that tb_link checks stay as they are.
CONSOLE         .EQU    0xFFFFFF00
:               MOVE    R1, @CONSOLE
                AND[M]  R0, R1, 0x200
        ?!Z     HALT
                AND[M]  R0, R1, 0x100   ; no byte waiting: read again
        ?Z      MOVE    R15, :-
                MOVE    @CONSOLE, R1
                ADD     R2, R2, 1
                MOVE    R15, :-
