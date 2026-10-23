#!/usr/bin/env python3
"""Tests of the parts of release.py that need no repository, tools, or network."""

import sys
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release  # noqa: E402

CYCLES = """\
bench.bin: 1697422 instructions, 2438761 cycles (estimate), CPI 1.437
  cycles above 1/instruction: 741664
  phase         instr    cycles    CPI   main extra cycles per instruction
  rng64         52768     83026  1.573   mpu 0.34
  total       1652811   2356816  1.426
hand.bin: 493964 instructions, 1260293 cycles (estimate), CPI 2.551
  total        491309   1252534  2.549
simple.bin: 733185 instructions, 1504993 cycles (estimate), CPI 2.053
  total        720284   1480786  2.056
"""

NOTES = """\
# Release notes

## RC06 (2026-11-01)

Six.

## RC05 (2026-10-26)

Five.

- A list.

## RC0 (2026-01-01)

Zero.
"""


def check(cond: bool, what: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {what}")


def test_figure_lines() -> None:
    f = release.figure_lines(CYCLES)
    check(sorted(f) == ["bench.bin", "hand.bin", "simple.bin"], "one entry per program")
    check(f["bench.bin"][0] == "bench.bin: 1697422 instructions, 2438761 cycles (estimate), CPI 1.437", "bench summary")
    check(f["bench.bin"][1] == "total 1652811 2356816 1.426", "bench total, spaces normalized")
    check(f["hand.bin"][1] == "total 491309 1252534 2.549", "hand total")
    check(f["simple.bin"][1] == "total 720284 1480786 2.056", "simple total")
    check(release.figure_lines("  rng64 1 2 1.0\nphase total 1 2\n") == {}, "phase rows are not totals")
    check("bench.bin" not in release.figure_lines(CYCLES.replace("bench.bin: ", "other: ")), "no bench summary")


def test_bench_totals() -> None:
    check(release.bench_totals(CYCLES) == ["2356816"], "the first total is the benchmark's")
    check(release.bench_totals("nothing") == [], "no total")


def test_next_tag() -> None:
    def tags(names: str) -> mock.Mock:
        return mock.Mock(return_value=names)

    with mock.patch.object(release, "git", tags("RC01\nRC02\nRW01\nRC10\nRC9\nv1")):
        check(release.release_tags() == ["RC01", "RC02", "RC9", "RC10"], "RCnn tags in numeric order")
        check(release.next_tag() == "RC11", "next after RC10")
    with mock.patch.object(release, "git", tags("RW01")):
        check(release.next_tag() == "RC01", "first tag")


def test_ci_status() -> None:
    import json

    expected = release.ci_jobs()
    check("programs" in expected and "formal" in expected, "the jobs are read from ci.yml")

    def jobs(**kw: tuple[str, str]) -> str:
        names = {n: ("completed", "success") for n in expected if n != "programs"}
        names["programs (pipeline)"] = ("completed", "success")
        names["programs (multicycle)"] = ("completed", "success")
        names.update(kw)
        return json.dumps({"jobs": [{"name": n, "status": s, "conclusion": c} for n, (s, c) in names.items()]})

    def state(run_list: str, *views: str) -> str:
        with mock.patch.object(release, "run", side_effect=[run_list, *views]):
            return release.ci_status("abc")[0]

    def runs(*events: str) -> str:
        return json.dumps([{"databaseId": i, "event": e} for i, e in enumerate(events, 1)])

    one = runs("push")
    check(state("[]") == "missing", "no run")
    check(state(one, jobs()) == "passed", "all jobs passed")
    check(state(one, jobs(formal=("completed", "failure"))) == "failed", "a job failed")
    check(state(one, jobs(formal=("completed", "skipped"))) == "failed", "a skipped job is not a success")
    check(state(one, jobs(hdl=("in_progress", ""))) == "pending", "a job is running")
    check(state(one, jobs(**{"programs (multicycle)": ("queued", "")})) == "pending", "a programs job is running")
    check(state(one, jobs(hdl=("in_progress", ""), formal=("completed", "failure"))) == "failed", "a failure counts at once")
    check(state(runs("pull_request")) == "missing", "only push runs count")
    check(state(runs("push", "push"), jobs(hdl=("completed", "cancelled")), jobs()) == "passed", "a rerun passes")
    check(state(runs("push", "push"), jobs(hdl=("completed", "cancelled")), jobs(hdl=("queued", ""))) == "pending", "a rerun waits")
    with mock.patch.object(release, "run", side_effect=[one, '{"jobs": []}']):
        check(release.ci_status("abc")[0] == "failed", "jobs missing from the run")
    only = json.dumps({"jobs": [{"name": "programs (pipeline)", "status": "completed", "conclusion": "success"}]})
    with mock.patch.object(release, "run", side_effect=[one, only]):
        check(release.ci_status("abc")[0] == "failed", "most jobs missing")


def test_notes_section() -> None:
    check(release.notes_section(NOTES, "RC05") == "RC05 (2026-10-26)\n\nFive.\n\n- A list.\n", "a middle section")
    check(release.notes_section(NOTES, "RC06") == "RC06 (2026-11-01)\n\nSix.\n", "the first section")
    check(release.notes_section(NOTES, "RC0") == "RC0 (2026-01-01)\n\nZero.\n", "the last section, not RC05")
    check(release.notes_section(NOTES, "RC07") is None, "no section")
    check(release.notes_section(NOTES, "RC5") is None, "RC5 is not RC05")


def test_stamp_covers() -> None:
    def git(*args: str, check: bool = True) -> str:
        if args[0] == "merge-base":
            return args[1] if args[1] in ("aaa", "bbb") else "other"
        return changed

    with mock.patch.object(release, "git", git):
        changed = "RELEASE_NOTES.md\nTODO.md"
        check(release.stamp_covers("aaa", "aaa"), "the same commit")
        check(release.stamp_covers("aaa", "bbb"), "only the notes and the TODO changed")
        check(not release.stamp_covers("zzz", "bbb"), "not an ancestor")
        changed = "RELEASE_NOTES.md\nhdl/src/pipeline.vhd"
        check(not release.stamp_covers("aaa", "bbb"), "code changed")
        changed = "README.md"
        check(not release.stamp_covers("aaa", "bbb"), "another document changed")


for t in (test_figure_lines, test_bench_totals, test_next_tag, test_ci_status, test_notes_section, test_stamp_covers):
    t()
print("release tests passed")
