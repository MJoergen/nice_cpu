; Run after test/monitor.nasm and start_wasm_trap_mon.nasm, with
; trapmsg.nasm joined after lib.nasm. As test/trapreport.nasm, under the
; stand-in: a trap with R1 = 2 and R2 = main's address, 0x8016. The report
; goes through mon.putc, the routine the stand-in passed, so its 48 bytes,
; "trap 2: memory access out of bounds at 00008016" and a newline, are
; counted in mon.count (0x18), and the processor halts at ___wasm_trap with
; exit status 2, not in the stand-in: a trap does not return to the
; monitor. R1 and R2 are as the trap left them, R3 = 0x19, the argv the
; stand-in passed, R9 = 0 from the report's digit loop, R10 = 2, and
; R11 = 0x8016. Z is clear: mon.putc's last ADD[M] made 48.
;
; The stand-in's call pushes 0xC at 0xFFFFFEFF. The start-up code is
; 0x8000-0x8014, with its vectors at 0x8013-0x8014: it pushes argc at
; 0xFFFFFEFE, pops it again, and jumps to main, so SP stays at 0xFFFFFEFF:
; the handler is entered by a jump too. ___wasm_start is 0x8015, main
; 0x8016-0x801C, and lib.nasm follows, with ___wasm_trap at 0x801D, so
; PC = 0x801E. The report's calls push at 0xFFFFFEFE, and the last one, of
; nice_putc for the newline, leaves 0x815E there, the address after it.
;
; Steps: 6 in the stand-in, 7 to the call of ___wasm_start, 1 in it, 2 for
; the pops, the jump to main, and 3 in main = 20 up to the jump to the
; report. In the report, with mon.putc at 5 steps, a call of nice_putc is
; 8 steps and nice_print 6 + 9n for n characters: 2 to save R1 and R2,
; 3 + 51 for "trap ", 3 + 8 for the digit, 3 + 24 for ": ", 6 + 249 for
; the name, 3 + 42 for " at ", 1 + 8 * 13 for the 8 digits, 1 + 8 for the
; newline, 3 to restore and jump, and the reserved word = 512. In all 532.

___wasm_start
                RET
_main           MOVE    R1, 2
                MOVE    R2, _main
                JMP     @___wasm_trap_vector
                HALT                    ; not reached
