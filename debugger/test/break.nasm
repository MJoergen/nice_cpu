; The program of test/link.py's checks of nicedbg.py, which sets
; breakpoints at its labels, from niceasm.py --symbols: a loop of three
; passes, a skipped instruction, a read from memory, a two-word
; instruction, an INT with its routine and RTI, and a HALT. The routine's
; vector is at 0x103, as VBASE is 1.
PC              .EQU    R15
SR              .EQU    R14

START           MOVE    SR, 1           ; VBASE = 1: the table is at 0x100
                MOVE    R13, 0x200
                MOVE    R4, 3
LOOP            SUB[M]  R4, R4, 1
        ?!Z     JMP     LOOP
SKIP    ?!Z     MOVE    R3, 0x55        ; skipped: R4 is 0
READ            MOVE    R1, @R13
TWO             MOVE    R5, 0x12345678
                INT     3               ; PC = mem[0x103] = V3; RTI to AFTER
AFTER           MOVE    R6, 7
DONE            HALT
V3              MOVE    R7, 0x1234
                RTI
                .ORG    0x103           ; vector 3 of the table at 0x100
                .DAT    V3
