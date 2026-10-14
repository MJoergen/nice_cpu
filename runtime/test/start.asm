; Run after start.asm. main returns 42, and the start-up code halts with
; R1 = 42 and SP back at 0xFFFFFF00.
;
; Addresses 0-6 are the start-up code, with HALT at 6, so the call pushes 6
; at 0xFFFFFEFF. Steps: MOVE SP, the call (2), MOVE R1, return, HALT = 6.

_main   MOVE    R1, 42
        MOVE    R15, @R13++
