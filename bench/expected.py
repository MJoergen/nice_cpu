#!/usr/bin/env python3
"""The expected results of the phases of bench.c, computed in Python.

    ./expected.py [bench.c]                  print the EXPECT defines
    ./expected.py --check bench.c [hand.nasm]  fail if a file has other values

The sizes are read from the defines in bench.c, the first file, so that
the two cannot disagree. hand.nasm has the same values as .EQU lines. Each phase is written again here from its description, not
copied from the C, so that a wrong result in the C is caught.
"""

import re
import sys
import zlib
from typing import Dict, List, Optional

MASK = 0xFFFFFFFF
MASK64 = 0xFFFFFFFFFFFFFFFF
FNV_BASIS = 0x811C9DC5
FNV_PRIME = 16777619
SEED = 0x9E3779B97F4A7C15


def signed32(x: int) -> int:
    x &= MASK
    return x - (1 << 32) if x >= (1 << 31) else x


class Rng:
    """xorshift64*."""

    def __init__(self, state: int) -> None:
        self.state = state

    def next64(self) -> int:
        x = self.state
        x ^= x >> 12
        x ^= (x << 25) & MASK64
        x ^= x >> 27
        self.state = x
        return (x * 0x2545F4914F6CDD1D) & MASK64


def phase_rng64(buf: bytearray, arr: List[int], rng: Rng) -> int:
    for i in range(len(buf) // 8):
        buf[8 * i:8 * i + 8] = rng.next64().to_bytes(8, "little")
    for i in range(len(arr)):
        arr[i] = signed32(rng.next64() >> 32)
    return (rng.state ^ (rng.state >> 32)) & MASK


def phase_crc32(buf: bytearray) -> int:
    return zlib.crc32(bytes(buf)) & MASK


class Node:
    def __init__(self, key: int) -> None:
        self.key = key
        self.count = 1
        self.left: Optional[Node] = None
        self.right: Optional[Node] = None


def phase_bst(arr: List[int]) -> int:
    root: Optional[Node] = None
    for key in arr:
        if root is None:
            root = Node(key)
            continue
        n = root
        while True:
            if key == n.key:
                n.count += 1
                break
            if key < n.key:
                if n.left is None:
                    n.left = Node(key)
                    break
                n = n.left
            else:
                if n.right is None:
                    n.right = Node(key)
                    break
                n = n.right

    def walk(n: Optional[Node], depth: int, h: int) -> int:
        if n is None:
            return h
        h = walk(n.left, depth + 1, h)
        h = ((h ^ (n.key & MASK)) * FNV_PRIME + depth * n.count) & MASK
        return walk(n.right, depth + 1, h)

    return walk(root, 1, FNV_BASIS)


def phase_heapsort(arr: List[int]) -> int:
    arr.sort()
    h = FNV_BASIS
    for x in arr:
        h = ((h ^ (x & MASK)) * FNV_PRIME) & MASK
    return h


def phase_vm(loops: int) -> int:
    acc = 0
    for i in range(loops):
        acc = ((acc * 31) ^ i) & MASK
    return acc


def phase_strings(buf: bytearray, count: int, maxlen: int) -> int:
    strs = []
    for j in range(count):
        b = buf[16 * j:16 * j + 16]
        length = 4 + b[0] % (maxlen - 3)
        strs.append(bytes(ord("a") + b[1 + k] % 26 for k in range(length)))
    joined = b"".join(sorted(strs))
    h = FNV_BASIS
    for c in joined:
        h = ((h ^ c) * FNV_PRIME) & MASK
    # "ab" cannot overlap itself, so count() finds every match that strstr
    # does.
    return (h + len(joined) * 65599 + joined.count(b"ab")) & MASK


def sizes(source: str) -> Dict[str, int]:
    found = dict(re.findall(r"^#define (BUF_BYTES|ARR_WORDS|VM_LOOPS|STR_COUNT|STR_MAXLEN) (\d+)",
                            source, re.M))
    missing = {"BUF_BYTES", "ARR_WORDS", "VM_LOOPS", "STR_COUNT", "STR_MAXLEN"} - set(found)
    if missing:
        sys.exit(f"expected.py: no define for {', '.join(sorted(missing))}")
    return {k: int(v) for k, v in found.items()}


def expected(s: Dict[str, int]) -> Dict[str, int]:
    buf = bytearray(s["BUF_BYTES"])
    arr = [0] * s["ARR_WORDS"]
    out = {}
    out["RNG64"] = phase_rng64(buf, arr, Rng(SEED))
    out["CRC32"] = phase_crc32(buf)
    out["BST"] = phase_bst(arr)
    out["HEAPSORT"] = phase_heapsort(arr)
    out["VM"] = phase_vm(s["VM_LOOPS"])
    out["STRINGS"] = phase_strings(buf, s["STR_COUNT"], s["STR_MAXLEN"])
    return out


def check(path: str, values: Dict[str, int]) -> bool:
    """Whether the EXPECT values in path, a C or an assembly file, are the
    ones computed here. Prints each one that is not."""
    source = open(path).read()
    good = True
    for name, value in values.items():
        m = re.search(rf"^#define EXPECT_{name} 0x([0-9A-Fa-f]+)u"
                      rf"|^EXPECT_{name}\s+\.EQU\s+0x([0-9A-Fa-f]+)", source, re.M)
        have = int(m.group(1) or m.group(2), 16) if m else None
        if have is None:
            print(f"{path}: no EXPECT_{name}")
            good = False
        elif have != value:
            print(f"{path}: EXPECT_{name} is {have:#010x}, expected.py gets {value:#010x}")
            good = False
    return good


def main() -> None:
    args = sys.argv[1:]
    checking = bool(args) and args[0] == "--check"
    if checking:
        args = args[1:]
    source_path = args[0] if args else "bench.c"
    values = expected(sizes(open(source_path).read()))
    if not checking:
        for name, value in values.items():
            print(f"#define EXPECT_{name} 0x{value:08X}u")
        return
    if not all([check(path, values) for path in args or ["bench.c"]]):
        sys.exit(1)
    print(f"PASS expected.py: {', '.join(args or ['bench.c'])} "
          f"{'has' if len(args) < 2 else 'have'} the values of expected.py")


if __name__ == "__main__":
    main()
