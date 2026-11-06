; Start-up code for a program without a wasm module that a monitor runs
; (ABI.md, "Programs under a monitor"). The monitor's ROM takes
; 0x0000-0x7FFF, so the program is assembled at 0x8000. The monitor calls
; the program on its own stack with R1 = its putc routine, or 0 for the
; console, R2 = argc, and R3 = argv. So this does not set SP: it saves it
; for exit, stores a putc routine in ___putc_vector, and jumps to main
; with argc and argv, so main returns to the monitor instead of halting.

                .ORG    0x8000
                MOVE    @___exit.sp, R13  ; SP at entry, for exit
                TST     R1              ; Z if the output stays on the console
        ?!Z     MOVE    @___putc_vector, R1
                MOVE    R1, R2          ; argc
                MOVE    R2, R3          ; argv
                JMP     _main           ; a tail call: main returns to the monitor

; exit: returns to the monitor from anywhere, with the status in R1 and SP
; as it was at entry (ABI.md). 2 steps.
_exit           MOVE    R13, @___exit.sp
                RET
___exit.sp
                .BLK    1

; The vectors that lib.nasm jumps through (ABI.md). They are here, not in
; lib.nasm, so that a system whose code runs from a ROM, and which has
; start-up code of its own, can put them in its RAM.

; ___wasm_trap_vector: wasm traps jump through it (WASM.md), also those of
; a library module. It holds the default handler of lib.nasm until a
; program stores its own.
___wasm_trap_vector
                .DAT    ___wasm_trap

; ___putc_vector: nice_putc and nice_print jump through it. It holds
; ___console_putc of lib.nasm, which writes the console, until the start-up
; code above stores the monitor's putc routine, if it has one.
___putc_vector
                .DAT    ___console_putc
