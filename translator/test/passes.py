#!/usr/bin/env python3
"""Tests of nicewasm's passes over a function's code, on code built by hand.

Usage: passes.py

Each case gives a pass a list of instructions and labels, as the
translator holds a function's code between its passes (DESIGN.md, How
functions are translated), and checks what comes out. The cases are the
rules that no wasm module reaches today, so that run.py and fuzz.py
cannot test them, and that a change to the code the translator emits
could reach tomorrow. One case gives pseudo the lines of the output,
which it rewrites after the passes."""

from __future__ import annotations

import os
import sys
from typing import Callable, List

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "assembler"))
import niceasm  # noqa: E402
from nicewasm import (SHORT_LOOP, Ins, Item, Label, anonymous_labels, duplicate_tails,  # noqa: E402
                      early_exit, hoist_into_slots, instr, predict_back_edges, pseudo,
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
    want = ["?C      MOVE    R15, W.f0.L1", "ADD     %v7, %v6, %v8", "MOVE    %v4, @___wasm_memory[%v1]",
            "W.f0.L1:"]
    assert got == want, got


def tail_call_plain() -> None:
    """A call just before the return becomes a tail call, the push of the
    return address and the return go, and a comment between them does
    not matter."""
    for between in ([], ["        ; a comment"]):
        items: List[Item] = call("_f") + between + [ret()]
        got = text(tail_calls(items))
        assert got == ["TAIL    R15, _f"] + [t.strip() for t in between], got


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
    want = ["W.f0:", "ADD     R1, R1, 1", "RET", "W.f0.L2:", "?C      MOVE    R15, W.f0.S0",
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
    MOVE R7, R1 copied (DESIGN.md, The frame). If R7 is not a copy, as
    after ADD R7, R1, 1, the copy cannot read it, and the jump stays."""
    test = Ins("SUB[M]", ["R8", "R7", "5"])
    got = early_exit(early_function([Ins("MOVE", ["R7", "R1"]), test],
                                    [Ins("MOVE", ["R1", "0"]), ret()]), ["R7", "R8"], "W.f0.E")
    assert got is not None
    want = [["SUB[M]  R0, R1, 5", "?Z      MOVE    R15, W.f0.E"],
            ["MOVE    R7, R1", "SUB     R8, R7, 5", "ADD     R1, R7, R8", "RET", "W.f0.L1:",
             "MOVE    R1, R0", "RET"],
            ["W.f0.E:", "MOVE    R1, R0"]]
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


def predicted_back_edge() -> None:
    """A conditional jump back at the end of a loop becomes ADD R15, R15,
    top-next, which DECODE predicts taken (doc/MICROARCH.md §5.4), with
    the label next after it, also when an unconditional jump follows. A
    forward jump, and one not marked as a jump back, stay as they were."""
    def back() -> Ins:
        j = Ins("MOVE", ["R15", "W.f0.L1"], "!Z", "jump", ["W.f0.L1"])
        j.back = True
        return j

    forward = Ins("MOVE", ["R15", "W.f0.L2"], "Z", "jump", ["W.f0.L2"])
    plain = Ins("MOVE", ["R15", "W.f0.L1"], "!Z", "jump", ["W.f0.L1"])
    items: List[Item] = [Label("W.f0.L1"), Ins("SUB", ["R1", "R1", "1"]), back(), forward, plain,
                         Ins("MOVE", ["R15", "W.f0.L3"], "", "jump", ["W.f0.L3"]),
                         Label("W.f0.L2"), Label("W.f0.L3")]
    out = predict_back_edges(items, "W.f0.B")
    assert text(out) == ["W.f0.L1:", "SUB     R1, R1, 1", "?!Z     ADD     R15, R15, W.f0.L1-W.f0.B0",
                         "W.f0.B0:", "?Z      MOVE    R15, W.f0.L2", "?!Z     MOVE    R15, W.f0.L1",
                         "MOVE    R15, W.f0.L3", "W.f0.L2:", "W.f0.L3:"], text(out)
    jump = out[2]
    assert isinstance(jump, Ins) and jump.kind == "jump" and jump.targets == ["W.f0.L1", "W.f0.B0"]


def assembled(lines: List[str]) -> List[int]:
    a = niceasm.Assembler()
    errors = a.run([line + "\n" for line in lines + ["x", "f"]], "t.nasm")
    assert not errors, errors
    return [w for _, w in sorted(a.output())]


def pseudo_instructions() -> None:
    """The output's idioms become the pseudo-instructions of ISA.md §10.1,
    which assemble to the same words. A CALL needs its two instructions
    together, with one condition, and the size of the jump as the ADD's
    constant. A line with a comment, or that is no idiom, stays."""
    lines = [instr("ADD", "@--R13", "2", "R15"), instr("MOVE", "R15", "f"),
             instr("?Z ADD", "@--R13", "1", "R15"), instr("?Z MOVE", "R15", "R3"),
             instr("ADD", "@--R13", "2", "R15"), instr("?Z MOVE", "R15", "f"),
             instr("ADD", "@--R13", "1", "R15"), instr("MOVE", "R15", "f"),
             instr("?!C MOVE", "R15", "x"), instr("MOVE", "R15", "@R13++"),
             instr("SUB[M]", "R0", "R1", "7"), instr("MOVE[M]", "R0", "R2"),
             instr("MOVE", "@--R13", "R7"), instr("MOVE", "R7", "@R13++"),
             instr("MOVE", "R4", "0"), instr("MOVE", "R0", "R0"),
             instr("SUB[CM]", "R0", "R1", "7"), instr("MOVE", "R5", "R6"),
             instr("MOVE", "R15", "x") + "  ; jump", "; MOVE R15, x"]
    out = pseudo(lines)
    assert [line.strip() for line in out] == [
        "CALL    f", "?Z      CALL    R3",
        "ADD     @--R13, 2, R15", "?Z      JMP     f",
        "ADD     @--R13, 1, R15", "JMP     f",
        "?!C     JMP     x", "RET", "CMP     R1, 7", "TST     R2",
        "PUSH    R7", "POP     R7", "CLR     R4", "NOP",
        "SUB[CM] R0, R1, 7", "MOVE    R5, R6",
        "MOVE    R15, x  ; jump", "; MOVE R15, x"], out
    assert assembled(out) == assembled(lines)


def anonymous_short_loops() -> None:
    """The labels of a short loop become anonymous (ISA.md §10.1), which
    assembles to the same words: its top, and its exit, that only jumps
    in it name, on the line of the next instruction. A relative jump back
    keeps its top, and its next label becomes ':'. A jump back over more
    than SHORT_LOOP instructions, a label that an operand other than a
    jump's target names, and a function's label keep their names."""
    lines = ["W.f0", "W.f0.L0",
             instr("SUB[M]", "R1", "R1", "1"), instr("?Z JMP", "W.f0.L1"),
             instr("ADD", "R2", "R2", "1"), instr("JMP", "W.f0.L0"),
             "W.f0.L1", instr("MOVE", "R3", "1"),
             "W.f0.L2", instr("SUB[M]", "R3", "R3", "1"),
             instr("?!Z ADD", "R15", "R15", "W.f0.L2-W.f0.B0"), "W.f0.B0",
             "W.f0.L3"] + [instr("ADD", "R4", "R4", "1")] * (SHORT_LOOP + 1) + [
             instr("JMP", "W.f0.L3"),
             "W.f0.L4", instr("MOVE", "R2", "W.f0.L4"), instr("JMP", "W.f0.L4"),
             instr("JMP", "W.f0")]
    out = anonymous_labels(lines)
    assert [line.strip() for line in out] == [
        "W.f0", ":               SUB[M]  R1, R1, 1", "?Z      JMP     :+",
        "ADD     R2, R2, 1", "JMP     :-", ":               MOVE    R3, 1",
        "W.f0.L2", "SUB[M]  R3, R3, 1", "?!Z     ADD     R15, R15, W.f0.L2-:+", ":",
        "W.f0.L3"] + ["ADD     R4, R4, 1"] * (SHORT_LOOP + 1) + [
        "JMP     W.f0.L3", "W.f0.L4", "MOVE    R2, W.f0.L4", "JMP     W.f0.L4",
        "JMP     W.f0"], out
    assert assembled(out) == assembled(lines)


CASES: List[Callable[[], None]] = [anonymous_short_loops, pseudo_instructions, predicted_back_edge, hoist_after_write, hoist_after_jump, tail_call_plain,
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
