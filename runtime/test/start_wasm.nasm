; Run after start_wasm.nasm. ___wasm_start stores 41 in flag and leaves R1 = 5
; and R2 = 7. main returns R1 + R2 + flag + 1. So R1 = 42 shows that
; ___wasm_start ran first, and that the start-up code then set R1 and R2 to
; 0 for main.
;
; Addresses 0-6 are the start-up code, with HALT at 6, and 7-8 its
; vectors. ___wasm_start is 9-16, main is 17-22, and flag is 23 (0x17).
; The second call pushes 6 at 0xFFFFFEFF. Steps: MOVE SP, 1 per call, 4
; in ___wasm_start, R1 = 0, R2 = 0, 4 in main, and HALT = 1 + 2 + 4 + 2 +
; 4 + 1 = 14.

___wasm_start
                MOVE    @flag, 41
                MOVE    R1, 5
                MOVE    R2, 7
                RET
_main           ADD     R1, R1, R2
                ADD     R1, R1, @flag
                ADD     R1, R1, 1
                RET
flag            .DAT    0
