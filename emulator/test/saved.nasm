; The saved-state instructions (ISA.md §5.3) in a breakpoint and a
; single step, with -t --nmi 12:1 -d 0x200:3. Vector 2 is the breakpoint
; routine, vector 1 the NMI routine of the single step. The steps are:
;    0-2  set VBASE = 1, R13 = 0x200, and R1 = 5
;    3    INT 2, the breakpoint at 6, over the word at orig
;    4-11 the routine: RDSPC R3 = 7, R3 = 6, WRSPC R3, log 6, put the
;         word at orig back at 6, RDSSR R4 = 0x01000001, log it, RTI to 6
;   12    MOVE R2, R1 runs first, though the NMI was raised before it,
;         because it is right after RTI (§7.1): a single step
;   13-16 NMI, RDSPC R3 = 7, log 7, RTI to 7
;   17    R1 = 6
;   18    RDSPC outside an interrupt routine halts, with exit status 2
; The log at 0x200 is 6, 0x01000001, 7. R2 = 5.
        MOVE    R14, 1          ; words 0,1: VBASE = 1: the table is at 0x100
        MOVE    R13, 0x200      ; words 2,3
        MOVE    R1, 5           ; words 4,5
        INT     2               ; word 6: the breakpoint
        ADD     R1, R1, 1       ; words 7,8
        RDSPC   R5              ; word 9: halts
orig    MOVE    R2, R1          ; word 10: the word the breakpoint replaced
        .ORG    0x10
brk     RDSPC   R3              ; word 0x10
        SUB     R3, R3, 1       ; words 0x11,0x12
        WRSPC   R3              ; word 0x13
        MOVE    @R13++, R3      ; word 0x14
        MOVE    @R3, @orig      ; words 0x15,0x16
        RDSSR   R4              ; word 0x17
        MOVE    @R13++, R4      ; word 0x18
        RTI                     ; word 0x19
        .ORG    0x20
nmi     RDSPC   R3              ; word 0x20
        MOVE    @R13++, R3      ; word 0x21
        RTI                     ; word 0x22
        .ORG    0x101
        .DAT    nmi
        .DAT    brk
