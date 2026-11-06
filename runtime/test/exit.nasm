; Run after start.nasm. main calls f, which calls exit with 7 from a frame
; of its own. _exit is the HALT after the call of main in the start-up
; code, at 8, so the processor halts with R1 = 7 and exit status 0, as
; after main returns, and with SP where f left it.
;
; start.nasm is words 0-10, its vectors 9-10, and its call of main pushes
; 8 at 0xFFFFFEFF. main is 11-15: its call of f pushes 0xF at 0xFFFFFEFE.
; f is 16-23: it pushes R7 = 0 at 0xFFFFFEFD, and its call of exit pushes
; 0x17 at 0xFFFFFEFC. Steps: 5 in the start-up code, 2 in main, 4 in f,
; and the HALT = 12.

_main           CALL    f
                HALT                    ; not reached
f               PUSH    R7
                MOVE    R1, 7
                CALL    _exit
                HALT                    ; not reached
