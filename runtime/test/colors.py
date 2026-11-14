#!/usr/bin/env python3
"""Checks that the four files with the names of the screen's colors agree.

runtime/colors.nasm, libc/include/nice.h, nice.zig, and nice.rs each name
the colors of a screen word (DEVICES.md §1.1): a foreground, FG, in bits
19..8, and a background, BG, in bits 31..20. Each must have the same
colors with the same values, each color must have both, the background
the foreground's components 12 bits higher, and the blank of the screen
must be a space in white on black, 0x000FFF20.
"""

import os
import re
import sys
from typing import Dict, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME = os.path.dirname(HERE)

# The file, and the pattern of a color's line: its kind, FG or BG, its
# name, and its value. Zig names them in lower case.
FILES = {
    "colors.nasm": r"^NICE_(FG|BG)_(\w+) +\.EQU +0x([0-9A-F_]+)$",
    "libc/include/nice.h": r"^#define NICE_(FG|BG)_(\w+) 0x([0-9A-F_]+)u$",
    "nice.zig": r"^pub const (fg|bg)_(\w+): u32 = 0x([0-9A-F_]+);$",
    "nice.rs": r"^pub const (FG|BG)_(\w+): u32 = 0x([0-9A-F_]+);$",
}

# The blank of the screen in each file, which must be white on black.
BLANKS = {
    "libc/include/nice.h": "#define NICE_SCREEN_BLANK (NICE_FG_WHITE | NICE_BG_BLACK | ' ')",
    "nice.zig": "pub const screen_blank: u32 = fg_white | bg_black | ' ';",
    "nice.rs": "pub const SCREEN_BLANK: u32 = FG_WHITE | BG_BLACK | ' ' as u32;",
}


def colors(path: str, pattern: str) -> Dict[str, int]:
    """The colors of a file, by kind and name, such as FG_WHITE."""
    out: Dict[str, int] = {}
    with open(os.path.join(RUNTIME, path), encoding="utf-8") as f:
        for line in f:
            m = re.match(pattern, line.rstrip("\n"))
            if m:
                out[f"{m.group(1).upper()}_{m.group(2).upper()}"] = int(m.group(3).replace("_", ""), 16)
    return out


def hexa(value: Optional[int]) -> str:
    return "missing" if value is None else f"0x{value:08X}"


def main() -> None:
    problems = []
    first = None
    for path, pattern in FILES.items():
        found = colors(path, pattern)
        if not found:
            problems.append(f"{path}: no colors")
            continue
        if first is None:
            first = (path, found)
        elif found != first[1]:
            for name in sorted(set(found) | set(first[1])):
                if found.get(name) != first[1].get(name):
                    problems.append(f"{path}: {name} is {hexa(found.get(name))}, in {first[0]}"
                                    f" {hexa(first[1].get(name))}")
    if first is not None:
        path, found = first
        for name, value in sorted(found.items()):
            kind, color = name.split("_", 1)
            fg, bg = found.get("FG_" + color), found.get("BG_" + color)
            if fg is None or bg is None:
                problems.append(f"{path}: {color} has no {'FG' if fg is None else 'BG'}")
            elif kind == "FG" and (fg & ~0x000FFF00 or bg != fg << 12):
                problems.append(f"{path}: FG_{color} 0x{fg:08X} and BG_{color} 0x{bg:08X}"
                                " are not one color in bits 19..8 and 31..20")
        if found.get("FG_WHITE") != 0x000FFF00 or found.get("BG_BLACK") != 0:
            problems.append(f"{path}: white on black is not 0x000FFF00")
    for path, line in BLANKS.items():
        with open(os.path.join(RUNTIME, path), encoding="utf-8") as f:
            if line not in f.read().splitlines():
                problems.append(f"{path}: the blank is not {line}")
    for p in problems:
        print("  " + p)
    n = len(first[1]) // 2 if first else 0
    print(f"{'FAIL' if problems else 'PASS'} colors.py ({n} colors in {len(FILES)} files)")
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
