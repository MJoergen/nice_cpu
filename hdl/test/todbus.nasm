; The bus decoder of test/tb_core.vhd and the clock of the time of day,
; src/tod.vhd (SYSTEM.md §10). The emulator runs this on the host's clock,
; and the core on its cycles, so the program reads only what is the same
; on both: the seconds it set, "set" after a write of CLOCK_USEC and after
; a write of CLOCK_STATUS, and READ_LO, the word after the clock, which is
; the read counter of src/perf.vhd. The microseconds go to R0, which drops
; them. R1 = 0x12345678 and R2 = 9, the seconds set, R3 = 1, R4 = 0, and
; R5 = 5, the data reads before it.
CLOCK_USEC      .EQU    0xFFFFFF46
CLOCK_SEC_LO    .EQU    0xFFFFFF47
CLOCK_SEC_HI    .EQU    0xFFFFFF48
CLOCK_STATUS    .EQU    0xFFFFFF49
READ_LO         .EQU    0xFFFFFF4A
                MOVE    @CLOCK_SEC_LO, 0x12345678
                MOVE    @CLOCK_SEC_HI, 9
                MOVE    @CLOCK_USEC, 0
                MOVE    R0, @CLOCK_USEC
                MOVE    R1, @CLOCK_SEC_LO
                MOVE    R2, @CLOCK_SEC_HI
                MOVE    R3, @CLOCK_STATUS
                MOVE    @CLOCK_STATUS, 0
                MOVE    R4, @CLOCK_STATUS
                MOVE    R5, @READ_LO
                HALT
