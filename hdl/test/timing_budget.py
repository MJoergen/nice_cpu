#!/usr/bin/env python3
"""Compares the reports of "make timing" with the budget of the board.

    timing_budget.py DIR BOARD PERIOD    judge the reports in DIR
    timing_budget.py --test              the self-test of make test

The budget is the least slack at a 10 ns clock, in ns, of the worst
register-to-register path (the core alone) and of the worst path from an
input or to an output (the time left to the system around the core). The
second is less than the first needs, since a system adds to it: the data
bus decode and the block RAMs of NiceMonMEGA65 take most of it.

A miss is a warning, never a failure: it prints "MISSED" and exits 0. DIR
gets budget.json, which release/release.py puts in its stamp. A board or
period without a budget is "none".
"""

import contextlib
import io
import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Optional

# board: (period in ns, least register-to-register slack, least port slack).
# The MEGA65 runs between 2.2 and 3.0 ns on the ports, so 1.5 ns leaves for a
# few tenths of placement noise and one more LUT level.
BUDGET: dict[str, tuple[float, float, float]] = {
    "mega65": (10.0, 0.0, 1.5),
}

SLACK = re.compile(r"^Slack \((?:MET|VIOLATED)\)\s*:\s*(-?\d+\.\d+)ns", re.M)


def first_slack(report: Path) -> Optional[float]:
    """The slack of the worst path in a report, or None if it has none."""
    m = SLACK.search(report.read_text())
    return float(m.group(1)) if m else None


def judge(d: Path, board: str, period: float) -> dict[str, object]:
    slacks = {name: first_slack(d / f"{name}.rpt") for name in ("timing", "timing_in", "timing_out")}
    out: dict[str, object] = {"board": board, "period": period, "reg": slacks["timing"],
                              "in": slacks["timing_in"], "out": slacks["timing_out"]}
    if board not in BUDGET or BUDGET[board][0] != period:
        out["status"] = "none"
        return out
    _, reg_min, port_min = BUDGET[board]
    out["budget_reg"] = reg_min
    out["budget_port"] = port_min
    reg, p_in, p_out = slacks["timing"], slacks["timing_in"], slacks["timing_out"]
    if reg is None or p_in is None or p_out is None:
        out["status"] = "missed"
    else:
        out["status"] = "met" if reg >= reg_min and min(p_in, p_out) >= port_min else "missed"
    return out


def describe(r: dict[str, object]) -> str:
    if r["status"] == "none":
        return f"timing budget: none for {r['board']} at {r['period']} ns"
    text = (f"timing budget {r['board']} at {r['period']} ns: core {r['reg']} ns (>= {r['budget_reg']}), "
            f"ports {r['in']} in and {r['out']} out (>= {r['budget_port']})")
    return f"{text}: {'met' if r['status'] == 'met' else 'MISSED'}"


def report(d: Path, board: str, period: float) -> None:
    r = judge(d, board, period)
    (d / "budget.json").write_text(json.dumps(r, indent=2) + "\n")
    print(describe(r))


def fake(d: Path, reg: str, p_in: str, p_out: str) -> None:
    for name, s in (("timing", reg), ("timing_in", p_in), ("timing_out", p_out)):
        (d / f"{name}.rpt").write_text(
            f"Timing Report\n\nSlack ({'VIOLATED' if s.startswith('-') else 'MET'}) :  {s}ns  (required time - arrival time)\n")


def self_test() -> None:
    with tempfile.TemporaryDirectory() as t:
        d = Path(t)
        fake(d, "0.314", "2.254", "2.456")
        assert judge(d, "mega65", 10.0)["status"] == "met"
        fake(d, "-0.010", "2.254", "2.456")
        assert judge(d, "mega65", 10.0)["status"] == "missed"
        fake(d, "0.314", "2.254", "1.499")
        assert judge(d, "mega65", 10.0)["status"] == "missed"
        fake(d, "0.314", "1.500", "1.500")
        assert judge(d, "mega65", 10.0)["status"] == "met"
        assert judge(d, "mega65", 11.0)["status"] == "none"
        assert judge(d, "nexys4ddr", 10.0)["status"] == "none"
        (d / "timing_in.rpt").write_text("No paths found\n")
        r = judge(d, "mega65", 10.0)
        assert r["status"] == "missed" and r["in"] is None
        assert "MISSED" in describe(r)
        with contextlib.redirect_stdout(io.StringIO()):
            report(d, "mega65", 10.0)
        assert json.loads((d / "budget.json").read_text())["status"] == "missed"
    print("timing_budget: ok")


def main() -> int:
    if sys.argv[1:] == ["--test"]:
        self_test()
        return 0
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    report(Path(sys.argv[1]), sys.argv[2], float(sys.argv[3]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
