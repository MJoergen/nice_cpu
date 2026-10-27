; Run after start_wasm.nasm. A trap as the translator emits it (WASM.md):
; R1 = 3, R2 = the trapping code's address, then a jump through
; ___wasm_trap_vector. The default handler is a reserved control word, so
; the processor halts with "reserved control instruction" and exit status 2.
;
; Addresses 0-12 are the start-up code. ___wasm_start is 13, and main
; starts at 14 (0xE), which R2 holds. lib.nasm follows at 21: the vector at
; 21 and ___wasm_trap at 22, so PC = 23 (0x17) after the halt. Steps: 1 +
; 2 + 1 + 2 + 2 + 3 in main + the reserved word = 12. SP = 0xFFFFFEFF, as
; main left it: the handler is entered by a jump, so nothing pops the
; return address.

___wasm_start
                MOVE    R15, @R13++
_main           MOVE    R1, 3           ; words 14,15
                MOVE    R2, _main       ; words 16,17
                MOVE    R15, @___wasm_trap_vector  ; words 18,19
                HALT                    ; word 20: not reached
