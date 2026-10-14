# niceasm

A simple assembler for the NICE processor: one Python 3 script with no
dependencies beyond the standard library. It implements the assembler syntax in
[doc/ISA.md §10](../doc/ISA.md#10-assembler-syntax).

## Test

    make test

This assembles every program in `test/` and compares the result with
the expected `.bin` file. It then runs `test/errors.py`, which assembles a
list of one-line faulty programs and checks the error message, the exit
status, and that no output file is written.

The script is fully type-annotated. `make typecheck` checks it with
`mypy --strict` (install mypy first).

## Usage

    ./niceasm.py [-o output.bin] input.asm

Without `-o`, the output goes to `input.bin`. If that is the input file
itself, the assembler refuses with a message. Errors in the program are
printed as `file:line: error: message`, followed by a count of them. No
output is written if there is an error. The exit status is 0 on success, 1
after any error, and 2 for a bad command line, which also prints the usage.
`-h` prints the usage.

## Output format

The output is the `.bin` text format of [ISA.md §10.4](../doc/ISA.md#104-object-format):
one line per assembled word, an 8-digit hex address, a space, and the 8-digit
hex word, in address order. This is the format the 2004 `NICE.pm` assembler
writes, so its example binaries can be compared directly. Addresses skipped
by `.ORG` are not listed.

## Details beyond ISA.md

- Operands are separated by whitespace or by one comma. A comma anywhere
  else, such as after the mnemonic or two in a row, is an error.
- A label or `.EQU` name cannot be a mnemonic or look like a register (`R`
  followed by digits, so `R16` is rejected too).
- An `.EQU` value is a number, an expression, a register, or a complete
  operand such as `@R2`, `R3++`, or `5[R4]`. The name is replaced by its value
  when it is a whole operand, the part after `@`, the register in `--Rx`,
  `Rx++`, `Rx--`, or `c[Rx]`, or a term in an expression. In an expression
  the value must be a number or an expression. Each value is checked where it
  is defined.
- Numbers are digits only: no `_` separators.
- Strings have no escape sequences.
- `.ORG` and `.BLK` arguments must not refer to labels defined later.
- A `.BLK` count must not be negative, and the block must end at or before
  address `0xFFFFFFFF`. Other statements wrap from `0xFFFFFFFF` to 0.
- Writing two words to the same address is an error.
- A UTF-8 byte order mark at the start of the file is ignored.

## Tests

| File | What it checks |
|---|---|
| `count`, `replicate`, `print` | The 2004 example programs by B. Ulmann ([examples.zip](http://www.vaxman.de/projects/nice/examples.zip)). The `.bin` files are the original `NICE.pm` output and match byte for byte. |
| `encoding` | Every addressing mode, opcode, alias, condition, control instruction, and directive; register spellings; and `.EQU` chains and operands. The expected output was checked by hand against ISA.md, including the worked example in §11. |
| `wrap` | Address wrap from `0xFFFFFFFF` to 0. |
| `crlf` | CRLF line endings and a program with no `.ORG`. |
| `errors.py` | One case per error message, including every bug fixed after [the review](../doc/review/assembler-review.md), and generated programs such as `.EQU` chains of 1200 names. |
