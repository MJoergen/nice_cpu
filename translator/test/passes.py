#!/usr/bin/env python3
"""Tests of nicewasm's passes over a function's code, on code built by hand.

Usage: passes.py

Each case gives a pass a list of instructions and labels, as the
translator holds a function's code between its passes (README.md, How
functions are translated), and checks what comes out. The cases are the
rules that no wasm module reaches today, so that run.py and fuzz.py
cannot test them, and that a change to the code the translator emits
could reach tomorrow."""

from __future__ import annotations

import os
import sys
from typing import Callable, List

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from nicewasm import (Ins, Item, Label, duplicate_tails, early_exit, hoist_into_slots,  # noqa: E402
                      tail_calls)


def text(items: List[Item]) -> List[str]:
    """The items as lines, for comparing."""
    out = []
    for it in items:
        if isinstance(it, Ins):
            out.append(it.text().strip())
        elif isinstance(it, Label):
            out.append(it.name + ":")
        else:
            out.append(it.strip())
    return out


def access(dest: str, base: str) -> Ins:
    return Ins("MOVE", [dest, f"@___wasm_memory[{base}]"])


def call(label: str) -> List[Item]:
    """A call of a label, as the translator emits it: the push of the
    return address, then the jump."""
    return [Ins("ADD", ["@--R13", "2", "R15"]), Ins("MOVE", ["R15", label], kind="call")]


def ret() -> Ins:
    return Ins("RET", [], kind="exit")


def hoist_after_write() -> None:
    """hoist_into_slots moves an instruction to between the write of an
    access's address register and the access, but not one that uses the
    register written (commit fa3a8a7): a copy of it before a jump back to
    the label after the access could run on a path that left before the
    write."""
    items: List[Item] = [Ins("SHR", ["%v1", "%v9", "2"]), access("%v4", "%v1"),
                         Ins("ADD", ["%v5", "%v1", "%v6"]), Ins("ADD", ["%v7", "%v6", "%v8"])]
    got = text(hoist_into_slots(items))
    want = ["SHR     %v1, %v9, 2", "ADD     %v7, %v6, %v8", "MOVE    %v4, @___wasm_memory[%v1]",
            "ADD     %v5, %v1, %v6"]
    assert got == want, got


def hoist_after_jump() -> None:
    """The same slot after a conditional jump: the first instruction after
    the read that commutes with it moves."""
    items: List[Item] = [Ins("MOVE", ["R15", "W.f0.L1"], "C", "jump", ["W.f0.L1"]),
                         access("%v4", "%v1"), Ins("ADD", ["%v7", "%v6", "%v8"]), Label("W.f0.L1")]
    got = text(hoist_into_slots(items))
    want = ["?C MOVE R15, W.f0.L1", "ADD     %v7, %v6, %v8", "MOVE    %v4, @___wasm_memory[%v1]",
            "W.f0.L1:"]
    assert got == want, got


def tail_call_plain() -> None:
    """A call just before the return becomes a tail call, the push of the
    return address and the return go, and a comment between them does
    not matter."""
    for between in ([], ["        ; a comment"]):
        items: List[Item] = call("_f") + between + [ret()]
        got = text(tail_calls(items))
        assert got == ["TAIL    _f"] + [t.strip() for t in between], got


def tail_call_data() -> None:
    """A call followed by data, such as the two words after a call of a
    checked helper, is not just before the return (commit 2e77769)."""
    items: List[Item] = call("_f") + ["        .DAT    W.f0.L3", ret()]
    got = text(tail_calls(items))
    assert got == ["ADD     @--R13, 2, R15", "MOVE    R15, _f", ".DAT    W.f0.L3", "RET"], got


def no_tail_copies_in_stubs() -> None:
    """duplicate_tails copies short code in place of a jump to it before
    the epilogue, and leaves the jumps in the stubs after it (commit
    3e0a2c1), which run rarely. The stub is the one a conditional jump
    in the body goes to, as a trap stub is."""
    jump = Ins("MOVE", ["R15", "W.f0.L1"], "", "jump", ["W.f0.L1"])
    items: List[Item] = [Label("W.f0"), jump, Label("W.f0.L2"),
                         Ins("MOVE", ["R15", "W.f0.S0"], "C", "jump", ["W.f0.S0"]),
                         Ins("ADD", ["R1", "R1", "2"]),
                         Label("W.f0.L1"), Ins("ADD", ["R1", "R1", "1"]), ret(),
                         Label("W.f0.S0"), Ins("MOVE", ["R2", "W.f0.L2"]),
                         Ins("MOVE", ["R15", "W.f0.L1"], "", "jump", ["W.f0.L1"])]
    got = text(duplicate_tails(items, 1))
    want = ["W.f0:", "ADD     R1, R1, 1", "RET", "W.f0.L2:", "?C MOVE R15, W.f0.S0",
            "ADD     R1, R1, 2", "W.f0.L1:", "ADD     R1, R1, 1", "RET", "W.f0.S0:",
            "MOVE    R2, W.f0.L2", "MOVE    R15, W.f0.L1"]
    assert got == want, got


def early_function(first: List[Item], exit_code: List[Item]) -> List[Item]:
    """A function that saves R7 and R8: first, then a jump on Z to
    W.f0.L1, a return of R7 + R8, and at W.f0.L1 exit_code."""
    return first + [Ins("MOVE", ["R15", "W.f0.L1"], "Z", "jump", ["W.f0.L1"]),
                    Ins("ADD", ["R1", "R7", "R8"]), ret(), Label("W.f0.L1")] + exit_code


def early_exit_flags() -> None:
    """early_exit moves the test and the jump before the prologue. The
    test SUB[M] R8, R7, 5 writes a saved register, so it stays after the
    prologue, without the M bit, and a copy that writes R0 sets the flags
    before it. R7 is not written yet there, so the copy reads R1, which
    MOVE R7, R1 copied (README.md, The frame). If R7 is not a copy, as
    after ADD R7, R1, 1, the copy cannot read it, and the jump stays."""
    test = Ins("SUB[M]", ["R8", "R7", "5"])
    got = early_exit(early_function([Ins("MOVE", ["R7", "R1"]), test],
                                    [Ins("MOVE", ["R1", "0"]), ret()]), ["R7", "R8"], "W.f0.E")
    assert got is not None
    want = [["SUB[M]  R0, R1, 5", "?Z MOVE R15, W.f0.E"],
            ["MOVE    R7, R1", "SUB     R8, R7, 5", "ADD     R1, R7, R8", "RET", "W.f0.L1:",
             "MOVE    R1, 0", "RET"],
            ["W.f0.E:", "MOVE    R1, 0"]]
    assert [text(part) for part in got] == want, [text(part) for part in got]
    got = early_exit(early_function([Ins("ADD", ["R7", "R1", "1"]), test],
                                    [Ins("MOVE", ["R1", "0"]), ret()]), ["R7", "R8"], "W.f0.E")
    assert got is None, got


def early_exit_call() -> None:
    """The code that the jump goes to must return without a call, which
    may change R1-R6 and needs the return address on the stack."""
    got = early_exit(early_function([Ins("MOVE[M]", ["R0", "R1"])], call("_f") + [ret()]),
                     ["R7", "R8"], "W.f0.E")
    assert got is None, got


CASES: List[Callable[[], None]] = [hoist_after_write, hoist_after_jump, tail_call_plain,
                                   tail_call_data, no_tail_copies_in_stubs, early_exit_flags,
                                   early_exit_call]


def main() -> None:
    bad = 0
    for case in CASES:
        try:
            case()
            print(f"PASS {case.__name__}")
        except AssertionError as e:
            bad += 1
            print(f"FAIL {case.__name__}: {e}")
    if bad:
        sys.exit(f"FAIL passes.py: {bad} of {len(CASES)}")
    print(f"PASS passes.py ({len(CASES)} cases)")


if __name__ == "__main__":
    main()
