; Start-up code for a program with a wasm module, whose traps print a
; message (ABI.md, WASM.md). It is start_wasm.nasm with the trap vector set
; to ___trap_report of trapmsg.nasm first, so a program that uses it joins
; trapmsg.nasm too. exit is the HALT after main, as in start.nasm.

                .ORG    0
                MOVE    R13, 0xFFFFFF00  ; SP
                MOVE    @___wasm_trap_vector, ___trap_report
                ADD     @--R13, 2, R15  ; call ___wasm_start
                MOVE    R15, ___wasm_start
                MOVE    R1, R0          ; argc = 0
                MOVE    R2, R0          ; argv = NULL
                ADD     @--R13, 2, R15  ; call main
                MOVE    R15, _main
_exit           HALT                    ; R1 holds main's result, or exit's status
