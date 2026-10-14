"""Builds small wasm modules for the tests, byte by byte."""

from __future__ import annotations

from typing import Sequence, Tuple

I32, I64, F32, F64 = 0x7F, 0x7E, 0x7D, 0x7C


def u(n: int) -> bytes:
    """Unsigned LEB128."""
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def s(n: int) -> bytes:
    """Signed LEB128."""
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if (n == 0 and not b & 0x40) or (n == -1 and b & 0x40):
            out.append(b)
            return bytes(out)
        out.append(b | 0x80)


def vec(items: Sequence[bytes]) -> bytes:
    return u(len(items)) + b"".join(items)


def name(x: str) -> bytes:
    return u(len(x.encode())) + x.encode()


def section(sec_id: int, payload: bytes) -> bytes:
    return bytes([sec_id]) + u(len(payload)) + payload


def module(*sections: bytes) -> bytes:
    return b"\0asm\1\0\0\0" + b"".join(sections)


def types(*fts: Tuple[Sequence[int], Sequence[int]]) -> bytes:
    return section(1, vec([b"\x60" + vec([bytes([t]) for t in p]) + vec([bytes([t]) for t in r])
                           for p, r in fts]))


def imports(*imps: Tuple[str, str, int]) -> bytes:
    """Function imports: (module, name, type index)."""
    return section(2, vec([name(m) + name(n) + b"\0" + u(t) for m, n, t in imps]))


def funcs(*type_idxs: int) -> bytes:
    return section(3, vec([u(t) for t in type_idxs]))


def memory(pages: int) -> bytes:
    return section(5, vec([b"\0" + u(pages)]))


def globals_(*inits: int) -> bytes:
    """Mutable i32 globals."""
    return section(6, vec([bytes([I32, 1, 0x41]) + s(i) + b"\x0b" for i in inits]))


def exports(*exps: Tuple[str, int, int]) -> bytes:
    """(name, kind, index), where kind 0 is a function and 3 a global."""
    return section(7, vec([name(n) + bytes([k]) + u(i) for n, k, i in exps]))


def start(idx: int) -> bytes:
    return section(8, u(idx))


def code(*bodies: Tuple[int, bytes]) -> bytes:
    """(number of i32 locals, instructions without the final end)."""
    out = []
    for n_locals, body in bodies:
        b = (vec([u(n_locals) + bytes([I32])]) if n_locals else vec([])) + body + b"\x0b"
        out.append(u(len(b)) + b)
    return section(10, vec(out))


# Instructions
def i32_const(n: int) -> bytes:
    return b"\x41" + s(n)


def local_get(i: int) -> bytes:
    return b"\x20" + u(i)


def local_set(i: int) -> bytes:
    return b"\x21" + u(i)


def local_tee(i: int) -> bytes:
    return b"\x22" + u(i)


def global_get(i: int) -> bytes:
    return b"\x23" + u(i)


def global_set(i: int) -> bytes:
    return b"\x24" + u(i)


def call(i: int) -> bytes:
    return b"\x10" + u(i)


NOP, DROP, RETURN = b"\x01", b"\x1a", b"\x0f"
ADD, SUB, MUL, AND, OR, XOR = b"\x6a", b"\x6b", b"\x6c", b"\x71", b"\x72", b"\x73"
