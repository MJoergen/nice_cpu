; Run after test/monitor.nasm and start_mon.nasm. The stand-in calls 0x8000
; with R1 = mon.putc, R2 = 1, and R3 = mon.argv (0x19). main gets argc in
; R1 and argv in R2, stores them in args, and returns 42. The start-up code
; returns to the stand-in, which halts with R1 = 42, R2 = 0 bytes written,
; R3 still 0x19, and SP back at 0xFFFFFF00.
;
; The stand-in's call pushes 0xC at 0xFFFFFEFF. Addresses 0x8000-0x800C are
; the start-up code: it jumps to main, so main's return pops the 0xC, and
; 0xFFFFFEFE stays 0. ___exit.sp at 0x800C holds 0xFFFFFEFF, the SP at
; entry. main is 0x800D-0x8013 and args 0x8014-0x8015. Steps: 6 in the
; stand-in, 6 in the start-up code, 4 in main, and 2 in the stand-in = 18.
; Z is clear, from the test of R1 in the start-up code.

_main           MOVE    @args, R1
                MOVE    @args+1, R2
                MOVE    R1, 42
                RET
args            .BLK    2
