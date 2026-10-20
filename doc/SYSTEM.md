# NICE system: the devices

The ISA ([ISA.md](ISA.md)) reserves the I/O range `0xFFFFFF00`–`0xFFFFFFFF`
and defines no device (ISA §8.3). This file describes the devices that the
emulator ([emulator/](../emulator/README.md)) and the FPGA implementation
([hdl/](../hdl/README.md)) map into it, and the character screen that only
the emulator has. They are properties of those systems, not of the ISA. The
runtime library ([runtime/](../runtime/README.md)) has routines for them.

"ISA §8.2" refers to a section of ISA.md, and a plain "§2" to a section of
this file.

## Contents

- [Memory map](#memory-map)
- [1. Console, screen, and read counter](#1-console-screen-and-read-counter)
- [2. Math unit](#2-math-unit)
- [3. Performance counters](#3-performance-counters)
- [4. Timer](#4-timer)

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
| `0xFFFFFF80`–`0xFFFFFFFF` | 128 | Reserved for I/O. |

## 1. Console, screen, and read counter

**Screen.** The original emulator of 2004, `NICE.pm` ([REFERENCES.md](REFERENCES.md)), maps a character screen at `0x400`. The emulator in this repository maps the screen at `0xFFFF0000` instead, so that it does not overlap the code of programs longer than 1024 words. Its option `-2004` puts the screen back at `0x400` for the 2004 example programs.

**Console.** The emulator maps a console at `0xFFFFFF00`. Each write prints bits 7..0 of the word. Each data read takes the next input byte, if there is one, and returns it in bits 7..0 with bit 8 set. With no byte waiting, a read returns 0. When the emulator's input has ended, a read returns `0x200` (bit 9) instead; a UART's input never ends. The emulator reads its input from stdin, so stdin from `/dev/null` gives a console with no input. The simulation memory of the FPGA core reads a file too, as the emulator's `--input` does, and returns `0x200` without one. This repository has no UART. A system built on the FPGA core, such as the example design in [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65), maps one at the same address, with the same bits (MICROARCH.md §8). Programs use the console for input and output.

**Read counter.** At `0xFFFFFF01` the emulator and the simulation memory of the FPGA core map a read counter for tests. A data read of it returns the number of data reads of it since the last write to it, and a write sets that number. Tests use it to count the data accesses of ISA §8.2.

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

The next 16 words work on the 64-bit operands C and D. Each 64-bit value takes two words, low word first, as in ISA §9.3:

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

The emulator and the FPGA implementation map performance counters at `0xFFFFFF40`–`0xFFFFFF7F`: two 64-bit counters, and the fetch statistics of the FPGA implementation.

| Address | Name | A data read returns | A write |
|---|---|---|---|
| `0xFFFFFF40` | `CYCLE_LO` | bits 31..0 of the cycle counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF41` | `CYCLE_HI` | bits 63..32 of the cycle counter's snapshot | is ignored |
| `0xFFFFFF42` | `INSTR_LO` | bits 31..0 of the instruction counter, and takes a snapshot of it | is ignored |
| `0xFFFFFF43` | `INSTR_HI` | bits 63..32 of the instruction counter's snapshot | is ignored |
| `0xFFFFFF44`–`0xFFFFFF4F` | | 0 | is ignored |
| `0xFFFFFF50`–`0xFFFFFF7F` | | the fetch statistics (MICROARCH.md §8.1), or 0 in the emulator | as MICROARCH.md §8.1 says, or is ignored in the emulator |

- The **instruction counter** counts the instructions that have completed since reset. Every instruction counts, including one whose condition is false, a control instruction, and `INT`. An interrupt entry for IRQ or NMI does not count, because it is not an instruction. An instruction that reads `INSTR_LO` reads the number of instructions that completed before it.
- The **cycle counter** counts the clock cycles since reset. The emulator has no clock, so it counts one cycle for each instruction and each interrupt entry, that is, for each step. Its cycle counter is an approximation and differs from the FPGA implementation's.
- Reset sets both counters and both snapshots to 0. Neither counter can be written. A program measures an interval as the difference of two readings.
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
- The emulator counts one cycle for each step, as its cycle counter does (§3). The FPGA implementation counts clock cycles.
- A request keeps the vector it was raised with. If the timer's last request is still pending when it raises the next one, the two merge (ISA §7.1). So a timer whose period is shorter than its interrupt routine, or than a stretch of code with E = 0, loses requests. To keep time, read the cycle counter rather than count interrupts.
- The interrupt routine need not acknowledge the request. Taking it is enough.
- Reset sets P, COUNT, and v to 0, with no request pending.

To get an IRQ through vector table entry `0x41` every 100000 cycles, that is, every millisecond at 100 MHz:

    MOVE @TIMER_VECTOR, 0x41
    MOVE @TIMER_PERIOD, 100000
    OR   R14, R14, 0x40000000     ; E = 1
