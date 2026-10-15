; An NMI raised before the first instruction (ISA.md §8.1), run with
;   -t --nmi 0:3
; After reset VBASE = 0, so word 3 is vector table entry 3. The NMI is taken
; before word 0 runs, and RTI returns to word 0.
        MOVE    R1, 1           ; words 0,1
        HALT                    ; word 2
        .DAT    nmi             ; word 3: vector 3
nmi     MOVE    R2, 0xB3        ; words 4,5
        RTI                     ; word 6
