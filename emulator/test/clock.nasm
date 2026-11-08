; The clock of the time of day (SYSTEM.md §10), run with --step-time, so
; that it counts one microsecond per step from 0, with "set" 0. A read of
; CLOCK_USEC returns the microseconds of the steps before the reading one,
; and takes a snapshot of the seconds; CLOCK_SEC_LO and CLOCK_SEC_HI
; return the snapshot. Writes of the seconds stage them, and a write of
; CLOCK_USEC sets the clock to them, at once, and sets "set". S below is
; 0x9_12345678. Each read is copied to the table at 0x100.
;
;   step
;    0    0x100 <- STATUS      0, not set
;    1    0x101 <- USEC        1; snapshot 0
;    2    0x102 <- SEC_LO      0
;    3    SEC_LO <- 0x12345678 staged
;    4    SEC_HI <- 9          staged
;    5    0x103 <- SEC_LO      0: staging leaves the snapshot
;    6    0x104 <- USEC        6: staging leaves the clock
;    7    USEC <- 999998       S s 999998 us, set; 999999 after the step
;    8    0x105 <- USEC        999999 = 0xf423f; snapshot S
;    9    0x106 <- USEC        0: the second S + 1 began; snapshot S + 1
;   10    0x107 <- SEC_LO      0x12345679
;   11    0x108 <- SEC_HI      9
;   12    0x109 <- STATUS      1
;   13    STATUS <- 0x55       clears "set"
;   14    0x10a <- STATUS      0
;   15    USEC <- 0xffffffff   999999, the most, with S still staged; set
;   16    0x10b <- USEC        0: S + 1 began after step 15; snapshot S + 1
;   17    0x10c <- SEC_LO      0x12345679, so the value was taken as 999999
;   18    SEC_LO <- 0xffffffff
;   19    SEC_HI <- 0xffffffff
;   20    USEC <- 999998       the last second; 999999 after the step
;   21    0x10d <- USEC        999999; snapshot 2^64 - 1; then it wraps to 0
;   22    0x10e <- SEC_HI      0xffffffff
;   23    0x10f <- USEC        1; snapshot 0
;   24    0x110 <- SEC_HI      0
;   25    HALT
;
; 26 steps. PC = 0x4c after the HALT at 0x4b. The dump reads the clock
; without a snapshot, 4 steps after the wrap: USEC 4, the snapshot 0:0,
; and STATUS 1.
CLOCK_USEC      .EQU    0xFFFFFF46
CLOCK_SEC_LO    .EQU    0xFFFFFF47
CLOCK_SEC_HI    .EQU    0xFFFFFF48
CLOCK_STATUS    .EQU    0xFFFFFF49
                MOVE    @0x100, @CLOCK_STATUS  ; words 0-2
                MOVE    @0x101, @CLOCK_USEC  ; 3-5
                MOVE    @0x102, @CLOCK_SEC_LO  ; 6-8
                MOVE    @CLOCK_SEC_LO, 0x12345678  ; 9-b
                MOVE    @CLOCK_SEC_HI, 9  ; c-e
                MOVE    @0x103, @CLOCK_SEC_LO  ; f-11
                MOVE    @0x104, @CLOCK_USEC  ; 12-14
                MOVE    @CLOCK_USEC, 999998  ; 15-17
                MOVE    @0x105, @CLOCK_USEC  ; 18-1a
                MOVE    @0x106, @CLOCK_USEC  ; 1b-1d
                MOVE    @0x107, @CLOCK_SEC_LO  ; 1e-20
                MOVE    @0x108, @CLOCK_SEC_HI  ; 21-23
                MOVE    @0x109, @CLOCK_STATUS  ; 24-26
                MOVE    @CLOCK_STATUS, 0x55  ; 27-29
                MOVE    @0x10a, @CLOCK_STATUS  ; 2a-2c
                MOVE    @CLOCK_USEC, 0xffffffff  ; 2d-2f
                MOVE    @0x10b, @CLOCK_USEC  ; 30-32
                MOVE    @0x10c, @CLOCK_SEC_LO  ; 33-35
                MOVE    @CLOCK_SEC_LO, 0xffffffff  ; 36-38
                MOVE    @CLOCK_SEC_HI, 0xffffffff  ; 39-3b
                MOVE    @CLOCK_USEC, 999998  ; 3c-3e
                MOVE    @0x10d, @CLOCK_USEC  ; 3f-41
                MOVE    @0x10e, @CLOCK_SEC_HI  ; 42-44
                MOVE    @0x10f, @CLOCK_USEC  ; 45-47
                MOVE    @0x110, @CLOCK_SEC_HI  ; 48-4a
                HALT                    ; 4b
