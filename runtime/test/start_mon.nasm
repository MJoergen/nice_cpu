; Run after test/monitor.nasm and start_mon.nasm. The stand-in calls 0x8000
; with R1 = mon.putc, R2 = 1, and R3 = mon.argv (0x16). main gets argc in
; R1 and argv in R2, stores them in args, and returns 42. The start-up code
; returns to the stand-in, which halts with R1 = 42, R2 = 0 bytes written,
; R3 still 0x16, and SP back at 0xFFFFFF00.
;
; The stand-in's call pushes 9 at 0xFFFFFEFF. Addresses 0x8000-0x800B are
; the start-up code: it jumps to main, so main's return pops the 9, and
; 0xFFFFFEFE stays 0. ___exit.sp at 0x800B holds 0xFFFFFEFF, the SP at
; entry, and the vectors are 0x800C-0x800D. main is 0x800E-0x8014 and args
; 0x8015-0x8016. Steps: 5 in the
; stand-in, 6 in the start-up code, 4 in main, and 2 in the stand-in = 17.
; Z is clear, from the test of R1 in the start-up code.

_main           MOVE    @args, R1
                MOVE    @args+1, R2
                MOVE    R1, 42
                RET
args            .BLK    2
