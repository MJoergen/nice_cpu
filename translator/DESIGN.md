# How nicewasm translates

This file is for whoever changes `nicewasm.py`. It says how a wasm
function becomes NICE code, how a multiplication by a constant is split,
how the registers are allocated, and how a function's frame is laid out.
[README.md](README.md) says how to use the translator and what it
supports, and [WASM.md](WASM.md) is the mapping that it implements. The
tests of these rules are `test/run.py`, `test/fuzz.py`, and
`test/passes.py` (README.md, Test).

- [How functions are translated](#how-functions-are-translated)
- [Multiplication by a constant](#multiplication-by-a-constant)
- [Register allocation](#register-allocation)
- [The frame](#the-frame)

## How functions are translated

Each wasm function becomes a function of the ABI (ABI.md) at the label `W.fN`, where N is
its function index. nicewasm translates it in two steps. The front end
turns each wasm instruction into NICE instructions on virtual registers.
The back end gives the virtual registers physical registers, or frame
words if there are too few, and adds the prologue and the epilogue.

Each local has a virtual register, or two for an `i64` or `f64`, low word
first. So does each value that an instruction pushes on the wasm operand
stack, whose type nicewasm tracks. The values that a block, loop, or `if`
takes and gives have fixed registers, which every branch to it writes.
Every wasm instruction becomes NICE instructions on these registers. For
example, `i32.add` is one `ADD` with three operands, and `i64.add` is
`ADD[M]` on the low words and `ADD[C]` on the high words. The output has
a comment for each wasm instruction. Physical registers appear only
where ABI.md or a helper demands them: the arguments and results of
calls, the function's parameters and result, and the code and address
of a trap.

A constant, and a `local.get`, emit no code. nicewasm records the value
on the operand stack as deferred, and the instruction that uses it takes
the constant or the local's register as its operand. A
result that the next instruction stores with `local.set` or `local.tee`
goes straight to the local, for an `i32` operation of two values, an
`i32` shift, a call, a multiplication by a constant, and the operations
that call the runtime library, such as `i32.mul` with `--no-mpu`. An
`i32.mul` through the math unit reads the product into a register of its
own, and the coalescing below folds that into the local. So `local.get
a; local.get b; i32.add; local.set c` is one `ADD c, a, b`. Before such an operation, the copies of the local's old
value below its operands are copied to registers of their own. A
deferred value is copied to registers of its own only when it must be:

- before a `local.set` or `local.tee` changes the local it is the value of;
- at the start of a block, for the values the block takes and for every
  value of a local below it, so these are the same on every path through
  the block. A constant below a block stays deferred, because nothing can
  change it;
- at an `else` or `end`, for the block's results.

`select`, `abs`, `neg`, and `copysign` change only a part of their first
operand, so they copy a deferred one to the result's registers first.

A branch moves deferred values to the registers of its target, as it
does any other value. A call takes deferred arguments directly, and
deferred values below the arguments stay deferred, since a call cannot
change this function's locals. `local.tee` leaves the local itself on
the stack, and `i32.wrap_i64` of a deferred value is the low word of it.

A branch moves the values it carries to the registers that the target
block expects, and then jumps. A branch out of the function moves them
to R1 and up, as `return` does. `br_table` checks the index against the
number of labels, then jumps through a table of `.DAT` addresses.
A comparison sets the flags, usually with `SUB[M]`, then sets the result from
them. A signed comparison is N XOR V (ISA.md §9.2), so `?V XOR R14, R14,
0x10000000` first flips N when V is set, and N alone holds the answer,
as ISA.md §9.2 describes. When the next instruction is `br_if` or `if`,
or `i32.eqz` and then one of them, the comparison sets only the flags,
and the branch jumps on them. `i32.eqz` and `i64.eqz` before `br_if` or
`if` do the same with Z. A comparison of an `i32` with the constant 0 is
`MOVE[M] R0, x`, whose flags are those of `SUB[M] R0, x, 0`, so that the
back end may give the M bit to the instruction that computed x (see
Register allocation). An `i64` `eq` or `ne` takes the words of x as they
are when the other operand's word is 0.

The front end also keeps track of what the flags say, until an
instruction changes them or a label comes. After a comparison or an
`eqz` sets its result, they say whether the result is 0. After an
`i32.load` whose offset is a multiple of 4, they can say whether the
value is 0: its `MOVE` gets the M bit, and so does the `MOVE` of the
helper's result in the stub, if a branch uses the flags. A `select`,
`br_if`, `if`, or `eqz` on such a value, or on a copy of it in a local,
then uses the flags, with no test of its own. So `select(a, b, x < y)`,
signed, is `SUB[M] R0, x, y`, the `?V XOR`, `MOVE d, a`, and `?!N MOVE
d, b`. If the comparison's result is not used otherwise, no code sets
it.

An `i32` shift masks its count to 5 bits first, because NICE uses the
full count (WASM.md). A constant count is masked by nicewasm, so a
shift by a constant is one instruction, such as `SHL d, x, 3`. `shr_s`
copies the sign bit into C and shifts it in with `C>0` (§5.2). A rotate
needs no mask, since only the count modulo 32 matters to `ROL` and
`ROR`. An `i64` shift by a constant combines the two words with three or
four 32-bit shifts inline, or with moves for a count of 32. Any other `i64` shift
or rotate calls a helper, such as `W.shl64`, with the value in R1 and R2
and the count in R3. A NICE shift by 32 or more gives 0, and so does a
shift by a "negative" count such as 32 − n for n > 32. So `W.shl64` and
`W.shr_u64` need no branch: each part that does not apply comes out as
0. An `i64` rotate by 32 or more swaps the words first.

A load or store first checks that all its bytes are in the memory. One
compare of the base with the first base at which the access does not
fit does it, as in `SUB[M] R0, R1, 65532` for a word access at offset 1, whose last
byte is at base + 4, since below that base the base plus the offset
cannot pass 2^32 either. A failed check jumps to a
trap stub after the function's epilogue, which sets R2 to the start of
the access code. Then the code adds the offset to the base. If the
memory can grow, the code adds the offset first, traps if the sum passes
2^32, and compares the sum with a word that `memory.grow` keeps up to
date, one of `W.limit0` to `W.limit8`, which it sets from the size in
pages, `W.pages`. An
access of 4 or 8 bytes then tests whether the address is at a multiple
of 4. If it is, one `MOVE` for each word does the access, with the word
index in a register. If it is not, the code jumps to a stub after the
epilogue, which calls a helper, `W.load4`, `W.load8`, `W.store4`, or
`W.store8`, and jumps back. So the common, aligned path changes no
registers but its own. A helper takes the byte address in R1. It returns
a loaded value in R1, or R1 and R2, and takes a value to store in R2, or
R2 and R3. nicewasm emits each helper once, if a function uses it.

With `--trust-alignment`, an access of 4 or 8 bytes whose alignment
hint is 4 bytes or more skips the test and the stub: `SHR` gives the
word index, and the `MOVE`s do the access. A misaligned access then
reaches the word that holds its first byte. The hint is exact in the
code of clang, Zig, and rustc, which give an access of unknown
alignment, such as the words of an inlined `memcpy`, a smaller hint, so
those keep the test. Without bounds checks, the test, its jump, and the
stub are most of the code of a word access. With them, the compare of
the next paragraph covers the alignment of an access whose offset is a
multiple of 4 already, so the option changes only the accesses with
other offsets.

With `--byte-windows`, an access goes through a byte window of
[SYSTEM.md §9](../doc/SYSTEM.md#9-byte-windows), which takes the byte
address itself. The window, the memory's start, and the offset fold into
one constant, so a byte load is `MOVE R1, @0x20000000+4*___wasm_memory+5[R2]`,
with no word index, no rotation, and no read and write back for a store.
The signed windows sign-extend a byte or a halfword. The bounds check
compares the base with the first base at which the access does not
fit, as above, and the offset needs no `ADD`. A window never straddles
two words, so a halfword takes one only if `--trust-alignment` trusts
its hint of 2, and a word only if the option trusts its hint of 4, or
word_index knows the address to be at a multiple of 4. The other
accesses, and those at a constant address of 4 or 8 bytes, keep the
code above. Window accesses do not join the groups of accesses that
share a compare. So with bounds checks, a word access whose address
word_index knows as 4 · (i + c) keeps the code above too: it takes
word c with i as the index, needs neither the shift nor the add that
compute the address, and shares its compare. In bench.c that saves
105K steps, most in its heapsort. Without bounds checks there is no
compare to share, and the window is one instruction as well.

The windows reach words 0 to `0x03FFFFFF` only, and where the assembler
puts the memory is not known here. So a memory of more than 4096 pages,
which fits nowhere, is refused, and `___wasm_start` tests the memory's
last word before any access and traps with code 8 if it lies beyond
them ([WASM.md](WASM.md), Traps).

Without bounds checks, an offset that is a multiple of 4 goes into the
word operand, as offset / 4, and the word index and the byte in the
word come from the base alone, with no `ADD` before them. That is exact
for an access in the memory, where base + offset does not pass 2^32,
and WASM.md defines no result for one past its end. So a byte load at
offset 8 is `SHR` and `SHL` of the base, then
`ROR d, @___wasm_memory+2[w], c` and an `AND`.

With bounds checks, an access of 4 or 8 bytes whose offset is a
multiple of 4 takes a shorter path. `ROR t, base, 2` gives base / 4 if
base is a multiple of 4, and 2^30 or more if it is not, which is past
the last word of any memory. So one unsigned compare of t checks the
bounds and the alignment at once, and the offset goes into the word
operand. An `i32.load` at offset 4 in a memory of one page is:

                    ROR     R2, R1, 2
                    CMP     R2, 16383
            ?!C     JMP     W.f0.L1
                    MOVE    R1, @___wasm_memory+1[R2]

If the compare fails, a stub after the epilogue gets the base back with
`ROL` and calls a helper such as `W.cload4`, which is followed by two
words: the start of the access code and the offset. The helper adds the
offset, traps if the access is out of bounds, with R2 the first word,
else does the access as `W.load4` does, and returns past the two words.
Then the stub jumps back. Such a stub takes some 10 words, and with the
check in each stub it took some 20. If the memory can grow, t is
compared with a word that `memory.grow` keeps up to date, `W.wlimit4` or
`W.wlimit8`. An offset is then added to t first, and the code jumps to
the stub if the sum passes 2^32.

Clang computes the address of an array element as `(i << 2) + c`, with
`i32.shl` and `i32.add`. When c is a multiple of 4, that address is a
multiple of 4 too, and t = i + c / 4 is its word index, modulo 2^30,
since the address wraps modulo 2^32. So the `i32.add` also computes t,
and an access at the address uses it in place of `ROR`. A t of 2^30 or
more fails the compare, and the stub gets the address back with `SHL`.
The same holds for `i << s` with s above 2, with t = (i << (s - 2)) +
c / 4, and for a constant added to such a sum. If no other code uses the
address itself, the allocator removes the shift and the add, and the
access is three instructions after the `ADD` that computes t. Without
bounds checks, t is taken modulo 2^30 with an `AND`, and there is no
compare. A later access at the same base in the same straight-line code
uses the same t. What nicewasm knows of t is dropped when a register it
involves is written, and at a label that a jump may reach.

Often the `ADD` that computes t can go too. Then t is i + d, with i
the index, or the index shifted by s - 2, and the constant d = c / 4.
If d is below the limit L of the compare, the compare is of i with L -
d, and d goes into the word operand. So for `(i << 2) + 8480`, an
`i32.load` is:

                    CMP     R7, 14264
            ?!C     JMP     W.f6.L8
                    MOVE    R5, @___wasm_memory+2120[R7]

If i passes the compare, i + d is below L, so the access is in bounds,
and its word index does not wrap. If not, the stub computes t with an
`ADD` and goes on as before. So an address that wraps modulo 2^32 to
one in the memory still works, through the checked helper. A d at or
past L keeps the `ADD`, and so does a negative c, since d is taken
modulo 2^32. So does every access if the memory can grow. Without
bounds checks, d and the access's offset go into one `ADD` before the
`AND`. For a library module, L comes from the library's memory. If
the `i32.add` writes the local that holds i, as a `local.tee` of the
index does, a copy of i comes first, for the accesses. The allocator
gives the copy the register of i if it can, and then removes it.

nicewasm also keeps an upper bound on the unsigned value of some
registers. A constant gives itself, and a value without a bound counts
as 2^32 - 1. `i32.and` gives the smaller bound of its operands, so a
constant mask m gives m. `i32.load8_u` and `i32.load16_u` give 255 and
65535. `i32.shr_u` by a constant k, and `i32.div_u` by 2^k, give the
bound of the value shifted right by k, so 2^(32 - k) - 1 at most.
`i32.rem_u` by a constant c gives c - 1, or the bound of the value if c
is a power of two and that is smaller. A copy keeps the bound of what it
copies, and `i32.add`, `i32.or`, `i32.xor`, and `i32.shl` by a constant
combine the bounds of their operands. Signed operations give no bound. A
bound is dropped, as what nicewasm knows of t is, when its register is
written, and at a label that a jump may reach. A call changes no virtual
register, so a bound lasts across it. If the bound of the register that
a word access compares is below the limit of the compare, every value
passes it, so there is no compare and no stub. For an access at word d
of the memory plus i, that is B + d + w ≤ L, with B the bound of i, w
the words of the access, 1 or 2, and d including a quarter of the
access's offset. So in crc32, `table[(crc ^ b) & 255]` with the table at
word 3144 is:

                    AND     R1, R1, 255
                    MOVE    R5, @___wasm_memory+3144[R1]

With a memory that can grow, the access keeps its compare. Without
bounds checks, if B + d is below 2^30, i + d is the word index, so d
goes into the word operand, and there is no `ADD` and no `AND`.

Such a group of word accesses with the same t, or the same i, shares
one compare: that of the first access, with the least limit of the
group, L - d for i. If the compare passes,
every access of the group is in bounds and at a multiple of 4, so the
others need no compare. A struct's fields, or a load and a store of the
same array element, are such groups. If the compare fails, the first
access's stub does that access, as before, and then goes on in a copy
of the code up to the end of the last access, after the epilogue. In
the copy, each word access calls its checked helper, such as
`W.cload4`, and the copy then jumps back to the code after the last
access. So an access out of bounds still traps where it would have:
the code before it has run, and its stores are done. R2 points at the
access in the original code, which has no compare of its own, as for
the copies of duplicate tails below. The stubs of the other accesses
go, and that pays for most of the copy. The code from the first compare
to the end of the last access may hold up to 16 other instructions. It
may not change t, and no jump may come into it. In a loop, the group
may make the code larger by up to 20 words for each compare that it
saves, twice that in two loops, and so on. Outside loops, it may not
make the code larger. With a memory that can grow, each access keeps
its own compare.

In a helper, the value is shifted together from, or split across, two
words, or three for an unaligned `i64`. A store that changes only part
of a word reads the word, changes its bytes, and writes it back once.

An access of 1 or 2 bytes is inline. A shift gives the word index w of
the address a, and `SHL c, a, 3` gives c, which is 8p modulo 32 for the
byte p of a in its word. Neither instruction can trap, and each writes
only its own register, so both come before the bounds check, after the
start of the code, where a trap's R2 points (WASM.md). So the read
waits for neither register, only for the skipped jump just before it,
unless an instruction moves to between them (below). Only a rotation
takes its count modulo 32 (ISA.md §5.2), so the code rotates by c. The
vm's fetch of an opcode, an `i32.load8_u`, is:

                    SHR     R2, R3, 2
                    SHL     R1, R3, 3
                    CMP     R3, 65536
            ?!C     JMP     W.f7.L20
                    ROR     R1, @___wasm_memory[R2], R1
                    AND     R1, R1, 0xFF

A signed load gets c from `SHL c, 1[a], 3` or `SHL c, 2[a], 3`
instead, which is 8p + 8 or 8p + 16 modulo 32, rotates the bytes up to
bit 31 by it, and then shifts them down with the
sign, by `C<0[M]` and `C>0`. A store rotates the mask of the bits to
keep, such as `ROL R4, -256, R3`, ANDs the word with it, rotates the new
bytes into place, and writes the word back with `OR`. A store of a
constant 0 needs no `OR`: `AND @___wasm_memory[R3], R2,
@___wasm_memory[R3]` writes the word back. With bounds checks and a
memory that cannot grow, an offset that is a multiple of 4 goes into
the word operand, as for the words above, and any other offset is added
before the check too. If the memory can grow, w and c come after the
add of the offset, which can trap, and before the compare. If the
bound of the base, as for the words above, shows that all the bytes
are in the memory, there is no bounds check. Two bytes at p = 3
straddle two words. The code checks for that, with `AND[M] R0, 1[a],
3`, which is 0 for p = 3, and jumps to a stub after the epilogue, which
does the access with the two words and jumps back.

If the address is a constant, nicewasm adds the offset itself. If all
the bytes are in the initial memory, or there are no bounds checks,
there is no check, and an aligned access of 4 or 8 bytes is a `MOVE`
for each word, such as `MOVE R3, @___wasm_memory+256`. If no access of
its size fits in the memory at all, the access traps at once.

`call_indirect` checks the table index against the table's size. It
checks the entry's address for 0 and its type number, then calls the
address with `ADD @--SP, 1, PC` and `MOVE PC, Rn`, the "through a
register" sequence of ABI.md. The arguments are in R1–R4 and on the
stack, as for `call`. If the address is in a frame word, the jump takes
a constant word, and the `ADD` adds 2.

## Multiplication by a constant

An `i32.mul` by a constant is at most three shifts, additions, and
subtractions, if that many will do. So x × 31 is `SHL t, x, 5` and `SUB
d, t, x`. The math unit takes three instructions, and on the FPGA core
its product can be read three cycles after the operand is written, so a
read right after the write waits about two; each of these instructions
takes one. By the cycle estimate of `bench/`, more steps gain nothing. A
multiplication by any other constant uses the math unit, or with
`--no-mpu` calls `__mul`.

For an `i64.mul` by a constant, with x = 2^32 · xh + xl and the constant
c = 2^32 · ch + cl, the product is xl · cl + 2^32 · (xl · ch + xh · cl),
modulo 2^64. Of the last two products only the low words count. The math
unit computes xl · cl, and then each of the two others in turn, but one
that takes at most four shifts, additions, and subtractions is computed
so, while the math unit computes xl · cl. xorshift64*'s constant
0x2545F4914F6CDD1D takes three products of the math unit, nine
instructions. With `--no-mpu` the multiplication calls `__mul64`.

## Register allocation

The back end works on a list of instructions and labels. It finds the
jumps between them, and which flags (ISA.md §6) each instruction may
leave for a later one to read. A test `MOVE[M] R0, x` of a value that
the same straight-line code computed, with no instruction between that
reads or writes the flags, goes away: the instruction that computed x
gets the M bit instead, as in `ADD[M] x, a, b`. A logic operation or a
shift whose bit shifted out is discarded sets the flags just as the
`MOVE[M]` would. An arithmetic operation also sets C and V from the
operation, so it takes the test's place only if neither is read before
the flags are written again. For a copy `MOVE x, y`, the instruction
that computed y gets the M bit, if it can.

Then the back end finds which registers are live at each instruction. It
removes the instructions whose only effect is to write a register that
is not read afterwards. So of the declared locals, which wasm sets to 0,
only those that may be read before they are set get a `MOVE x, R0`. An
instruction with the M bit stays for its flags, but if its result is not
read, it writes R0 instead, as in `AND[M] R0, x, 1`. Then it splits
each virtual register into webs: each web is the definitions that reach
a common use, with those uses. A local that the wasm code
reuses for unrelated values thus gets a register for each of them.

The registers are colored by iterated register coalescing (George and
Appel, 1996), with R1–R12. A move between two registers that do not
interfere is removed if, by the tests of Briggs and George, that cannot
make the coloring fail. This includes moves to and from the physical
registers of calls, so an argument is often computed straight into R1.
A call may change R1–R6 and the flags, as ABI.md allows, so a value that
is live across a call gets one of R7–R12, which ABI.md preserves. A call
of a helper changes only the registers that the helper uses, all among
R1–R6. A value that is not live across a call gets one of R1–R6 if it
can, since the function must save each of R7–R12 that it uses.

If there are too few registers, the values with the lowest cost for
their number of neighbors go to frame words. The cost of a value counts
its uses and definitions, each weighted by 10 for each loop around it,
so values in inner loops keep their registers. NICE takes a memory
operand almost anywhere, so a value in a frame word is used in place, as
in `ADD R1, @2[R13], R3`. Only where it is an address, as in `@x[Rn]`,
or is changed by a side effect, does it go to a temporary register for
that one instruction, and the coloring runs again. Values in frame
words that are never live at the same time share a word.

Then each source operand 0 becomes R0, which reads 0 too (ISA.md §4.3)
and takes no constant word. So `MOVE x, 0` becomes `MOVE x, R0`, the
`CLR x` of ISA.md §10.1, in one word, and the compare `SUB[M] R0, 0,
y` becomes `SUB[M] R0, R0, y`. The passes before this one see the
constant. The helpers and the start code write R0 the same way.
Then nicewasm removes each `MOVE` of a register to itself and each jump
to the label that follows it.

Next, a conditional jump over up to four instructions goes away, and
they get the opposite condition instead. On the FPGA core, a taken
conditional jump costs six cycles more than a skipped instruction
(doc/MICROARCH.md §5.4). The instructions must not write the flags or be
conditional already, and no label may come between them. A skipped
instruction makes no memory access (ISA.md §3), so they may access
memory. So `if (x) y = 9;` is `MOVE[M] R0, x` and `?!Z MOVE y, 9`. The
code of an if before its else, up to two instructions and the jump to
the end, becomes conditional the same way, jump and all.

An unconditional jump to code of up to three instructions that ends in a
jump or a return gives way to a copy of that code. That saves the jump,
which costs at least two cycles on the FPGA core. So a `return` in a
function that saves at most two registers and has no frame words becomes
the epilogue itself. Code that ends in the jump of a `br_table` may have
up to twelve instructions, so that each case of an interpreter's loop
ends with its own copy of the dispatch. The copy has no labels. A jump
in it to one of the original's labels, such as from a stub back to the
code, goes on in the original, which does the same, and so a trap's R2
points at the original. The jumps of the stubs after the epilogue stay,
since the stubs run rarely: copies there cost words and save little.
Code that no jump reaches any more goes.

A `br_if` back to the start of a loop, at the end of the loop, is
usually taken. On the FPGA core DECODE predicts a conditional `ADD PC,
PC, offset` taken when the offset is negative, and a predicted jump costs
what an unconditional jump to a label does when taken, a bubble of 3
cycles in a stream without reads and 2 behind a read, which holds the
stream up a cycle (`hdl/test/bubble.nasm`, MICROARCH.md §5.4). So the `br_if` becomes `?cc ADD R15,
R15, top-next`, where `next` is a new label right after it, written as
`?cc JMPR top` at the end (ISA.md §10.1). Each round of
the loop then costs two cycles and one instruction less than a skipped
conditional jump out and an unconditional one back, and leaving it, a
mispredict, costs six cycles more, as a taken conditional jump did. If an
unconditional jump follows the `br_if`, leaving the loop takes two more
cycles than if the two swapped targets, but a loop that runs three rounds
or more still gains. A loop that runs once pays the six cycles at its
exit and gains nothing.

A `br_if` out of a block whose other arm ends in a `br` forward, as in
`block; block; c; br_if 0; A; br 1; end; B; end`, jumps over arm A to
arm B. Without a profile, nicewasm guesses that the shorter arm is the
rarer one, as an edge case tends to be. So if A has fewer instructions
than B, the jump goes to A on the opposite condition instead, and A
moves to the end of the function, after the return, so that B falls
through. A may have no other unconditional jump, and no jump back,
which would be the next round of a loop. In the benchmark, this made
heapsort's sift take some 51000 cycles fewer.

Last, on the FPGA core, a data read waits a cycle for a conditional
jump just before it that is not taken (doc/MICROARCH.md §5.3). So an
earlier instruction of the same straight-line code moves to between the
two, if one can: it must compute a register from registers only, with
no flags, the code it passes must not use the register or change its
sources, and the register must not be live where the jumps it passes
go. Nor may it be the read's address register, or its count if the
read is a shift, as the `SHL` of a byte access is, since the read would
wait for it instead on a core that forms the count in PREPARE. In a
copy of an interpreter's dispatch, for example, the `ADD` that
computes the next pc moves to just before the jump through the table.

Often no earlier instruction can, as when the read is the first
instruction after the label of a word access. Then one of the next four
instructions after the read, in the same straight-line code, may move
to between the jump and the read instead. This holds for any
conditional jump just before a read: the jump to the stub of a word
access, the check of a 2-byte access for p = 3, or a `br_if` just
before a load from a constant address. This is done on the virtual
registers, before the allocation, so that the moved instruction gets a
register of its own. It must compute a virtual register from virtual
registers and constants, with no flags, be unconditional, and not be a
copy, which the allocator may remove. Neither it nor an instruction
that it passes, the read included, may write a register that the other
reads or writes. It may pass a label that no jump goes to, such as the
start of the code of a wasm instruction, where a trap's R2 points, only
if it is the first instruction after it. The label then moves with it,
so R2 still points at the first instruction of that code, as in the
vm's `ROR` of the address of a store just after a load.
It may pass the label where the stub of a word access comes back, or
another label that only unconditional jumps go to, if it is in a loop:
then a copy of it goes just before each of those jumps. So every path
past the label runs it once, as before, and an access that traps in its
stub has not run it. If the stub goes on in a copy of the code, as for
a group of accesses that share a compare, the copy runs its own. It may
not be the value that a later `MOVE[M] R0`
tests, since it then could no longer take the M bit.

A data access also waits a cycle when the instruction just before it
writes its address register, since the core forms the address in
PREPARE, before that instruction's WRITE (doc/MICROARCH.md §3). So one
of the next four instructions may move to between them in the same
way. Labels that no jump goes to, such as the start of the access's
code, may be between them, and the moved instruction goes before those.
In crc32, the `SHR` of the CRC moves to between the `AND` of the table
index and the load from the table.

## The frame

There is no frame pointer. The prologue pushes the registers of R7–R12
that the function uses, then reserves its frame words with `SUB R13,
R13, n`. The epilogue drops them with `ADD R13, R13, n`, pops the
registers, and returns with `MOVE R15, @R13++`. A function that needs
neither has no prologue. Frame words are addressed from SP, as `@k[R13]`.
SP moves only in a call sequence: each stack argument and the return
address are pushed, the return pops the return address, and `ADD R13,
R13, n` drops the stack arguments. nicewasm counts the words pushed at
each instruction, so that it can address the same frame word from
anywhere. All sources of an instruction are read before its destination
is written (ISA.md §5), so `MOVE @--R13, @3[R13]` pushes the frame word at
3 above the old SP. A parameter that arrives on the stack is read at
entry from above the return address.

A function that starts with a test and an early return often needs no
saved register on that path, as in a recursive walk of a tree that
returns at once for a null node. If the first jump of the function is a
conditional one, and the code it goes to returns without a saved
register, SP, or a call, within ten instructions before the return,
the test and the jump come before the prologue. The jump then goes to a copy of that code, which returns with
`MOVE R15, @R13++` alone. The instructions before the jump may not need
a saved register or SP either, except those that only write a saved
register from other registers and constants, such as the copy of a
parameter. These come after the prologue instead. If one of them sets
the flags for the jump, a copy of it that writes R0 sets them before
the prologue. Where it reads a saved register that an earlier one
of them copied from another register or a constant, the copy reads
that instead, and if it cannot, the jump stays after the prologue.

A call of a function or a helper by its label, just before the return,
is a tail call: the epilogue drops the frame and restores the saved
registers, and then jumps to the label with `MOVE R15, label`, without
pushing a return address. The callee then returns to this function's
caller, with its results in R1 and up, which are this function's. A
call with stack arguments drops them after it, so it is never a tail
call.

`return_call` and `return_call_indirect` are tail calls of their own,
which need no call just before the return. They end in a TAIL, an exit
that the register allocator sees as it sees the return, reading the
argument registers. Before it, the callee's stack arguments are written
to the words of this function's own, `@%aN`, which nothing reads after
the copies of the parameters at the start. Then the register arguments
go to R1 and up. A register target, the function of a
`return_call_indirect`, goes to R5, which the epilogue does not restore.
The back end gives the TAIL the same epilogue as the return, with
`MOVE R15, target` in place of `MOVE R15, @R13++`. A callee with more
words of stack arguments than this function gets a call, then the
return.

The translated functions may use every register. The helpers and
`___wasm_start` use only R1–R6, R13, R14, and R15, so a value in R7–R12
survives a call of a helper, as it does any ABI.md call.

## The output

The passes see each idiom written out: a jump is `MOVE R15, x`, a
compare `SUB[M] R0, a, b`, and a call `ADD @--R13, n, R15` then `MOVE
R15, f`. Once a function's code and the helpers are lines, nicewasm
writes the idioms as the pseudo-instructions of ISA.md §10.1, so that
the output reads like hand-written NICE assembly: `JMP`, `JMPR`, `CMP`,
`TST`, `PUSH`, `POP`, `CLR`, `NOP`, `RET`, and `CALL`. Each assembles to
the same words. A `CALL` stands for the two instructions only where they
follow each other with one condition, and the `ADD` pushes the size of
the jump in words. A `JMPR top` stands for `ADD R15, R15, top-next` only
where the label `next` comes right after it and nothing else names it,
and that label goes. A line with a comment stays as it is. So a call and
the return are:

                    CALL    W.f12
                    RET

Then the labels of short loops become the anonymous labels of ISA.md
§10.1, as hand-written code has them. A short loop is a jump back to a
label over at most 10 instructions. If only jumps in the loop name its
label, the label becomes `:`, on the line of the next instruction if
one follows, and the jumps name it `:-`. So does a label in the loop,
or right after its jump back, that only jumps in the loop name, as `:+`
from above it.
A reference with more than two signs, such as `:---`, keeps the name.
A `JMPR` names its target as a `JMP` does, so a short loop that the
predicted jump closes is:

    :               SUB[M]  R3, R3, 1
            ?!Z     JMPR    :-

A relative jump that is still an `ADD` keeps the name of the loop's
top, since an expression holds one anonymous reference only.

A function's label, a label that starts with `_`, and a label that a
`.DAT` or an operand other than a jump's target names keep their
names. A stub after the epilogue names the start of its access, with a
`.DAT` or in `R2`, and jumps back from afar, so a loop with a checked
access keeps those labels.
