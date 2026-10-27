; Copy 5 words from SRC to DST, one MOVE per word.
PC              .EQU    R15
                MOVE    R1, SRC         ; source pointer
                MOVE    R2, DST         ; destination pointer
                MOVE    R3, 5           ; word count
LOOP            MOVE    @R2++, @R1++    ; copy a word, advance both pointers
                DEC[M]  R3, R3
        ?!Z     MOVE    PC, LOOP
                HALT

SRC             .DAT    1, 2, 3, 4, 5
DST             .BLK    5               ; 5 words of 0
