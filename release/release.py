#!/usr/bin/env python3
"""The scripted parts of the release procedure of RELEASE.md.

    release.py preflight        step 1: tree, branch, toolchain, tools
    release.py check            steps 2.4 and 3 to 5: run the gates, write the stamp
    release.py figures          step 2.4: the benchmark figures in bench/README.md
    release.py ci [--wait]      step 6: every CI job passed on HEAD
    release.py notes            a draft of the tag message
    release.py tag [NAME]       step 8: tag HEAD, if the stamp and CI allow it

Python 3 standard library only. The commands stop at the first failure and
exit with status 1.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "release" / "build"
STAMP = BUILD / "stamp.json"

ZIG_VERSION = "0.15.2"
TAG_PATTERN = re.compile(r"^RC(\d+)$")

# The jobs of .github/workflows/ci.yml.
CI_JOBS = ["assembler", "emulator", "runtime", "translator", "doc", "bench", "hdl", "formal", "intro", "release"]

# The 2004 programs, whose .bin files are the original NICE.pm output.
ORIGINAL_BINS = ["assembler/test/count.bin", "assembler/test/print.bin", "assembler/test/replicate.bin"]

# The programs that must be on PATH, and the step that needs each.
TOOLS = {
    "git": "everything",
    "gh": "release.py ci",
    "make": "everything",
    "zig": "the emulator",
    "ghdl": "make test, make slow",
    "sby": "make formal",
    "yosys": "make formal",
    "vsg": "make lint",
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


def release_tags() -> list[str]:
    """The tags named RCnn, oldest first."""
    tags = [t for t in git("tag", "--list").split() if TAG_PATTERN.match(t)]
    return sorted(tags, key=lambda t: int(t[2:]))


def next_tag() -> str:
    tags = release_tags()
    n = int(tags[-1][2:]) + 1 if tags else 1
    return f"RC{n:02d}"


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


def figure_lines(text: str) -> list[str]:
    """The lines of make cycles that the bench README quotes: the summary
    of each program and its total row."""
    lines = []
    for line in text.splitlines():
        s = " ".join(line.split())
        if re.match(r"^\w+\.bin: \d+ instructions, \d+ cycles \(estimate\)", s):
            lines.append(s)
        elif re.match(r"^total \d+ \d+ [\d.]+$", s):
            lines.append(s)
    return lines


def cmd_figures(_: argparse.Namespace) -> int:
    print("Figures (RELEASE.md step 2.4)")
    out = run(["make", "--no-print-directory", "-C", "bench", "cycles"])
    measured = figure_lines(out)
    if len(measured) != 4:
        raise Failure(f"expected 4 figure lines from make cycles, got {len(measured)}")
    readme = FIGURES_FILE.read_text()
    flat = {" ".join(line.split()) for line in readme.splitlines()}
    # The README quotes the bench.bin summary line and the bench total row;
    # the hand total is quoted in prose, as the cycles of a sentence.
    ok = True
    for line in measured:
        if line.startswith("hand.bin:"):
            continue
        if line.startswith("total"):
            cycles = line.split()[2]
            ok &= say(cycles in readme, f"bench/README.md quotes {cycles} ({line})")
        else:
            ok &= say(line in flat, f"bench/README.md has '{line}'")
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


def cmd_check(a: argparse.Namespace) -> int:
    print("Check (RELEASE.md steps 2.4 and 3 to 5)")
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
    if not a.skip_formal:
        step("make formal", ["make", "formal"])
    if not a.skip_slow:
        for core in a.cores:
            step(f"make slow {core}", ["make", "slow", f"CORE={core}"])
            if core == "pipeline":
                step("bench compare", ["make", "-C", "bench", "compare"])
    step("diagrams", ["make", "diagrams"])
    step("slides", ["make", "-C", "doc/intro", "pdf"])
    if not tree_is_clean():
        print(git("status", "--short"))
        raise Failure("make diagrams or make pdf changed a file, or a step edited the tree: commit it and start again")
    if cmd_figures(a) != 0:
        raise Failure("a figure in bench/README.md is out of date")

    if head() != sha:
        raise Failure("HEAD moved during the check")
    stamp = {
        "sha": sha,
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
        "cores": [] if a.skip_slow else a.cores,
        "formal": not a.skip_formal,
        "slow": not a.skip_slow,
        "steps": steps,
    }
    STAMP.write_text(json.dumps(stamp, indent=2) + "\n")
    print(f"Passed on {sha[:7]}; stamp in {STAMP.relative_to(ROOT)}")
    if a.skip_slow or a.skip_formal:
        print("The stamp records the skipped steps, and tag refuses it unless --allow-partial is given.")
    return 0


# ----------------------------------------------------------------------- ci


def ci_status(sha: str) -> tuple[str, str]:
    """(state, text) of the push run of ci.yml on sha: state is one of
    missing, pending, failed, passed."""
    out = run(["gh", "run", "list", "--workflow", "ci.yml", "--commit", sha,
               "--json", "databaseId,status,conclusion,event"])
    runs = [r for r in json.loads(out) if r["event"] == "push"]
    if not runs:
        return "missing", "no CI run for this commit: push it"
    r = runs[0]
    jobs = json.loads(run(["gh", "run", "view", str(r["databaseId"]), "--json", "jobs"]))["jobs"]
    by_name = {j["name"]: j for j in jobs}
    missing = [n for n in CI_JOBS if n not in by_name]
    if missing:
        return "failed", f"jobs not in the run: {', '.join(missing)}"
    bad = [n for n in CI_JOBS if by_name[n]["conclusion"] not in (None, "", "success")]
    if bad:
        return "failed", f"jobs failed: {', '.join(bad)}"
    if any(by_name[n]["status"] != "completed" for n in CI_JOBS):
        waiting = [n for n in CI_JOBS if by_name[n]["status"] != "completed"]
        return "pending", f"waiting for: {', '.join(waiting)}"
    return "passed", f"all {len(CI_JOBS)} jobs passed"


def cmd_ci(a: argparse.Namespace) -> int:
    print("CI (RELEASE.md step 6)")
    sha = head()
    if git("rev-parse", "origin/main") != sha:
        raise Failure("HEAD is not origin/main: push the commit first")
    while True:
        state, text = ci_status(sha)
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
    tags = release_tags()
    last = tags[-1] if tags else None
    rng = f"{last}..HEAD" if last else "HEAD"
    log = git("log", "--reverse", "--format=- %s", rng)
    out = [f"Zig {run(['zig', 'version'], check=False) or ZIG_VERSION}", ""]
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
    out.append(f"Since {last}:" if last else "Changes:")
    out.append(log)
    return "\n".join(out) + "\n"


def cmd_notes(_: argparse.Namespace) -> int:
    print(draft_notes(), end="")
    return 0


# ---------------------------------------------------------------------- tag


def edit(text: str) -> str:
    with tempfile.NamedTemporaryFile("w+", suffix=".txt", delete=False) as f:
        f.write(text)
        path = f.name
    subprocess.run([os.environ.get("EDITOR", "vi"), path], check=True)
    result = Path(path).read_text()
    os.unlink(path)
    return "\n".join(line for line in result.splitlines() if not line.startswith("#")).strip() + "\n"


def confirm(question: str) -> bool:
    return input(f"{question} [y/N] ").strip().lower() == "y"


def cmd_tag(a: argparse.Namespace) -> int:
    print("Tag (RELEASE.md step 8)")
    name = a.name or next_tag()
    if not TAG_PATTERN.match(name):
        raise Failure(f"{name} does not follow the RCnn pattern of the earlier tags")
    if name in git("tag", "--list").split():
        raise Failure(f"tag {name} exists")
    if not tree_is_clean():
        raise Failure("the working tree is not clean")
    sha = head()
    stamp = read_stamp()
    if stamp is None or stamp.get("sha") != sha:
        raise Failure("no release.py check stamp for HEAD: run release.py check")
    if not (stamp.get("slow") and stamp.get("formal")) and not a.allow_partial:
        raise Failure("the stamp skipped steps: run release.py check in full, or pass --allow-partial")
    state, text = ci_status(sha)
    if state != "passed":
        raise Failure(f"CI: {text}")
    print(f"  stamp and CI are good for {sha[:7]}")
    message = edit(draft_notes() + "\n# The tag message. Lines starting with # are removed.\n"
                   "# Say what changed, in particular the Zig version, the benchmark cycles,\n"
                   "# and any interface change.\n")
    if not message.strip():
        raise Failure("empty tag message")
    print(f"\nTag {name} on {sha[:7]}:\n\n{message}")
    if not confirm(f"Create tag {name}?"):
        return 1
    git("tag", "-a", name, "-m", message)
    print(f"  created {name}")
    if confirm(f"Push {name} to origin? (publishes it)"):
        git("push", "origin", name)
        print(f"  pushed {name}")
    else:
        print(f"  not pushed: git push origin {name}")
    print("Next: the NiceMonMEGA65 submodule pointer and tag (RELEASE.md step 8.4).")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("preflight").set_defaults(fn=cmd_preflight)
    c = sub.add_parser("check")
    c.add_argument("--cores", nargs="+", default=["pipeline", "multicycle"], help="cores for make slow")
    c.add_argument("--skip-slow", action="store_true", help="skip make slow (a partial stamp)")
    c.add_argument("--skip-formal", action="store_true", help="skip make formal (a partial stamp)")
    c.set_defaults(fn=cmd_check)
    sub.add_parser("figures").set_defaults(fn=cmd_figures)
    c = sub.add_parser("ci")
    c.add_argument("--wait", action="store_true", help="poll until the jobs finish")
    c.set_defaults(fn=cmd_ci)
    sub.add_parser("notes").set_defaults(fn=cmd_notes)
    c = sub.add_parser("tag")
    c.add_argument("name", nargs="?", help="default: the next RCnn")
    c.add_argument("--allow-partial", action="store_true", help="accept a stamp that skipped steps")
    c.set_defaults(fn=cmd_tag)
    a = ap.parse_args()
    try:
        return int(a.fn(a))
    except Failure as e:
        print(f"release.py: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
