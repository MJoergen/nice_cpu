# Adversarial review of niceasm

Reviewed on 2026-10-14: `assembler/niceasm.py` at commit 55a6913 ("niceasm: add type hints"), against `doc/ISA.md` §2, §4, §5.3, §10, and §11.

**Status after commit 0670e53** ("niceasm: fix the issues from the adversarial review"), checked the same day: every item in sections 1, 2, and 4 is fixed, and each has a case in `test/errors.py` or a line in `test/encoding.asm`. Section 5 is the second round against the new code. It found one crash on an unrealistic input and a few message nits, nothing that affects correct programs.

**How it was checked.** I read the code against the specification, confirmed that `make test` passes, checked the shift alias table and the control encodings by hand, and then ran about sixty one- to five-line probe programs through the assembler to see what it accepts, rejects, and reports. The probe files were not kept; every input quoted below is complete and reproduces the result.

## Summary

The encoder is correct. Every encoding I checked matches ISA.md, the two passes always agree on sizes, and the three 2004 example binaries still match byte for byte. The problems are in input validation and error reporting:

- Two kinds of line are silently dropped.
- `.EQU` can redefine a register name.
- `.BLK` with a negative or huge count hangs or exhausts memory.
- Several error messages point at the wrong token or the wrong line.
- There are no tests for any error path.

## 1. Bugs

### 1.1 Lines can be silently dropped

`tokenize()` (line 266) hits `break` instead of raising when the token regex fails to match at the start of a line. Two inputs trigger it:

    ,MOVE R1, R2
     MOVE R3, R4

assembles to one word (`MOVE R3, R4`) with exit status 0. Likewise

       'oops
     MOVE R3, R4

drops line 1. Only an unterminated quote in column 1 is reported, because the `text[pos]` check at line 267 looks at the first character of the line, not at the character where the match failed.

**Fix.** Raise on any failed match. Report "unexpected character ','" or "unterminated string" depending on the character at the failure position.

### 1.2 `.EQU` can redefine a register

    R1 .EQU 5
     MOVE R1, R2

is accepted and assembles to `000c0100 00000005`, which is `MOVE 5, R2`: a store to memory word 5. Labels are checked against register names (line 314), but `.EQU` names (line 295) are not.

The same check should also reject mnemonic and directive names. `ADD .EQU 5` is accepted. It can never be used as a label, because `ADD` at the start of a line is parsed as an instruction, but it still substitutes as a constant in `MOVE R1, ADD`.

### 1.3 `.BLK` with a bad count hangs or exhausts memory

`.BLK -1` wraps to 2³²−1 and loops in pass 1 until killed. A typo such as swapping the operands of `.BLK end-start` produces the same thing.

Large counts that do not wrap are also a problem, because each zero word becomes a dict entry:

| Input | Time | Memory | Output |
|---|---|---|---|
| `.BLK 0x2000000` | 28 s | 4.7 GB | 604 MB |

**Fix.** Reject a count that would carry the PC past 2³². Consider recording `.BLK` as a range and expanding it only when writing the output.

### 1.4 A condition on a directive is only caught when it is non-zero

Line 334 tests `if cond:`, and `?1` encodes as 0. So `?1 .DAT 1` and `?1 .ORG 5` are accepted. Test for the presence of the condition token instead.

### 1.5 The default output can overwrite the input

`niceasm.py prog.bin` reads `prog.bin` as source and then writes the result to `prog.bin`. Refuse when the output path equals the input path.

### 1.6 Documentation mismatch on `.EQU`

ISA.md §10.3 says `.EQU` "is substituted textually, so it can stand for a number or a register". Only a number, an expression, or a register survives substitution:

| Input | Result at the use site |
|---|---|
| `X .EQU @R2` then `MOVE R1, X` | `expected a number or a symbol at '@R2'` |
| `X .EQU R1++` then `MOVE R2, X` | `bad expression 'R1++'` |

Either support full operands or say in ISA.md and the README that an `.EQU` value is a number, an expression, or a register name.

### 1.7 Things accepted without complaint

These may or may not be intended. None is wrong by the letter of ISA.md.

- `1_000` and `0x1_0` are accepted, because Python's `int()` allows underscores.
- A double comma, `MOVE R1,,R2`, and a trailing comma, `MOVE R1, R2,`.
- A label before `.ORG` takes the address before the jump: in `foo .ORG 0x10`, foo is 0. ISA.md §10.1 says a label is "the address of what follows on that line", which reads as 0x10.
- `R16` is a valid label name, so `R16 .DAT 1` followed by `MOVE R1, R16` assembles as a constant operand.

## 2. Error messages

The `file:line: error: message` format is good, and the operand-mode messages are the best in the program:

    '@R1--': post-decrement is only a direct destination mode
    '--R1': pre-decrement is not a destination mode, use Rx--

These mislead or point at the wrong place.

| Input | Message | Problem |
|---|---|---|
| `LOOP MOV R1, R2` | `unknown mnemonic 'LOOP'` | The label is fine. The typo is `MOV`. Line 307 reports the first token. When the second token exists and is not a register, name it, or name both. |
| `.DATA 1` | `unknown mnemonic '.DATA'` | A first token starting with `.` should get "unknown directive". |
| `.DATA` alone | `bad label '.DATA'` | Same. |
| `X .EQU 0xZZ` then two uses | `bad number: '0xZZ'` on each use line | Reported once per use, never at the definition, and never at all if X is unused. Validate the value's syntax in pass 0. |
| `.ORG later` with `later` defined below | `undefined symbol 'later'` | It is defined, just not yet. Say it must be defined before the `.ORG`. |
| `MOVE [M] R1, R2` | `MOVE takes 2 operands, got 3` | It is a modifier written with a space. |
| `MOVE[M R1, R2` | `unknown mnemonic 'MOVE[M'` | It is an unterminated modifier. |
| `MOVE R1, R16` | `undefined symbol 'R16'` | A hint that registers are R0 to R15 would help, since R16 is also a legal label name. |
| `MOVE R1, 'A'` | `expected a number or a symbol at ''A''` | The token's quotes are printed inside the message's quotes. |
| `.ASCII_L 'it's'` | `expected one quoted string` | Correct but unhelpful. The string ended early. |
| A UTF-8 byte order mark | `bad label 'ï»¿'` | Strip the mark on line 1. |
| `SP .EQU R13` then `SP MOVE R1, R2` | `'SP' is a register name, not a label` | True, but "already defined" would send the reader to the `.EQU` line. |

## 3. What is correct

For the record, these were checked and are right:

- The worked example in §11, `0xB278C971 0x12345678`.
- All sixteen shift opcodes and the six aliases `SHL ROL BPL SHR ROR BPR`.
- `HALT`, `RTI`, and `INT n` encodings, and the range check on n including for a label whose value is 256.
- Constant words in field order dest, s0, s1, and unused fields encoded as R0.
- Pass 1 and pass 2 agree on every statement size, because operand modes depend only on `.EQU` definitions, which are fixed before pass 1, and `.ORG` and `.BLK` refuse forward references.
- Duplicate labels, duplicate `.EQU` names, a label that collides with an `.EQU`, `.EQU` loops including `X .EQU X+1`, duplicate addresses, numbers above 2³², CRLF line endings, and address wrap at `0xFFFFFFFF` are all handled.
- `.ASCII_B` byte order and padding, `.ASCII_L` terminator, and both quote styles including a `'` inside `"..."`.

## 4. Missing tests

`make test` has no negative test. None of the error paths, the exit status, or the rule that no output is written on error is covered. A table of one-line inputs with the expected message, run by a small Python test or a shell loop, would cover most of sections 1 and 2.

Positive gaps in `encoding.asm`:

- The aliases `ROL`, `BPL`, `SHR`, and `BPR`. Only `SHL` and `ROR` are tested.
- The conditions `?!X`, `?!C`, `?!N`, `?!V`, `?!E`, and `?!I`. Only `?!1` and `?!M` are tested.
- `@c[Rx]` as a destination, `--R0`, the `R00` to `R09` spellings, and the registers R10 to R12.
- Double-quoted strings, an empty string for both `.ASCII` forms, a string containing `;`, and a `*` comment.
- `.BLK 0`, an `.EQU` chain such as `A .EQU B` and `B .EQU R1`, an `.EQU` that names a label, and a program with no `.ORG`.
- Address wrap at `.ORG 0xFFFFFFFF`.
- CRLF line endings.

Negative tests to add, one line each:

- Undefined symbol, duplicate label, duplicate `.EQU`, label colliding with `.EQU`, `.EQU` loop.
- Duplicate address, `.ORG` and `.BLK` forward references.
- `--Rx` as a destination, `Rx--` as a source, `@Rx--`.
- Wrong operand count for each class, `INT 256`, `INT -1`.
- Bad condition, bad modifier, `[C]` on a shift, a modifier on a control instruction, a condition on a directive.
- Unterminated string, number too large, bad number.
- After the fixes above: a line starting with `,`, `R1 .EQU 5`, `.BLK -1`, `?1 .DAT 1`.

## 5. Second round, commit 0670e53

**How it was checked.** `make test` (six programs and 71 error cases) and `make typecheck` pass. I re-ran every probe from sections 1 and 2 and confirmed the new behaviour, then ran about forty new probes aimed at the rewritten parts: `.EQU` values that are whole operands, `.EQU` validation and loop detection in pass 0, `.BLK` stored as ranges with the overlap check, the comma-aware tokenizer, and the label-on-`.ORG` rule.

### 5.1 Confirmed fixed

- A line starting with `,` and an indented unterminated string are both reported.
- `R1 .EQU 5`, `R16 .DAT 1`, and `ADD .EQU 5` are rejected with a message that names the rule.
- `.BLK -1` is an error. `.BLK 0x2000000` now runs in 14 MB instead of 4.7 GB.
- `?1 .DAT 1` is an error.
- The default output name never overwrites the input, and `-o` pointing at the input is refused.
- `X .EQU @R2`, `X .EQU R1++`, and `X .EQU 5[R4]` work as whole operands, and ISA.md §10.3 and the README now say what an `.EQU` may hold.
- A bad `.EQU` value is reported once, on its own line, even if unused.
- A label on a `.ORG` line names the new address, and ISA.md §10.1 says so.
- Every message in the section 2 table is replaced. `LOOP MOV R1, R2` now reports `MOV` and says that `LOOP` is read as a label.
- `.BLK` ranges are checked against words and other ranges in both orders, and a range that merely touches the next word is accepted.

### 5.2 A crash

`check_equs()` (line 185) recurses once per dependency. A chain of `.EQU` names written in reverse order, so that each depends on a name defined below it, recurses once per name. At 1200 names this exceeds Python's recursion limit of 1000 and the assembler dies with a traceback instead of an error message:

    A1200 .EQU A1199
    A1199 .EQU A1198
    ...
    A0    .EQU 7

Fifty names in reverse order work. The forward order never recurses deeply, because each name is checked after its dependency. No real program has a chain this long, but a traceback is never the right output. An explicit stack, or catching `RecursionError` and reporting the name, would fix it.

### 5.3 A false "loop" on long chains

`resolve()` (line 83) gives up after 100 steps and reports a loop. A forward chain of 101 names is therefore rejected:

    chain.asm:101: error: '7': .EQU definitions form a loop

Two things are wrong with that line: it is not a loop, and the name quoted is the final value `7`, not an `.EQU` name. Real loops are now found by `check_equs()` before anything else runs, and bad names stop `resolve()` early, so the 100-step limit no longer catches anything that the loop check misses. It could be raised to the number of `.EQU` definitions, or dropped.

### 5.4 Message nits

| Input | Message | Problem |
|---|---|---|
| `X .EQU R1++` then `MOVE R2, --X` | `bad expression '--X'` | X stands for an operand. The messages for `X+1` and `INT X` say so; this one does not. The same for `X++`. |
| `MOVE[M] [C] R1, R2` | `MOVE takes 2 operands, got 3` | The hint about a space before the modifier only fires when the mnemonic has no modifier of its own. |
| `.ASCII_L 'abc' 'def'` | `text after the string 'abc': to put ' in a string, quote the string with "` | The extra token is a complete second string. The hint about quoting is wrong here. |
| `A HALT` then `A .EQU 1` | line 1: `symbol 'A' is already defined on line 2` | True, since `.EQU` is processed first, but the reader expects the error on line 2. |

### 5.5 Accepted without complaint

- A comma directly after the mnemonic, label, or condition: `MOVE , R1, R2`, `L , HALT`, and `?Z , HALT`. The README says operands are separated by one comma. This comma separates nothing.
- `X: .EQU 5` is still rejected with "bad symbol name 'X:'" while `X: HALT` is accepted. The README says a label may end with `:`, and an `.EQU` name is written in the label position.

### 5.6 Tests

`errors.py` covers every message from section 2 and every bug from section 1. Gaps worth one case each: a `.BLK` range overlapping a word emitted after it, two overlapping `.BLK` ranges, a `.BLK` that ends at `0xFFFFFFFF` exactly followed by a word at 0, and, after the fixes in 5.2 and 5.3, a long chain in each order.

## 6. Third round, commit 0de7cb7

`make test` (90 cases) and `make typecheck` pass. Every item in section 5 is fixed: the reversed 1200-name chain assembles, a forward chain of any length is accepted, the four message nits and the two silent acceptances are handled, and the `.BLK` overlap orderings are tested.

### 6.1 One message regression

`equ_value()` (line 157) evaluates the names a value mentions before the name itself, and calls `check_number()` on each. When an `.EQU` whose value is an operand is used where a number is expected, the message now blames the register inside the operand instead of the name:

    SP .EQU R13
    X  .EQU 5[SP]
       .DAT X

    3: error: 'SP' is a register where a number is expected

Commit 0670e53 said `'X' stands for the operand '5[SP]', not a number`, which is the message `X .EQU @R2` with `.DAT X+1` still gives, because `@R2` mentions no `.EQU` name. `MOVE R1, X+1` and `INT X` give the same wrong message. Calling `check_number(name)` on the requested name before walking its dependencies restores the old message, and `Y .EQU SP+1` keeps its correct one, since there the register really is a term.

### 6.2 Nit

`MOVE[M] [M] R1, R2` suggests `MOVE[MM]`, which is itself rejected as a bad modifier.
