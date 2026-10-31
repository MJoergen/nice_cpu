; Start-up code for a program without a wasm module that a monitor runs
; (ABI.md, "Programs under a monitor"). The monitor's ROM takes
; 0x0000-0x7FFF, so the program is assembled at 0x8000. The monitor calls
; the program on its own stack with R1 = its putc routine, or 0 for the
; console, R2 = argc, and R3 = argv. So this does not set SP: it saves it
; for exit, stores a putc routine in ___putc_vector, and jumps to main
; with argc and argv, so main returns to the monitor instead of halting.

                .ORG    0x8000
                MOVE    @___exit.sp, R13  ; SP at entry, for exit
                MOVE[M] R0, R1          ; Z if the output stays on the console
        ?!Z     MOVE    @___putc_vector, R1
                MOVE    R1, R2          ; argc
                MOVE    R2, R3          ; argv
                MOVE    R15, _main      ; a tail call: main returns to the monitor

; exit: returns to the monitor from anywhere, with the status in R1 and SP
; as it was at entry (ABI.md). 2 steps.
_exit           MOVE    R13, @___exit.sp
                RET
___exit.sp
                .BLK    1
