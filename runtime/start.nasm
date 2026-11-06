; Start-up code for a program without a wasm module (ABI.md).
; It sits at address 0, so it comes first in the program.
;
; SP starts at 0xFFFFFF00, one past the highest word below the I/O
; addresses (§8.3). A system with less memory needs a lower value.
;
; exit is the HALT after the call of main: a program ends the same way
; from anywhere, with the status in R1 (ABI.md).

                .ORG    0
                MOVE    R13, 0xFFFFFF00  ; SP
                MOVE    R1, R0          ; argc = 0
                MOVE    R2, R0          ; argv = NULL
                CALL    _main
_exit           HALT                    ; R1 holds main's result, or exit's status

; The vectors that lib.nasm jumps through (ABI.md). They are here, not in
; lib.nasm, so that a system whose code runs from a ROM, and which has
; start-up code of its own, can put them in its RAM.

; ___wasm_trap_vector: wasm traps jump through it (WASM.md), also those of
; a library module. It holds the default handler of lib.nasm until a
; program stores its own.
___wasm_trap_vector
                .DAT    ___wasm_trap

; ___putc_vector: nice_putc and nice_print jump through it. It holds
; ___console_putc of lib.nasm, which writes the console, until the program
; stores another routine.
___putc_vector
                .DAT    ___console_putc
