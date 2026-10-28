# niceasm

A simple assembler for the NICE processor: one Python 3 script with no
dependencies beyond the standard library. It implements the assembler syntax in
[doc/ISA.md §10](../doc/ISA.md#10-assembler-syntax). Next to it are
`nicefmt`, which checks the layout of the sources, and `nicedis`, the
[disassembler](#disassembler).

## Test

    make test

This assembles every program in `test/` and compares the result with
the expected `.bin` file. It then runs `test/errors.py`, which assembles a
list of short faulty programs and checks the error message, the exit
status, and that no output file is written. It also checks short good
programs, the format of several errors, and the command line. Then it
runs the tests of `nicefmt` and `nicedis`, and checks the layout of every
`.nasm` file.

The scripts are fully type-annotated. `make typecheck` checks them with
`mypy --strict` (install mypy first).

## Usage

    ./niceasm.py [-o output.bin] [--symbols output.sym] input.nasm

Without `-o`, the output goes to `input.bin`. If that is the input file
itself, the assembler refuses with a message, as it does if `--symbols`
names the input or the output. With `--symbols`, it also writes every label to the given file, one line per label: the 8-digit
hex address, a space, and the name, sorted by address and then by name. The
emulator reads this file (`niceemu --symbols`). Errors in the program are
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

## Source layout

The assembler accepts any spacing. The sources in this repository use
spaces only, in columns: the label in column 0, the condition in column 8,
the mnemonic in column 16, the operands in column 24, and the comment in
column 40. A label of 8 or more characters stands on a line of its own.

`nicefmt.py FILE...` reports the first line of each file that is not in this
layout and exits with status 1. `nicefmt.py --write FILE...` rewrites the
files, keeping every word and comment. A string that holds a `;` is kept
whole.

## Disassembler

    ./nicedis.py [--symbols FILE] [--start ADDR] [--end ADDR] input.bin

`nicedis.py` writes the program of a `.bin` file to stdout in the syntax
of [ISA.md §10](../doc/ISA.md#10-assembler-syntax) and the layout above.
`niceasm` assembles the output back to the same words. `--start` and
`--end` list only the words from `ADDR` up to, but not including, the end
address. An address is decimal, or hex with `0x`.

It reads the `.bin` file as `niceemu` does: 1 to 8 hex digits, blank lines
allowed, and the lines in any order. A bad line, an address given twice,
or a file with no words is an error, printed as `file:line: error:
message`. The exit status is 0 on success, 1 after an error, and 2 for a
bad command line.

The rules of the output:

- An instruction takes its constant words with it. The output shows them
  as operands, in hex: `MOVE R1, 0x1000`. The vector of `INT` is decimal.
- Mnemonics are the ones of ISA.md, with the alias for a SHIFT
  instruction where one exists (`SHL`, `ROL`, `BPL`, `SHR`, `ROR`, `BPR`).
  "Always" is no condition, and "never" is `?!1`. Registers are `R0` to
  `R15`, never `SP` or `PC`, which are names that programs define.
- Words that no instruction of the syntax gives are `.DAT`, with what they
  would do as a comment. These are the reserved control words (ISA.md
  §5.3), and `MOVE`, `DBL`, `DEC`, `NOT`, and `ONE` with an unused field
  that is not R0 (§4.4), constant words included:
  `.DAT 0x00004130, 0x00000005 ; MOVE R1, R2 (s1: 0x5)`.
- An instruction whose constant words fall in a gap, after the end of the
  file or of the range, or past address `0xFFFFFFFF` is cut off. Its words
  up to there are a `.DAT`, with `?` for the missing constants in the
  comment. A gap is a `.ORG` line.
- The words are read one instruction after the other. Data is shown as
  instructions, or as `.DAT`, since nothing tells it from code.

With `--symbols FILE`, the labels of `niceasm --symbols` or
`nicebuild.py --symbols`:

- Each label is shown at its address. A label of 8 or more characters
  stands on a line of its own, and so does each label but the last at one
  address.
- An instruction never spans a label, since each label starts a
  statement. If it would, its words before the label are a `.DAT`, and the
  next line starts at the label. So the code after a string comes out
  right when it has a label.
- A constant of 16 or more that is the address of a label is shown as the
  label, with the value in the comment: `MOVE R15, loop ; loop =
  0x00000123`. Smaller constants, such as the 2 of a call, stay numbers,
  and so does the count of a SHIFT instruction. Of several labels at one
  address, the first one in the file that `niceasm` accepts is shown.
- A name that `niceasm` does not accept as a label, such as the `::` or `$`
  names of Rust and Zig functions that `nicebuild.py` writes, a mnemonic,
  a register name, or a name that occurs twice, is only a comment: on a
  line of its own at its address if a word is there, and in the comment of a constant, which
  stays a number.
- A label that the output uses but does not define, because no word is at
  its address or it is outside the range, is defined with `.EQU` at the
  top.

Other tools import `nicedis.disassemble(addr, read, symbols)`. It
disassembles the instruction at `addr`, where `read(a)` returns the word
at `a` or `None`, and returns the text and the number of words it used.
`symbols` maps addresses to names, which are shown as above but without
the comment, and may be any names, since nothing reassembles the text.

## Editor support

`nice.vim` is a Vim syntax file for `.nasm` files. Copy it to
`~/.vim/syntax/nice.vim` and add `autocmd BufRead,BufNewFile *.nasm set
filetype=nice` to `~/.vimrc`, because Vim takes `*.nasm` for another
assembler.

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
| `dis.py` | `nicedis`: every `.bin` file of the repository disassembled and reassembled to the same words, without symbols and with them where its `.nasm` file or `.sym` file gives them, and each listing in the layout; the hand-checked listings `count.lst` and `disedge.lst`; `disassemble()`; `--start` and `--end`; and the errors. `disedge.bin` and `disedge.sym` hold the cases no assembled program has: the `.DAT` words, cut-off instructions, a gap, a label inside an instruction, and the names that are not labels. |
| `errors.py` | One case per error message, including every bug fixed after [the review](../doc/review/assembler-review.md); generated programs such as `.EQU` chains of 1200 names; an empty file and one with no final newline; the exact output for two errors, and for warnings; and the command line: `-o`, a missing file, a directory in place of a file, and bad arguments. |
