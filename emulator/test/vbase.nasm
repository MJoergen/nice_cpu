; VBASE != 0, the I flag, and INT inside an interrupt routine (ISA.md §7).
; The program halts with exit status 2.
                MOVE    R14, 0x00000001  ; VBASE = 1: the table is at 0x100
                INT     2
                HALT                    ; not reached
isr             MOVE    R1, R14         ; R1 = 0x81000001
                INT     3               ; halts: INT inside an interrupt routine
                .ORG    0x102
                .DAT    isr
