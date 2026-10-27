; RTI that returns to instructions with data reads, for the runs one step
; at a time (hdl/Makefile, rtiread_step), with
;   --nmi 2:1 --nmi 5:1
; A single step over RTI must run RTI alone, so the core may not issue the
; read of the instruction after it while pause_i is '1' (MICROARCH.md §6.1).
; The steps are:
;    0,1  set VBASE = 1 and R2
;    2    NMI
;    3,4  a read, RTI
;    5    the read after RTI, first; the NMI raised before it waits
;    6    NMI
;    7,8  a read, RTI
;    9    two reads after RTI
;   10    HALT
                MOVE    R14, 1          ; VBASE = 1: the table is at 0x100
                MOVE    R2, data
                MOVE    R1, @R2
                ADD     R3, @R2, @R2
                HALT
nmi             ADD     R4, R4, @R2
                RTI
data            .DAT    0x1234
                .ORG    0x101
                .DAT    nmi
