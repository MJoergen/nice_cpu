; Run after start_wasm.asm. ___wasm_start stores 41 in flag, and main
; returns flag + 1. So R1 = 42 shows that ___wasm_start ran first.
;
; Addresses 0-10 are the start-up code, with HALT at 10. ___wasm_start is
; 11-14, main is 15-18, and flag is 19 (0x13). The second call pushes 10
; at 0xFFFFFEFF. Steps: MOVE SP, 2 per call, 2 in each function, and HALT
; = 1 + 4 + 4 + 1 = 10.

___wasm_start
        MOVE    @flag, 41
        MOVE    R15, @R13++
_main   ADD     R1, @flag, 1
        MOVE    R15, @R13++
flag    .DAT    0
