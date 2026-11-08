; The hidden state of the debug link (DEBUG.md 6), for nicedbg's status:
; an INT, its RTI, and a request of the timer that E = 0 holds.
TIMER_PERIOD    .EQU    0xFFFFFF10
START           MOVE    R14, 0x00000001  ; VBASE = 1, E = 0
                INT     2
BACK            MOVE    @TIMER_PERIOD, 1
                NOP
                HALT
ISR             RTI
                .ORG    0x102
                .DAT    ISR
