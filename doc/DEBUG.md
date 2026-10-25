# NICE system: the debug link

A system with a NICE processor can have a debug link. A host uses it to
read and write the memory, to load and start a program, and to learn when
the program halts. The link shares one byte stream with the console
(SYSTEM.md §1), so one serial cable carries both. The emulator
([emulator/](../emulator/README.md)) serves the link over TCP, and
[NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65) over its debug
UART. Both follow this file, so one host tool works with either.

The link is a property of the system, not of the ISA. This is version 2 of
the protocol. Its run control is the pause (§6). It has no step or
breakpoints yet.

"SYSTEM.md §1" refers to a section of SYSTEM.md, and a plain "§2" to a
section of this file.

## Contents

- [1. The byte stream](#1-the-byte-stream)
- [2. Packets](#2-packets)
- [3. Requests and answers](#3-requests-and-answers)
- [4. Notices](#4-notices)
- [5. Errors and timeouts](#5-errors-and-timeouts)
- [6. The debug registers](#6-the-debug-registers)
- [7. Transports](#7-transports)
- [8. An example](#8-an-example)

## 1. The byte stream

The byte `0xFF` is the escape byte, ESC. It starts a packet in either
direction. Every other byte is a console byte.

- From the host, a console byte goes to the program's input, at
  `0xFFFFFF00`. ESC ESC is the console byte `0xFF`.
- From the system, a console byte is one that the program wrote to
  `0xFFFFFF00`. The system sends a written `0xFF` as ESC ESC.

So the console is 8-bit clean, and a terminal that knows nothing of the
link shows the program's output almost unchanged.

Console bytes from the host reach the program while it runs or is paused.
While the processor is held or halted (§6), and after the end of the input
(§7), they are dropped. A paused processor keeps them in the input buffer,
and the program reads them when it goes on. A console byte that
arrives while the program's input buffer is full is lost, and the system
sends an overflow notice (§4). A host avoids the loss by sending no more
bytes than the free-space register (§6) allows.

The checksum of §2 covers only packets. Console bytes have no check.

## 2. Packets

A packet is ESC, a tag, a payload, the character `#`, and a checksum:

    ESC tag payload # cc

- The tag is one ASCII letter. Requests have uppercase tags, and answers
  and notices lowercase ones.
- The payload is ASCII hex digits, in fields of fixed width. An address and
  a data word are 8 digits, a count is 4, and a version, a reason, a tag, or
  an error code is 2. Each field is big-endian, as it is written.
- cc is two hex digits: the sum, mod 256, of the bytes from the tag to the
  last byte of the payload, as they were sent.
- A sender sends uppercase digits, in the payload and in cc. A receiver
  accepts either case. The sum is over the bytes as sent, so a lowercase
  digit in the payload changes it.

A packet never holds ESC, and nothing else goes between its bytes: no
console byte, and no other packet. A sender sends a packet whole.

## 3. Requests and answers

Only the host sends requests, and the system answers each one. The host
sends no request before the answer to its last one has arrived, or its
timeout (§5) has passed. Console bytes and notices may come between a
request and its answer.

| Request | Payload | Answer | Payload |
|---|---|---|---|
| `R`, read | address A, count N | `r` | A, N, and N data words |
| `W`, write | address A, count N, N data words | `k` | A and N |
| any | | `e` | the request's tag and an error code |

- `R` reads the N words from A upwards, and `W` writes N words there. An
  address past `0xFFFFFFFF` wraps to 0, but a `W` that wraps is answered
  with `e02` (below): it would write the control register (§6) and then
  the memory, which the program, once started, or a clear may use.
- N is 0 to 65535. N = 0 reads or writes nothing, and is answered as any
  other request, so the host can use it to test the link.
- The answers repeat A and N, so that a host can tell an answer to an
  earlier request, which came after its timeout, from the answer it waits
  for. A host skips an answer that does not match its request.
- The system writes the words of a `W` as they arrive, before it can check
  the checksum. So a `W` with a bad checksum may leave some words written.
  The `k` answer says the whole packet was good and every word written. A
  host that gets no `k` to a `W` to memory sends the whole `W` again.
- The debug registers of §6 are written as they arrive too, like any other
  word. So a `W` to the control register with a damaged payload may still
  hold, start, or clear. A host writes the control register with a `W` of
  its own, with N = 1, to keep that window small.
- A `W` with more than N data words is answered with `e03`. The system
  writes only the first N.
- A host must not resend a request with a side effect blindly: a write to
  the control register (§6), for example. The protocol has no sequence
  numbers, so the system runs a resent request again.

**The address space.** The words go to the same address space as the
program's data accesses, with these differences:

- The debug registers of §6 are there for the link only.
- While the program runs, the link reaches only the debug registers. A
  request that reads or writes any other word then is answered with the
  error `02`, and reads or writes nothing. So a host holds the processor,
  or waits for it to halt or pause, before it reads or writes the memory.
- No link read has a side effect that a program can see. A link read of
  the console or the read counter (SYSTEM.md §1) returns 0, takes no input
  byte, and is not counted. A link read of `CYCLE_LO`, `INSTR_LO`, or
  `TIME_LO` (SYSTEM.md §3) returns the counter's low word. The emulator
  takes no snapshot then, but a board may, as a property of the system.
  A program cannot tell, because the link reads a counter only while the
  processor is held, halted, or paused. A start resets the counters and
  their snapshots (§6), and the counters stop while the processor is paused,
  where a link read takes no snapshot, so that the program's own snapshot
  survives the pause. A host can tell: on such a board, while the processor
  is held or halted, a read of `CYCLE_HI`, `INSTR_HI`, or `TIME_HI` after a
  link read of the low word returns the snapshot of that read.
- A link write to the console or the read counter is ignored. A link write
  to another device register acts as a program's write. A host that writes a
  device register or the memory while the processor is paused changes what
  the program sees when it goes on.

**Errors.** The system answers a packet with a good checksum that it
cannot carry out with `e`, the packet's tag, and an error code. The tag is
two hex digits, its ASCII code, so `R` is `52` and `W` is `57`. The codes:

| Code | Meaning |
|---|---|
| `01` | The tag is not a request of this version. |
| `02` | The program runs (§6), and the request reaches a word that is not a debug register; or a `W` wraps past `0xFFFFFFFF`. |
| `03` | The payload has the wrong length, or a byte that is not a hex digit. |

When more than one error applies, the answer gives the first in the
table. The system decides `02` from A and N, before any data word arrives,
so it carries out nothing of a request that it answers with `e01` or
`e02`. A `W` answered with `e03` may leave some words written, as one with a
bad checksum may: a byte that is not a hex digit, or an early `#`, is found
only after the words before it are written.

## 4. Notices

The system sends notices on its own. A notice never interrupts a packet,
but it may come between a request and its answer: the `p` that a write of
the control register causes may come before the `k` of that write.

| Notice | Payload | Meaning |
|---|---|---|
| `b` | version | The system has powered up or been reset, or a host has connected over TCP (§7). The version is `02`. |
| `h` | reason | The processor has halted. The reason is the halt reason of §6, `01`–`05`. The last console byte that the program wrote comes before the notice. |
| `p` | none | The processor has paused: a pause request (§6) has taken effect, and bit 4 of the control register reads 1. The last console byte that the program wrote comes before the notice. |
| `o` | none | A console byte from the host was lost, because the program's input buffer was full. |

The system sends `o` once, and no other until its input buffer has room
again. A console byte dropped while the processor is held or halted (§1)
sends no `o`. A pause ends in exactly one of `p` and `h` (§6), so a host
that waits for either knows which came.

## 5. Errors and timeouts

ESC and a letter start a packet. Every byte up to the `#` and the two bytes
of cc after it belongs to the packet, so none of them reaches the program,
even when the packet is dropped. ESC followed by a byte that is neither ESC
nor a letter is dropped with that byte.

A receiver drops a packet, silently, when:

- its checksum is wrong,
- an ESC comes before its `#` and checksum, or
- 100 ms pass between two of its bytes.

An ESC that ends a packet early starts a new escape sequence. A system that
receives a packet with a good checksum, but an unknown tag or a bad
payload, answers it with an error (§3). A host drops such an answer or
notice.

The system never answers a packet that it dropped. A host that gets no
answer within 100 ms of the last byte of its request, or with a gap of
100 ms between two bytes of the answer, sends the request again, unless it
has a side effect (§3). Then the host reads what the request changes, such
as the control register, to learn whether it took effect. A system
sends the first byte of every answer within 100 ms of the last byte of the
request, a clear of the memory included (§6). The whole answer may take
longer: a 65535-word `r` takes about 2.6 s at 2 Mbaud.

## 6. The debug registers

The words `0xFFFFFFE0`–`0xFFFFFFFF` are registers for the link only. A
program cannot reach them: its data accesses there go to whatever the
system has there otherwise.

| Address | Register |
|---|---|
| `0xFFFFFFE0`–`0xFFFFFFEF` | R0 to R15, read only. After a halt, until the next start, they are the values the program left, with R15 the address after the halting instruction, as the emulator prints them, also while the processor is held after the halt. While the processor is paused, they are the values after the last step, with R15 the address of the next instruction, and a hold of the paused processor keeps them until the next start. From a start, or from a go on after a pause, until the next halt or pause, their values are not defined. |
| `0xFFFFFFF0` | Control (below). |
| `0xFFFFFFF1` | The halt reason, read only: 0 while the processor has not halted, 1 for `HALT`, 2 for a reserved control word, 3 for `INT` inside an interrupt routine, 4 for `RTI` outside one (ISA §5.3, §7.2, §7.4), and 5 when the emulator's step limit stopped the program (§7). |
| `0xFFFFFFF2` | The protocol version, read only: 2. A host checks it before it uses the pause. |
| `0xFFFFFFF3` | The free space, read only: the number of console bytes that the program's input buffer can take now. It reads so while the processor is held or halted too, although the bytes sent then are dropped (§1), and a start empties the buffer. |
| `0xFFFFFFF4`–`0xFFFFFFFF` | Reserved. They read 0 and take no write. |

A write to a read-only register is ignored. The bits of the control
register:

| Bit | Read | Write |
|---|---|---|
| 0 | 1 while the processor is held | 1 holds the processor in reset, and 0 starts it |
| 1 | 1 after a halt | ignored |
| 2 | 0 | 1 first clears the memory to 0, with the processor held |
| 3 | 1 while the ROM is hidden | 1 hides the ROM, so the RAM is at 0, and 0 shows it |
| 4 | 1 while the processor is paused | 1 asks for a pause, and 0 cancels the request or goes on |

The other bits read 0 and take no write. The processor runs while bits 0,
1, and 4 all read 0. That includes the time between a pause request and the
step boundary where it takes effect. Every write to the control register
writes bits 0, 2, 3, and 4 at once, so a host keeps bit 3 as it is in each
write, for example by reading the register first, and bit 4 as it reads to
stay paused, or at 0 to go on.

- **Start.** When bit 0 goes from 1 to 0, the processor starts at address
  0, as the emulator starts a run. The math unit, the performance counters,
  and the timer start from their reset values. The read counter keeps its
  value (SYSTEM.md §1). The input buffer is emptied, and an earlier end of
  the input (§7) is cleared. Bit 1 and the halt reason are cleared, and
  R0–R15 are not defined until the next halt.
- **Restart.** A halt leaves bit 0 at 0, so a restart after a halt takes
  two writes: bit 0 to 1, then to 0 (§8). A resent write of 0 cannot start a
  program again by itself.
- **Hold.** Writing 1 to bit 0 stops a running program at once. It sends no
  `h` notice. Bit 1, the halt reason, and R0–R15 keep their values while
  the processor is held, so a host can read them after a halt in either
  state. A hold of a paused processor keeps R0–R15 as they were at the
  pause, until the next start, so a host can pause, read, and stop. A hold
  that stops a running program leaves R0–R15 not defined. A hold ends the
  pause: bit 4 reads 0 while the processor is held.
- **Halt.** A stop by the emulator's step limit is a halt: bit 1 reads 1.
- **Clear.** A write with bit 2 set clears every word of the memory, the
  screen included, and holds the processor first if it runs. Bit 3 takes
  effect when the clear starts, and bit 0 when it ends. So a write of `0x4`
  clears the memory and then starts a program at address 0, from memory
  that is all 0. A host that loads a program next writes `0x5`, to clear
  and stay held, or `0xD`, to keep the ROM hidden as well. The `k` answer
  comes when the memory is clear, within the 100 ms of §5. A `W` writes
  each word as it arrives, so a dropped `W` (§5) may still start a clear.
  A request that comes while the memory clears is carried out after the
  clear ends.
- **ROM.** A system without a ROM, such as the emulator, reads bit 3 as 1
  and ignores writes to it.
- **Pause.** A write of 1 to bit 4 of a running processor asks for a pause.
  The processor stops at the next step boundary, ahead of an interrupt
  (MICROARCH.md §6.1), and the system sends `p`. Bit 4 reads 1 only then:
  the processor has stopped, and no bus cycle is open. A request that is
  still on its way reads 0, so a host waits for `p`, or polls until bit 4
  or bit 1 reads 1. A write of 0 before that cancels the request, and the
  processor may pause before the write arrives.
- **Pause and halt.** A halt goes first. A halted processor ignores the
  pause, and bit 4 reads 0. So a request ends in exactly one of bit 4 and
  bit 1, and in exactly one of `p` and `h`.
- **While paused.** The link reaches the whole address map, as while held or
  halted. R0–R15 are defined (above). A host may write memory, code
  included, because the processor fetches from R15 again when it goes on.
  The counters and the timer stop, and a link read of a counter takes no
  snapshot (§3), so the program cannot tell that it was paused, but by the
  wall clock. A pause fires no timer interrupt when the processor goes on.
  Console bytes from the host go into the input buffer (§1).
- **Go on.** A write of 0 to bit 4 of a paused processor, with bit 0 at 0,
  makes it go on from R15. Single step is not in this version, and needs a
  bit of its own.
- **Start paused.** A start with bit 4 set pauses before the first step,
  and the system sends `p`. So a host can load a program and keep it at its
  first instruction. With bit 3 at 0, a write of `0x11`
  holds with the request, and a write of `0x10` then starts paused.

After a reset of the system, a system that boots a ROM runs with bit 0 at 0
and bit 3 at 0. A system without one waits, held, with bit 0 at 1.

## 7. Transports

- **UART.** NiceMonMEGA65 carries the link on its debug UART, 8-N-1, at
  2 Mbaud unless it was built for another rate. A UART break, a frame
  of ten 0 bits, ends the program's input, as a break from the keyboard
  does (SYSTEM.md §5). Then the console reads `0x200` (SYSTEM.md §1)
  until the next start.
- **TCP.** The emulator serves the link on a TCP port, on `127.0.0.1`
  only. It serves one host at a time: while a host is connected, it accepts
  another and closes that connection at once, with nothing sent. It sends
  `b` to each host that connects. A host ends the program's input by
  closing its half of the connection for writing (a TCP half-close), and
  keeps reading the answers and the output. Then the console reads `0x200`,
  as after a UART break. A host that sends after that must connect again.
  A host that has half-closed does not keep another out: it counts as
  disconnected when another connects.

When a host disconnects, the program keeps running, and the memory keeps
its contents for the next host. The emulator cannot tell a disconnect from
a half-close, so a disconnect ends the program's input too: its console
reads `0x200` until the next start. The output and the notices sent while
no host is connected are lost.

On either transport, the console bytes that arrive after the end of the
input are dropped until the next start, with no `o` notice. A start clears
the end of the input (§6).

The emulator, serving the link, works as when it runs a program from the
command line, with these differences:

- `--link PORT` serves the link on PORT. With PORT 0, the emulator picks a
  free port and prints `link: port N` on stderr.
- It starts held, and starts the program only when the host clears bit 0 of
  the control register.
- Its memory starts as a `.bin` file given on its command line, if one is,
  and as 0 otherwise. The host can load a program with `W` either way.
- The console's input comes from the link, so `--input` is an error with
  `--link`. A console read waits for the next byte or the end of the input,
  as it does from the command line. The input buffer holds 2048 bytes, as
  NiceMonMEGA65's does.
- It serves the link while a program runs and while a console read waits,
  often enough to answer within the 100 ms of §5. Its README says how often.
- A pause takes effect between two steps, at once, and the emulator sends
  `p`. The exception is a console read that waits for input (SYSTEM.md §1):
  the processor is inside a step then, and pauses after the next byte
  arrives or the input ends. A host can send a console byte, or hold.
- Its step limit (`--max-steps`), `--irq`, and `--nmi` count the steps of
  each run that the link starts. When the step limit stops the program, the
  halt reason is 5, and the emulator sends `h` with it.
- What it prints after a halt (the `Halted` line, the registers, `--dump`,
  and `--screen`) and `--trace` go to stderr, for each run, and stdout
  stays empty. A hold that stops a run is not a halt and prints nothing,
  and neither does a pause.
- `-2004`, `--symbols`, `--no-cycle-counter`, and its other options work as
  usual.
- It runs until it is stopped by a signal, and then exits with status 0.

## 8. An example

The host writes `0x11223344` and `0x55667788` at `0x100`, and reads the
first word back. The checksum of the `W` is the sum of the bytes from `W`
to the last `8`, mod 256. FF is the byte `0xFF`, and the rest is ASCII.

    host:    FF "W0000010000021122334455667788#E2"
    system:  FF "k000001000002#AE"
    host:    FF "R000001000001#94"
    system:  FF "r00000100000111223344#48"

A system reset sends `FF "b02#C4"`, and a `HALT` sends `FF "h01#C9"`. The
same `R` sent while the program runs gets `FF "e5202#2E"`.

After a halt, the host restarts the program with two writes to the
control register, hold and then start. Both keep bit 3 at 1, so the ROM
stays hidden:

    host:    FF "WFFFFFFF0000100000009#BB"
    system:  FF "kFFFFFFF00001#46"
    host:    FF "WFFFFFFF0000100000008#BA"
    system:  FF "kFFFFFFF00001#46"

To look at a running program, the host writes bit 4, with the ROM hidden
as above, and waits for the notice. Then it reads the memory and goes on.
A board may send the `p` before the `k`:

    host:    FF "WFFFFFFF0000100000018#BB"
    system:  FF "kFFFFFFF00001#46"
    system:  FF "p#70"
    host:    FF "WFFFFFFF0000100000008#BA"
    system:  FF "kFFFFFFF00001#46"
