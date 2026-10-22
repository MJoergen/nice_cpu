# niceasm

A simple assembler for the NICE processor: one Python 3 script with no
dependencies beyond the standard library. It implements the assembler syntax in
[doc/ISA.md §10](../doc/ISA.md#10-assembler-syntax).

## Test

    make test

This assembles every program in `test/` and compares the result with
the expected `.bin` file. It then runs `test/errors.py`, which assembles a
list of short faulty programs and checks the error message, the exit
status, and that no output file is written. It also checks short good
programs, the format of several errors, and the command line.

The script is fully type-annotated. `make typecheck` checks it with
`mypy --strict` (install mypy first).

## Usage

    ./niceasm.py [-o output.bin] input.nasm

Without `-o`, the output goes to `input.bin`. If that is the input file
itself, the assembler refuses with a message. Errors in the program are
printed as `file:line: error: message`, followed by a count of them, and
warnings as `file:line: warning: message`. No output is written if there
is an error; a warning does not stop the output. The exit status is 0 on success, 1
after any error, and 2 for a bad command line, which also prints the usage.
`-h` prints the usage.

## Output format

The output is the `.bin` text format of [ISA.md §10.4](../doc/ISA.md#104-object-format):
one line per assembled word, an 8-digit hex address, a space, and the 8-digit
hex word, in address order. This is the format the 2004 `NICE.pm` assembler
writes, so its example binaries can be compared directly. Addresses skipped
by `.ORG` and words reserved by `.RES` are not listed.

## Details beyond ISA.md

- Operands are separated by whitespace or by one comma. A comma anywhere
  else, such as after the mnemonic or two in a row, is an error.
- `;` starts a comment anywhere outside a string. `*` starts one only at
  the start of a word, so `R2 *note` is `R2` and a comment, but `R2*note`
  is an error.
- A line with one word that is not a mnemonic or a directive is a label,
  even when it is indented. When it is indented and has no `:`, as a
  misspelled `HALT` or `RTI` alone on a line would be, the assembler prints
  `file:line: warning: message` and assembles the program.
- A label or `.EQU` name cannot be a mnemonic or look like a register (`R`
  followed by digits, so `R16` is rejected too).
- An `.EQU` value is a number, an expression, a register, or a complete
  operand such as `@R2`, `R3++`, or `5[R4]`. The name is replaced by its value
  when it is a whole operand, the part after `@`, the register in `--Rx`,
  `Rx++`, `Rx--`, or `c[Rx]`, or a term in an expression. In an expression
  the value must be a number or an expression. Each value is checked where it
  is defined, also when the name is never used, and an error in it is
  reported there and not where the name is used.
- Numbers are digits only: no `_` separators.
- Strings have no escape sequences. The source is read byte by byte, as
  Latin-1, so each byte of a string is one character: a UTF-8 `é` gives two.
- `.ORG`, `.BLK`, and `.RES` arguments must not refer to labels defined later.
- A `.BLK` or `.RES` count must not be negative, and the block must end at or
  before address `0xFFFFFFFF`. Other statements wrap from `0xFFFFFFFF` to 0.
- Writing two words to the same address is an error. So is any overlap of
  a `.BLK` or `.RES` with another `.BLK`, `.RES`, or word, `.RES` against
  `.RES` included. Blocks that only touch are fine.
- `.BLK n` writes n lines of output, with no upper limit: `.BLK 0xFFFFFFFF`
  writes about 38 GB. Use `.RES` for a large reservation, which writes
  nothing.
- `.ASCII_B ''` emits nothing, and `.ASCII_L ''` emits one 0 word.
- The output is sorted by address, not by source order. With a wrap, the
  words at 0 come before those at `0xFFFFFFFE` (`test/wrap.nasm`).
- Whitespace is what Python's `str.isspace()` says, so a form feed and
  the Latin-1 character `0xA0` separate words too.
- Warnings print before errors. A run that fails leaves an existing output
  file as it was. `-o -` writes a file named `-`, not stdout.
- A UTF-8 byte order mark at the start of the file is ignored.

## Tests

| File | What it checks |
|---|---|
| `count`, `replicate`, `print` | The 2004 example programs by B. Ulmann ([examples.zip](http://www.vaxman.de/projects/nice/examples.zip)). The `.bin` files are the original `NICE.pm` output and match byte for byte. |
| `encoding` | Every addressing mode in every field, opcode, alias, condition, control instruction, and directive; three constant words; number spellings and expressions; register spellings; and `.EQU` chains and operands. The expected output was checked by hand against ISA.md, including the worked example in §11. The comments of the later lines give the derivation. |
| `wrap` | Address wrap from `0xFFFFFFFF` to 0. |
| `crlf` | CRLF line endings and a program with no `.ORG`. |
| `errors.py` | One case per error message, including every bug fixed after [the review](../doc/review/assembler-review.md); generated programs such as `.EQU` chains of 1200 names; an empty file and one with no final newline; the exact output for two errors, and for warnings; and the command line: `-o`, a missing file, a directory in place of a file, and bad arguments. |
