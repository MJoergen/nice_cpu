; Run after start.nasm. main returns 42, and the start-up code halts with
; R1 = 42 and SP back at 0xFFFFFF00.
;
; Addresses 0-8 are the start-up code, with HALT at 8, so the call pushes 8
; at 0xFFFFFEFF. Steps: MOVE SP, R1 = 0, R2 = 0, the call (2), MOVE R1,
; return, HALT = 8.

_main           MOVE    R1, 42
                MOVE    R15, @R13++
