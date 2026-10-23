# Release checklist

The steps to take before a release, in order. Each step is cheaper than the
ones after it, so a problem is found as early as possible. Do not go on to
the next step while one fails.

A release needs a clean working tree on `main`. The slow checks and the
board check in [NiceMonMEGA65](https://github.com/MJoergen/NiceMonMEGA65)
come last because they take the longest.

This repository is FPGA-agnostic and has no bitstream. NiceMonMEGA65 carries
the core to the boards as a git submodule, so a release here is also a
commit that NiceMonMEGA65 can pin. Its own checklist is
[RELEASE.md](https://github.com/MJoergen/NiceMonMEGA65/blob/main/RELEASE.md).

The mechanical parts are scripted by [release.py](README.md),
which each step names. `make release-check` runs steps 2.4 and 3 to 5, and
leaves a stamp that `release.py tag` requires. The rest is by hand.

## 1. Prepare

Run `python3 release/release.py preflight`. It checks items 1 and 3 and the
tools. Item 2 is by hand.

1. `git status` is clean, and the branch is `main`, up to date with `origin`.
2. [TODO.md](../TODO.md) lists only what is open. Nothing in it blocks the
   release, or the release notes say why it is acceptable.
3. The toolchain is the one in [README.md](../README.md): Zig 0.15.2, not the
   latest release or master. Check `zig version`.

## 2. Documentation

1. [doc/ISA.md](../doc/ISA.md) says what the code does. A behavior change
   starts there, and Appendix B lists every departure from the sources.
2. Each document says only what is true now. What used to be true is in
   [doc/HISTORY.md](../doc/HISTORY.md).
3. Every README agrees with the options, formats, and error behavior of its
   tool.
4. The figures quoted in the documents (the cycle counts of the benchmark,
   the word counts, the timing) are those you measure in steps 3 to 5. The
   cycle counts are in `bench/README.md`, and the timing in
   `hdl/README.md` and [doc/MICROARCH.md](../doc/MICROARCH.md).
5. The diagrams match their sources: after an edit of a `.tex` in `doc/`, run
   `make diagrams` and commit both the `.tex` and the `.png`.
6. The slides match: `make pdfcheck`. After an edit of
   `doc/intro/nice_intro.tex`, run `make -C doc/intro pdf` and commit both.
7. American spelling, plain short sentences, the Oxford comma.

## 3. Quick checks

These are what CI runs, so a green CI run on the release commit is the same
evidence, but run them locally too. Do not edit `hdl/src` while they run.

1. Everything quick, in parallel:

       make test

2. The type checks, and the VHDL style check (`pip install vsg`):

       make typecheck
       make lint

3. Or all four of test, typecheck, lint, and pdfcheck at once:

       make all

Every part must pass. A bug fix or new rule has its test (CLAUDE.md,
"Conventions"). The 2004 example `.bin` files must be unchanged.

`release.py check` runs steps 3 to 5 in one go, and step 2.4 and the
diagram and slide checks of step 2, and writes the stamp. The sections below
say what it runs.

## 4. Formal checks

Run these alone, not next to other work, as some proofs take minutes. CI
pins older SymbiYosys and Yosys versions than a local install, so a proof
that passes on one and fails on the other is worth a look.

    make formal

## 5. Slow checks

These need GHDL and take hours. Run them with each core:

    make slow                 # CORE=pipeline, the default
    make slow CORE=multicycle

That is `hdl make programs` (the runtime and translator programs), `bench
make core` (the benchmark on the core), and `hdl make sweep` (one interrupt
per run). Every line must say `PASS`, and both cores must agree with
`niceemu`.

Then refresh the estimate against the core:

    make -C bench compare     # after make core

If a figure in the documents changed, go back to step 2.4.

## 6. CI

Push the release candidate and wait for every CI job (`assembler`,
`emulator`, `runtime`, `translator`, `doc`, `bench`, `hdl`, `formal`,
`intro`, and `release`) to pass on that exact commit.
`python3 release/release.py ci --wait` does it.

## 7. NiceMonMEGA65

NiceMonMEGA65 is the integration test of the core on real boards: a board
can differ from the simulation in timing, which no test here shows. Do this
after the steps above pass, from a clone with the submodule.

1. In NiceMonMEGA65, point the `nice_cpu` submodule at the commit to release:

       git -C nice_cpu fetch
       git -C nice_cpu checkout <commit>
       git submodule status

2. Follow the "After a submodule bump" steps of its
   [CLAUDE.md](https://github.com/MJoergen/NiceMonMEGA65/blob/main/CLAUDE.md):
   build the emulator, and re-read its table "Compared with the emulator".
   Anything that changed in the address map, a device, or the ports of the
   core (see "Interface changes" below) must be matched in `src/`.
3. Run its release checklist, at least steps 3 to 7: its simulation tests
   with both `NICE=pipeline` and `NICE=multi`, its formal checks, the
   bitstreams for the boards with timing met, and `make hwtest` on each
   board. Every check must pass, and the bitstream must be built from the
   commit that you tag here.
4. Check the timing against this repository's. `make -C hdl timing` here
   (`BOARD=mega65` or `nexys4ddr`, `FLOW=default` or `timing`) must give
   about what NiceMonMEGA65 gets in Vivado. A large difference means the
   figures in [doc/MICROARCH.md](../doc/MICROARCH.md) or the open items in
   [TODO.md](../TODO.md) are out of date.
5. If NiceMonMEGA65 needed a change, make it a commit there with the new
   submodule pointer, and do not release this repository until both pass.

### Interface changes

Tell NiceMonMEGA65 about anything that changes what an integrator sees, and
record it in the release notes:

- the ports of either core, or of `wb_dmux` and the devices;
- the I/O address map of [doc/SYSTEM.md](../doc/SYSTEM.md);
- `regs_o`, `retire_o`, `stats_o`, or the reset and interrupt behavior;
- the clock assumptions of the timer and the performance counters.

## 8. Release

1. Update the figures in the documents (step 2.4), and commit them. If this
   changes any VHDL or code, go back to step 3.
2. `git status` is clean, and CI is green on the commit to tag.
3. Run `release.py tag`. It refuses without a stamp for this commit and green
   CI, drafts the message with `release.py notes`, and asks before it tags and
   again before it pushes. By hand, tag it, and push the tag. NiceMonMEGA65 pins the submodule to this tag
   (its `git submodule status` shows `(RC01)`, for example), so the name
   follows the earlier tags. The tag message says what changed since the
   last release, in particular the Zig version, the effect on the benchmark
   cycles, and any interface change from the list above:

       git tag -a RCnn -m "..."
       git push origin RCnn

4. In NiceMonMEGA65, commit the new submodule pointer, tag it as its
   checklist says, and attach the bitstreams. Reference this tag in its tag
   message.
