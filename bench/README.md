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
    make compare    # the estimate beside the pipelined core's cycles, after make core CORE=pipeline
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
of the phase, from the performance counters of SYSTEM.md §3, then the
phase's result and whether it is the expected one. `main` returns the
number of phases with a wrong result, so R1 is 0 after a good run.

These are the tables from the emulator. First `bench.c`
through nicewasm:

    phase      instructions       cycles  result
    rng64            52768        52796  0e18cd0a  ok
    crc32            65816        65844  2df3b109  ok
    bst             310469       310497  55a72225  ok
    heapsort        307416       307444  bdb22882  ok
    vm              840049       840077  04156880  ok
    strings         104562       104590  d9867cf6  ok
    total          1681080      1681248

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
  The strings have one character per word, as a C `char` does in ABI.md, the interpreter's program has one word per opcode or operand, and
  pointers are word addresses. The tree's nodes are four words, as in the
  wasm version.
- The C library routines of the strings phase are written inline.

The ratio of the instruction counts, translated to hand-written:

| Phase | Ratio | Where the translated code loses |
|---|---|---|
| `rng64` | 1.3 | `i64` shifts take the same two-word steps either way, and the 64-bit product three products of the math unit. |
| `crc32` | 2.4 | A byte load is seven instructions with its own bounds check, against a word read with a side effect on the pointer and shifts by hand. The table lookups need no check. |
| `bst` | 2.7 | Each node's fields take a compare and a skipped jump before their reads, which the hand-written code does without. |
| `heapsort` | 1.8 | The array elements take a compare and a skipped jump before their reads and writes, and the signed comparisons take two instructions either way. |
| `vm` | 7.5 | The `br_table` checks its index, each stack cell is a checked word access, and the bytecode fetch is a byte load of seven instructions, where the hand-written interpreter has one word per opcode and the operands in registers. |
| `strings` | 4.9 | Every character is a byte load of seven instructions, where the hand-written strings have one character per word. |
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

`make core CORE=pipeline` runs them on the pipelined core, on the same
programs as the multi-cycle core above, at commit 4bbbb81, which leaves
the multi-cycle core as it was:

| Program | Instructions | Cycles | Cycles per instruction | Faster than the multi-cycle core |
|---|---|---|---|---|
| `bench.c` through nicewasm | 1681080 | 2351908 | 1.40 | 8.1 times |
| `hand.nasm` | 491617 | 1333925 | 2.71 | 4.2 times |



The hand-written program gains less, because more of its time goes to
what a pipeline cannot hide: `vm` jumps through a table every three or
four instructions, which flushes the pipeline, and `strings` and `bst`
read the math unit right after writing its operands
([hdl/README.md](../hdl/README.md), The pipelined core).

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

    hand: 494272 instructions, 91075 skipped (18.4%)
      words        1: 39.0%  2: 59.7%  3: 1.3%  4: 0.0%   mean 1.62
      micro-ops    1: 82.3%  2: 17.5%  3: 0.2%   mean 1.18
      conditional                                                  137036  27.7%
      ...
      reads a register the previous instruction writes             148135  30.0%
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
`ADD R15, R15, c` with the condition "always", as in the core; a `MOVE`
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
cycle, a bubble of 2 cycles for a jump that DECODE resolves and of 7 for
one resolved in WRITE, a data read that waits for an older write of SR
or an older skipped jump, an address register written by the previous
micro-operation, one data access per cycle on the bus, read data that
reaches WRITE a cycle after its ACK unless it only goes into a register,
and the math unit of `hdl/src/mpu.vhd`: a product two cycles after the write of an operand,
and a quotient after one cycle per bit, less the runs of eight zero bits
that the divider skips, which the model works out from the operands in
the trace. Every cycle above one per instruction is
charged to the rule that caused it, so the output says where the time
goes, and a program that reads the instruction counter around each phase,
as both programs do, gets a row per phase:

    bench.bin: 1726106 instructions, 2338396 cycles (estimate), CPI 1.355
      cycles above 1/instruction: 612290
      taken jumps resolved in WRITE (flush)                        266700  0.155/instr  43.6%
      jumps DECODE resolves (early-redirect bubble)                 63898  0.037/instr  10.4%
      ...

      phase         instr    cycles    CPI   main extra cycles per instruction
      rng64         52768     74312  1.408   mpu 0.34, early 0.04, fetch 0.02, readlate 0.01
      ...
      total       1681080   2260097  1.344

The core's bubble is 6 cycles, as `hdl/test/bubble.nasm` measures. A
jump leaves WRITE in cycle c − 1 and flushes in the same cycle, since
the flush is combinational. FETCH issues the request in c, so it is on
the bus in c + 1, and the memory acknowledges in c + 2. DECODE takes the
instruction in c + 3 and emits its micro-op in c + 4, PREPARE passes it
on in c + 5, and WRITE runs it in c + 6. The model's 7 is a fit: with
`--flush 6` it is 4.6% below the core's cycles for the translated
program and 10.5% below for `hand.nasm`, with 7 3.1% and 6.6%, so the
extra cycle stands in for something the model lacks. The hand-counted
cases of `pipecycles.py --test` and `cycprof.py --test` use the 7.

The phases of the translated program take an estimated
2260097 cycles, 1.34 per instruction, and those of `hand.nasm` 1203605,
2.4 per instruction: the hand-written code has more instructions with
side effects, memory operands, and reads of the math unit, and fewer
instructions in all. Options such as `--flush`, `--early`, `--agen`,
`--mul`, and `--div-skip` set the model's parameters, to try a design
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
phases take 2260097 cycles, against 2258384 without, and those of
`hand.nasm` 1203605 against 1202581. A fifth, `--read-late N`, also 1 by
default, has WRITE take read data N cycles after its ACK, but for a
micro-op whose data only goes into a register: s0 or s1 with a side
effect, and a `MOVE` into a register other than R15 (MICROARCH.md §5.3).
Without it, the phases take 2171133 cycles and 1122967. `pipecycles.py --test` checks the model on
small programs whose cycles are worked out by hand in the script, and
`make test` runs it, and then the model on both programs with `--phases
6`, which fails unless each reads the instruction counter around its six
phases.

`make compare` puts the estimate beside the cycles the pipelined core
took, phase by phase, from the output of `make core CORE=pipeline`,
which must have run first, on the same `.bin`. At commit 4bbbb81:

| Phase | `bench.c`, model | Core | Model against the core | `hand.nasm`, model | Core | Model against the core |
|---|---|---|---|---|---|---|
| `rng64` | 74312 | 83076 | −10.5% | 62481 | 66339 | −5.8% |
| `crc32` | 76603 | 85108 | −10.0% | 41998 | 45855 | −8.4% |
| `bst` | 405711 | 412973 | −1.8% | 256281 | 279699 | −8.4% |
| `heapsort` | 375849 | 386464 | −2.7% | 289631 | 305038 | −5.1% |
| `vm` | 1170099 | 1220162 | −4.1% | 492044 | 574061 | −14.3% |
| `strings` | 157523 | 164125 | −4.0% | 61170 | 62933 | −2.8% |
| total | 2260097 | 2351908 | −3.9% | 1203605 | 1333925 | −9.8% |

The model is below the core in every phase, by up to 14%, most in `vm`
of `hand.nasm` and in `rng64` and `crc32` of the translated program. It
does not model DBUS's store register yet (TODO.md).

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
8447, 5170, and 7083 words. Each module is translated and
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
