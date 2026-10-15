; The instruction after RTI (ISA.md §1.4, §7.1), run with
;   --nmi 3:1 --nmi 10:1
; It may be an INT, which works normally, and a pending NMI then waits
; through that routine as well. A skipped instruction after RTI counts as
; the instruction after RTI. Each step logs a marker at 0x200: An in the
; main program, Bn in the routine for vector n. The steps are:
;    0,1  set VBASE = 1 and R13
;    2    INT 3
;    3,4  B3, RTI; the NMI raised before step 3 waits for RTI
;    5    INT 4 (after RTI, so first)
;    6,7  B4, RTI
;    8    A1 (after RTI, so first)
;    9-11 NMI, B1, RTI; the NMI raised before step 10 waits for RTI
;   12    the skipped MOVE (after RTI, so first)
;   13-15 NMI, B1, RTI
;   16    A3 (after RTI, so first)
;   17    HALT
; The log is B3 B4 A1 B1 B1 A3.
        MOVE    R14, 1          ; words 0,1: VBASE = 1: the table is at 0x100
        MOVE    R13, 0x200      ; words 2,3
        INT     3               ; word 4
        INT     4               ; word 5
        MOVE    @R13++, 0xA1    ; words 6,7
?!1     MOVE    @R13++, 0xA2    ; words 8,9: never runs
        MOVE    @R13++, 0xA3    ; words 10,11
        HALT                    ; word 12
nmi     MOVE    @R13++, 0xB1    ; words 13,14
        RTI                     ; word 15
v3      MOVE    @R13++, 0xB3    ; words 16,17
        RTI                     ; word 18
v4      MOVE    @R13++, 0xB4    ; words 19,20
        RTI                     ; word 21
        .ORG    0x101
        .DAT    nmi
        .ORG    0x103
        .DAT    v3
        .DAT    v4
