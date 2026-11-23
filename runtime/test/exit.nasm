; Run after start.nasm. main calls f, which calls exit with 7 from a frame
; of its own. _exit is the HALT after the call of main in the start-up
; code, at 5, so the processor halts with R1 = 7 and exit status 0, as
; after main returns, and with SP where f left it.
;
; start.nasm is words 0-7, its vectors 6-7, and its call of main pushes
; 5 at 0xFFFFFEFF. main is 8-9: its call of f pushes 9 at 0xFFFFFEFE.
; f is 10-14: it pushes R7 = 0 at 0xFFFFFEFD, and its call of exit pushes
; 0xE at 0xFFFFFEFC. Steps: 4 in the start-up code, 1 in main, 3 in f,
; and the HALT = 9.

_main           CALL    f
                HALT                    ; not reached
f               PUSH    R7
                MOVE    R1, 7
                CALL    _exit
                HALT                    ; not reached
