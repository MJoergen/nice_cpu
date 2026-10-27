#!/usr/bin/env python3
"""nicefmt - checks, or fixes, the layout of NICE assembly source.

The layout has spaces only and these columns: the label in 0, the
condition in 8, the mnemonic or directive in 16, the operands in 24, and
the comment in 40. A label of 8 or more characters stands on a line of its
own. A comment on a line of its own starts in column 0 or, if it was
indented, in column 16. Operands are left as written.

    nicefmt.py FILE...           report the first line of each file that differs
    nicefmt.py --write FILE...   rewrite the files in the layout

Exit status 1 if a file differs, 0 if not, or after --write."""

from __future__ import annotations

import argparse
import sys
from typing import List, Optional, Tuple

import niceasm

COND, OP, ARGS, CMT = 8, 16, 24, 40


def is_keyword(word: str) -> bool:
    """Whether the word is a condition, directive, or mnemonic, not a label."""
    return (word.startswith("?") or word.upper() in niceasm.DIRECTIVES
            or word.split("[")[0].upper() in niceasm.MNEMONICS)


def split_comment(line: str) -> Tuple[str, str]:
    """The code and the comment of a line, which starts at the first ';' outside a string."""
    quote = ""
    for i, c in enumerate(line):
        if quote:
            if c == quote:
                quote = ""
        elif c in niceasm.QUOTES:
            quote = c
        elif c == ";":
            return line[:i], line[i:]
    return line, ""


def first_word(text: str) -> Tuple[Optional[str], str]:
    parts = text.split(None, 1)
    return (parts[0], parts[1] if len(parts) > 1 else "") if parts else (None, "")


def pad(text: str, column: int) -> str:
    """The text, then spaces up to the column, or one space if it reaches it."""
    return text.ljust(column) if len(text) < column else text + " "


def format_line(line: str) -> List[str]:
    """The lines that one line of source becomes: two if its label is long."""
    line = line.expandtabs(8).rstrip()
    stripped = line.lstrip()
    if not stripped:
        return [""]
    if stripped[0] == ";":
        return [line if line[0] == ";" else " " * OP + stripped]
    if stripped[0] == "*":
        return [line]
    code, comment = split_comment(line)
    word, rest = first_word(code.rstrip())
    assert word is not None
    label = cond = None
    if not is_keyword(word):
        label = word
        word, rest = first_word(rest)
    if word is not None and word.startswith("?"):
        cond = word
        word, rest = first_word(rest)
    out: List[str] = []
    text = ""
    if word is None:
        text = label or ""
    else:
        if label is not None:
            if word.upper() == ".EQU":
                text = pad(label, OP)
            elif len(label) < COND:
                text = label
            else:
                out.append(label)
        if cond is not None:
            text = pad(text, COND) + cond
        if not (label is not None and word.upper() == ".EQU"):
            text = pad(text, OP)
        text += word
        if rest:
            text = pad(text, ARGS) + rest
    if comment:
        text = (text.ljust(CMT) if len(text) < CMT - 1 else text + "  ") + comment if text else comment
    out.append(text.rstrip())
    return out


def format_source(source: str) -> str:
    lines = source.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    out: List[str] = []
    for line in lines:
        out += format_line(line)
    return "\n".join(out) + "\n"


def words(source: str) -> List[str]:
    """Every word and comment of the source, to check that formatting keeps them."""
    out: List[str] = []
    for line in source.split("\n"):
        if line.lstrip().startswith("*"):
            out.append(line.strip())
            continue
        code, comment = split_comment(line)
        out += niceasm.TOKEN.findall(code.replace(",", " "))
        out += [comment.strip()] if comment else []
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Checks the layout of NICE assembly source.")
    ap.add_argument("files", nargs="+", help="assembly sources (.nasm)")
    ap.add_argument("--write", action="store_true", help="rewrite the files in the layout")
    args = ap.parse_args()
    status = 0
    for path in args.files:
        with open(path, newline="") as f:
            old = f.read()
        new = format_source(old)
        assert words(old) == words(new), f"{path}: formatting would change the program"
        if new == old:
            continue
        if args.write:
            with open(path, "w", newline="") as f:
                f.write(new)
            continue
        status = 1
        old_lines, new_lines = old.split("\n"), new.split("\n")
        n = next((i for i, (a, b) in enumerate(zip(old_lines, new_lines)) if a != b),
                 min(len(old_lines), len(new_lines)))
        print(f"{path}:{n + 1}: not in the layout of CLAUDE.md; run nicefmt.py --write", file=sys.stderr)
    sys.exit(status)


if __name__ == "__main__":
    main()
