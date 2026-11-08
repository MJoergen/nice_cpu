; Watchpoints for tb_core's G_WATCH_AT, at "20rw 102r FFFFFF20w 1Fr", with
;   --irq 4:2 --irq 8:2
; test/break_stops.py gets the stops of the emulator (doc/DEBUG.md §6).
; Each pass of the loop hits watchpoint 0 at DATA five times: a write, two
; reads in one step, a read with @R1++, a write with @--R1, and a read
; with @c[R7]. The skipped read hits nothing. The read of OTHER after the
; last hits nothing, and has no reason to wait for the read before it, so
; the stop must come before it, with R9 still 0 in the first pass. Then a
; store into the math unit hits watchpoint 2, an I/O store that the
; pipelined core holds until the bus takes it, and a jump through TAB hits
; watchpoint 3, after which R15 is BACK. The INT and each IRQ entry hit
; watchpoint 1 with the read of vector 2, so the stop is at ISR, and the
; hit is at the INT, or at the instruction that the entry goes before.
; The steps are:
;    0-3    set SR, R1, R7, and R3
;    4      IRQ entry before LOOP: stop at ISR, hit at 8
;    5,6    ADD, RTI
;    7      the write at LOOP: stop, hit at 8, with the IRQ raised before
;           step 8 pending, which waits for the go on
;    8      IRQ entry before the ADD: stop at ISR, hit at 9
;    9,10   ADD, RTI
;   11-20   the rest of the first pass, six stops
;   21-31   the second pass, seven stops
;   32      INT: stop at ISR, hit at 26
;   33-35   ADD, RTI, HALT
                MOVE    R14, 0x40000001  ; words 0,1: VBASE = 1, E = 1
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
                INT     2               ; word 26
                HALT                    ; word 27
ISR             ADD     R8, R8, 1       ; words 28,29
                RTI                     ; word 30
TAB             .DAT    BACK            ; word 31
DATA            .DAT    7               ; word 32
OTHER           .DAT    5               ; word 33
                .ORG    0x102
                .DAT    ISR
