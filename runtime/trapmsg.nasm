; The trap report (WASM.md). start_wasm_trap.nasm stores ___trap_report in
; ___wasm_trap_vector. It goes after lib.nasm, which it uses.
;
; ___trap_report: a wasm trap handler. It writes one line to the console,
; such as "trap 2: out of bounds memory access at 00003dc9", with the
; trap's code from R1 and its address from R2, and then jumps to
; ___wasm_trap, the default handler. So the processor halts as without the
; report, with R1 and R2 as the trap left them. R3 is 0 and R10 and R11
; are changed. Uses the stack at SP, like a call.
___trap.console .EQU    0xFFFFFF00

___trap_report
        MOVE    R10, R1                 ; the code
        MOVE    R11, R2                 ; the address
        MOVE    R1, ___trap.head
        ADD     @--R13, 2, R15
        MOVE    R15, _nice_print
        ADD     R1, R10, 0x30           ; the code is 1 to 7
        MOVE    @___trap.console, R1
        MOVE    R1, ___trap.colon
        ADD     @--R13, 2, R15
        MOVE    R15, _nice_print
        AND     R1, R10, 7
        MOVE    R1, @___trap.names[R1]
        ADD     @--R13, 2, R15
        MOVE    R15, _nice_print
        MOVE    R1, ___trap.at
        ADD     @--R13, 2, R15
        MOVE    R15, _nice_print
        MOVE    R3, 8                   ; eight hex digits, high one first
___trap.digit
        ROL     R11, R11, 4             ; 8 times 4 bits: R11 is the address again
        AND     R1, R11, 15
        MOVE    R1, @___trap.hex[R1]
        MOVE    @___trap.console, R1
        DEC[M]  R3, R3
        ?!Z MOVE R15, ___trap.digit
        MOVE    @___trap.console, 10
        MOVE    R1, R10
        MOVE    R2, R11
        MOVE    R15, ___wasm_trap

___trap.head    .ASCII_L 'trap '
___trap.colon   .ASCII_L ': '
___trap.at      .ASCII_L ' at '
___trap.hex     .ASCII_L '0123456789abcdef'

; Indexed by code & 7, so that any code has a name.
___trap.names
        .DAT    ___trap.n0, ___trap.n1, ___trap.n2, ___trap.n3
        .DAT    ___trap.n4, ___trap.n5, ___trap.n6, ___trap.n7
___trap.n0      .ASCII_L 'unknown trap'
___trap.n1      .ASCII_L 'unreachable'
___trap.n2      .ASCII_L 'out of bounds memory access'
___trap.n3      .ASCII_L 'division by zero'
___trap.n4      .ASCII_L 'integer overflow'
___trap.n5      .ASCII_L 'float to integer conversion'
___trap.n6      .ASCII_L 'call_indirect: bad index'
___trap.n7      .ASCII_L 'call_indirect: type mismatch'
