; Watchpoints for tb_core's G_WATCH_AT, at "1Crw 1Dw FFFFFF20w 1Br".
; test/break_stops.py gets the stops of the emulator (doc/DEBUG.md §6).
; Each pass of the loop hits watchpoint 0 at DATA five times: a write, two
; reads in one step, a read with @R1++, a write with @--R1, and a read
; with @c[R7]. The skipped read hits nothing. The read of OTHER after the
; last hits nothing, as watchpoint 1 watches its writes only, and has no
; reason to wait for the read before it, so the stop must come before it,
; with R9 still 0 in the first pass. Then a store into the math unit hits
; watchpoint 2, an I/O store that the pipelined core holds until the bus
; takes it, and a jump through TAB hits watchpoint 3, after which R15 is
; BACK. The steps are:
;    0-3    set SR, R1, R7, and R3
;    4-14   the first pass, seven stops
;   15-25   the second pass, seven stops
;   26      HALT
                MOVE    R14, 0x40000001  ; words 0,1: F0 = 1, U = 1
                MOVE    R1, DATA        ; words 2,3
                MOVE    R7, DATA-1      ; words 4,5
                MOVE    R3, 2           ; words 6,7
LOOP            MOVE    @R1, R3         ; word 8: a write
                ADD     R2, @R1, @R1    ; word 9: two reads
        ?Z      MOVE    R4, @R1         ; word 10: skipped, Z is 0
                MOVE    R5, @R1++       ; word 11: a read, R1 = DATA + 1
                MOVE    @--R1, R5       ; word 12: a write, R1 = DATA
                MOVE    R6, @1[R7]      ; words 13,14: a read
                MOVE    R9, @OTHER      ; words 15,16: a read of no watchpoint
                MOVE    @0xFFFFFF20, R3  ; words 17,18: an I/O store
                MOVE    R15, @TAB       ; words 19,20: a jump through TAB
                HALT                    ; word 21: never reached
BACK            SUB[M]  R3, R3, 1       ; words 22,23
        ?!Z     MOVE    R15, LOOP       ; words 24,25
                HALT                    ; word 26
TAB             .DAT    BACK            ; word 27
DATA            .DAT    7               ; word 28
OTHER           .DAT    5               ; word 29
