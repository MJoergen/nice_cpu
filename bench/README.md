# bench

A benchmark for code that reaches NICE through wasm: `bench.c`, compiled
with clang and the small C library, translated by `nicewasm`, and run on
the emulator or on the core. Next to it is `hand.nasm`, the same
benchmark written in NICE assembly by hand, which shows how far the
translated code is from what the machine can do. Both are for measuring
the translator's output and the core, phase by phase, not for comparing
NICE with other processors.

    make            # run both on the emulator and print their tables
    make test       # the same, and check every result
    make core       # run both on the multi-cycle core in GHDL (about 20 minutes)
    make core CORE=pipeline  # the same on the pipelined core (about 20 minutes)
    make hazards    # count the pipeline hazards of MICROARCH.md §5 in both
    make cycles     # estimate the cycles of both on the pipelined core of MICROARCH.md
    make profile    # the same, charged to the source lines, in build/*.cyc.txt
    make words      # the size in words of the benchmark, safe.zig, and float modules
    make native     # build and run bench.c on the host, as a check
    make wasm       # rebuild bench.wasm from bench.c (needs clang)

`bench.wasm` is checked in, so `make` and `make test` need only Python 3
and the emulator, as the translator's tests do. `make wasm` needs clang
with the wasm32 target and wasm-ld, and it builds `runtime/libc/libc.a`
first.

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
of the phase, from the performance counters of ISA.md §8.5, then the
phase's result and whether it is the expected one. `main` returns the
number of phases with a wrong result, so R1 is 0 after a good run.

These are the tables from the emulator on 2026-10-19. First `bench.c`
through nicewasm:

    phase      instructions       cycles  result
    rng64            89632        89660  0e18cd0a  ok
    crc32            65816        65844  2df3b109  ok
    bst             315589       315617  55a72225  ok
    heapsort        312536       312564  bdb22882  ok
    vm              840049       840077  04156880  ok
    strings         105901       105929  d9867cf6  ok
    total          1729523      1729691

Then `hand.nasm`:

    phase      instructions       cycles  result
    rng64            39949        39953  0e18cd0a  ok
    crc32            27658        27662  2df3b109  ok
    bst             115203       115207  55a72225  ok
    heapsort        175654       175658  bdb22882  ok
    vm              112013       112017  04156880  ok
    strings          21140        21144  d9867cf6  ok
    total           491617       491641

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
  translated `switch` does, not through addresses in the program.
- The data layout is the natural one for a word-addressed machine. The
  byte buffer stays packed, four bytes to a word, as in linear memory.
  The strings have one character per word, as a C `char` does in ISA.md
  §9.3, the interpreter's program has one word per opcode or operand, and
  pointers are word addresses. The tree's nodes are four words, as in the
  wasm version.
- The C library routines of the strings phase are written inline.

The ratio of the instruction counts, translated to hand-written:

| Phase | Ratio | Where the translated code loses |
|---|---|---|
| `rng64` | 2.2 | `i64` shifts and the 64-bit product take the same two-word steps either way. |
| `crc32` | 2.4 | A byte load is seven instructions with its own bounds check, against a word read with a side effect on the pointer and shifts by hand. The table lookups need no check. |
| `bst` | 2.7 | Each node's fields take a compare and a skipped jump before their reads, which the hand-written code does without. |
| `heapsort` | 1.8 | The array elements take a compare and a skipped jump before their reads and writes, and the signed comparisons take two instructions either way. |
| `vm` | 7.5 | The `br_table` checks its index, each stack cell is a checked word access, and the bytecode fetch is a byte load of seven instructions, where the hand-written interpreter has one word per opcode and the operands in registers. |
| `strings` | 5.0 | Every character is a byte load of seven instructions, where the hand-written strings have one character per word. |
| total | 3.5 | |

What remains is in TODO.md, under "Faster and smaller translated code".
A byte load of linear memory stays several instructions, since the
memory is byte-addressed and packed four to a word (ISA.md §9.4).

On the multi-cycle core, which takes about ten cycles for a plain
instruction, the two programs ran like this on 2026-10-19:

| Program | Instructions | Cycles | Cycles per instruction | GHDL time |
|---|---|---|---|---|
| `bench.c` through nicewasm | 1729523 | 19834290 | 11.5 | 10 minutes |
| `hand.nasm` | 491617 | 5829021 | 11.9 | 3 minutes |

So the hand-written program is 3.5 times shorter in instructions and 3.4
times faster in cycles. On 2026-10-15, before the translator's register
allocator and inline memory accesses, the ratios were 6.8 and 7.3, and
the translated code took 12.6 cycles per instruction, because more of
its instructions had constant words and memory operands. Now `vm` and
`strings` have the most cycles per instruction in the translated
program, 12.0 and 11.9, and `rng64` in the hand-written one, 14.0,
because its reads of the math unit wait for the multiplier.

`make core CORE=pipeline` runs them on the pipelined core. On 2026-10-16:

| Program | Instructions | Cycles | Cycles per instruction | Faster than the multi-cycle core |
|---|---|---|---|---|
| `bench.c` through nicewasm | 3359061 | 6003616 | 1.79 | 7.1 times |
| `hand.nasm` | 491617 | 1541542 | 3.14 | 3.8 times |

The hand-written program gains less, because more of its time goes to
what a pipeline cannot hide: `rng64` waits for the multiplier, and `vm`
jumps through a table every three or four instructions, which flushes
the pipeline ([hdl/README.md](../hdl/README.md), The pipelined core).

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
share of all instructions:

    hand: 494070 instructions, 91075 skipped (18.4%)
      words        1: 39.0%  2: 59.7%  3: 1.3%  4: 0.0%   mean 1.62
      micro-ops    1: 82.3%  2: 17.5%  3: 0.2%   mean 1.18
      conditional                                                  137036  27.7%
      ...
      reads a register the previous instruction writes             148135  30.0%
      ...
      registers read from the previous instruction: R2 8.7%, R1 7.0%, ...

MICROARCH.md §5.6 has the table from 2026-10-15 and the decisions it led
to. `hazards.py --test` checks the counts on a small program whose hazards
are counted by hand in the script, and `make test` runs it. `make
typecheck` runs mypy on `expected.py`, `hazards.py`, and the tools below.

## The cycle estimate

`pipecycles.py` estimates the clock cycles a program takes on the
pipelined core of [MICROARCH.md](../doc/MICROARCH.md), which is not built
yet, and `make cycles` runs it on both programs. Like `hazards.py`, it
takes `.bin` files, which it runs on the emulator with `--trace`, or
traces. It is a model built from MICROARCH.md, not the core. Each
instruction of the trace is decoded as `hazards.py` decodes it, split
into its micro-operations, and sent through FETCH, DECODE, SEQUENCER,
PREPARE, and WRITE under the rules of §3 to §5: two words fetched per
cycle, a bubble of 2 cycles for a jump that DECODE resolves and of 5 for
one resolved in WRITE, a data read that waits for an older write of SR
or an older skipped jump, an address register written by the previous
micro-operation, one data access per cycle on the bus, and 35 cycles for
a result of the math unit. Every cycle above one per instruction is
charged to the rule that caused it, so the output says where the time
goes, and a program that reads the instruction counter around each phase,
as both programs do, gets a row per phase:

    bench.bin: 1774408 instructions, 2366863 cycles (estimate), CPI 1.334
      cycles above 1/instruction: 592455
      taken jumps resolved in WRITE (flush)                        191000  0.108/instr  32.2%
      math unit result not ready                                   143406  0.081/instr  24.2%
      ...

      phase         instr    cycles    CPI   main extra cycles per instruction
      rng64         89632    101952  1.137   mpu 0.10, early 0.02, fetch 0.01, flush 0.00
      ...
      total       1729523   2273490  1.315

On 2026-10-19 the phases of the translated program take an estimated
2273490 cycles, 1.3 per instruction, and those of `hand.nasm` 1361674,
2.8 per instruction: the hand-written code has more instructions with
side effects, memory operands, and reads of the math unit, and fewer
instructions in all. Options such as `--flush`, `--early`, `--agen`, and
`--mpu32` set the model's parameters, to try a design change before it
is built. `pipecycles.py --test` checks the model on small programs whose
cycles are worked out by hand in the script, and `make test` runs it.

`cycprof.py` charges the model's cycles to the source lines of a program,
and `make profile` writes `build/bench.cyc.txt` and `build/hand.cyc.txt`.
It takes the assembly of the whole program and the `.bin` assembled from
it, runs the model as `pipecycles.py` does, and writes the source with
two columns in front of each line, how often its instruction ran and the
cycles it cost above one per run, and the causes after the line. The
cycles land on the instruction in whose WRITE the model saw them wait: a
taken jump's on the instruction at its target, and a math unit wait's on
the read of the result. In heapsort's inner loop, for example:

        7722   13400         ADD     R7, R1, 2                  early13400
        7722                 SUB[M]  R0, R7, R8
        7722                 ?V XOR  R14, R14, 0x10000000

`cycprof.py --test` checks the charging on a counted loop whose cycles
are worked out by hand in the script, and `make test` runs it.

## The size of a module

`words.py` gives the size in words of a wasm module translated by
nicewasm, the measure that [translator/README.md](../translator/README.md)
quotes for `test/safe.zig` and the float library. `make words` prints it
for `bench.wasm`, `translator/test/safe.wasm`, and `runtime/float.wasm`:
on 2026-10-19, 8623, 5182, and 7083 words. Each module is translated and
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
