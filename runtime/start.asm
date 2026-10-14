; Start-up code for a program without a wasm module (doc/ISA.md §9.3).
; It sits at address 0, so it comes first in the program.
;
; SP starts at 0xFFFFFF00, one past the highest word below the I/O
; addresses (§8.3). A system with less memory needs a lower value.

        .ORG    0
        MOVE    R13, 0xFFFFFF00         ; SP
        MOVE    R1, R0                  ; argc = 0
        MOVE    R2, R0                  ; argv = NULL
        ADD     @--R13, 2, R15          ; call main
        MOVE    R15, _main
        HALT                            ; R1 holds main's result
