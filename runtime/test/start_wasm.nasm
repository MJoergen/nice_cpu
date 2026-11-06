; Run after start_wasm.nasm. ___wasm_start stores 41 in flag and leaves R1 = 5
; and R2 = 7. main returns R1 + R2 + flag + 1. So R1 = 42 shows that
; ___wasm_start ran first, and that the start-up code then set R1 and R2 to
; 0 for main.
;
; Addresses 0-12 are the start-up code, with HALT at 12, and 13-14 its
; vectors. ___wasm_start is 15-22, main is 23-28, and flag is 29 (0x1D). The second call pushes 12
; (0xC) at 0xFFFFFEFF. Steps: MOVE SP, 2 per call, 4 in ___wasm_start,
; R1 = 0, R2 = 0, 4 in main, and HALT = 1 + 4 + 4 + 2 + 4 + 1 = 16.

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
