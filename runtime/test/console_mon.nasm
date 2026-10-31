; Run after test/monitor_console.nasm and start_mon.nasm. The stand-in
; calls 0x8000 with R1 = 0, so the start-up code leaves ___putc_vector at
; ___console_putc. main prints "Hi" with nice_print and a newline with
; nice_putc, which reach the console, and returns 5. The stand-in halts
; with R1 = 5, R2 = 0, as nothing went through its putc routine, R3 =
; 0x19, its argv, and SP back at 0xFFFFFF00. R7 is 0: nice_print restored
; it. Z is set, and the other flags are clear: the last instruction with
; the M bit is nice_print's read of the 0 after "Hi".
;
; The stand-in's call pushes 0xC at 0xFFFFFEFF, and the start-up code's
; call of main 0x800B at 0xFFFFFEFE. Steps: 6 in the stand-in, 7 in the
; start-up code, with the skipped store of the vector, 1 to load R1, 2 for
; the call of nice_print and 6 + 6 * 2 in it with ___console_putc, 1 to
; load R1, 2 for the call of nice_putc and 3 in it, 1 for the result,
; main's return, the start-up code's return, and 2 in the stand-in = 45.

_main           MOVE    R1, text
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_print
                MOVE    R1, 10
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_putc
                MOVE    R1, 5
                MOVE    R15, @R13++
text            .ASCII_L 'Hi'
