; The demos, which a board can keep in its ROM, and which run in niceemu
; --window too. They show that the core runs, and that the keyboard and the
; screen work, on a board with no computer on its debug UART. Their test,
; in demo/Makefile, runs them in niceemu and compares the screens with
; demo/test.expected.
;
; One demo runs at a time, and a function key switches to another: the
; menu in the second row of the screen lists them. A switch starts the demo
; afresh. F3 shows the bytes of each key, in hex and as characters, F5 the
; 256 characters of the font and ramps of colors, F7 the performance
; counters and those of a prime sieve, F9 is a game, the comet, and F11 is
; the board: it tests the RAM, the math unit, the timer's interrupts, and
; the counters, and shows and sets the network station's addresses.
; At the start the typewriter, F1, runs. Its top rows say what the core is
; and how to go further, and the rows below them take what is typed, from
; the keyboard or the UART: a character goes at the cursor, RETURN starts a
; new line, DEL (or backspace) deletes the character before the cursor, TAB
; goes to the next column that is a multiple of 8, the cursor keys move the
; cursor, and CTRL-L clears the rows.
;
; The keys come through POLL, which every demo calls. It turns the escape
; sequences of the cursor keys and of the function keys, as xterm sends
; them, into codes of their own, and on a function key with a demo it
; starts that demo. A demo starts with SP at its top, so the switch leaves
; nothing on the stack. A demo that wants the bytes themselves, as F3 does,
; puts the address of a routine in ECHO, which POLL calls with each byte.
;
; When the cursor goes past the last row, the typewriter scrolls its rows
; up by one, by copying each row to the one above it. The top rows do not
; move. The display offset (0xFFFFFF85) is not used, for three reasons. It
; would scroll the top rows away too. It wraps at the end of the screen's
; memory, whose size differs between the boards. And in niceemu it is plain
; memory, so the program would not scroll there.
;
; The demo is a program under a monitor (runtime/ABI.md, "Programs under a
; monitor"), assembled at 0x8000. A monitor calls it there with E = 0 and
; SP on the monitor's stack; in niceemu, the runtime's stand-in for a
; monitor, runtime/test/monitor_console.nasm, does. Each demo starts with
; SP as it was at the entry, and F12 clears the screen and returns from
; there with the status 0. The variables are at VARS, past the image, and
; F11 tests the RAM from RAM_LO, past them, up to 0xDFFF, below a
; monitor's stack and variables, which on NiceMonMEGA65 start at
; 0xFFFFF000. The vector table of the timer's interrupt is the page 0x8000
; of the image. So the demo writes no memory but these words, the screen,
; the cursor's registers, the math unit, the timer, the network station's
; addresses when F11 sets them, and the stack. The words are the same in
; niceemu.
;
; On the board, a read of the console returns 0 until a byte arrives, so the
; program polls it in a loop. A read returns 0x200 when the input has ended,
; and then the program halts. In niceemu that happens after the last byte
; of the input file. On the board it happens after a break on the line, or
; when an Ethernet host half-closes its connection, after which the console
; takes no byte, from the line or the keyboard, until the core is started
; again. So the halt is on purpose: no key could come, and the tools and
; the tests end on the halt.
;
; It is assembled with two files joined after it (demo/Makefile): the
; text of the system it runs on, text.nasm or the system's own, which
; defines NAME, T1 to T4, URL, KEYS, P3, and P4, and build/version.nasm,
; which defines VERSION, the version string of the title bar.

SP              .EQU    R13

CONSOLE         .EQU    0xFFFFFF00      ; a read: bit 8 and the byte, or bit 9 at the end
SCREEN          .EQU    0xFFFF0000      ; 80 x 25 words, the character in bits 7..0
SCR_CTL         .EQU    0xFFFFFF80      ; bit 6 shows the cursor, bit 5 blinks it
SCR_X           .EQU    0xFFFFFF81      ; the cursor's column
SCR_Y           .EQU    0xFFFFFF82      ; the cursor's row

; The math unit, with A and B of 32 bits, and C and D of 64 bits
M_A             .EQU    0xFFFFFF20
M_B             .EQU    0xFFFFFF21
M_UMUL          .EQU    0xFFFFFF24      ; bits 31..0 of A * B
M_UDIVQ         .EQU    0xFFFFFF28      ; A / B, and the remainder
M_UDIVR         .EQU    0xFFFFFF29
M_SMUL          .EQU    0xFFFFFF22      ; A * B, signed, and its bits 63..32
M_SMULH         .EQU    0xFFFFFF23
M_UMULH         .EQU    0xFFFFFF25      ; bits 63..32 of A * B
M_SDIVQ         .EQU    0xFFFFFF26      ; A / B, signed, and the remainder
M_SDIVR         .EQU    0xFFFFFF27
M_CLO           .EQU    0xFFFFFF30
M_CHI           .EQU    0xFFFFFF31
M_DLO           .EQU    0xFFFFFF32
M_DHI           .EQU    0xFFFFFF33
M_QLO           .EQU    0xFFFFFF38      ; C / D, and the remainder
M_QHI           .EQU    0xFFFFFF39
M_RLO           .EQU    0xFFFFFF3A

; The performance counters, 64 bits each. A read of the low word takes the
; snapshot that the high word returns.
P_CYC           .EQU    0xFFFFFF40
P_CYCH          .EQU    0xFFFFFF41
P_INS           .EQU    0xFFFFFF42
P_INSH          .EQU    0xFFFFFF43
P_US            .EQU    0xFFFFFF44
P_USH           .EQU    0xFFFFFF45

; The variables, from VARS, after the image (see the entry), and the RAM
; that F11 tests, from RAM_LO up to the stack. The stack starts below
; the monitor's variables at 0xFFFFF000, which on the Nexys4DDR are RAM
; word 0xF000, as its 64K words repeat, and 0x1F000 on the MEGA65, so
; RAM_LO + RAM_N stays below 0xE000.
VARS            .EQU    0xA000
SIEVE           .EQU    VARS            ; the sieve of F7, a word for each number
SIEVE_N         .EQU    2048            ; its numbers, 0 to SIEVE_N - 1
D_SP            .EQU    VARS+2048       ; SP at the entry, the top of each demo's stack
V_RUNS          .EQU    VARS+2049       ; the runs of the sieve
V_CYC           .EQU    VARS+2050       ; the cycles of the last run
V_INS           .EQU    VARS+2051       ; its instructions
V_US            .EQU    VARS+2052       ; and its microseconds
V_TLO           .EQU    VARS+2053       ; the microseconds since reset
V_THI           .EQU    VARS+2054
V_CLO           .EQU    VARS+2055       ; the cycles since reset
V_CHI           .EQU    VARS+2056
V_ILO           .EQU    VARS+2057       ; the instructions since reset
V_IHI           .EQU    VARS+2058

; The variables of F9, in the same words, as only one demo runs at a time
BODY            .EQU    VARS            ; the ring of the comet's cells, head last
BODY_M          .EQU    2047            ; the mask of an index of the ring
G_HEAD          .EQU    VARS+2049       ; the index of the head in the ring
G_LEN           .EQU    VARS+2050       ; the cells of the comet
G_GROW          .EQU    VARS+2051       ; the cells it still grows by
G_DIR           .EQU    VARS+2052       ; its step, -80, 80, 1, or -1, or 0 at the start
G_POS           .EQU    VARS+2053       ; the address of the head
G_SCORE         .EQU    VARS+2054
G_BEST          .EQU    VARS+2055
G_SEED          .EQU    VARS+2056       ; the state of RANDOM
G_NEXT          .EQU    VARS+2057       ; the microsecond counter at the next tick
G_TICK          .EQU    VARS+2058       ; the microseconds from a tick to the next
G_OVER          .EQU    VARS+2059       ; 1 after the game has ended

; The variables of F11, in the same words, and the RAM that it tests
S_TICKS         .EQU    VARS+2049       ; the interrupts of the timer
B_MODE          .EQU    VARS+2050       ; 0, or 1 or 2 while an IP or MAC address is typed
VARS_N          .EQU    2064            ; the words from VARS
RAM_LO          .EQU    0xB000          ; the RAM tested
RAM_N           .EQU    12288           ; up to 0xDFFF

; The timer, and the vector of its interrupt, whose entry in the table at
; VBASE * 256 is at 0x8041, in the image (see the entry)
TM_PER          .EQU    0xFFFFFF10      ; the period, in cycles, or 0 to stop
TM_VEC          .EQU    0xFFFFFF12
VBASE           .EQU    0x80
VECTOR          .EQU    0x41

; The network station (doc/DEVICES.md §6)
E_IP            .EQU    0xFFFFFFB0      ; the IP address, the first byte in bits 31..24
E_MACH          .EQU    0xFFFFFFB1      ; MAC bytes 0 and 1, in bits 15..0
E_MACL          .EQU    0xFFFFFFB2      ; MAC bytes 2 to 5
E_GOOD          .EQU    0xFFFFFFB3      ; the good frames received
E_BAD           .EQU    0xFFFFFFB4      ; the bad frames received, and the dropped ones
E_SENT          .EQU    0xFFFFFFB5      ; the frames sent
E_STAT          .EQU    0xFFFFFFB6      ; bit 31 while a host is connected, the port in 15..0

; The colors: the background in bits 31..20, the foreground in bits 19..8
BAR             .EQU    0x00AFFF00      ; white on blue
TEXT            .EQU    0x000CCC00      ; light gray on black
LINK            .EQU    0x000FF000      ; yellow on black
MENU_ON         .EQU    0xFFF00000      ; black on white, the running demo in the menu
TYPED           .EQU    0x000FFF00      ; white on black
TAIL            .EQU    0x0000F000      ; green on black
RED             .EQU    0x000F0000      ; red on black

TOP             .EQU    10              ; the first row of the typewriter
LAST            .EQU    24              ; and its last
SCR_TOP         .EQU    SCREEN+800      ; the address of row TOP, 80 * TOP words in
KTOP            .EQU    8               ; the first row of the keys of F3
SCR_KEY         .EQU    SCREEN+640      ; its address, 80 * KTOP words in
K_MAX           .EQU    12              ; the bytes of a key that F3 shows

; The registers that hold the state of the demos
COL             .EQU    R10             ; the typewriter's column, 0 to 79, or the
                ; bytes shown of the key, for F3
ROW             .EQU    R11             ; the row, TOP or KTOP to LAST
CR              .EQU    R8              ; 1 when the byte before was a CR
ECHO            .EQU    R12             ; a routine that POLL calls with each byte, or 0

; The codes that POLL gives for the cursor keys, above those of the bytes
KEY_UP          .EQU    0x101
KEY_DN          .EQU    0x102
KEY_RT          .EQU    0x103
KEY_LT          .EQU    0x104

; The longest wait for the next byte of an escape sequence, in microseconds.
; A sequence from the keyboard or a terminal comes at once, and a person
; cannot type a byte after ESC that fast.
T_ESC           .EQU    10000

; The variables, which are not in the image, and the RAM that F11 tests.
; The assembler fails if the image reaches them.
                .ORG    VARS
                .RES    VARS_N
                .ORG    RAM_LO
                .RES    RAM_N

; The entry, at 0x8000, where the monitor calls the demo: the stack it
; is called on is that of every demo, and the typewriter starts
                .ORG    0x8000
                MOVE    @D_SP, SP
                JMP     TYPEW

; The entry of the timer's interrupt in the vector table, at VBASE * 256 +
; VECTOR
                .ORG    0x8041
                .DAT    TICK

; The typewriter: the welcome, and the rows below it
TYPEW           MOVE    SP, @D_SP
                MOVE    R6, TYPEW
                CALL    FRAME
                MOVE    R2, SCREEN+720
                MOVE    R3, BAR+0x20
                MOVE    R4, 80
                CALL    FILL
                MOVE    R5, WELCOME
                CALL    PRINTS
                MOVE    COL, 0
                MOVE    ROW, TOP
                MOVE    CR, 0
                MOVE    @SCR_CTL, 0x60  ; a blinking cursor, and no display offset
KEY             MOVE    @SCR_X, COL     ; the cursor where the next character goes
                MOVE    @SCR_Y, ROW
:               CALL    POLL
                TST     R1
        ?Z      JMP     :-
                MOVE    R7, CR          ; whether this key follows a CR
                MOVE    CR, 0
                CMP     R1, 0x100
        ?!C     JMP     CURSOR          ; a cursor key
                CMP     R1, 0x20
        ?C      JMP     CONTROL         ; below 0x20
                CMP     R1, 0x7F
        ?C      JMP     PUT             ; printable ASCII
        ?Z      JMP     BACK            ; DEL
                CMP     R1, 0xA0
        ?C      JMP     KEY             ; 0x80 to 0x9F have no character
                ; 0xA0 and above fall through to PUT

; A character at the cursor, which moves on, to the next line after the last
; column
PUT             CALL    CELL
                OR      @R2, R1, TYPED
                ADD     COL, COL, 1
                CMP     COL, 80
        ?Z      JMP     NEWLINE
                JMP     KEY

CONTROL         CMP     R1, 0x0D
        ?Z      MOVE    CR, 1
        ?Z      JMP     NEWLINE
                CMP     R1, 0x0A        ; LF, but only if the byte before was no CR:
        ?Z      TST     R7              ; Z after 0x0A stays only if R7, the CR, is 0
        ?Z      JMP     NEWLINE
                CMP     R1, 0x08        ; backspace
        ?Z      JMP     BACK
                CMP     R1, 0x09
        ?Z      JMP     TAB
                CMP     R1, 0x0C        ; CTRL-L
        ?Z      JMP     CLEAR
                JMP     KEY             ; a code that does nothing

; The cursor keys move the cursor within the typewriter's rows
CURSOR          CMP     R1, KEY_UP
        ?Z      JMP     UP
                CMP     R1, KEY_DN
        ?Z      JMP     DOWN
                CMP     R1, KEY_RT
        ?Z      JMP     RIGHT
                TST     COL             ; left
        ?!Z     SUB     COL, COL, 1
                JMP     KEY
UP              CMP     ROW, TOP
        ?!Z     SUB     ROW, ROW, 1
                JMP     KEY
DOWN            CMP     ROW, LAST
        ?!Z     ADD     ROW, ROW, 1
                JMP     KEY
RIGHT           CMP     COL, 79
        ?!Z     ADD     COL, COL, 1
                JMP     KEY

; The first column of the next row, and a scroll after the last
NEWLINE         MOVE    COL, 0
                CMP     ROW, LAST
        ?!Z     ADD     ROW, ROW, 1
        ?!Z     JMP     KEY
                MOVE    R2, SCR_TOP
                MOVE    R4, 1120        ; the rows TOP+1 to LAST, 14 of 80 words
                CALL    SCROLL
                JMP     KEY

; The character before the cursor deleted, in the cursor's row
BACK            TST     COL
        ?Z      JMP     KEY
                SUB     COL, COL, 1
                CALL    CELL
                MOVE    @R2, TYPED+0x20
                JMP     KEY

; The next column that is a multiple of 8, or the next line after the last
TAB             OR      COL, COL, 7
                ADD     COL, COL, 1
                CMP     COL, 80
        ?!C     JMP     NEWLINE
                JMP     KEY

; The typewriter's rows cleared, and the cursor at the top
CLEAR           MOVE    R2, SCR_TOP
                MOVE    R3, TYPED+0x20
                MOVE    R4, 1200        ; the rows TOP to LAST, 15 of 80 words
                CALL    FILL
                MOVE    COL, 0
                MOVE    ROW, TOP
                JMP     KEY

; CELL sets R2 to the address of the cursor's word, SCREEN + 80 * ROW + COL.
; It changes R3.
CELL            SHL     R2, ROW, 4
                SHL     R3, ROW, 6
                ADD     R2, R2, R3
                ADD     R2, R2, COL
                ADD     R2, R2, SCREEN
                RET

; FILL writes R3 to the R4 words from R2, and leaves R2 after them. R4 is
; at least 1. It changes R4.
FILL            MOVE    @R2++, R3
                SUB[M]  R4, R4, 1
        ?!Z     JMP     FILL
                RET

; PRINT writes the string at R1, which ends with a 0 word, to the screen
; from R2, each character with the color R3. It changes R1, R2, and R4.
PRINT           MOVE[M] R4, @R1++
        ?Z      RET
                OR      @R2++, R4, R3
                JMP     PRINT

; The key codes: each key on a row of its own, with its bytes in hex and as
; characters. ECHO shows the bytes as POLL reads them, and when POLL
; returns, the key has ended. A key that gives 0, such as a sequence that is
; no key, still ends. An ESC shows with the bytes that come within T_ESC
; after it, as POLL waits for them, so an ESC alone has a row of its own.
KCODES          MOVE    SP, @D_SP
                MOVE    R6, KCODES
                CALL    FRAME
                MOVE    R2, SCREEN+560  ; the bar of row 7
                MOVE    R3, BAR+0x20
                MOVE    R4, 80
                CALL    FILL
                MOVE    R5, K_TEXTS
                CALL    PRINTS
                MOVE    COL, 0
                MOVE    ROW, KTOP
                MOVE    ECHO, SHOWB
:               CALL    POLL
                TST     COL
        ?Z      JMP     :-              ; no byte yet
                MOVE    COL, 0          ; the key has ended: the next row
                CMP     ROW, LAST
        ?!Z     ADD     ROW, ROW, 1
        ?!Z     JMP     :-
                MOVE    R2, SCR_KEY     ; or a scroll after the last
                MOVE    R4, 1280        ; the rows KTOP+1 to LAST, 16 of 80 words
                CALL    SCROLL
                JMP     :-

; SHOWB, the ECHO of F3, shows the byte R1 in the row ROW, as the byte COL of
; its key: in hex from column 2, and from column 42 as a character, or as ^
; and a character for a control code. 0x80 to 0x9F have no character, and
; the bytes after the first K_MAX of a key are not shown. It changes nothing
; but COL, which it counts up.
SHOWB           PUSH    R2
                PUSH    R3
                PUSH    R4
                CMP     COL, K_MAX
        ?!C     JMP     SHOWN
                SHL     R2, ROW, 4      ; R2 is SCREEN + 80 * ROW + 3 * COL
                SHL     R3, ROW, 6
                ADD     R2, R2, R3
                SHL     R4, COL, 1
                ADD     R4, R4, COL
                ADD     R2, R2, R4
                ADD     R2, R2, SCREEN
                SHR     R3, R1, 4
                OR      @2[R2], @HEXDIG[R3], TYPED
                AND     R3, R1, 0xF
                OR      @3[R2], @HEXDIG[R3], TYPED
                CMP     R1, 0x20
        ?C      JMP     CARET           ; a control code
                CMP     R1, 0x7F
        ?Z      JMP     CARET           ; DEL
        ?C      JMP     CHAR
                CMP     R1, 0xA0
        ?C      JMP     SHOWN           ; 0x80 to 0x9F
CHAR            OR      @42[R2], R1, LINK
                JMP     SHOWN
CARET           MOVE    @42[R2], LINK+0x5E
                XOR     R3, R1, 0x40    ; ^@ to ^_, and ^? for DEL
                OR      @43[R2], R3, LINK
SHOWN           ADD     COL, COL, 1
                POP     R4
                POP     R3
                POP     R2
                RET

; The character set and the colors. On the left, the 256 characters in 16
; rows of 16, each row labeled with the high digit of its codes, and each
; column with the low digit. On the right, a ramp of each color of COLORS,
; with the intensities 0 to F: as backgrounds, and below them as
; foregrounds, the digits of the intensities on black. The keys do nothing
; here, but the function keys.
CHARS           MOVE    SP, @D_SP
                MOVE    R6, CHARS
                CALL    FRAME
                MOVE    R5, C_TEXTS
                CALL    PRINTS
                MOVE    R1, 0           ; the code
                MOVE    R2, SCREEN+405  ; row 5, column 5, where code 0 goes
:               SHR     R3, R1, 4       ; the label of the row: its first code
                OR      @-3[R2], @HEXDIG[R3], LINK
                MOVE    @-2[R2], LINK+0x30
:               OR      @R2, R1, TYPED
                ADD     R2, R2, 2
                ADD     R1, R1, 1
                AND[M]  R0, R1, 0xF
        ?!Z     JMP     :-
                ADD     R2, R2, 48      ; the next row, 80 - 2 * 16 words on
                CMP     R1, 256
        ?!Z     JMP     :--
                MOVE    R2, SCREEN+444  ; row 5, column 44
                MOVE    R7, 20          ; the background
                CALL    RAMPS
                MOVE    R2, SCREEN+1164  ; row 14, column 44
                MOVE    R7, 8           ; the foreground
                CALL    RAMPS
:               CALL    POLL
                JMP     :-

; RAMPS draws a row for each color of COLORS: its letter at R2, and from
; three columns on, 16 cells of two columns, with the intensities 0 to F of
; the color. R7 is where the color goes in a word: 20 for the background,
; where a cell is two blanks, or 8 for the foreground, where it is the digit
; of the intensity on black. It changes R1 to R5, R8, and R9.
RAMPS           MOVE    R5, COLORS
RROW            MOVE[M] R1, @R5++       ; the letter, or 0 after the last
        ?Z      RET
                OR      @R2, R1, TEXT
                MOVE    R3, @R5++       ; the color at intensity 1
                MOVE    R4, 0           ; the color of the cell
                MOVE    R8, 0           ; the intensity of the cell
                ADD     R9, R2, 3       ; the cell
:               SHL     R1, R4, R7
                CMP     R7, 20
        ?Z      OR      @R9, R1, 0x20
        ?Z      OR      @1[R9], R1, 0x20
        ?!Z     OR      @R9, R1, @HEXDIG[R8]
                ADD     R9, R9, 2
                ADD     R4, R4, R3
                ADD     R8, R8, 1
                CMP     R8, 16
        ?!Z     JMP     :-
                ADD     R2, R2, 80
                JMP     RROW

; The performance counters: those since reset, as a clock and as numbers,
; and the clock's frequency, cycles per microsecond; and those of a run of a
; prime sieve, which runs again before each update of the screen, with the
; cycles per instruction and the instructions per microsecond. The keys do
; nothing here, but the function keys. The values end at column 60, and R3
; is their color.
COUNTS          MOVE    SP, @D_SP
                MOVE    R6, COUNTS
                CALL    FRAME
                MOVE    R5, P_TEXTS
                CALL    PRINTS
                MOVE    @V_RUNS, 0
PLOOP           MOVE    @V_CYC, @P_CYC  ; a run of the sieve, and its counts
                MOVE    @V_INS, @P_INS
                MOVE    @V_US, @P_US
                CALL    PRIMES
                SUB     @V_CYC, @P_CYC, @V_CYC
                SUB     @V_INS, @P_INS, @V_INS
                SUB     @V_US, @P_US, @V_US
                ADD     @V_RUNS, @V_RUNS, 1
                MOVE    R3, TYPED
                MOVE    R4, 20
                MOVE    R7, 0
                MOVE    R2, SCREEN+1100  ; the primes, from R1
                CALL    DEC64
                MOVE    R1, @V_RUNS
                MOVE    R7, 0
                MOVE    R2, SCREEN+1020
                CALL    DEC64
                MOVE    R1, @V_INS
                MOVE    R7, 0
                MOVE    R2, SCREEN+1180
                CALL    DEC64
                MOVE    R1, @V_CYC
                MOVE    R7, 0
                MOVE    R2, SCREEN+1260
                CALL    DEC64
                MOVE    R1, @V_US
                MOVE    R7, 0
                MOVE    R2, SCREEN+1340
                CALL    DEC64
                MOVE    @M_A, @V_CYC    ; 100 times the cycles per instruction
                MOVE    @M_B, 100
                MOVE    @M_A, @M_UMUL
                MOVE    @M_B, @V_INS
                MOVE    R1, @M_UDIVQ
                MOVE    R2, SCREEN+1417
                CALL    FIX2
                MOVE    @M_A, @V_INS    ; 100 times the instructions per microsecond
                MOVE    @M_B, 100
                MOVE    @M_A, @M_UMUL
                MOVE    @M_B, @V_US
                MOVE    R1, @M_UDIVQ
                MOVE    R2, SCREEN+1497
                CALL    FIX2
                MOVE    @V_TLO, @P_US   ; the counters since reset, low word first
                MOVE    @V_THI, @P_USH
                MOVE    @V_CLO, @P_CYC
                MOVE    @V_CHI, @P_CYCH
                MOVE    @V_ILO, @P_INS
                MOVE    @V_IHI, @P_INSH
                MOVE    R4, 20
                MOVE    R1, @V_TLO
                MOVE    R7, @V_THI
                MOVE    R2, SCREEN+540
                CALL    DEC64
                MOVE    R1, @V_CLO
                MOVE    R7, @V_CHI
                MOVE    R2, SCREEN+620
                CALL    DEC64
                MOVE    R1, @V_ILO
                MOVE    R7, @V_IHI
                MOVE    R2, SCREEN+700
                CALL    DEC64
                MOVE    @M_CLO, @V_CLO  ; the cycles per microsecond
                MOVE    @M_CHI, @V_CHI
                MOVE    @M_DLO, @V_TLO
                MOVE    @M_DHI, @V_THI
                MOVE    R1, @M_QLO
                MOVE    R7, @M_QHI
                MOVE    R2, SCREEN+780
                CALL    DEC64
                MOVE    @M_CLO, @V_TLO  ; the clock: the seconds in R5
                MOVE    @M_CHI, @V_THI
                MOVE    @M_DLO, 1000000
                MOVE    @M_DHI, 0
                MOVE    R5, @M_QLO
                MOVE    @M_A, @M_RLO    ; the hundredths
                MOVE    @M_B, 10000
                MOVE    R1, @M_UDIVQ
                MOVE    R2, SCREEN+458
                CALL    TWO
                MOVE    @M_A, R5        ; the seconds, and the minutes in R5
                MOVE    @M_B, 60
                MOVE    R1, @M_UDIVR
                MOVE    R5, @M_UDIVQ
                MOVE    R2, SCREEN+455
                CALL    TWO
                MOVE    @M_A, R5        ; the minutes, and the hours in R5
                MOVE    @M_B, 60
                MOVE    R1, @M_UDIVR
                MOVE    R5, @M_UDIVQ
                MOVE    R2, SCREEN+452
                CALL    TWO
                MOVE    R1, R5
                MOVE    R7, 0
                MOVE    R4, 8
                MOVE    R2, SCREEN+451
                CALL    DEC64
                CALL    POLL
                JMP     PLOOP

; PRIMES runs the sieve of Eratosthenes on the numbers below SIEVE_N, and
; sets R1 to the primes among them. It changes R2 to R6.
PRIMES          MOVE    R2, SIEVE       ; every number a prime
                MOVE    R3, 1
                MOVE    R4, SIEVE_N
                CALL    FILL
                MOVE    R5, 2           ; R5 is the prime, whose multiples go
PRIME           TST     @SIEVE[R5]
        ?Z      JMP     PNEXT
                MOVE    @M_A, R5        ; from its square on
                MOVE    @M_B, R5
                MOVE    R6, @M_UMUL
:               CMP     R6, SIEVE_N
        ?!C     JMP     PNEXT
                MOVE    @SIEVE[R6], 0
                ADD     R6, R6, R5
                JMP     :-
PNEXT           ADD     R5, R5, 1
                CMP     R5, 46          ; up to 45, as 46 * 46 is above SIEVE_N
        ?!Z     JMP     PRIME
                MOVE    R1, 0
                MOVE    R5, 2
:               ADD     R1, R1, @SIEVE[R5]
                ADD     R5, R5, 1
                CMP     R5, SIEVE_N
        ?!Z     JMP     :-
                RET

; DEC64 writes R7:R1 in decimal, in the color R3, right-aligned in the R4
; words before R2, with blanks before it. R4 must have room for the digits.
; It changes R1, R2, R7, and R9. The digits come first and the blanks after
; them, so a number written again and again over itself does not flicker.
DEC64           SUB     @--SP, R2, R4   ; the start of the field
                MOVE    @M_DLO, 10
                MOVE    @M_DHI, 0
:               MOVE    @M_CLO, R1
                MOVE    @M_CHI, R7
                ADD     R9, @M_RLO, 0x30
                OR      @--R2, R9, R3
                MOVE    R1, @M_QLO
                MOVE    R7, @M_QHI
                OR[M]   R0, R1, R7
        ?!Z     JMP     :-
                POP     R9
:               CMP     R9, R2
        ?Z      RET
                OR      @R9++, R3, 0x20
                JMP     :-

; TWO writes R1, which is below 100, as two digits at R2, in the color R3.
; It changes R9.
TWO             MOVE    @M_A, R1
                MOVE    @M_B, 10
                ADD     R9, @M_UDIVQ, 0x30
                OR      @R2, R9, R3
                ADD     R9, @M_UDIVR, 0x30
                OR      @1[R2], R9, R3
                RET

; FIX2 writes R1 / 100 with two decimals and its point at R2, in the color
; R3, and the integer part right-aligned in the 10 words before the point.
; It changes R1, R2, R4, R7, and R9.
FIX2            MOVE    @M_A, R1
                MOVE    @M_B, 100
                MOVE    R1, @M_UDIVQ
                PUSH    @M_UDIVR
                PUSH    R2
                OR      @R2, R3, 0x2E
                MOVE    R7, 0
                MOVE    R4, 10
                CALL    DEC64
                POP     R2
                POP     R1
                ADD     R2, R2, 1
                CALL    TWO
                RET

; The comet, a game. The comet, @, moves through the field, rows 4 to 23
; inside a frame, one cell at each tick, and the cursor keys steer it. Its
; tail follows it. A star, *, makes the tail longer by 4, scores 1, and
; makes the ticks shorter, from 150 to 50 ms, and a new star comes at a
; random free cell. The game ends when the comet hits the frame or its
; tail, and then a key starts a new game. The comet waits for a cursor key
; at the start, and a key that would turn it back is ignored.
;
; The ticks come from the microsecond counter, and the game takes one key at
; each tick. Each tick sets the next one from the time that it came, so a
; tick that comes late delays the ticks after it, and they do not run back
; to back to catch up. So in niceemu, where a microsecond is a step, an
; input file is a script with one key for each tick. RANDOM steps while
; the game waits for a tick, so on the board the stars depend on when the
; keys come. The ring BODY holds the addresses of the comet's cells, and
; the screen itself tells what is in a cell, by the whole word, as the
; frame is blanks too.
GAME            MOVE    SP, @D_SP
                MOVE    R6, GAME
                CALL    FRAME
                MOVE    R5, G_TEXTS
                CALL    PRINTS
                MOVE    @G_BEST, 0
                MOVE    @G_SEED, 0x2545F491
GNEW            MOVE    R2, SCREEN+240  ; a new game: the frame, and the field cleared
                MOVE    R3, BAR+0x20
                MOVE    R4, 80
                CALL    FILL
                MOVE    R5, 20          ; R2 is at row 4
:               MOVE    @R2++, BAR+0x20
                MOVE    R3, TEXT+0x20
                MOVE    R4, 78
                CALL    FILL
                MOVE    @R2++, BAR+0x20
                SUB[M]  R5, R5, 1
        ?!Z     JMP     :-
                MOVE    R3, BAR+0x20
                MOVE    R4, 80
                CALL    FILL
                MOVE    R2, SCREEN+1079  ; the comet, in the middle
                MOVE    @R2, TYPED+0x40
                MOVE    @G_POS, R2
                MOVE    @G_HEAD, 0
                MOVE    @BODY, R2
                MOVE    @G_LEN, 1
                MOVE    @G_GROW, 2
                MOVE    @G_DIR, 0
                MOVE    @G_SCORE, 0
                MOVE    @G_OVER, 0
                MOVE    @G_TICK, 150000
                ADD     @G_NEXT, @P_US, 150000
                CALL    STAR
                MOVE    R1, G_START
                CALL    STATUS
GTICK           CALL    RANDOM          ; wait for the tick
                CMP     @P_US, @G_NEXT
        ?N      JMP     GTICK
                ADD     @G_NEXT, @P_US, @G_TICK  ; from now, not from G_NEXT
                CALL    POLL
                TST     @G_OVER
        ?Z      JMP     GKEY
                TST     R1              ; after the end, a key starts a new game
        ?!Z     JMP     GNEW
                JMP     GTICK
GKEY            SUB     R2, R1, KEY_UP
                CMP     R2, 4
        ?!C     JMP     GMOVE           ; no cursor key
                MOVE    R3, @GSTEPS[R2]
                ADD[M]  R0, R3, @G_DIR  ; 0 for the key that turns it back
        ?!Z     MOVE    @G_DIR, R3
GMOVE           MOVE[M] R4, @G_DIR
        ?Z      JMP     GTICK           ; not started yet
                ADD     R5, @G_POS, R4  ; the cell of the new head
                MOVE    R7, 0           ; 1 for a star
                CMP     @R5, TYPED+0x2A
        ?Z      JMP     GSTAR
                CMP     @R5, TEXT+0x20
        ?!Z     JMP     GOVER           ; the frame, a blank on blue, or the tail
GSTEP           MOVE    R6, @G_POS      ; the old head is now tail
                MOVE    @R6, TAIL+0x6F
                MOVE    @R5, TYPED+0x40
                MOVE    @G_POS, R5
                ADD     R2, @G_HEAD, 1
                AND     R2, R2, BODY_M
                MOVE    @G_HEAD, R2
                MOVE    @BODY[R2], R5
                TST     @G_GROW
        ?Z      JMP     GTAIL
                SUB     @G_GROW, @G_GROW, 1
                ADD     @G_LEN, @G_LEN, 1
                JMP     GDONE
GTAIL           SUB     R2, R2, @G_LEN  ; the last cell of the tail is cleared
                AND     R2, R2, BODY_M
                MOVE    R6, @BODY[R2]
                MOVE    @R6, TEXT+0x20
GDONE           TST     R7
        ?!Z     CALL    STAR
                JMP     GTICK
GSTAR           ADD     @G_SCORE, @G_SCORE, 1
                ADD     @G_GROW, @G_GROW, 4
                CMP     @G_TICK, 50000
        ?!Z     SUB     @G_TICK, @G_TICK, 5000
                MOVE    R1, G_START
                CALL    STATUS
                MOVE    R7, 1
                JMP     GSTEP
GOVER           MOVE    @G_OVER, 1
                CMP     @G_BEST, @G_SCORE
        ?C      MOVE    @G_BEST, @G_SCORE
                MOVE    R1, G_END
                CALL    STATUS
                JMP     GTICK

; STAR puts a star at a random free cell of the field. It changes R1 to R4.
STAR            CALL    RANDOM
                MOVE    @M_A, R1        ; one of the 20 * 78 cells
                MOVE    @M_B, 1560
                MOVE    @M_A, @M_UDIVR
                MOVE    @M_B, 78
                SHL     R2, @M_UDIVQ, 4  ; R2 is SCREEN + 80 * (row + 4) + col + 1
                SHL     R3, @M_UDIVQ, 6
                ADD     R2, R2, R3
                ADD     R2, R2, @M_UDIVR
                ADD     R2, R2, SCREEN+321
                CMP     @R2, TEXT+0x20
        ?!Z     JMP     STAR            ; not free: another
                MOVE    @R2, TYPED+0x2A
                RET

; RANDOM steps G_SEED, a xorshift generator, and sets R1 to it. It changes
; R2.
RANDOM          MOVE    R1, @G_SEED
                SHL     R2, R1, 13
                XOR     R1, R1, R2
                SHR     R2, R1, 17
                XOR     R1, R1, R2
                SHL     R2, R1, 5
                XOR     R1, R1, R2
                MOVE    @G_SEED, R1
                RET

; STATUS writes the score and the best in row 2, and the string at R1 after
; them. It changes R1, R2, R3, R4, R7, and R9.
STATUS          PUSH    R1
                MOVE    R3, TYPED
                MOVE    R4, 5
                MOVE    R1, @G_SCORE
                MOVE    R7, 0
                MOVE    R2, SCREEN+173
                CALL    DEC64
                MOVE    R1, @G_BEST
                MOVE    R7, 0
                MOVE    R2, SCREEN+187
                CALL    DEC64
                MOVE    R2, SCREEN+192
                MOVE    R3, TEXT+0x20
                MOVE    R4, 48
                CALL    FILL
                POP     R1
                MOVE    R2, SCREEN+192
                MOVE    R3, LINK
                CALL    PRINT
                RET

; The board: the self-test of the RAM from RAM_LO, the math unit, the timer's
; interrupts, and the performance counters, each with PASS or FAIL, once each
; time that F11 starts it. R10 counts the failures. Then the Ethernet
; station's addresses and counts, which BLOOP shows again and again, and
; which I and M change (see ESTART).
BOARD           MOVE    SP, @D_SP
                MOVE    R6, BOARD
                CALL    FRAME
                MOVE    R5, S_TEXTS
                CALL    PRINTS
                MOVE    R10, 0
                CALL    TRAM
                MOVE    R2, SCREEN+450
                CALL    RESULT
                CALL    TMATH
                MOVE    R2, SCREEN+530
                CALL    RESULT
                CALL    TTIMER
                MOVE    R2, SCREEN+610
                CALL    RESULT
                CALL    TCOUNT
                MOVE    R2, SCREEN+690
                CALL    RESULT
                MOVE    R1, S_PASSED
                MOVE    R3, TAIL
                TST     R10
        ?!Z     MOVE    R1, S_FAILED
        ?!Z     MOVE    R3, RED
                MOVE    R2, SCREEN+802
                CALL    PRINT
                CALL    EIDLE
BLOOP           CALL    SHOWNET
                CALL    POLL
                TST     R1
        ?Z      JMP     BLOOP           ; no key
                TST     @B_MODE
        ?!Z     JMP     BEDIT           ; an address is being typed
                OR      R1, R1, 0x20    ; I or i, M or m
                CMP     R1, 0x69
        ?Z      MOVE    R7, 1
        ?Z      JMP     ESTART
                CMP     R1, 0x6D
        ?Z      MOVE    R7, 2
        ?Z      JMP     ESTART
                JMP     BLOOP

; Each test sets R1 to 0 when it passes. When it fails, R1 is 1, and R5 and
; R6 tell what failed: an address and the word read there, or for the timer,
; the interrupts and the cycles that they took.

; TRAM writes each word of the RAM_N words from RAM_LO with its address,
; checks them, and does the same with the addresses inverted.
TRAM            MOVE    R7, 0           ; 0, or -1 to invert
RPASS           MOVE    R2, RAM_LO
                MOVE    R4, RAM_N
:               XOR     @R2++, R2, R7
                SUB[M]  R4, R4, 1
        ?!Z     JMP     :-
                MOVE    R2, RAM_LO
                MOVE    R4, RAM_N
:               XOR     R6, R2, R7
                CMP     @R2, R6
        ?!Z     JMP     RBAD
                ADD     R2, R2, 1
                SUB[M]  R4, R4, 1
        ?!Z     JMP     :-
                XOR[M]  R7, R7, -1
        ?!Z     JMP     RPASS
                MOVE    R1, 0
                RET
RBAD            MOVE    R5, R2
                MOVE    R6, @R2
                MOVE    R1, 1
                RET

; TMATH runs the script MATH, which writes operands of the math unit and
; checks its results.
TMATH           MOVE    R2, MATH
:               MOVE[M] R3, @R2++       ; 1 to write, 2 to check, 0 at the end
        ?Z      JMP     MPASS
                MOVE    R5, @R2++       ; the address
                MOVE    R4, @R2++       ; and the word
                CMP     R3, 1
        ?Z      MOVE    @R5, R4
        ?Z      JMP     :-
                MOVE    R6, @R5
                CMP     R6, R4
        ?Z      JMP     :-
                MOVE    R1, 1
                RET
MPASS           MOVE    R1, 0
                RET

; TTIMER lets the timer raise 10 interrupts, one every 1000 cycles, which
; TICK counts, and checks that they came in 9500 to 10500 cycles. It waits
; at most 100000 cycles. It sets VBASE, and leaves E clear.
TTIMER          MOVE    @S_TICKS, 0
                MOVE    @TM_VEC, VECTOR
                AND     R14, R14, 0xFF000000
                OR      R14, R14, VBASE
                MOVE    R5, @P_CYC
                MOVE    @TM_PER, 1000
                OR      R14, R14, 0x40000000  ; E, which lets the interrupts in
:               SUB     R6, @P_CYC, R5
                CMP     @S_TICKS, 10
        ?Z      JMP     :+
                CMP     R6, 100000
        ?C      JMP     :-
:               MOVE    @TM_PER, 0
                NOP                     ; a request still pending is taken here
                NOP
                AND     R14, R14, 0xBFFFFFFF
                MOVE    R5, @S_TICKS
                MOVE    R1, 1
                CMP     R5, 10
        ?C      RET                     ; fewer than 10
                CMP     R6, 9500
        ?C      RET
                CMP     R6, 10500
        ?!C     RET
                MOVE    R1, 0
                RET

; TICK, the routine of the timer's interrupt
TICK            ADD     @S_TICKS, @S_TICKS, 1
                RTI

; TCOUNT checks the performance counters: the instructions of a known
; sequence, and over a loop, at least as many cycles as instructions, some
; microseconds, and 1 to 255 cycles per microsecond.
TCOUNT          MOVE    R5, @P_INS
                NOP                     ; eight instructions
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                SUB     R6, @P_INS, R5  ; read 9 instructions after the first
                MOVE    R5, P_INS
                MOVE    R1, 1
                CMP     R6, 9
        ?!Z     RET
                MOVE    R7, @P_INS
                MOVE    R8, @P_CYC
                MOVE    R9, @P_US
                MOVE    R4, 1000
:               SUB[M]  R4, R4, 1
        ?!Z     JMP     :-
                SUB     R7, @P_INS, R7
                SUB     R8, @P_CYC, R8
                SUB     R9, @P_US, R9
                MOVE    R5, P_CYC
                MOVE    R6, R8
                CMP     R8, R7
        ?C      RET                     ; fewer cycles than instructions
                MOVE    R5, P_US
                MOVE    R6, R9
                TST     R9
        ?Z      RET                     ; no microsecond
                MOVE    @M_A, R8
                MOVE    @M_B, R9
                MOVE    R5, M_UDIVQ
                MOVE[M] R6, @M_UDIVQ
        ?Z      RET
                CMP     R6, 256
        ?!C     RET
                MOVE    R1, 0
                RET

; SHOWNET shows the network station's registers: the IP address in decimal
; with dots, the MAC address in hex with colons, the three counts, and the
; TCP port of the debug link, with whether a host is connected to it. It
; changes R1 to R7 and R9.
SHOWNET         MOVE    R3, TYPED
                MOVE    R2, SCREEN+1304
                MOVE    R5, @E_IP
                MOVE    R6, 24          ; the shift of the byte, 24 down to 0
:               SHR     R1, R5, R6
                AND     R1, R1, 0xFF
                CALL    DECB
                SUB[M]  R6, R6, 8
        ?N      JMP     :+
                OR      @R2++, R3, 0x2E
                JMP     :-
:               MOVE    R4, SCREEN+1319  ; blanks after a shorter address
                SUB[M]  R4, R4, R2
        ?!Z     MOVE    R3, TEXT+0x20
        ?!Z     CALL    FILL
                MOVE    R3, TYPED
                MOVE    R2, SCREEN+1384
                MOVE    R6, 0           ; the byte of the MAC address
:               MOVE    R1, @E_MACH
                CMP     R6, 2
        ?!C     MOVE    R1, @E_MACL
                SHR     R1, R1, @MSHIFT[R6]
                AND     R1, R1, 0xFF
                CALL    HEX2
                ADD     R6, R6, 1
                CMP     R6, 6
        ?Z      JMP     :+
                OR      @R2++, R3, 0x3A
                JMP     :-
:               MOVE    R4, 10
                MOVE    R7, 0
                MOVE    R1, @E_GOOD
                MOVE    R2, SCREEN+1474
                CALL    DEC64
                MOVE    R7, 0
                MOVE    R1, @E_BAD
                MOVE    R2, SCREEN+1554
                CALL    DEC64
                MOVE    R7, 0
                MOVE    R1, @E_SENT
                MOVE    R2, SCREEN+1634
                CALL    DEC64
                MOVE    R5, @E_STAT
                AND     R1, R5, 0xFFFF  ; the port of the link, 0 for none
                MOVE    R7, 0
                MOVE    R2, SCREEN+1714
                CALL    DEC64
                MOVE    R1, S_HOST
                TST     R5
        ?!N     MOVE    R1, S_NOHOST    ; bit 31 is clear: no host
                MOVE    R2, SCREEN+1716
                CALL    PRINT
                RET

; DECB writes R1, which is below 256, in decimal at R2, in the color R3, and
; leaves R2 after it. It changes R1 and R4.
DECB            MOVE    R4, 0           ; the digits, pushed last first
:               MOVE    @M_A, R1
                MOVE    @M_B, 10
                ADD     @--SP, @M_UDIVR, 0x30
                MOVE    R1, @M_UDIVQ
                ADD     R4, R4, 1
                TST     R1
        ?!Z     JMP     :-
:               POP     R1
                OR      @R2++, R1, R3
                SUB[M]  R4, R4, 1
        ?!Z     JMP     :-
                RET

; HEX2 writes R1, which is below 256, as 2 hex digits at R2, in the color R3,
; and leaves R2 after them. It changes R9.
HEX2            SHR     R9, R1, 4
                OR      @R2++, @HEXDIG[R9], R3
                AND     R9, R1, 0xF
                OR      @R2++, @HEXDIG[R9], R3
                RET

; NIBBLE sets R1, a character, to its value as a hex digit, or to 99 if it
; is none.
NIBBLE          SUB     R1, R1, 0x30
                CMP     R1, 10
        ?C      RET                     ; 0 to 9
                ADD     R1, R1, 0x30
                OR      R1, R1, 0x20    ; A to F as a to f
                SUB     R1, R1, 0x61
                CMP     R1, 6
        ?C      ADD     R1, R1, 10
        ?!C     MOVE    R1, 99
                RET

; EIDLE ends the typing of an address: it clears the three rows at the
; bottom, shows the keys that start it, and hides the cursor. It changes R1
; to R4.
EIDLE           MOVE    @B_MODE, 0
                MOVE    @SCR_CTL, 0
                MOVE    R2, SCREEN+1760
                MOVE    R3, TEXT+0x20
                MOVE    R4, 240
                CALL    FILL
                MOVE    R1, E_HELP
                MOVE    R2, SCREEN+1762
                MOVE    R3, TEXT
                CALL    PRINT
                RET

; The typing of an address. I starts the IP address, with R7 = 1, and M the
; MAC address, with R7 = 2. The characters go to row 22 from column 20, and
; COL counts them. The keys are digits and dots for the IP address, and hex
; digits and colons for the MAC address, DEL or backspace, CTRL-C, which is
; RUN/STOP on the MEGA65, or ESC to cancel, and RETURN to write the address
; to the station. A function key still starts its demo.
ESTART          MOVE    @B_MODE, R7
                MOVE    COL, 0
                MOVE    R2, SCREEN+1760
                MOVE    R3, TEXT+0x20
                MOVE    R4, 240
                CALL    FILL
                MOVE    R1, E_NEWIP
                MOVE    R5, E_HINTIP
                CMP     R7, 1
        ?!Z     MOVE    R1, E_NEWMAC
        ?!Z     MOVE    R5, E_HINTMAC
                MOVE    R2, SCREEN+1762
                MOVE    R3, LINK
                CALL    PRINT
                MOVE    R1, R5
                MOVE    R2, SCREEN+1842
                MOVE    R3, TEXT
                CALL    PRINT
                MOVE    @SCR_Y, 22
                MOVE    @SCR_X, 20
                MOVE    @SCR_CTL, 0x60
                JMP     BLOOP

; A key while typing, in R1. The error row is cleared first.
BEDIT           MOVE    R2, SCREEN+1920
                MOVE    R3, TEXT+0x20
                MOVE    R4, 80
                CALL    FILL
                CMP     R1, 0x0D
        ?Z      JMP     EENTER
                CMP     R1, 0x0A
        ?Z      JMP     EENTER
                CMP     R1, 0x03
        ?Z      JMP     ECANCEL
                CMP     R1, 0x1B
        ?Z      JMP     ECANCEL
                CMP     R1, 0x08
        ?Z      JMP     EBACK
                CMP     R1, 0x7F
        ?Z      JMP     EBACK
                MOVE    R4, 10          ; the base, the separator, and the length
                MOVE    R5, 0x2E
                MOVE    R6, 15
                CMP     @B_MODE, 1
        ?!Z     MOVE    R4, 16
        ?!Z     MOVE    R5, 0x3A
        ?!Z     MOVE    R6, 17
                CMP     COL, R6
        ?!C     JMP     BLOOP           ; the line is full
                MOVE    R9, R1
                CMP     R1, R5
        ?Z      JMP     EPUT
                CALL    NIBBLE
                CMP     R1, R4
        ?!C     JMP     BLOOP           ; no digit of the base
EPUT            ADD     R2, COL, SCREEN+1780
                OR      @R2, R9, TYPED
                ADD     COL, COL, 1
                ADD     @SCR_X, COL, 20
                JMP     BLOOP
EBACK           TST     COL
        ?Z      JMP     BLOOP
                SUB     COL, COL, 1
                ADD     R2, COL, SCREEN+1780
                MOVE    @R2, TEXT+0x20
                ADD     @SCR_X, COL, 20
                JMP     BLOOP
ECANCEL         CALL    EIDLE
                JMP     BLOOP

; RETURN: the text is parsed, and written to the station if it is an
; address. Otherwise a message shows, and the typing goes on.
EENTER          MOVE    R2, SCREEN+1780
                MOVE    R3, COL
                MOVE    R4, 10
                MOVE    R5, 0x2E
                MOVE    R6, 4
                CMP     @B_MODE, 1
        ?!Z     MOVE    R4, 16
        ?!Z     MOVE    R5, 0x3A
        ?!Z     MOVE    R6, 6
                CALL    PARSE
                TST     R1
        ?!Z     JMP     EBAD
                CMP     @B_MODE, 1
        ?Z      MOVE    @E_IP, R8
        ?Z      JMP     ECANCEL         ; which ends the typing
                AND[M]  R0, R11, 0x100  ; bit 0 of the first byte: a group address
        ?!Z     JMP     EBAD
                MOVE    @E_MACH, R11
                MOVE    @E_MACL, R8
                JMP     ECANCEL
EBAD            MOVE    R1, E_BADIP
                CMP     @B_MODE, 1
        ?!Z     MOVE    R1, E_BADMAC
                MOVE    R2, SCREEN+1922
                MOVE    R3, RED
                CALL    PRINT
                JMP     BLOOP

; PARSE reads the R3 characters from R2 as R6 numbers in the base R4, from
; 0 to 255, with the separator R5 between them. A number in hex has one or
; two digits, and one in decimal any number of them, as long as its value
; is in range. It sets R1 to 0 and R11:R8 to the bytes, the first in the
; highest bits, or sets R1 to 1 if the text is none of that. It changes R1
; to R9, and R11.
PARSE           MOVE    R11, 0
                MOVE    R8, 0
PFIELD          MOVE    R7, 0           ; the digits of the number
                MOVE    R9, 0           ; and its value
PCHAR           TST     R3
        ?Z      JMP     PLAST           ; the end of the text ends the number
                MOVE    R1, @R2++
                AND     R1, R1, 0xFF
                SUB     R3, R3, 1
                CMP     R1, R5
        ?Z      JMP     PSEP
                CALL    NIBBLE
                CMP     R1, R4
        ?!C     JMP     PBAD            ; no digit of the base
                MOVE    @M_A, R9
                MOVE    @M_B, R4
                ADD     R9, @M_UMUL, R1
                ADD     R7, R7, 1
                CMP     R9, 256
        ?!C     JMP     PBAD
                CMP     R4, 16          ; hex: two digits at most
        ?!Z     JMP     PCHAR
                CMP     R7, 3
        ?!C     JMP     PBAD
                JMP     PCHAR
PLAST           MOVE    R1, 0           ; R1 is 1 if a separator ended the number
                JMP     PEND
PSEP            MOVE    R1, 1
PEND            TST     R7
        ?Z      JMP     PBAD            ; an empty number
                TST     R6
        ?Z      JMP     PBAD            ; one number too many
                SUB     R6, R6, 1
                SHL     R11, R11, 8     ; the byte goes in at the low end of R11:R8
                SHR     R7, R8, 24
                OR      R11, R11, R7
                SHL     R8, R8, 8
                OR      R8, R8, R9
                TST     R1
        ?!Z     JMP     PFIELD          ; the next number
                TST     R6
        ?Z      MOVE    R1, 0           ; all R6 numbers, and the text has ended
        ?!Z     MOVE    R1, 1
                RET
PBAD            MOVE    R1, 1
                RET

; RESULT writes PASS in green at R2 when R1 is 0, or else FAIL in red, and
; R5 and R6 in hex after it, and counts the failure in R10. It changes R1,
; R2, R3, R4, and R9.
RESULT          TST     R1
        ?!Z     JMP     RFAIL
                MOVE    R1, S_PASS
                MOVE    R3, TAIL
                JMP     PRINT           ; which returns to the caller
RFAIL           ADD     R10, R10, 1
                MOVE    R1, S_FAIL
                MOVE    R3, RED
                CALL    PRINT
                ADD     R2, R2, 1
                MOVE    R1, R5
                MOVE    R3, TYPED
                CALL    HEX8
                ADD     R2, R2, 1
                MOVE    R1, R6
                JMP     HEX8            ; which returns to the caller

; HEX8 writes R1 in 8 hex digits from R2, in the color R3, and leaves R2
; after them. It changes R1, R2, R4, and R9.
HEX8            MOVE    R4, 8
:               SHR     R9, R1, 28
                OR      @R2++, @HEXDIG[R9], R3
                SHL     R1, R1, 4
                SUB[M]  R4, R4, 1
        ?!Z     JMP     :-
                RET

; F12 returns to the monitor, or whatever called the demo, with the screen
; cleared, the cursor at the top left, steady, and the status 0. Every demo
; leaves the timer stopped and E clear. A monitor that keeps a cursor of
; its own sets it again.
MONITOR         MOVE    SP, @D_SP
                MOVE    R2, SCREEN
                MOVE    R3, TEXT+0x20
                MOVE    R4, 2000
                CALL    FILL
                MOVE    @SCR_X, 0
                MOVE    @SCR_Y, 0
                MOVE    @SCR_CTL, 0x40  ; the cursor shown, not blinking
                MOVE    R1, 0
                RET

; POLL takes a key from the input, if one has arrived, and sets R1 to it: a
; byte, KEY_UP to KEY_LT for a cursor key, or 0 when there is none. It
; reads the escape sequences that xterm sends for the cursor keys and the
; function keys, and waits for the bytes of a sequence after its ESC, at
; most T_ESC microseconds for each. A function key with a demo in FKEYS
; starts that demo, and POLL does not return. Other sequences give 0. ESC
; and a byte that starts none gives that byte. An ESC with no byte after it
; in time gives ESC, 0x1B, as the MEGA65's ESC key sends it alone. At the
; end of the input, POLL halts. It changes R1 to R5, and calls ECHO, unless
; it is 0, with each byte in R1.
POLL            CALL    READ
        ?Z      RET                     ; no byte, and R1 is 0
                CMP     R1, 0x1B
        ?!Z     RET                     ; a byte other than ESC
:               CALL    NEXT
        ?Z      MOVE    R1, 0x1B        ; an ESC alone is a key of its own
        ?Z      RET
                CMP     R1, 0x1B
        ?Z      JMP     :-              ; ESC again starts again
                CMP     R1, 0x5B        ; [
        ?Z      JMP     CSI
                CMP     R1, 0x4F        ; O
        ?!Z     RET
; ESC O and a byte: A to D are the cursor keys, and P to S F1 to F4. No
; byte in time leaves R1 0, which is none of them.
                CALL    NEXT
                SUB     R2, R1, 0x41
                CMP     R2, 4
        ?C      JMP     ARROW
                SUB     R2, R1, 0x50
                CMP     R2, 4
        ?C      JMP     FKEY
                JMP     NONE
; ESC [, parameters, and a final byte, which is 0x40 or above. A to D are
; the cursor keys, whatever the parameters. ~ is a function key, whose
; number in FNUMS is the first parameter. R3 is the first parameter, and R4
; is 1 once it has ended. A sequence that stops before its final byte
; gives 0 at the timeout, so that the bytes typed after it are keys again.
CSI             MOVE    R3, 0
                MOVE    R4, 0
PARAM           CALL    NEXT
        ?Z      JMP     NONE            ; no byte in time
                CMP     R1, 0x40
        ?!C     JMP     FINAL
                SUB     R2, R1, 0x30
                CMP     R2, 10
        ?!C     MOVE    R4, 1           ; not a digit, such as ;, ends the first
                TST     R4
        ?!Z     JMP     PARAM
                SHL     R5, R3, 1       ; R3 is 10 * R3 + the digit
                SHL     R3, R3, 3
                ADD     R3, R3, R5
                ADD     R3, R3, R2
                JMP     PARAM
FINAL           SUB     R2, R1, 0x41
                CMP     R2, 4
        ?C      JMP     ARROW
                CMP     R1, 0x7E        ; ~
        ?!Z     JMP     NONE
                MOVE    R2, 0
:               CMP     R3, @FNUMS[R2]
        ?Z      JMP     FKEY
                ADD     R2, R2, 1
                CMP     R2, 12
        ?!Z     JMP     :-
NONE            MOVE    R1, 0
                RET
ARROW           ADD     R1, R2, KEY_UP  ; R2 is 0 to 3 for A to D
                RET
FKEY            MOVE[M] R1, @FKEYS[R2]  ; R2 is 0 to 11 for F1 to F12
        ?Z      RET                     ; a key without a demo, and R1 is 0
                JMP     R1

; READ reads the console. Z is set when no byte has arrived, and R1 is the
; byte, or 0. It calls ECHO with the byte, unless ECHO is 0. At the end of
; the input it halts.
READ            MOVE    R1, @CONSOLE
                AND[M]  R0, R1, 0x200   ; the end of the input
        ?!Z     HALT
                AND[M]  R0, R1, 0x100
        ?Z      RET                     ; no byte, and R1 is 0
                AND     R1, R1, 0xFF
                TST     ECHO
        ?!Z     CALL    ECHO
                OR[M]   R0, R1, 0x100   ; Z is clear, also for a byte of 0
                RET

; NEXT waits at most T_ESC microseconds for a byte of the console, and sets
; R1 to it, with Z clear. If none comes, R1 is 0 and Z is set. The deadline
; is on the stack, not in a register, as the demo can halt in READ here, and
; a time in a register would then differ from niceemu's.
NEXT            ADD     @--SP, @P_US, T_ESC  ; the deadline
:               CALL    READ
        ?!Z     JMP     NDONE           ; a byte
                CMP     @P_US, @SP
        ?N      JMP     :-
                MOVE[M] R1, 0
NDONE           ADD     SP, SP, 1       ; drop the deadline, and keep the flags
                RET

; FRAME clears the screen and hides the cursor, and draws the two rows at
; the top that every demo has: the title bar, and the menu of the demos, in
; which the demo that starts at R6 stands out. It sets ECHO to 0, and
; changes R1 to R5.
FRAME           MOVE    @SCR_CTL, 0
                MOVE    ECHO, 0
                MOVE    R2, SCREEN
                MOVE    R3, TEXT+0x20
                MOVE    R4, 2000
                CALL    FILL
                MOVE    R2, SCREEN
                MOVE    R3, BAR+0x20
                MOVE    R4, 160
                CALL    FILL
                MOVE    R5, TITLE
                CALL    PRINTS
                MOVE    R5, MENU
:               MOVE[M] R2, @R5++       ; the position, or -1 at the end
        ?X      RET
                ADD     R2, R2, SCREEN
                MOVE    R3, BAR
                CMP     R6, @R5++       ; the demo
        ?Z      MOVE    R3, MENU_ON
                MOVE    R1, @R5++       ; the string
                CALL    PRINT
                JMP     :-

; SCROLL moves the R4 words from R2 + 80 to R2, which scrolls their rows up
; by one, and clears the row after them. R4 is at least 1. It changes R2 to
; R4.
SCROLL          ADD     R3, R2, 80
:               MOVE    @R2++, @R3++
                SUB[M]  R4, R4, 1
        ?!Z     JMP     :-
                MOVE    R3, TYPED+0x20
                MOVE    R4, 80
                JMP     FILL            ; which returns to the caller

; PRINTS writes the texts of the table at R5 to the screen. Each has its
; position on the screen, 80 * row + column, its color, and its string, and
; -1 ends the table. It changes R1 to R5.
PRINTS          MOVE[M] R2, @R5++
        ?X      RET
                ADD     R2, R2, SCREEN
                MOVE    R3, @R5++
                MOVE    R1, @R5++
                CALL    PRINT
                JMP     PRINTS

; The demos of the function keys F1 to F12, or 0 for none
FKEYS           .DAT    TYPEW, 0, KCODES, 0, CHARS, 0, COUNTS, 0, GAME, 0, BOARD, MONITOR

; The numbers before ~ of F1 to F12. xterm sends ESC O P to ESC O S for F1
; to F4, and 11 to 14 are those of the VT220.
FNUMS           .DAT    11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 23, 24

; The menu: the position of each entry, the demo, and the string, and -1 at
; the end
MENU            .DAT    80, TYPEW, M_TYPEW
                .DAT    96, KCODES, M_KEYS
                .DAT    111, CHARS, M_CHARS
                .DAT    124, COUNTS, M_COUNT
                .DAT    138, GAME, M_GAME
                .DAT    149, BOARD, M_BOARD
                .DAT    -1

; The texts of the title bar, and of the welcome. NAME, VERSION, T1 to T4,
; URL, and KEYS are in the files joined after this one.
TITLE           .DAT    1, BAR, NAME
                .DAT    15, BAR, VERSION
                .DAT    47, BAR, CPU
                .DAT    -1
WELCOME         .DAT    242, TEXT, T1
                .DAT    322, TEXT, T2
                .DAT    482, TEXT, T3
                .DAT    562, TEXT, T4
                .DAT    642, LINK, URL
                .DAT    721, BAR, KEYS
                .DAT    -1

CPU             .ASCII_L 'the 32-bit NICE CPU of B. Ulmann'
M_TYPEW         .ASCII_L ' F1 typewriter '
M_KEYS          .ASCII_L ' F3 key codes '
M_CHARS         .ASCII_L ' F5 charset '
M_COUNT         .ASCII_L ' F7 counters '
M_GAME          .ASCII_L ' F9 comet '
M_BOARD         .ASCII_L ' F11 board '

; The texts of F3
K_TEXTS         .DAT    242, TEXT, K1
                .DAT    322, TEXT, K2
                .DAT    402, TEXT, K3
                .DAT    562, BAR, K_HEX
                .DAT    602, BAR, K_CHARS
                .DAT    -1

K1              .ASCII_L 'Each key that you type, or byte sequence sent to the console, shows'
K2              .ASCII_L 'its bytes in hex and as characters. A control code shows as ^ and a'
K3              .ASCII_L 'character, so ^[ is ESC and ^? is DEL. A function key with a demo starts it.'
K_HEX           .ASCII_L 'Bytes in hex'
K_CHARS         .ASCII_L 'As characters'
HEXDIG          .ASCII_L '0123456789ABCDEF'

; The texts of F5
C_TEXTS         .DAT    242, LINK, C1
                .DAT    284, LINK, C2
                .DAT    325, TEXT, C_DIGIT
                .DAT    364, TEXT, C_BACK
                .DAT    1084, TEXT, C_FORE
                .DAT    1762, TEXT, C_NAMES
                .DAT    -1

C1              .ASCII_L 'Characters, ISO 8859-1'
C2              .ASCII_L 'Colors, 4 bits of red, green, blue'
C_DIGIT         .ASCII_L '0 1 2 3 4 5 6 7 8 9 A B C D E F'
C_BACK          .ASCII_L 'Backgrounds, 0 to F'
C_FORE          .ASCII_L 'Foregrounds, 0 to F'
C_NAMES         .ASCII_L 'R red   G green   B blue   Y yellow   C cyan   M magenta   W gray'

; The colors of the ramps: the letter, and the 12-bit color at intensity 1
COLORS          .DAT    0x52, 0x100     ; R
                .DAT    0x47, 0x010     ; G
                .DAT    0x42, 0x001     ; B
                .DAT    0x59, 0x110     ; Y
                .DAT    0x43, 0x011     ; C
                .DAT    0x4D, 0x101     ; M
                .DAT    0x57, 0x111     ; W
                .DAT    0

; The texts of F7. P3 and P4 are in the file joined after this one.
P_TEXTS         .DAT    242, LINK, P1
                .DAT    404, TEXT, P_TIME
                .DAT    451, TYPED, P_COLON
                .DAT    454, TYPED, P_COLON
                .DAT    457, TYPED, P_POINT
                .DAT    484, TEXT, L_US
                .DAT    564, TEXT, L_CYC
                .DAT    644, TEXT, L_INS
                .DAT    724, TEXT, P_CLOCK
                .DAT    882, LINK, P2
                .DAT    964, TEXT, P_RUNS
                .DAT    1044, TEXT, P_PRIMES
                .DAT    1124, TEXT, L_INS
                .DAT    1204, TEXT, L_CYC
                .DAT    1284, TEXT, L_US
                .DAT    1364, TEXT, P_CPI
                .DAT    1444, TEXT, P_IPUS
                .DAT    1602, TEXT, P3
                .DAT    1682, TEXT, P4
                .DAT    -1

P1              .ASCII_L 'Since reset, while the core runs'
P2              .ASCII_L 'A prime sieve to 2048, run before each update'
P_TIME          .ASCII_L 'Time, h:mm:ss.hh'
L_US            .ASCII_L 'Microseconds'
L_CYC           .ASCII_L 'Cycles'
L_INS           .ASCII_L 'Instructions'
P_CLOCK         .ASCII_L 'Clock in MHz, cycles per microsecond'
P_RUNS          .ASCII_L 'Runs'
P_PRIMES
                .ASCII_L 'Primes found'
P_CPI           .ASCII_L 'Cycles per instruction'
P_IPUS          .ASCII_L 'Instructions per microsecond'
P_COLON         .ASCII_L ':'
P_POINT         .ASCII_L '.'

; The texts of F9, and its messages
G_TEXTS         .DAT    162, TEXT, G_SCOREL
                .DAT    176, TEXT, G_BESTL
                .DAT    -1

G_SCOREL
                .ASCII_L 'Score'
G_BESTL         .ASCII_L 'Best'
G_START         .ASCII_L 'The cursor keys steer the comet @ to the stars *'
G_END           .ASCII_L 'Game over. A key starts a new game.'

; The steps of the cursor keys up, down, right, and left
GSTEPS          .DAT    -80, 80, 1, -1

; The shifts of the six bytes of the MAC address, in E_MACH and E_MACL
MSHIFT          .DAT    8, 0, 24, 16, 8, 0

; The texts of F11
S_TEXTS         .DAT    242, LINK, S1
                .DAT    404, TEXT, S_RAM
                .DAT    484, TEXT, S_MATH
                .DAT    564, TEXT, S_TIMER
                .DAT    644, TEXT, S_COUNT
                .DAT    962, TEXT, S_NOTE1
                .DAT    1042, TEXT, S_NOTE2
                .DAT    1202, LINK, S_ETH
                .DAT    1282, TEXT, S_IP
                .DAT    1362, TEXT, S_MAC
                .DAT    1442, TEXT, S_GOOD
                .DAT    1522, TEXT, S_BAD
                .DAT    1602, TEXT, S_SENT
                .DAT    1682, TEXT, S_LINK
                .DAT    -1

S1              .ASCII_L 'A self-test, which runs each time that F11 starts it'
S_RAM           .ASCII_L 'RAM, 0000B000 to 0000DFFF'
S_MATH          .ASCII_L 'Math unit, multiply and divide'
S_TIMER         .ASCII_L 'Timer, 10 interrupts every 1000 cycles'
S_COUNT         .ASCII_L 'Performance counters'
S_NOTE1         .ASCII_L 'A failure shows where it failed and what was read: an address and its word,'
S_NOTE2         .ASCII_L 'or for the timer, the interrupts that came and the cycles that they took.'
S_ETH           .ASCII_L 'The network station, 0xFFFFFFB0 to 0xFFFFFFBF'
S_IP            .ASCII_L 'IP address'
S_MAC           .ASCII_L 'MAC address'
S_GOOD          .ASCII_L 'Good frames received'
S_BAD           .ASCII_L 'Bad or dropped frames'
S_SENT          .ASCII_L 'Frames sent'
S_LINK          .ASCII_L 'Debug link, TCP port'
S_HOST          .ASCII_L 'a host connected'
S_NOHOST
                .ASCII_L '                '
E_HELP          .ASCII_L 'I types a new IP address, and M a new MAC address.'
E_NEWIP         .ASCII_L 'New IP address:'
E_NEWMAC
                .ASCII_L 'New MAC address:'
E_HINTIP
                .ASCII_L 'Digits and dots. RETURN writes it; ESC, CTRL-C, or RUN/STOP cancels.'
E_HINTMAC
                .ASCII_L 'Hex digits and colons. RETURN writes it; ESC, CTRL-C, or RUN/STOP cancels.'
E_BADIP         .ASCII_L 'Not an IP address: four numbers from 0 to 255, with dots between them.'
E_BADMAC
                .ASCII_L 'Not a MAC address: six bytes in hex with colons, the first one even.'
S_PASS          .ASCII_L 'PASS'
S_FAIL          .ASCII_L 'FAIL'
S_PASSED
                .ASCII_L 'All tests passed.'
S_FAILED
                .ASCII_L 'A test failed.'

; The script of the math unit's test: 1, an address, and a word to write
; there, or 2, an address, and the word expected there, and 0 at the end
MATH            .DAT    1, M_A, -7
                .DAT    1, M_B, 6
                .DAT    2, M_SMUL, -42
                .DAT    2, M_SMULH, -1
                .DAT    2, M_UMUL, 0xFFFFFFD6
                .DAT    2, M_UMULH, 5
                .DAT    2, M_SDIVQ, -1
                .DAT    2, M_SDIVR, -1
                .DAT    2, M_UDIVQ, 0x2AAAAAA9
                .DAT    2, M_UDIVR, 3
                .DAT    1, M_B, 0       ; a division by zero
                .DAT    2, M_UDIVQ, 0xFFFFFFFF
                .DAT    2, M_UDIVR, -7
                .DAT    2, M_SDIVQ, -1
                .DAT    2, M_SDIVR, -7
                .DAT    1, M_A, 0x80000000
                .DAT    1, M_B, -1
                .DAT    2, M_SDIVQ, 0x80000000
                .DAT    2, M_SDIVR, 0
                .DAT    1, M_CLO, 0xA4C86240  ; 10^15 + 123456
                .DAT    1, M_CHI, 0x00038D7E
                .DAT    1, M_DLO, 1000000
                .DAT    1, M_DHI, 0
                .DAT    2, M_QLO, 0x3B9ACA00  ; 10^9
                .DAT    2, M_QHI, 0
                .DAT    2, M_RLO, 123456
                .DAT    1, M_CLO, 0xFFFFFFFF  ; 2^64 - 1
                .DAT    1, M_CHI, 0xFFFFFFFF
                .DAT    1, M_DLO, 10
                .DAT    2, M_QLO, 0x99999999
                .DAT    2, M_QHI, 0x19999999
                .DAT    2, M_RLO, 5
                .DAT    0
