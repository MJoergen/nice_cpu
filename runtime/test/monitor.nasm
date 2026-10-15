; A stand-in for a monitor, for the tests of start_mon.nasm and
; start_wasm_mon.nasm. It sits at 0, where the monitor's ROM is, and does
; what the monitor does to run a program: sets SP to its stack, calls the
; program at 0x8000, and, when the program returns, halts with the
; program's result in R1.
;
; Addresses 0-1 set SP, 2-5 are the call, and HALT is at 6, so the call
; pushes 6 at 0xFFFFFEFF.

        MOVE    R13, 0xFFFFFF00         ; SP
        ADD     @--R13, 2, R15          ; call the program
        MOVE    R15, 0x8000
        HALT
