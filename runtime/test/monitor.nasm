; A stand-in for a monitor, for the tests of the start-up files for a
; program under a monitor (ABI.md, "Programs under a monitor"). It sits at
; 0, where the monitor's ROM is, and does what the monitor does to run a
; program: sets SP to its stack, calls the program at 0x8000 with R1 = its
; putc routine, R2 = argc = 1, and R3 = argv, and, when the program
; returns, halts with the program's result in R1 and the number of bytes
; its putc routine wrote in R2.
;
; mon.putc writes bits 7..0 of R1 to the console and counts the bytes in
; mon.count. It changes R1 and the flags, as the C ABI allows, so a caller
; that relied on them would fail. 5 steps.
;
; Addresses 0-1 set SP, 2-7 set R1-R3, 8 is the call, and 9-10 and 11 are
; the MOVE and the HALT after the return, so the call pushes 9 at
; 0xFFFFFEFF, and PC = 12 (0xC) after the halt. mon.putc is 12-20,
; mon.count 21 (0x15), mon.argv 22-23 (0x16), and mon.arg0 24-28. Steps: 4
; to set up, 1 for the call, and 2 after the return.

mon.console     .EQU    0xFFFFFF00

                MOVE    R13, 0xFFFFFF00  ; SP
                MOVE    R1, mon.putc    ; the putc routine
                MOVE    R2, 1           ; argc
                MOVE    R3, mon.argv    ; argv
                CALL    0x8000          ; call the program
                MOVE    R2, @mon.count  ; the bytes written
                HALT

mon.putc
                MOVE    @mon.console, R1
                MOVE    R1, @mon.count
                ADD[M]  R1, R1, 1
                MOVE    @mon.count, R1
                RET
mon.count
                .BLK    1
mon.argv
                .DAT    mon.arg0, 0
mon.arg0
                .ASCII_L 'nice'
