; Run after test/monitor.nasm and start_mon.nasm. main prints "Hi" with
; nice_print and a newline with nice_putc, which go through ___putc_vector
; to mon.putc, the routine the stand-in passed, and then calls f, which
; calls exit with 7 from a frame of its own. exit restores the SP of the
; entry and returns to the stand-in, which halts with R1 = 7, R2 = 3 bytes
; written, and SP back at 0xFFFFFF00. R7 is 0: nice_print restored it, and
; f's push did not change it. Z is clear: mon.putc's last ADD[M] made 3.
;
; The stand-in's call pushes 0xC at 0xFFFFFEFF, and the start-up code
; jumps to main. main is 0x800D-0x801D: its call of f pushes 0x801D at
; 0xFFFFFEFE. f is 0x801E-0x8025: it pushes R7 at 0xFFFFFEFD, and its call
; of exit pushes 0x8025 at 0xFFFFFEFC. text is 0x8026-0x8028. Steps: 6 in
; the stand-in, 6 in the start-up code, 3 for nice_print's call and
; 6 + 9 * 2 in it with mon.putc at 5 steps, 3 for nice_putc's call and 6
; in it, 2 for the call of f, 4 in f, 2 in exit, and 2 in the
; stand-in = 58.

_main           MOVE    R1, text
                CALL    _nice_print
                MOVE    R1, 10
                CALL    _nice_putc
                CALL    f
                HALT                    ; not reached
f               MOVE    @--R13, R7
                MOVE    R1, 7
                CALL    _exit
                HALT                    ; not reached
text            .ASCII_L 'Hi'
