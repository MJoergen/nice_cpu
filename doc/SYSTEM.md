# NICE system: the devices

The ISA ([ISA.md](ISA.md)) reserves the I/O range `0xFFFFFF00`–`0xFFFFFFFF`
and defines no device (ISA §8.3). This file describes the devices that the
emulator ([emulator/](../emulator/README.md)) and the FPGA implementation
([hdl/](../hdl/README.md)) map into it, and the character screen, window, font, and
keyboard that only the emulator has. They are properties of those systems, not of the ISA. The
runtime library ([runtime/](../runtime/README.md)) has routines for them.

"ISA §8.2" refers to a section of ISA.md, and a plain "§2" to a section of
this file.

A data read is an operand read. An instruction fetch from the I/O range
reads 0 and reaches no device (ISA §8.3), so the tables below say what a
data read returns.

## Contents

- [Memory map](#memory-map)
- [1. Console, screen, and read counter](#1-console-screen-and-read-counter)
  - [1.1 Screen](#11-screen)
  - [1.2 Console](#12-console)
  - [1.3 Window](#13-window)
  - [1.4 Cursor](#14-cursor)
  - [1.5 Keyboard](#15-keyboard)
  - [1.6 Pacing](#16-pacing)
  - [1.7 Read counter](#17-read-counter)
  - [1.8 Font](#18-font)
  - [1.9 Receive interrupt](#19-receive-interrupt)
- [2. Math unit](#2-math-unit)
- [3. Performance counters](#3-performance-counters)
- [4. Timer](#4-timer)
- [5. SD card](#5-sd-card)
- [6. Network station](#6-network-station)
- [7. Ethernet frames](#7-ethernet-frames)
- [8. Systems built on the FPGA core](#8-systems-built-on-the-fpga-core)
- [9. Byte windows](#9-byte-windows)
- [10. Clock](#10-clock)

## Memory map

The byte windows, the I/O range, the screen, the font, and what the systems put in them. The emulator's own map, with
its ordinary memory, is in [emulator/README.md](../emulator/README.md).

| Address | Words | What |
|---|---|---|
| `0x10000000`–`0x5FFFFFFF` | 5 × 2^28 | The byte windows onto words `0x00000000`–`0x03FFFFFF` (§9). |
| `0xFFFE0000`–`0xFFFE1FFF` | 8192 | The font RAM (§1.8). |
| `0xFFFE2000`–`0xFFFE3FFF` | 8192 | The character ROM (§1.8). |
| `0xFFFF0000`–`0xFFFF07CF` | 2000 | The emulator's character screen, 80×25 (§1.1). |
| `0xFFFFFF00` | 1 | Console (§1.2). |
| `0xFFFFFF01` | 1 | Read counter (§1.7). |
| `0xFFFFFF02` | 1 | The console's receive interrupt (§1.9). |
| `0xFFFFFF03`–`0xFFFFFF0F` | 13 | Reserved for I/O. |
| `0xFFFFFF10`–`0xFFFFFF1F` | 16 | Timer (§4). |
| `0xFFFFFF20`–`0xFFFFFF3F` | 32 | Math unit (§2). |
| `0xFFFFFF40`–`0xFFFFFF7F` | 64 | Performance counters (§3), but for `0xFFFFFF46`–`0xFFFFFF49`, the clock of the time of day (§10). |
| `0xFFFFFF80`–`0xFFFFFF82` | 3 | Reserved for I/O. The emulator's window draws its cursor from them (§1.4). |
| `0xFFFFFF83`–`0xFFFFFF85` | 3 | Reserved for I/O. |
| `0xFFFFFF86` | 1 | Reserved for I/O. The emulator's window takes its font base from it (§1.8). |
| `0xFFFFFF87`–`0xFFFFFF9F` | 25 | Reserved for I/O. |
| `0xFFFFFFA0`–`0xFFFFFFAF` | 16 | SD card (§5). |
| `0xFFFFFFB0`–`0xFFFFFFBF` | 16 | Network station (§6). |
| `0xFFFFFFC0`–`0xFFFFFFCF` | 16 | Ethernet frames (§7). |
| `0xFFFFFFD0`–`0xFFFFFFFF` | 48 | Reserved for I/O. The debug link's registers are here, for the link only ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)). |

## 1. Console, screen, and read counter

### 1.1 Screen

The emulator maps a character screen of 25 rows of 80 words at `0xFFFF0000`, row by row: row r, column c is the word at `0xFFFF0000` + 80·r + c, row 0 is the top, column 0 is the left edge, and the last word is at `0xFFFF07CF`. The original emulator of 2004, `NICE.pm` ([REFERENCES.md](REFERENCES.md)), maps the screen at `0x400`. Here it is at `0xFFFF0000`, so that it does not overlap the code of programs longer than 1024 words, and the emulator's option `-2004` puts it back at `0x400` for the 2004 example programs.

The screen word has the character in bits 7..0, the background color in bits 31..20, and the foreground color in bits 19..8. Each color is three 4-bit components, red, green, and blue, from the high bits to the low. A component `n` gives the byte `n × 0x11`, so `0x0` is no intensity and `0xF` is full. The emulator's option `--color` prints the screen with these colors as ANSI escapes. Programs that write the 2004 layout should note one difference: the 2004 IDE (`nice_ide.pl`) inverts the three foreground components, so that `0x0` is full intensity and `0xF` is none, and here it is not inverted. The emulator's option `--invert-fg` inverts it, for the 2004 programs. A word with only a character, such as `0x41`, is black on black here, but white on black in the 2004 IDE. The background is the same in both.

### 1.2 Console

The emulator maps a console at `0xFFFFFF00`, and programs use it for input and output. Each write prints bits 7..0 of the word. Each data read takes the next input byte, if one waits, and returns:

| The input | A read returns |
|---|---|
| A byte waits | The byte in bits 7..0, with bit 8 set. |
| No byte waits | 0, from a UART or from the emulator's window (§1.3). From stdin, a file, or the simulation memory of the FPGA core, the read waits for the next byte or the end of the input instead, and never returns 0. |
| The input has ended | `0x200` (bit 9). A UART's input ends only if the system provides a break (§8), and a keyboard's never ends (§1.5). |

The emulator reads its input from stdin, or from the file of its option `--input`, so stdin from `/dev/null` gives a console with no input. The simulation memory of the FPGA core reads a file too, and returns `0x200` without one. This repository has no UART. A system built on the FPGA core, such as the example design in [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65), maps one at the same address, with the same bits (MICROARCH.md §8).

### 1.3 Window

The emulator built with a window (its README says how) shows the screen in a window with its option `--window`, 1280×800 pixels, while the program runs. Each character is 16×32 pixels, from the font of §1.8, which is Spleen until the program selects a font of its own, with the colors of §1.1. The window shows the 2000 words of the screen and nothing else; the console still writes to stdout, or to the host with `--link`. When the program halts, the window stays, with the last screen, until it is closed. Closing the window before then ends the run. With `--link` ([DEBUG.md §7](DEBUG.md#7-transports)), the window opens when the emulator starts and stays open over every run. It shows the screen also while the processor is held, halted, or paused, so the host's writes to the screen show at once. Closing the window ends the emulator, as a signal does.

### 1.4 Cursor

The window draws a cursor from three words, numbered as the screen registers of NiceMonMEGA65 (§8). In the emulator they are ordinary memory, which the window only reads:

| Address | What |
|---|---|
| `0xFFFFFF80` | State. Bit 6 shows the cursor, bit 5 makes it blink, about twice a second, and bit 4 makes it small, the bottom 4 lines of the character. The other bits are ignored. |
| `0xFFFFFF81` | The cursor's column, 0 to 79. |
| `0xFFFFFF82` | The cursor's row, 0 to 24. |

The cursor swaps the foreground and background colors of its character. With a column or row out of range, no cursor is shown. The words are 0 at the start of a run, so the cursor is off.

### 1.5 Keyboard

With `--window`, the console reads the input of `--input`, if given, and then the keys typed into the window. It does not read stdin. A read returns 0 when no byte is waiting, as from a UART. Without `--link` it never returns `0x200`, as a keyboard has no end. A key gives these bytes, as xterm sends them:

| Key | Bytes |
|---|---|
| Letters, digits, symbols | The ASCII of the character typed, with the host's keyboard layout |
| Return, Enter | CR (`0x0D`) |
| Backspace, Delete | DEL (`0x7F`) |
| Tab, Esc | TAB (`0x09`), ESC (`0x1B`) |
| Up, Down, Right, Left | `ESC [ A`, `ESC [ B`, `ESC [ C`, `ESC [ D` |
| F1 to F4 | `ESC O P`, `ESC O Q`, `ESC O R`, `ESC O S` |
| F5 to F8 | `ESC [ 15 ~`, `ESC [ 17 ~`, `ESC [ 18 ~`, `ESC [ 19 ~` |
| F9 to F12 | `ESC [ 20 ~`, `ESC [ 21 ~`, `ESC [ 23 ~`, `ESC [ 24 ~` |
| Ctrl with a letter | Its control code, `0x01` to `0x1A`, so Ctrl-C is `0x03` |

A character outside ASCII and the other keys give nothing. A held key repeats as the host repeats it.

With `--link`, the keys and the bytes from the host go into the one input buffer, in the order they arrive, as a board's keyboard and UART share one FIFO (§8). Keys typed while the processor is held or has halted are dropped, and keys typed while it is paused wait in the buffer, as the host's bytes do. A byte of a key waits until the buffer has room for two bytes, so that a byte from the host still finds room. When the host's input ends ([DEBUG.md §7](DEBUG.md#7-transports)), the host's bytes are dropped until the next start or the next connection, but the keys still go into the buffer, as after a break on a board's UART (§8). A read then returns a byte if one waits, and `0x200` otherwise. So a program that reads until the end still ends with the host's input, and one that reads on, as a monitor does, gets the keys.

### 1.6 Pacing

With `--window`, the emulator runs as fast as the host can, as without the window. The microsecond counter (§3) keeps the host's time, so a program that waits on it waits real time, and the screen changes as the program writes it. The cycle counter and the timer count one per step (§3, §4), at the host's rate of steps, tens of megahertz, which varies, so a program that keeps time by the timer or by counting steps runs at a rate of its own. The option `--speed N` runs N steps a second for such a program: at `--speed 1000000`, one step per microsecond, the cycle counter counts at 1 MHz, and a timer period of P cycles lasts P microseconds, where on a board of 100 MHz it lasts P/100.

While a program waits, the emulator sleeps. A console read that finds no byte and a read of `TIME_LO` are idle reads, and two idle reads within 1000 steps of each other mean a wait loop. At each step of one, the emulator waits for a key or another event of the window, so a key still reaches the program at once: for up to a millisecond when the loop has read `TIME_LO` within the last 1000 steps, so that a wait on the counter ends at most a millisecond late, and for up to 10 milliseconds when it waits for a key alone. A program that polls less often than once in 1000 steps never sleeps, and runs at full speed. With `--speed`, the pace sleeps instead, and the rule does not apply.

A wait for an interrupt ([ISA.md §7.5](ISA.md#75-waiting)) takes no time on the host, as the emulator counts its steps at once (§3). With `--speed`, the pace runs them at N a second, as any steps. A wait that no request can end, with no timer running, no `--irq` or `--nmi` to come, and no request of the console to come (§1.9), stops a run with an error, unless the run has the window or the link. Then the emulator sleeps until the window closes or the host ends the run. A wait with the console's enable set, under the window, sleeps until a key or a byte from the host comes, and its request ends the wait. So a program that waits for input with `WAIT` sleeps without the rule of the idle reads above. While the timer runs too, the timer's next request ends the wait at once, as above, and the host does not sleep.

### 1.7 Read counter

At `0xFFFFFF01` the emulator and the simulation memory of the FPGA core map a read counter for tests. A data read of it returns the number of data reads of it since the last write to it, and a write sets that number. It is 0 at the start of a run, and a reset of the processor does not clear it. Tests use it to count the data accesses of ISA §8.2.

### 1.8 Font

The window draws each character from a font of 256 glyphs, one for each code, of 16×32 pixels. The emulator maps two fonts below the screen, and a word that selects the one the window shows:

| Address | What |
|---|---|
| `0xFFFE0000`–`0xFFFE1FFF` | The font RAM, read and write. A write keeps bits 15..0 of the word, so bits 31..16 read 0. |
| `0xFFFE2000`–`0xFFFE3FFF` | The character ROM, Spleen 16×32. A read returns the row, and a write is dropped. Its glyphs are those of ISO 8859-1, and the codes `0x00`–`0x1F` and `0x7F`–`0x9F` are blank. |
| `0xFFFFFF86` | The font base. 0 shows the ROM, and `0xFFFE0000` the font RAM. The other values are reserved, and show the ROM. |

Both fonts have the same layout. The word at the font's address + 32·c + r is row r of the glyph of code c, row 0 at the top. Bits 15..0 are the 16 pixels of the row, the leftmost in bit 15. A set bit is drawn in the foreground color of §1.1, and a clear bit in the background color.

The font RAM and the base are 0 at the start of a run, and the debug link's clear makes them 0 again ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)), so the window shows Spleen until a program writes the base. A program that wants Spleen's letters and a few symbols of its own copies the ROM into the font RAM, changes the glyphs it wants, and writes `0xFFFE0000` to the base. The base is an address, so that a later system can show a font from elsewhere in memory without changing what programs see.

The window draws every cell from the font that the base selects. While the font RAM is selected, a write to a glyph shows at the next redraw in every cell with its code, and a write to the base changes the whole screen at once. In the emulator, the base is ordinary memory that the window only reads, as the cursor's words are (§1.4), and is one of the words of NiceMonMEGA65's screen registers (§8).

The fonts are memory to every access. An instruction fetch reads them as a data read does, `--dump` and the debug link read and write them, and a write to the ROM is dropped from each. `--screen` and `--color` print the codes of the screen as text, whatever the font.

### 1.9 Receive interrupt

At `0xFFFFFF02` the emulator and the FPGA implementation map `CONSOLE_IRQ`, with which the console raises IRQ when input comes, so that a program can wait for input with `WAIT` (ISA §7.5) instead of polling.

| Bits | A data read returns | A write |
|---|---|---|
| 7..0 | the vector v | sets v |
| 8 | the enable | sets the enable |
| 31..9 | 0 | is ignored |

While the enable is 1, the console raises IRQ with vector v when:

1. a byte enters the input while no byte waits,
2. the input ends, so that a read returns `0x200` (§1.2), or
3. a write sets the enable from 0 to 1 while a byte waits or the input has ended.

- The request is an edge, not a level. A byte that enters while others wait raises none, so a program reads the input until no byte waits before it waits again. A level would be taken again after each `RTI`, for as long as the byte waits, and the wait loop below would never get back to read it.
- A request may come for a byte that the program has read already. It only ends a wait once more, for a read that finds no byte.
- A write of the enable to 0 withdraws no request that is pending, as a stop of the timer does not (§4).
- The interrupt routine need not acknowledge the request. Taking it is enough.
- The console is a source of IRQ beside the timer, which goes first (§4).
- Reset sets v and the enable to 0, with no request pending.

When a byte enters depends on the input. From the window, with `--link` or without, it enters when a key is typed or the host sends it (§1.5), and from a UART when it arrives. From stdin, a file, `--link` without the window ([DEBUG.md §7](DEBUG.md#7-transports)), or the simulation memory of the FPGA core, where a read waits for its byte, the first byte enters at the start of the run, and each one after it when the read before has taken one. So there a program that waits for each byte with `WAIT` runs as one that polls. Input that is dropped while the processor is held or has halted (§1.5, §8) enters nothing, and a halted processor takes no request (ISA §7.1).

A program waits for a byte with E = 0, so that a byte that comes between its read and its `WAIT` leaves a request pending, and the `WAIT` ends at once. With the enable set, and a vector whose routine is only `RTI`:

    :               AND     R14, R14, 0xBFFFFFFF  ; E = 0
                    MOVE    R1, @0xFFFFFF00
                    AND[M]  R0, R1, 0x100   ; bit 8: a byte waits
            ?!Z     JMP     :+
                    WAIT                    ; ends when a request is pending
                    OR      R14, R14, 0x40000000  ; E = 1: the request is taken
                    JMP     :-
    :               ...                     ; the byte is in R1

The loop can leave a request pending: a byte that enters after E is cleared is read at once, and its request stays. A program that then sets another vector table and E = 1 takes it through that table. So before such a hand-over, a program clears the enable and takes the request: it sets E = 1 and then clears it again, with VBASE still on the table whose routine for v is only `RTI`. A request that a stopped timer leaves pending needs the same.

## 2. Math unit

The emulator and the FPGA implementation map a math unit, the MPU, at `0xFFFFFF20`–`0xFFFFFF3F`. It multiplies and divides 32-bit integers, counts the bits of a 32-bit integer, and divides 64-bit integers and takes their square root.

The first 16 words work on the 32-bit operands A and B:

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF20` | `A` | the left operand A | sets A |
| `0xFFFFFF21` | `B` | the right operand B | sets B |
| `0xFFFFFF22` | `SMUL_LO` | bits 31..0 of A · B, signed | is ignored |
| `0xFFFFFF23` | `SMUL_HI` | bits 63..32 of A · B, signed | is ignored |
| `0xFFFFFF24` | `UMUL_LO` | bits 31..0 of A · B, unsigned | is ignored |
| `0xFFFFFF25` | `UMUL_HI` | bits 63..32 of A · B, unsigned | is ignored |
| `0xFFFFFF26` | `SDIV_Q` | the quotient of A / B, signed | is ignored |
| `0xFFFFFF27` | `SDIV_R` | the remainder of A / B, signed | is ignored |
| `0xFFFFFF28` | `UDIV_Q` | the quotient of A / B, unsigned | is ignored |
| `0xFFFFFF29` | `UDIV_R` | the remainder of A / B, unsigned | is ignored |
| `0xFFFFFF2A` | `CLZ` | the number of leading 0 bits in A, 32 for 0 | is ignored |
| `0xFFFFFF2B` | `CTZ` | the number of trailing 0 bits in A, 32 for 0 | is ignored |
| `0xFFFFFF2C` | `POPCNT` | the number of 1 bits in A | is ignored |
| `0xFFFFFF2D`–`0xFFFFFF2F` | | 0 | is ignored |

The next 16 words work on the 64-bit operands C and D. Each 64-bit value takes two words, low word first, as in [ABI.md](../runtime/ABI.md):

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF30`, `0xFFFFFF31` | `C_LO`, `C_HI` | the left operand C | sets that half of C |
| `0xFFFFFF32`, `0xFFFFFF33` | `D_LO`, `D_HI` | the right operand D | sets that half of D |
| `0xFFFFFF34`, `0xFFFFFF35` | `SDIV64_Q_LO`, `SDIV64_Q_HI` | the quotient of C / D, signed | is ignored |
| `0xFFFFFF36`, `0xFFFFFF37` | `SDIV64_R_LO`, `SDIV64_R_HI` | the remainder of C / D, signed | is ignored |
| `0xFFFFFF38`, `0xFFFFFF39` | `UDIV64_Q_LO`, `UDIV64_Q_HI` | the quotient of C / D, unsigned | is ignored |
| `0xFFFFFF3A`, `0xFFFFFF3B` | `UDIV64_R_LO`, `UDIV64_R_HI` | the remainder of C / D, unsigned | is ignored |
| `0xFFFFFF3C` | `ISQRT64_Q` | Q = floor(√C), C unsigned, which fits in 32 bits | is ignored |
| `0xFFFFFF3D`, `0xFFFFFF3E` | `ISQRT64_R_LO`, `ISQRT64_R_HI` | the remainder C − Q², which is at most 2Q and needs 33 bits | is ignored |
| `0xFFFFFF3F` | | 0 | is ignored |

- Each result depends only on the operands of its half, A and B or C and D, as they are when it is read. `CLZ`, `CTZ`, and `POPCNT` depend on A alone, and `ISQRT64` on C alone. A read has no side effect, so the results can be read in any order and any number of times.
- Signed operations treat the operands as two's complement. A signed product is exact in 64 bits.
- A signed quotient is rounded toward zero, and a signed remainder has the sign of the dividend, so A = Q · B + R and C = Q · D + R. This is C's `/` and `%`, and wasm's `div_s` and `rem_s`.
- Division by zero gives a quotient of all ones and a remainder equal to the dividend, signed and unsigned: Q = `0xFFFFFFFF` and R = A, or Q = `0xFFFFFFFF_FFFFFFFF` and R = C.
- The signed division of the most negative number by −1 gives Q = the most negative number and R = 0. That is `0x80000000 / 0xFFFFFFFF` = `0x80000000` for A and B, and −2⁶³ / −1 = −2⁶³ for C and D.
- floor(log2 A) is 31 − `CLZ`, for A other than 0.
- Reset sets A, B, C, and D to 0.

These are RISC-V's results for the two special cases. Software never needs to wait for a result. The FPGA implementation starts a new computation at each write to an operand, which may take many cycles, and holds off the acknowledge of a read of a result until the result is ready.

A use of the MPU takes several instructions, and an interrupt may come between them. An interrupt service routine that uses the MPU must therefore read the operands it changes first, and write them back before `RTI`. The results depend only on the operands, so that restores the whole state.

## 3. Performance counters

The emulator and the FPGA implementation map performance counters at `0xFFFFFF40`–`0xFFFFFF7F`: three 64-bit counters of cycles, instructions, and time, five 64-bit counters of the events of a program, and the fetch statistics of the FPGA implementation.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF40` | `CYCLE_LO` | bits 31..0 of the cycle counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF41` | `CYCLE_HI` | bits 63..32 of the cycle counter's snapshot | is ignored |
| `0xFFFFFF42` | `INSTR_LO` | bits 31..0 of the instruction counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF43` | `INSTR_HI` | bits 63..32 of the instruction counter's snapshot | is ignored |
| `0xFFFFFF44` | `TIME_LO` | bits 31..0 of the microsecond counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF45` | `TIME_HI` | bits 63..32 of the microsecond counter's snapshot | is ignored |
| `0xFFFFFF46`–`0xFFFFFF49` | | the clock of the time of day (§10) | as §10 says |
| `0xFFFFFF4A` | `READ_LO` | bits 31..0 of the data read counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF4B` | `READ_HI` | bits 63..32 of the data read counter's snapshot | is ignored |
| `0xFFFFFF4C` | `STORE_LO` | bits 31..0 of the store counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF4D` | `STORE_HI` | bits 63..32 of the store counter's snapshot | is ignored |
| `0xFFFFFF4E` | `SKIP_LO` | bits 31..0 of the skip counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF4F` | `SKIP_HI` | bits 63..32 of the skip counter's snapshot | is ignored |
| `0xFFFFFF50` | `JUMP_LO` | bits 31..0 of the jump counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF51` | `JUMP_HI` | bits 63..32 of the jump counter's snapshot | is ignored |
| `0xFFFFFF52` | `INTR_LO` | bits 31..0 of the interrupt counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF53` | `INTR_HI` | bits 63..32 of the interrupt counter's snapshot | is ignored |
| `0xFFFFFF54`–`0xFFFFFF5F` | | 0 | is ignored |
| `0xFFFFFF60`–`0xFFFFFF7F` | | the fetch statistics (MICROARCH.md §8.1), or 0 in the emulator | as MICROARCH.md §8.1 says, or is ignored in the emulator |

- The **instruction counter** counts the instructions that have completed since reset. Every instruction counts, including one whose condition is false, a control instruction, and `INT`. An interrupt entry for IRQ or NMI does not count, because it is not an instruction. An instruction that reads `INSTR_LO` reads the number of instructions that completed before it.
- The **cycle counter** counts the clock cycles since reset while the core runs, and stops when the core is held, paused, or has halted, so a reading after a halt does not change. The emulator has no clock, so it counts one cycle for each instruction, each interrupt entry, and each wait step (below), that is, for each step. Its cycle counter is an approximation and differs from the FPGA implementation's.
- The **microsecond counter** counts microseconds since reset while the core runs, and stops when the core is held, paused, or has halted, like the cycle counter. The FPGA implementation derives it from its clock frequency, so for a clock of 1 MHz or more the count after N cycles is the integer part of N·10⁶ divided by the frequency, whether or not it is a multiple of 1 MHz: it adds 1000000 to an accumulator in each cycle, and counts a microsecond and subtracts the clock frequency in hertz each time the sum reaches it. The emulator counts the host's monotonic time, without the time the host sleeps, in microseconds since reset, less the time the processor was held, paused, or halted. A read of `TIME_LO` reads the host's clock. So a program that waits on the counter waits real time, as on a board, with or without the window and at any speed (§1.6). A console read that waits for input counts as running, as a board polls meanwhile, and so does a wait (below). With the option `--step-time`, the emulator instead counts one microsecond for each step, as its cycle counter counts one cycle, so that a run counts the same each time. A program that needs a time in seconds divides by 1000000, whatever the board.
- In the emulator, the cycle counter and the microsecond counter have no fixed ratio, unless with `--step-time`. A program that divides one by the other gets the rate at which the host runs steps, which varies from run to run.
- The **event counters** count what the program does, not what the processor that runs it does. So the emulator and every FPGA core count the same, and a program reads the same counts on each:
  - The **data read counter** counts the data reads of ISA §8.2: the operand reads, and the vector table reads of interrupt entries and `INT`. A read of `READ_LO` returns the number of data reads before it, the earlier reads of its own instruction included.
  - The **store counter** counts the destination writes of ISA §8.2, to a device too, and to a word that ignores them.
  - The **skip counter** counts the instructions whose condition was false.
  - The **jump counter** counts the instructions that are not skipped and write R15: as their register destination, in mode 000, 001, or 010, or by the side effect of a field, in mode 001, 010, 101, or 110 (ISA §4), and `RTI`. It counts a jump to the next instruction too. It does not count `INT`, an interrupt entry, or an instruction that halts.
  - The **interrupt counter** counts the interrupt entries for IRQ and NMI, and `INT`. An `INT` that halts does not count.
  - A read of a counter's low word returns the events of the steps before its instruction, and for the data read counter also the earlier reads of its own instruction. The accesses of the debug link (DEBUG.md) are not the program's, and do not count.
- Reset sets all the counters and their snapshots to 0. No counter can be written. A program measures an interval as the difference of two readings.
- A counter wraps from `0xFFFFFFFF_FFFFFFFF` to 0. At one count per cycle at 100 MHz that takes over 5000 years.
- The **fetch statistics** count what the pipelined FPGA core does in each cycle: a cause for each cycle, and the flushes of its pipeline by cause, to show where the cycles of a program go. They depend on the core, so MICROARCH.md §8.1 describes them. The emulator has none: their words read 0 and ignore writes, and are not memory.

**Waiting.** A processor that waits for an interrupt ([ISA.md §7.5](ISA.md#75-waiting)) runs: the cycle counter, the microsecond counter, and the timer (§4) count on, and the instruction counter and the event counters count nothing. In the FPGA implementation a wait lasts a whole number of clock cycles. In the emulator it lasts a whole number of wait steps, and the cycle counter and the timer count one for each, as for any step. The emulator does not run the wait steps one by one. It counts them at once, up to the step at which the next request comes, from the timer or from `--irq` or `--nmi`, or up to the step limit, with the same result. So the microsecond counter, which keeps the host's time, moves on little during a wait, unless with `--step-time`, where it counts one for each wait step.

**Reading a counter.** Read the low word first, then the high word: `MOVE R1, @CYCLE_LO` then `MOVE R2, @CYCLE_HI`. The read of the low word copies the whole 64-bit counter into the snapshot, and the read of the high word returns the high half of the snapshot. So R2:R1 is the value at the time of the first read, even when the low word wraps from `0xFFFFFFFF` to 0 between the two reads. Each counter has its own snapshot.

An interrupt service routine that reads a counter's low word overwrites its snapshot. If the routine interrupted code between the two reads, that code then reads a high word that may not belong to its low word. So either interrupt service routines do not read the counters, or the code that reads them clears E, the interrupt enable flag (ISA §1.3), around its two reads and NMI service routines do not read them.

## 4. Timer

The emulator and the FPGA implementation map a timer at `0xFFFFFF10`–`0xFFFFFF1F`. It raises IRQ once every P cycles.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF10` | `TIMER_PERIOD` | the period P | sets P, and COUNT, to the value written |
| `0xFFFFFF11` | `TIMER_COUNT` | COUNT, the cycles left until the next request | is ignored |
| `0xFFFFFF12` | `TIMER_VECTOR` | the vector v in bits 7..0, and 0 in bits 31..8 | sets v to bits 7..0 of the value written |
| `0xFFFFFF13`–`0xFFFFFF1F` | | 0 | is ignored |

- While P ≠ 0, COUNT decreases by one at the end of each cycle, the cycle of the write to `TIMER_PERIOD` included. When COUNT reaches 0, the timer raises IRQ with vector v, and COUNT is set to P again. So the first request comes at the end of the P-th cycle, counting from the write, and then one comes every P cycles.
- P = 0 stops the timer, and COUNT stays 0. A request that is already pending stays pending.
- The emulator counts one cycle for each step, a wait step included, as its cycle counter does (§3). The FPGA implementation counts clock cycles while the core runs. Like the cycle counter, COUNT stops when the core is held or has halted, and counts on while it waits for an interrupt (§3).
- The timer and the console's receive interrupt (§1.9) are the sources of IRQ (ISA §7.1). Each one's requests merge only with its own. When both are pending, the timer's is taken first, so that a timer routine's latency stays steady; the console's input waits in its buffer meanwhile. The emulator's `--irq` raises requests of the timer's source, as it stands in for the timer in the tests of the FPGA core.
- A request keeps the vector it was raised with. If the timer's last request is still pending when it raises the next one, the two merge (ISA §7.1), and the pending one keeps its vector. So a timer whose period is shorter than its interrupt routine, or than a stretch of code with E = 0, loses requests. To keep time, read the cycle counter rather than count interrupts.
- The interrupt routine need not acknowledge the request. Taking it is enough.
- Reset sets P, COUNT, and v to 0, with no request pending.

To get an IRQ through vector table entry `0x41` every 100000 cycles, that is, every millisecond at 100 MHz:

                    MOVE    @TIMER_VECTOR, 0x41
                    MOVE    @TIMER_PERIOD, 100000
                    OR      R14, R14, 0x40000000  ; E = 1

## 5. SD card

The emulator and the FPGA implementation map an SD card controller at `0xFFFFFFA0`–`0xFFFFFFAF`. The controller does the whole protocol of the card. A program sees a buffer of one sector, 512 bytes, and the commands "read sector N into the buffer" and "write the buffer to sector N". A system has one or more slots for cards, and the controller serves the one that is selected.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFFA0` | `SD_CSR` | the status below | starts the command in bits 3..0 |
| `0xFFFFFFA1` | `SD_LBA` | the sector number | sets the sector number |
| `0xFFFFFFA2` | `SD_CHUNK` | the chunk, 0 to 15 | sets the chunk to bits 3..0 |
| `0xFFFFFFA3` | `SD_ERROR` | the error of the last command, 0 for none | is ignored |
| `0xFFFFFFA4` | `SD_SELECT` | the selected slot, 0 to 15 | selects the slot in bits 3..0 |
| `0xFFFFFFA5` | `SD_LAST` | the number of the card's last sector while "ready" is 1, and 0 otherwise | is ignored |
| `0xFFFFFFA6` | `SD_SLOTS` | the number of slots of the system | is ignored |
| `0xFFFFFFA7` | | 0 | is ignored |
| `0xFFFFFFA8`–`0xFFFFFFAF` | `SD_BUF0`–`SD_BUF7` | word 8·c + k of the buffer, where c is `SD_CHUNK` and k is 0 to 7 | writes that word |

The commands, in bits 3..0 of a write to `SD_CSR`:

| Command | Name | What it does |
|---|---|---|
| 0 | Init | Starts the card in the selected slot up, reads its size, and clears "changed" |
| 1 | Read | Reads the sector `SD_LBA` into the buffer |
| 2 | Write | Writes the buffer to the sector `SD_LBA` |
| 3–15 | | Nothing. The write is ignored. |

The status, from a read of `SD_CSR`:

| Bit | Meaning |
|---|---|
| 0 | Busy: a command runs |
| 1 | Error: the last command failed, and `SD_ERROR` says why |
| 2 | Present: a card is in the selected slot |
| 3 | Ready: the card in the selected slot has been started up by Init |
| 4 | Changed: a card has been put into the selected slot since the last Init of it |
| 5 | Write-protected: the card's switch is set |
| 9..8 | The card's type while "ready" is 1: 1 SDSC, 2 SDHC or SDXC. 0 while "ready" is 0 |
| others | 0 |

The errors in `SD_ERROR`:

| Error | Meaning |
|---|---|
| 0 | None: the last command succeeded, or none has run since reset |
| 1 | No card is in the selected slot |
| 2 | The card is not ready: Read or Write before a successful Init |
| 3 | Timeout: the card did not answer |
| 4 | CRC: the data from the card was corrupted |
| 5 | The card reported an error |
| 6 | Write-protected: Write to a card whose switch is set |
| 7 | Out of range: Read or Write of a sector after `SD_LAST` |
| 8 | Init failed |

**The buffer.** It is 128 words, and each word holds 4 bytes, little-endian: byte 4n of the sector is bits 7..0 of word n, and byte 4n + 3 is bits 31..24. A program sees the buffer 8 words at a time, through `SD_BUF0`–`SD_BUF7`, and `SD_CHUNK` chooses which 8. FAT is little-endian, so a 32-byte directory entry is one chunk, with the file's size in `SD_BUF7`, and entry i of a sector of the FAT is word i mod 8 of chunk i / 8. For code from the wasm translator, a word of the buffer is one `i32` ([translator/WASM.md](../translator/WASM.md)).

**No side effects on a read.** A read of any of the 16 words changes nothing, and a write does only what the table says. So the debug link reads and writes them as the processor does, with no rule of its own ([DEBUG.md §3](DEBUG.md#3-requests-and-answers)). A host reads a sector with 16 writes of `SD_CHUNK`, each followed by a read of the 8 words at `SD_BUF0`, and writes one likewise.

**Busy.**

- A program waits for busy to be 0 before it starts a command, and after one.
- A read of `SD_CSR` after the write that starts a command returns busy 1 until the command has ended. When busy reads 0, the buffer, `SD_ERROR`, and the status are those of the finished command.
- In the emulator, and in the simulation of the FPGA core, a command ends in the write that starts it, so busy never reads 1. On a board a Read takes about a millisecond, and an Init up to hundreds. A program that waits for busy runs the same on both.
- While busy is 1, the buffer is not defined, and a write to `SD_CSR`, `SD_LBA`, `SD_SELECT`, or `SD_BUF0`–`SD_BUF7` is ignored. `SD_CHUNK` can be written at any time, and no command changes it.
- Every command ends: the controller has a timeout for each step of the protocol, so busy does not stay 1.

**Commands.**

- Each command sets `SD_ERROR`, and the error bit is 1 when `SD_ERROR` is not 0.
- A command checks, in this order, that a card is in the selected slot (error 1); for Read and Write, that the card is ready (2) and that `SD_LBA` is at most `SD_LAST` (7); and for Write, that the card is not write-protected (6). A command that fails a check changes nothing else.
- An Init that finds a card clears "changed". If it succeeds, it sets "ready" to 1, the type, and `SD_LAST`; if it fails, "ready" is 0.
- Read and Write leave "ready" as it is. A failed Read leaves the buffer not defined. A failed Write leaves the sector on the card not defined.
- `SD_LBA` is always a sector number, also for an SDSC card, whose byte addresses the controller computes. `SD_LAST` is the last sector's number, not the count, so that a card of 2 TB, 2³² sectors, fits.

**Slots.**

- `SD_SLOTS` is the number of slots that the system has, fixed when it is built, whether or not a card is in them. An empty slot counts.
- A change of `SD_SELECT` takes effect at once. The status then shows the other slot, and "ready" is 0 until an Init of it, as the slots may share one controller. A slot at or above `SD_SLOTS` shows no card, and every command on it fails with error 1.
- When a card is taken out, "ready" falls to 0. When one is put in, "changed" is set. Both stay so until the next Init of the slot.
- A slot whose card detect does not work shows "present" as 1 at all times, "write-protected" as 0, and "changed" only after reset. A command on it with no card fails with error 3 or 8. §8 says which systems have such a slot.

**Reset.** Reset, which a start of the processor gives the devices ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)), lets a Write that has begun finish, so that no sector on the card is torn, and abandons any other command. The Write finishes on its own slot, and reports nothing. Then, or when that Write ends, the controller is idle, with slot 0 selected, `SD_CHUNK`, `SD_LBA`, and `SD_ERROR` 0, the error bit and "ready" 0, and "changed" set if a card is present. The buffer is not defined. Busy may read 1 after reset for as long as the Write takes, so a program waits for busy before its first command, as before any other.

**The debug link.** Nothing but reset affects the controller. It runs while the processor is held, paused, or halted, so a host can read and write the card then. A host that does so while a program is paused can restore `SD_CHUNK`, `SD_LBA`, `SD_SELECT`, and the buffer, which it can read first, as reads have no side effects. It cannot restore `SD_ERROR` and the error bit, which its own commands overwrite, nor "ready" and "changed", which an Init or a change of slot changes. So a host that uses the card of a paused program uses only the program's slot, does no Init, waits for the program's command to end before it starts, and lets its own end before the program goes on. While the processor is held or has halted, a host may do anything, since the program starts again from reset.

**Interrupts.** An interrupt or NMI service routine does not use the card. `SD_CHUNK`, `SD_LBA`, `SD_SELECT`, the buffer, and a running command are shared with the program it interrupts.

**The emulator.** `niceemu --sd0 FILE --sd1 FILE` gives a slot an image file, which holds the card's sectors in order. The emulator refuses to start with an image that is empty, or whose size is not a multiple of 512 bytes.

- The emulator always has 2 slots, as the MEGA65 does, so `SD_SLOTS` is 2 with any images or none, and `--sd1` alone puts a card in slot 1 and leaves slot 0 empty.
- A card is present when its image is given. Its type is 2, SDHC, `SD_LAST` is the image's size in sectors minus 1, and it is write-protected when the file cannot be written.
- "Changed" is set at the start, so a program does the Init that it does on a board. There is no way to take a card out.
- A Write goes to the file at once.

Without an image, a program sees what it sees on a MEGA65 with both slots empty: `SD_SLOTS` is 2, "present" is 0, and every command fails with error 1.

## 6. Network station

A system that serves the debug link over TCP ([DEBUG.md §7](DEBUG.md#7-transports)) maps the registers of its network station at `0xFFFFFFB0`–`0xFFFFFFBF`. A program sees the station's addresses, its counts of frames, and the state of the link. A board fills them from its Ethernet hardware. The emulator has no Ethernet, and gives each word a meaning it can keep.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFFB0` | `NET_IP` | the IP address, the first byte in bits 31..24: `0xC0A80141` is 192.168.1.65 | sets the IP address |
| `0xFFFFFFB1` | `NET_MAC_HI` | the first two bytes of the MAC address in bits 15..0, and 0 in bits 31..16 | sets them to bits 15..0 |
| `0xFFFFFFB2` | `NET_MAC_LO` | the last four bytes of the MAC address, the first in bits 31..24 | sets them |
| `0xFFFFFFB3` | `NET_RX_GOOD` | the good frames received | is ignored |
| `0xFFFFFFB4` | `NET_RX_BAD` | the bad frames received, and the good ones that were dropped | is ignored |
| `0xFFFFFFB5` | `NET_TX` | the frames sent | is ignored |
| `0xFFFFFFB6` | `NET_STATUS` | the status below | is ignored |
| `0xFFFFFFB7`–`0xFFFFFFBF` | | 0 | is ignored |

`NET_STATUS`:

| Bits | What |
|---|---|
| 31 | 1 while a host is connected to the link over TCP |
| 30..16 | 0 |
| 15..0 | the TCP port on which the system serves the link |

**On a board.** The station answers ARP requests for its IP address and pings to it, and serves the link on the port of `NET_STATUS`. With the IP address at 0 it answers nothing, so a board on a network stays silent until a program or the link gives it an address. The counts wrap at 2^32. The board's documentation says what makes a frame good or bad. The frames that the station does not serve go to the port of §7, if the system has one, and are dropped otherwise.

**A write of an address.** On a board, a write to `NET_IP`, `NET_MAC_HI`, or `NET_MAC_LO` breaks the connection of a host, and a reply that is going out.

**Reset.** A reset of the system sets the IP address to 0, the MAC address to 02:4E:49:43:45:00, and the counts to 0. Unlike the other devices, the station is not reset by a start of the processor ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)), nor by the link's clear, so that a host connected over TCP keeps its connection through a start, and a program finds the addresses that an earlier one set. The MAC address is a locally administered one. Two systems on one network need different ones.

**Interrupts.** The station raises no interrupt.

**The emulator.**

- `NET_IP`, `NET_MAC_HI`, and `NET_MAC_LO` are registers with the reset values above, which keep what a program writes. The emulator serves the link where `--link` says, whatever `NET_IP` holds, and a write closes no connection.
- The counts read 0, also for the frames of §7.
- `NET_STATUS` gives the port of `--link`, and bit 31 while a host is connected to it. Without `--link` it reads 0.
- The emulator's reset is its launch: the registers keep their values for as long as it runs.

Bit 31 of `NET_STATUS` changes when a host connects, which depends on the host, so a program whose result depends on it does not run the same each time.

## 7. Ethernet frames

A system with a network station (§6) may map a port for Ethernet frames at `0xFFFFFFC0`–`0xFFFFFFCF`, through which a program sends and receives frames of its own. A program that does DHCP, DNS, NTP, or TFTP builds and parses the frames itself. The station keeps the frames it serves: the ARP requests for its IP address, the pings to it, and the TCP of the debug link. Every other frame that the station receives for its MAC address, or for everyone, goes to the program.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFFC0` | `ETH_CSR` | the status below | sets "enabled" to bit 0 |
| `0xFFFFFFC1` | `ETH_RX_LEN` | the length in bytes of the frame at the head of the queue, and 0 when the queue is empty | releases that frame |
| `0xFFFFFFC2` | `ETH_TX_LEN` | 0 | sends the first N bytes of the frame in the send buffer, where N is the value written |
| `0xFFFFFFC3` | `ETH_CHUNK` | the chunk in bits 5..0, and the buffer in bit 8 | sets them to bits 5..0 and bit 8 |
| `0xFFFFFFC4` | `ETH_DROPPED` | the frames dropped because the queue was full | is ignored |
| `0xFFFFFFC5`–`0xFFFFFFC7` | | 0 | is ignored |
| `0xFFFFFFC8`–`0xFFFFFFCF` | `ETH_BUF0`–`ETH_BUF7` | word 8·c + k of the buffer that bit 8 of `ETH_CHUNK` selects, where c is the chunk and k is 0 to 7 | writes that word of the send buffer |

The status, from a read of `ETH_CSR`:

| Bit | What |
|---|---|
| 0 | Enabled |
| 1 | A frame waits: `ETH_RX_LEN` is not 0 |
| 2 | Busy: a frame is being sent |
| 31..3 | 0 |

A program writes 0 to bits 31..1 of `ETH_CSR`. Bit 1 is reserved for a receive interrupt.

**Enabled.** While "enabled" is 0, the queue is empty, no frame enters it, and a write of `ETH_TX_LEN` sends nothing, so a program that does not use the network sees no frame and sends none. The station answers as it does without the port. A write of `ETH_CSR` with bit 0 at 0 empties the queue and sets `ETH_DROPPED` to 0. So a program that sets "enabled" gets no frame from before.

**The queue.** It holds 4 frames, on every system. A frame enters it at its tail when the station has received the whole frame. When the queue is full, the frame is dropped, and `ETH_DROPPED` counts it. `ETH_RX_LEN` gives the length of the frame at the head, and a write of `ETH_RX_LEN`, of any value, releases it, so the next one takes its place. A write of `ETH_RX_LEN` while the queue is empty is ignored. A frame is 14 to 1514 bytes long, without the FCS. The station drops longer frames, and frames with a bad FCS, before the queue. `ETH_DROPPED` wraps at 2^32.

**Sending.** A write of N to `ETH_TX_LEN`, with N from 14 to 1514, sends the first N bytes of the frame in the send buffer, and busy reads 1 until the frame is sent. The station adds the FCS, and pads a frame of fewer than 60 bytes with zeros to 60. A write of any other N sends nothing. While busy is 1, a write of `ETH_TX_LEN` or of the send buffer is ignored. A program waits for busy to be 0 before it writes the next frame. In the emulator, and in the simulation of the FPGA core, a frame is sent in the write of `ETH_TX_LEN`, so busy never reads 1.

**The buffers.** There are two: the frame at the head of the queue, and the send buffer, which bit 8 of `ETH_CHUNK` selects, 0 for the queue and 1 for the send buffer. A program sees the selected one 8 words at a time, through `ETH_BUF0`–`ETH_BUF7`, and bits 5..0 of `ETH_CHUNK` choose which 8. A frame with its offset is at most 379 words, so it fits in chunks 0 to 47. A chunk of 48 to 63 reads 0 and ignores writes, as does the queue's buffer while the queue is empty. A write to the queue's buffer is ignored. A copy of a received frame into the send buffer changes bit 8 for each chunk.

Each word holds 4 bytes, big-endian, in network order as `NET_IP` has them: byte 4n of the buffer is bits 31..24 of word n, and byte 4n + 3 is bits 7..0. A frame starts at byte 2 of its buffer. Bytes 0 and 1 are not part of it: they read 0 in the queue's buffer, and the station does not send them from the send buffer. The lengths do not count them. With the offset, the fields of a frame fall on words:

| Word | What |
|---|---|
| 0 | The destination MAC address's first two bytes in bits 15..0, as `NET_MAC_HI` has them |
| 1 | Its last four bytes, as `NET_MAC_LO` has them |
| 2, 3 | The source MAC address, and the EtherType in bits 15..0 of word 3 |
| 4 | The first word of an IPv4 header |
| 7, 8 | The IPv4 source and destination addresses, as `NET_IP` has them |
| 9 | The UDP source port in bits 31..16 and the destination port in bits 15..0 |
| 11 | The first word of a UDP payload |

In the queue's buffer, the bytes after the frame's last byte are not defined. The send buffer keeps what a program writes to it, also through a start of the processor. It is 0 after a reset of the system.

**No side effects on a read.** A read of any of the 16 words changes nothing. So the debug link reads and writes them as the processor does ([DEBUG.md §3](DEBUG.md#3-requests-and-answers)). A host that reads the frames of a paused program restores `ETH_CHUNK` before the program goes on. A write of `ETH_CSR`, `ETH_RX_LEN`, or `ETH_TX_LEN` changes what the program sees.

**Reset.** Reset, which a start of the processor gives the devices ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)), sets "enabled" to 0, empties the queue, and sets `ETH_DROPPED` and `ETH_CHUNK` to 0. A frame being sent finishes first, so busy may read 1 after reset. The station is not reset (§6), and goes on answering on its own.

**Interrupts.** The port raises no interrupt. An interrupt or NMI service routine does not use it, as `ETH_CHUNK` and the queue are shared with the program it interrupts.

**The emulator.** The emulator has no Ethernet. Its frames come from a file or a UDP socket, and go to a file or the socket, with these options:

- `--eth-in FILE`: the frames that the station receives, one per line, each byte as two hex digits. Spaces between bytes are allowed, a `#` starts a comment that runs to the end of the line, and a line with no bytes is skipped. A line may start with `N:`, a decimal number and a colon: the frame then waits until the program has sent N frames since the emulator started. The lines are taken in order. At each write of `ETH_CSR` that sets "enabled" from 0 to 1, and each write of `ETH_TX_LEN` that sends a frame, every next line whose N has been reached arrives at the station, which serves it or passes it to the queue, where it is dropped and counted if the queue is full. So a run is the same each time, and a test fills the queue on purpose with lines that enter at once.
- `--eth-out FILE`: the frames sent, the program's and the station's, one per line, each byte as two hex digits with a space between bytes, without the padding to 60 bytes. A line of `--eth-out` is a valid line of `--eth-in`.
- `--eth-udp [ADDR:]PORT` and `--eth-peer [ADDR:]PORT`, which go together: each frame travels as one UDP datagram, as QEMU's `-netdev socket,udp=` does. The emulator receives on PORT of ADDR and sends to the peer's, with ADDR 127.0.0.1 by default for both, written as for `--link` ([DEBUG.md §7](DEBUG.md#7-transports)). A datagram from any address arrives at the station when the emulator next looks, so a run over the socket is not the same each time. A datagram of fewer than 14 or more than 1514 bytes is dropped. Frames sent go to the peer padded to 60 bytes, as on the wire. Two emulators, each the other's peer, are two systems on one network. On Linux, `emulator/tools/nicetap.py` is a peer that joins the socket to a TAP device, and so to a real network ([emulator/README.md](../emulator/README.md#a-real-network)).

The emulator refuses to start with a line of `--eth-in` that is not hex, or that has fewer than 14 or more than 1514 bytes. Without `--eth-in` and `--eth-udp`, no frame enters the queue. Without `--eth-out` and `--eth-udp`, the frames sent go nowhere.

The emulator's station serves the frames that a board's does, by the same rules, before the queue. While `NET_IP` is not 0, it answers an ARP request for `NET_IP` with an ARP reply, and a ping to it with an echo reply, which go out as frames the program sends do, but do not count toward N. It keeps TCP to `NET_IP` and the port of `NET_STATUS`, while that is not 0. It passes a frame to the queue only if its destination is `NET_MAC_HI` and `NET_MAC_LO`, or `FF:FF:FF:FF:FF:FF`, and drops the others without counting them.

## 8. Systems built on the FPGA core

A board that wraps the FPGA core, such as [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65), may differ from the emulator in the points below. Its own README has the details.

- **Reserved words.** `0xFFFFFF03`–`0xFFFFFF0F`, `0xFFFFFF80`–`0xFFFFFF9F`, and `0xFFFFFFD0`–`0xFFFFFFFF` are reserved for I/O. A board may use them if it documents them. A system without the clock of §10 has nothing at `0xFFFFFF46`–`0xFFFFFF49`. The emulator treats all these words as ordinary memory for data accesses, and only instruction fetches read 0 ([ISA.md §8.3](ISA.md)). NiceMonMEGA65 uses `0xFFFFFF80`–`0xFFFFFF8F` for its screen registers, `0xFFFFFF90`–`0xFFFFFF9F` for its board's devices, and `0xFFFFFFE0`–`0xFFFFFFFF` for the debug registers of the link (**Debug link** below). The link's registers of version 7 start at `0xFFFFFFD0`.
- **Screen.** A board's screen may be larger than the emulator's 80×25. NiceMonMEGA65's has up to 32K words. The color format of §1.1 applies unchanged. The display offset belongs to the board. The emulator's window draws the cursor from the board's cursor registers (§1.4), but has no offset.
- **Console input.** A UART or a keyboard feeds the same console at `0xFFFFFF00`, with the same bits (§1.2). A break on the UART may end the line's input: the UART's bytes are then dropped until the next start, and a read returns `0x200` once the FIFO is empty, but the keyboard's bytes still go into the FIFO, and a read returns them. So a monitor that a host leaves keeps running on the keyboard, and a program that reads until the end still ends with the host's input. A keyboard sends no break. A board's keyboard gives the bytes of the window's keys (§1.5), and may have more keys.
- **NMI.** No device of this file raises NMI. The debug link's request is a source of NMI ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)), and the only one of the emulator but for `--nmi`, its own source, which goes first. A board may have more, such as a button or a watchdog, and merges them into the core's one NMI port, each request merging only with its own (ISA.md §7.1). NiceMonMEGA65 does not wire the link's request yet (MJoergen/NiceMonMEGA65#106).
- **Receive interrupt.** A system may leave out the receive interrupt of §1.9. Then it has nothing at `0xFFFFFF02`, and the timer is its only source of IRQ. A board raises the request from its input FIFO, so one request covers its keyboard and its UART. NiceMonMEGA65 does not have it yet (MJoergen/NiceMonMEGA65#104).
- **Input FIFO.** A system's input FIFO may lose bytes. NiceMonMEGA65 drops a UART byte that arrives when the FIFO is full, with the link's `o` notice ([DEBUG.md §4](DEBUG.md#4-notices)), or after a break. Over a transport with flow control, such as TCP, the byte waits up to 50 ms for room first ([DEBUG.md §1](DEBUG.md#1-the-byte-stream)). Input that arrives while the processor is held or has halted is dropped, as by `niceemu --link`, and input that arrives while it is paused waits in the FIFO ([DEBUG.md §1](DEBUG.md#1-the-byte-stream)). A keyboard byte waits until the FIFO has room for two, so that a UART byte still finds room.
- **SD card slots.** A system without an SD card controller has nothing at `0xFFFFFFA0`–`0xFFFFFFAF`. The MEGA65 has 2 slots: the microSD slot at the back, and the full-size slot underneath, the only one with write protect, whose card detect does not work on the R3 (§5). NiceMonMEGA65 plans to number them 0 and 1 (MJoergen/NiceMonMEGA65#55). The Nexys4DDR has 1, its microSD slot.
- **Network station.** A system that serves the debug link only on a UART, or not at all, has nothing at `0xFFFFFFB0`–`0xFFFFFFBF`. NiceMonMEGA65 has its station at `0xFFFFFF98`–`0xFFFFFF9D` today, with the same registers in another order and no status word, until it follows §6.
- **Ethernet frames.** A system without a network station, or without the port, has nothing at `0xFFFFFFC0`–`0xFFFFFFCF`. NiceMonMEGA65 plans the port (#121), with the network stack in its ROM.
- **Clock.** A system may leave out the clock of §10, or set it at a reset of the system from a source of its own (§10). The MEGA65 has a real-time clock with a battery, on I2C, from which NiceMonMEGA65 can set it. The Nexys4DDR has none, so there "set" stays 0 until a program sets the clock. NiceMonMEGA65 does not have the clock yet.
- **Byte windows.** A system may leave out the windows of §9. Then a program translated to use them does not run there. NiceMonMEGA65 has them (MJoergen/NiceMonMEGA65#90), on the MEGA65 and the Nexys4DDR, in its RAM, and in its ROM while the ROM is shown. There a read of a byte or a halfword takes a cycle more than a read of a word, for the timing at 100 MHz, which does not change the step counts. An instruction fetch from a window reads the memory that the address aliases (**Aliasing** below).
- **ROM.** A system may map a ROM at 0 that it can hide, so that a program loads at 0 as in the emulator.
- **Font.** A board that shows the screen on a display draws it from the font of §1.8, with the same font RAM, character ROM, and base, and its clear makes the font RAM and the base 0. An instruction fetch from `0xFFFE0000`–`0xFFFE3FFF` may reach the board's RAM there instead, as an alias (**Aliasing** below). NiceMonMEGA65 has the font RAM, the character ROM, and the base from its V1.6 (MJoergen/NiceMonMEGA65#71), on the MEGA65 and the Nexys4DDR; there an instruction fetch from the range reads the RAM it aliases.
- **Debug link.** A board may serve the debug link of [DEBUG.md](DEBUG.md) on its UART, or over TCP as the emulator does. Its debug registers at `0xFFFFFFD0`–`0xFFFFFFFF` are for the link only, so a program's data accesses there go to whatever the board has there otherwise.
- **Aliasing.** A system with 2^N words of RAM may decode only the low N address bits, so that the RAM repeats through the address space. Then the words of `0xFFFFFF02`–`0xFFFFFFFF` where it has no device or register alias the top words of the RAM, and the stack below `0xFFFFFF00` lands in them too. With 64K words they alias the RAM words `0xFF02`–`0xFFFF`, and `0xFFFF8000`–`0xFFFFFEFF` alias `0x8000`–`0xFEFF`; with 128K words, `0x1FF02`–`0x1FFFF` and `0x18000`–`0x1FEFF`. That is a property of the system, not a bug. A system with the byte windows of §9 decodes the top four address bits for them first. A program learns the size from the system's documentation, or from a register in the system's own range (**Reserved words** above) if it has one. NiceMonMEGA65 has 64K words on the Nexys4DDR and 128K on the MEGA65, and a read-only word at `0xFFFFFF9E` that returns the RAM's words, which reads 0 in the emulator, where there is no limit (MJoergen/NiceMonMEGA65#68).

## 9. Byte windows

The memory is word-addressed (ISA §1.1), but code translated from wasm
holds byte addresses ([translator/WASM.md](../translator/WASM.md)). Five
windows let a data access take a byte address. A data access to an
address A whose top four bits are 1 to 5 reaches the word
W = (A >> 2) AND `0x03FFFFFF` of the memory. Byte b of a word is its
bits 8b + 7 to 8b, as in WASM.md, and halfword h is its bits 16h + 15 to
16h.

| Addresses | Window | A read returns | A write changes |
|---|---|---|---|
| `0x10000000`–`0x1FFFFFFF` | Word | Word W. | Word W. |
| `0x20000000`–`0x2FFFFFFF` | Byte | Byte A mod 4 of W, zero-extended. | Byte A mod 4 of W, to bits 7..0 of the value. |
| `0x30000000`–`0x3FFFFFFF` | Signed byte | Byte A mod 4 of W, sign-extended. | As the byte window. |
| `0x40000000`–`0x4FFFFFFF` | Halfword | Halfword bit 1 of A of W, zero-extended. | Halfword bit 1 of A of W, to bits 15..0 of the value. |
| `0x50000000`–`0x5FFFFFFF` | Signed halfword | Halfword bit 1 of A of W, sign-extended. | As the halfword window. |

So a program whose linear memory starts at word `MEMBASE` reads the byte
at byte address b with `MOVE R1, @0x20000000+4*MEMBASE[R2]`, with b in R2.
The word window ignores bits 1..0 of A, and the halfword windows bit 0,
so a word or a halfword through a window never straddles two words.

- **One access.** A read or a write through a window is one data access
  in the sense of ISA §8.2, and the counters of §3 count it once. A
  write changes only its byte or halfword, as one access: nothing,
  an interrupt routine included, can write the word between a read and
  a write of it.
- **The first 64M words.** W is below `0x04000000`, so a window reaches
  only words `0x00000000`–`0x03FFFFFF`, and never the I/O range, the
  screen, or the font.
- **No code.** An instruction fetch from `0x10000000`–`0x5FFFFFFF`
  reads 0 in the emulator, and on a board may read the memory that the
  address aliases (§8, **Aliasing**). A store through a window into
  instructions that the processor may have fetched leaves undefined which
  value runs (ISA §8.2): the pipelined core's check of
  [MICROARCH.md §5.5](MICROARCH.md#55-self-modifying-code) compares the
  address of the store, not the address of the word.
- **Vector tables.** The read of a vector table entry is a data access
  (ISA §7.3), so a VBASE of `0x100000`–`0x5FFFFF` puts the table in a
  window, where an entry is read from another word.
- **The debug link** reads and writes through the windows as the
  processor's data accesses do. A program image has no words in
  `0x10000000`–`0x5FFFFFFF`.

The emulator and the simulated memory of `hdl/sim` have the windows. A
board has them if it says so (§8).

## 10. Clock

The emulator and the FPGA implementation map a clock of the time of day at `0xFFFFFF46`–`0xFFFFFF49`, inside the block of the performance counters (§3). It keeps the time in UTC since the Unix epoch, 1970-01-01 00:00:00, as seconds and the microseconds within the second. Time zones are for software.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF46` | `CLOCK_USEC` | the microseconds within the second, 0 to 999999, and takes a snapshot of the seconds | sets the clock to the staged seconds and this many microseconds, and sets "set" |
| `0xFFFFFF47` | `CLOCK_SEC_LO` | bits 31..0 of the seconds' snapshot | stages bits 31..0 of the seconds |
| `0xFFFFFF48` | `CLOCK_SEC_HI` | bits 63..32 of the seconds' snapshot | stages bits 63..32 of the seconds |
| `0xFFFFFF49` | `CLOCK_STATUS` | "set" in bit 0, and 0 in bits 31..1 | clears "set", whatever the value |

- **Reading.** Read `CLOCK_USEC` first, then `CLOCK_SEC_LO` and `CLOCK_SEC_HI`. The read of `CLOCK_USEC` copies the seconds into the snapshot in the same instant, so the three give one time, even when a second ends between the reads. The rule of §3 for interrupt service routines applies to this snapshot too.
- **Setting.** Write `CLOCK_SEC_LO` and `CLOCK_SEC_HI`, in either order, then `CLOCK_USEC`. The writes of the seconds only stage them, so the clock never shows a half-set time. The write of `CLOCK_USEC` sets the clock to the staged seconds and the microseconds written, at once, and sets "set" to 1. A value of 1000000 or more sets 999999. The staged seconds keep their value, so a second write of `CLOCK_USEC` sets the same second again.
- **"Set"** says that the clock holds a time: 0 after a reset of the system, and 1 once a program has set the clock, or the system has set it from a source of its own. A program that finds it 0 does not know the time. `time()` of the C library then returns -1.
- **It always runs.** The clock counts on while the processor is held, paused, halted, or waiting, and a start over the debug link (DEBUG.md §6) leaves it, its snapshot, the staged seconds, and "set" as they are. Only a reset of the system, when the FPGA is loaded or the emulator starts, sets them all to 0. So the time survives a start of a program, unlike the microsecond counter of §3. The seconds wrap from `0xFFFFFFFF_FFFFFFFF` to 0.
- The FPGA implementation counts the microseconds from its clock frequency, as the microsecond counter does (§3), but in every cycle.
- The emulator reads the host's clock of the time of day, plus an offset that a write sets, so a program that sets the clock sees the time it set run on. "Set" is 1 from the start, as the host knows the time. With `--step-time`, the clock instead counts one microsecond for each step, a wait step included, from 0 with "set" 0, so that a run reads the same each time. With `--no-cycle-counter`, the four words are memory, as are those of the cycle counter and the microsecond counter.
- A system may set the clock at a reset of the system from a source of its own, such as a real-time clock with a battery, and then set "set" too (§8).

To read the time into R3:R2 seconds and R1 microseconds:

                    MOVE    R1, @CLOCK_USEC
                    MOVE    R2, @CLOCK_SEC_LO
                    MOVE    R3, @CLOCK_SEC_HI
