# Adversarial review of niceemu

Reviewed on 2026-10-14: `emulator/src/cpu.zig` and `emulator/src/main.zig` at commit 91eee00 ("Add niceemu, a NICE emulator in Zig"), against `doc/ISA.md`.

**How it was checked.** I read both files against the specification and confirmed that `make test` passes (15 unit tests, 3 example programs, Zig 0.15.2). Then I assembled nine probe programs with `niceasm` and ran them, covering the parts of the ISA that no unit test executes: every logic opcode, destination modes 001/110/111, unused operand fields (§4.4), the carry-input timing (§5.1), R15 side effects (§4.3), all sixteen conditions, the 33-bit rotations with a 2³²−1 count, VBASE ≠ 0 with a nested `INT`, `HALT` after `RTI`, self-modifying code (§8.2) and writes beyond memory. Then I ran about twenty-five bad command lines and `.bin` files. Finally I appended five tests to a copy of `cpu.zig` for interrupt cases that need `requestIrq`/`requestNmi`. Every input quoted below is complete and reproduces the result.

## Summary

**The core is faithful.** I found no divergence from ISA.md in any instruction, addressing mode, flag rule, or interrupt rule, including the corners the specification spent the most words on: R0 and R14 bit 24 within an instruction, R15 reading as the next instruction, the carry input taken after the source side effects, unused fields evaluated in full, shifts writing C only with M, `after_rti`, and NMI before IRQ.

The problems are around the core:

- One real bug: a trace line for an interrupt repeats the previous instruction's memory write (§1.1).
- Memory is a dense array, so nothing can ever live at a high address. The assembler's own `wrap.bin` cannot be loaded, the ISA's address wrap and I/O range are unreachable, and a stack placed high silently loses every write (§1.2).
- An out-of-memory `--mem-size` and an empty program are not reported (§1.3, §1.4).
- Error messages are decent but a few are vague or go to the wrong stream (§4).
- The tests pass but have real gaps: eight ALU opcodes, three destination modes, §4.4, the carry timing, twelve conditions, the trace, the loader, and the exit codes are never tested (§5).

## 1. Bugs and limitations

### 1.1 An interrupt's trace line repeats the previous instruction's write

In `step()`, `self.last_write = null` comes after the interrupt check. When an interrupt is taken, `traceInterrupt` calls `traceChanges`, which still sees the write of the instruction before. With `MOVE @0x50, 7` at address 0, vector 6 = `0x40`, and `requestNmi(6)` after the first step, the trace is:

    00000000 001c1800 [00000050]=00000007
    NMI 06         R14=81000000 R15=00000040 [00000050]=00000007

Interrupt entry makes no write, so the second `[00000050]=00000007` is wrong. The CLI cannot trigger it yet because no device raises interrupts, but the core's API can, and the README offers the trace for line-by-line comparison with the FPGA.

**Fix.** Clear `last_write` right after the `halted()` check, before the interrupt check. Add a trace test (§5).

### 1.2 Nothing can be placed at a high address

Memory is `[]u32` from 0 to `--mem-size`, and `--mem-size` is a `u32`. So no address at or above the size can hold a word: the loader rejects it, and `0xFFFFFFFF` is unreachable with any option, because `-m 0xFFFFFFFF` asks for 16 GB and still leaves `0xFFFFFFFF` outside. Consequences:

- `assembler/test/wrap.bin`, a fixture of this repository, cannot be run:

      wrap.bin:5: error: address ffffffff is beyond memory (see --mem-size)

  The message points at an option that cannot help.
- The address wrap of ISA.md §1.1 and the I/O range of §8.3 can never be exercised.
- A program that puts its stack high loses every push without any diagnostic:

          MOVE R13, 0x200000
          MOVE @--R13, 42
          MOVE R1, @R13
          HALT

  ends with R1 = 0 and exit status 0, and the trace shows `[001fffff]=0000002a` as if the store had stuck. The ISA says the write is ignored, so the behaviour is legal, but the emulator is the one place that could tell the programmer.

**Fix.** Make memory sparse: a map from page number (say the top 20 bits) to a `[4096]u32` page, allocated on first write. Then `--mem-size` goes away, the loader accepts any address, and the ISA's full address space is available. If the dense array stays, mark dropped writes in the trace (for example `[001fffff]=0000002a!`) and say in the README that `wrap.bin` cannot be run.

### 1.3 A `--mem-size` that cannot be allocated crashes with a raw error

    $ niceemu -m 0x40000000 count.bin        # under a 2 GB ulimit
    error: OutOfMemory

The error escapes `main` and Zig prints it. **Fix.** Catch it in `run()` and print `niceemu: cannot allocate 0x40000000 words of memory`, exit status 1.

### 1.4 An empty program is accepted and runs 100 million NOPs

An empty `.bin` loads without complaint. The processor then executes the all-zero NOP until the step limit:

    Stopped at the step limit after 100000000 steps, PC=05f5e100

That takes about a second and exits with status 3, as if the program were an infinite loop. **Fix.** Report `no words loaded` as a load error.

### 1.5 The instruction word is read twice per step

`step()` reads `mem[PC]` for the trace and then `execute()` fetches it again. With plain memory this is invisible. ISA.md §8.2 promises that each access is performed exactly once, and the README says I/O devices are planned, so the day a device is mapped, executing from it, or merely tracing, would read its register twice. **Fix.** Have `execute()` return the instruction word (or the trace data) instead of re-reading it. Similarly, `printMemory` and `printScreen` go through `cpu.read`, which will have to bypass device side effects once devices exist.

## 2. What is correct

Each probe below was assembled with `niceasm` and run. The results match ISA.md.

**Logic opcodes and `SUB[C]`** (§5.1). With R1 = `0xF0F0F0F0`, R2 = `0xFF00FF00`: `NOR` `000f000f`, `IAND` `0f000f00`, `NAND` `0fff0fff`, `XOR` `0ff00ff0`, `IOR` `ff0fff0f`, `XNOR` `f00ff00f`, `AND` `f000f000`, `OR` `fff0fff0`, `NOT R1` `0f0f0f0f`, `ONE` 1, `SUB[C]` with C = 0 `f1eff1f0`.

**Destination modes 001, 110, and 011/111, and unused fields** (§4.2, §4.4). The last two words are hand-encoded, because the assembler rightly refuses three operands for `MOVE` and `ONE`:

            MOVE R1, 0x100
            MOVE R1--, 5          ; R1 = 4
            MOVE R2, 0x200
            MOVE @R2++, 7         ; mem[0x200] = 7, R2 = 0x201
            MOVE @0x10[R2], 9     ; mem[0x211] = 9
            MOVE 0x20[R2], 11     ; mode 011 as destination: mem[0x221] = 11
            MOVE R3, 0x300
            .DAT 0x0000C0E2       ; MOVE R3, R1, @R2++   : unused s1 reads and bumps R2
            .DAT 0x01C148E2       ; ONE R5, --R1, @R2++  : unused s0 and s1 both apply
            HALT

Result: R1 = 3, R2 = `0x203`, R3 = 4, R5 = 1, mem[0x200] = 7, mem[0x211] = 9, mem[0x221] = `0xb`. All as specified.

**Carry input is the C flag as step 5 left it** (§5.1):

            MOVE R14, 0x03FFFFFF     ; C = 0
            ADD[C] R1, R14++, 0      ; the side effect carries into bit 26: C = 1 after step 5
            HALT

R1 = `0x04000000` (= s0 + 1), so cin was read after the source side effect. Reading it before would give `0x03FFFFFF`.

**R15 as operand and destination** (§4.3):

            MOVE R1, R15          ; 0:    R1 = 1
            ADD  R2, R15, 5       ; 1,2:  R15 reads 3, R2 = 8
            ADD  R4, R15++, R15   ; 3:    s0 = 4 and R15 <- 5, so s1 = 5: R4 = 9, next fetch at 5
            HALT                  ; 4:    skipped over
            MOVE R15++, 8         ; 5,6:  R15 = 8, then 9
            HALT                  ; 7:    trap
            HALT                  ; 8:    trap
            MOVE R3, 1            ; 9,10
            HALT                  ; 11

Result: R1 = 1, R2 = 8, R4 = 9, R3 = 1, halted at PC = `0xc`. This also covers the §4.3 exception (a source side effect on R15 is seen by the next operand) and the "last write wins" rule.

**All sixteen conditions** (§3). With R14 = `0xFF000000`, `?X ?C ?Z ?N ?V ?E ?I` each run and `?!X … ?!I` and `?!1` each skip; with R14 = `0x01000000` the negated forms run.

**33-bit rotations and a huge shift count** (§5.2). With C = 1 and R1 = `0x80000000`: `C<C[M] R2, R1, 1` gives R2 = 1 and C = 1; `C>C R4, R1, R3` with R3 = `0xFFFFFFFF` (n = 2³²−1 ≡ 3 mod 33) gives `0x30000000` and leaves C alone because M is clear; `0<0[M] R5, R1, R3` gives 0 with Z = 1 and C = 0.

**VBASE ≠ 0, the I flag, and a nested `INT`** (§7). With R14 = `0x01000001` (table at `0x100`) and vector 2 pointing at the routine, `INT 2` enters it with R14 = `0x81000001`; an `INT 3` inside it halts with `INT inside an interrupt routine` and exit status 2. `HALT` directly after `RTI` works (4 steps).

**Self-modifying code** (§8.2). `MOVE @0x4, 0x0C000000` followed by `MOVE R1, 1` (whose constant is word 4) gives R1 = `0x0C000000`.

**Interrupt ordering**, from the ad-hoc Zig tests: with IRQ 5 and NMI 6 both pending and E = 1, the NMI is taken, the IRQ stays pending through the routine, the instruction after `RTI` runs, and then the IRQ is taken with `saved_pc` = 1. The §11 instruction `0xB278C971 0x12345678`, when actually executed (the existing test only checks its encoding), decrements R2, adds mem[R1 + 0x12345678], stores at R3, and increments R3.

**Everything else I read.** The constant words are fetched before the condition and dest/s0/s1 order is right. The condition sees SR before the instruction. R14 register-direct destinations skip the flag update and force bit 24; memory-mode destinations on R14 do update the flags. Reserved control words are detected by `bits 20..8 ≠ 0 or (cmd ≠ INT and vector ≠ 0)`. `RTI` outside a routine halts. `after_rti` is cleared by a skipped instruction too. The `shift()` reduction of the count (mod 33, (n−1) mod 32 + 1, min(n, 33)) is correct for every one of the sixteen shifts, and the C result follows the §5.2 table exactly. Zig precedence is right everywhere (`&` binds tighter than `==`), all wrap-around arithmetic uses `+%`/`-%`, and no index or cast can trap on hostile input.

## 3. Things ISA.md leaves open that the emulator decided silently

These are not emulator bugs, but the FPGA will have to make the same choices, so ISA.md should state them.

- **`R14--` and `R14++` as destinations.** §4.2 says `Rx ← r − 1`; §4.3 says every write to R14 sets bit 24. The emulator writes r (bit 24 forced), then decrements, then forces bit 24 again. So `MOVE R14--, 0` gives `0x01FFFFFF`, where the literal `r − 1` would give `0xFFFFFFFF`. The emulator's reading is consistent with the `--R14` example in §4.3, and I think it is the right one, but §4.2 should say so.
- **What a step is.** The CLI counts an interrupt entry as a step: NMI, `RTI`, `HALT` is "3 steps". This affects `--max-steps` and the reported count. The README should say so.
- **Writes beyond memory in the trace** appear as ordinary writes (§1.2).
- **PC after a halt** is reported as the address after the halting word. Not observable in hardware, but the README could say what the printed PC means.

## 4. Error messages

**Good.** Loader errors carry `file:line:`. No program, a missing value, an unknown option, and two programs each get a clear one-line message, and the full usage is shown only when it helps. Exit statuses 0/1/2/3 behave as documented; I checked each.

**Nits.**

| Input | Message | Problem |
|---|---|---|
| `-n abc`, `-d :5` | `bad number 'abc'`, `bad number ''` | Does not say which option. Say `--max-steps: bad number 'abc'`. |
| a `.bin` line `hello world`, `00000000`, `00000000 0c000000 extra`, `100000000 0c000000` | `expected 'address word' in hex` for all four | One message for four faults. Say what was found: not hex, one field, three fields, value too wide. |
| `-h` | usage on **stderr**, exit 0 | `niceemu -h \| less` shows nothing. Help that was asked for belongs on stdout. |
| `-d 10` | `--dump wants ADDR:N, not '10'` | Names the long option when `-d` was typed. Trivial. |
| `-n 5000000000` | `bad number '5000000000'` | `max_steps` is a `u64`, but the parser is `u32`. Parse as `u64`, or say the limit. |

**Lenient loading, undocumented.** The format is "8-digit hex, space, 8-digit hex", but the loader accepts `0000_0000 0C00_0000`, `+1 +5`, and fields of any width, and a later line for the same address silently overwrites an earlier one (the assembler calls that an error). A `0x` prefix and a UTF-8 BOM are rejected. None of this matters for `niceasm` output; it only matters if the README is taken as a format definition.

## 5. Tests

**What is good.** The three 2004 programs are compared end to end with exact output; I re-derived `count` (12292 = 3 + 3·4096 + 1 steps, R1 = 4096·4097/2 = `0x800800`, R14 = Z + bit 24) and `replicate` (34 steps, R2 = `0x1a`, the dump equals program words 0–9) by hand and they are right. The `shift()` tests are thorough: every count regime, both directions, n = 0, and the C rule. The R0, R14 bit 24, R15/call-return, skip, reserved-word, and missing-memory tests each pin a sentence of ISA.md. The `run()` helper panics after 10 000 steps, so a wrong jump cannot hang the suite.

**Gaps.** Each of these would let a one-character typo through today.

| Area | Not tested | Suggested test |
|---|---|---|
| §5.1 ALU | `NOT NOR IAND NAND XOR IOR XNOR AND` are never executed (`OR` once, in the R14 test). `DEC`/`MOVE` with the C bit set. | The logic probe in §2; `alu(DEC, 5, 0, 1)` = 4. |
| §4.2 destinations | Modes 001 `Rx--`, 110 `@Rx++`, 111 `@c[Rx]` never run. The test named "worked example of §11" only checks the encoding of `0xB278C971`; it executes a different program. | Run the §11 instruction (R1 = `0x60 − 0x12345678` wrapping, so the operand lands at `0x60`). |
| §4.4 unused fields | Nothing. | The two hand-encoded words in §2. |
| §5.1 carry timing | Nothing. | The `ADD[C] R1, R14++, 0` probe. |
| §3 conditions | Only always, never, Z, !Z. The `Cond` enum stops at `nz`; !N, !V, !E, !I are not encodable. | The sixteen-condition probe. |
| §4.3 R15 | `R15++` as destination, the side-effect exception, last-write-wins. | The R15 probe. |
| §7 interrupts | NMI before IRQ when both pend; IRQ held through a routine; nested `INT` halts; `HALT` inside a routine; VBASE ≠ 0; `RTI` restoring E. | The two ad-hoc tests in §2 and the VBASE probe. |
| §8.2 | Self-modifying code. | The `selfmod` probe. |
| Trace | Nothing, although the README defines the format and it is the FPGA comparison tool. §1.1 is the result. | Trace into a `std.Io.Writer.fixed` buffer and compare lines, for a jump, a skip, a write, and an interrupt. |
| CLI and loader | Nothing. No exit code, no loader error, no option parser path. The assembler has `test/errors.py`; the emulator has no equivalent. | A shell or Python script that runs the binary on each bad input in §4 and checks message and status. |

**Hygiene.** The IRQ/NMI test pokes `cpu.saved_sr = 0` and `setReg(14, …)` halfway through with the comment "irrelevant from here"; splitting it into two tests would make each self-explanatory. The `.expected` files were produced by the emulator itself; a comment that `count` and `replicate` were checked by hand would record that they are not circular.

## 6. Nits

- Interrupt trace lines start the change list 3 columns left of instruction lines (`NMI 06` plus 8 spaces is 14 characters, `00000000 001c1800` is 17).
- The Makefile builds `niceemu` as ReleaseSafe but `zig build test` runs the unit tests in Debug. Probably intended; worth a comment.
- `README.md` says "Nothing is mapped at the I/O addresses … yet", which is true, but with the dense array the addresses themselves cannot exist (§1.2).

## 7. Second round, commit 99feb8d

Checked on 2026-10-14 against commit 99feb8d ("niceemu: fix the issues from the adversarial review"). `make test` passes: 24 unit tests, 13 programs with exit statuses, and 27 command-line and loader cases.

### 7.1 Confirmed fixed

- **§1.1** `last_write` is cleared before the interrupt check, and `trace: an interrupt line shows no write of the instruction before` pins it.
- **§1.2** Memory is sparse (4096-word pages in a hash map, one-entry cache, allocated on the first nonzero write). `wrap.bin` loads and `test/addr.asm` executes across `0xFFFFFFFF` → 0, reads R15 as 0 there, and keeps a stack at `0x1FFFFF`. `--mem-size` is gone and is rejected as an unknown option. The cache costs about 25 % when code and data alternate between pages (16M-iteration loop: 0.93 s against 0.73 s on one page), and 100M NOPs take 1.2 s against 0.9 s before. Acceptable.
- **§1.3** With a 300 MB address-space limit, a program that touches a new page per iteration ends with `niceemu: out of memory`, exit status 1, and the trace written so far is flushed (56 002 lines).
- **§1.4** An empty file and a blank-only file give `error: no words to load`.
- **§1.5** `execute()` returns the instruction word; dumps and the screen use `peek()`, which is documented as not being a §8.2 access.
- **§3** ISA.md §4.2 and Appendix B now state the `R14--`/`R14++` rule; the README defines a step and the printed PC.
- **§4** Every message in the table is fixed and has a case in `test/errors.py`; `-h` goes to stdout; the loader is strict (1–8 hex digits, no `0x`, `_`, or sign, duplicates rejected) and the README says so.
- **§5** Every gap in the table has a test: `alu()` for the logic ops plus `logic.asm`, the executed §11 instruction, `dest.asm`, `carry.asm`, all sixteen conditions in `cond.asm` and the full `Cond` enum, `r15.asm`, NMI before IRQ, the IRQ waiting through a routine, `RTI` restoring E, `HALT` and `INT` inside a routine, VBASE, `selfmod.asm`, two trace tests, and the exit statuses. The interrupt test is split in three with a shared fixture, and the Makefile records that `count` and `replicate` were checked by hand.
- **§6** Interrupt trace lines are padded to 17 characters, and the Makefile explains Debug against ReleaseSafe.

The streaming-stdout change also holds: `(niceemu x.bin; echo) > log` keeps all six lines in order.

### 7.2 Nits

- `niceemu -t x.bin | head -2` ends with `error: WriteFailed` on stderr and exit status 1 once `head` closes the pipe. Catch `error.WriteFailed` in `main` and exit quietly, as other filters do.
- The README's `make` comment still says "unit tests, then the example programs"; the probes and `test/errors.py` run too, and the latter needs Python 3.

## 8. Third round, commit 6199dd8

Checked on 2026-10-14. `make test` passes (28 error cases). Both nits of §7.2 are fixed: `niceemu -t x.bin | head -1` ends with status 141 and nothing on stderr, `niceemu x.bin > /dev/full` prints `niceemu: cannot write the output: NoSpaceLeft` with status 1, and the README names Python 3 and the full `make test` contents.

One nit left: `-h` writes the usage with a plain `try writeAll`, so a closed pipe there would still surface as a raw `error: BrokenPipe` rather than go through `outputFailed`. Harmless in practice, since the usage is 600 bytes.

## 9. Fourth round, commit dd42e91: `--irq` and `--nmi`

Checked on 2026-10-14. The commit adds `--irq STEP:VEC` and `--nmi STEP:VEC` to `main.zig`, the probes `irq` and `merge`, seven `errors.py` cases, and a README section. `make test` passes (24 unit tests, 4 examples, 11 probes, 35 error cases).

**How it was checked.** I read the diff against ISA.md §7 and §8.1, traced `irq.asm` and `merge.asm` by hand and compared every line with the `.expected` files, and then assembled eight more probes for the corners the two probes leave out: merging across steps, `INT`, `HALT`, a skipped instruction, and a second `RTI` as the instruction after `RTI`, an NMI before the first instruction, E cleared by the instruction after `RTI`, and E set inside a routine. Then I tried about ten odd command lines. Every input quoted below is complete and reproduces the result.

### 9.1 Summary

**The core and the CLI are right.** Both `.expected` files are correct: `irq` logs `B1 A1 A2 C1 C2 A3 B1 A4 B1 A5 C1 C2` in 26 steps, and `merge` takes vector 2 and halts in 5 steps with the IRQ still pending. The request loop raises every request at its step and never after a halt, the sort is stable, and the parser rejects every malformed value with a message that names the option. None of the eight extra probes found a divergence from ISA.md.

What is left is in the words, not the code:

- The README documents merging only for two requests at the same step, but any request of a kind already pending replaces it (§9.3).
- ISA.md §7.1 says a deferred request "waits at most one instruction after `RTI`". That is not true when that instruction is an `INT`, halts, or clears E (§9.3).
- ISA.md §1.4 defines `halted` as "1 after `HALT`" and forgets the three other halts (§9.3).
- Four interrupt rules still have no test, among them the one the README now states and the §1.4 rule about a skipped instruction after `RTI` (§9.4).

### 9.2 What is correct

**Merging across steps.** With E = 0 until step 3:

        MOVE    R14, 1          ; 0: VBASE = 1
        MOVE    R1, 0           ; 1
        MOVE    R2, 0           ; 2
        OR      R14, R14, 0x40000000 ; 3: E = 1
        HALT                    ; 4: IRQ taken before this
    v5  MOVE    R1, 5
        RTI
    v6  MOVE    R1, 6
        RTI
        .ORG    0x105
        .DAT    v5
        .DAT    v6

`--irq 1:5 --irq 3:6` takes `IRQ 06` and ends with R1 = 6; vector 5 is never seen. That is what `requestIrq` says it does ("requests that arrive while one is pending merge into one") and is within §7.1's "may merge".

**`INT` as the instruction after `RTI`, with an NMI pending.** Vectors 1, 3, and 4 point at routines that log `BB`, `B3`, and `B4` at R13, and the main program is `INT 3`, `INT 4`, log `A1`, `HALT`. With `--nmi 3:1`, raised inside the first routine, the log is `B3 B4 A1 BB`: the `INT 4` runs first, as §7.1 says, the NMI waits through its routine because `in_service` = 1 again, the instruction after the second `RTI` runs, and only then is the NMI taken.

**`HALT` as the instruction after `RTI`, with an NMI pending.** `INT 3`, `HALT`, routine `RTI`, with `--nmi 2:1`: the NMI is never taken, 4 steps, exit status 0. As §7.1 says for a halt.

**A skipped instruction after `RTI` clears `after_rti`** (§1.4, "whether or not its condition is true"). `INT 3`, `?!1 MOVE R1, 0xA1`, `MOVE R2, 0xA2`, `HALT`, with `--nmi 2:1`: the trace shows `skipped` and then `NMI 01` directly, before the `MOVE R2`.

**`RTI` after `RTI`.** `?!1 RTI` outside a routine is skipped and does not halt; a real `RTI` as the instruction after `RTI` halts with `RTI outside an interrupt routine`, exit status 2.

**NMI before the first instruction.** With VBASE = 0 and `.DAT 0x20` at word 3, `-t --nmi 0:3` starts the trace with `NMI 03            R14=81000000 R15=00000020`: §8.1's warning that word 3 is both code and vector table, made visible.

**E around `RTI`.** If the instruction after `RTI` clears E, a pending IRQ waits until software sets E again (`AND R14, R14, 0xBFFFFFFF`, `MOVE R1, 0xA1`, `OR R14, R14, 0x40000000`: the IRQ is taken after the `OR`). If the routine sets E and `RTI` restores E = 0, the IRQ is never taken.

**The CLI.** `--irq 5:1:2` gives `bad number '1:2'`, `--irq=1:2` is an unknown option like `-d=`, `-n 2 --nmi 2:3` never raises the request, and `--nmi 0:0` takes vector 0 through word 0. Hex works in both fields. `std.sort.insertion` is documented as stable, so the "last wins" comment holds.

### 9.3 Documentation

**README, merging.** "Two requests of one kind raised at the same step merge, and the vector given last wins" is the special case. The rule the code implements, and the one a user of `--irq` needs, is: a request of a kind that is already pending replaces it, so the vector given last wins, whether the two were given for the same step or for different steps. The probe in §9.2 shows the difference. Say so, and make `merge.asm` show it (§9.4).

**ISA.md §7.1, "waits at most one instruction".** The paragraph says: "A deferred NMI waits at most one instruction after `RTI`. A deferred IRQ does the same if E = 1 in the restored SR, and otherwise waits until software sets E." Three cases break it, all run in §9.2:

- The instruction after `RTI` is an `INT`. The sentence before it says that works normally, but then the request waits through that routine too, and for the instruction after its `RTI`, and so on for every `INT` in that position.
- The instruction after `RTI` halts. The request is never taken.
- For an IRQ, the instruction after `RTI` clears E. Then E = 1 in the restored SR, but the IRQ waits.

Suggested wording: "A deferred request is taken before the second instruction after `RTI`, unless the first one is an `INT` (then it waits for that routine's `RTI` as well), halts the processor, or, for an IRQ, leaves E = 0." That keeps the guarantee that matters, progress of the interrupted program, and drops the bound that does not hold.

**ISA.md §1.4, `halted`.** "1 after `HALT`. Only reset clears it." Reserved control words (§5.3), `INT` inside a routine (§7.2), and `RTI` outside one (§7.4) also halt the processor, and the emulator's `HaltReason` has all four. Say "1 after `HALT` or any other halt (§5.3, §7.2, §7.4)".

**README, "pending at reset".** "`--nmi 0:5` makes an NMI pending at reset" reads against §8.1's "Pending interrupt requests: none" after reset. The request is raised after reset and before the first instruction, which is what the probe shows. Say "before the first instruction".

**README, what a step number is.** "Counted from 0 as in the step count that niceemu prints" is hard to use, because the printed number is a total. What a user needs: a request before step N is raised after N steps have run, so with `--trace` it comes before line N + 1, and `--nmi 0:v` comes before the first line.

**README, "show each rule".** The `--nmi 0:5` rule is in neither probe, and `merge.asm` merges NMIs only. Either drop "each" or add the cases (§9.4).

**README, "after the processor halts".** A request for step N is also never raised with `-n N`, when the processor does not halt. Trivial.

### 9.4 Tests

| Rule | Not tested | Suggested test |
|---|---|---|
| §1.4: a skipped instruction after `RTI` clears `after_rti` | Nothing. §2 above says it is so from reading the code, and only this round ran it. | A `?!1 MOVE` as the first instruction after a return point in `irq.asm`, or a unit test next to "no interrupt right after RTI". |
| §7.1: `INT` as the instruction after `RTI` works normally, and a pending request waits through it | Nothing. | The `B3 B4 A1 BB` probe of §9.2. |
| README: merging across steps | Nothing. `merge.asm` raises both NMIs at step 1. | `--irq 1:5 --irq 3:6` with E set after step 3, as in §9.2. |
| README: `--nmi 0:v` | Nothing. Both probes start at step 1 or 2. | `-t --nmi 0:3` on the word-3 probe of §9.2; the first trace line is the check. |

### 9.5 Nits

- `requestNmi`'s doc comment lacks the sentence on merging that `requestIrq`'s has.
- `std.fmt.parseInt` accepts `+5` and `1_0`, so `--irq 0:+5` and `--irq 0:1_0` are taken. The same holds for `-d` and `-n` since the first round; the README says only "decimal or 0x hex".
- The numbers in the line comments of `irq.asm` and `merge.asm` (`; 0,1: VBASE = 1`) are word addresses, while the header comment of each file numbers steps. Both are bare numbers. "Words 0,1" would separate them.
- Nothing shows a request that is still pending when the program stops. One line after the halt line, such as `Pending: IRQ 02`, would make the "never taken" rule visible instead of inferred from an absence.

## 10. Fifth round, commits 0883db0 and c7012b2

Checked on 2026-10-14. `make test` passes (24 unit tests, 4 examples, 13 probes, 40 error cases), and `make bins` leaves `test/` unchanged. Every item of §9 is fixed, and each fix was run, not just read.

**ISA.md.** §1.4 now defines `halted` by any halt, with the three section references. §7.1 states the deferred-request rule with the `INT`, halt, and E = 0 exceptions, in the wording §9.3 proposed. Appendix B's row on `after_rti` is still accurate.

**Probes.** I traced the three `.expected` files by hand. `after` logs `B3 B4 A1 B1 B1 A3` in 18 steps with R13 = `0x206`: the `INT 4` runs before the pending NMI, the NMI waits through its routine, and the skipped `MOVE` at word 8 counts as the instruction after `RTI`. `merge` takes `NMI 02` and then `IRQ 04`, which replaced `IRQ 03` across steps, and ends after 10 steps with `Pending: IRQ 05`, R1 = 2, R2 = 4, R3 = 3. `start` begins its trace with `NMI 03            R14=81000000 R15=00000004` and returns to word 0. All three step lists in the header comments are right, and the line comments now say "words".

**The pending line.** `Pending: NMI 01 IRQ 02` appears with both kinds pending, `Pending: IRQ 05` after `Stopped at the step limit`, and `Pending: IRQ 07` after a halt inside a routine, each on the line after the first one, as the README says.

**Numbers in options.** `+5`, `1_0`, `0b11`, `0x`, `0xg`, and `1e3` are all rejected with `bad number`, naming the option; `007` is decimal 7, and `0x10` still works. The `InvalidCharacter => unreachable` in `parseNumber` is sound: every character has passed `charToDigit` for the base before `parseInt` sees it, and the sign and `_` cases that `parseInt` would accept fail that check first.

One trivial thing left: `0X3` is accepted as hex while the README and the usage say `0x`.
