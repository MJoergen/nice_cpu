; TIME_SKIP (DEVICES.md §3) and the requests that skip.nasm does not
; raise: an NMI ends a skip, and the console's request drops one, while
; a byte that waits without the console's enable does not. TIME_SKIP
; reads 0, and the FPU's word 0xFFFFFF8F (§11.1) takes no write. Run with
;   --step-time --nmi 20:0x80 --input test/input.txt -d 0x200:7
; The steps are:
;    0    [0x200] = CYCLE_LO = 0
;    1    TIME_SKIP <- 1000
;    2-19 18 wait steps. --nmi raises 0x80 before step 20
;   20    NMI 0x80, which ends the skip
;   21-22 ADD R5, RTI
;   23    [0x201] = CYCLE_LO = 23
;   24    TIME_SKIP <- 100. "H" waits, but the console's request is not
;         enabled, so nothing ends the skip
;   25-124 100 wait steps
;  125    [0x202] = CYCLE_LO = 125
;  126    CONSOLE_IRQ = 0x142: the enable 0 to 1, and a byte waits, so the
;         console raises 0x42, pending with E = 0
;  127    TIME_SKIP <- 1000, with 0x42 pending: no wait step
;  128    [0x203] = CYCLE_LO = 128
;  129    [0x204] = -1
;  130    [0x204] = TIME_SKIP = 0
;  131    0xFFFFFF8F <- 5, which the FPU ignores
;  132    [0x205] = 0xFFFFFF8F = 0
;  133    [0x206] = INSTR_LO = 14: steps 0-1 and 21-24, and 125-132
;  134    HALT
; At the end R5 = 1. 135 steps.
CONSOLE_IRQ     .EQU    0xFFFFFF02
CYCLE_LO        .EQU    0xFFFFFF40
INSTR_LO        .EQU    0xFFFFFF42
TIME_SKIP       .EQU    0xFFFFFF5F
FPU_7           .EQU    0xFFFFFF8F
                MOVE    @0x200, @CYCLE_LO
                MOVE    @TIME_SKIP, 1000
                MOVE    @0x201, @CYCLE_LO
                MOVE    @TIME_SKIP, 100
                MOVE    @0x202, @CYCLE_LO
                MOVE    @CONSOLE_IRQ, 0x142
                MOVE    @TIME_SKIP, 1000
                MOVE    @0x203, @CYCLE_LO
                MOVE    @0x204, 0xFFFFFFFF
                MOVE    @0x204, @TIME_SKIP
                MOVE    @FPU_7, 5
                MOVE    @0x205, @FPU_7
                MOVE    @0x206, @INSTR_LO
                HALT
                .ORG    0x80
                .DAT    on_nmi
on_nmi          ADD     R5, R5, 1
                RTI
