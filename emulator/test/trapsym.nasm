; --symbols (README.md): after a halt at ___wasm_trap, the emulator names
; the location of the halt and, from R1 and R2, the trap. See trapsym.sym.
;
; R1 = 2 and R2 = 0x13, the address 3 words into body, then a jump to
; ___wasm_trap, the reserved word at 6. Steps: 3 + 1 = 4. PC = 7 after the
; halt. The output names ___wasm_trap, and then trap 2 at body+0x3.
start   MOVE    R1, 2
        MOVE    R2, 0x13
        MOVE    R15, ___wasm_trap
___wasm_trap
        .DAT    0x0FE00000
        .ORG    0x10
body    HALT
