; Run after start.nasm. A program installs its own trap handler at run
; time by storing its address in ___wasm_trap_vector (WASM.md), and then
; traps as the translator does: R1 = 4, R2 = the trapping code's address,
; and a jump through the vector. The handler stores R1 and R2 and halts
; with HALT, so the exit status is 0, not the 2 of the default handler.
;
; Code: start.nasm is words 0-7, with ___wasm_trap_vector at 6 and
; ___putc_vector at 7. main is 8-20: the two three-word MOVEs at 8 and
; 11, then 14, 16, and 18, and the HALT at 20 that the jump skips. handler
; is 21-25 (0x15-0x19), with its HALT at 25, so PC = 26 (0x1A) after it.
; saved is 26, got 27-28, and lib.nasm follows at 29 (0x1D) with
; ___wasm_trap.
;
; The dumps show the vector = 0x15, handler, and at 0x1A-0x1C saved =
; 0x1D, the vector's first value, ___wasm_trap, and got = 4 and 8, the
; code and main's address. Steps: 4 in the start-up code, 5 in main, and 3
; in handler = 12. SP = 0xFFFFFEFF, as main left it: the handler is entered
; by a jump.

_main           MOVE    @saved, @___wasm_trap_vector
                MOVE    @___wasm_trap_vector, handler
                MOVE    R1, 4
                MOVE    R2, _main
                JMP     @___wasm_trap_vector
                HALT                    ; not reached
handler         MOVE    @got, R1
                MOVE    @got+1, R2
                HALT
saved           .BLK    1
got             .BLK    2
