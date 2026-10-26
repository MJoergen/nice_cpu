#!/usr/bin/env python3
"""Checks the section references and the links of the repository's documents.

Usage: check_refs.py [ROOT]

ROOT is the repository, by default the parent of this file's directory.
Two things are checked in every file that git tracks:

- A section reference "FILE §n.m" or "FILE.md §n.m", where FILE is one of
  the documents in DOCUMENTS, names a section that FILE has. The notes in
  doc/review/ are left out: they cite the sections as they were numbered
  on their dates (doc/REFERENCES.md).
- In a Markdown file, a link "[text](target)" or "![text](target)" whose
  target is not a URL names a file that exists, relative to the file, and
  its "#anchor", if it has one, names a heading of that file, as GitHub
  makes anchors from headings.

The exit status is 1 if anything is wrong, with one line per problem.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from typing import Dict, List, Set

# The documents whose sections are referred to by name, and where they are.
DOCUMENTS = {
    "ISA.md": "doc/ISA.md",
    "SYSTEM.md": "doc/SYSTEM.md",
    "DEBUG.md": "doc/DEBUG.md",
    "MICROARCH.md": "doc/MICROARCH.md",
    "HISTORY.md": "doc/HISTORY.md",
    "REFERENCES.md": "doc/REFERENCES.md",
    "ABI.md": "runtime/ABI.md",
    "WASM.md": "translator/WASM.md",
    "ASSUMPTIONS.md": "hdl/ASSUMPTIONS.md",
}

# The files whose section references are not checked.
HISTORICAL = ("doc/review/",)

SECTION_REF = re.compile(r"\b(" + "|".join(name[:-3] for name in DOCUMENTS)
                         + r")(?:\.md)?\s*§\s*(\d+(?:\.\d+)*)")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
NUMBERED = re.compile(r"^(\d+(?:\.\d+)*)\b")
APPENDIX = re.compile(r"^Appendix ([A-Z])\b")
LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
SCHEME = re.compile(r"^[a-z][a-z0-9+.-]*:")
CODE_FENCE = re.compile(r"^(```|~~~)")


def read(path: str) -> str | None:
    """The text of a file, or None if it is not text."""
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
        return None


def headings(text: str) -> List[str]:
    """The headings of a Markdown text, outside code fences."""
    out = []
    fenced = False
    for line in text.split("\n"):
        if CODE_FENCE.match(line):
            fenced = not fenced
            continue
        m = HEADING.match(line)
        if m and not fenced:
            out.append(m.group(1))
    return out


def sections(text: str) -> Set[str]:
    """The section numbers of a document: "5.3" for "### 5.3 Data accesses",
    and "Appendix B" for "## Appendix B: ..."."""
    out = set()
    for h in headings(text):
        m = NUMBERED.match(h)
        if m:
            out.add(m.group(1))
        a = APPENDIX.match(h)
        if a:
            out.add("Appendix " + a.group(1))
    return out


def slug(heading: str) -> str:
    """The anchor GitHub makes from a heading: lower case, letters, digits,
    spaces, hyphens, and underscores kept, spaces turned into hyphens."""
    s = heading.strip().lower()
    s = "".join(c for c in s if c.isalnum() or c in " -_")
    return s.replace(" ", "-")


def anchors(text: str) -> Set[str]:
    """The anchors of a Markdown text, with -1, -2, ... for repeated ones."""
    out: Set[str] = set()
    seen: Dict[str, int] = {}
    for h in headings(text):
        s = slug(h)
        n = seen.get(s, 0)
        seen[s] = n + 1
        out.add(s if n == 0 else f"{s}-{n}")
    return out


def check(root: str) -> List[str]:
    files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True,
                           check=True).stdout.split()
    known = {name: sections(read(os.path.join(root, path)) or "")
             for name, path in DOCUMENTS.items()}
    anchors_of: Dict[str, Set[str]] = {}
    problems = []
    for f in files:
        text = read(os.path.join(root, f))
        if text is None:
            continue
        lines = text.split("\n")
        if not f.startswith(HISTORICAL):
            for i, line in enumerate(lines, 1):
                for m in SECTION_REF.finditer(line):
                    doc, sec = m.group(1) + ".md", m.group(2)
                    if sec not in known[doc]:
                        problems.append(f"{f}:{i}: {doc} has no section {sec}")
        if not f.endswith(".md"):
            continue
        fenced = False
        for i, line in enumerate(lines, 1):
            if CODE_FENCE.match(line):
                fenced = not fenced
            if fenced:
                continue
            for m in LINK.finditer(line):
                target = m.group(1)
                if SCHEME.match(target):
                    continue
                path, _, anchor = target.partition("#")
                if path:
                    full = os.path.normpath(os.path.join(root, os.path.dirname(f), path))
                    rel = os.path.relpath(full, root)
                    if not os.path.exists(full):
                        problems.append(f"{f}:{i}: {target}: no file {rel}")
                        continue
                else:
                    rel = f
                if anchor:
                    if rel not in anchors_of:
                        anchors_of[rel] = anchors(read(os.path.join(root, rel)) or "")
                    if anchor not in anchors_of[rel]:
                        problems.append(f"{f}:{i}: {target}: {rel} has no heading for #{anchor}")
    return problems


def main() -> None:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))
    problems = check(root)
    for p in problems:
        print(p)
    if problems:
        sys.exit(f"FAIL check_refs.py: {len(problems)} problems")
    print("PASS check_refs.py")


if __name__ == "__main__":
    main()
