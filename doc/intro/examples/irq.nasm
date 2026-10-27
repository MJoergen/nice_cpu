; Print a star each time an IRQ arrives. Run it with, for example,
;     niceemu --irq 5:5 --irq 12:5 irq.bin
SP              .EQU    R13
SR              .EQU    R14
PC              .EQU    R15
CONSOLE         .EQU    0xFFFFFF00

                .ORG    0
                MOVE    SP, 0x1000
                OR      SR, SR, 1       ; VBASE = 1: the table is at 0x100
                OR      SR, SR, 0x40000000  ; E = 1: accept IRQs
                MOVE    R1, 20
WAIT            DEC[M]  R1, R1          ; count down from 20 ...
        ?!Z     MOVE    PC, WAIT        ; ... while the IRQs come in
                MOVE    @CONSOLE, 10    ; a newline
                HALT

ISR             MOVE    @CONSOLE, 0x2A  ; print '*'
                RTI                     ; restore PC and SR, and return

                .ORG    0x105           ; vector 5 of the table at 0x100
                .DAT    ISR
