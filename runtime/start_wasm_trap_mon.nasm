; Start-up code for a program with a wasm module that a monitor runs, whose
; traps print a message (ABI.md, "Programs under a monitor", and WASM.md).
; It is start_wasm_mon.nasm with the trap vector set to ___trap_report of
; trapmsg.nasm first, so a program that uses it joins trapmsg.nasm too.
; The report prints through ___putc_vector, so it reaches the monitor's
; output. A trap still halts the processor; it does not return to the
; monitor.

                .ORG    0x8000
                MOVE    @___exit.sp, R13  ; SP at entry, for exit
                TST     R1              ; Z if the output stays on the console
        ?!Z     MOVE    @___putc_vector, R1
                MOVE    @___wasm_trap_vector, ___trap_report
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
