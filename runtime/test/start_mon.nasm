; Run after test/monitor.nasm and start_mon.nasm. main returns 42, and the
; start-up code returns to the monitor, which halts with R1 = 42 and SP
; back at 0xFFFFFF00.
;
; The monitor's call pushes 6 at 0xFFFFFEFF. Addresses 0x8000-0x8006 are
; the start-up code, with the return at 0x8006, so its call to main
; pushes 0x8006 at 0xFFFFFEFE. Steps: MOVE SP, the monitor's call (2),
; R1 = 0, R2 = 0, the call (2), MOVE R1, return, return, HALT = 11.

_main   MOVE    R1, 42
        MOVE    R15, @R13++
