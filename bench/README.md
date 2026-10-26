# bench

A benchmark for code that reaches NICE through wasm: `bench.c`, compiled
with clang and the small C library, translated by `nicewasm`, and run on
the emulator or on the core. Next to it is `hand.nasm`, the same
benchmark written in NICE assembly by hand, which shows how far the
translated code is from what the machine can do. `simple.nasm` is
`hand.nasm` with two phases written as a simple C compiler would emit
them (see A simple compiler below). They are for measuring
the translator's output and the core, phase by phase, not for comparing
NICE with other processors.

    make            # run the three on the emulator and print their tables
    make dhry       # run Dhrystone 2.1 on the emulator
    make test       # the same, and check every result
    make core       # run both on the pipelined core in GHDL (about 22 minutes)
    make core CORE=multicycle  # the same on the multi-cycle core (about 38 minutes)
    make core-dhry  # run Dhrystone on a core in GHDL, CORE as above, and check it (about 2.5 minutes)
    make hazards    # count the pipeline hazards of MICROARCH.md §5 in both
    make cycles     # estimate the cycles of the three on the pipelined core of MICROARCH.md
    make profile    # the same, charged to the source lines, in build/*.cyc.txt
    make compare    # the estimate beside the pipelined core's cycles, after make core
    make words      # the size in words of the benchmark, safe.zig, and float modules
    make native     # build and run bench.c on the host, as a check
    make wasm       # rebuild bench.wasm and dhrystone/dhry.wasm (needs clang)

`dhrystone/` is Dhrystone 2.1, the classic benchmark for comparing
small processors, ported to the C library (see Dhrystone below).

`bench.wasm` and `dhrystone/dhry.wasm` are checked in, so `make` and
`make test` need only Python 3 and the emulator, as the translator's
tests do. `make wasm` needs clang with the wasm32 target and wasm-ld, and
it builds `runtime/libc/libc.a` first.

## The phases

Each phase is a well-known kernel with a known result, and each one
isolates a few of the costs that translated code pays.

| Phase | What it does | What it exercises |
|---|---|---|
| `rng64` | xorshift64* fills a 4096-byte buffer and 1024 integers. | `i64` multiplication and shifts, byte stores, word stores. |
| `crc32` | A table-driven CRC-32 of the buffer, with the table built first. | Byte loads, word loads with a computed index, shifts, xor. |
| `bst` | The integers go into a binary search tree of static nodes, which a recursive walk hashes. | Loads and stores of struct fields at constant offsets, calls. |
| `heapsort` | Sorts the integers in place. | Word loads and stores with computed indices, signed comparisons, swaps. |
| `vm` | A bytecode interpreter with ten opcodes runs a loop of 2000 iterations. | A `switch`, which is a `br_table` in wasm, byte fetches, a word stack. |
| `strings` | 64 strings made from the buffer are sorted with `strcmp`, joined with `strcpy`, and searched with `strstr`. | Byte accesses through the C library. |

There is no float phase, because it would measure the float library
rather than the translator. There are no function pointers and no
`malloc`.

The sizes are the defines at the top of `bench.c`. All of the data is
static, so the program needs one page of linear memory. The phases run
in this order on purpose: `bst` takes the integers in the order `rng64`
left them, and `heapsort` sorts them afterwards.

## The output

Each program prints one line per phase: the instructions and the cycles
of the phase, from the performance counters of SYSTEM.md §3, then the
phase's result and whether it is the expected one. `main` returns the
number of phases with a wrong result, so R1 is 0 after a good run.

These are the tables from the emulator. First `bench.c`
through nicewasm:

    phase      instructions       cycles  result
    rng64            51746        51774  0e18cd0a  ok
    crc32            63514        63542  2df3b109  ok
    bst             297825       297853  55a72225  ok
    heapsort        298396       298424  bdb22882  ok
    vm              840049       840077  04156880  ok
    strings         101281       101309  d9867cf6  ok
    total          1652811      1652979

Then `hand.nasm`:

    phase      instructions       cycles  result
    rng64            39949        39953  0e18cd0a  ok
    crc32            27658        27662  2df3b109  ok
    bst             114179       114183  55a72225  ok
    heapsort        177189       177193  bdb22882  ok
    vm              112013       112017  04156880  ok
    strings          20321        20325  d9867cf6  ok
    total           491309       491333

The instruction count leaves out the reads of the counters, and the
cycle count includes them. The emulator counts one cycle per
instruction, so its two columns differ only by those reads. On the core
the cycles are clock cycles, and `make core` shows how many each
instruction takes. The start-up code, which sets the linear memory to 0
for the translated program, and the printing are outside the phases.

## The hand-written version

`hand.nasm` keeps to these rules, so that the two programs measure the
same work:

- The same phases, sizes, algorithms, and results as `bench.c`, and the
  same table. The optimization is at the instruction level: operands in
  memory, conditional instructions instead of jumps, flags from the
  operation itself, side effects on pointers, tail calls, and the math
  unit used directly, with an operand left in place where it does not
  change. The interpreter dispatches through a jump table, as the
  translated `switch` does, not through addresses in the program. A
  conditional jump back that is mostly taken, such as a loop's back
  edge, is `ADD PC, PC, label-next`, where `next` labels the
  instruction after the jump, which DECODE predicts taken
  ([MICROARCH.md](../doc/MICROARCH.md) §5.4).
- The data layout is the natural one for a word-addressed machine. The
  byte buffer stays packed, four bytes to a word, as in linear memory.
  The strings have one character per word, as a C `char` does in ABI.md, the interpreter's program has one word per opcode or operand, and
  pointers are word addresses. The tree's nodes are four words, as in the
  wasm version.
- The C library routines of the strings phase are written inline.

The ratio of the instruction counts, translated to hand-written:

| Phase | Ratio | Where the translated code loses |
|---|---|---|
| `rng64` | 1.3 | `i64` shifts take the same two-word steps either way, and the 64-bit product three products of the math unit. |
| `crc32` | 2.3 | A byte load is seven instructions with its own bounds check, against a word read with a side effect on the pointer and shifts by hand. The table lookups need no check. |
| `bst` | 2.6 | Each node's fields take a compare and a skipped jump before their reads, which the hand-written code does without. |
| `heapsort` | 1.7 | The array elements take a compare and a skipped jump before their reads and writes, and the signed comparisons take two instructions either way. |
| `vm` | 7.5 | The `br_table` checks its index, each stack cell is a checked word access, and the bytecode fetch is a byte load of seven instructions, where the hand-written interpreter has one word per opcode and the operands in registers. |
| `strings` | 5.0 | Every character is a byte load of seven instructions, where the hand-written strings have one character per word. |
| total | 3.4 | |

What remains is in TODO.md, under "Faster and smaller translated code".
A byte load of linear memory stays several instructions, since the
memory is byte-addressed and packed four to a word (WASM.md).

On the multi-cycle core, which takes about ten cycles for a plain
instruction, the two programs run like this, measured at commit 8f899fe:

| Program | Instructions | Cycles | Cycles per instruction | GHDL time |
|---|---|---|---|---|
| `bench.c` through nicewasm | 1681080 | 19043715 | 11.3 | 38 minutes on a busy machine |
| `hand.nasm` | 491617 | 5598318 | 11.4 | 8 minutes on a busy machine |

So the hand-written program is 3.4 times shorter in instructions and 3.4
times faster in cycles. In the translated program, `rng64` and `vm` have
the most cycles per instruction, 12.0 and 11.7, and `vm` in the
hand-written one, 12.8.

`make core` runs them on the pipelined core (the default), on the same
programs as the multi-cycle core above, at commit 1a41b0c, which leaves
the multi-cycle core as it was:

| Program | Instructions | Cycles | Cycles per instruction | Faster than the multi-cycle core |
|---|---|---|---|---|
| `bench.c` through nicewasm | 1681080 | 2384635 | 1.42 | 8.0 times |
| `hand.nasm` | 491617 | 1384879 | 2.82 | 4.0 times |

Since DECODE predicts backward conditional jumps taken
([MICROARCH.md](../doc/MICROARCH.md) §5.4), and `hand.nasm` closes its
loops with them, `hand.nasm` takes 1252613 cycles on the pipelined
core at commit 98d2bed, 2.55 per instruction and 9.6% fewer than the 1384879 of the
program at that commit. `bench.c` closes its loops the same way
(translator/README.md), and takes 2357155 cycles for 1652811
instructions, 1.43 per instruction and 1.2% fewer than the 2384635
above.

On the pipelined core, `make core` also prints how long data reads waited
for their condition or for an older micro-operation, the waits that
speculative reads would remove ([hdl/README.md](../hdl/README.md), The
pipelined core). The cycles count from reset, so they include the start-up
and the output:

    bench: Read waits: 2439238 cycles; went on: 146 for the condition, 0 for an older micro-operation; dropped: 0, 0
    hand:  Read waits: 1260303 cycles; went on: 269 for the condition, 2002 for an older micro-operation; dropped: 0, 52002

So such waits cost 0.006% and 0.18% of the cycles (MICROARCH.md §5.3).


The hand-written program gains less, because more of its time goes to
what a pipeline cannot hide: `vm` jumps through a table every three or
four instructions, which flushes the pipeline, and `strings` and `bst`
read the math unit right after writing its operands
([hdl/README.md](../hdl/README.md), The pipelined core).

## A simple compiler

`simple.nasm` estimates what a C compiler that targets NICE directly
would gain over nicewasm ([doc/review/c-compiler-plan.md](../doc/review/c-compiler-plan.md)).
It is `hand.nasm` with the `vm` and `strings` phases written the way a
simple compiler would emit them from `bench.c` with `CHAR_BIT` = 32
([ABI.md](../runtime/ABI.md)): locals in registers, local arrays in the
frame, loads folded into the one instruction that uses them, the math
unit inline, and the C library routines of `strings` as separate
functions, called by the ABI. It uses no `@R++` or `--R`, no conditional
instruction but a jump, and no flags from an earlier operation, and each
case of the `switch` jumps back to the top of the loop. A loop tested at
the bottom closes with `ADD PC, PC, label-next`, as in `hand.nasm`. Before the
strings phase, outside its timing, the byte buffer is unpacked to one
byte per word, as `unsigned char buf[]` is with `CHAR_BIT` = 32. The
other four phases are those of `hand.nasm`.

The two phases, in instructions on the emulator and in cycles by
`make cycles`, at commit 98d2bed:

| Phase | nicewasm | `simple.nasm` | `hand.nasm` |
|---|---|---|---|
| `vm`, instructions | 840049 | 314016 | 112013 |
| `vm`, cycles | 1248112 | 768069 | 602050 |
| `strings`, instructions | 101281 | 47293 | 20321 |
| `strings`, cycles | 163528 | 110956 | 48723 |

So such a compiler would take 1.62 times fewer cycles than nicewasm in
`vm` and 1.47 times fewer in `strings`, about three quarters and half of
what `hand.nasm` saves. `make test` checks its results as it checks the
others'. `make core` does not run it.

## The hazard profile

`hazards.py` counts how often the pipeline hazards of
[MICROARCH.md §5](../doc/MICROARCH.md) occur in a program, from the
emulator's trace, and `make hazards` runs it on both programs. It takes
`.bin` files, which it runs on the emulator with `--trace`, or traces that
`niceemu --trace` wrote. The emulator is the one in `emulator/zig-out/bin`,
or `$NICEEMU`.

Each instruction is decoded into the registers it reads and writes, its
data accesses, its constant words, and its micro-operations, and compared
with the one, two, and three instructions before it. A skipped instruction
counts as if it ran, because DECODE sees its operands before the condition
is known. For each program the output gives the number of instructions,
the distributions of the instruction length in words and of the
micro-operations, and then one line per hazard with its count and its
share of all instructions. This is the output for `hand.nasm` at commit 98d2bed:

    hand: 493964 instructions, 91075 skipped (18.4%)
      words        1: 35.6%  2: 63.1%  3: 1.3%  4: 0.0%   mean 1.66
      micro-ops    1: 85.7%  2: 14.1%  3: 0.2%   mean 1.14
      conditional                                                  137036  27.7%
      ...
      reads a register the previous instruction writes             149002  30.2%
      ...
      registers read from the previous instruction: R2 8.7%, R1 7.0%, ...

The last lines count what costs a cycle on the core which forms every operand value, address, and shift count in PREPARE: the shifts by the kind of their count (a
constant, R0 and R15 included, a register, memory, or an adder, `c[R]`
or `--R`, which WRITE reduces in a cycle of its own whoever wrote R), the shifts whose
count register the previous instruction writes, the sources in mode 001
or 011 and the store addresses in mode 011, 101, or 111 whose register
the previous instruction writes, the same for stores through `@R` or
`@R++`, the taken jumps that WRITE resolves, by their target (a
constant, a word in memory, or computed), and the register destinations
in mode 001 or 010. A jump that DECODE resolves is `MOVE R15, c` or
`ADD R15, R15, c` with the condition "always", or the `ADD` with
another condition and `c` negative, which DECODE predicts taken, as in
the core (MICROARCH.md §5.4). A trace shows no constant words, so this
last one counts only when FILE is a `.bin`. A `MOVE`
to R15 of a register or a sum is resolved in WRITE, in one cycle, and
any other operation on R15 computes its target. In both programs, no
shift's count register and no source in mode 001 or 011 came from the
previous instruction, and there were no computed jumps and no
destinations in mode 001 or 010, and no shift whose count WRITE
reduces. `hand.nasm` has six jumps to a register.

MICROARCH.md §5.6 has a table of these shares and the decisions it led to. `hazards.py --test` checks the counts on a small program whose hazards
are counted by hand in the script, and `make test` runs it. `make
typecheck` runs mypy on `expected.py`, `hazards.py`, and the tools below.

## The cycle estimate

`pipecycles.py` estimates the clock cycles a program takes on the
pipelined core of [MICROARCH.md](../doc/MICROARCH.md), and `make cycles`
runs it on both programs. Like `hazards.py`, it
takes `.bin` files, which it runs on the emulator with `--trace`, or
traces. It is a model built from MICROARCH.md, not the core. Each
instruction of the trace is decoded as `hazards.py` decodes it, split
into its micro-operations, and sent through FETCH, DECODE, SEQUENCER,
PREPARE, and WRITE under the rules of §3 to §5: two words fetched per
cycle, a bubble of 3 cycles for a jump that DECODE resolves (2 behind a read, which holds the stream up a cycle) and of 7 for
one resolved in WRITE, DECODE's skid register, a data read that waits for an older write of SR,
an address register written by the previous micro-operation, one data
access per cycle on the bus, a read that is on the bus a cycle after
PREPARE loads it, a store that is on the bus from DBUS's store register
a cycle after WRITE and that FETCH waits for, a cycle more for an access to another slave of the bus
than the one before, read data that reaches WRITE a cycle after its ACK
unless it only goes into a register,
and the math unit of `hdl/src/mpu.vhd`: a product two cycles after the write of an operand,
and a quotient after one cycle per bit, less the runs of eight zero bits
that the divider skips, which the model works out from the operands in
the trace. Every cycle above one per instruction is
charged to the rule that caused it, so the output says where the time
goes, and a program that reads the instruction counter around each phase,
as both programs do, gets a row per phase:

    bench.bin: 1697422 instructions, 2438761 cycles (estimate), CPI 1.437
      cycles above 1/instruction: 741339
      ...
      taken jumps resolved in WRITE (flush)                        267540  0.158/instr  36.1%
      jumps DECODE resolves (early-redirect bubble)                 60047  0.035/instr   8.1%
      ...
      read data a cycle after the bus (registered request)         103494  0.061/instr  14.0%
      read data used by more than a register write                 179438  0.106/instr  24.2%

      phase         instr    cycles    CPI   main extra cycles per instruction
      rng64         51746     82515  1.595   mpu 0.35, bus 0.15, early 0.06, adjust 0.02
      ...
      total       1652811   2356816  1.426

The bubbles are the core's. A jump that WRITE resolves leaves WRITE in
cycle c − 2 and flushes in the same cycle, and the redirect reaches
FETCH from a register in c − 1 (MICROARCH.md §5.4). FETCH issues the
request in c, so it is on the bus in c + 1, and the memory acknowledges
in c + 2. DECODE takes the instruction in c + 3 and emits its micro-op
in c + 4, PREPARE passes it on in c + 5, and WRITE runs it in c + 6: 7
cycles. A jump that DECODE resolves redirects FETCH in the cycle DECODE
takes it, d, so the target is in DECODE in d + 4, 3 cycles later than
the instruction after the jump would have been, and a cycle more right
after a store, which FETCH waits for. A jump that DECODE predicted taken
and that is skipped costs a flush, like a taken jump that WRITE
resolves. `hdl/test/bubble.nasm` measures 7
and 2, since its read of the cycle counter before the jump holds the
stream up a cycle, which hides one cycle of the early bubble but none of
the flush. Each case of `pipecycles.py --test` gives the core's cycles,
step by step, with `--retires` below.

The phases of the translated program take an estimated
2356816 cycles, 1.43 per instruction, and those of `hand.nasm` 1252534,
2.6 per instruction: the hand-written code has more instructions with
side effects, memory operands, and reads of the math unit, and fewer
instructions in all. Options such as `--flush`, `--early`, `--agen`,
`--read-bus`, `--slave-gap`, `--mul`, and `--div-skip` set the model's parameters, to try a design
change before it is built. Four options, each 1 by default, are the rules of the core, which forms every operand value, address, and shift count in PREPARE (MICROARCH.md §7.3 and §7.4); 0 turns a rule off: `--shift-late N`
gives a shift whose count WRITE reduces N cycles more in WRITE, and a
rotation through C 2N: a count from memory, through an adder (`c[R]` or
`--R`), with a side effect, in R14, or of `C<C` or `C>C`, but for a
constant word (MICROARCH.md §7.3);
`--shift-reg N` makes a shift wait N cycles in PREPARE for any other
count register that the previous micro-op writes, as `--agen` does for
an address register; `--sum-wait N` does the same for a source in mode 001
or 011, and a store address in mode 011, 101, or 111, the sums that
PREPARE forms; and `--dest-adjust N` gives a register destination in
mode 001 or 010, and a jump to a computed target, N cycles more in
WRITE. A store through `@R` or `@R++` never waits, since WRITE takes
the value it wrote last. With the four rules, the translated program's
phases take 2356816 cycles, against 2354763 without, and those of
`hand.nasm` 1252534 against 1248275. A fifth, `--read-late N`, also 1 by
default, has WRITE take read data N cycles after its ACK, but for a
micro-op whose data only goes into a register: s0 or s1 with a side
effect, and a `MOVE` into a register other than R15 (MICROARCH.md §5.3).
Without it, the phases take 2266828 cycles and 1172037. `pipecycles.py --test` checks the model on
small programs whose cycles are worked out by hand in the script, and
`make test` runs it, and then the model on both programs with `--phases
6`, which fails unless each reads the instruction counter around its six
phases.

`make compare` puts the estimate beside the cycles the pipelined core
took, phase by phase, from the output of `make core`,
which must have run first, on the same `.bin`. With the core that
predicts backward jumps (MICROARCH.md §5.4), and both programs closing
their loops with them:

| Phase | `bench.c`, model | Core | Model − core | `hand.nasm`, model | Core | Model − core |
|---|---|---|---|---|---|---|
| `rng64` | 82515 | 82571 | −56 | 62257 | 62270 | −13 |
| `crc32` | 80708 | 80765 | −57 | 40233 | 40246 | −13 |
| `bst` | 403351 | 403408 | −57 | 225654 | 225667 | −13 |
| `heapsort` | 378602 | 378658 | −56 | 273617 | 273630 | −13 |
| `vm` | 1248112 | 1248168 | −56 | 602050 | 602064 | −14 |
| `strings` | 163528 | 163585 | −57 | 48723 | 48736 | −13 |
| total | 2356816 | 2357155 | −339 | 1252534 | 1252613 | −79 |

The difference is all but the same in every phase of a program, so it
lies at the reads of the instruction counter around the phases, whose
timing the model does not follow exactly, and not in the phases. `make compare` prints the percentages of the table's last column, not the cycles.

`make core` also has the testbench write a retire log,
`hdl/build/bench_pipeline.retires` and `hand_pipeline.retires`
(`G_RETIRE_LOG` of `hdl/test/tb_core.vhd`): a line per step, with the
cycle it retired in and its address. `pipecycles.py --retires FILE`
compares the model with it, step by step. For each step it takes the
core's cycles since the step before, less the model's, and sums them by
the cause the model charged the step and by address, so the rules the
model lacks show up as causes and addresses with large sums. The runs
part where the program prints the cycles it measured, since the core's
differ from the emulator's, and the comparison stops there:

    python3 pipecycles.py --retires ../hdl/build/hand_pipeline.retires build/hand.bin

At commit 98d2bed the model is 289 cycles below the core over the first
1588218 steps of the translated program, which take the core 2258468
cycles, and 21 above it over the 493904 steps of `hand.nasm`, which take
1260090.

`cycprof.py` charges the model's cycles to the source lines of a program,
and `make profile` writes `build/bench.cyc.txt` and `build/hand.cyc.txt`.
It takes the assembly of the whole program and the `.bin` assembled from
it, runs the model as `pipecycles.py` does, and writes the source with
two columns in front of each line, how often its instruction ran and the
cycles it cost above one per run, and the causes after the line. The
cycles land on the instruction in whose WRITE the model saw them wait: a
taken jump's on the instruction at its target, and a math unit wait's on
the read of the result. In heapsort's inner loop, for example:

        7722   26800         ADD     R7, R1, 2                  early20100 fetch6700
        7722                 SUB[M]  R0, R7, R8
        7722                 ?V XOR  R14, R14, 0x10000000

`cycprof.py --test` checks the charging on a counted loop whose cycles
are worked out by hand in the script, and `make test` runs it.

## The size of a module

`words.py` gives the size in words of a wasm module translated by
nicewasm, the measure that [translator/README.md](../translator/README.md)
quotes for `test/safe.zig` and the float library. `make words` prints it
for `bench.wasm`, `translator/test/safe.wasm`, and `runtime/float.wasm`:
8537, 5156, and 7079 words. Each module is translated and
assembled on its own, with the labels it uses but does not define, such
as the runtime's routines, defined as 0 first; a constant takes a whole
word whatever its value (ISA.md §3), so that changes no size. The count
is the words the assembler emits, instructions and data, and not the
words that `.RES` reserves for the linear memory. `words.py --test`
checks the count on a snippet whose words are counted by hand in the
script, and `make test` runs it.

## Checking the results

The expected results are computed three ways. `expected.py` computes
each phase in Python from the sizes in `bench.c`, written again from the
phase's description rather than copied from the C. `make native` runs
the same C on the host. And `make test` runs the translated program and
the hand-written one on NICE. All must agree, and `make test` checks
that the `EXPECT` defines in `bench.c` and the `EXPECT` equates in
`hand.nasm` are the values of `expected.py`.

To change a size, edit its define in `bench.c` and its equate in
`hand.nasm`, run `python3 expected.py` and put its values in both files,
then `make wasm`. A smaller `VM_LOOPS` or `ARR_WORDS` is the quickest way
to a shorter run on the core.

## Dhrystone

`dhrystone/` holds Dhrystone 2.1 by Reinhold P. Weicker: `dhry.h`,
`dhry_1.c`, and `dhry_2.c`, from his 1990 posting to alt.sources, as
extracted in [Keith-S-Thompson/dhrystone](https://github.com/Keith-S-Thompson/dhrystone)
(`v2.1`). It is the benchmark that small processors publish numbers
for. The files state no license, and the MIT license of this repository does not
cover them (README.md). Whoever redistributes them must find out the terms
for themselves; the headers ask only that results be sent to the authors. It needs `malloc`, `strcpy`, `strcmp`, `printf`, and `scanf` from
the C library, and reads the number of runs from the console,
`dhrystone/dhry.input`.

The port is a system of its own, `NICE`, beside the original's `TIMES`,
`TIME`, and `MSC_CLOCK`, and changes only lines under `#ifdef NICE`, and
one `#ifndef` in `dhry.h` that would otherwise choose `TIMES`. The timer
is `nice_cycles`. The original prints its results with `%f`, which the C
library cannot print, and needs a run of two seconds. The port prints
the cycles of all the runs and of one run, and the Dhrystone MIPS per
MHz, 10⁶ / (1757 × cycles per run), with three decimals in integer
arithmetic, for any number of runs from 1. Given 0, or no number, it says
that the number must be at least 1, and `main` returns 1.

The sources are K&R C, so `make wasm` compiles them as C89. It follows
the ground rules in `dhry.h`: `dhry_1.c` and `dhry_2.c` are compiled
separately, and `-fno-inline` keeps the procedures apart. Inlining them
would take about 7% off the instructions. `main` returns no value, so R1 means
nothing at the end.

`dhrycheck.py` checks the output against a table of its own: the 22
final values in order, with their names and their "should be" lines,
where `Arr_2_Glob[8][7]` is the number of runs plus 10 and the two
`Ptr_Comp` are one address, not 0; the number of runs, which `--runs`
gives it from `dhry.input`; and the three result lines, which must agree
with each other and with the number of runs. `make test` runs it on the
emulator's output and `make core-dhry` on the core's.

100 runs, measured at commit 98d2bed:

| Where | Cycles per run | DMIPS/MHz |
|---|---|---|
| emulator (one cycle per instruction) | 1508 | 0.377 |
| multi-cycle core | 17479 | 0.032 |
| pipelined core | 2302 | 0.247 |

The emulator's row counts instructions. The program prints DMIPS/MHz truncated to three decimals. For comparison, Arm gives 0.87
DMIPS/MHz for the Cortex-M0 under the ground rules. The translation
through wasm accounts for much of the gap, judging by the ratios of
`hand.nasm` above.
