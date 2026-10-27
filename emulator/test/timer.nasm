; The timer (SYSTEM.md §4). The emulator counts one cycle per step, so the
; timer counts steps here. COUNT is shown after the step's read, then at the
; end of the step. "raise" is a request raised at the end of the step, which
; is pending before the next one.
;
;   step                                 COUNT  end
;    0  MOVE R1, @TIMER_COUNT    R1 = 0    0     0   stopped after reset
;    1  MOVE @TIMER_VECTOR, 0x141          0     0   v = 0x41
;    2  MOVE R2, @TIMER_VECTOR   R2 = 0x41 0     0
;    3  MOVE @TIMER_PERIOD, 4              4     3   the write's step counts
;    4  MOVE R3, @TIMER_COUNT    R3 = 3    3     2
;    5  MOVE R4, @TIMER_PERIOD   R4 = 4    2     1
;    6  MOVE R5, @TIMER_COUNT    R5 = 1    1     4   raise; E = 0, so it waits
;    7  MOVE R7, @TIMER_COUNT    R7 = 4    4     3
;    8  MOVE @TIMER_PERIOD, 0              0     0   stopped; still pending
;    9  MOVE R8, @TIMER_COUNT    R8 = 0    0     0
;   10  OR R14, R14, 0x40000000            0     0   E = 1
;   11  IRQ 0x41, the request of step 6
;   12  ADD R6, R6, 1            R6 = 1
;   13  RTI
;   14  MOVE @TIMER_PERIOD, 3              3     2   first after RTI
;   15  ADD R9, R9, 1            R9 = 1    2     1
;   16  SUB[M] R0, R6, 4         Z = 0     1     3   raise
;   17  IRQ                                3     2
;   18  ADD R6, R6, 1            R6 = 2    2     1
;   19  RTI                                1     3   raise
;   20  ?!Z MOVE R15, loop       taken     3     2   first after RTI
;   21  IRQ                                2     1
;   22  ADD R6, R6, 1            R6 = 3    1     3   raise, pending in the routine
;   23  RTI                                3     2
;   24  ADD R9, R9, 1            R9 = 2    2     1   first after RTI
;   25  IRQ                                1     3   raise, pending in the routine
;   26  ADD R6, R6, 1            R6 = 4    3     2
;   27  RTI                                2     1
;   28  SUB[M] R0, R6, 4         Z = 1     1     3   raise: merges with step 25's
;   29  IRQ                                3     2
;   30  ADD R6, R6, 1            R6 = 5    2     1
;   31  RTI                                1     3   raise
;   32  ?!Z MOVE R15, loop       skipped   3     2   first after RTI
;   33  IRQ                                2     1
;   34  ADD R6, R6, 1            R6 = 6    1     3   raise
;   35  RTI                                3     2
;   36  MOVE @TIMER_PERIOD, 0              0     0   stopped; still pending
;   37  IRQ, the request of step 34
;   38  ADD R6, R6, 1            R6 = 7
;   39  RTI
;   40  AND R14, R14, 0xBFFFFFFF           0     0   E = 0
;   41  MOVE @TIMER_PERIOD, 1              1     1   raise, with v = 0x41; E = 0, so it waits
;   42  MOVE @TIMER_PERIOD, 0              0     0   stopped; still pending
;   43  MOVE @TIMER_VECTOR, 0x142          0     0   v = 0x42
;   44  OR R14, R14, 0x40000000            0     0   E = 1
;   45  IRQ 0x41: the request of step 41 keeps the vector it was raised with
;   46  ADD R6, R6, 1            R6 = 8
;   47  RTI
;   48  AND R14, R14, 0xBFFFFFFF           0     0   E = 0, first after RTI
;   49  MOVE @TIMER_PERIOD, 1              1     1   raise, with v = 0x42
;   50  MOVE @TIMER_PERIOD, 0              0     0   stopped; still pending
;   51  OR R14, R14, 0x40000000            0     0   E = 1
;   52  IRQ 0x42, the request of step 49
;   53  ADD R10, R10, 1          R10 = 1
;   54  RTI
;   55  HALT                               0     0
;
; Ten requests are raised and nine taken: R6 = 8 counts the entries
; through 0x41 and R10 = 1 those through 0x42. R14 = 0x49000000 at the
; end, E and Z from the flags of step 28 that the routines restored, and
; the HALT is the 56th step. The dump of the timer shows P = 0, COUNT = 0,
; v = 0x42, and a spare word, 0.
TIMER_PERIOD    .EQU    0xFFFFFF10
TIMER_COUNT     .EQU    0xFFFFFF11
TIMER_VECTOR    .EQU    0xFFFFFF12
                MOVE    R1, @TIMER_COUNT
                MOVE    @TIMER_VECTOR, 0x141
                MOVE    R2, @TIMER_VECTOR
                MOVE    @TIMER_PERIOD, 4
                MOVE    R3, @TIMER_COUNT
                MOVE    R4, @TIMER_PERIOD
                MOVE    R5, @TIMER_COUNT
                MOVE    R7, @TIMER_COUNT
                MOVE    @TIMER_PERIOD, 0
                MOVE    R8, @TIMER_COUNT
                OR      R14, R14, 0x40000000
                MOVE    @TIMER_PERIOD, 3
loop            ADD     R9, R9, 1
                SUB[M]  R0, R6, 4
        ?!Z     MOVE    R15, loop
                MOVE    @TIMER_PERIOD, 0
                AND     R14, R14, 0xBFFFFFFF
                MOVE    @TIMER_PERIOD, 1
                MOVE    @TIMER_PERIOD, 0
                MOVE    @TIMER_VECTOR, 0x142
                OR      R14, R14, 0x40000000
                AND     R14, R14, 0xBFFFFFFF
                MOVE    @TIMER_PERIOD, 1
                MOVE    @TIMER_PERIOD, 0
                OR      R14, R14, 0x40000000
                HALT
                .ORG    0x41
                .DAT    on_irq, on_irq2
on_irq          ADD     R6, R6, 1
                RTI
on_irq2         ADD     R10, R10, 1
                RTI
