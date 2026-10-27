; An instruction that overwrites its own constant word (ISA.md §8.2). ADD
; @k, @k, 1 at word 2 has three constant words: k at 3 (dest), k at 4
; (s0), and 1 at 5 (s1), and k = 5, its own s1 constant. Each run reads
; mem[5] as s0 and takes word 5 as s1, which are the same word, and writes
; their sum back to it. The next run must see the new word:
;
;   run 1: s0 = 1, s1 = 1, mem[5] = 2
;   run 2: s0 = 2, s1 = 2, mem[5] = 4
;   run 3: s0 = 4, s1 = 4, mem[5] = 8
;
; A processor that kept the old constant word would write 2, 3, and 4.
; R1 = mem[5] = 8. Steps: 1 + 3 * 3 + 2 = 12. R7 = 0 with Z set, R14 =
; 0x09000000. HALT is word 11, so PC = 0xC.
                MOVE    R7, 3           ; words 0,1
loop            ADD     @5, @5, 1       ; words 2-5
                DEC[M]  R7, R7          ; word 6
        ?!Z     MOVE    R15, loop       ; words 7,8
                MOVE    R1, @5          ; words 9,10
                HALT                    ; word 11
