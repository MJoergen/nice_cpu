; The trap report (trapmsg.nasm). Run after start_wasm_trap.nasm, with
; trapmsg.nasm joined after lib.nasm. A trap as the translator emits it
; (WASM.md): R1 = 2, R2 = the trapping code's address, 0x1abc, and a jump
; through ___wasm_trap_vector. The report writes
; "trap 2: memory access out of bounds at 00001abc" and a newline, and then
; the processor halts at ___wasm_trap as in trap.nasm, with exit status 2,
; R1 = 2, and R2 = 0x1abc.
;
; The start-up code is 15 words, with its vectors at 13-14, so
; ___wasm_start is at 15 and the .ORG moves main to 0x1abc. lib.nasm
; follows main's 7 words, with ___wasm_trap at 0x1ac3, so PC = 0x1ac4 after
; the halt. The
; report leaves R9 = 0, R10 = 2, R11 = 0x1abc, and the flag Z set by its
; last DEC: the console routine behind ___putc_vector changes no flags.
; SP = 0xFFFFFEFF, as in trap.nasm. Steps, with a call of nice_putc at 5
; and of nice_print at 8 + 6n for n characters: 11 up to the jump to the
; report, 2 to save R1 and R2, 3 + 36 for "trap " and 3 + 5 for the digit,
; 3 + 18 for ": ", 6 + 168 for the name, 3 + 30 for " at ", 1 + 8 * 10 for
; the 8 digits, 1 + 5 for the newline, 3 to restore and jump, and the
; reserved word = 379.

___wasm_start
                RET
                .ORG    0x1abc
_main           MOVE    R1, 2
                MOVE    R2, _main
                JMP     @___wasm_trap_vector
                HALT                    ; not reached
