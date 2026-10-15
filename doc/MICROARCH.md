# NICE core microarchitecture

This is a design note for the FPGA implementation of NICE. It is a draft.
[ISA.md](ISA.md) is the specification, and it wins wherever this note
disagrees with it. "ISA §8.2" refers to a section of ISA.md, and a plain
"§5.3" to a section of this note.

The core is pipelined and has separate instruction and data buses, like
[qnice_cpu](https://github.com/MJoergen/qnice_cpu). It reuses that design
where NICE allows it. This note concentrates on where NICE differs.

A simple multi-cycle core, `hdl/src/multicycle.vhd`, comes first. It runs one
instruction at a time, with the same buses, interrupt ports, and trace
report as planned here. It passes steps 1 to 3 and 7 of the test order in
§9, and the interrupt probes of step 5 with the requests at fixed steps.
It is the working reference for the pipelined core
([hdl/README.md](../hdl/README.md)).

## 1. Decisions at a glance

| Topic | Decision |
|---|---|
| Structure | A pipeline: FETCH, ICACHE, DECODE, SEQUENCER, PREPARE, and WRITE, as in qnice_cpu. |
| Buses | Harvard: a read-only Wishbone instruction port and a Wishbone data port. Both see the same memory, through dual-port RAM. |
| Instructions | DECODE splits each instruction into one to three micro-operations. |
| Registers | R1–R13 in a register file with three read ports and one write port. R0 is a constant 0. SR (R14) and PC (R15) are separate registers. |
| Data accesses | Exact, in order, and never speculative, as ISA §8.2 requires. |
| Instruction fetches | Free to run ahead, as ISA §8.2 allows (§2). |
| Interrupts | Taken in WRITE, before an instruction, as soon as ISA §7.1 allows (§6). Valid/ready request ports for NMI and IRQ. |
| Language | VHDL-2008, GHDL for simulation, and SymbiYosys for formal verification. Synthesis for a board is done in the example design (§10). |
| Verification | A trace writer diffed against `niceemu --trace`, then formal checks with SymbiYosys. |
| Location | The `hdl/` directory, with commit prefix `nicehdl:` (§10). |
| Boards | None in this repository. The design is board-agnostic, and generics set the memory map (§10). |

## 2. Changes to the ISA

The ISA used to say that every memory access, instruction fetches included,
happens exactly once, in program order, and never speculatively. A pipeline
must fetch ahead, and a Harvard core cannot keep its two buses in one order.
So ISA.md was changed for this core:

- **ISA §8.2** splits accesses into instruction fetches and data accesses. Only
  data accesses (operand reads, destination writes, and vector reads) must be
  exact and in order. Instruction fetches may run early, repeat, or be wasted.
  Each instruction still runs with the words memory held once the
  instructions before it had completed, so self-modifying code works as
  before (§5.5).
- **ISA §8.3** says that instruction fetches never reach I/O devices. A fetch
  from `0xFFFFFF00`–`0xFFFFFFFF` reads 0. Without this, a fetch running ahead
  could start a device access. The emulator follows it, and
  `emulator/test/iofetch.nasm` tests it.
- **ISA §7.1** checks for interrupts "before each instruction", not "before
  each instruction fetch".
- **ISA §5** and **§9.4** name the two kinds of access where they referred to
  the old rule.
- **Appendix B** records both rules.

Nothing else in the ISA had to change. Conditional execution, the side
effects, R15 as an operand, and interrupts are all handled in the pipeline.

## 3. Pipeline

    FETCH --> ICACHE --> DECODE --> SEQUENCER --> PREPARE --> WRITE
      |                    |                         |          |
    instruction       REGISTERS                   MEMORY -------+
      bus              (3 reads)                (data bus)
      ^                                                         |
      +----------------- redirect and flush --------------------+

The stages do what they do in qnice_cpu, with these differences:

- **ICACHE** presents up to four words to DECODE: the instruction word and up
  to three constant words. DECODE takes the instruction only when all its
  words are present. The length follows from the instruction word (ISA §2.3).
- **DECODE** reads up to three registers: the bases of s0, s1, and dest. It
  knows PC, which is the instruction's address plus its length, so it does
  not read R15 from the register file. The one exception is an R15 operand
  after a side effect on R15 in the same instruction (ISA §4.3), which takes
  the slow path of §5.4. It emits the micro-operations of §4.
- **PREPARE** forms operand values and addresses, and issues data reads.
- **WRITE** holds the ALU and the shifter, writes registers and memory,
  updates SR, checks the condition, and starts flushes and interrupts.

All of this uses the valid/ready primitives of qnice_cpu's `src/sub/`.

## 4. Micro-operations

A micro-operation makes at most one register write, so the register file needs
one write port. DECODE emits:

| Micro-op | When | What it does |
|---|---|---|
| `S0` | s0 has a side effect on a register other than R0 (modes 001, 010, 101, and 110) | Reads s0 if it is in memory. Writes Rx ± 1. |
| `S1` | the same for s1 | Reads s0 first, if it is a memory operand not yet read. Then reads s1 if it is in memory, and writes Ry ± 1. |
| `OP` | always, for ALU and SHIFT instructions | Reads the memory sources not yet read. Computes r. Writes the destination and applies its side effect. Updates the flags. |
| `CTRL` | control instructions | `HALT`, `RTI`, `INT`, or a reserved word. |

Reads happen in field order, s0 then s1, as ISA §8.2 requires. That is why `S1`
also reads an s0 that has no micro-op of its own.

The common instructions need one micro-op: `ADD R1, R2, R3`, `MOVE R1, 5`,
the push `MOVE @--SP, x`, and the call `ADD @--SP, 2, PC`. A pop
`MOVE x, @SP++` and a return `MOVE PC, @SP++` need two. The most any
instruction needs is three.

**One write per micro-op is enough** because the two writes of a register
destination in mode 001 or 010 merge into one: Rx ← regval(x, regval(x, r) ∓ 1)
(§7.1). In a memory destination mode, the side effect is the only register
write.

**s1 can depend on s0's side effect**, as in `ADD R1, R2++, @R2`. `S0` writes
R2 in WRITE, before s1's address is formed. A bypass from WRITE to PREPARE, or
a stall, gives `S1` the new value.

## 5. Hazards

### 5.1 Registers

The register file writes before it reads, as in qnice_cpu. DECODE stalls an
instruction that reads a register an older micro-op in flight will write.
Bypasses can come later, once the stall counts are measured.

### 5.2 The condition

Every instruction is conditional, and the condition reads SR as it was before
the instruction started (ISA §3). Many instructions write SR, so this is the main
hazard.

- **A micro-op with no data access** checks the condition in WRITE, where SR
  is current. It needs no stall. If the condition is false, WRITE discards
  it. This covers the common pair `SUB[M] R0, a, b` followed by
  `?Z MOVE PC, label`.
- **A micro-op with a data read** must know its condition before PREPARE
  issues the read (§5.3). It waits in PREPARE while any older micro-op in
  flight can still change SR. A store is issued in WRITE, where the condition
  is known, so it needs no wait.
- **An instruction with condition "always"** never waits for SR.

The condition is decided once per instruction. A skipped instruction's
remaining micro-ops go through as bubbles, so none of its side effects
happen (ISA §3).

### 5.3 Data accesses

ISA §8.2 keeps data accesses exact, in order, and never speculative. So PREPARE
issues a data read only when the instruction is certain to run:

1. Its condition is known (§5.2).
2. No older micro-op in flight can still redirect: a write to R15, `RTI`,
   `INT`, a halt, or a store that may hit fetched code (§5.5).
3. Every older store has been issued, so the read cannot overtake it.
4. No interrupt request is pending that could be taken before it (§6): an
   NMI that is valid while `in_service` = 0, or an IRQ that is valid while
   `in_service` = 0 and either E = 1 or an older micro-op in flight may
   still set E. An IRQ with E = 0 does not count, or a program that never
   sets E could never read memory. The instruction directly after an `RTI`
   is exempt, because ISA §7.1 holds every request off until it has retired.
   The instruction after that is not.

When PREPARE issues an instruction's first data read, the core commits to
that instruction. No interrupt is taken before it (§6).

Stores are issued in WRITE, which is in order, so they need no extra rule.

This costs a cycle or two after conditional jumps and stores. If that turns
out to matter, the ISA could later let reads of RAM (not of the I/O range) be
speculative. That needs a check of each read against older stores, so it is
not part of the first version.

### 5.4 Control flow

WRITE flushes the stages above it and redirects FETCH when:

- A micro-op writes R15. This is every jump that DECODE did not resolve.
- An `INT`, an `RTI`, or an interrupt (§6) is taken.
- A store may hit a word already fetched (§5.5).

DECODE redirects early for jumps it can resolve itself: condition "always",
destination R15 in mode 000, and a source with no memory access, such as
`MOVE PC, label` and `ADD PC, PC, offset`. qnice_cpu does the same.

A side effect on R15 in `S0` or `S1`, such as `MOVE R1, @R15++`, must not
flush the instruction's own later micro-ops. As in qnice_cpu, the flush waits
for the instruction's last micro-op. A later operand of the same instruction
that reads R15 sees the side effect (ISA §4.3), so it takes R15 from the PC
register after that micro-op has retired, not from DECODE. R15 as a pointer
is rare, so a slow path is fine.

R14 used as an operand or base register is also rare. DECODE can stall such
an instruction until everything older has retired.

### 5.5 Self-modifying code

A store can change a word that FETCH has already read. WRITE compares each
store address with the words that are fetched but not yet retired. While
FETCH runs straight on, they are one range, from the storing instruction's
next PC to FETCH's current address. After an early redirect by DECODE (§5.4)
they are two: the words from the storing instruction up to the jump, and the
words from the jump's target to FETCH's current address. So WRITE checks the
range held in FETCH and ICACHE, from the oldest word ICACHE still holds to
FETCH's current address, and the one to four words of each instruction in
DECODE, SEQUENCER, and PREPARE. On a hit, it flushes and refetches from the
next instruction. Over-approximating is safe, because a needless flush costs
only cycles. qnice_cpu uses a fixed window of 32 words for the same purpose.

A store into the storing instruction's own constant words must not change
it, and refetching from the next instruction gives that.

## 6. Interrupts

Requests use valid/ready ports, as in qnice_cpu. The device holds `valid` and
the vector until the core raises `ready`. So the device holds the pending
state of ISA §7.1, and requests are never lost.

WRITE takes a request before an instruction, the first one after reset
included, when ISA §7.1 allows it: not halted, `in_service` = 0,
`after_rti` = 0, and E = 1 for IRQ. NMI goes first. Entry (ISA §7.2) flushes
the pipeline, saves PC and SR, reads the vector through the data port, and
redirects FETCH.

A request is taken at the first instruction boundary where ISA §7.1 allows
it, as in the emulator. ISA §7.1 says a request "is taken" when the
conditions hold, and promises that a request deferred during an interrupt
routine is taken before the second instruction after `RTI`. Rule 4 of §5.3
makes this possible: no younger instruction issues a data read while a
request is pending that could be taken before it, so the core never has to
choose between a wasted access and a late interrupt. The one delay is the
instruction after `RTI`, which `after_rti` protects until it has retired.

A request that arrives after a younger instruction has issued its first data
read is taken after that instruction. Software cannot tell this from a
request that arrived one instruction later, and ISA §7.1 leaves the timing of
the request signals to the hardware interface.

`INT` and `RTI` run in WRITE as `CTRL` micro-ops, and flush.

## 7. Datapath details

### 7.1 Register values

R0 is not stored. SR's bit 24 is a constant 1. Every value read from register
*x*, or produced by a side effect on *x*, goes through the function below.
The multi-cycle core applies it on every write instead, which gives the same
values.


    regval(x, v) = 0            if x = 0
                   v OR 2^24    if x = 14
                   v            otherwise

This covers several rules of ISA §4.3 that are easy to miss. `@--R0` addresses
word 0, not `0xFFFFFFFF`. `@--R14` after reset addresses `0x01FFFFFF`. `--R0`
reads 0. Every write to R14 sets bit 24. `MOVE R14--, 0` leaves `0x01FFFFFF`
(ISA §4.2).

### 7.2 ALU

The arithmetic operations share one 32-bit adder `A + B + k`, with A = s0:

| Operation | B | k | C flag |
|---|---|---|---|
| `ADD` | s1 | cin | carry out |
| `DBL` | s0 | cin | carry out |
| `MDBL` | s0 AND s1 | cin | carry out |
| `SUB` | NOT s1 | NOT cin | NOT carry out (the borrow) |
| `DEC` | `0xFFFFFFFF` | 0 | NOT carry out |

`cin` is SR's C bit if the instruction's C bit is set, and 0 otherwise. The
ALU is in WRITE, so `cin` is read after the side effects of `S0` and `S1`, as
ISA §5.1 requires. V is the usual adder rule for all five operations: A and B have
the same sign, and r has the other sign. This matches ISA §5.1 for subtraction,
because B is the inverted subtrahend.

The logic operations, `MOVE`, and `ONE` are a 16-way mux. X, Z, and N come
from r.

### 7.3 Shifter

The count is all 32 bits of s1, with no modulo (ISA §5.2). So the shifter uses the
closed forms of ISA §5.2. It needs three reduced counts:

- **Fixed-fill shifts:** n saturated to 33.
- **32-bit rotations:** n mod 32, which is bits 4..0.
- **33-bit rotations through carry** (`C<C`, `C>C`): n mod 33. Because
  32 ≡ −1 (mod 33), split n into 5-bit digits d0 (bits 4..0) to d6
  (bits 31..30). Then n ≡ d0 − d1 + d2 − d3 + d4 − d5 + d6 (mod 33). The sum
  lies between −93 and 96, so a few compare-and-subtract steps finish it.

The reduction does not depend on s0, so PREPARE can compute it and keep it
out of WRITE's critical path.

## 8. Memory system

The repository provides a system around the core: the core, dual-port RAM, the
bus decoders, a default slave, and the console UART. It is not tied to a
board. Generics set the memory map, for example the size and base address of
each RAM and the address of the UART. These rules hold for every setting:

- **Dual-port RAM.** The instruction port and the data port reach the same
  RAM. Any memory that the data port sees must be visible to the instruction
  port too, except the I/O range.
- **Unmapped addresses.** Both buses need a default slave that acknowledges a
  read with 0 and drops a write (ISA §8.2). Without one, the core would wait
  forever.
- **I/O.** Only the data bus reaches I/O. The instruction bus returns 0 for
  the I/O range (ISA §8.3).
- **Console.** A UART at `0xFFFFFF00` by default, as in the emulator
  (ISA §8.3). A write sends bits 7..0. A read returns the next received
  byte with bit 8 set, or 0 if none has arrived.
- **Math unit.** `hdl/src/mpu.vhd` at `0xFFFFFF20`–`0xFFFFFF3F` (ISA §8.4), 32
  aligned words, so the decoder compares address bits 31..5.
  A read of a result holds off its ACK until the result is ready, so the
  data bus must allow a slave to take many cycles.
- **Performance counters.** `hdl/src/perf.vhd` at `0xFFFFFF10`–`0xFFFFFF1F`
  (ISA §8.5). The core raises `instret_o` for one cycle per completed
  instruction. A read of `INSTR_LO` must count every older instruction, so
  the pipelined core raises it at the latest when the data read of a younger
  instruction is made, or holds that read off until it has.
- **Timer.** `hdl/src/timer.vhd` at `0xFFFFFF40`–`0xFFFFFF4F` (ISA §8.6),
  with its request on the core's IRQ port. It is the only device that
  raises IRQ so far, so it needs no interrupt controller.
- **Stack.** The runtime puts the stack just below `0xFFFFFF00`. A memory map
  that runs the runtime's programs needs RAM there as well as at address 0.

## 9. Verification

The main check is a line-by-line diff against the emulator's trace.

**The trace writer** is a simulation-only module, like `debug.vhd` in
qnice_cpu. WRITE reports each retired instruction: its address and word,
whether it was skipped, any interrupt taken, the halt reason, and the register
values. The writer prints what changed, in the emulator's format and order:
R0–R14 in order, R15 only after a jump, the memory write, and the halt reason.
The report is a `t_retire` record (`hdl/src/trace_pkg.vhd`), and the writer
is `hdl/sim/trace.vhd`.

**The testbench** has a sparse dual-port memory model that loads `.bin` files,
a console model that writes each byte into the trace stream when it is
written, a read counter that makes the number and order of data reads
visible, and random stalls (all in `hdl/sim/wb_mem.vhd`), and an interrupt
source that raises a request once a given number of instructions have
retired. The multi-cycle core takes a request only between steps, so its
test gives the emulator the same options and the diff is exact. For the
pipelined core, whether it takes a request before the next instruction or
after one that had already issued a data read depends on the pipeline state
(§6), so the trace cannot be predicted from the request step alone. Its
test will need a comparison script, not written yet, that reads from the
core's trace where each interrupt was taken, and runs the emulator with the
matching `--irq STEP:VEC` or `--nmi STEP:VEC` options. The diff is then
exact.

**Test order:**

1. The 2004 examples: `count`, `replicate`, and `print`, and `wrap`.
2. The emulator probes in `emulator/test/`.
3. `emulator/test/cputest.nasm`.
4. New hazard programs: back-to-back flag use, every pair of side effects on
   the same register, R14 and R15 as pointers, stores into the next few
   instructions, and jumps over `HALT`. qnice_cpu's `prog_hazard.asm` and
   `prog_pipeline.asm` are the model.
5. The interrupt probes, and requests at every point in a hazard program.
6. The runtime and translator test programs.
7. Random instruction streams, run on both and diffed.

**Formal checks**, as in qnice_cpu: each primitive and stage on its own, and
properties of the whole core. The checkers of the Wishbone and interrupt
ports in `hdl/formal/`, written for the multi-cycle core, apply to the
pipelined core too. The most important new property is the data
access rule of §5.3: every data access belongs to an instruction that retires,
and the accesses appear in program order.

## 10. Repository and boards

- **Directory.** The HDL lives in `hdl/`, with its own `make test`. Its commit
  subjects start with `nicehdl:`. Synthesisable code goes in `hdl/src/`, the
  simulation models in `hdl/sim/`, and the testbenches in `hdl/test/`.
- **No board.** This repository targets no particular board. Everything that
  depends on a board, including the memory map, is set by generics (§8).
- **Example design.** The example design for the MEGA65 lives in the separate
  [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65) repository, not here.
  It sets the generics, maps the screen at `0xFFFF0000` to video RAM if it
  wants one, adds the board's clocks and pins, and does the synthesis.
