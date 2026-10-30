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
; Addresses 0-1 set SP, 2-7 set R1-R3, 8-11 are the call, and 12-13 and 14
; are the MOVE and the HALT after the return, so the call pushes 12 (0xC) at
; 0xFFFFFEFF, and PC = 15 (0xF) after the halt. mon.putc is 15-23,
; mon.count 24 (0x18), mon.argv 25-26 (0x19), and mon.arg0 27-31. Steps: 4 to
; set up, 2 for the call, and 2 after the return.

mon.console     .EQU    0xFFFFFF00

                MOVE    R13, 0xFFFFFF00  ; SP
                MOVE    R1, mon.putc    ; the putc routine
                MOVE    R2, 1           ; argc
                MOVE    R3, mon.argv    ; argv
                ADD     @--R13, 2, R15  ; call the program
                MOVE    R15, 0x8000
                MOVE    R2, @mon.count  ; the bytes written
                HALT

mon.putc
                MOVE    @mon.console, R1
                MOVE    R1, @mon.count
                ADD[M]  R1, R1, 1
                MOVE    @mon.count, R1
                MOVE    R15, @R13++
mon.count
                .BLK    1
mon.argv
                .DAT    mon.arg0, 0
mon.arg0
                .ASCII_L 'nice'
