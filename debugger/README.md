# The debugger

`nicedbg.py` is an interactive debugger on the debug link of
[DEBUG.md](../doc/DEBUG.md). It talks to `niceemu --link` over TCP
([emulator/README.md](../emulator/README.md#debug-link)), or to a
system on its UART. It loads a program, runs, pauses, steps, and goes
on, sets the breakpoints, reads and writes the registers and the
memory, and disassembles with [`nicedis.py`](../assembler/README.md),
with labels from `niceasm.py --symbols` or `nicebuild.py`.

The tools use only the Python standard library, and run on Linux and
macOS.

| File | What it is |
|---|---|
| `nicedbg.py` | The debugger, a shell with one short command for each action. |
| `nicelink.py` | The debug link: the packets, the debug registers, the requests, the notices, and the transports, TCP to niceemu and a UART. |
| `nicebin.py` | The `.bin` and `.sym` files, and the loading of a program over the link. |

## Running it

Start niceemu with the link, and connect to its port:

    niceemu --link 4510 &
    debugger/nicedbg.py --tcp 4510 --symbols prog.sym prog.bin

The options:

| Option | What it does |
|---|---|
| `--tcp [HOST:]PORT` | Talk to `niceemu --link` on `PORT` of `HOST`, `127.0.0.1` by default. An IPv6 `HOST` goes in brackets, `[::1]:4510`. |
| `--port DEVICE` | Talk to a system on its UART, the serial device `DEVICE`, such as `/dev/ttyUSB1`. On macOS, use the `/dev/cu.*` device. |
| `--baud RATE` | The UART's baud rate, 2000000 by default. |
| `--symbols FILE` | Read the labels of a `.sym` file. |
| `FILE.bin` | A program to load at the start, with the processor held. |

One of `--tcp` and `--port` must be given. The files are read before the
link opens, so a bad file stops the debugger before it touches the
system. It then reads the link's version, and stops on a major other
than 0, which it does not know (DEBUG.md §9). With `--tcp`, it waits up
to 2 seconds for the `b` notice that niceemu sends to each host that
connects (DEBUG.md §7.2), and stops without one, as the port is then
served by another program.

An error in the options, the files, or the connection prints a message
on stderr and exits with status 1, or with status 2 for an option that
argparse refuses. A `.bin` file must have the lines that niceemu takes:
two fields of 1 to 8 hex digits, with no `0x`; no address twice; and at
least one word. Only LF ends a line, only blanks and tabs part the
fields, and a CR at the end of a line is ignored. A `.sym` file has
lines of an address and a name.

## The commands

Numbers are hex, with or without `0x`. With symbols, an address may be
a label, `label+N`, or `label-N`. A label comes before a hex number
that is spelled the same, such as `add`; a number with `0x` is always
one. `help` lists the commands, and `help CMD` describes one.

| Command | What it does |
|---|---|
| `status` | The state of the processor, the ROM, and the link. |
| `load FILE` | Holds the processor, hides the ROM, clears the memory, disables the breakpoints, and loads the `.bin` file. |
| `go` (`g`) | Goes on from a pause, or starts a held processor at 0. |
| `run` | Starts the program at 0 again. The memory is not loaded again. |
| `hold` | Holds the processor in reset. |
| `pause` | Pauses the running processor, and shows where. |
| `step` (`s`) `[N]` | Runs N steps of a paused processor, and shows the PC after each, up to 16. An empty line steps again. |
| `b [ADDR]` | Sets a breakpoint at ADDR, or lists them. |
| `bd N` or `bd all` | Disables breakpoint N, or all of them. |
| `regs` | Shows R0 to R15. |
| `set Rn VALUE` | Writes a register of a paused processor. `SP`, `SR`, and `PC` name R13, R14, and R15. |
| `pc [ADDR]` | Shows the PC of a paused processor and its instruction, or sets it. |
| `r [ADDR [N]]` | Reads N words, 16 by default. Without ADDR, it goes on after the last read. |
| `w ADDR WORD...` | Writes words. |
| `d [ADDR [N]]` | Disassembles N instructions, 16 by default, with the labels before them. Without ADDR, it goes on after the last `d`, or at the PC of the last stop. |
| `ctl [VALUE]` | Reads the control register, or writes it. |
| `symbols [FILE]` | Reads the labels of a `.sym` file, or counts them. |
| `send TEXT` | Sends text to the program, with escapes such as `\n` and `\x1b`. |
| `eof` | Ends the program's input. |
| `console` (`c`) | Passes the terminal through to the program until Ctrl-]. It needs a terminal. |
| `quit` (`q`) | Leaves the processor as it is, and quits. Ctrl-D quits too. |

The program's console output and the link's notices are shown as they
arrive, above the prompt: `[breakpoint 0, PC=... LOOP  SUB[M] ...]`,
`[paused, PC=...]`, `[halted: HALT, PC=...]`, `[boot]`, and `[input
overflow]`. The PC after a halt is the word after the instruction that
halted.

The commands also come from stdin when it is no terminal, so a script
can drive it:

    printf 'b DONE\ng\nregs\nq\n' | debugger/nicedbg.py --tcp 4510 --symbols prog.sym prog.bin

## On a board

A board's link may run over transports of its own, such as Ethernet,
and its memory may not reach every address. The board's tools import
these modules and pass hooks of their own:

- A transport subclasses `nicelink.Transport`, or `nicelink.Tcp` for
  one over TCP, with its own `peer`, `hint()`, `_connect()`, and
  `_reconnect()`. `nicelink.add_arguments()` returns the group of
  `--tcp` and `--port`, to which the board adds its own options.
- `nicebin.load_words()` takes a check of the words against the
  board's memory, which may read the board's registers while the
  processor is held, and stops on a word that does not fit.
- `nicedbg.main()` takes `add_link_arguments`, `open_link`, `load`, and
  `check_file`, for the options, the link, the loader, and the check of
  a file before the link opens.

[NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65) does this
for its Ethernet port and its simulation, and checks a program against
the MEGA65's RAM.

## Tests

`make test` runs `test/errors.py`, the error cases of the options and
the files, with exact messages, and `test/link.py`, which runs the link,
the loader, and the debugger's commands on `niceemu --link` with the
programs `test/echo.nasm` and `test/break.nasm`. It builds niceemu
first if needed. `make typecheck` runs `mypy --strict`.
