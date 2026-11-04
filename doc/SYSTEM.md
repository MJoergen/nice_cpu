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
- [2. Math unit](#2-math-unit)
- [3. Performance counters](#3-performance-counters)
- [4. Timer](#4-timer)
- [5. SD card](#5-sd-card)
- [6. Systems built on the FPGA core](#6-systems-built-on-the-fpga-core)

## Memory map

The I/O range, the screen, the font, and what the systems put in them. The emulator's own map, with
its ordinary memory, is in [emulator/README.md](../emulator/README.md).

| Address | Words | What |
|---|---|---|
| `0xFFFE0000`–`0xFFFE1FFF` | 8192 | The font RAM (§1.8). |
| `0xFFFE2000`–`0xFFFE3FFF` | 8192 | The character ROM (§1.8). |
| `0xFFFF0000`–`0xFFFF07CF` | 2000 | The emulator's character screen, 80×25 (§1.1). |
| `0xFFFFFF00` | 1 | Console (§1.2). |
| `0xFFFFFF01` | 1 | Read counter (§1.7). |
| `0xFFFFFF02`–`0xFFFFFF0F` | 14 | Reserved for I/O. |
| `0xFFFFFF10`–`0xFFFFFF1F` | 16 | Timer (§4). |
| `0xFFFFFF20`–`0xFFFFFF3F` | 32 | Math unit (§2). |
| `0xFFFFFF40`–`0xFFFFFF7F` | 64 | Performance counters (§3). `0xFFFFFF46`–`0xFFFFFF49` are reserved for the clock of the time of day (#122). |
| `0xFFFFFF80`–`0xFFFFFF82` | 3 | Reserved for I/O. The emulator's window draws its cursor from them (§1.4). |
| `0xFFFFFF83`–`0xFFFFFF85` | 3 | Reserved for I/O. |
| `0xFFFFFF86` | 1 | Reserved for I/O. The emulator's window takes its font base from it (§1.8). |
| `0xFFFFFF87`–`0xFFFFFF9F` | 25 | Reserved for I/O. |
| `0xFFFFFFA0`–`0xFFFFFFAF` | 16 | SD card (§5). |
| `0xFFFFFFB0`–`0xFFFFFFBF` | 16 | Reserved for the network station's addresses and counts (#124). |
| `0xFFFFFFC0`–`0xFFFFFFCF` | 16 | Reserved for Ethernet frames (#121). |
| `0xFFFFFFD0`–`0xFFFFFFDF` | 16 | Reserved for I/O. |
| `0xFFFFFFE0`–`0xFFFFFFFF` | 32 | Reserved for I/O. The debug link's registers are here, for the link only ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)). |

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
| The input has ended | `0x200` (bit 9). A UART's input ends only if the system provides a break (§6), and a keyboard's never ends (§1.5). |

The emulator reads its input from stdin, or from the file of its option `--input`, so stdin from `/dev/null` gives a console with no input. The simulation memory of the FPGA core reads a file too, and returns `0x200` without one. This repository has no UART. A system built on the FPGA core, such as the example design in [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65), maps one at the same address, with the same bits (MICROARCH.md §8).

### 1.3 Window

The emulator built with a window (its README says how) shows the screen in a window with its option `--window`, 1280×800 pixels, while the program runs. Each character is 16×32 pixels, from the font of §1.8, which is Spleen until the program selects a font of its own, with the colors of §1.1. The window shows the 2000 words of the screen and nothing else; the console still writes to stdout, or to the host with `--link`. When the program halts, the window stays, with the last screen, until it is closed. Closing the window before then ends the run. With `--link` ([DEBUG.md §7](DEBUG.md#7-transports)), the window opens when the emulator starts and stays open over every run. It shows the screen also while the processor is held, halted, or paused, so the host's writes to the screen show at once. Closing the window ends the emulator, as a signal does.

### 1.4 Cursor

The window draws a cursor from three words, numbered as the screen registers of NiceMonMEGA65 (§6). In the emulator they are ordinary memory, which the window only reads:

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

With `--link`, the keys and the bytes from the host go into the one input buffer, in the order they arrive, as a board's keyboard and UART share one FIFO (§6). Keys typed while the processor is held or has halted are dropped, and keys typed while it is paused wait in the buffer, as the host's bytes do. A byte of a key waits until the buffer has room for two bytes, so that a byte from the host still finds room. When the host's input ends ([DEBUG.md §7](DEBUG.md#7-transports)), the host's bytes are dropped until the next start or the next connection, but the keys still go into the buffer, as after a break on a board's UART (§6). A read then returns a byte if one waits, and `0x200` otherwise. So a program that reads until the end still ends with the host's input, and one that reads on, as a monitor does, gets the keys.

### 1.6 Pacing

With `--window`, the emulator runs as fast as the host can, as without the window. The microsecond counter (§3) keeps the host's time, so a program that waits on it waits real time, and the screen changes as the program writes it. The cycle counter and the timer count one per step (§3, §4), at the host's rate of steps, tens of megahertz, which varies, so a program that keeps time by the timer or by counting steps runs at a rate of its own. The option `--speed N` runs N steps a second for such a program: at `--speed 1000000`, one step per microsecond, the cycle counter counts at 1 MHz, and a timer period of P cycles lasts P microseconds, where on a board of 100 MHz it lasts P/100.

While a program waits, the emulator sleeps. A console read that finds no byte and a read of `TIME_LO` are idle reads, and two idle reads within 1000 steps of each other mean a wait loop. At each step of one, the emulator waits for a key or another event of the window, so a key still reaches the program at once: for up to a millisecond when the loop has read `TIME_LO` within the last 1000 steps, so that a wait on the counter ends at most a millisecond late, and for up to 10 milliseconds when it waits for a key alone. A program that polls less often than once in 1000 steps never sleeps, and runs at full speed. With `--speed`, the pace sleeps instead, and the rule does not apply.

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

The window draws every cell from the font that the base selects. While the font RAM is selected, a write to a glyph shows at the next redraw in every cell with its code, and a write to the base changes the whole screen at once. In the emulator, the base is ordinary memory that the window only reads, as the cursor's words are (§1.4), and is one of the words of NiceMonMEGA65's screen registers (§6).

The fonts are memory to every access. An instruction fetch reads them as a data read does, `--dump` and the debug link read and write them, and a write to the ROM is dropped from each. `--screen` and `--color` print the codes of the screen as text, whatever the font.

## 2. Math unit

The emulator and the FPGA implementation map a math unit, the MPU, at `0xFFFFFF20`–`0xFFFFFF3F`. It multiplies and divides 32-bit integers, and divides 64-bit integers.

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
| `0xFFFFFF2A`–`0xFFFFFF2F` | | 0 | is ignored |

The next 16 words work on the 64-bit operands C and D. Each 64-bit value takes two words, low word first, as in [ABI.md](../runtime/ABI.md):

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF30`, `0xFFFFFF31` | `C_LO`, `C_HI` | the left operand C | sets that half of C |
| `0xFFFFFF32`, `0xFFFFFF33` | `D_LO`, `D_HI` | the right operand D | sets that half of D |
| `0xFFFFFF34`, `0xFFFFFF35` | `SDIV64_Q_LO`, `SDIV64_Q_HI` | the quotient of C / D, signed | is ignored |
| `0xFFFFFF36`, `0xFFFFFF37` | `SDIV64_R_LO`, `SDIV64_R_HI` | the remainder of C / D, signed | is ignored |
| `0xFFFFFF38`, `0xFFFFFF39` | `UDIV64_Q_LO`, `UDIV64_Q_HI` | the quotient of C / D, unsigned | is ignored |
| `0xFFFFFF3A`, `0xFFFFFF3B` | `UDIV64_R_LO`, `UDIV64_R_HI` | the remainder of C / D, unsigned | is ignored |
| `0xFFFFFF3C`–`0xFFFFFF3F` | | 0 | is ignored |

- Each result depends only on the operands of its half, A and B or C and D, as they are when it is read. A read has no side effect, so the results can be read in any order and any number of times.
- Signed operations treat the operands as two's complement. A signed product is exact in 64 bits.
- A signed quotient is rounded toward zero, and a signed remainder has the sign of the dividend, so A = Q · B + R and C = Q · D + R. This is C's `/` and `%`, and wasm's `div_s` and `rem_s`.
- Division by zero gives a quotient of all ones and a remainder equal to the dividend, signed and unsigned: Q = `0xFFFFFFFF` and R = A, or Q = `0xFFFFFFFF_FFFFFFFF` and R = C.
- The signed division of the most negative number by −1 gives Q = the most negative number and R = 0. That is `0x80000000 / 0xFFFFFFFF` = `0x80000000` for A and B, and −2⁶³ / −1 = −2⁶³ for C and D.
- Reset sets A, B, C, and D to 0.

These are RISC-V's results for the two special cases. Software never needs to wait for a result. The FPGA implementation starts a new computation at each write to an operand, which may take many cycles, and holds off the acknowledge of a read of a result until the result is ready.

A use of the MPU takes several instructions, and an interrupt may come between them. An interrupt service routine that uses the MPU must therefore read the operands it changes first, and write them back before `RTI`. The results depend only on the operands, so that restores the whole state.

## 3. Performance counters

The emulator and the FPGA implementation map performance counters at `0xFFFFFF40`–`0xFFFFFF7F`: three 64-bit counters, and the fetch statistics of the FPGA implementation.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF40` | `CYCLE_LO` | bits 31..0 of the cycle counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF41` | `CYCLE_HI` | bits 63..32 of the cycle counter's snapshot | is ignored |
| `0xFFFFFF42` | `INSTR_LO` | bits 31..0 of the instruction counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF43` | `INSTR_HI` | bits 63..32 of the instruction counter's snapshot | is ignored |
| `0xFFFFFF44` | `TIME_LO` | bits 31..0 of the microsecond counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF45` | `TIME_HI` | bits 63..32 of the microsecond counter's snapshot | is ignored |
| `0xFFFFFF46`–`0xFFFFFF49` | | 0, reserved for the clock of the time of day (#122) | is ignored |
| `0xFFFFFF4A`–`0xFFFFFF4F` | | 0 | is ignored |
| `0xFFFFFF50`–`0xFFFFFF7F` | | the fetch statistics (MICROARCH.md §8.1), or 0 in the emulator | as MICROARCH.md §8.1 says, or is ignored in the emulator |

- The **instruction counter** counts the instructions that have completed since reset. Every instruction counts, including one whose condition is false, a control instruction, and `INT`. An interrupt entry for IRQ or NMI does not count, because it is not an instruction. An instruction that reads `INSTR_LO` reads the number of instructions that completed before it.
- The **cycle counter** counts the clock cycles since reset while the core runs, and stops when the core is held, paused, or has halted, so a reading after a halt does not change. The emulator has no clock, so it counts one cycle for each instruction and each interrupt entry, that is, for each step. Its cycle counter is an approximation and differs from the FPGA implementation's.
- The **microsecond counter** counts microseconds since reset while the core runs, and stops when the core is held, paused, or has halted, like the cycle counter. The FPGA implementation derives it from its clock frequency, so for a clock of 1 MHz or more the count after N cycles is the integer part of N·10⁶ divided by the frequency, whether or not it is a multiple of 1 MHz: it adds 1000000 to an accumulator in each cycle, and counts a microsecond and subtracts the clock frequency in hertz each time the sum reaches it. The emulator counts the host's monotonic time, without the time the host sleeps, in microseconds since reset, less the time the processor was held, paused, or halted. A read of `TIME_LO` reads the host's clock. So a program that waits on the counter waits real time, as on a board, with or without the window and at any speed (§1.6). A console read that waits for input counts as running, as a board polls meanwhile. With the option `--step-time`, the emulator instead counts one microsecond for each step, as its cycle counter counts one cycle, so that a run counts the same each time. A program that needs a time in seconds divides by 1000000, whatever the board.
- In the emulator, the cycle counter and the microsecond counter have no fixed ratio, unless with `--step-time`. A program that divides one by the other gets the rate at which the host runs steps, which varies from run to run.
- Reset sets all three counters and their snapshots to 0. No counter can be written. A program measures an interval as the difference of two readings.
- A counter wraps from `0xFFFFFFFF_FFFFFFFF` to 0. At one count per cycle at 100 MHz that takes over 5000 years.
- The **fetch statistics** count what the instruction fetch of the pipelined FPGA core does in each cycle, to judge the size of its buffer. They depend on the core, so MICROARCH.md §8.1 describes them. The emulator has none: their words read 0 and ignore writes, and are not memory.

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
- The emulator counts one cycle for each step, as its cycle counter does (§3). The FPGA implementation counts clock cycles while the core runs. Like the cycle counter, COUNT stops when the core is held or has halted.
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
- A slot whose card detect does not work shows "present" as 1 at all times, "write-protected" as 0, and "changed" only after reset. A command on it with no card fails with error 3 or 8. §6 says which systems have such a slot.

**Reset.** Reset, which a start of the processor gives the devices ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)), lets a Write that has begun finish, so that no sector on the card is torn, and abandons any other command. The Write finishes on its own slot, and reports nothing. Then, or when that Write ends, the controller is idle, with slot 0 selected, `SD_CHUNK`, `SD_LBA`, and `SD_ERROR` 0, the error bit and "ready" 0, and "changed" set if a card is present. The buffer is not defined. Busy may read 1 after reset for as long as the Write takes, so a program waits for busy before its first command, as before any other.

**The debug link.** Nothing but reset affects the controller. It runs while the processor is held, paused, or halted, so a host can read and write the card then. A host that does so while a program is paused can restore `SD_CHUNK`, `SD_LBA`, `SD_SELECT`, and the buffer, which it can read first, as reads have no side effects. It cannot restore `SD_ERROR` and the error bit, which its own commands overwrite, nor "ready" and "changed", which an Init or a change of slot changes. So a host that uses the card of a paused program uses only the program's slot, does no Init, waits for the program's command to end before it starts, and lets its own end before the program goes on. While the processor is held or has halted, a host may do anything, since the program starts again from reset.

**Interrupts.** An interrupt or NMI service routine does not use the card. `SD_CHUNK`, `SD_LBA`, `SD_SELECT`, the buffer, and a running command are shared with the program it interrupts.

**The emulator.** `niceemu --sd0 FILE --sd1 FILE` gives a slot an image file, which holds the card's sectors in order. The emulator refuses to start with an image that is empty, or whose size is not a multiple of 512 bytes.

- The emulator always has 2 slots, as the MEGA65 does, so `SD_SLOTS` is 2 with any images or none, and `--sd1` alone puts a card in slot 1 and leaves slot 0 empty.
- A card is present when its image is given. Its type is 2, SDHC, `SD_LAST` is the image's size in sectors minus 1, and it is write-protected when the file cannot be written.
- "Changed" is set at the start, so a program does the Init that it does on a board. There is no way to take a card out.
- A Write goes to the file at once.

Without an image, a program sees what it sees on a MEGA65 with both slots empty: `SD_SLOTS` is 2, "present" is 0, and every command fails with error 1.

## 6. Systems built on the FPGA core

A board that wraps the FPGA core, such as [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65), may differ from the emulator in the points below. Its own README has the details.

- **Reserved words.** `0xFFFFFF02`–`0xFFFFFF0F`, `0xFFFFFF80`–`0xFFFFFF9F`, and `0xFFFFFFD0`–`0xFFFFFFFF` are reserved for I/O. A board may use them if it documents them. The blocks that the memory map reserves for a device, `0xFFFFFFB0`–`0xFFFFFFCF` and `0xFFFFFF46`–`0xFFFFFF49`, hold that device or nothing. The emulator treats all these words as ordinary memory for data accesses, and only instruction fetches read 0 ([ISA.md §8.3](ISA.md)). NiceMonMEGA65 uses `0xFFFFFF80`–`0xFFFFFF8F` for its screen registers, `0xFFFFFF90`–`0xFFFFFF9F` for its board's devices, and `0xFFFFFFE0`–`0xFFFFFFFF` for the debug registers of the link (**Debug link** below).
- **Screen.** A board's screen may be larger than the emulator's 80×25. NiceMonMEGA65's has up to 32K words. The color format of §1.1 applies unchanged. The display offset belongs to the board. The emulator's window draws the cursor from the board's cursor registers (§1.4), but has no offset.
- **Console input.** A UART or a keyboard feeds the same console at `0xFFFFFF00`, with the same bits (§1.2). A break on the UART may end the line's input: the UART's bytes are then dropped until the next start, and a read returns `0x200` once the FIFO is empty, but the keyboard's bytes still go into the FIFO, and a read returns them. So a monitor that a host leaves keeps running on the keyboard, and a program that reads until the end still ends with the host's input. A keyboard sends no break. A board's keyboard gives the bytes of the window's keys (§1.5), and may have more keys.
- **Input FIFO.** A system's input FIFO may lose bytes. NiceMonMEGA65 drops a UART byte that arrives when the FIFO is full, with the link's `o` notice ([DEBUG.md §4](DEBUG.md#4-notices)), or after a break. Over a transport with flow control, such as TCP, the byte waits up to 50 ms for room first ([DEBUG.md §1](DEBUG.md#1-the-byte-stream)). Input that arrives while the processor is held or has halted is dropped, as by `niceemu --link`, and input that arrives while it is paused waits in the FIFO ([DEBUG.md §1](DEBUG.md#1-the-byte-stream)). A keyboard byte waits until the FIFO has room for two, so that a UART byte still finds room.
- **SD card slots.** A system without an SD card controller has nothing at `0xFFFFFFA0`–`0xFFFFFFAF`. The MEGA65 has 2 slots: the microSD slot at the back, and the full-size slot underneath, the only one with write protect, whose card detect does not work on the R3 (§5). NiceMonMEGA65 plans to number them 0 and 1 (MJoergen/NiceMonMEGA65#55). The Nexys4DDR has 1, its microSD slot.
- **ROM.** A system may map a ROM at 0 that it can hide, so that a program loads at 0 as in the emulator.
- **Font.** A board that shows the screen on a display draws it from the font of §1.8, with the same font RAM, character ROM, and base, and its clear makes the font RAM and the base 0. An instruction fetch from `0xFFFE0000`–`0xFFFE3FFF` may reach the board's RAM there instead, as an alias (**Aliasing** below). NiceMonMEGA65 draws from Spleen alone today, and has the font RAM and the base planned (MJoergen/NiceMonMEGA65#71). Until then, the range aliases its RAM, so a program that writes the font RAM there writes the RAM it aliases.
- **Debug link.** A board may serve the debug link of [DEBUG.md](DEBUG.md) on its UART, or over TCP as the emulator does. Its debug registers at `0xFFFFFFE0`–`0xFFFFFFFF` are for the link only, so a program's data accesses there go to whatever the board has there otherwise.
- **Aliasing.** A system with 2^N words of RAM may decode only the low N address bits, so that the RAM repeats through the address space. Then the words of `0xFFFFFF02`–`0xFFFFFFFF` where it has no device or register alias the top words of the RAM, and the stack below `0xFFFFFF00` lands in them too. With 64K words they alias the RAM words `0xFF02`–`0xFFFF`, and `0xFFFF8000`–`0xFFFFFEFF` alias `0x8000`–`0xFEFF`; with 128K words, `0x1FF02`–`0x1FFFF` and `0x18000`–`0x1FEFF`. That is a property of the system, not a bug. A program learns the size from the system's documentation, or from a register in the system's own range (**Reserved words** above) if it has one. NiceMonMEGA65 has 64K words on the Nexys4DDR and 128K on the MEGA65, and a read-only word at `0xFFFFFF9E` that returns the RAM's words, which reads 0 in the emulator, where there is no limit (MJoergen/NiceMonMEGA65#68).
