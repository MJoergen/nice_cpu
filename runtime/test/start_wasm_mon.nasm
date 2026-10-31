; Run after test/monitor.nasm and start_wasm_mon.nasm. ___wasm_start
; prints a newline with nice_putc, which goes through ___putc_vector to
; mon.putc, the routine the stand-in passed: the start-up code stored the
; vector before the call, as a constructor may print. It stores 41 in
; flag and leaves R1 = 5, R2 = 7, and R3 = 9, as a C ABI function may.
; main gets argc = 1 in R1 and argv = 0x19 in R2, the stand-in's, kept on
; the stack across that call. It stores argv in args and returns
; argc + flag = 42. The stand-in halts with R1 = 42, R2 = 1 byte written,
; and R3 = 9, which nothing restores. Z is clear: mon.putc's ADD[M] made 1.
;
; The stand-in's call pushes 0xC at 0xFFFFFEFF. Addresses 0x8000-0x8015 are
; the start-up code: it pushes argc at 0xFFFFFEFE and argv at 0xFFFFFEFD,
; and its call of ___wasm_start pushes 0x800B at 0xFFFFFEFC, whose call of
; nice_putc pushes 0x801F at 0xFFFFFEFB. After the pops, its call of main
; pushes 0x8011 at 0xFFFFFEFE. ___exit.sp at 0x8015 holds 0xFFFFFEFF.
; ___wasm_start is 0x8016-0x8025, main 0x8026-0x802A, flag 0x802B, and
; args 0x802C. Steps: 6 in the stand-in, 7 to the call of ___wasm_start,
; 14 in it, with 1 in nice_putc and 5 in mon.putc, 2 pops and 2 for the
; call of main, 3 in main, the return, and 2 in the stand-in = 37.

___wasm_start
                MOVE    @flag, 41
                MOVE    R1, 10          ; a newline through the vector
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_putc
                MOVE    R1, 5
                MOVE    R2, 7
                MOVE    R3, 9
                MOVE    R15, @R13++
_main           MOVE    @args, R2
                ADD     R1, R1, @flag
                MOVE    R15, @R13++
flag            .DAT    0
args            .BLK    1
