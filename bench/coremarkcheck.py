#!/usr/bin/env python3
"""Checks the output of CoreMark against the values it should print.

    ./coremarkcheck.py --seeds perf|valid --iterations N [--clock HZ] [--host] FILE
    ./coremarkcheck.py --test       check the checker on good and bad outputs

CoreMark checks the CRCs of its list, matrix, and state for the two sets
of seeds itself, and prints an ERROR line for each that is wrong. This
checks them again, against the known values of core_main.c, and the final
CRC, which depends on the iterations, against a table of its own, taken
from builds of coremark/ for the host with gcc and clang (README.md,
CoreMark). The seeds are perf, 0 0 0x66, or valid, 0x3415 0x3415 0x66,
and the iterations must be those of the output.

There must be no ERROR line but the one that says that the run took less
than 10 seconds, which must be there exactly when the ticks are fewer
than 10 seconds at --clock HZ, 100 MHz by default. CoreMark then says
that errors were detected, and after a longer run that the operation was
validated, and with the performance seeds it prints its CoreMark 1.0
line. The port's two lines (README.md, CoreMark) must agree with the
ticks and the iterations: the cycles of one iteration and the CoreMark
per MHz, 10^6 N / cycles with three decimals. --host leaves out the
ticks, which are clock()'s there, and so the two lines and the 10
seconds. One line: PASS, or FAIL and what was wrong.
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import Dict, List, Optional, Tuple

# The seeds: the parameters line and the seedcrc that CoreMark prints, and
# the CRCs of list, matrix, and state, which do not depend on the
# iterations (known_id 3 and 4 of core_main.c, for 666 bytes each).
SEEDS: Dict[str, Tuple[str, int, int, int, int]] = {
    "perf": ("2K performance run parameters for coremark.", 0xE9F5, 0xE714, 0x1FD7, 0x8E3A),
    "valid": ("2K validation run parameters for coremark.", 0x18F2, 0xE3C1, 0x0747, 0x8D84),
}

# crcfinal by seeds and iterations, from the host builds. After one
# iteration it is crclist. 1 is a core's run, 10 the emulator's, and 2000
# the run that CoreMark times itself at 100 MHz.
FINAL: Dict[Tuple[str, int], int] = {
    ("perf", 1): 0xE714,
    ("perf", 10): 0xFCAF,
    ("perf", 2000): 0x4983,
    ("valid", 1): 0xE3C1,
    ("valid", 10): 0xC64E,
    ("valid", 2000): 0x0CAC,
}

SHORT = "ERROR! Must execute for at least 10 secs for a valid result!"
FIELD = re.compile(r"^(\[0\])?([A-Za-z][A-Za-z /]*?)\s*: (.*)$")


def fields(lines: List[str]) -> Dict[str, str]:
    """The first value of each field "name : value" in lines."""
    found: Dict[str, str] = {}
    for line in lines:
        m = FIELD.match(line)
        if m and not line.startswith("ERROR") and m.group(2) not in found:
            found[m.group(2)] = m.group(3)
    return found


def hex16(text: Optional[str]) -> Optional[int]:
    """The value of a CRC field, 0x and four hex digits, or None."""
    if text is None or not re.fullmatch(r"0x[0-9a-f]{4}", text):
        return None
    return int(text, 16)


def check(text: str, seeds: str, iterations: int, clock: int = 100_000_000,
          host: bool = False) -> List[str]:
    """The errors in CoreMark's output text, none if it is right."""
    lines = text.splitlines()
    f = fields(lines)
    errors: List[str] = []
    params, seedcrc, *known = SEEDS[seeds]
    if params not in lines:
        errors.append(f"no line '{params}'")
    if f.get("CoreMark Size") != "666":
        errors.append(f"CoreMark Size is {f.get('CoreMark Size')}, expected 666")
    if f.get("Iterations") != str(iterations):
        errors.append(f"{f.get('Iterations')} iterations, expected {iterations}")
    if hex16(f.get("seedcrc")) != seedcrc:
        errors.append(f"seedcrc is {f.get('seedcrc')}, expected 0x{seedcrc:04x}")
    want_final = FINAL.get((seeds, iterations))
    if want_final is None:
        errors.append(f"no known crcfinal for {iterations} iterations")
    for name, want in zip(("crclist", "crcmatrix", "crcstate", "crcfinal"), known + [want_final]):
        if want is not None and hex16(f.get(name)) != want:
            errors.append(f"{name} is {f.get(name)}, expected 0x{want:04x}")

    others = [line for line in lines if line.startswith("ERROR") and line != SHORT]
    errors += [f"'{line}'" for line in others]
    if host:
        return errors

    ticks_text = f.get("Total ticks", "")
    if not ticks_text.isdigit() or int(ticks_text) == 0:
        return errors + [f"Total ticks is {ticks_text!r}"]
    ticks = int(ticks_text)
    short = ticks < 10 * clock
    if (SHORT in lines) != short:
        errors.append(f"the 10-second line {'missing' if short else 'there'} with {ticks} ticks")
    ok = not short and not others
    for line, want in (("Errors detected", not ok), ("Correct operation validated.", ok)):
        if any(x.startswith(line) for x in lines) != want:
            errors.append(f"'{line}' {'missing' if want else 'there'}")
    score = any(x.startswith("CoreMark 1.0 : ") for x in lines)
    if score != (ok and seeds == "perf"):
        errors.append(f"the CoreMark 1.0 line {'there' if score else 'missing'}")

    if iterations > 0:
        if f.get("Cycles/iteration") != str(ticks // iterations):
            errors.append(f"Cycles/iteration is {f.get('Cycles/iteration')}, "
                          f"expected {ticks // iterations}")
        milli = 10**9 * iterations // ticks
        score_text = f"{milli // 1000}.{milli % 1000:03d}"
        if f.get("CoreMark/MHz") != score_text:
            errors.append(f"CoreMark/MHz is {f.get('CoreMark/MHz')}, expected {score_text}")
    return errors


# --test: the emulator's output for the performance seeds and 10
# iterations, and a mistake put into each part of it.
GOOD = """\
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 6750958
Total time (secs): 0.067510
Iterations/Sec   : 148.127125
ERROR! Must execute for at least 10 secs for a valid result!
Iterations       : 10
Compiler version : Ubuntu Clang 18.1.3 (1ubuntu1), wasm32, through nicewasm
Compiler flags   : --target=wasm32 -mbulk-memory -O2
Memory location  : STATIC
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xfcaf
Errors detected
Cycles/iteration : 675095
CoreMark/MHz     : 1.481
"""

# The emulator's output for the performance seeds and 0 iterations, which
# CoreMark set to 2000, a run of 13.5 seconds at 100 MHz.
LONG = """\
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 1350217511
Total time (secs): 13.502175
Iterations/Sec   : 148.124282
Iterations       : 2000
Compiler version : Ubuntu Clang 18.1.3 (1ubuntu1), wasm32, through nicewasm
Compiler flags   : --target=wasm32 -mbulk-memory -O2
Memory location  : STATIC
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0x4983
Correct operation validated. See README.md for run and reporting rules.
CoreMark 1.0 : 148.124282 / Ubuntu Clang 18.1.3 (1ubuntu1), wasm32, through nicewasm \
--target=wasm32 -mbulk-memory -O2 / STATIC
Cycles/iteration : 675108
CoreMark/MHz     : 1.481
"""
SCORE = next(line for line in LONG.splitlines() if line.startswith("CoreMark 1.0")) + "\n"

# (what is wrong, the output, seeds, iterations, an error that must be reported)
BAD: List[Tuple[str, str, str, int, str]] = [
    ("other seeds", GOOD, "valid", 10, "no line '2K validation run parameters for coremark.'"),
    ("other iterations", GOOD, "perf", 1, "10 iterations, expected 1"),
    ("unknown iterations", GOOD.replace(": 10\n", ": 7\n"), "perf", 7,
     "no known crcfinal for 7 iterations"),
    ("the size", GOOD.replace(": 666", ": 600"), "perf", 10, "CoreMark Size is 600, expected 666"),
    ("the seedcrc", GOOD.replace("0xe9f5", "0xe9f6"), "perf", 10,
     "seedcrc is 0xe9f6, expected 0xe9f5"),
    ("crclist", GOOD.replace("0xe714", "0xe715"), "perf", 10, "crclist is 0xe715, expected 0xe714"),
    ("crcmatrix", GOOD.replace("0x1fd7", "0x1fd8"), "perf", 10,
     "crcmatrix is 0x1fd8, expected 0x1fd7"),
    ("crcstate", GOOD.replace("0x8e3a", "0x8e3b"), "perf", 10,
     "crcstate is 0x8e3b, expected 0x8e3a"),
    ("crcfinal", GOOD.replace("0xfcaf", "0xfcae"), "perf", 10,
     "crcfinal is 0xfcae, expected 0xfcaf"),
    ("no crcfinal", GOOD.replace("[0]crcfinal      : 0xfcaf\n", ""), "perf", 10,
     "crcfinal is None, expected 0xfcaf"),
    ("an error of CoreMark",
     GOOD.replace("Errors detected", "ERROR! list crc 0x0 - should be 0x1\nErrors detected"),
     "perf", 10,
     "'ERROR! list crc 0x0 - should be 0x1'"),
    ("ticks that do not fit",
     GOOD.replace("Errors detected", "ERROR! 5000000000 ticks do not fit CORE_TICKS!\n"
                  "Errors detected"), "perf", 10,
     "'ERROR! 5000000000 ticks do not fit CORE_TICKS!'"),
    ("no ticks", GOOD.replace("6750958", "0"), "perf", 10, "Total ticks is '0'"),
    ("no 10-second line", GOOD.replace(SHORT + "\n", ""), "perf", 10,
     "the 10-second line missing with 6750958 ticks"),
    ("validated after a short run", GOOD.replace("Errors detected", "Correct operation validated."),
     "perf", 10, "'Errors detected' missing"),
    ("the cycles of one iteration",
     GOOD.replace("iteration : 675095", "iteration : 675096"), "perf", 10,
     "Cycles/iteration is 675096, expected 675095"),
    ("the CoreMark/MHz", GOOD.replace("1.481", "1.480"), "perf", 10,
     "CoreMark/MHz is 1.480, expected 1.481"),
    ("no CoreMark/MHz", GOOD.replace("CoreMark/MHz     : 1.481\n", ""), "perf", 10,
     "CoreMark/MHz is None, expected 1.481"),
    ("a long run with the 10-second line", LONG.replace("Correct", SHORT + "\nCorrect"),
     "perf", 2000, "the 10-second line there with 1350217511 ticks"),
    ("a long run without the CoreMark 1.0 line", LONG.replace(SCORE, ""), "perf", 2000,
     "the CoreMark 1.0 line missing"),
    ("a long run of the validation seeds with a CoreMark 1.0 line",
     LONG.replace("performance", "validation").replace("0xe9f5", "0x18f2")
     .replace("0xe714", "0xe3c1").replace("0x1fd7", "0x0747").replace("0x8e3a", "0x8d84")
     .replace("0x4983", "0x0cac"),
     "valid", 2000, "the CoreMark 1.0 line there"),
]


def test() -> None:
    good = check(GOOD, "perf", 10)
    if good:
        sys.exit(f"FAIL coremarkcheck.py --test: the good output: {good}")
    long_errors = check(LONG, "perf", 2000)
    if long_errors:
        sys.exit(f"FAIL coremarkcheck.py --test: the long run: {long_errors}")
    host = check(GOOD.replace("6750958", "0").replace(SHORT + "\n", ""), "perf", 10, host=True)
    if host:
        sys.exit(f"FAIL coremarkcheck.py --test: the host's output: {host}")
    # The same ticks are 10 seconds or more at 100 kHz.
    slow = check(GOOD, "perf", 10, clock=100_000)
    if "the 10-second line there with 6750958 ticks" not in slow:
        sys.exit(f"FAIL coremarkcheck.py --test: a clock of 100 kHz: {slow}")
    for what, text, seeds, iterations, error in BAD:
        errors = check(text, seeds, iterations)
        if error not in errors:
            sys.exit(f"FAIL coremarkcheck.py --test: {what}: {errors}")
    print(f"PASS coremarkcheck.py --test ({len(BAD) + 4} cases)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("file", nargs="?")
    ap.add_argument("--seeds", choices=sorted(SEEDS))
    ap.add_argument("--iterations", type=int)
    ap.add_argument("--clock", type=int, default=100_000_000, metavar="HZ",
                    help="the ticks per second, 100 MHz by default")
    ap.add_argument("--host", action="store_true", help="the output of the host build")
    ap.add_argument("--test", action="store_true")
    args = ap.parse_args()
    if args.test:
        test()
        return
    if not args.file or args.seeds is None or args.iterations is None:
        ap.error("give --seeds, --iterations, and a FILE, or --test")
    with open(args.file) as f:
        errors = check(f.read(), args.seeds, args.iterations, args.clock, args.host)
    what = f"coremark {args.seeds} {args.iterations}"
    if errors:
        sys.exit(f"FAIL {what}: " + "; ".join(errors))
    print(f"PASS {what}")


if __name__ == "__main__":
    main()
