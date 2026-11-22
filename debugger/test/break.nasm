; The program of test/link.py's checks of nicedbg.py, which sets
; breakpoints at its labels, from niceasm.py --symbols: a loop of three
; passes, a skipped instruction, a read from memory, a two-word
; instruction, a CALL with its routine and RET, and a HALT.
PC              .EQU    R15

START           MOVE    R13, 0x200
                MOVE    R4, 3
LOOP            SUB[M]  R4, R4, 1
        ?!Z     JMP     LOOP
SKIP    ?!Z     MOVE    R3, 0x55        ; skipped: R4 is 0
READ            MOVE    R1, @R13
TWO             MOVE    R5, 0x12345678
                CALL    V3              ; RET to AFTER
AFTER           MOVE    R6, 7
DONE            HALT
V3              MOVE    R7, 0x1234
                RET
