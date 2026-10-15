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

These are the tables from the emulator on 2026-10-15. First `bench.c`
through nicewasm:

    phase      instructions       cycles  result
    rng64            88642        88700  0e18cd0a  ok
    crc32           146487       146545  2df3b109  ok
    bst             574615       574673  55a72225  ok
    heapsort        802646       802704  bdb22882  ok
    vm             1554096      1554154  04156880  ok
    strings         192575       192633  d9867cf6  ok
    total          3359061      3359409

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
| `crc32` | 5.3 | A byte load is a helper call, and the operand stack lives in frame words. |
| `bst` | 5.0 | Each field access computes a byte address, checks it, and tests its alignment. |
| `heapsort` | 4.6 | The same for each array element, and the `?:` becomes a comparison materialized as 0 or 1 and then a `select`. |
| `vm` | 13.9 | The `br_table` checks and loads its table, each stack operation is several accesses, and the bytecode fetch is a helper call. |
| `strings` | 9.1 | Every character goes through a byte helper and a library call. |
| total | 6.8 | |

The first column of TODO.md's list of translator optimizations, trusting
the alignment hint, and the second, the operand stack in registers, aim
at exactly the costs in the middle rows.

On the multi-cycle core, which takes about ten cycles for a plain
instruction, the two programs ran like this on 2026-10-15:

| Program | Instructions | Cycles | Cycles per instruction | GHDL time |
|---|---|---|---|---|
| `bench.c` through nicewasm | 3359061 | 42487187 | 12.6 | 17.5 minutes |
| `hand.nasm` | 491617 | 5829021 | 11.9 | 2.3 minutes |

So the hand-written program is 6.8 times shorter in instructions and 7.3
times faster in cycles. The translated code takes more cycles per
instruction because more of its instructions have constant words and
memory operands. In both programs `rng64` has the most cycles per
instruction, 14.9 and 14.0, because its reads of the math unit wait for
the multiplier.

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
