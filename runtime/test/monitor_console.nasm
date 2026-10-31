; test/monitor.nasm with R1 = 0: a stand-in for a monitor that leaves the
; output on the console (ABI.md, "Programs under a monitor"). mon.putc
; stays, unused, so that the addresses are those of monitor.nasm, and
; mon.count stays 0, which shows that nothing went through it. The steps
; are the same: 4 to set up, 2 for the call, and 2 after the return.

mon.console     .EQU    0xFFFFFF00

                MOVE    R13, 0xFFFFFF00  ; SP
                MOVE    R1, 0           ; the output stays on the console
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
