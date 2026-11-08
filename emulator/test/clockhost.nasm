; The clock of the time of day (SYSTEM.md §10) on the host's clock, run
; without --step-time. "Set" is 1 from the start, as the host knows the
; time. The seconds are 0x40000000 or more from 2004 to 2106, so bit 31 or
; bit 30 is set: R2 = 1. SEC_HI is 0 until 2106: R3 = 0. The clock set to
; 0x9_12345678 s 0 us reads those seconds back a few microseconds later:
; R4 = 0x12345678, R5 = 9. A write of STATUS clears "set": R6 = 0.
; R1 = 1, the status at the start.
CLOCK_USEC      .EQU    0xFFFFFF46
CLOCK_SEC_LO    .EQU    0xFFFFFF47
CLOCK_SEC_HI    .EQU    0xFFFFFF48
CLOCK_STATUS    .EQU    0xFFFFFF49
                MOVE    R1, @CLOCK_STATUS
                MOVE    R2, @CLOCK_USEC
                MOVE    R7, @CLOCK_SEC_LO
                MOVE    R3, @CLOCK_SEC_HI
                SHR     R2, R7, 31
                SHR     R7, R7, 30
                OR      R2, R2, R7
                AND     R2, R2, 1
                CLR     R7
                MOVE    @CLOCK_SEC_LO, 0x12345678
                MOVE    @CLOCK_SEC_HI, 9
                MOVE    @CLOCK_USEC, 0
                MOVE    R4, @CLOCK_USEC
                MOVE    R4, @CLOCK_SEC_LO
                MOVE    R5, @CLOCK_SEC_HI
                MOVE    @CLOCK_STATUS, 0
                MOVE    R6, @CLOCK_STATUS
                HALT
