#!/usr/bin/env python3
"""Check the worked examples of the top-level README.md against the tools.

Usage: check_readme.py [FILE]

FILE is README.md in the top directory unless given. A section of it that
links to an example program, doc/intro/examples/X.nasm, is a worked
example, and each indented block of the section is one of two kinds:

* A listing of the program. Its lines are lines of X.nasm, in the order
  of the file and next to each other. A line "..." stands for lines left
  out.
* Commands and their output: a line "$ command", and after it the lines
  that the command prints. A line "..." stands for any lines. A command
  that shows no output must end with status 0.

The commands are those of the top directory. A command is run when it is
niceasm or niceemu, and has no --window. It runs in a temporary directory,
with the names of the repository's files made absolute, so that a .bin
file is written there and found there by the next command. niceemu must
have been built.

The script prints one line, PASS or FAIL, with the lines of each block
that fails, and its exit status is 1 after a FAIL.
"""

import os
import re
import shlex
import subprocess
import sys
import tempfile
from typing import List, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN = ("assembler/niceasm.py", "emulator/zig-out/bin/niceemu")
EXAMPLE = re.compile(r"\]\((doc/intro/examples/\w+\.nasm)\)")
ELLIPSIS = "..."

Block = Tuple[int, List[str]]  # the number of its first line, and its lines


def sections(lines: List[str]) -> List[Tuple[int, List[str]]]:
    """The file split at its headings: the number of each section's first
    line, from 1, and its lines."""
    out: List[Tuple[int, List[str]]] = [(1, [])]
    for n, line in enumerate(lines, 1):
        if line.startswith("#"):
            out.append((n, []))
        out[-1][1].append(line)
    return out


def blocks(first: int, lines: List[str]) -> List[Block]:
    """The indented blocks of a section, without their indent. A blank line
    between two indented lines belongs to the block."""
    out: List[Block] = []
    cur: List[str] = []
    for n, line in enumerate(lines + [""], first):
        if line.startswith("    "):
            if not cur:
                out.append((n, cur))
            cur.append(line[4:].rstrip())
        elif line.strip() == "" and cur:
            cur.append("")
        else:
            cur = []
    for _, block in out:
        while block and block[-1] == "":
            block.pop()
    return out


def pieces(lines: List[str]) -> List[List[str]]:
    """The lines split at each "..." line."""
    out: List[List[str]] = [[]]
    for line in lines:
        if line.strip() == ELLIPSIS:
            out.append([])
        else:
            out[-1].append(line)
    return out


def find(piece: List[str], lines: List[str], start: int) -> int:
    """The first index from start where piece lies in lines, or -1."""
    for i in range(start, len(lines) - len(piece) + 1):
        if lines[i:i + len(piece)] == piece:
            return i
    return -1


def matches(expected: List[str], got: List[str]) -> bool:
    """Whether got is expected, where a "..." line stands for any lines."""
    parts = pieces(expected)
    if len(parts) == 1:
        return got == parts[0]
    head, tail = parts[0], parts[-1]
    if got[:len(head)] != head:
        return False
    pos = len(head)
    for part in parts[1:-1]:
        i = find(part, got, pos)
        if i < 0:
            return False
        pos = i + len(part)
    return len(got) - len(tail) >= pos and got[len(got) - len(tail):] == tail


def check_listing(block: Block, program: str) -> List[str]:
    """The faults of a listing of program, a path from the top directory."""
    with open(os.path.join(ROOT, program), encoding="utf-8") as f:
        source = [line.rstrip() for line in f.read().split("\n")]
    pos = 0
    for part in pieces(block[1]):
        i = find(part, source, pos)
        if i < 0:
            at = next((line for k, line in enumerate(part)
                       if find(part[:k + 1], source, pos) < 0), "")
            return [f"line {block[0]}: not as in {program}:", "    " + at]
        pos = i + len(part)
    return []


def run(command: str, cwd: str) -> Tuple[int, List[str]]:
    """Run a command of the top directory in cwd: its status and the lines
    it prints."""
    args = [os.path.join(ROOT, a) if os.path.exists(os.path.join(ROOT, a)) else a
            for a in shlex.split(command)]
    p = subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       encoding="utf-8", errors="replace")
    return p.returncode, [line.rstrip() for line in p.stdout.splitlines()]


def check_commands(block: Block, cwd: str) -> Tuple[int, List[str]]:
    """Run the commands of a block: how many ran, and their faults."""
    faults: List[str] = []
    ran = 0
    first, lines = block
    starts = [k for k, line in enumerate(lines) if line.startswith("$ ")]
    for k, end in zip(starts, starts[1:] + [len(lines)]):
        command = lines[k][2:]
        expected = lines[k + 1:end]
        words = shlex.split(command)
        if words[0] not in RUN or "--window" in words:
            continue
        ran += 1
        status, got = run(command, cwd)
        if not expected and status != 0:
            faults += [f"line {first + k}: $ {command}", f"    ends with status {status}:"]
            faults += ["    " + line for line in got]
        elif expected and not matches(expected, got):
            faults += [f"line {first + k}: $ {command}", "    prints:"]
            faults += ["    " + line for line in got]
    return ran, faults


def main() -> int:
    if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1].startswith("-")):
        print(__doc__.strip(), file=sys.stderr)
        return 1
    path = sys.argv[1] if len(sys.argv) == 2 else os.path.join(ROOT, "README.md")
    name = os.path.basename(path)
    with open(path, encoding="utf-8") as f:
        text = f.read().split("\n")
    if not os.path.exists(os.path.join(ROOT, RUN[1])):
        print(f"FAIL {name}: {RUN[1]} is not built")
        return 1
    faults: List[str] = []
    listings = commands = 0
    with tempfile.TemporaryDirectory() as tmp:
        for first, lines in sections(text):
            programs = EXAMPLE.findall("\n".join(lines))
            if not programs:
                continue
            for block in blocks(first, lines):
                if any(line.startswith("$ ") for line in block[1]):
                    ran, found = check_commands(block, tmp)
                    commands += ran
                    faults += found
                else:
                    listings += 1
                    faults += check_listing(block, programs[0])
    if faults or not listings or not commands:
        print(f"FAIL {name}: {listings} listings and {commands} commands")
        for line in faults:
            print("  " + line)
        return 1
    print(f"PASS {name}: {listings} listings and {commands} commands")
    return 0


if __name__ == "__main__":
    sys.exit(main())
