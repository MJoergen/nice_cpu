; IRQ and NMI raised from the command line (ISA.md §7.1), with
;   --nmi 2:1 --irq 2:2 --nmi 9:1 --irq 17:2 --nmi 17:1 --irq 100:2
; Each step logs a marker at 0x200: An in the main program, Bn in the NMI
; routine, Cn in the IRQ routine. The steps are:
;    0,1  set VBASE = 1 and R13
;    2    NMI, though E = 0; the IRQ raised with it waits for E
;    3,4  B1, RTI
;    5,6  A1 (after RTI, so first), A2; the IRQ still waits
;    7    set E
;    8    IRQ
;    9-11 C1, C2, RTI; the NMI raised before step 9 waits for RTI
;   12    A3 (after RTI, so first)
;   13-15 NMI, B1, RTI
;   16    A4
;   17-19 NMI, B1, RTI; NMI goes before the IRQ raised with it
;   20    A5 (after RTI, so first)
;   21-24 IRQ, C1, C2, RTI
;   25    HALT; the IRQ for step 100 is never raised
; The log is B1 A1 A2 C1 C2 A3 B1 A4 B1 A5 C1 C2.
                MOVE    R14, 1          ; words 0,1: VBASE = 1: the table is at 0x100
                MOVE    R13, 0x200      ; words 2,3
                MOVE    @R13++, 0xA1    ; words 4,5
                MOVE    @R13++, 0xA2    ; words 6,7
                OR      R14, R14, 0x40000000  ; words 8,9: E = 1
                MOVE    @R13++, 0xA3    ; words 10,11
                MOVE    @R13++, 0xA4    ; words 12,13
                MOVE    @R13++, 0xA5    ; words 14,15
                HALT                    ; word 16
nmi             MOVE    @R13++, 0xB1    ; words 17,18
                RTI                     ; word 19
irq             MOVE    @R13++, 0xC1    ; words 20,21
                MOVE    @R13++, 0xC2    ; words 22,23
                RTI                     ; word 24
                .ORG    0x101
                .DAT    nmi
                .DAT    irq
