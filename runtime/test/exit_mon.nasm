; Run after test/monitor.nasm and start_mon.nasm. main prints "Hi" with
; nice_print and a newline with nice_putc, which go through ___putc_vector
; to mon.putc, the routine the stand-in passed, and then calls f, which
; calls exit with 7 from a frame of its own. exit restores the SP of the
; entry and returns to the stand-in, which halts with R1 = 7, R2 = 3 bytes
; written, and SP back at 0xFFFFFF00. R7 is 0: nice_print restored it, and
; f's push did not change it. Z is clear: mon.putc's last ADD[M] made 3.
;
; The stand-in's call pushes 9 at 0xFFFFFEFF, and the start-up code,
; with its vectors at 0x800C-0x800D, jumps to main. main is 0x800E-0x8015:
; its call of f pushes 0x8015 at 0xFFFFFEFE. f is 0x8016-0x801A: it pushes
; R7 at 0xFFFFFEFD, and its call of exit pushes 0x801A at 0xFFFFFEFC. text
; is 0x801B-0x801D. Steps: 5 in the stand-in, 6 in the start-up code, 2
; for nice_print's call and 6 + 9 * 2 in it with mon.putc at 5 steps, 2
; for nice_putc's call and 6 in it, 1 for the call of f, 3 in f, 2 in
; exit, and 2 in the stand-in = 53.

_main           MOVE    R1, text
                CALL    _nice_print
                MOVE    R1, 10
                CALL    _nice_putc
                CALL    f
                HALT                    ; not reached
f               PUSH    R7
                MOVE    R1, 7
                CALL    _exit
                HALT                    ; not reached
text            .ASCII_L 'Hi'
