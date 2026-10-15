; Run after test/monitor.nasm and start_wasm_mon.nasm. As in
; test/start_wasm.nasm, ___wasm_start stores 41 in flag and leaves R1 = 5
; and R2 = 7, and main returns R1 + R2 + flag + 1, so R1 = 42 shows that
; ___wasm_start ran first and that R1 and R2 were then set to 0 for main.
; The start-up code returns to the monitor, which halts.
;
; The monitor's call pushes 6 at 0xFFFFFEFF. Addresses 0x8000-0x800A are
; the start-up code, with the return at 0x800A, so its call to main
; pushes 0x800A at 0xFFFFFEFE. ___wasm_start is 0x800B-0x8012, main is
; 0x8013-0x8018, and flag is 0x8019. Steps: MOVE SP, the monitor's call
; (2), 2 per call, 4 in ___wasm_start, R1 = 0, R2 = 0, 4 in main, return,
; HALT = 1 + 2 + 2 + 4 + 2 + 2 + 4 + 1 + 1 = 19.

___wasm_start
        MOVE    @flag, 41
        MOVE    R1, 5
        MOVE    R2, 7
        MOVE    R15, @R13++
_main   ADD     R1, R1, R2
        ADD     R1, R1, @flag
        ADD     R1, R1, 1
        MOVE    R15, @R13++
flag    .DAT    0
