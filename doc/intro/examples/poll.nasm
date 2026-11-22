; Print a star every 10 cycles, three times, while the main loop counts.
; NICE has no interrupts, so the loop polls the cycle counter itself.
CONSOLE         .EQU    0xFFFFFF00
CYCLE_LO        .EQU    0xFFFFFF40      ; the cycles since reset

                .ORG    0
                MOVE    R1, 3           ; R1: the stars still to print
                MOVE    R2, 10          ; R2: the cycle of the next star
LOOP            ADD     R3, R3, 1       ; the work of the main loop
                SUB[M]  R0, @CYCLE_LO, R2  ; C = 1 while the star is not due
        ?C      JMP     LOOP
                MOVE    @CONSOLE, 0x2A  ; print '*'
                ADD     R2, R2, 10      ; the next one 10 cycles later
                DEC[M]  R1, R1
        ?!Z     JMP     LOOP
                MOVE    @CONSOLE, 10    ; a newline
                HALT
