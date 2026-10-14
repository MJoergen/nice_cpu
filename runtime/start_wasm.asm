; Start-up code for a program with a wasm module (doc/ISA.md §9.3, §9.4).
; It is start.asm with a call to ___wasm_start before main.

        .ORG    0
        MOVE    R13, 0xFFFFFF00         ; SP
        ADD     @--R13, 2, R15          ; call ___wasm_start
        MOVE    R15, ___wasm_start
        MOVE    R1, R0                  ; argc = 0
        MOVE    R2, R0                  ; argv = NULL
        ADD     @--R13, 2, R15          ; call main
        MOVE    R15, _main
        HALT                            ; R1 holds main's result
