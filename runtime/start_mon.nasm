; Start-up code for a program without a wasm module that a monitor runs
; (ABI.md, "Programs under a monitor"). The monitor's ROM takes
; 0x0000-0x7FFF, so the program is assembled at 0x8000. The monitor calls
; the program with SP set to its own stack, so this does not set SP, and
; it returns to the monitor instead of halting.

        .ORG    0x8000
        MOVE    R1, R0                  ; argc = 0
        MOVE    R2, R0                  ; argv = NULL
        ADD     @--R13, 2, R15          ; call main
        MOVE    R15, _main
        MOVE    R15, @R13++             ; return to the monitor; R1 holds main's result
