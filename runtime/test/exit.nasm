; Run after start.nasm. main calls f, which calls exit with 7 from a frame
; of its own. _exit is the HALT after the call of main in the start-up
; code, at 8, so the processor halts with R1 = 7 and exit status 0, as
; after main returns, and with SP where f left it.
;
; start.nasm is words 0-8, and its call of main pushes 8 at 0xFFFFFEFF.
; main is 9-13: its call of f pushes 0xD at 0xFFFFFEFE. f is 14-21: it
; pushes R7 = 0 at 0xFFFFFEFD, and its call of exit pushes 0x15 at
; 0xFFFFFEFC. Steps: 5 in the start-up code, 2 in main, 4 in f, and the
; HALT = 12.

_main           ADD     @--R13, 2, R15
                MOVE    R15, f
                HALT                    ; not reached
f               MOVE    @--R13, R7
                MOVE    R1, 7
                ADD     @--R13, 2, R15
                MOVE    R15, _exit
                HALT                    ; not reached
