# NICE system: the devices

The ISA ([ISA.md](ISA.md)) reserves the I/O range `0xFFFFFF00`–`0xFFFFFFFF`
and defines no device (ISA §8.3). This file describes the devices that the
emulator ([emulator/](../emulator/README.md)) and the FPGA implementation
([hdl/](../hdl/README.md)) map into it, and the character screen, window, and
keyboard that only the emulator has. They are properties of those systems, not of the ISA. The
runtime library ([runtime/](../runtime/README.md)) has routines for them.

"ISA §8.2" refers to a section of ISA.md, and a plain "§2" to a section of
this file.

## Contents

- [Memory map](#memory-map)
- [1. Console, screen, and read counter](#1-console-screen-and-read-counter)
- [2. Math unit](#2-math-unit)
- [3. Performance counters](#3-performance-counters)
- [4. Timer](#4-timer)
- [5. Systems built on the FPGA core](#5-systems-built-on-the-fpga-core)

## Memory map

The I/O range, and what the systems put in it. The emulator's own map, with
its ordinary memory, is in [emulator/README.md](../emulator/README.md).

| Address | Words | What |
|---|---|---|
| `0xFFFF0000`–`0xFFFF07CF` | 2000 | The emulator's character screen, 80×25 (§1). |
| `0xFFFFFF00` | 1 | Console (§1). |
| `0xFFFFFF01` | 1 | Read counter (§1). |
| `0xFFFFFF02`–`0xFFFFFF0F` | 14 | Reserved for I/O. |
| `0xFFFFFF10`–`0xFFFFFF1F` | 16 | Timer (§4). |
| `0xFFFFFF20`–`0xFFFFFF3F` | 32 | Math unit (§2). |
| `0xFFFFFF40`–`0xFFFFFF7F` | 64 | Performance counters (§3). |
| `0xFFFFFF80`–`0xFFFFFF82` | 3 | Reserved for I/O. The emulator's window draws its cursor from them (§1). |
| `0xFFFFFF83`–`0xFFFFFFDF` | 93 | Reserved for I/O. |
| `0xFFFFFFE0`–`0xFFFFFFFF` | 32 | Reserved for I/O. The debug link's registers are here, for the link only ([DEBUG.md §6](DEBUG.md#6-the-debug-registers)). |

## 1. Console, screen, and read counter

**Screen.** The original emulator of 2004, `NICE.pm` ([REFERENCES.md](REFERENCES.md)), maps a character screen at `0x400`. The emulator in this repository maps the screen at `0xFFFF0000` instead, so that it does not overlap the code of programs longer than 1024 words. Its option `-2004` puts the screen back at `0x400` for the 2004 example programs.

The screen word has the character in bits 7..0, the background color in bits 31..20, and the foreground color in bits 19..8. Each color is three 4-bit components, red, green, and blue, from the high bits to the low. A component `n` gives the byte `n × 0x11`, so `0x0` is no intensity and `0xF` is full. The emulator's option `--color` prints the screen with these colors as ANSI escapes. Programs that write the 2004 layout should note one difference: the 2004 IDE (`nice_ide.pl`) inverts the three foreground components, so that `0x0` is full intensity and `0xF` is none, and here it is not inverted. The emulator's option `--invert-fg` inverts it, for the 2004 programs. A word with only a character, such as `0x41`, is black on black here, but white on black in the 2004 IDE. The background is the same in both.

**Console.** The emulator maps a console at `0xFFFFFF00`. Each write prints bits 7..0 of the word. Each data read takes the next input byte, if there is one, and returns it in bits 7..0 with bit 8 set. With no byte waiting, a read returns 0. When the input has ended, a read returns `0x200` (bit 9) instead; a UART's input ends only if the system provides a break (§5). The emulator and the simulation memory of the FPGA core never return 0: a read waits for the next byte or the end of the input. Only a UART and the emulator's window (below) return 0. The emulator reads its input from stdin, so stdin from `/dev/null` gives a console with no input. The simulation memory of the FPGA core reads a file too, as the emulator's `--input` does, and returns `0x200` without one. This repository has no UART. A system built on the FPGA core, such as the example design in [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65), maps one at the same address, with the same bits (MICROARCH.md §8). Programs use the console for input and output.

**Window.** The emulator built with a window (its README says how) shows the screen in a window with its option `--window`, 1280×800 pixels, while the program runs. Each character is 16×32 pixels, from the Spleen font, with the colors above. The window shows the 2000 words of the screen and nothing else; the console still writes to stdout, or to the host with `--link`. When the program halts, the window stays, with the last screen, until it is closed. Closing the window before then ends the run. With `--link` ([DEBUG.md §7](DEBUG.md#7-transports)), the window opens when the emulator starts and stays open over every run. It shows the screen also while the processor is held, halted, or paused, so the host's writes to the screen show at once. Closing the window ends the emulator, as a signal does.

**Cursor.** The window draws a cursor from three words, numbered as the screen registers of NiceMonMEGA65 (§5). In the emulator they are ordinary memory, which the window only reads:

| Address | What |
|---|---|
| `0xFFFFFF80` | State. Bit 6 shows the cursor, bit 5 makes it blink, about twice a second, and bit 4 makes it small, the bottom 4 lines of the character. The other bits are ignored. |
| `0xFFFFFF81` | The cursor's column, 0 to 79. |
| `0xFFFFFF82` | The cursor's row, 0 to 24. |

The cursor swaps the foreground and background colors of its character. With a column or row out of range, no cursor is shown. The words are 0 at the start of a run, so the cursor is off.

**Keyboard.** With `--window`, the console reads the input of `--input`, if given, and then the keys typed into the window. It does not read stdin. A read returns 0 when no byte is waiting, as from a UART. Without `--link` it never returns `0x200`, as a keyboard has no end. A key gives these bytes, as xterm sends them:

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

With `--link`, the keys and the bytes from the host go into the one input buffer, in the order they arrive, as a board's keyboard and UART share one FIFO (§5). Keys typed while the processor is held or has halted are dropped, and keys typed while it is paused wait in the buffer, as the host's bytes do. A byte of a key waits until the buffer has room for two bytes, so that a byte from the host still finds room. When the host's input ends, a read returns `0x200` once the buffer is empty, and keys are dropped until the next start, as after a break on a board's UART.

**Pacing.** With `--window`, the emulator runs one step per microsecond, so the microsecond counter (§3) and the timer (§4) keep the time of the host's clock, and a program that waits on them runs at the speed it would on a board. The counters still count one per step. The option `--speed` sets another rate in steps per second, and `--speed 0` runs as fast as the host can.

**Read counter.** At `0xFFFFFF01` the emulator and the simulation memory of the FPGA core map a read counter for tests. A data read of it returns the number of data reads of it since the last write to it, and a write sets that number. It is 0 at the start of a run, and a reset of the processor does not clear it. Tests use it to count the data accesses of ISA §8.2.

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
| `0xFFFFFF46`–`0xFFFFFF4F` | | 0 | is ignored |
| `0xFFFFFF50`–`0xFFFFFF7F` | | the fetch statistics (MICROARCH.md §8.1), or 0 in the emulator | as MICROARCH.md §8.1 says, or is ignored in the emulator |

- The **instruction counter** counts the instructions that have completed since reset. Every instruction counts, including one whose condition is false, a control instruction, and `INT`. An interrupt entry for IRQ or NMI does not count, because it is not an instruction. An instruction that reads `INSTR_LO` reads the number of instructions that completed before it.
- The **cycle counter** counts the clock cycles since reset while the core runs, and stops when the core is held, paused, or has halted, so a reading after a halt does not change. The emulator has no clock, so it counts one cycle for each instruction and each interrupt entry, that is, for each step. Its cycle counter is an approximation and differs from the FPGA implementation's.
- The **microsecond counter** counts microseconds since reset while the core runs, and stops when the core is held, paused, or has halted, like the cycle counter. The FPGA implementation derives it from its clock frequency, so for a clock of 1 MHz or more the count after N cycles is the integer part of N·10⁶ divided by the frequency, whether or not it is a multiple of 1 MHz: it adds 1000000 to an accumulator in each cycle, and counts a microsecond and subtracts the clock frequency in hertz each time the sum reaches it. The emulator has no clock, so it counts one microsecond for each step, as its cycle counter counts one cycle. A program that needs a time in seconds divides by 1000000, whatever the board.
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

## 5. Systems built on the FPGA core

A board that wraps the FPGA core, such as [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65), may differ from the emulator in the points below. Its own README has the details.

- **Reserved words.** `0xFFFFFF02`–`0xFFFFFF0F` and `0xFFFFFF80`–`0xFFFFFFFF` are reserved for I/O. A board may use them if it documents them. The emulator treats them as ordinary memory for data accesses, and only instruction fetches read 0 ([ISA.md §8.3](ISA.md)). NiceMonMEGA65 uses `0xFFFFFF80`–`0xFFFFFF8F` for its screen registers, `0xFFFFFF90`–`0xFFFFFF9F` for its board's devices, and `0xFFFFFFE0`–`0xFFFFFFFF` for the debug registers of the link (**Debug link** below).
- **Screen.** A board's screen may be larger than the emulator's 80×25. NiceMonMEGA65's has up to 32K words. The color format of §1 applies unchanged. The display offset belongs to the board. The emulator's window draws the cursor from the board's cursor registers (§1), but has no offset.
- **Console input.** A UART or a keyboard feeds the same console at `0xFFFFFF00`, with the same bits (§1). A break on the UART may end the input, and a read then returns `0x200`. A keyboard sends no break. A board's keyboard gives the bytes of the window's keys (§1), and may have more keys.
- **Input FIFO.** A system's input FIFO may lose bytes. NiceMonMEGA65 drops a UART byte that arrives when the FIFO is full, with the link's `o` notice ([DEBUG.md §4](DEBUG.md#4-notices)), or after a break. Input that arrives while the processor is held or has halted is dropped, as by `niceemu --link`, and input that arrives while it is paused waits in the FIFO ([DEBUG.md §1](DEBUG.md#1-the-byte-stream)). A keyboard byte waits until the FIFO has room for two, so that a UART byte still finds room.
- **ROM.** A system may map a ROM at 0 that it can hide, so that a program loads at 0 as in the emulator.
- **Debug link.** A board may serve the debug link of [DEBUG.md](DEBUG.md) on its UART, as the emulator serves it over TCP. Its debug registers at `0xFFFFFFE0`–`0xFFFFFFFF` are for the link only, so a program's data accesses there go to whatever the board has there otherwise.
- **Aliasing.** A system with 64K words of RAM may decode only the low 16 address bits. Then the words of `0xFFFFFF02`–`0xFFFFFFFF` where it has no device or register alias the RAM words `0xFF02`–`0xFFFF`, and `0xFFFF8000`–`0xFFFFFEFF` alias `0x8000`–`0xFEFF`. That is a property of the system, not a bug.
