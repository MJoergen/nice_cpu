# Adversarial review of niceasm

Reviewed on 2026-10-14: `assembler/niceasm.py` at commit 55a6913 ("niceasm: add type hints"), against `doc/ISA.md` §2, §4, §5.3, §10 and §11.

**How it was checked.** I read the code against the specification, confirmed that `make test` passes, checked the shift alias table and the control encodings by hand, and then ran about sixty one- to five-line probe programs through the assembler to see what it accepts, rejects and reports. The probe files were not kept; every input quoted below is complete and reproduces the result.

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

ISA.md §10.3 says `.EQU` "is substituted textually, so it can stand for a number or a register". Only a number, an expression or a register survives substitution:

| Input | Result at the use site |
|---|---|
| `X .EQU @R2` then `MOVE R1, X` | `expected a number or a symbol at '@R2'` |
| `X .EQU R1++` then `MOVE R2, X` | `bad expression 'R1++'` |

Either support full operands or say in ISA.md and the README that an `.EQU` value is a number, an expression or a register name.

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
- `HALT`, `RTI` and `INT n` encodings, and the range check on n including for a label whose value is 256.
- Constant words in field order dest, s0, s1, and unused fields encoded as R0.
- Pass 1 and pass 2 agree on every statement size, because operand modes depend only on `.EQU` definitions, which are fixed before pass 1, and `.ORG` and `.BLK` refuse forward references.
- Duplicate labels, duplicate `.EQU` names, a label that collides with an `.EQU`, `.EQU` loops including `X .EQU X+1`, duplicate addresses, numbers above 2³², CRLF line endings and address wrap at `0xFFFFFFFF` are all handled.
- `.ASCII_B` byte order and padding, `.ASCII_L` terminator, and both quote styles including a `'` inside `"..."`.

## 4. Missing tests

`make test` has no negative test. None of the error paths, the exit status, or the rule that no output is written on error is covered. A table of one-line inputs with the expected message, run by a small Python test or a shell loop, would cover most of sections 1 and 2.

Positive gaps in `encoding.asm`:

- The aliases `ROL`, `BPL`, `SHR` and `BPR`. Only `SHL` and `ROR` are tested.
- The conditions `?!X`, `?!C`, `?!N`, `?!V`, `?!E` and `?!I`. Only `?!1` and `?!M` are tested.
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
