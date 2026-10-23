# release

`release.py` scripts the mechanical parts of [RELEASE.md](RELEASE.md).
Python 3, standard library only, `mypy --strict` clean. The judgment calls
stay with you: whether the open items of [TODO.md](../TODO.md) block a
release, whether the documents still tell the truth, the boards, and the
NiceMonMEGA65 steps.

    python3 release/release.py preflight      # step 1
    python3 release/release.py check          # steps 2.4 and 3 to 5; make release-check
    python3 release/release.py figures        # step 2.4
    python3 release/release.py ci [--wait]    # step 6
    python3 release/release.py notes          # a draft of the tag message
    python3 release/release.py tag [NAME]     # step 8

Each command stops at the first failure and exits with status 1.

| Command | What it does |
|---|---|
| `preflight` | The branch is `main`, the tree is clean, `HEAD` is `origin/main` after a fetch, `zig version` is 0.15.2, the tools are on `PATH`, `gh` is logged in. Prints the next `RCnn`. |
| `check` | Needs a clean tree. Checks that the three 2004 `.bin` files are unchanged since the last tag, then runs `make all`, `make formal`, `make slow` for each core (`--cores`, default both), `make -C bench compare`, `make diagrams`, and `make -C doc/intro pdf`, and checks that the last two left the tree clean. Then runs `figures`. The log of each step is in `release/build/`. On success it writes `release/build/stamp.json` with the commit, the time, and the steps. `--skip-slow` and `--skip-formal` skip steps, and mark the stamp partial. |
| `figures` | Runs `make -C bench cycles`, and checks that [bench/README.md](../bench/README.md) quotes the same summary line and totals. |
| `ci` | Finds the push run of `ci.yml` on `HEAD`, and checks that every job passed. `--wait` polls until the jobs finish. |
| `notes` | Prints a draft of the tag message: the Zig version, the benchmark cycles against the last tag, the changes to `hdl/src` and `doc/SYSTEM.md`, and the commit subjects since the last tag. |
| `tag` | Refuses unless the tree is clean, the stamp is for `HEAD` and not partial (`--allow-partial` accepts a partial one), and CI passed. Opens the draft of `notes` in `$EDITOR`, asks, creates an annotated tag (the next `RCnn` unless given), and asks again before pushing it. |

The stamp is what makes "do not go on while one fails" hold: any new commit
makes it stale, and `tag` will not use it. `release/build/` is not committed.

`make test` and `make typecheck` in this directory test the parts of
`release.py` that need no repository, tools, or network.
