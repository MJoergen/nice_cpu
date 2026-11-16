# Thirteenth review of the repository, at commit 611498b

Reviewed on 2026-11-16: the 37 commits between `V2.2` and the head of `dev-V2.3`, commit 611498b ("nicedbg: the console's line after its modes"), before the release `V2.3`. They add the functions of the FPU (#167, #182, #183): `SIN` to `HYPOT`, each a sequence of steps that `emulator/test/fpu_seq.py` holds, with the commands `XMUL` and `CHOP`, in the model, the emulator, and `hdl/src/fpu.vhd`. They put `math.h` on those functions and take the float library in software out (#184), check for the FPU at the start of a program (#179), give the screen a chunky mode (#187), let niceasm take spaces in an expression (#174), add the `iscanf` family (#177), the names of the colors (#175), `nice.heap_end` and `nice.grow` (#168), a CR as the end of a line (#189, #191), and nicedbg's `help` from one table (#190), and prove the bound of `SCALE10` (#181). A code review of the same commits was run before this one, and its findings are fixed. This review looks at two things: what the documents say, and what the tests cover.

**How it was checked.** I read the diff of every document since `V2.2`, and DEVICES.md §1.10, §8, §11.3, and §11.5 whole. For each change I looked for the other places that state the same fact: the READMEs, the documents of `doc/`, the usage texts, CLAUDE.md, and CONTRIBUTING.md. I checked the statements about NiceMonMEGA65 against its checkout and its tags. On the unchanged tree I ran `make all`, which passes: 1668 lines of `PASS`, in 1786 seconds on a machine that ran the rest of this review at the same time. CI passed every job on 611498b. I ran `release.py figures`, and the benchmarks on the pipelined core in nvc.

For the functions I measured which steps of the sequences each test runs. A script puts a counter in the model's `function()` and replays on it the vectors of `make test` with both seeds, the slow vectors, the calls of `fpu_model_test.py` and of `float_fpu.py`, and the 7542 calls that the programs of every test suite make, which an emulator built for this review wrote to a file. For the steps that nothing runs I searched operands that run them, checked the model on them against mpmath, and replayed them on the emulator, built for the host's CPU and for the baseline one, and on `fpu.vhd` in nvc. For the bounds of the functions I searched operands where the code's own comments lean on something: a base next to 1 for `POW`, and operands next to a power of two for `HYPOT` and `ATAN2`, the last with musl's `atan2` compiled for the host on 10^9 pairs.

Three agents, each in a copy of the repository, looked at what the tests cover: the emulator, `hdl/`, and the runtime with the translator, the assembler, and the debugger. Each broke the code on purpose, one rule at a time, to see which test fails: 42 changes in the emulator, 42 in `hdl/`, and 81 in the runtime and the tools. One of them compiled the C sources that DEVICES.md §11.3 names, musl's, fdlibm's, and FreeBSD's, for the host, and compared the functions with them bit for bit. I ran again by hand what this review states as a bug or shows with its output: the bugs of §2, on `V2.3` and on `V2.2`, those of the bounds on the model against mpmath to 600 bits or more, and the first also against the host's `pow` and FreeBSD's and fdlibm's code compiled for the host; the reset of §3.2, with the agent's testbench; and the changes that pass in §3.4, §3.5, §3.6, and §3.7, each run to its end in a clone of its own. The other changes that pass are the agents' runs, which I read against the tests they name.

## Summary

**The release steps are open** (§1). RELEASE_NOTES.md has no section for `V2.3` (§1.1), its table still says "none yet" for the board's `V2.1` and `V2.2` (§1.2), and `emulator/build.zig.zon` says `2.2.0` (§1.3). `release.py figures` fails: `bench.c` takes 2351494 cycles on the pipelined core now, and bench/README.md has the 2339110 of `V2.2` (§1.4). The board has no issue for three things that break or go stale there when it follows (§1.5).

**Three bugs pass every test** (§2), and the first and the last are best fixed before the tag.

- `POW`, and so C's `pow`, is up to some 630 ulp off for a base within 2^−20 of 1 and an exponent above 2^31 (§2.1). DEVICES.md and runtime/README.md say 1 ulp. The sequence follows FreeBSD's `e_pow.c` there bit for bit, and the error is that code's; `V2.2`, with musl's `pow`, gave the true value. The general path of the same code is within 0.7 ulp on these operands. It is a rule of the specification, so it costs least to change before a release has it.
- `HYPOT` is up to 1.03 ulp off, and `ATAN2` up to 1.52, where the same two documents say 1 and 1.5 (§2.2). The bits are musl's, and it is the bounds that are wrong, for operands next to a power of two.
- A program without floats that exports a function with the name of one of the float library's, such as `log` or `round`, no longer builds (§2.3): nicebuild takes the program's own label for a call of the library, joins the library, and niceasm reports the label as defined twice. It built on `V2.2`.

**The tests run less of the functions than they seem to** (§3.1), and they draw their operands evenly, which is how §2.1 and §2.2 got through. The sequences have 5134 steps. The vectors that the emulator replays in `make test` never run 501 of them, and those of `tb_fpu`, which have another seed, never run 614. All the tests together, with the programs and the fuzz of the release gates, never run 139. Eleven of those are dead. The other 128 are reachable: 96 are the correction of the reduction by π/2 in `SIN`, `COS`, and `TAN`, which an operand next to an odd multiple of π/4 runs one time in four. But for §2.1 the steps are right: 52 vectors run every reachable step that the others leave out, the model is within its bounds on those paths against mpmath, and the emulator and `fpu.vhd` give the model's bits.

**Beside the vectors the tests are thin in a few places:**

- a reset while a function runs: `fpu.vhd` without the reset of `seq_r` passes every test (§3.2);
- the cycles of a third of the slow vectors, which `tb_fpu` does not time (§3.3);
- `pow` of a base just above 1, and `cos` and `tan` at the limit of the reduction (§3.4);
- trap 9: the line of its report, its name in the emulator, and the check for a module whose only float is a conversion, a comparison, or `sin` (§3.5);
- niceasm's `.ORG` and `.RES` with spaces, and a `*` at the end of a word (§3.6);
- `--ram` alone and a library module in the reserved part, the heap's clamp, `--no-screen-mode` on the command line, and the chunky mode in `--screen` and in the window (§3.7).

Where this review ran the case that is missing, the code is right.

**The documents of the release agree with the code**, with small exceptions (§4, §5): emulator/README.md does not know the sequences, the float column of the steps in runtime/README.md is 10 to 24 steps too high, hdl/README.md has three old counts, and the sequences, which follow fdlibm's and FreeBSD's code operation by operation, carry no notice and are not in the README's License section.

Nothing is fixed yet, and no issue is filed.

## 1. The release

### 1.1 RELEASE_NOTES.md has no section for `V2.3`

The newest section is `V2.2`. RELEASE.md step 2.8 asks for the section, and for a row `V2.3`, "none yet", in the table of board tags. `release.py notes` drafts it. The upgrade notes must say at least:

- **The float library in software is gone** (#184): `runtime/float.zig`, `float.wasm`, and the generated `float.nasm`, nicebuild's `--no-fpu`, `make -C runtime float.nasm`, and `NO_FPU=1` in the Makefiles of the runtime, the C library, and the benchmarks. A program that uses floats runs only on a system with the FPU. Its start-up code checks for it and traps with code 9 (#179), where in `V2.2` it computed wrong results.
- **The functions of `math.h` have other bits** (#184). `log`, `log2`, `exp`, and `pow` follow fdlibm and FreeBSD where they followed musl, so `exp(1)` is the double above e. The float functions round a binary64 result, so `acosf(-1)` and `atanf` of an infinity are the nearest floats. `exp2` and `hypot` are new. A Zig or Rust module that exports a function with the name of one of the library's, such as `pow`, no longer joins with it (§2.3). And `pow` next to 1, if §2.1 stays as it is.
- **niceasm reads a line with a comma by its commas only** (#174). `ADD R1 R2, R3` is an error now, and `.DAT 1 +5, 3` is two words, 6 and 3, where it was three.
- **The console's Enter key is CR** (#189, #191). nicedbg's console sends CR where it sent LF, and `fgetc`, and so `getchar`, `fgets`, and `scanf`, return a CR as `'\n'` and a CR LF as one `'\n'`. A program that read the bytes of `stdin` as they came has `nice_getc` for that. `readLine` and `read_line` end a line at a lone CR too.
- **The emulator's screen is 16000 words** (#187), `0xFFFF0000`–`0xFFFF3E7F`, and `0xFFFFFF87` is the screen's mode word, where it was reserved and kept any value: a write of a value other than 0 and 1 now writes 0. `--no-screen-mode` makes it memory again, and the runs that compare a core with the emulator pass it.
- **`hdl/src` has a new file, `fpu_seq_pkg.vhd`**, which `fpu.vhd` needs: a build that lists the files, as NiceMonMEGA65's `core.mk` does, adds it. The FPU takes 5.5 block RAMs with it. Out of context it now leaves +0.898 ns in the default flow, below its budget of 1.0 ns, and RELEASE.md asks the notes to say so, with the cause: the worst path is in `fpu_unit.vhd`, from `a_r` to a DSP, which no commit of this release changes (618d7cd).
- `0x1E` and `0x1F` of the FPU are `XMUL` and `CHOP`, and `0x40`–`0x4F` are the functions, where they set the invalid flag.
- nicewasm takes the imports `nice.heap_end` and `nice.grow` (#168), and `malloc` and the heaps of `nice.zig` and `nice.rs` work with `--memory-bytes` and `--ram`. A module built against the runtime of `V2.3` does not translate with the nicewasm of `V2.2`.
- nicedbg's `help` prints one line for each command (#190), which a tool that reads it must follow (MJoergen/NiceMonMEGA65#143).
- The demo joins `runtime/colors.nasm` (#175), so a build that joins `demo.nasm` by itself needs the file too.
- The debug link stays version 8, and Zig stays 0.17.0.

**Fix:** write the section, with the line "The version is 2.3.0." under the emulator's heading, and the row of the table.

### 1.2 The table of board tags says "none yet" for `V2.1` and `V2.2`

RELEASE_NOTES.md lines 17 and 18. NiceMonMEGA65 has both tags: its `V2.1`, of 2026-11-14, pins c7d7974, which is `V2.1` here, and its `V2.2`, of 2026-11-15, pins 1bd0085, which is `V2.2`. RELEASE.md step 2.8 keeps a row at "none yet" only until the board follows. DEVICES.md §8 already says that the board has the FPU "from its `V2.2` on".

**Fix:** `V2.2` and `V2.1` in the two rows, with the row of §1.1.

### 1.3 `emulator/build.zig.zon` still says `2.2.0`

RELEASE.md step 2.9 asks for the new tag's version there before `release.py check`. **Fix:** `2.3.0`.

### 1.4 `release.py figures` fails: the cycles of `bench.c` are those of `V2.2`

    $ python3 release/release.py figures
    Figures (RELEASE.md step 2.4)
      FAIL bench/README.md has 'bench.bin: 1697007 instructions, 2435862 cycles (estimate), CPI 1.435'
      FAIL bench/README.md quotes 2351155 (total 1652811 2351155 1.423)
      ok   bench/README.md quotes 617442, float on the pipelined core
      ok   bench/README.md quotes 355798, float_inline on the pipelined core

`bench.wasm` changed with fe28596, where `malloc` took `nice.heap_end` and `nice.grow`: the module is 11604 words, from 11588. It runs the same 1652811 instructions in its phases, but the code after `malloc` lies 16 words further on, and that moves the cycles of five of the six phases. On the pipelined core, in nvc, at this commit:

| Phase | bench/README.md, at af029f1 | At 611498b |
|---|---|---|
| `rng64` | 82060 | 82060 |
| `crc32` | 80762 | 83069 |
| `bst` | 402885 | 403407 |
| `heapsort` | 378646 | 371012 |
| `vm` | 1232167 | 1248168 |
| `strings` | 162590 | 163778 |
| total | 2339110 | 2351494 |

That is 0.5% more. The model gives 2351155, 339 below the core, as before. bench/README.md says "at commit af029f1" beside its figure, so it states nothing false, but step 2.4 asks for the figures of the release, and `release.py check` stops here. The figures of `float.c` hold: 617442 and 355798.

**Fix:** release step 2.4, as for `V2.2`: the summary line, the table of the phases, the cycles per instruction, and the comparison with `hand.nasm` in bench/README.md, from `make -C bench cycles` and `make -C bench core`.

### 1.5 NiceMonMEGA65 has no issue for what `V2.3` asks of it

The board follows a release at its own pace (RELEASE.md step 7), and it has issues for two of this release's changes: MJoergen/NiceMonMEGA65#144, the chunky mode, and #143, `help`. Three more things break or go stale there when its submodule moves, and no issue names them:

- `core.mk` line 32 lists the FPU's files, `fpu_pkg.vhd fpu_unit.vhd fpu.vhd`, without `fpu_seq_pkg.vhd`, so its build fails.
- Its `doc/PROGRAMMING.md` line 270 names `nicebuild.py --no-fpu` for a board without the FPU. The option is gone.
- Its timing with the FPU was met by +0.114 ns on the R3 and +0.152 ns on the R6 at its `V2.2`. The functions add some 340 LUTs to the FPU, which now takes 5.5 block RAMs, and its slack out of context fell from +1.276 ns to +0.898 ns.

**Fix:** an issue in NiceMonMEGA65 for the three, named in the notes of §1.1.

### 1.6 The rest of the checklist

- The milestone `V2.3` has 16 closed issues and none open. #66, #67, #147, and #186 are closed too, each with its paragraph in doc/review/decisions.md.
- The debug link stays version 8, and DEBUG.md §9 needs no row. `emulator/src/link.zig` changes by two lines, which keep `--no-screen-mode` over a clear.
- No `make -C hdl sweep` is owed: the diff of `hdl/src` is `fpu.vhd` and `fpu_seq_pkg.vhd`. Each of the five commits that change a path of the FPU gives `make timing UNIT=fpu` before and after in its message, as CONTRIBUTING.md asks: 83da02c, 8c45924, 30a19df, f1e3ea2, and 618d7cd. fa98df0 changes one constant and one comparison of the ROM.

## 2. Three bugs that every test passes

### 2.1 `POW` of a base next to 1 is up to some 630 ulp off

DEVICES.md §11.3 says that `POW` "is within 1 ulp; the worst error of 320,000 samples is 0.84 ulp", and runtime/README.md says of `math.h` that "each result is within 1 ulp of the true value". For a base within 2^−20 of 1 and an exponent above 2^31 in size, where the result is neither 0 nor ∞, that does not hold:

| Y | X | `POW`, and C's `pow` in `V2.3` | The true value, rounded | Off by |
|---|---|---|---|---|
| `3FEFFFFF9B2003F2`, 0.99999981 | `41E88783927172C9`, 3.29 · 10^9 | `08276C7D15F0CD05` | `08276C7D15F0CB77` | 398 ulp |
| `3FEFFFFFCBEEABD1`, 0.99999990 | `41F48E19F147AC52`, 5.52 · 10^9 | `0FAF6BBC0A6671D9` | `0FAF6BBC0A66701A` | 447 ulp |
| `3FF000003F7D991F`, 1.00000024 | `41E40B1019BBF5A9`, 2.69 · 10^9 | `794F04B6E2583719` | `794F04B6E25838C8` | 431 ulp |

- **It is the C code's.** FreeBSD's `e_pow.c` and fdlibm's, compiled for the host, give the model's bits on the first line, and on all of the agent's 1.7 million pairs. For such operands the code takes log₂ of the base from a short series, `pow_log1` in `fpu_seq.py`. Its comment takes the product `ivln2_h*t` for exact: "t has 20 trailing zeros", "ivln2_h has 21 sig. bits". But `ivln2_h` is `0x3FF7154760000000`, 24 bits, and t has up to 33, so the product is rounded. That is an error of up to half an ulp in the logarithm, which the exponent then multiplies by up to 1074.
- **How often, and how far.** Of 1000 random such operands with a base below 1, 27 are 1 ulp or more off, and of 1000 with a base above 1, 13 are. The median error is 0.27 ulp. The error grows with the exponent of the result: of 1500 operands with a base 2^−24 to 2^−21 from 1 and a result beyond 2^±900, 383 are 1 ulp or more off, and the worst is 634 ulp, at Y = `3FEFFFFFA01AAAAA` and X = `41ED25051130BE25`.
- **`V2.2` was right.** With the nicebuild and the C library of `V2.2`, which had musl's `pow`, the program gives the true values of the table, as the host's `pow` does.
- **No test has such an operand.** `function_bounds` of `fpu_model_test.py` draws the exponent so that the result is finite, with a base from any of 61 binades, which comes within 2^−20 of 1 once in tens of millions of samples, and `fuzz_math.py` draws from the range where `pow` is most used. The vectors of `make test` never run the steps of the path, 388 to 435 of `POW`, on the emulator or on `fpu.vhd` (§3.1). `float_fpu.py` runs them, and compares with the model.
- **The general path is within the bound there.** With `pow_log` in place of `pow_log1`, in a copy of `fpu_seq.py`, none of the same 2000 operands is 1 ulp off, and the worst is 0.7 ulp. fdlibm takes the short series for speed.

The case is rare: a base that differs from 1 by less than one part in a million, to a power of billions. It is what a compound rate over many small steps computes.

**Fix:** DEVICES.md first, one of two. Either `POW` takes the general path for every base, and departs from FreeBSD's bits for these operands: `pow_log1` and its 48 steps go, the sentence on `e_pow.c` says so, and `POW` keeps its bound. Or the sequence stays, and DEVICES.md §11.3 and runtime/README.md say where the bound does not hold, and by how much. I would take the first. Either way, operands of this kind among those of `function_bounds` and `fuzz_math.py`, and the three lines of the table in the directed vectors.

### 2.2 `HYPOT` and `ATAN2` pass their bounds, by 0.03 ulp

DEVICES.md §11.3 says of `HYPOT`: "It is within 1 ulp; the worst error of 320,000 samples is 0.98 ulp." Of `ATAN2` it says: "It is within 1.5 ulp", and "the worst error of 320,000 samples is 1.35 ulp". runtime/README.md says the same of `hypot` and `atan2`. Neither bound holds. On the model, against mpmath:

| Function | Y | X | Result | The true value, rounded | Off by |
|---|---|---|---|---|---|
| `HYPOT` | `2D3000001617B6BC` | `2D3000000023FEDA` | `2D36A09E7637E144` | `2D36A09E7637E143` | 1.028 ulp |
| `HYPOT` | `1A700000AC11E529` | `1A7000000021B5D9` | `1A76A09EE0430E13` | `1A76A09EE0430E12` | 1.027 ulp |
| `HYPOT` | `3FF0000109CBF173` | `3FF000000008C4D0` | `3FF6A09F2277C793` | `3FF6A09F2277C794` | 1.020 ulp |
| `ATAN2` | `BFA003DEC75DA384` | `3FF003A708A81F8C` | `BF9FFDC503D47312` | `BF9FFDC503D47310` | 1.523 ulp |
| `ATAN2` | `3FA00268B443C6CF` | `3FDFFB347A586826` | `3FAFFEF07EABD502` | `3FAFFEF07EABD500` | 1.523 ulp |
| `ATAN2` | `BFA00024D41534F8` | `3FEFFFDBEF75879D` | `BF9FFDC359723161` | `BF9FFDC35972315F` | 1.523 ulp |

C's `hypot` and `atan2` give the same bits, on the first and the fourth line.

- **The bits are musl's**, so it is the bounds that are wrong, and by little.
- **`HYPOT`.** Both operands are just above the same power of two. musl's `hypot` then adds the two squares, each just above 1, in two sums that each round, by up to 1.5 ulp of a square together. The root halves that, and rounds once more: 0.5 + 0.375 · √2 = 1.03 ulp, by this count the most there can be. The agent's search finds 79 of 600,000 such pairs at 1 ulp or more, and none past 1.03.
- **`ATAN2`.** Y / X is just above a power of two, 2^−3 to 2^−6, and the result is just below it. The rounding of the quotient is then a whole ulp of the result, and the `atan` rounds by half an ulp more. The rest, some 0.02 ulp, I take to be the error of its polynomial. Of 10^9 such pairs, on musl's code compiled for the host against the host's `atan2l`, 544 are past 1.5 ulp, and the worst are the three of the table.
- **Why no test finds them.** `function_bounds` of `fpu_model_test.py` draws 400 pairs for each function, and `fuzz_math.py` draws its pairs from every binade. Neither puts both operands next to a power of two, or their quotient there. The two figures "of 320,000 samples" are of such even samples too.

**Fix:** in DEVICES.md §11.3 and runtime/README.md, bounds with some room, such as 1.1 ulp for `HYPOT` and 1.6 for `ATAN2`, each with its reason and the worst that is known, and the same in `BOUNDS` of `fpu_model_test.py` and of `fuzz_math.py`. Operands of both kinds among those of `function_bounds`, and the lines of the table in the directed vectors.

### 2.3 A program without floats that exports `log` does not build

`nicebuild.py` joins the float library when the program holds one of the library's labels (line 258). A label that the program defines itself counts too. So a Zig, Rust, or C program that exports a function with the name of a routine of `math.h` gets the library, though it calls nothing of it, and the label is then defined twice:

    $ cat ex2.zig
    var a: i32 = 5;
    export fn log(x: i32) i32 {
        return x * 3;
    }
    export fn main() i32 {
        const p: *volatile i32 = &a;
        return log(p.*);
    }
    $ python3 translator/nicebuild.py -o ex2.bin ex2.zig
    /tmp/tmp4u2k105u/full.nasm:721: error: symbol '_log' is already defined on line 107
    1 error
    nicebuild: niceasm.py failed with status 1

- With the nicebuild of `V2.2` the same file builds and runs, with R1 = 15. So does a C file with `__attribute__((export_name("round")))` on a function of its own, which fails the same way now.
- In `V2.2` the library had the labels of the float operations, `___adddf3` and the like, which no program defines. Since 0f337d1 it has 33 labels of `math.h` too: `_log`, `_round`, `_pow`, `_exp`, `_hypot`, `_fmod`, `_ldexp`, and the others. `log` and `round` are names a program without floats may well export.
- runtime/README.md line 301 says that a program that defines one of these labels "cannot be joined with the library". That holds, and is not this case: this program needs no library.
- A function that is not exported has no label, so a C program with a `static` or plain `log` of its own builds.
- `translator/test/build.py` has no program with such a name.

**Fix:** in nicebuild, a label counts as a use only where the program does not define it: take the labels at the start of the program's lines out of the set before the test. A program with floats that defines `_log` still fails, as the README says. A case in `build.py` for each: the program above, which must build, and one with a float, whose error is the README's.

## 3. Test coverage

### 3.1 The tests never run 501 to 614 of the 5134 steps of the functions

The 14 sequences have 5134 steps, 249 of them `JZ`. A step runs on the model, on the emulator, and on `fpu.vhd` only where an operand takes its path. What each test runs, measured on the model:

| What runs the functions | Steps never run |
|---|---|
| The emulator in `make test`: its vectors, 35754 directed and 20001 random lines of seed 161 | 501 |
| The same with the programs of every test suite, 7542 calls | 425 |
| `fpu.vhd` in `make test`: `tb_fpu`'s vectors of seed 1, the slow vectors, and the probe `fpufunc`, 11 calls | 614 |
| `fpu.vhd` with all of those programs, most of which CI's `make programs` runs on the cores | 488 |
| The model in `fpu_model_test.py` | 596 |
| All of these, and `runtime/test/float_fpu.py` | 211 |
| With `fuzz_math.py 1 1000` of `make slow`, on the emulator | 139 |

The steps that the emulator's vectors leave out, by function:

| Function | Steps | Never run | What takes the path |
|---|---|---|---|
| `SIN` | 701 | 114 | 5π/4 ≤ \|X\| < 7π/4, where n = ±3; one sign of 7π/4 ≤ \|X\| < 9π/4; the high word `0x3FF921FB`; the correction below |
| `COS` | 716 | 143 | the same |
| `TAN` | 750 | 125 | the same, and a negative X from −0.6744 to −π/4 |
| `ATAN2` | 404 | 9 | dead |
| `LN` | 254 | 14 | X in [1.380, 1.4142) or (0.7071, 0.7098]: k = 0 and the fraction from `0x6147A` to `0x6B851` |
| `POW2` | 189 | 2 | dead |
| `POW` | 830 | 94 | a base within 2^−20 of 1; a negative result at the overflow or the underflow; the tests of the two thresholds |
| The other seven | 1290 | 0 | |

- **128 reachable steps are run by nothing**, not by the fuzz of the release gates either: `LN` 184-197, `POW` 293-295, 377-379, 673, and 686-696, and 32 steps each of `SIN`, `COS`, and `TAN`.
- **Those 96 are the correction of the reduction**, `fn - 1.0` and `fn + 1.0` in `rem_pio2` (`fpu_seq.py:321`). musl's comment calls it a matter of directed rounding. It is not only that: the nearest whole number to X · 2/π comes from two roundings, and where X is the double next to an odd multiple of π/4 the product rounds to a half and the tie goes to the wrong side half of the time. Of 3000 such operands, with the multiple from 5 to 2^20, 667 run a correction: 344 the one down, and 323 the one up. `fpu_model_test.py` takes its operands next to a multiple of π/2, which never does.
- **11 steps are dead.** `ATAN2` calls the steps of `ATAN` on \|Y / X\|, so their two branches for a negative argument, 181-184 and 357-361, cannot run. `POW2` 55 and 78 are the jumps past a test of `p_l` that always holds where `p_l` is 0.
- **But for one path, the steps are right.** The path of `POW` for a base within 2^−20 of 1, steps 388 to 435, is §2.1. On the others that the vectors leave out, the model is within its bound against mpmath, on 200 to 600 random operands of each: at most 0.76 ulp for `LN`, 0.73 for `SIN`, `COS`, and `TAN` from 5π/4 to 9π/4 and next to the high words where the paths part, and 0.69 for `POW` of a negative base. `POW` rounds to ∞ and to 0 at the right values on 3000 operands at the two thresholds. On the 667 operands of the correction the worst errors are 0.76, 0.67, and 0.50 ulp.
- **The emulator and `fpu.vhd` run them as the model does.** 52 vectors, with the operands below, run every reachable step that the vectors of `make test` leave out. The emulator, on the host's CPU and on the baseline one, and `fpu.vhd` in nvc give the model's bits on them, in at most 2942 cycles, and both fail a line whose result is changed.
- **Why it matters.** `make seqcheck` checks that the emulator's table and the ROM are the generator's text. Whether a step is right, only an operand that runs it shows. With step 220 of `SIN` made a `NOP` in the ROM, `tb_fpu` passes all 55801 lines of `make test`, and fails one of the 52 vectors. And §2.1 is a path of the sequences that no test of the bounds takes.

The operands, in hex:

| Function | Operands that run what the vectors leave out |
|---|---|
| `SIN` | `C01196EE32DF51DA`, `4012D97D00000000`, `C0192429B3D39DDF`, `4012D97CFDD2CB40`, `BFF921FB00000000`, `401921FB34528476` |
| `COS` | `C01196EE32DF51DA`, `BFF921FBE5F31BED`, `4012D97C00000000`, `40139710A595C57C`, `4016A2454D0B42A6`, `C0192429B3D39DDF`, `401921FBFFFFFFFF` |
| `TAN` | `C01921FB00000001`, `C01196EE32DF51DA`, `400921FC00000000`, `4016A2454D0B42A6`, `C0192429B3D39DDF`, `BFE66827758397C4`, `C012D97CC407E2A9` |
| All three, the correction | `C02AB41B09886FEA`, `C07331736EDA1070`, `402AB41B09886FEA`, `407331736EDA1070`, `4055CB77F3131F1B`, `41217464DCF06AE8`, `C1361738372F2277` |
| `LN` | `3FF66876247B3559` |
| `POW`, Y and X | `3FEFFFFFFFFF9BD6` `43BE076631E12AFA`; `400B4776BDAAE23C` `408214F65B5259F0`; `C000000000000000` `C090CC0000000000`; `3FE58505B2C7265E` `409D57F96C2D8F35`; `400B93072EF726EA` `4081ECB40477AE3C`; `F8E7D1A620357B8E` `C388F211ABA10DBC`; and −0.5 and −2, each to 2^52 + 1 and to −(2^52 + 1) |

**Fix:** the operands as directed vectors in `fpu_vectors.py`, and a bin for them in its coverage, which already fails on an empty bin: every step of every sequence runs, and every `JZ` goes both ways, in the directed vectors, but for a list of the dead ones. Then a sequence that gets a new path fails `make test` until a vector takes it. Operands next to an odd multiple of π/4 among those of `function_bounds`. The dead steps can stay, or go with a pass of the generator.

### 3.2 A reset while a function runs is in no test

`fpu.vhd` holds `seq_r` while a function runs, and its reset clears it (line 1866). With that line taken out, `tb_fpu` passes on the vectors of `make test`: "55801 lines, 0 differ, at most 3359 cycles to an ACK, line 55756, 45 resets". So do the probes on both cores and `formal/fpu/prove`, in the agent's runs, which I did not repeat.

- `tb_fpu` resets every 1000th command "while it runs", two cycles after the write is acknowledged. A function has not started its first step then, so `seq_r` is still 0.
- The agent's testbench resets `POW` at 31 distances from its write, from 0 cycles to some hundreds, and then runs `SQRT` and `SIN`. On the changed unit it fails, "STATUS 00200901 after SQRT and SIN, reset at 1", and on the unit as it is it passes. So the code is right.
- The formal checks say one thing of a function: the bus rule. The proof of the stack assumes that no function runs (`f_no_function`, line 966).

**Fix:** in `tb_fpu`, after the vectors: a reset some cycles into a function, at several distances, and then a command and a function, whose results must be the model's. An assertion for `formal/fpu.sby` that a reset leaves `seq_r` at 0.

**Resolved.** `tb_fpu` runs `POW` of 1.5 and 2.5 alone, which takes 2340 cycles, and then resets it at 50 distances from its request: each of the first 32 cycles, six further in, and the last 12 before its end. After each reset, `SQRT` of 9 and then `HYPOT` of the result and 4 must give 5, with no flag. `fpu.vhd` without the reset of `seq_r` fails 49 of the 50, all but the reset in the cycle of the request. `f_seq_reset` in `fpu.vhd` asserts that the cycle after a reset the FPU is idle and `seq_r` is 0; all three tasks of `formal/fpu.sby` pass with it, and `prove` fails its induction without the reset of `seq_r`.

### 3.3 `tb_fpu` does not time a third of the slow vectors

`test/fpu_slow_vectors.py` adds the 46 slowest operands that a scan found, so that `tb_fpu` bounds their cycles (`hdl/Makefile`: "whose cycles it bounds"). But `tb_fpu` follows every third line with an access that waits for the command, and takes no time of those lines. 15 of the 46 fall there: four of `DIGITS`, two of `SCALE10`, and one each of `SIN`, `COS`, `ASIN`, `ATAN`, `ATAN2`, `LOG2`, `LOG10`, `POW2`, and `HYPOT`.

So for six commands `make test` measures less than the table of hdl/README.md gives, on some random line instead: `SCALE10` 1223 against 1235, `ASIN` 1102 against 1106, `ATAN2` 1313 against 1323, `LOG10` 1203 against 1214, `POW2` 1051 against 1053, and `HYPOT` 541 against 542. The bounds are 20% above the table, so nothing fails, but the slowest `ASIN` and `LOG10` that the scan found are never timed.

**Fix:** time every line of the slow vectors, by a mark in the file or by their place after the others.

**Resolved.** `fpu_slow_vectors.py` writes a line `#timed` before its own, and from that line on `tb_fpu` times every command, follows none at once, and resets none. The scan had the same gap, as `tb_fpu` timed two of three of its lines too. A scan with every line timed found a slower `DIGITS`, 3365 cycles for 3363, and a slower `SCALE10`, 1243 for 1235, of 1.5 by −511, and both are among the slow vectors now. `SIN` takes 1537 cycles on its slow vector, which was one of the 15, where the table had 1533. The table of hdl/README.md has what `tb_fpu` measures now.

### 3.4 `pow` just above 1, and `cos` and `tan` at the limit of the reduction

- **`_pow`.** C gives 1 for `pow(1, y)`, also where y is a NaN, and the routine of `float_fpu.nasm` tests both words of x for it. Without the test of the low word, `pow` of any base from 1 up to 1 + 2^−20 gives 1, and every test passes: `float_fpu.py`, the C library's tests, the translator's, and the benchmarks. No test has a base whose high word is `0x3FF00000` and whose low word is not 0. The code is right: `pow(1 + 2^−52, 10)` gives `3FF000000000000A`.
- **`cos.c` and `tan.c`.** Each tests the high word against `NICE_TRIG_LIMIT` by itself, as `sin.c` does. `libc/test/math.c` has the two values at the limit, `0x413921FB00000000` and the double below it, for `sin` only (lines 149 and 150). With `<=` for `<` in `cos.c` or in `tan.c`, the function gives a NaN at the limit, and the agent's run of the tests passes. The code is right: at both values `cos` and `tan` give the correctly rounded results, `3FEE4831257A62DA` and `BFD5DCA6BD170C6F` at the limit.

**Fix:** `pow` of 1 + 2^−52 in `float_fpu.py` or `math.c`, and the two values for `cos` and `tan` beside those of `sin`.

### 3.5 Trap 9: its report, its name, and three of its checks

`translator/test/run.py` checks that a module with floats traps with code 9 on `niceemu --no-fpu`: three cases, each by R1. These pass every test of the runtime, the translator, the benchmarks, and the demo:

- **The report.** In `runtime/trapmsg.nasm`, the text `'no FPU'` changed, and the first test of the code against 10 changed to 9, which prints "?" for the digit. No test prints the report for code 9. By hand it is right: "trap 9: no FPU at 0000000f".
- **The emulator's name** for the code, "no FPU" in `main.zig:237` (the agent's run).
- **The check for the FPU** where a module's only float instruction is a conversion to an integer, or a comparison, inline or called: `uses_fpu` not set for each of the three. And where its only use is `sin`, `cos`, or `tan`: `nice_sin`, `nice_cos`, and `nice_tan` out of `MATH_IMPORTS`. WASM.md states each. By hand a program whose only float is `(int)a` traps with code 9.
- **The write of 0 to `FPU_STATUS`** in the check, which WASM.md gives its reason for.
- **nicebuild's test for the library** with only the labels that start with `__`: `build.py` has no program whose only use of the library is a function of `math.h`. By hand such a program builds and runs.

**Fix:** a run of the trap report with code 9, as `trapreport.nasm` has for the others; in `run.py`, the `--no-fpu` case for a module with only a conversion, only a comparison, and only `sin`; in `build.py`, a program with only `pow`.

### 3.6 niceasm: `.ORG`, `.RES`, and a `*` at the end of a word

ISA.md §10.1 says that a directive with one operand takes all of its words, and names `.ORG`. With `.ORG` and `.RES` out of the list in `niceasm.py`, so that only `.BLK` is left, `make -C assembler test` passes. `.ORG 0x10 + 2` and `.RES 1 + 1` are then errors, and no test has either.

The same run had two more changes, which pass too:

- `joins` without the `*`. Then `MOVE R1, 4* x` is an error, where it assembles to `4*x`. §10.1 says so, "two of them with no `+`, `-`, or `*` between them are an error", while §10.2 says that a product has no spaces. Both hold only if "no spaces" means none before the `*`.
- `joins` without its test for a string.

**Fix:** a line of each in `encoding.nasm` or `errors.py`, and a word in §10.2: a product has no space before its `*`.

### 3.7 Smaller gaps

- **`--ram` alone, and a library module.** nicewasm reserves only the start of the memory for `--memory-bytes`, for `--ram`, and for a library module. With the last two out of that test, the tests of the runtime, the translator, and the benchmarks pass. WASM.md gives `nice.grow` as −1 for both.
- **The heap's clamp.** `malloc.c`, `nice.zig`, and `nice.rs` each take a heap that ends before it starts as empty. Without the clamp the agent's runs pass. By hand it works: with `--memory-bytes 4200` and a `__heap_base` of 4208, `malloc(16)` returns `NULL`. A reserved part that ends below the program's own variables traps with code 2, as the README says of any access past it.
- **`--no-screen-mode`.** `errors.py` checks that niceemu takes the option, on a program of two words. The unit test sets the field itself. With the option doing nothing, in a run, with `--link`, or over the link's clear, the emulator's tests pass (the agent's runs).
- **The chunky mode in `--screen`.** The probes `chunky` and `chunky_screen` print the pixels. The emulator's tests pass with `-2004` not moving the pixels, with a pixel black only where all 32 bits are 0, where DEVICES.md looks at the upper 12, with the black lines at the bottom kept, and with a mode word that looks at its low 16 bits only: the unit test writes 2, `0x101`, and `0xFFFFFFFF` (the agent's runs).
- **The chunky mode in the window.** `window.zig` chooses between the text and the pixels in `drawn`. With the choice taken out, so that the window always draws text, `make window-test` passes its 11 tests (the agent's run). `window.py` cannot see a pixel, and `frame.zig`'s unit tests cover the drawing itself.
- **`JZ` of −0.** DEVICES.md says that `JZ` jumps if X is zero. With a test for +0 only, in `fpu.vhd` and in `fpu.zig`, everything passes (the agents' runs). Of the 26551 `JZ` steps that `tb_fpu`'s vectors and the vectors of §3.1 run, none pops −0, and perhaps none can.
- **The names of the mode.** `NICE_SCREEN_MODE`, `NICE_MODE_TEXT`, `NICE_MODE_CHUNKY`, `NICE_PIXEL_COLS`, and `NICE_PIXEL_ROWS` of `nice.h` are in no test, and `nice.zig` and `nice.rs` have no such names (§5.4).
- **The colors.** `colors.py` checks that the four files agree, so a value that is wrong in all four passes, but for the colors the demo shows. The table of runtime/README.md agrees with the files.
- **"Bit for bit".** DEVICES.md §11.3 says that a sequence gives musl's result bit for bit, and `POW2` and `HYPOT` FreeBSD's and musl's. The tests check bounds, not bits. The claim holds: against the C sources compiled for the host, the model differs on none of 77886 operands, and the emulator on none of 223,542 operands for each function of one operand and 1,689,788 pairs each for `ATAN2`, `HYPOT`, and `POW`, but for the NaN cases that DEVICES.md names. The operands sit at every high word that a sequence compares with, one below, and one above (the agent's runs).
- **A CR in the emulator's input files.** The `.bin` file and the `--eth-in` file may end their lines with CR LF. Without the three places that say so, the emulator's tests pass; `errors.py` has a CR only in a symbol file (the agent's runs). The rule is older than this release.

**Fix:** a case for each where it is one line: `--ram` and a library module with a call of `nice.grow` in `run.py`, `--memory-bytes` just below `__heap_base` in the C library's tests, a probe that writes 2 to the mode word under `--no-screen-mode`, `chunky_screen` with `-2004` and with a pixel whose lower 20 bits only are set, and a `.bin` file with CR LF in `errors.py`. The others are for an issue, or to leave.

## 4. Stale statements

### 4.1 hdl/README.md: three counts

- Line 1386: `make programs` "makes 878 programs and runs 621 of them". CI's job on 611498b prints "634 of 634 … and 266 the same as one of them": 900 and 634.
- Line 1034: "some 31300 directed lines". There are 35754.
- Line 787: `XMUL` at most 62 cycles. `tb_fpu` measures 64, on a random line.

**Fix:** the figures. DEVICES.md §11.5 says "some 60" for `XMUL`, which may stay.

### 4.2 emulator/README.md: the tests of the FPU are those of `V2.2`

Lines 760 to 795. "Some 28000 lines are directed" is 35754 now. The groups of the vectors leave out `XMUL`, `CHOP`, and the functions, and so does the docstring of `fpu_vectors.py`. The four ways in which `fpu_model_test.py` checks the model end with the constants of 15 digits; the test's own docstring adds the bound of `SCALE10` and "the functions within their bounds, against series in decimal". See §5.1 for what the section does not have at all.

### 4.3 runtime/README.md: the steps of the float functions

The table of Math functions gives the steps of a call in double and in float. The double column holds, within two steps. The float column is 10 to 24 steps too high:

| Function | README, float | Measured, float | Measured, double |
|---|---|---|---|
| `sinf` | 70 | 59 | 43 |
| `tanf` | 71 | 61 | 45 |
| `asinf`, `expf` | 28 | 18 | 21 |
| `exp2f` | 27 | 16 | 19 |
| `atan2f`, `fmodf` | 48 | 26 | 33 |
| `powf` | 51 | 28 | 37 |
| `hypotf` | 54 | 32 | 41 |
| `sqrtf`, `floorf` | 27 | 16 | 19 |
| `roundf` | 28 | 18 | 19 |
| `fminf` | 68 | 44 | 66 |
| `fabsf` | 18 | 7 | 9 |

I measured as the README says: 32 arguments, the loop counted, on `volatile` arrays of each type. A float routine passes one word for each operand, so it takes fewer steps than the double one, but for `sinf` and `tanf`, which convert and call the double function. The README's column looks like a loop that converts its floats to double and back. No script makes the table.

Line 325 of the same file says "(Screen colors, below)" in the row of `nice.h`; the section is above.

**Fix:** the column, and "above".

### 4.4 Small ones

- CLAUDE.md line 107: `make words` gives the size of "the benchmark, safe.zig, CoreMark, float, and math modules". There is no float module now, and `bench/words.py` keeps a `--library NAME` that no Makefile passes.
- demo/README.md line 224: "the Makefile joins `demo.nasm`, the text of `TEXT`, and a line that defines `VERSION`". It joins `runtime/colors.nasm` too.
- `emulator/src/fpu.zig` line 1 and `emulator/test/fpu_model.py` line 2: "§11, phase 1". Both hold the functions of phase 2.
- `runtime/test/trapreport_big.nasm` line 1: "for a code above 7". The report knows the codes up to 9.
- translator/README.md line 465 and `nicewasm.py` line 5034: a library module may not use a float instruction, as it "would call the float library, which a library module could be part of", "which would then call itself". The float library is no module now. The rule stands; its reason is that a library module has no start-up code to check for the FPU.
- README.md, License: "the math functions of the C library, in `runtime/libc/src/math/`, are musl's". `sin.c`, `cos.c`, and `tan.c` there are the library's own now (runtime/README.md, Math functions).

## 5. Gaps

### 5.1 emulator/README.md does not know the sequences

The file names neither `test/fpu_seq.py` nor `src/fpu_seq.zig`, which is generated and checked in, nor `make seqcheck`, which `make test` runs. Its section on the floating-point unit does not say how a function runs, and its section on the tests does not say how the functions are checked (§4.2). hdl/README.md has all of it for the ROM, and DEVICES.md §11.3 names the three files. A reader who changes a sequence finds in the emulator's README no word that `fpu_seq.zig` must be written again.

**Fix:** a paragraph in the README's Floating-point unit section: the table, where it comes from, the command that writes it, and `seqcheck`; and the functions in the paragraphs on the model's test and on the vectors.

### 5.2 doc/REFERENCES.md does not link `review/scale10-bound.md`

It is the one file of `doc/review/` that REFERENCES.md leaves out. DEVICES.md §11.3 links it. **Fix:** a sentence with the other reviews. This review is linked there already.

**Resolved.** REFERENCES.md has a sentence for it, after the reviews, which says what it proves.

### 5.3 The sequences carry no notice of their sources

`emulator/test/fpu_seq.py` follows the C code of musl, fdlibm, and FreeBSD "operation by operation", with their constants, and `emulator/src/fpu_seq.zig` and `hdl/src/fpu_seq_pkg.vhd` are written from it. The comments name each source file. None of the three files has a copyright notice. `e_pow.c`, `e_log.c`, `e_exp.c`, `e_log2.c`, and `k_log.h` have Sun's notice, which grants the use "provided that this notice is preserved", and musl's files of the same origin have it too. `runtime/libc/src/math/COPYRIGHT` collects musl's notices for the C library, and README.md's License section covers `runtime/libc/src/math/` only.

Whether steps written from C code are that code is not for a review to settle. The notice costs nothing.

**Fix:** Sun's notice and musl's in the header of `fpu_seq.py`, a line in the two generated files that points there, and a bullet in the License section for the three files.

### 5.4 `nice.zig` and `nice.rs` have no names for the screen's mode

`nice.h` has `NICE_SCREEN_MODE`, the two modes, and the size in pixels. A Zig or Rust program writes `0xFFFFFF87` by its number. runtime/README.md says that the two files give "the device routines that `nice.h` gives C code". Optional: #187 asked for the mode in the emulator, and the board has not followed (MJoergen/NiceMonMEGA65#144).

## 6. What was checked, and found right

- **The tests.** `make all` passes with 1668 lines of `PASS`, and CI passes every job on 611498b. `make wasmcheck` has no note, on 54 files (the agent's run).
- **The functions.** But for §2.1 and §2.2, every reachable step runs on some operand of §3.1 and gives a result within its bound. The frame of each function takes the k values that DEVICES.md §11.3 gives, measured on the vectors and on those operands: 12, 12, 13, 10, 10, 9, 11, 10, 10, 11, 7, 9, 13, and 6. Every jump of the ROM goes forward within its program, so a sequence ends (the agent's script). `POW` and `POW2` at 1024, at −1074, and at −1075 give ∞ with the overflow flag, 2^−1074, and 0, where the exact value rounds there.
- **The cycles.** The most cycles of each function in `tb_fpu` are within the "up to some" of DEVICES.md §11.5 and below the bounds of `tb_fpu`, on the operands of §3.1 too: at most 1511 for `SIN`, 1439 for `COS`, 1992 for `TAN`, and 2939 for `POW` there. A core that waits for a function takes an interrupt, a pause, a held pause, and a single step as the emulator does, on both cores, and a read of `FPU_CMD` during `POW` returns 0 within 3 cycles (the agent's runs by hand; none is in `make test`).
- **The timing.** `make timing UNIT=fpu` gives +0.898 ns in the default flow and +1.036 ns in the timing flow, as hdl/README.md says (the agent's runs).
- **`math.h`.** `sin` of a huge argument takes at most 6075 steps and `sinf` 5237, against "some 6000" and "5500", with the host's results to 17 digits. `sin`, `cos`, and `tan` are correctly rounded at the limit `0x413921FB00000000` and at the double below it. `make -C bench words` prints the sizes that the documents give: 11604, 5903, 29891, and 7268 words, and the float library is 483 (the agent's run).
- **The benchmarks.** `float` and `float_inline` take 617442 and 355798 cycles on the pipelined core, as bench/README.md says.
- **Trap 9.** A program with a float, with only `pow`, or with only `(int)a` traps with code 9 on `niceemu --no-fpu`, and prints "trap 9: no FPU at 0000000f".
- **The chunky mode.** The probes `chunky` and `chunky_screen`, two unit tests of the frame, and two of the mode word check it in the emulator, with the gaps of §3.7.
- **The software float library** left nothing behind outside HISTORY.md, the reviews, and the old release notes, but for the lines of §4.4.
- **The documents.** DEVICES.md §8 on NiceMonMEGA65 matches its checkout: the link version 8, the FPU from its `V2.2`, #144, #106, and `0xFFFFFF87`. The memory map of emulator/README.md adds up. The arithmetic of the `SCALE10` bound in DEVICES.md agrees with `review/scale10-bound.md`. ABI.md and debugger/README.md state nothing new that no test checks (the agent's reading).
