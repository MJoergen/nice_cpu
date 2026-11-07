; Writes to TIMER_PERIOD (SYSTEM.md §4) by instructions with a data read,
; which the pipelined core counts on instret_o before their store, each
; followed by reads of TIMER_COUNT. The step of the write counts, on the
; new count, as in the emulator (test/tb_core.vhd). E = 0, so the request
; of step 7 waits, and the later ones merge with it.
;
;   step                                      COUNT  end
;    2  MOVE @TIMER_PERIOD, @R2    P = 5        5     4
;    3  MOVE R3, @TIMER_COUNT      R3 = 4       4     3
;    4  ADD @TIMER_PERIOD, @R2, 2  P = 7        7     6
;    5  MOVE R4, @TIMER_COUNT      R4 = 6       6     5
;    6  MOVE R5, @TIMER_COUNT      R5 = 5       5     4
;    7  MOVE @TIMER_PERIOD, @R1    P = 1        1     1   raise
;    8  MOVE R6, @TIMER_COUNT      R6 = 1       1     1   raise, merges
;    9  ADD @TIMER_PERIOD, @R1, @R2  P = 6      6     5
;   10  MOVE R7, @TIMER_COUNT      R7 = 5       5     4
;   11  MOVE @TIMER_PERIOD, 0      stopped      0     0
;   12  MOVE R8, @TIMER_COUNT      R8 = 0       0     0
;   13  SUB @TIMER_PERIOD, @R2, 1  P = 4        4     3
;   14  MOVE R9, @TIMER_COUNT      R9 = 3       3     2
;   15  MOVE R10, @TIMER_PERIOD    R10 = 4      2     1
;   16  MOVE R11, @TIMER_COUNT     R11 = 1      1     4   raise, merges
;   17  MOVE @TIMER_PERIOD, 0      stopped      0     0
TIMER_PERIOD    .EQU    0xFFFFFF10
TIMER_COUNT     .EQU    0xFFFFFF11
                MOVE    R1, val1
                MOVE    R2, val5
                MOVE    @TIMER_PERIOD, @R2
                MOVE    R3, @TIMER_COUNT
                ADD     @TIMER_PERIOD, @R2, 2
                MOVE    R4, @TIMER_COUNT
                MOVE    R5, @TIMER_COUNT
                MOVE    @TIMER_PERIOD, @R1
                MOVE    R6, @TIMER_COUNT
                ADD     @TIMER_PERIOD, @R1, @R2
                MOVE    R7, @TIMER_COUNT
                MOVE    @TIMER_PERIOD, 0
                MOVE    R8, @TIMER_COUNT
                SUB     @TIMER_PERIOD, @R2, 1
                MOVE    R9, @TIMER_COUNT
                MOVE    R10, @TIMER_PERIOD
                MOVE    R11, @TIMER_COUNT
                MOVE    @TIMER_PERIOD, 0
                HALT
val1            .DAT    1
val5            .DAT    5
