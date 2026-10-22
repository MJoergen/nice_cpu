; Requests of one kind merge while one is pending (ISA.md §7.1), run with
;   --nmi 1:1 --nmi 1:2 --irq 1:3 --irq 4:4 --irq 7:5
; Two NMIs raised at the same step merge, and the first vector wins. IRQ 3
; waits for E, and IRQ 4, raised at a later step, merges with it and does not
; replace it. IRQ 5 waits
; for RTI, and then for the HALT after it, so it is still pending at the end.
; The steps are:
;    0    MOVE: VBASE = 1
;    1-3  NMI 01, MOVE R1, RTI
;    4    MOVE R3 (after RTI, so first)
;    5    OR: E = 1
;    6-8  IRQ 03, MOVE R2, RTI
;    9    HALT (after RTI, so first)
; At the end R1 = 1, R2 = 3, R3 = 3, and IRQ 05 is pending.
        MOVE    R14, 1          ; words 0,1: VBASE = 1: the table is at 0x100
        MOVE    R3, 3           ; words 2,3
        OR      R14, R14, 0x40000000 ; words 4,5: E = 1
        HALT                    ; word 6
v1      MOVE    R1, 1           ; words 7,8
        RTI                     ; word 9
v2      MOVE    R1, 2           ; words 10,11
        RTI                     ; word 12
v3      MOVE    R2, 3           ; words 13,14
        RTI                     ; word 15
v4      MOVE    R2, 4           ; words 16,17
        RTI                     ; word 18
v5      MOVE    R2, 5           ; words 19,20
        RTI                     ; word 21
        .ORG    0x101
        .DAT    v1
        .DAT    v2
        .DAT    v3
        .DAT    v4
        .DAT    v5
