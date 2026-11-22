; Breakpoints for tb_core's G_BREAK_AT, at "4 5 8 C".
; test/break_stops.py gets the stops of the emulator (doc/DEBUG.md §6). The
; steps and the stops are:
;    0,1    set R14 and R1
;           stop at 4: the loop, an instruction with a data read
;    2,3    MOVE, SUB, and stop at 8: the ?Z, whose condition is false
;    4,5    ?Z, the jump to the loop, and stop at 4
;    6,7    MOVE, SUB, and stop at 8
;    8,9    ?Z, the jump, and stop at 4
;   10,11   MOVE, SUB, and stop at 8
;   12      ?Z, taken this time, and stop at C: the HALT
;   13      HALT
; The word at 5 is the constant of the MOVE at 4, and never a stop.
                MOVE    R14, 0x40000001  ; words 0,1: F0 = 1, U = 1
                MOVE    R1, 3           ; words 2,3
:               MOVE    R2, @data       ; words 4,5
                SUB[M]  R1, R1, 1       ; words 6,7
        ?Z      JMP     :+              ; words 8,9
                JMP     :-              ; words 10,11
:               HALT                    ; word 12
data            .DAT    7               ; word 13
