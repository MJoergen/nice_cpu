"""Builds small wasm modules for the tests, byte by byte."""

from __future__ import annotations

from typing import Dict, Sequence, Tuple, Union

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


def s(n: int, length: int = 0) -> bytes:
    """Signed LEB128, padded to length bytes if that is more than it needs.
    LLVM pads some numbers, and a padded encoding is valid."""
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        done = (n == 0 and not b & 0x40) or (n == -1 and b & 0x40)
        if done and len(out) + 1 >= length:
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


def typed_globals(*gs: Tuple[int, bool, int]) -> bytes:
    """Globals of any integer type: (type, mutable, initial value)."""
    return section(6, vec([bytes([t, int(m), 0x41 if t == I32 else 0x42]) + s(i) + b"\x0b"
                           for t, m, i in gs]))


def exports(*exps: Tuple[str, int, int]) -> bytes:
    """(name, kind, index), where kind 0 is a function and 3 a global."""
    return section(7, vec([name(n) + bytes([k]) + u(i) for n, k, i in exps]))


def start(idx: int) -> bytes:
    return section(8, u(idx))


def code(*bodies: Tuple[Union[int, Sequence[int]], bytes]) -> bytes:
    """(number of i32 locals, or the type of each local, instructions
    without the final end)."""
    out = []
    for local_types, body in bodies:
        if isinstance(local_types, int):
            local_types = [I32] * local_types
        b = vec([u(1) + bytes([t]) for t in local_types]) + body + b"\x0b"
        out.append(u(len(b)) + b)
    return section(10, vec(out))


def names(funcs: Dict[int, str]) -> bytes:
    """A name section with the given function names."""
    sub = vec([u(i) + name(n) for i, n in sorted(funcs.items())])
    return section(0, name("name") + b"\x01" + u(len(sub)) + sub)


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


def i64_const(n: int, length: int = 0) -> bytes:
    return b"\x42" + s(n, length)


NOP, DROP, RETURN = b"\x01", b"\x1a", b"\x0f"
UNREACHABLE = b"\x00"
ADD, SUB, MUL, AND, OR, XOR = b"\x6a", b"\x6b", b"\x6c", b"\x71", b"\x72", b"\x73"
ADD64, SUB64, AND64, OR64, XOR64 = b"\x7c", b"\x7d", b"\x83", b"\x84", b"\x85"
WRAP, EXTEND_S, EXTEND_U = b"\xa7", b"\xac", b"\xad"


def block(bt: Union[int, None] = None) -> bytes:
    """block with a block type: None for no values, a value type for one
    result, or typeidx(i) for the function type i."""
    return b"\x02" + blocktype(bt)


def loop(bt: Union[int, None] = None) -> bytes:
    return b"\x03" + blocktype(bt)


def if_(bt: Union[int, None] = None) -> bytes:
    return b"\x04" + blocktype(bt)


def blocktype(bt: Union[int, None]) -> bytes:
    if bt is None:
        return b"\x40"
    return s(bt - 0x100) if bt >= 0x100 else bytes([bt])


def typeidx(i: int) -> int:
    """A block type that names the function type i. Pass it to block, loop,
    or if_."""
    return 0x100 + i


def br(i: int) -> bytes:
    return b"\x0c" + u(i)


def br_if(i: int) -> bytes:
    return b"\x0d" + u(i)


def br_table(labels: Sequence[int], default: int) -> bytes:
    return b"\x0e" + vec([u(i) for i in labels]) + u(default)


def select_t(t: int) -> bytes:
    """The typed select."""
    return b"\x1c" + vec([bytes([t])])


ELSE, END, SELECT = b"\x05", b"\x0b", b"\x1b"
EQZ, EQ, NE, LT_S, LT_U, GT_S, GT_U, LE_S, LE_U, GE_S, GE_U = (bytes([op]) for op in range(0x45, 0x50))
EQZ64, EQ64, NE64, LT_S64, LT_U64, GT_S64, GT_U64, LE_S64, LE_U64, GE_S64, GE_U64 = (
    bytes([op]) for op in range(0x50, 0x5B))


def mem(op: int, offset: int = 0, align: int = 0) -> bytes:
    """A load or a store, by its opcode."""
    return bytes([op]) + u(align) + u(offset)


I32_LOAD, I64_LOAD = 0x28, 0x29
I32_LOAD8_S, I32_LOAD8_U, I32_LOAD16_S, I32_LOAD16_U = 0x2C, 0x2D, 0x2E, 0x2F
I64_LOAD8_S, I64_LOAD8_U, I64_LOAD16_S, I64_LOAD16_U, I64_LOAD32_S, I64_LOAD32_U = range(0x30, 0x36)
I32_STORE, I64_STORE, I32_STORE8, I32_STORE16 = 0x36, 0x37, 0x3A, 0x3B
I64_STORE8, I64_STORE16, I64_STORE32 = 0x3C, 0x3D, 0x3E
MEMORY_SIZE, MEMORY_GROW = b"\x3f\x00", b"\x40\x00"


def data(*segs: Tuple[int, bytes]) -> bytes:
    """Active data segments: (byte offset, bytes)."""
    return section(11, vec([b"\0" + b"\x41" + s(off) + b"\x0b" + u(len(d)) + d for off, d in segs]))
