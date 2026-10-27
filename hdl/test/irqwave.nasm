; The program of the interrupt timing diagram, doc/interrupt.tex. It runs
; with two IRQs through vector 9 (make test, INTR_irqwave): the first comes
; before a plain instruction and is taken at once, and the second comes
; just after the next instruction, a data read, has issued its read, so
; the pipelined core takes it one instruction later (MICROARCH.md §6).
; The routine counts its entries in R3, and the main program counts its
; instructions in R1, so the trace shows where each request was taken.
IRQ             .EQU    9

                MOVE    R15, start      ; words 0,1
                .ORG    IRQ
                .DAT    isr

                .ORG    0x10
start           MOVE    R14, 0x40000000  ; E = 1
                ADD     R1, R1, 1
                ADD     R1, R1, 1
                ADD     R1, R1, 1
                ADD     R1, R1, 1
                ADD     R1, R1, 1
                MOVE    R2, @data       ; a data read
                ADD     R1, R1, 1
                ADD     R1, R1, 1
                ADD     R1, R1, 1
                HALT

isr             ADD     R3, R3, 1
                RTI

data            .DAT    0x1234
