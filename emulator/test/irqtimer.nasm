; --irq and the timer's request raised before the same step (SYSTEM.md §4,
; ISA.md §7.1): the request that is pending first keeps its vector, and
; --irq raises its request before the step starts, so it is the one that
; was there first. Run with
;   --irq 5:0x42
; The timer has the vector 0x41 and the period 3, written in step 2, so it
; raises a request at the end of step 4, and again at the end of step 7.
; The steps are:
;    0    MOVE @TIMER_VECTOR, 0x141
;    1    OR: E = 1
;    2    MOVE @TIMER_PERIOD, 3
;    3-4  ADD R5: the timer raises 0x41 at the end of step 4, and --irq
;         raises 0x42 before step 5, merged: 0x42 is kept
;    5    IRQ 0x42
;    6-7  ADD R10, RTI: the timer raises 0x41 again at the end of step 7
;    8    MOVE @TIMER_PERIOD, 0 (first after RTI) stops the timer
;    9    IRQ 0x41
;   10-11 ADD R6, RTI
;   12    HALT (first after RTI)
; At the end R5 = 2, R6 = 1, R10 = 1, R14 = 0x41000000 (E and the 0x01000000 of reset), after 13 steps. If
; the timer's vector were kept in step 5, R6 would be 2 and R10 0.
TIMER_PERIOD .EQU 0xFFFFFF10
TIMER_VECTOR .EQU 0xFFFFFF12
        MOVE    @TIMER_VECTOR, 0x141
        OR      R14, R14, 0x40000000
        MOVE    @TIMER_PERIOD, 3
        ADD     R5, R5, 1
        ADD     R5, R5, 1
        MOVE    @TIMER_PERIOD, 0
        HALT
        .ORG    0x41
        .DAT    on_irq, on_irq2
on_irq  ADD     R6, R6, 1
        RTI
on_irq2 ADD     R10, R10, 1
        RTI
