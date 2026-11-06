; Run after start.nasm. A program installs its own trap handler at run
; time by storing its address in ___wasm_trap_vector (WASM.md), and then
; traps as the translator does: R1 = 4, R2 = the trapping code's address,
; and a jump through the vector. The handler stores R1 and R2 and halts
; with HALT, so the exit status is 0, not the 2 of the default handler.
;
; Code: start.nasm is words 0-10, with ___wasm_trap_vector at 9 and
; ___putc_vector at 10. main is 11-23: the two three-word MOVEs at 11 and
; 14, then 17, 19, and 21, and the HALT at 23 that the jump skips. handler
; is 24-28 (0x18-0x1C), with its HALT at 28, so PC = 29 (0x1D) after it.
; saved is 29, got 30-31, and lib.nasm follows at 32 (0x20) with
; ___wasm_trap.
;
; The dumps show the vector = 0x18, handler, and at 0x1D-0x1F saved =
; 0x20, the vector's first value, ___wasm_trap, and got = 4 and 0xB, the
; code and main's address. Steps: 5 in the start-up code, 5 in main, and 3 in
; handler = 13. SP = 0xFFFFFEFF, as main left it: the handler is entered
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
