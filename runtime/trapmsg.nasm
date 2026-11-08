; The trap report (WASM.md). start_wasm_trap.nasm starts its
; ___wasm_trap_vector with ___trap_report. It goes after lib.nasm, which
; it uses.
;
; ___trap_report: a wasm trap handler. It writes one line, such as
; "trap 2: memory access out of bounds at 00003dc9", with the trap's code
; from R1 and its address from R2, named as the emulator's --symbols names
; them, with nice_print and nice_putc, and so through ___putc_vector, and
; then jumps to ___wasm_trap, the default handler. So the processor halts
; as without the report, with R1 and R2 as the trap left them. R9, R10,
; and R11 are changed, and R3-R6 and the flags may be, by the routine
; behind the vector. Uses the stack at SP, like a call.

___trap_report
                MOVE    R10, R1         ; the code
                MOVE    R11, R2         ; the address
                MOVE    R1, ___trap.head
                CALL    _nice_print
                SUB[M]  R0, R10, 9      ; C, a borrow, if the code is below 9
        ?C      ADD     R1, R10, 0x30   ; the digit
        ?!C     MOVE    R1, 0x3F        ; "?" for a code above 8
                CALL    _nice_putc
                MOVE    R1, ___trap.colon
                CALL    _nice_print
                SUB[M]  R0, R10, 9
        ?C      MOVE    R1, R10
        ?!C     MOVE    R1, 0           ; a code above 8 is unknown
                MOVE    R1, @___trap.names[R1]
                CALL    _nice_print
                MOVE    R1, ___trap.at
                CALL    _nice_print
                MOVE    R9, 8           ; eight hex digits, high one first
___trap.digit
                ROL     R11, R11, 4     ; 8 times 4 bits: R11 is the address again
                AND     R1, R11, 15
                MOVE    R1, @___trap.hex[R1]
                CALL    _nice_putc
                DEC[M]  R9, R9
        ?!Z     JMP     ___trap.digit
                MOVE    R1, 10
                CALL    _nice_putc
                MOVE    R1, R10
                MOVE    R2, R11
                JMP     ___wasm_trap

___trap.head
                .ASCII_L 'trap '
___trap.colon
                .ASCII_L ': '
___trap.at
                .ASCII_L ' at '
___trap.hex
                .ASCII_L '0123456789abcdef'

; Indexed by the code, or by 0 above 8, so that any code has a name.
___trap.names
                .DAT    ___trap.n0, ___trap.n1, ___trap.n2, ___trap.n3
                .DAT    ___trap.n4, ___trap.n5, ___trap.n6, ___trap.n7
                .DAT    ___trap.n8
___trap.n0
                .ASCII_L 'unknown trap'
___trap.n1
                .ASCII_L 'unreachable'
___trap.n2
                .ASCII_L 'memory access out of bounds'
___trap.n3
                .ASCII_L 'division by zero'
___trap.n4
                .ASCII_L 'integer overflow'
___trap.n5
                .ASCII_L 'float to integer conversion'
___trap.n6
                .ASCII_L 'call_indirect: bad index'
___trap.n7
                .ASCII_L 'call_indirect: type mismatch'
___trap.n8
                .ASCII_L 'memory beyond the byte windows'
