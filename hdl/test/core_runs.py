"""Runs programs on the core and on the emulator, for irq_sweep.py and
programs.py.

A run on the core is GHDL's --elab-run of tb_core, with the VHDL analyzed
in BUILD already, and the core that its generic G_CORE names. Runs may go
in parallel, from threads: each thread runs GHDL in its own directory
under BUILD/WORK, because GHDL's LLVM and GCC backends write an executable
where they run.
"""

import os
import shutil
import subprocess
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BUILD = os.path.join(HERE, "..", "build")
DEFAULT_EMU = os.path.join(HERE, "..", "..", "emulator", "zig-out", "bin", "niceemu")
DEFAULT_CORE = "multicycle"


def run_emulator(emu: str, binfile: str, opts: list[str]) -> str:
    """The trace and the output of "niceemu -t", and its exit status. A
    program may write any byte to the console, so the output is not
    always UTF-8."""
    r = subprocess.run(
        [emu, "-t", *opts, binfile], stdin=subprocess.DEVNULL, capture_output=True, text=True,
        errors="replace"
    )
    return r.stdout + f"exit {r.returncode}\n"


class Core:
    """Runs a core in tb_core, each thread in its own directory."""

    def __init__(self, ghdl: str, build: str, work: str, core: str = DEFAULT_CORE) -> None:
        self.ghdl = ghdl
        self.core = core
        self.build = os.path.abspath(build)
        self.root = os.path.join(self.build, work)
        self.local = threading.local()
        self.count = 0
        self.lock = threading.Lock()

    def directory(self) -> str:
        d: str | None = getattr(self.local, "dir", None)
        if d is None:
            with self.lock:
                self.count += 1
                d = os.path.join(self.root, str(self.count))
            os.makedirs(d, exist_ok=True)
            self.local.dir = d
        return d

    def run(self, binfile: str, generics: list[str]) -> str:
        """The trace and the output of the core, in the form of
        run_emulator's. generics are more -gNAME=VALUE options."""
        return self.run_logged(binfile, generics)[0]

    def run_logged(self, binfile: str, generics: list[str]) -> tuple[str, str]:
        """The same, and the interrupt log of tb_core's G_INTR_LOG,
        which is empty when no request was raised."""
        d = self.directory()
        trace = os.path.join(d, "core.out")
        log = os.path.join(d, "intr.log")
        cmd = [
            self.ghdl, "--elab-run", "--std=08", "--workdir=" + self.build, "tb_core",
            "-gG_CORE=" + self.core, "-gG_BIN_FILE=" + os.path.abspath(binfile),
            "-gG_TRACE_FILE=" + trace, "-gG_INTR_LOG=" + log, *generics,
        ]
        for path in (trace, log):
            if os.path.exists(path):
                os.remove(path)
        r = subprocess.run(cmd, cwd=d, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        if not os.path.exists(trace):
            return f"no trace from GHDL, exit {r.returncode}\n" + r.stdout + r.stderr, ""
        with open(trace, errors="replace") as f:
            out = f.read()
        if r.returncode not in (0, 2, 3):
            out += r.stdout + r.stderr
        intr = ""
        if os.path.exists(log):
            with open(log) as f:
                intr = f.read()
        return out + f"exit {r.returncode}\n", intr

    def clean(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def difference(expected: str, got: str) -> str | None:
    """None if the two runs are the same, or where they differ."""
    if got == expected:
        return None
    e, g = expected.splitlines(), got.splitlines()
    i = next((i for i, (a, b) in enumerate(zip(e, g)) if a != b), min(len(e), len(g)))
    return f"the traces differ at line {i + 1}\n" + "\n".join(
        [f"  emulator: {line}" for line in e[i : i + 3]]
        + [f"  core:     {line}" for line in g[i : i + 3]]
    )
