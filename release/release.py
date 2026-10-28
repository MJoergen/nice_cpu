#!/usr/bin/env python3
"""The scripted parts of the release procedure of RELEASE.md.

    release.py preflight        step 1: tree, branch, toolchain, tools
    release.py check            steps 2.4 and 3 to 5: run the gates, write the stamp
                                (the timing budget is shown, not a gate)
    release.py figures          step 2.4: the benchmark figures in bench/README.md
    release.py ci [--wait]      step 6: every CI job passed on HEAD
    release.py notes            a draft of the section of RELEASE_NOTES.md
    release.py tag [NAME]       step 8: tag HEAD, if the stamp and CI allow it

Python 3 standard library only. The commands stop at the first failure and
exit with status 1.
"""

import argparse
import concurrent.futures
import datetime
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "release" / "build"
STAMP = BUILD / "stamp.json"

ZIG_VERSION = "0.17.0"
TAG_PATTERN = re.compile(r"^V(\d+)\.(\d+)$")
# The release candidates RC01 to RC06 came before V1.0.
OLD_TAG_PATTERN = re.compile(r"^RC(\d+)$")

CI_YML = ROOT / ".github" / "workflows" / "ci.yml"
NOTES_FILE = ROOT / "RELEASE_NOTES.md"

# The cores that make slow must have run on.
CORES = ["pipeline", "multicycle"]

# The files that may change between check and tag: they are no code.
STAMP_FREE = {"RELEASE_NOTES.md", "TODO.md"}

# The 2004 programs, whose .bin files are the original NICE.pm output.
ORIGINAL_BINS = ["assembler/test/count.bin", "assembler/test/print.bin", "assembler/test/replicate.bin"]

# The programs that must be on PATH, and the step that needs each.
TOOLS = {
    "git": "everything",
    "gh": "release.py ci",
    "make": "everything",
    "zig": "the emulator",
    "ghdl": "make test",
    "nvc": "make slow",
    "sby": "make formal",
    "yosys": "make formal",
    "vsg": "make lint, at the version of ci.yml",
    "pdflatex": "make diagrams, make pdf",
    "pdftoppm": "make diagrams",
}

# Where the benchmark figures are quoted, and what make -C bench cycles prints.
FIGURES_FILE = ROOT / "bench" / "README.md"


class Failure(Exception):
    pass


def run(args: list[str], cwd: Path = ROOT, check: bool = True) -> str:
    """The output of a command, which must succeed unless check is False."""
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise Failure(f"{' '.join(args)} failed:\n{p.stdout}{p.stderr}".rstrip())
    return p.stdout.strip()


def git(*args: str, check: bool = True) -> str:
    return run(["git", *args], check=check)


def head() -> str:
    return git("rev-parse", "HEAD")


def tree_is_clean() -> bool:
    return git("status", "--porcelain") == ""


def tag_key(name: str) -> Optional[tuple[int, int, int]]:
    """The order of a release tag: the RCnn tags before the Vmajor.minor
    ones. None for any other name."""
    if m := OLD_TAG_PATTERN.match(name):
        return (0, int(m[1]), 0)
    if m := TAG_PATTERN.match(name):
        return (1, int(m[1]), int(m[2]))
    return None


def release_tags() -> list[str]:
    """The tags named RCnn and Vmajor.minor, oldest first."""
    tags = [t for t in git("tag", "--list").split() if tag_key(t)]
    return sorted(tags, key=lambda t: tag_key(t) or (0, 0, 0))


def next_tag() -> str:
    """The next minor version. A new major version is named by hand."""
    tags = [t for t in release_tags() if TAG_PATTERN.match(t)]
    if not tags:
        return "V1.0"
    _, major, minor = tag_key(tags[-1]) or (0, 1, -1)
    return f"V{major}.{minor + 1}"


def say(ok: bool, text: str) -> bool:
    print(f"  {'ok  ' if ok else 'FAIL'} {text}")
    return ok


# ---------------------------------------------------------------- preflight


def check_preflight() -> bool:
    ok = True
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    ok &= say(branch == "main", f"branch is main (is {branch})")
    clean = tree_is_clean()
    ok &= say(clean, "working tree is clean")
    if not clean:
        print(git("status", "--short"))
    p = subprocess.run(["git", "fetch", "origin"], cwd=ROOT, capture_output=True, text=True)
    if say(p.returncode == 0, "git fetch origin"):
        local, remote = head(), git("rev-parse", "origin/main")
        ok &= say(local == remote, f"HEAD is origin/main ({local[:7]} against {remote[:7]})")
    else:
        ok = False
    if shutil.which("zig"):
        v = run(["zig", "version"])
        ok &= say(v == ZIG_VERSION, f"zig version is {ZIG_VERSION} (is {v})")
    for tool, why in TOOLS.items():
        ok &= say(shutil.which(tool) is not None, f"{tool} on PATH, for {why}")
    if shutil.which("vsg"):
        want = re.search(r"vsg==([\d.]+)", CI_YML.read_text())
        have = re.search(r"([\d.]+)\s*$", run(["vsg", "--version"]))
        if want and have:
            ok &= say(have.group(1) == want.group(1), f"vsg version is {want.group(1)}, as in ci.yml (is {have.group(1)})")
    if shutil.which("gh"):
        p = subprocess.run(["gh", "auth", "status"], cwd=ROOT, capture_output=True, text=True)
        ok &= say(p.returncode == 0, "gh is logged in")
    p = subprocess.run([sys.executable, "-m", "mypy", "--version"], capture_output=True, text=True)
    ok &= say(p.returncode == 0, "mypy installed, for make typecheck")
    print(f"  next tag: {next_tag()}")
    return ok


def cmd_preflight(_: argparse.Namespace) -> int:
    print("Preflight (RELEASE.md step 1)")
    return 0 if check_preflight() else 1


# ------------------------------------------------------------------ figures


def figure_lines(text: str) -> dict[str, tuple[str, str]]:
    """The summary line and the total row of each program in the output of
    make cycles, by program name (bench.bin, hand.bin, simple.bin)."""
    figures: dict[str, tuple[str, str]] = {}
    name, summary = "", ""
    for line in text.splitlines():
        s = " ".join(line.split())
        m = re.match(r"^(\w+\.bin): \d+ instructions, \d+ cycles \(estimate\)", s)
        if m:
            name, summary = m.group(1), s
        elif name and re.match(r"^total \d+ \d+ [\d.]+$", s):
            figures[name] = (summary, s)
            name = ""
    return figures


def cmd_figures(_: argparse.Namespace) -> int:
    print("Figures (RELEASE.md step 2.4)")
    out = run(["make", "--no-print-directory", "-C", "bench", "cycles"])
    measured = figure_lines(out)
    if "bench.bin" not in measured:
        raise Failure("make cycles printed no summary and total for bench.bin")
    readme = FIGURES_FILE.read_text()
    flat = {" ".join(line.split()) for line in readme.splitlines()}
    # The README quotes the bench.bin summary line and the bench total row.
    # The other programs are quoted in prose and tables, which are not checked.
    summary, total = measured["bench.bin"]
    ok = say(summary in flat, f"bench/README.md has '{summary}'")
    cycles = total.split()[2]
    ok &= say(cycles in readme, f"bench/README.md quotes {cycles} ({total})")
    return 0 if ok else 1


# -------------------------------------------------------------------- check


def read_stamp() -> Optional[dict[str, object]]:
    try:
        data = json.loads(STAMP.read_text())
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def make_step(name: str, args: list[str], log: Path) -> dict[str, object]:
    """Runs make with the output in log. A failure stops the release check."""
    print(f"  {name} ... ", end="", flush=True)
    t0 = time.time()
    with open(log, "w") as f:
        p = subprocess.run(args, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
    secs = time.time() - t0
    print(f"{'ok' if p.returncode == 0 else 'FAILED'} ({secs:.0f} s, {log.relative_to(ROOT)})")
    if p.returncode != 0:
        print("".join(log.read_text().splitlines(keepends=True)[-30:]))
        raise Failure(f"{name} failed")
    return {"name": name, "seconds": round(secs)}


def timing_budget(board: str = "mega65") -> dict[str, object]:
    """Runs make -C hdl timing and reads the budget it judged. Never fails
    the release: a miss, a Vivado error, or a skip is recorded. It prints
    nothing, as it runs beside make formal; show_timing shows the result."""
    out_dir = ROOT / "hdl" / "build" / "timing" / f"{board}-default-4"
    (out_dir / "budget.json").unlink(missing_ok=True)
    log = BUILD / "timing.log"
    with open(log, "w") as f:
        p = subprocess.run(["make", "-C", "hdl", "timing", f"BOARD={board}", "FLOW=default"],
                           cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
    try:
        result = json.loads((out_dir / "budget.json").read_text())
    except (OSError, ValueError):
        result = {"status": "error", "board": board}
    if p.returncode != 0:
        result["status"] = "error"
    return result  # type: ignore[no-any-return]


def show_timing(result: dict[str, object]) -> None:
    print(f"  timing (not a gate) ... {result['status']} (release/build/timing.log)")


def cmd_check(a: argparse.Namespace) -> int:
    print("Check (RELEASE.md steps 2.4 to 5)")
    if not tree_is_clean():
        print(git("status", "--short"))
        raise Failure("the working tree is not clean")
    sha = head()
    BUILD.mkdir(parents=True, exist_ok=True)
    STAMP.unlink(missing_ok=True)
    steps: list[dict[str, object]] = []

    def step(name: str, args: list[str]) -> None:
        steps.append(make_step(name, args, BUILD / (name.replace(" ", "_") + ".log")))

    tags = release_tags()
    if tags:
        changed = git("diff", "--name-only", tags[-1], "--", *ORIGINAL_BINS)
        if not say(changed == "", f"the 2004 .bin files are unchanged since {tags[-1]}"):
            raise Failure(f"changed: {changed}")

    step("make all", ["make", "all"])
    # The timing is shown, never a gate (RELEASE.md step 5, Timing). Vivado's
    # slack does not depend on the load, so it runs beside make formal.
    timing: dict[str, object] = {"status": "skipped"}
    with concurrent.futures.ThreadPoolExecutor(1) as pool:
        timed = None if a.skip_timing else pool.submit(timing_budget)
        if not a.skip_formal:
            step("make formal", ["make", "formal"])
        if timed is not None:
            timing = timed.result()
            show_timing(timing)
    if not a.skip_slow:
        # Both cores at once, in parallel, in nvc (Makefile, make slow).
        step("make slow", ["make", "slow", "CORES=" + " ".join(a.cores)])
        if "pipeline" in a.cores:
            step("bench compare", ["make", "-C", "bench", "compare"])
    # The slides need no step: make all ran pdfcheck, and the PDF holds its build date.
    step("diagrams", ["make", "diagrams"])
    if not tree_is_clean():
        print(git("status", "--short"))
        raise Failure("make diagrams changed a file, or a step edited the tree: commit it and start again")
    if cmd_figures(a) != 0:
        raise Failure("a figure in bench/README.md is out of date")

    if head() != sha:
        raise Failure("HEAD moved during the check")
    stamp = {
        "sha": sha,
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
        "cores": [] if a.skip_slow else sorted(a.cores),
        "formal": not a.skip_formal,
        "timing": timing,
        "steps": steps,
    }
    STAMP.write_text(json.dumps(stamp, indent=2) + "\n")
    print(f"Passed on {sha[:7]}; stamp in {STAMP.relative_to(ROOT)}")
    if timing["status"] != "met":
        print(f"WARNING: the timing budget is {timing['status']} (hdl/test/timing_budget.py); "
              "tag does not need it, but the release notes should say so.")
    if a.skip_slow or a.skip_formal or set(a.cores) < set(CORES):
        print("The stamp records the skipped steps, and tag refuses it unless --allow-partial is given.")
    return 0


# ----------------------------------------------------------------------- ci


def ci_jobs() -> list[str]:
    """The jobs of ci.yml: the keys under jobs:."""
    body = CI_YML.read_text().split("\njobs:\n", 1)[1]
    return re.findall(r"^  ([\w-]+):\s*$", body, re.M)


def run_state(jobs: list[dict[str, str]]) -> tuple[str, str]:
    """(state, text) of the jobs of one CI run. Every job of ci.yml must be
    there, including each of a matrix (programs (pipeline) and so on), and
    must have succeeded. A failure counts even while other jobs run."""
    names = [j["name"] for j in jobs]
    absent = [e for e in ci_jobs() if not any(n == e or n.startswith(e + " (") for n in names)]
    if absent:
        return "failed", f"jobs not in the run: {', '.join(absent)}"
    bad = [j["name"] for j in jobs if j["status"] == "completed" and j["conclusion"] != "success"]
    if bad:
        return "failed", f"jobs failed: {', '.join(bad)}"
    waiting = [j["name"] for j in jobs if j["status"] != "completed"]
    if waiting:
        return "pending", f"waiting for: {', '.join(waiting)}"
    return "passed", f"all {len(jobs)} jobs passed"


def ci_status(sha: str, repo: Optional[str] = None) -> tuple[str, str]:
    """(state, text) of the push runs of ci.yml on sha: state is one of
    missing, pending, failed, passed. One passed run is enough, as a run
    that was canceled or failed on a runner is followed by a rerun or by the
    run of a tag. Pending beats failed, as a run may still pass. repo is
    OWNER/NAME, for an origin that gh cannot find."""
    gh = ["gh", "-R", repo] if repo else ["gh"]
    out = run([*gh, "run", "list", "--workflow", "ci.yml", "--commit", sha, "--limit", "50",
               "--json", "databaseId,event"])
    runs = [r for r in json.loads(out) if r["event"] == "push"]
    if not runs:
        return "missing", "no CI run for this commit: push it"
    results = []
    for r in runs:
        jobs = json.loads(run([*gh, "run", "view", str(r["databaseId"]), "--json", "jobs"]))["jobs"]
        results.append(run_state(jobs))
    for state in ("passed", "pending", "failed"):
        for st, text in results:
            if st == state:
                return st, text
    raise Failure("unreachable")


def cmd_ci(a: argparse.Namespace) -> int:
    print("CI (RELEASE.md step 6)")
    sha = head()
    if git("rev-parse", "origin/main") != sha:
        raise Failure("HEAD is not origin/main: push the commit first")
    while True:
        state, text = ci_status(sha, a.repo)
        if state == "pending" and a.wait:
            print(f"  {text}")
            time.sleep(60)
            continue
        say(state == "passed", f"{sha[:7]}: {text}")
        return 0 if state == "passed" else 1


# -------------------------------------------------------------------- notes


def bench_totals(text: str) -> list[str]:
    return re.findall(r"^\s*total\s+\d+\s+(\d+)\s+[\d.]+\s*$", text, re.M)[:1]


def draft_notes() -> str:
    """A draft of the section of RELEASE_NOTES.md, from the commits since
    the last tag. The text is to be written by hand: the subjects are not
    the notes."""
    tags = release_tags()
    last = tags[-1] if tags else None
    rng = f"{last}..HEAD" if last else "HEAD"
    log = git("log", "--reverse", "--format=- %s", rng)
    out = [f"## {next_tag()} ({datetime.date.today().isoformat()})", ""]
    out.append(f"Zig {run(['zig', 'version'], check=False) or ZIG_VERSION}")
    new = bench_totals(FIGURES_FILE.read_text())
    if last:
        old = bench_totals(git("show", f"{last}:bench/README.md"))
        if old and new:
            o, n = int(old[0]), int(new[0])
            out.append(f"Benchmark estimate: {n} cycles, {n - o:+d} against {last} ({o}).")
        out.append("")
        ports = git("diff", "--stat", last, "--", "hdl/src", "doc/SYSTEM.md", check=False)
        out.append("Interface changes (check by hand against RELEASE.md, Interface changes):")
        out.append(ports if ports else "  none in hdl/src or doc/SYSTEM.md")
    out.append("")
    out.append(f"Commits since {last}:" if last else "Commits:")
    out.append(log)
    return "\n".join(out) + "\n"


def cmd_notes(_: argparse.Namespace) -> int:
    print(draft_notes(), end="")
    return 0


def notes_section(text: str, name: str) -> Optional[str]:
    """The section of RELEASE_NOTES.md of the tag name, from its heading to
    the next, without the leading ##, or None."""
    m = re.search(rf"^## ({re.escape(name)}\b.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1).strip() + "\n" if m else None


# ---------------------------------------------------------------------- tag


def confirm(question: str) -> bool:
    return input(f"{question} [y/N] ").strip().lower() == "y"


def stamp_covers(stamp_sha: str, sha: str) -> bool:
    """Whether the stamp of stamp_sha holds for sha: the same commit, or a
    descendant that changed only the files of STAMP_FREE."""
    if stamp_sha == sha:
        return True
    if git("merge-base", stamp_sha, sha, check=False) != stamp_sha:
        return False
    return all(f in STAMP_FREE for f in git("diff", "--name-only", stamp_sha, sha).split())


def cmd_tag(a: argparse.Namespace) -> int:
    print("Tag (RELEASE.md step 8)")
    name = a.name or next_tag()
    if not TAG_PATTERN.match(name):
        raise Failure(f"{name} is not a version Vmajor.minor, such as V1.0")
    tags = release_tags()
    if tags and (tag_key(name) or (0, 0, 0)) <= (tag_key(tags[-1]) or (0, 0, 0)):
        raise Failure(f"{name} does not come after the last tag, {tags[-1]}")
    if name in git("tag", "--list").split():
        raise Failure(f"tag {name} exists")
    if not tree_is_clean():
        raise Failure("the working tree is not clean")
    sha = head()
    stamp = read_stamp()
    if stamp is None or not stamp_covers(str(stamp.get("sha")), sha):
        raise Failure(f"no release.py check stamp for HEAD: run release.py check "
                      f"(only {', '.join(sorted(STAMP_FREE))} may change after it)")
    cores = stamp.get("cores")
    full = bool(stamp.get("formal")) and isinstance(cores, list) and set(CORES) <= set(cores)
    if not full and not a.allow_partial:
        raise Failure("the stamp skipped make formal or make slow on a core: "
                      "run release.py check in full, or pass --allow-partial")
    message = notes_section(NOTES_FILE.read_text(), name)
    if message is None:
        raise Failure(f"RELEASE_NOTES.md has no section for {name}: write it (release.py notes drafts it) and commit it")
    state, text = ci_status(sha, a.repo)
    if state != "passed":
        raise Failure(f"CI: {text}")
    print(f"  stamp and CI are good for {sha[:7]}")
    timing = stamp.get("timing")
    status = timing.get("status") if isinstance(timing, dict) else None
    print(f"  timing budget: {status or 'not in the stamp'}" + ("" if status == "met" else " (no gate)"))
    print(f"\nTag {name} on {sha[:7]}, with the section of RELEASE_NOTES.md as its message:\n\n{message}")
    if not confirm(f"Create tag {name}?"):
        return 1
    git("tag", "-a", "--cleanup=whitespace", name, "-m", message)
    print(f"  created {name}")
    if confirm(f"Push {name} to origin? (publishes it)"):
        git("push", "origin", name)
        print(f"  pushed {name}")
    else:
        print(f"  not pushed: git push origin {name}")
    print("Next, when you like: the NiceMonMEGA65 bump (RELEASE.md step 7). It does not gate this release.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("preflight").set_defaults(fn=cmd_preflight)
    c = sub.add_parser("check")
    c.add_argument("--cores", nargs="+", default=CORES, choices=CORES, help="cores for make slow")
    c.add_argument("--skip-slow", action="store_true", help="skip make slow (a partial stamp)")
    c.add_argument("--skip-formal", action="store_true", help="skip make formal (a partial stamp)")
    c.add_argument("--skip-timing", action="store_true", help="skip make timing, which is no gate (10 minutes)")
    c.set_defaults(fn=cmd_check)
    sub.add_parser("figures").set_defaults(fn=cmd_figures)
    c = sub.add_parser("ci")
    c.add_argument("--wait", action="store_true", help="poll until the jobs finish")
    c.add_argument("--repo", metavar="OWNER/NAME", help="the GitHub repository, if origin is not it")
    c.set_defaults(fn=cmd_ci)
    sub.add_parser("notes").set_defaults(fn=cmd_notes)
    c = sub.add_parser("tag")
    c.add_argument("name", nargs="?", help="default: the next minor version, such as V1.1")
    c.add_argument("--allow-partial", action="store_true", help="accept a stamp that skipped steps")
    c.add_argument("--repo", metavar="OWNER/NAME", help="the GitHub repository, if origin is not it")
    c.set_defaults(fn=cmd_tag)
    a = ap.parse_args()
    try:
        return int(a.fn(a))
    except Failure as e:
        print(f"release.py: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
