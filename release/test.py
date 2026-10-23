#!/usr/bin/env python3
"""Tests of the parts of release.py that need no repository, tools, or network."""

import sys
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release  # noqa: E402

CYCLES = """\
bench.bin: 1726106 instructions, 2467770 cycles (estimate), CPI 1.430
  cycles above 1/instruction: 741664
  phase         instr    cycles    CPI   main extra cycles per instruction
  rng64         52768     83026  1.573   mpu 0.34
  total       1681080   2384296  1.418
hand.bin: 494272 instructions, 1393057 cycles (estimate), CPI 2.818
  total        491617   1384800  2.817
"""


def check(cond: bool, what: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL: {what}")


def test_figure_lines() -> None:
    lines = release.figure_lines(CYCLES)
    check(len(lines) == 4, "four figure lines")
    check(lines[0] == "bench.bin: 1726106 instructions, 2467770 cycles (estimate), CPI 1.430", "bench summary")
    check(lines[1] == "total 1681080 2384296 1.418", "bench total, spaces normalized")
    check(lines[3] == "total 491617 1384800 2.817", "hand total")
    check(release.figure_lines("  rng64 1 2 1.0\nphase total 1 2\n") == [], "phase rows are not totals")


def test_bench_totals() -> None:
    check(release.bench_totals(CYCLES) == ["2384296"], "the first total is the benchmark's")
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
    def jobs(**kw: tuple[str, str]) -> str:
        import json

        names = {n: ("completed", "success") for n in release.CI_JOBS}
        names.update(kw)
        return json.dumps({"jobs": [{"name": n, "status": s, "conclusion": c} for n, (s, c) in names.items()]})

    def state(run_list: str, view: str) -> str:
        with mock.patch.object(release, "run", side_effect=[run_list, view]):
            return release.ci_status("abc")[0]

    one = '[{"databaseId": 1, "status": "completed", "conclusion": "success", "event": "push"}]'
    check(state("[]", "") == "missing", "no run")
    check(state(one, jobs()) == "passed", "all jobs passed")
    check(state(one, jobs(formal=("completed", "failure"))) == "failed", "a job failed")
    check(state(one, jobs(hdl=("in_progress", ""))) == "pending", "a job is running")
    pr = '[{"databaseId": 1, "status": "completed", "conclusion": "success", "event": "pull_request"}]'
    check(state(pr, "") == "missing", "only push runs count")
    with mock.patch.object(release, "run", side_effect=[one, '{"jobs": []}']):
        check(release.ci_status("abc")[0] == "failed", "jobs missing from the run")


for t in (test_figure_lines, test_bench_totals, test_next_tag, test_ci_status):
    t()
print("release tests passed")
