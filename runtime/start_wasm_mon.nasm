; Start-up code for a program with a wasm module that a monitor runs
; (ABI.md, "Programs under a monitor", and WASM.md). It is
; start_mon.nasm with a call to ___wasm_start before main.

        .ORG    0x8000
        ADD     @--R13, 2, R15          ; call ___wasm_start
        MOVE    R15, ___wasm_start
        MOVE    R1, R0                  ; argc = 0
        MOVE    R2, R0                  ; argv = NULL
        ADD     @--R13, 2, R15          ; call main
        MOVE    R15, _main
        MOVE    R15, @R13++             ; return to the monitor; R1 holds main's result
