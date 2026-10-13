# niceasm

A simple assembler for the NICE processor: one Python 3 script with no
dependencies beyond the standard library. It implements the assembler syntax in
[doc/ISA.md §10](../doc/ISA.md#10-assembler-syntax).

## Test

    make test

This assembles every program in `test/` and compares the result with
the expected `.bin` file.

The script is fully type-annotated. `make typecheck` checks it with
`mypy --strict` (install mypy first).

## Usage

    ./niceasm.py [-o output.bin] input.asm

Without `-o`, the output goes to `input.bin`. Errors are printed as
`file:line: error: message`, and the exit status is 1 if there were any.

## Output format

The output is the `.bin` text format of [ISA.md §10.4](../doc/ISA.md#104-object-format):
one line per assembled word, an 8-digit hex address, a space and the 8-digit
hex word, in address order. This is the format the 2004 `NICE.pm` assembler
writes, so its example binaries can be compared directly. Addresses skipped
by `.ORG` are not listed.

## Details beyond ISA.md

- Expressions are a number or symbol, optionally combined with `+` and `-`
  (for example `end-data` or `TABLE+1`), with no spaces, because whitespace
  separates operands. Arithmetic wraps modulo 2³².
- A label may end with `:`.
- Labels and `.EQU` names are case-sensitive. Mnemonics, register names,
  conditions, modifiers and directives are not.
- `.DAT` accepts several values: `.DAT 1, 2, 3`.
- Strings for `.ASCII_L` and `.ASCII_B` may use `'...'` or `"..."`. There are
  no escape sequences.
- `.ORG` and `.BLK` arguments must not refer to labels defined later.
- Writing two words to the same address is an error.

## Tests

| File | What it checks |
|---|---|
| `count`, `replicate`, `print` | The 2004 example programs by B. Ulmann ([examples.zip](http://www.vaxman.de/projects/nice/examples.zip)). The `.bin` files are the original `NICE.pm` output and match byte for byte. |
| `encoding` | Every addressing mode, opcode, condition, control instruction and directive. The expected output was checked by hand against ISA.md, including the worked example in §11. |
