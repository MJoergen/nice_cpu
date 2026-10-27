; Reserved control words (ISA.md §5.3). With a false condition they are
; skipped like any instruction. Executed, they halt the processor.
;
; The four ?!1 words are skipped: an unknown command, HALT with a bit of
; 20..8 set, INT with a bit of 20..8 set, and RTI with a vector. Then
; R1 = 1, and the word 0x0FE00000 (command 31, the wasm trap handler of
; WASM.md) halts with exit status 2. Steps: 4 + 1 + 1 = 6. PC = 7 after the
; halt, and R1 = 1.
                .DAT    0x8C600000
                .DAT    0x8C000100
                .DAT    0x8C400105
                .DAT    0x8C200001
                MOVE    R1, 1
                .DAT    0x0FE00000
                MOVE    R1, 2
