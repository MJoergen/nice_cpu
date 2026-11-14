; TIME_SKIP (DEVICES.md §3): with --step-time, a write of N skips N wait
; steps after the step of the write, which count cycles, microseconds,
; the clock, and the timer, but no instructions. A write of 0 skips
; nothing, a request ends a skip early, and a request pending with E = 0
; drops it at once. Run with
;   --step-time --irq 140:0x42 --irq 146:0x42 -d 0x200:9 -d 0x210:2
; The steps are:
;    0    [0x200] = CYCLE_LO = 0
;    1    TIME_SKIP <- 100
;    2-101 100 wait steps
;  102    [0x201] = CYCLE_LO = 102
;  103    [0x202] = INSTR_LO = 3: steps 0, 1, and 102
;  104    [0x210] = TIME_LO = 104, one microsecond per step
;  105    [0x211] = CLOCK_USEC = 105, the clock counts the skip too
;  106    TIME_SKIP <- 0, no skip
;  107    [0x203] = CYCLE_LO = 107
;  108    MOVE @TIMER_VECTOR, 0x41
;  109    OR: E = 1, and VBASE 3, so the vectors are at 0x341
;  110    MOVE @TIMER_PERIOD, 20: COUNT is 19 at the end of the step
;  111    TIME_SKIP <- 1000: COUNT 18
;  112-129 18 wait steps: the timer raises 0x41 at the end of step 129,
;         which ends the skip, and the rest of it is dropped
;  130    IRQ 0x41
;  131-132 ADD R5, RTI
;  133    [0x204] = CYCLE_LO = 133
;  134    MOVE @TIMER_PERIOD, 0
;  135    TIME_SKIP <- 1000
;  136-139 four wait steps. --irq raises 0x42 before step 140
;  140    IRQ 0x42, which ends the skip
;  141-142 ADD R6, RTI
;  143    [0x205] = CYCLE_LO = 143
;  144    AND: E = 0
;  145    [0x206] = CYCLE_LO = 145. --irq raises 0x42 before step 146
;  146    TIME_SKIP <- 1000, with 0x42 pending: no wait step
;  147    [0x207] = CYCLE_LO = 147
;  148    OR: E = 1
;  149    IRQ 0x42
;  150-151 ADD R6, RTI
;  152    [0x208] = INSTR_LO = 27: steps 0-1, 102-111, 131-135, 141-148,
;         and 150-151
;  153    HALT
; At the end R5 = 1, R6 = 2, and R14 = 0x41000003: E, VBASE 3, and the
; 0x01000000 of reset. 154 steps.
; Also run with --max-steps 4 and no --step-time (skip_off in the
; Makefile), where the write is ignored: [0x201] = CYCLE_LO = 2, and
; [0x202] = INSTR_LO = 3; with --step-time --max-steps 50 (skip_limit),
; where the step limit cuts the first skip short after 50 steps, PC at
; the word after the write; and with --step-time --no-cycle-counter
; (skip_mem), where TIME_SKIP stays a device: 154 steps, as above.
TIMER_PERIOD    .EQU    0xFFFFFF10
TIMER_VECTOR    .EQU    0xFFFFFF12
CYCLE_LO        .EQU    0xFFFFFF40
INSTR_LO        .EQU    0xFFFFFF42
TIME_LO         .EQU    0xFFFFFF44
CLOCK_USEC      .EQU    0xFFFFFF46
TIME_SKIP       .EQU    0xFFFFFF5F
                MOVE    @0x200, @CYCLE_LO
                MOVE    @TIME_SKIP, 100
                MOVE    @0x201, @CYCLE_LO
                MOVE    @0x202, @INSTR_LO
                MOVE    @0x210, @TIME_LO
                MOVE    @0x211, @CLOCK_USEC
                MOVE    @TIME_SKIP, 0
                MOVE    @0x203, @CYCLE_LO
                MOVE    @TIMER_VECTOR, 0x41
                OR      R14, R14, 0x40000003
                MOVE    @TIMER_PERIOD, 20
                MOVE    @TIME_SKIP, 1000
                MOVE    @0x204, @CYCLE_LO
                MOVE    @TIMER_PERIOD, 0
                MOVE    @TIME_SKIP, 1000
                MOVE    @0x205, @CYCLE_LO
                AND     R14, R14, 0xBFFFFFFF
                MOVE    @0x206, @CYCLE_LO
                MOVE    @TIME_SKIP, 1000
                MOVE    @0x207, @CYCLE_LO
                OR      R14, R14, 0x40000000
                MOVE    @0x208, @INSTR_LO
                HALT
                .ORG    0x341
                .DAT    on_timer, on_irq
on_timer
                ADD     R5, R5, 1
                RTI
on_irq          ADD     R6, R6, 1
                RTI
