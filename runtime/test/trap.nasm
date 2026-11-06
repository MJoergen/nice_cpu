; Run after start_wasm.nasm. A trap as the translator emits it (WASM.md):
; R1 = 3, R2 = the trapping code's address, then a jump through
; ___wasm_trap_vector. The default handler is a reserved control word, so
; the processor halts with "reserved control instruction" and exit status 2.
;
; Addresses 0-12 are the start-up code, and 13-14 its vectors.
; ___wasm_start is 15, and main starts at 16 (0x10), which R2 holds.
; lib.nasm follows at 23 with ___wasm_trap, so PC = 24 (0x18) after the
; halt. Steps: 1 +
; 2 + 1 + 2 + 2 + 3 in main + the reserved word = 12. SP = 0xFFFFFEFF, as
; main left it: the handler is entered by a jump, so nothing pops the
; return address.

___wasm_start
                RET
_main           MOVE    R1, 3           ; words 16,17
                MOVE    R2, _main       ; words 18,19
                JMP     @___wasm_trap_vector  ; words 20,21
                HALT                    ; word 22: not reached
