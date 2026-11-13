; The console's receive interrupt (DEVICES.md §1.9, §4) from a file, where a
; read waits for its byte, with test/input.txt, "Hi". Run with
;   --input test/input.txt --irq 4:0x41 -d 0x200:8
; Each routine logs its vector at R12, and the loop logs each read.
; The steps are:
;    0    MOVE R12, 0x200
;    1    CONSOLE_IRQ = 0x142: the enable 0 to 1, and a byte waits, so the
;         console raises 0x42
;    2    CONSOLE_IRQ = 0x143: the enable was 1, no request
;    3    CONSOLE_IRQ = 0x43: the enable 0, the request stays pending
;    4    R1 = 0x43, read back; --irq raises 0x41 before this step
;    5    E = 1
;    6-8  IRQ 0x41, the timer's first though it came later; log, RTI
;    9    NOP, the first after RTI
;   10-12 IRQ 0x42, with the vector it was raised with; log, RTI
;   13    E = 0
;   14    CONSOLE_IRQ = 0x144: 0 to 1, a byte waits, so 0x44
;   15-23 the loop: E = 1, IRQ 0x44, log, RTI, E = 0, read 0x148 ("H"),
;         which raises 0x44 as "i" enters, log, test, jump back
;   24-32 again: 0x44, and 0x169 ("i"), which raises 0x44 as the input ends
;   33-41 again: 0x44, and 0x200, the end, which raises nothing; the jump
;         is skipped
;   42-43 E = 1 and a NOP: no request is pending
;   44    HALT
; So 45 steps, and the log at 0x200 is 41 42 44 148 44 169 44 200. At
; the end R1 = 0x200, R12 = 0x208, and R14 has E and Z of the last test.
CONSOLE         .EQU    0xFFFFFF00
CONSOLE_IRQ     .EQU    0xFFFFFF02
                MOVE    R12, 0x200
                MOVE    @CONSOLE_IRQ, 0x142
                MOVE    @CONSOLE_IRQ, 0x143
                MOVE    @CONSOLE_IRQ, 0x43
                MOVE    R1, @CONSOLE_IRQ
                OR      R14, R14, 0x40000000
                NOP
                AND     R14, R14, 0xBFFFFFFF
                MOVE    @CONSOLE_IRQ, 0x144
:               OR      R14, R14, 0x40000000
                AND     R14, R14, 0xBFFFFFFF
                MOVE    R1, @CONSOLE
                MOVE    @R12++, R1
                AND[M]  R0, R1, 0x100
        ?!Z     JMP     :-
                OR      R14, R14, 0x40000000
                NOP
                HALT
                .ORG    0x41
                .DAT    on_41, on_42, on_43, on_44
on_41           MOVE    @R12++, 0x41
                RTI
on_42           MOVE    @R12++, 0x42
                RTI
on_43           MOVE    @R12++, 0x43
                RTI
on_44           MOVE    @R12++, 0x44
                RTI
