; Breakpoints for tb_core's G_BREAK_AT, at "4 5 8 D", with
;   --irq 6:2 --nmi 8:2 --irq 18:2
; test/break_stops.py gets the stops of the emulator (doc/DEBUG.md §6). The
; steps and the stops are:
;    0,1    set VBASE = 1, E = 1, and R1
;           stop at 4: the loop, an instruction with a data read
;    2,3    MOVE, SUB, and stop at 8: the ?Z, whose condition is false
;    4,5    ?Z, the jump to the loop
;    6      IRQ: the entry goes first at the loop
;           stop at D: the routine's first instruction
;    7,8    ADD, RTI; the NMI raised before step 8 waits for the RTI
;           stop at 4: the instruction after the RTI goes first
;    9      MOVE
;   10      NMI, after the MOVE
;           stop at D
;   11,12   ADD, RTI
;   13      SUB, back from the NMI, and stop at 8
;   14,15   ?Z, the jump, and stop at 4
;   16,17   MOVE, SUB
;   18      IRQ: the entry goes first at 8, which the pipelined core
;           has fetched already
;           stop at D
;   19,20   ADD, RTI, and stop at 8
;   21      ?Z, taken this time
;   22      HALT
; The word at 5 is the constant of the MOVE at 4, and never a stop.
        MOVE    R14, 0x40000001 ; words 0,1: VBASE = 1, E = 1
        MOVE    R1, 3           ; words 2,3
loop    MOVE    R2, @data       ; words 4,5
        SUB[M]  R1, R1, 1       ; words 6,7
        ?Z MOVE R15, done       ; words 8,9
        MOVE    R15, loop       ; words 10,11
done    HALT                    ; word 12
intr    ADD     R4, R4, 1       ; words 13,14
        RTI                     ; word 15
data    .DAT    7               ; word 16
        .ORG    0x102
        .DAT    intr
