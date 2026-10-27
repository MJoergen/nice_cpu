# Release checklist

The steps to take before a release, in order. Each step is cheaper than the
ones after it, so a problem is found as early as possible. Do not go on to
the next step while one fails.

A release needs a clean working tree on `main`. The slow checks come last
because they take the longest.

This repository is FPGA-agnostic and has no bitstream, and it does not
depend on any board repository. It can be released at any time. NiceMonMEGA65
carries the core to the boards as a git submodule, and it is the example
design that shows the core meets 100 MHz on the MEGA65. That is an
achievement to keep, not a gate: step 7 happens after the tag, and a miss
only shows (the badge, and the release notes of the next tag).

## Version names

A release here is named `Vmajor.minor`: `V1.0`, `V1.1`, and so on, with a
new major version when a change asks for it. The release candidates
`RC01` to `RC06` came before `V1.0`.

Every release here gets a release of NiceMonMEGA65 with the same name,
which moves its `nice_cpu` submodule to the tag. A release of
NiceMonMEGA65 that leaves the submodule alone adds a third number:

| NiceMonMEGA65 | `nice_cpu` | What it is |
|---|---|---|
| `V1.0` | `V1.0` | the submodule moved to `V1.0` |
| `V1.0.1` | `V1.0` | a change in NiceMonMEGA65 only |
| `V1.0.2` | `V1.0` | another one |
| `V1.1` | `V1.1` | the submodule moved to `V1.1` |

So the first two numbers of a NiceMonMEGA65 tag always name the
`nice_cpu` tag it pins. NiceMonMEGA65 pins only tags of this repository,
never a commit between them. If it needs a fix from here, that is a
release here first.

The mechanical parts are scripted by [release.py](README.md),
which each step names. `make release-check` runs steps 2.4 to 5, and
leaves a stamp that `release.py tag` requires. The rest is by hand.

## 1. Prepare

Run `python3 release/release.py preflight`. It checks items 1 and 3 and the
tools. Item 2 is by hand.

1. `git status` is clean, and the branch is `main`, up to date with `origin`.
2. No open [issue](https://github.com/MJoergen/nice_cpu/issues) blocks the release, or the release notes
   say why it is acceptable. The milestone of the release has no open
   issue left: close it, or move what remains to the next milestone.
3. The toolchain is the one in [README.md](../README.md): Zig 0.17.0, not the
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
8. [RELEASE_NOTES.md](../RELEASE_NOTES.md) has a section for the new tag,
   with the date, as CLAUDE.md requires. `release.py notes` drafts its
   Zig version, benchmark cycles, interface changes, and commit subjects;
   the text is yours. It is the message of the tag. It may be committed
   after `release.py check`: `tag` accepts commits since the stamp that
   change only RELEASE_NOTES.md and TODO.md.

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
diagram check of step 2, and writes the stamp. The slides are checked by
`make all`. The sections below say what it runs.

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
make core` (the benchmark on the core), `bench make core-dhry` (Dhrystone on
the core), and `hdl make strides` (the interrupt sweeps with strides 17,
31, and 64). Every line must say `PASS`, and both cores must agree with
`niceemu`. `hdl make sweep`, with one interrupt per run, takes hours and is
not part of the release; it is run after a change to the interrupt path
(CLAUDE.md, Conventions).

Then refresh the estimate against the core:

    make -C bench compare     # after make core

If a figure in the documents changed, go back to step 2.4.

### Timing

`release.py check` also runs `make -C hdl timing` (`BOARD=mega65`, about 3
minutes) and compares the slacks with the budget in
[hdl/test/timing_budget.py](../hdl/test/timing_budget.py): the core alone must
meet the 10 ns clock, and the paths to and from the core's ports must leave
the system around it 1.5 ns. This is **not a gate**. A miss prints a warning
and goes into the stamp, and `tag` shows it. If it missed, say so in the
release notes, with the cause, or the commit to blame. The out-of-context
figures are a proxy: the memory logic of a real system takes some of the
time left, so the budget for the ports is a margin, not a promise. Skip the
run with `--skip-timing`.

A change to `hdl/src` that touches the paths of the groups in
`timing_groups.rpt` needs a `make timing` before and after it, with both
figures in the commit message, so that a feature does not quietly take the
100 MHz.

## 6. CI

Push the release candidate and wait for every job of
[ci.yml](../.github/workflows/ci.yml) to pass on that exact commit. That
includes the `programs` jobs, which take hours, three shards for each core.
Cut no tag before they are done.
`python3 release/release.py ci --wait` does it. If `origin` is not on
GitHub, add `--repo OWNER/NAME`.

## 7. NiceMonMEGA65 (after the tag, not a gate)

NiceMonMEGA65 is the example design and the real-world test of the core: a
board can differ from the simulation in timing, which no test here shows.
It depends on this repository, never the other way. Do this after the tag,
from a clone with the submodule, or later, at your pace.

1. In NiceMonMEGA65, point the `nice_cpu` submodule at the tag:

       git -C nice_cpu fetch
       git -C nice_cpu checkout <tag>
       git submodule status

2. Follow the "After a submodule bump" steps of its
   [CLAUDE.md](https://github.com/MJoergen/NiceMonMEGA65/blob/main/CLAUDE.md),
   and its own release checklist, and tag it with the same name as the tag here
   (Version names). Anything that changed in the address map, a
   device, or the ports of the core (see "Interface changes" below) must be
   matched in `src/` there.
3. Its bump script writes the result for the tag (the timing in the system,
   the date, and the tag) to the file that the badge in
   [README.md](../README.md) reads. Until then the badge still shows the
   tag before. If the timing was missed, the badge shows it, and the cause
   is an [issue](https://github.com/MJoergen/nice_cpu/issues) here.
4. Compare its timing with `make -C hdl timing` here (`BOARD=mega65`,
   `FLOW=default` or `timing`). A large difference means the budget in
   `timing_budget.py`, the figures in
   [doc/MICROARCH.md](../doc/MICROARCH.md), or the open
   [issues](https://github.com/MJoergen/nice_cpu/issues) are out of date.

If NiceMonMEGA65 needs a change to follow an interface change, it is a
commit there. A release here never waits for it.

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
3. Run `release.py tag`. It refuses without a stamp for this commit that
   covers both cores, formal, and the slow checks, without a section for the
   tag in [RELEASE_NOTES.md](../RELEASE_NOTES.md), and without green CI. It
   shows the section, asks before it makes an annotated tag with the section
   as its message, and asks again before it pushes. NiceMonMEGA65 pins the
   submodule to this tag (its `git submodule status` shows `(V1.0)`, for
   example), and its own tag has the same name (Version names). `tag`
   takes the next minor version unless given a name, and refuses a name
   that is not `Vmajor.minor` or does not come after the last tag. The section says what
   changed since the last release, in particular the Zig version, the effect
   on the benchmark cycles, and any interface change from the list above.
   By hand:

       git tag -a --cleanup=whitespace V1.0 -m "<the section>"
       git push origin V1.0

4. Then step 7, whenever you like. Reference this tag in the tag message
   of NiceMonMEGA65.
