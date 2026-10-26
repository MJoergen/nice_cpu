; The trap report (trapmsg.nasm) for a code above 7. As trapreport.nasm, but
; with R1 = 12. The report writes "trap ?: unknown trap at 00001abc" and a
; newline: "?" in place of the digit, and the name of code 0. The processor
; halts as there, with exit status 2 (as after any halt but HALT), R1 = 12,
; R2 = 0x1abc, R10 = 12, and R11 = 0x1abc.
;
; The steps are those of trapreport.nasm, 247, less the 27 characters of
; "memory access out of bounds" and plus the 12 of "unknown trap", each
; character costing 4 steps: 247 - 4 * 15 = 187. The conditional moves that
; are skipped count as steps, so the digit and the name take as many for
; code 12 as for code 2.

___wasm_start
        MOVE    R15, @R13++
        .ORG    0x1abc
_main   MOVE    R1, 12
        MOVE    R2, _main
        MOVE    R15, @___wasm_trap_vector
        HALT                            ; not reached
