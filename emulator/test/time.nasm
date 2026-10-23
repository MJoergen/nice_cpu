; The microsecond counter (SYSTEM.md §3). The emulator has no clock, so it
; counts one microsecond per step. A read of TIME_LO returns the number of
; steps before the reading one, and takes a snapshot; a read of TIME_HI
; returns the snapshot's high word, 0 here, since no run is 2^32 steps long.
;
;   step
;    0    MOVE R1, @TIME_HI    no snapshot yet: R1 = 0
;    1    MOVE R2, @TIME_LO    R2 = 1
;    2    MOVE R3, @TIME_HI    R3 = 0
;    3    MOVE R4, @TIME_LO    R4 = 3
;    4    MOVE R5, @TIME_HI    R5 = 0
;    5    MOVE @TIME_LO, 0x55  ignored
;    6    MOVE R6, @TIME_LO    R6 = 6
;    7    HALT
;
; 8 steps. PC = 0x10 after the HALT at 0xF. The dump reads the counter
; without taking a snapshot: 8 steps, and the snapshot's high word, 0. The
; write left no trace.
TIME_LO .EQU    0xFFFFFF44
TIME_HI .EQU    0xFFFFFF45
        MOVE    R1, @TIME_HI    ; words 0,1
        MOVE    R2, @TIME_LO    ; words 2,3
        MOVE    R3, @TIME_HI    ; words 4,5
        MOVE    R4, @TIME_LO    ; words 6,7
        MOVE    R5, @TIME_HI    ; words 8,9
        MOVE    @TIME_LO, 0x55  ; words 10-12
        MOVE    R6, @TIME_LO    ; words 13,14
        HALT                    ; word 15
