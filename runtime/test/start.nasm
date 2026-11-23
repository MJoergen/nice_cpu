; Run after start.nasm. main returns 42, and the start-up code halts with
; R1 = 42 and SP back at 0xFFFFFF00.
;
; Addresses 0-5 are the start-up code, with HALT at 5, so the call pushes 5
; at 0xFFFFFEFF. Steps: MOVE SP, R1 = 0, R2 = 0, the call, MOVE R1,
; return, HALT = 7.

_main           MOVE    R1, 42
                RET
