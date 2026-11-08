; The program of test/link.py's checks of nicedbg.py's watchpoints, which
; it sets at DATA: a write of DATA, two reads of it, and a HALT.
START           MOVE    @DATA, 5
READ            MOVE    R2, @DATA
ADD2            ADD     R3, @DATA, @DATA
DONE            HALT
DATA            .DAT    7
