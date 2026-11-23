; Run after test/monitor.nasm and start_wasm_mon.nasm. ___wasm_start
; prints a newline with nice_putc, which goes through ___putc_vector to
; mon.putc, the routine the stand-in passed: the start-up code stored the
; vector before the call, as a constructor may print. It stores 41 in
; flag and leaves R1 = 5, R2 = 7, and R3 = 9, as a C ABI function may.
; main gets argc = 1 in R1 and argv = 0x16 in R2, the stand-in's, kept on
; the stack across that call. It stores argv in args and returns
; argc + flag = 42. The stand-in halts with R1 = 42, R2 = 1 byte written,
; and R3 = 9, which nothing restores. Z is clear: mon.putc's ADD[M] made 1.
;
; The stand-in's call pushes 9 at 0xFFFFFEFF. Addresses 0x8000-0x8010 are
; the start-up code: it pushes argc at 0xFFFFFEFE and argv at 0xFFFFFEFD,
; and its call of ___wasm_start pushes 0x8008 at 0xFFFFFEFC, whose call of
; nice_putc pushes 0x8017 at 0xFFFFFEFB. After the pops, it jumps to main,
; so argc stays at 0xFFFFFEFE. ___exit.sp at 0x800E holds 0xFFFFFEFF, and
; the vectors are 0x800F-0x8010. ___wasm_start is 0x8011-0x801D, main
; 0x801E-0x8022, flag 0x8023, and args 0x8024. Steps: 5 in the stand-in,
; 6 to the call of ___wasm_start, 13 in it, with 1 in nice_putc and 5 in
; mon.putc, 2 pops, the jump to main, 3 in main, and 2 in the stand-in =
; 32.

___wasm_start
                MOVE    @flag, 41
                MOVE    R1, 10          ; a newline through the vector
                CALL    _nice_putc
                MOVE    R1, 5
                MOVE    R2, 7
                MOVE    R3, 9
                RET
_main           MOVE    @args, R2
                ADD     R1, R1, @flag
                RET
flag            .DAT    0
args            .BLK    1
