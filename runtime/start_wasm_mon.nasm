; Start-up code for a program with a wasm module that a monitor runs
; (ABI.md, "Programs under a monitor", and WASM.md). It is start_mon.nasm
; with a call to ___wasm_start before main. ___wasm_start may change
; R1-R6, as any C ABI function, so argc and argv wait on the stack while
; it runs, and the putc routine is stored before it, as a constructor may
; print.

                .ORG    0x8000
                MOVE    @___exit.sp, R13  ; SP at entry, for exit
                TST     R1              ; Z if the output stays on the console
        ?!Z     MOVE    @___putc_vector, R1
                PUSH    R2              ; argc and argv, across ___wasm_start
                PUSH    R3
                CALL    ___wasm_start
                POP     R2              ; argv
                POP     R1              ; argc
                JMP     _main           ; a tail call: main returns to the monitor

; exit: returns to the monitor from anywhere, with the status in R1 and SP
; as it was at entry (ABI.md). 2 steps.
_exit           MOVE    R13, @___exit.sp
                RET
___exit.sp
                .BLK    1
