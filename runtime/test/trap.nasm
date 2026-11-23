; Run after start_wasm.nasm. A trap as the translator emits it (WASM.md):
; R1 = 3, R2 = the trapping code's address, then a jump through
; ___wasm_trap_vector. The default handler is a reserved control word, so
; the processor halts with "reserved control instruction" and exit status 2.
;
; Addresses 0-6 are the start-up code, and 7-8 its vectors.
; ___wasm_start is 9, and main starts at 10 (0xA), which R2 holds.
; lib.nasm follows at 17 (0x11) with ___wasm_trap, so PC = 18 (0x12)
; after the halt. Steps: 1 + 1 + 1 + 2 + 1 + 3 in main + the reserved
; word = 10. SP = 0xFFFFFEFF, as
; main left it: the handler is entered by a jump, so nothing pops the
; return address.

___wasm_start
                RET
_main           MOVE    R1, 3           ; words 10,11
                MOVE    R2, _main       ; words 12,13
                JMP     @___wasm_trap_vector  ; words 14,15
                HALT                    ; word 16: not reached
