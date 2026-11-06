; Start-up code for a program with a wasm module, whose traps print a
; message (ABI.md, WASM.md). It is start_wasm.nasm with the trap vector
; holding ___trap_report of trapmsg.nasm, so a program that uses it joins
; trapmsg.nasm too. exit is the HALT after main, as in start.nasm.

                .ORG    0
                MOVE    R13, 0xFFFFFF00  ; SP
                CALL    ___wasm_start
                MOVE    R1, R0          ; argc = 0
                MOVE    R2, R0          ; argv = NULL
                CALL    _main
_exit           HALT                    ; R1 holds main's result, or exit's status

; The vectors that lib.nasm jumps through (ABI.md). They are here, not in
; lib.nasm, so that a system whose code runs from a ROM, and which has
; start-up code of its own, can put them in its RAM.

; ___wasm_trap_vector: wasm traps jump through it (WASM.md). It holds the
; trap report of trapmsg.nasm.
___wasm_trap_vector
                .DAT    ___trap_report

; ___putc_vector: nice_putc and nice_print jump through it. It holds
; ___console_putc of lib.nasm, which writes the console, until the program
; stores another routine.
___putc_vector
                .DAT    ___console_putc
