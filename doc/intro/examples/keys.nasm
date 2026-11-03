; Echo the keys typed into the window on the screen, with a blinking
; cursor. Backspace deletes, and Enter ends the program. The cursor swaps
; the colors of its cell, so the program keeps a white space under it; on
; a cell never written, black on black, it would not show. Build niceemu
; with make window, and run it with
;     niceemu --window keys.bin
CONSOLE         .EQU    0xFFFFFF00
SCREEN          .EQU    0xFFFF0000      ; row 0, column 0
LINE            .EQU    0xFFFF00A0      ; row 2, column 0: SCREEN + 2*80
CUR_STATE       .EQU    0xFFFFFF80
CUR_COL         .EQU    0xFFFFFF81
CUR_ROW         .EQU    0xFFFFFF82
TITLE_COLOR     .EQU    0x00FFF000      ; yellow (0xFF0) on blue (0x00F)
TEXT_COLOR      .EQU    0x000FFF00      ; white (0xFFF) on black (0x000)
SPACE           .EQU    TEXT_COLOR+0x20  ; a space, white on black

; Write the title on row 0. Each screen word is a character and its colors.
                MOVE    R1, TITLE
                MOVE    R3, SCREEN
NEXT            MOVE[M] R2, @R1++       ; next character, and set Z if it is 0
        ?Z      JMP     START
                ADD     @R3++, R2, TITLE_COLOR  ; add the colors, and write
                JMP     NEXT

START           MOVE    R3, LINE        ; R3: the address of the next key
                MOVE    R4, 0           ; R4: its column
                MOVE    @CUR_ROW, 2
                MOVE    @CUR_STATE, 0x60  ; show the cursor, blinking
CURSOR          MOVE    @CUR_COL, R4    ; move the cursor to the next key,
                MOVE    @R3, SPACE      ; with a space under it, so it shows
KEY             MOVE[M] R2, @CONSOLE    ; read: 0 if no byte waits, else the
        ?Z      JMP     KEY             ; byte with bit 8 set; none: again
                CMP     R2, 0x200       ; the end of the input, without --window
        ?Z      JMP     DONE
                AND     R2, R2, 0xFF    ; the byte alone
                CMP     R2, 13          ; Enter gives CR
        ?Z      JMP     DONE
                CMP     R2, 0x7F        ; Backspace gives DEL
        ?Z      JMP     BACK
                CMP     R2, 0x20        ; ignore the other control characters
        ?C      JMP     KEY
                CMP     R4, 79          ; the line is full at 79 characters,
        ?Z      JMP     KEY             ; so the cursor stays on the screen
                ADD     @R3++, R2, TEXT_COLOR
                ADD     R4, R4, 1
                JMP     CURSOR

BACK            TST     R4              ; at column 0,
        ?Z      JMP     KEY             ; there is nothing to delete
                MOVE    @R3, 0          ; clear the space under the cursor
                MOVE    @--R3, 0        ; and the last character
                DEC     R4, R4
                JMP     CURSOR

DONE            MOVE    @CUR_STATE, 0   ; hide the cursor
                HALT

TITLE           .ASCII_L ' Type, and press Enter to end '
