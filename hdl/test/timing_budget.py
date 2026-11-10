#!/usr/bin/env python3
"""Compares the reports of "make timing" with the budget of the board.

    timing_budget.py DIR BOARD PERIOD [FLOW]   judge the reports in DIR
    timing_budget.py --spread DIR...           the least, median, and most of
                                               each slack over several runs
    timing_budget.py --test                    the self-test of make test

The budget is the least slack at a 10 ns clock, in ns, of the worst
register-to-register path (the core alone), of the worst path from an
input, and of the worst path to an output. The last two are the time left
to the system around the core, which takes some of it: the block RAMs, the
data bus decode, and the devices of NiceMonMEGA65.

A miss is a warning, never a failure: it prints "MISSED" and exits 0. DIR
gets budget.json, which release/release.py puts in its stamp. A board or
period without a budget is "none".

One run cannot tell a small change from noise. Vivado gives the same result
for the same input, but a change elsewhere in the design moves the
placement, and with it the slacks, by more than the margin of the budget
(#151). SPREAD has the range seen over the seven variants of "make
timing-spread", and a miss by less than it says so. --spread judges those
variants: a change counts if it moves the median by more than the range.
"""

import contextlib
import io
import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Optional

# board: (period in ns, least slack of the core, of the inputs, of the outputs).
# The MEGA65's from NiceMonMEGA65 at V1.0: out of context the inputs have 2.25
# ns and the outputs 2.46 ns, and in the system +0.92 ns and +0.46 ns. So the
# system takes about 1.3 ns of the inputs and 2.0 ns of the outputs, and each
# budget keeps about 0.2 ns of in-system slack. The worst output in the system
# goes to a device, which is not in the core, so this is a calibration, not a
# promise. The Nexys4DDR has none: the core alone misses 90 MHz there.
BUDGET: dict[str, tuple[float, float, float, float]] = {
    "mega65": (10.0, 0.0, 1.5, 2.2),
}

# (board, flow): the range, most less least, of the slack of the core, the
# inputs, and the outputs over the seven variants of make timing-spread, in
# ns. The MEGA65's from 565b976 (#151): in the default flow the core has
# 0.111 to 0.708, the inputs 1.869 to 2.559, and the outputs 1.554 to 2.963;
# in the timing flow -0.075 to 0.342, 1.052 to 2.176, and 1.246 to 2.495.
# So the budget of the outputs lies inside the range of both flows.
SPREAD: dict[tuple[str, str], tuple[float, float, float]] = {
    ("mega65", "default"): (0.60, 0.69, 1.41),
    ("mega65", "timing"): (0.42, 1.12, 1.25),
}

SLACK = re.compile(r"^Slack \((?:MET|VIOLATED)\)\s*:\s*(-?\d+\.\d+)ns", re.M)


def first_slack(report: Path) -> Optional[float]:
    """The slack of the worst path in a report, or None if it has none."""
    m = SLACK.search(report.read_text())
    return float(m.group(1)) if m else None


def judge(d: Path, board: str, period: float, flow: str = "default") -> dict[str, object]:
    slacks = {name: first_slack(d / f"{name}.rpt") for name in ("timing", "timing_in", "timing_out")}
    out: dict[str, object] = {"board": board, "period": period, "flow": flow, "reg": slacks["timing"],
                              "in": slacks["timing_in"], "out": slacks["timing_out"]}
    if board not in BUDGET or BUDGET[board][0] != period:
        out["status"] = "none"
        return out
    _, reg_min, in_min, out_min = BUDGET[board]
    out["budget_reg"] = reg_min
    out["budget_in"] = in_min
    out["budget_out"] = out_min
    reg, p_in, p_out = slacks["timing"], slacks["timing_in"], slacks["timing_out"]
    if reg is None or p_in is None or p_out is None:
        out["status"] = "missed"
    else:
        out["status"] = "met" if reg >= reg_min and p_in >= in_min and p_out >= out_min else "missed"
        spread = SPREAD.get((board, flow))
        if out["status"] == "missed" and spread is not None:
            out["within_spread"] = all(s >= m - w for s, m, w in
                                       zip((reg, p_in, p_out), (reg_min, in_min, out_min), spread))
    return out


def describe(r: dict[str, object]) -> str:
    if r["status"] == "none":
        return f"timing budget: none for {r['board']} at {r['period']} ns"
    text = (f"timing budget {r['board']} at {r['period']} ns: core {r['reg']} ns (>= {r['budget_reg']}), "
            f"inputs {r['in']} ns (>= {r['budget_in']}), outputs {r['out']} ns (>= {r['budget_out']})")
    if r["status"] == "met":
        return f"{text}: met"
    if r.get("within_spread"):
        return f"{text}: MISSED, by less than one run varies (make timing-spread)"
    return f"{text}: MISSED"


def median(xs: list[float]) -> float:
    xs = sorted(xs)
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2


def spread(dirs: list[Path]) -> str:
    """The least, median, and most of each slack over the runs in dirs, from
    their budget.json, and how many met the budget."""
    runs = [json.loads((d / "budget.json").read_text()) for d in dirs]
    lines = [f"{len(runs)} runs:"]
    for key, name in (("reg", "core"), ("in", "inputs"), ("out", "outputs")):
        xs = [float(r[key]) for r in runs if r.get(key) is not None]
        if len(xs) < len(runs):
            lines.append(f"  {name}: {len(runs) - len(xs)} runs have no slack")
        if xs:
            lines.append(f"  {name}: least {min(xs):.3f}, median {median(xs):.3f}, most {max(xs):.3f} ns")
    met = sum(r.get("status") == "met" for r in runs)
    judged = sum(r.get("status") in ("met", "missed") for r in runs)
    if judged:
        lines.append(f"  budget met in {met} of {judged}")
    return "\n".join(lines)


def report(d: Path, board: str, period: float, flow: str = "default") -> None:
    r = judge(d, board, period, flow)
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
        fake(d, "0.314", "2.254", "2.199")
        assert judge(d, "mega65", 10.0)["status"] == "missed"
        fake(d, "0.314", "1.499", "2.456")
        assert judge(d, "mega65", 10.0)["status"] == "missed"
        fake(d, "0.314", "1.500", "2.200")
        assert judge(d, "mega65", 10.0)["status"] == "met"
        fake(d, "0.314", "2.200", "1.500")
        assert judge(d, "mega65", 10.0)["status"] == "missed"
        assert judge(d, "mega65", 11.0)["status"] == "none"
        assert judge(d, "nexys4ddr", 10.0)["status"] == "none"
        (d / "timing_in.rpt").write_text("No paths found\n")
        r = judge(d, "mega65", 10.0)
        assert r["status"] == "missed" and r["in"] is None
        assert "MISSED" in describe(r)
        with contextlib.redirect_stdout(io.StringIO()):
            report(d, "mega65", 10.0)
        assert json.loads((d / "budget.json").read_text())["status"] == "missed"
        fake(d, "0.314", "2.254", "1.000")
        assert judge(d, "mega65", 10.0)["within_spread"] is True
        assert "less than one run varies" in describe(judge(d, "mega65", 10.0))
        fake(d, "0.314", "2.254", "0.700")
        assert judge(d, "mega65", 10.0)["within_spread"] is False
        assert describe(judge(d, "mega65", 10.0)).endswith("MISSED")
        assert "within_spread" not in judge(d, "mega65", 10.0, "other")
        fake(d, "-0.100", "2.254", "2.456")
        assert judge(d, "mega65", 10.0, "timing")["within_spread"] is True
        dirs = []
        for i, (reg, p_in, p_out) in enumerate((("0.1", "2.0", "2.5"), ("0.3", "1.0", "2.1"), ("0.2", "1.6", "3.0"))):
            di = d / str(i)
            di.mkdir()
            fake(di, reg, p_in, p_out)
            with contextlib.redirect_stdout(io.StringIO()):
                report(di, "mega65", 10.0)
            dirs.append(di)
        text = spread(dirs)
        assert "core: least 0.100, median 0.200, most 0.300 ns" in text, text
        assert "inputs: least 1.000, median 1.600, most 2.000 ns" in text, text
        assert "budget met in 2 of 3" in text, text
        assert median([4.0, 1.0, 3.0, 2.0]) == 2.5
    print("timing_budget: ok")


def main() -> int:
    if sys.argv[1:] == ["--test"]:
        self_test()
        return 0
    if sys.argv[1:2] == ["--spread"] and len(sys.argv) > 2:
        print(spread([Path(a) for a in sys.argv[2:]]))
        return 0
    if len(sys.argv) not in (4, 5):
        print(__doc__, file=sys.stderr)
        return 2
    report(Path(sys.argv[1]), sys.argv[2], float(sys.argv[3]), *sys.argv[4:])
    return 0


if __name__ == "__main__":
    sys.exit(main())
