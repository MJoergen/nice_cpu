; The text of the demo for a system that brings none of its own: the name
; in the title bar, the welcome, the keys in its bar, and the note on the
; clock under the counters. The Makefile joins this file after demo.nasm,
; or the file that TEXT names, which a board gives with its own text.
; Each string fits its row: NAME 13 characters, from column 1, before
; VERSION at column 15, and the others 76, from column 2.

NAME            .ASCII_L 'nice_cpu'
T1              .ASCII_L 'This is the demo of the NICE CPU. What you type on the keyboard, or send to'
T2              .ASCII_L 'the console, appears below the blue bar. The function keys start the demos.'
T3              .ASCII_L 'It runs in niceemu --window, and on a board that keeps it in its ROM. The'
T4              .ASCII_L 'assembler, the emulator, the C library, and the FPGA cores are at'
URL             .ASCII_L 'https://github.com/MJoergen/nice_cpu'
KEYS            .ASCII_L 'RETURN new line   DEL delete   cursor keys move   CTRL-L clear   F12 return'
P3              .ASCII_L 'On a board, the time is real, and the clock is that of the core.'
P4              .ASCII_L 'In niceemu, each step counts as a cycle and as a microsecond.'
