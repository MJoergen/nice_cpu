; A WAIT that no request can end (DEVICES.md §1.6): the timer counts, but
; with --no-timer-irq it raises no request, and no --irq or --nmi is to
; come. Run with
;   --no-timer-irq
; Step 0 starts the timer, and step 1 is the WAIT at word 3. Then the run
; stops with exit status 2, after 2 steps, with PC = 4, the address after
; the WAIT.
TIMER_PERIOD    .EQU    0xFFFFFF10
                MOVE    @TIMER_PERIOD, 5
                WAIT
                HALT
