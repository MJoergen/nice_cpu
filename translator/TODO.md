# nicewasm: smaller code

nicewasm supports every wasm feature that clang, Zig, and Rust emit by default.
The next step is smaller code. This file records the analysis and the
plan, for later.

## Where the words go

Words of NICE code for each kind of wasm instruction, measured on commit
2b96d36. The words for an instruction include its bounds check and its
trap stub, but not the epilogue.

| Instructions | `test/safe.zig` (ReleaseSafe): 12353 words | `runtime/float.asm`: 30587 words |
|---|---|---|
| `local.get`, `local.set`, `local.tee` | 2298 (19%) | 7734 (25%) |
| `i32.const`, `i64.const` | 594 (5%) | 4539 (15%) |
| Loads and stores | about 3600 (29%): 24 words for an `i32.load`, 37 for an `i32.store` | about 1450 (5%) |
| `i64.shl`, `i64.shr_u` | few | 2888 (9%): 19 words each |

There are two main causes:

- Every value on the wasm operand stack is copied to a frame word. So
  `local.get a; local.get b; i32.add; local.set c` becomes four
  instructions of about 13 words, where `ADD @c, @a, @b` takes 4.
- Every memory access has inline code for the general case: any byte
  address, and a value that spans two words. The common case, an aligned
  word, needs only a part of it. Each access also has its own trap stub of
  6 words.

## Plan

Do these in order, one commit each. Each commit message and the README
give the word counts before and after.

1. **Deferred operands.** Done. `test/safe.zig` went from 12353 to 9941
   words (19% less), and the float library from 29569 to 20317 (31%
   less). Each count is every word of the translated module in the
   program image, including the float library's 256-word stack. Values
   are not written to their frame words before a call, since a call
   cannot change the caller's locals. The README describes the rules.

   The operand stack records what each value is: a constant, a local, or
   a value in its frame word. `local.get` and the
   constants emit no code. The instruction that uses the value takes it
   as a NICE operand: `@-3[R12]` for a local, the number for a constant.
   A value is written to its frame word only when it must be:
   - before a `local.set` or `local.tee` changes the local it refers to;
   - at the start and end of a block, and before a branch, where values
     must be in fixed frame words;
   - before a call, and where an instruction needs a register or a frame
     word.

   The frame layout, the calling convention, and ISA.md stay as they are.
   Expected saving: 15–25% of each program.

2. **Memory accesses with a short inline path.** Done. `test/safe.zig`
   went from 9941 to 8730 words (12% less), and the float library from
   20317 to 19808 (2.5% less). An `i32.load` is now 12 words after its
   bounds check, and an `i32.store` 13, as estimated, but `safe.zig`
   saved about 1200 words, not 2000. An access at a constant address
   that is known to be in bounds has no check, and is a `MOVE` for each
   word when aligned.

   The bounds check and an aligned 32-bit or 64-bit access stay inline.
   Unaligned and narrow accesses call helpers that nicewasm emits once,
   as it does `W.fill`.
   Expected: about 12 words for an `i32.load` and 14 for an `i32.store`,
   which saves about 2000 words in `safe.zig`.

3. **`i64` shifts in helpers.** Each `i64` shift calls a helper instead of
   19 words of inline code. This saves about 2000 words in the float
   library.

All three together should make both programs about a third smaller:
`safe.zig` about 8000 words, and the float library about 20000. These
are estimates.

## Left as it is

The trap stubs stay. Sharing them would save about 4 words for each
memory access. But ISA.md §9.4 says that R2 holds the address of the first
NICE instruction of the code for the wasm instruction that trapped, and a
shared stub cannot easily know that address.

## Tests

The tests check results, not the code, so every `make test` case must
still pass after each step. That includes the C, Zig, and Rust programs and the
float library. Step 1 needs new cases for the ways it can go wrong:

- a `local.set` or `local.tee` to a local whose old value is still on the
  operand stack;
- deferred values that a branch, `br_if`, or `br_table` carries;
- deferred values across a call, and as the arguments of a call;
- deferred values at the end of a block, of an `if` with and without
  `else`, and of a `loop`.
