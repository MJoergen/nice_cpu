; Run after start.nasm with test/device.input, "ab", as the console input,
; and with -s. Calls each device routine of lib.nasm (ABI.md).
;
; The counters. The start-up code runs 5 instructions, 0-4, and main
; starts with a call, 5 and 6. The read of INSTR_LO in nice_instructions
; is instruction 7, so it returns 7. Then its MOVE and return (8, 9), two
; stores (10, 11), and the call (12, 13): the read of CYCLE_LO is
; instruction 14. With no interrupts, the emulator's cycle counter counts
; the same steps, so it returns 14 = 0xE. Both high words are 0. The four
; words go to results (see below).
;
; The console. nice_print prints "Hi" and nice_putc a newline, from
; 0x10A: only bits 7..0 count. nice_getc returns 'a' = 0x61, nice_pollc
; 'b' = 0x62, and then the input has ended: nice_pollc and nice_getc
; return -1. Those four results follow the counters in results. nice_putc
; echoes the two bytes, and a newline ends the output: "Hi", then "ab".
;
; The screen. nice_screen_clear writes 0x20 to all 2000 words, then
; nice_screen_put writes "O" and "K" to row 0, columns 0 and 1, "!" with a
; color, 0xC80FF021, to row 1, column 2, at 0xFFFF0000 + 80 + 2 =
; 0xFFFF0052, and "Z" to row 24, column 79, the last word, 0xFFFF07CF.
; -s prints the rows with their trailing blanks dropped, so rows 2-23 are
; just "|". The dumps show the words, with the blank at 0xFFFF07CE that
; the clear wrote.
;
; Code: start.nasm is words 0-8. main is 115 words, 9-0x7B: 57 instructions
; of 2 words and the return. text is 0x7C-0x7E, and results 0x7F-0x86.
; Steps, from the comments in lib.nasm: main itself runs 58 instructions,
; and the 16 calls 3 (nice_instructions) + 3 (nice_cycles) + 6 + 6 * 2
; (nice_print, through ___putc_vector) + 4 + 4 + 8 + 8 (nice_getc,
; nice_pollc, nice_pollc, nice_getc) + 4 * 3 (nice_putc, through the
; vector) + 6002 (nice_screen_clear) + 4 * 6 (nice_screen_put) = 6086
; steps. With the 5 of the start-up code and HALT, that is
; 5 + 58 + 6086 + 1 = 6150 steps. At the end R1 = 79 = 0x4F,
; R2 = 80 * 24 + 79 = 0x7CF, R3 = 0x5A, and R4 = 64 * 24 = 0x600, from the
; last nice_screen_put. R14 = 0x09000000: Z from the last DEC[M] of
; nice_screen_clear.

_main           ADD     @--R13, 2, R15
                MOVE    R15, _nice_instructions
                MOVE    @results, R1
                MOVE    @results+1, R2
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_cycles
                MOVE    @results+2, R1
                MOVE    @results+3, R2

                MOVE    R1, text
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_print
                MOVE    R1, 0x10A
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_putc
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_getc
                MOVE    @results+4, R1
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_pollc
                MOVE    @results+5, R1
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_pollc
                MOVE    @results+6, R1
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_getc
                MOVE    @results+7, R1
                MOVE    R1, @results+4
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_putc
                MOVE    R1, @results+5
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_putc
                MOVE    R1, 10
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_putc

                ADD     @--R13, 2, R15
                MOVE    R15, _nice_screen_clear
                MOVE    R1, 0
                MOVE    R2, 0
                MOVE    R3, 0x4F
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_screen_put
                MOVE    R1, 1
                MOVE    R2, 0
                MOVE    R3, 0x4B
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_screen_put
                MOVE    R1, 2
                MOVE    R2, 1
                MOVE    R3, 0xC80FF021
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_screen_put
                MOVE    R1, 79
                MOVE    R2, 24
                MOVE    R3, 0x5A
                ADD     @--R13, 2, R15
                MOVE    R15, _nice_screen_put
                MOVE    R15, @R13++

text            .ASCII_L 'Hi'
results         .BLK    8
