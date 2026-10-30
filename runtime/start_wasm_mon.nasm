; Start-up code for a program with a wasm module that a monitor runs
; (ABI.md, "Programs under a monitor", and WASM.md). It is start_mon.nasm
; with a call to ___wasm_start before main. ___wasm_start may change
; R1-R6, as any C ABI function, so argc and argv wait on the stack while
; it runs, and the putc routine is stored before it, as a constructor may
; print.

                .ORG    0x8000
                MOVE    @___exit.sp, R13  ; SP at entry, for exit
                MOVE[M] R0, R1          ; Z if the output stays on the console
        ?!Z     MOVE    @___putc_vector, R1
                MOVE    @--R13, R2      ; argc and argv, across ___wasm_start
                MOVE    @--R13, R3
                ADD     @--R13, 2, R15  ; call ___wasm_start
                MOVE    R15, ___wasm_start
                MOVE    R2, @R13++      ; argv
                MOVE    R1, @R13++      ; argc
                ADD     @--R13, 2, R15  ; call main
                MOVE    R15, _main
                MOVE    R15, @R13++     ; return to the monitor; R1 holds main's result

; exit: returns to the monitor from anywhere, with the status in R1 and SP
; as it was at entry (ABI.md). 2 steps.
_exit           MOVE    R13, @___exit.sp
                MOVE    R15, @R13++
___exit.sp
                .BLK    1
