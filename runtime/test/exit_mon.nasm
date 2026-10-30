; Run after test/monitor.nasm and start_mon.nasm. main prints "Hi" with
; nice_print and a newline with nice_putc, which go through ___putc_vector
; to mon.putc, the routine the stand-in passed, and then calls f, which
; calls exit with 7 from a frame of its own. exit restores the SP of the
; entry and returns to the stand-in, which halts with R1 = 7, R2 = 3 bytes
; written, and SP back at 0xFFFFFF00. R7 is 0: nice_print restored it, and
; f's push did not change it. Z is clear: mon.putc's last ADD[M] made 3.
;
; The stand-in's call pushes 0xC at 0xFFFFFEFF, and the start-up code's
; call of main 0x800B at 0xFFFFFEFE. main is 0x8010-0x8020: its call of f
; pushes 0x8020 at 0xFFFFFEFD. f is 0x8021-0x8028: it pushes R7 at
; 0xFFFFFEFC, and its call of exit pushes 0x8028 at 0xFFFFFEFB. text is
; 0x8029-0x802B. Steps: 6 in the stand-in, 7 in the start-up code, 3 for
; nice_print's call and 6 + 9 * 2 in it with mon.putc at 5 steps, 3 for
; nice_putc's call and 6 in it, 2 for the call of f, 4 in f, 2 in exit,
; and 2 in the stand-in = 59.

_main           MOVE    R1, text
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_print
                MOVE    R1, 10
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_putc
                ADD     @--R13, 2, R15
                MOVE    R15, f
                HALT                    ; not reached
f               MOVE    @--R13, R7
                MOVE    R1, 7
                ADD     @--R13, 2, R15
                MOVE    R15, _exit
                HALT                    ; not reached
text            .ASCII_L 'Hi'
