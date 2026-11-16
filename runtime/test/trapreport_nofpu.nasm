; The trap report (trapmsg.nasm) for code 9, the last that it names. As
; trapreport.nasm, but with R1 = 9. The report writes
; "trap 9: no FPU at 00001abc" and a newline: the digit of the last code
; below 10, and the last name of its table. The processor halts as there,
; with exit status 2, R1 = 9, R2 = 0x1abc, R10 = 9, and R11 = 0x1abc.
;
; The steps are those of trapreport.nasm, 379, less the 27 characters of
; "memory access out of bounds" and plus the 6 of "no FPU", each character
; costing 6 steps: 379 - 6 * 21 = 253.

___wasm_start
                RET
                .ORG    0x1abc
_main           MOVE    R1, 9
                MOVE    R2, _main
                JMP     @___wasm_trap_vector
                HALT                    ; not reached
