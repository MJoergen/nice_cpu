"""Runs programs on the core and on the emulator, for irq_sweep.py and
programs.py.

A run on the core is a run of tb_core in the simulator, GHDL's
--elab-run or nvc's elaboration in memory, with the VHDL analyzed in BUILD
already (hdl/Makefile, SIM), and the core that its generic G_CORE names.
Runs may go in parallel, from threads: each thread runs the simulator in
its own directory under BUILD/WORK, because GHDL's LLVM and GCC backends
write an executable where they run.
"""

import argparse
import os
import shutil
import subprocess
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BUILD = os.path.join(HERE, "..", "build")
DEFAULT_EMU = os.path.join(HERE, "..", "..", "emulator", "zig-out", "bin", "niceemu")
DEFAULT_CORE = "pipeline"
SIMS = ["ghdl", "nvc"]


def add_sim_args(p: argparse.ArgumentParser) -> None:
    """The options that choose the simulator, as hdl/Makefile passes them."""
    p.add_argument("--sim", choices=SIMS, default="ghdl", help="the simulator (default ghdl)")
    p.add_argument("--ghdl", default=os.environ.get("GHDL", "ghdl"))
    p.add_argument("--nvc", default=os.environ.get("NVC", "nvc"))


def sim_command(sim: str, tool: str, build: str, unit: str, generics: list[str]) -> list[str]:
    """The command that runs the testbench unit with the generics, in the
    simulator sim, whose program is tool, with the VHDL analyzed in build,
    and the options of hdl/sim.mk."""
    if sim == "nvc":
        work = os.path.join(build, "nvc")
        return [tool, "--std=2008", "--work=work:" + work, "-H", "1g",
                "-e", "--jit", "--no-save", *generics, unit, "-r"]
    return [tool, "--elab-run", "--std=08", "--workdir=" + build, unit, *generics]


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

    def __init__(self, args: argparse.Namespace, build: str, work: str, core: str = DEFAULT_CORE) -> None:
        """args holds the options of add_sim_args."""
        self.sim: str = args.sim
        self.tool: str = args.nvc if self.sim == "nvc" else args.ghdl
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
        cmd = sim_command(self.sim, self.tool, self.build, "tb_core", [
            "-gG_CORE=" + self.core, "-gG_BIN_FILE=" + os.path.abspath(binfile),
            "-gG_TRACE_FILE=" + trace, "-gG_INTR_LOG=" + log, *generics,
        ])
        for path in (trace, log):
            if os.path.exists(path):
                os.remove(path)
        r = subprocess.run(cmd, cwd=d, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        if not os.path.exists(trace):
            return f"no trace from {self.sim}, exit {r.returncode}\n" + r.stdout + r.stderr, ""
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
