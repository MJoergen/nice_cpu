; R15 in the modes that r15.nasm and cputest leave out (ISA.md §4.1-§4.3):
; --R15 and @--R15 as sources, and @--R15, @R15++, and R15-- as
; destinations. Each is a jump. W1, W2, and W3 are the instruction words of
; MOVE R2, R15, MOVE R4, R15, and MOVE R6, R15: dest field 000 0010, 000
; 0100, or 000 0110 at bit 14, and s0 field 000 1111 at bit 7. A jump back
; by one word runs one of them.
;
;   word 0   ADD R1, --R15, W1    R15 reads 2 and becomes 1: s0 = 1,
;                                 R1 = 1 + 0x8780 = 0x8781. Jumps to 1.
;   word 1   (W1) MOVE R2, R15    the constant runs: R2 = 2
;   word 2   ADD R3, @--R15, W2   R15 = 4, then 3: s0 = mem[3] = W2,
;                                 R3 = 2 * 0x10780 = 0x20F00. Jumps to 3.
;   word 3   (W2) MOVE R4, R15    R4 = 4
;   word 4,5 MOVE R9, W3          R9 = 0x18780
;   word 6   MOVE @--R15, R9      R15 = 7, then 6: mem[6] = W3, which
;                                 overwrites this instruction. Jumps to 6.
;   word 6   (W3) MOVE R6, R15    the new word runs: R6 = 7
;   word 7,8 MOVE R10, 0x1234
;   word 9   MOVE @R15++, R10     R15 = 10: mem[10] = 0x1234, then R15 = 11,
;                                 which jumps over the word just written
;   word 10  HALT                 overwritten, and never runs
;   word 11  MOVE R7, @10         R7 = 0x1234
;   word 13  MOVE R15--, done+1   R15 = 0x21, then 0x20: jumps to done
;   word 15  HALT                 never runs
;   0x20     MOVE R8, R15         R8 = 0x21
;   0x21     HALT
;
; Steps: 13. PC = 0x22 after the HALT. The flags never change: R14 =
; 0x01000000. The dumps show W3 at 6 and 0x1234 at 10.
W1      .EQU    0x00008780      ; MOVE R2, R15
W2      .EQU    0x00010780      ; MOVE R4, R15
W3      .EQU    0x00018780      ; MOVE R6, R15
        ADD     R1, --R15, W1   ; words 0,1
        ADD     R3, @--R15, W2  ; words 2,3
        MOVE    R9, W3          ; words 4,5
        MOVE    @--R15, R9      ; word 6
        MOVE    R10, 0x1234     ; words 7,8
        MOVE    @R15++, R10     ; word 9
        HALT                    ; word 10
        MOVE    R7, @10         ; words 11,12
        MOVE    R15--, done+1   ; words 13,14
        HALT                    ; word 15
        .ORG    0x20
done    MOVE    R8, R15         ; word 0x20
        HALT                    ; word 0x21
