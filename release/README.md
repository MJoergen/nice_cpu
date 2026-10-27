# release

`release.py` scripts the mechanical parts of [RELEASE.md](RELEASE.md).
Python 3, standard library only, `mypy --strict` clean. The judgment calls
stay with you: whether the open items of [TODO.md](../TODO.md) block a
release, whether the documents still tell the truth, and the NiceMonMEGA65 step,
which follows the tag and gates nothing.

    python3 release/release.py preflight      # step 1
    python3 release/release.py check          # steps 2.4 to 5; make release-check
    python3 release/release.py figures        # step 2.4
    python3 release/release.py ci [--wait] [--repo OWNER/NAME]    # step 6
    python3 release/release.py notes          # a draft of the section of RELEASE_NOTES.md
    python3 release/release.py tag [NAME] [--allow-partial] [--repo OWNER/NAME]    # step 8

Each command stops at the first failure and exits with status 1.

| Command | What it does |
|---|---|
| `preflight` | The branch is `main`, the tree is clean, `HEAD` is `origin/main` after a fetch, `zig version` is 0.17.0, the tools are on `PATH`, `gh` is logged in. Prints the next `RCnn`. |
| `check` | Needs a clean tree. Checks that the three 2004 `.bin` files are unchanged since the last tag, then runs `make all`, `make formal`, `make slow` for each core (`--cores`, default both), `make -C bench compare`, and `make diagrams`, and checks that the tree is still clean. `make all` has run `pdfcheck`, so the slides need no step. Then runs `figures`. Before the diagrams it runs `make -C hdl timing` for the MEGA65 and judges it against the budget in `hdl/test/timing_budget.py`. That step is no gate: a miss or a Vivado error is shown and recorded, and `tag` still works. The log of each step is in `release/build/`. On success it writes `release/build/stamp.json` with the commit, the time, the timing result, and the steps. `--skip-slow` and `--skip-formal` skip steps, and `--cores` runs fewer cores; each marks the stamp partial. `--skip-timing` skips the timing and does not. |
| `figures` | Runs `make -C bench cycles`, and checks that [bench/README.md](../bench/README.md) quotes the summary line and the total of `bench.bin`. The other programs are not checked. |
| `ci` | Finds the push runs of `ci.yml` on `HEAD`, and checks that every job of the file, each `programs` job among them, succeeded in one of them. A failed job fails the check at once. `--wait` polls until the jobs finish. `--repo` names the GitHub repository if `origin` is not it. |
| `notes` | Prints a draft of the section of [RELEASE_NOTES.md](../RELEASE_NOTES.md) for the next tag: the Zig version, the benchmark cycles against the last tag, the changes to `hdl/src` and `doc/SYSTEM.md`, and the commit subjects since the last tag. |
| `tag` | Refuses unless the tree is clean, the stamp is for `HEAD` and not partial (`--allow-partial` accepts a partial one), RELEASE_NOTES.md has a section for the tag, and CI passed. Shows the section, asks, creates an annotated tag (the next `RCnn` unless given) with the section as its message, and asks again before pushing it. |

The stamp is what makes "do not go on while one fails" hold: a new commit
makes it stale, and `tag` will not use it, unless the commits since the stamp changed
only RELEASE_NOTES.md and TODO.md. `release/build/` is not committed.

`make test` and `make typecheck` in this directory test the parts of
`release.py` that need no repository, tools, or network.
