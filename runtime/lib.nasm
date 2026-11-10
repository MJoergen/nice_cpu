; The NICE runtime library (ABI.md). It goes after the program's
; own files, followed by muldiv_mpu.nasm or muldiv_soft.nasm, which hold the
; multiply and divide routines, the bit counts __clz, __ctz, and __popcnt,
; and _nice_isqrt64. Every routine follows the C ABI of ABI.md.
; It holds no word that it writes: the two vectors it jumps through,
; ___wasm_trap_vector and ___putc_vector, are in the start-up code, so that
; a system whose code runs from a ROM can put them in its RAM (ABI.md).

; ___wasm_trap: the default trap handler. It is the reserved control word
; 0x0FE00000 (§5.3), which halts with R1 and R2 as the trap left them. The
; emulator reports a reserved control instruction and exits with status 2,
; so a trap does not look like the normal end of the program.
___wasm_trap
                .DAT    0x0FE00000

; __clz64, __ctz64, __popcnt64: R1:R2 = the same counts for the 64-bit
; number in R1:R2. The result is at most 64, so R2 = 0.
; __clz64 steps: 7 + __clz(R2) if R2 is not 0, else 7 + __clz(R1).
__clz64         TST     R2
        ?Z      JMP     __clz64.lo
                MOVE    R1, R2
                CALL    __clz
                MOVE    R2, 0
                RET
__clz64.lo
                CALL    __clz
                ADD     R1, R1, 32
                MOVE    R2, 0
                RET

; __ctz64 steps: 6 + __ctz(R1) if R1 is not 0, else 8 + __ctz(R2).
__ctz64         TST     R1
        ?Z      JMP     __ctz64.hi
                CALL    __ctz
                MOVE    R2, 0
                RET
__ctz64.hi
                MOVE    R1, R2
                CALL    __ctz
                ADD     R1, R1, 32
                MOVE    R2, 0
                RET

; __popcnt64 steps: 10 + __popcnt(R1) + __popcnt(R2). Uses R3 and R4.
__popcnt64
                MOVE    R4, R2
                CALL    __popcnt
                MOVE    R3, R1
                MOVE    R1, R4
                CALL    __popcnt
                ADD     R1, R1, R3
                MOVE    R2, 0
                RET

; The device routines of ABI.md: the console (SYSTEM §1), the performance counters
; (SYSTEM §3), and the emulator's character screen. Unlike the routines above,
; programs call them by their C names. The console output goes through
; ___putc_vector, so that a monitor can direct it to its screen.
__nice.console  .EQU    0xFFFFFF00
__nice.cycle_lo .EQU    0xFFFFFF40
__nice.cycle_hi .EQU    0xFFFFFF41
__nice.instr_lo .EQU    0xFFFFFF42
__nice.instr_hi .EQU    0xFFFFFF43
__nice.screen   .EQU    0xFFFF0000      ; 80 columns, 25 rows
__nice.blank    .EQU    0x000FFF20      ; a blank in white on black (SYSTEM.md §1.4)

; nice_putc: writes bits 7..0 of R1 through ___putc_vector, the word of the
; start-up code that holds the routine that writes one character. The
; routine follows the C ABI: it writes bits 7..0 of R1, and may change
; R1-R6 and the flags (ABI.md, Device routines). 1 step and the
; routine's: 3 with ___console_putc, which changes nothing.
_nice_putc
                JMP     @___putc_vector

; ___console_putc: writes bits 7..0 of R1 to the console. 2 steps.
___console_putc
                MOVE    @__nice.console, R1
                RET

; nice_getc: R1 = the next input byte, waiting until there is one, or -1
; once the line's input has ended (SYSTEM §1); a keyboard's bytes may still
; come after that. A console read returns the byte with bit 8 set,
; 0 if none is waiting, or 0x200 at the end. Steps: 4 for a byte, 8 at the
; end, and 6 more for each read that finds no byte. Skipped instructions
; count as steps.
_nice_getc
                MOVE    R1, @__nice.console
                AND[M]  R0, R1, 0x100
        ?!Z     AND     R1, R1, 0xFF
        ?!Z     RET
                AND[M]  R0, R1, 0x200
        ?Z      JMPR    _nice_getc
                MOVE    R1, -1
                RET

; nice_pollc: as nice_getc, but with one read: R1 = -2 if no byte is
; waiting. Steps: 4 for a byte, 8 otherwise.
_nice_pollc
                MOVE    R1, @__nice.console
                AND[M]  R0, R1, 0x100
        ?!Z     AND     R1, R1, 0xFF
        ?!Z     RET
                AND[M]  R0, R1, 0x200
                MOVE    R1, -2
        ?!Z     MOVE    R1, -1
                RET

; nice_print: writes the string at R1, one character per word, up to its
; first 0 word, with one call through ___putc_vector per character. The
; pointer is kept in R7, which the routine behind the vector preserves,
; and which is saved and restored here. Steps: 6 + 6n for n characters
; with ___console_putc. Uses R1, and R7 across the calls.
_nice_print
                PUSH    R7
                MOVE    R7, R1
                MOVE[M] R1, @R7++
        ?Z      JMP     _nice_print.end
:               CALL    @___putc_vector
                MOVE[M] R1, @R7++
        ?!Z     JMPR    :-
_nice_print.end
                POP     R7
                RET

; nice_cycles, nice_instructions: R1:R2 = the counter, low word first.
; The read of the low word takes the snapshot that the read of the high
; word returns (SYSTEM §3). 3 steps.
_nice_cycles
                MOVE    R1, @__nice.cycle_lo
                MOVE    R2, @__nice.cycle_hi
                RET

_nice_instructions
                MOVE    R1, @__nice.instr_lo
                MOVE    R2, @__nice.instr_hi
                RET

; nice_screen_put: writes R3 to the screen at column R1 and row R2, the
; word 80 * R2 + R1. 80 * R2 = 64 * R2 + 16 * R2. 6 steps. Uses R2 and R4.
_nice_screen_put
                SHL     R4, R2, 6
                SHL     R2, R2, 4
                ADD     R2, R2, R4
                ADD     R2, R2, R1
                MOVE    @__nice.screen[R2], R3
                RET

; nice_screen_clear: writes a blank in white on black, 0x000FFF20, to the
; 2000 words of the screen, from the last down to the first. The colors
; are a board's monitor's, so that a cursor, which swaps the colors of its
; cell, shows on the blank; on one of color 0 it is black on black too
; (SYSTEM.md §1.4). 6002 steps. Uses R1.
_nice_screen_clear
                MOVE    R1, 2000
:               DEC[M]  R1, R1
                MOVE    @__nice.screen[R1], __nice.blank
        ?!Z     JMPR    :-
                RET
