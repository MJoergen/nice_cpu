; WAIT (ISA.md §7.5, SYSTEM.md §3): the timer, --irq, and --nmi end a
; wait, wait steps count cycles and microseconds but no instructions, and
; a request pending with E = 0 ends a wait at once. Run with
;   --step-time --irq 25:0x42 --nmi 40:0x43 -d 0x200:7
; The steps are:
;    0    MOVE @TIMER_VECTOR, 0x41
;    1    OR: E = 1
;    2    MOVE @TIMER_PERIOD, 10: COUNT is 9 at the end of the step
;    3    WAIT: COUNT 8
;    4-11 eight wait steps: the timer raises 0x41 at the end of step 11
;   12    the wait ends, IRQ 0x41, which saves PC = the MOVE after WAIT
;   13-14 ADD R5, RTI
;   15    [0x200] = CYCLE_LO = 15, the steps before it
;   16    [0x201] = INSTR_LO = 7: steps 0-3 and 13-15
;   17    MOVE @TIMER_PERIOD, 0
;   18    AND: E = 0
;   19    WAIT
;   20-24 five wait steps. --irq raises 0x42 before step 25
;   25    the wait ends, and as E = 0 the next MOVE runs in the same step:
;         [0x202] = CYCLE_LO = 25
;   26    WAIT, with 0x42 pending
;   27    no wait step: [0x203] = CYCLE_LO = 27
;   28    OR: E = 1
;   29    IRQ 0x42
;   30-31 ADD R6, RTI
;   32    WAIT
;   33-39 seven wait steps. --nmi raises 0x43 before step 40
;   40    the wait ends, NMI 0x43
;   41-42 ADD R7, RTI
;   43    [0x204] = CYCLE_LO = 43
;   44    [0x205] = INSTR_LO = 21: steps 0-3, 13-19, 25-28, 30-32, and 41-43
;   45    [0x206] = TIME_LO = 45, one microsecond per step with --step-time
;   46    HALT
; At the end R5 = R6 = R7 = 1, and R14 = 0x41000000: E, and the 0x01000000
; of reset, as each RTI restores the SR before its entry. 47 steps.
; Also run with --step-time --symbols test/wait.sym and --max-steps 11,
; then 12 (wait_in and wait_end in the Makefile). After 11 steps the
; processor is in the first wait, so the report says "At wait1", the WAIT
; at word 8, with R15 = 9, the word after it. After 12 the timer has
; raised its request, which ends the wait at the next step, so the
; processor waits no more (DEBUG.md §6, bit 6): "At wait1+0x1".
TIMER_PERIOD    .EQU    0xFFFFFF10
TIMER_VECTOR    .EQU    0xFFFFFF12
CYCLE_LO        .EQU    0xFFFFFF40
INSTR_LO        .EQU    0xFFFFFF42
TIME_LO         .EQU    0xFFFFFF44
                MOVE    @TIMER_VECTOR, 0x41
                OR      R14, R14, 0x40000000
                MOVE    @TIMER_PERIOD, 10
wait1           WAIT
                MOVE    @0x200, @CYCLE_LO
                MOVE    @0x201, @INSTR_LO
                MOVE    @TIMER_PERIOD, 0
                AND     R14, R14, 0xBFFFFFFF
wait2           WAIT
                MOVE    @0x202, @CYCLE_LO
wait3           WAIT
                MOVE    @0x203, @CYCLE_LO
                OR      R14, R14, 0x40000000
wait4           WAIT
                MOVE    @0x204, @CYCLE_LO
                MOVE    @0x205, @INSTR_LO
                MOVE    @0x206, @TIME_LO
                HALT
                .ORG    0x41
                .DAT    on_timer, on_irq, on_nmi
on_timer
                ADD     R5, R5, 1
                RTI
on_irq          ADD     R6, R6, 1
                RTI
on_nmi          ADD     R7, R7, 1
                RTI
