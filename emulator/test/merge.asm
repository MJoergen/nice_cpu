; Requests of one kind that arrive together merge (ISA.md §7.1), run with
;   --nmi 1:1 --nmi 1:2 --irq 1:3
; The second NMI's vector wins. The IRQ waits for E, which is never set, and
; is still pending at HALT. Steps: 0 MOVE, 1 NMI, 2 MOVE, 3 RTI, 4 HALT.
        MOVE    R14, 1          ; 0,1: VBASE = 1: the table is at 0x100
        HALT                    ; 2
v1      MOVE    R1, 1           ; 3,4
        RTI                     ; 5
v2      MOVE    R1, 2           ; 6,7: R1 = 2
        RTI                     ; 8
v3      MOVE    R1, 3           ; 9,10
        RTI                     ; 11
        .ORG    0x101
        .DAT    v1
        .DAT    v2
        .DAT    v3
