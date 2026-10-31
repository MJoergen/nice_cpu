; Start-up code for a program with a wasm module (ABI.md, WASM.md).
; It is start.nasm with a call to ___wasm_start before main, and exit is
; the HALT after main, as there.

                .ORG    0
                MOVE    R13, 0xFFFFFF00  ; SP
                CALL    ___wasm_start
                MOVE    R1, R0          ; argc = 0
                MOVE    R2, R0          ; argv = NULL
                CALL    _main
_exit           HALT                    ; R1 holds main's result, or exit's status
