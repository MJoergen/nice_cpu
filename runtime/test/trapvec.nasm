; Run after start.nasm. A program installs its own trap handler at run
; time by storing its address in ___wasm_trap_vector (WASM.md), and then
; traps as the translator does: R1 = 4, R2 = the trapping code's address,
; and a jump through the vector. The handler stores R1 and R2 and halts
; with HALT, so the exit status is 0, not the 2 of the default handler.
;
; Code: start.nasm is words 0-8. main is 9-21: the two three-word MOVEs
; at 9 and 12, then 15, 17, and 19, and the HALT at 21 that the jump
; skips. handler is 22-26 (0x16-0x1A), with its HALT at 26, so PC = 27
; (0x1B) after it. saved is 27, got 28-29, and lib.nasm follows at 30
; (0x1E): the vector at 30 and ___wasm_trap at 31 (0x1F).
;
; The dump of 0x1B-0x1E shows saved = 0x1F, the vector's first value,
; ___wasm_trap; got = 4 and 9, the code and main's address; and the vector
; = 0x16, handler. Steps: 5 in the start-up code, 5 in main, and 3 in
; handler = 13. SP = 0xFFFFFEFF, as main left it: the handler is entered
; by a jump.

_main   MOVE    @saved, @___wasm_trap_vector
        MOVE    @___wasm_trap_vector, handler
        MOVE    R1, 4
        MOVE    R2, _main
        MOVE    R15, @___wasm_trap_vector
        HALT                            ; not reached
handler MOVE    @got, R1
        MOVE    @got+1, R2
        HALT
saved   .BLK    1
got     .BLK    2
