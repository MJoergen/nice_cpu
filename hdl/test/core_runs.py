"""Runs programs on the core and on the emulator, for irq_sweep.py and
programs.py.

A run on the core is a run of tb_core in the simulator, GHDL's
--elab-run or nvc's elaboration in memory, with the VHDL analyzed in BUILD
already (hdl/Makefile, SIM), and the core that its generic G_CORE names.
Runs may go in parallel, from threads: each thread runs the simulator in
its own directory under BUILD/WORK, because GHDL's LLVM and GCC backends
write an executable where they run.

Under make with -j, each run on the core or the emulator first takes a
token from make's jobserver, and gives it back after, so that make and
the threads of every script together run at most as many jobs as -j
says. Make gives the jobserver as two descriptors of a pipe,
"--jobserver-auth=R,W" in MAKEFLAGS, which make before 4.2 calls
"--jobserver-fds=R,W", and only to a recipe that it takes for a
recursive make, one with a "+" in front; make 4.4 gives a named pipe,
"fifo:PATH". hdl/Makefile's $(JOBSERVER) is that "+". The script holds
one token already, the one make ran it with, so one run at a time needs
none from the pipe. Without a jobserver, the threads of the pool are the
bound.
"""

import argparse
import contextlib
import os
import select
import shutil
import stat
import subprocess
import threading
from typing import Iterator

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BUILD = os.path.join(HERE, "..", "build")
DEFAULT_EMU = os.path.join(HERE, "..", "..", "emulator", "zig-out", "bin", "niceemu")
DEFAULT_CORE = "pipeline"
SIMS = ["ghdl", "nvc"]


class Jobserver:
    """A client of make's jobserver, from MAKEFLAGS, or none if it has
    none that this process can use."""

    def __init__(self, makeflags: str) -> None:
        self.fds: tuple[int, int] | None = None
        self.free = True  # the token that make ran the script with
        self.lock = threading.Lock()
        names = ("--jobserver-auth=", "--jobserver-fds=")
        auth = [w.split("=", 1)[1] for w in makeflags.split() if w.startswith(names)]
        if not auth:
            return
        if auth[-1].startswith("fifo:"):
            try:
                fd = os.open(auth[-1][5:], os.O_RDWR)
            except OSError:
                return
            self.fds = (fd, fd)
            return
        try:
            r, w = (int(x) for x in auth[-1].split(","))
            if stat.S_ISFIFO(os.fstat(r).st_mode) and stat.S_ISFIFO(os.fstat(w).st_mode):
                self.fds = (r, w)
        except (ValueError, OSError):
            pass

    def acquire(self) -> bytes:
        """Takes a token, waiting for one: b"" for the script's own."""
        with self.lock:
            if self.free or self.fds is None:
                self.free = False
                return b""
        while True:
            select.select([self.fds[0]], [], [])
            try:
                token = os.read(self.fds[0], 1)
            except BlockingIOError:
                continue
            if token:
                return token

    def release(self, token: bytes) -> None:
        if token and self.fds is not None:
            os.write(self.fds[1], token)
        else:
            with self.lock:
                self.free = True

    @contextlib.contextmanager
    def slot(self) -> Iterator[None]:
        """Holds a token while the block runs. Without a jobserver, it
        does nothing."""
        if self.fds is None:
            yield
            return
        token = self.acquire()
        try:
            yield
        finally:
            self.release(token)


JOBSERVER = Jobserver(os.environ.get("MAKEFLAGS", ""))


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
    with JOBSERVER.slot():
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
        with JOBSERVER.slot():
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


def self_test(make: str) -> None:
    """The jobserver client against pipes with tokens in them, a named
    pipe, descriptors that are not pipes, and make itself, the program
    that make names, on hdl/Makefile's jobserver-probe."""
    import tempfile
    import time

    def most_at_once(js: Jobserver, threads: int) -> int:
        lock = threading.Lock()
        now = [0, 0]

        def job() -> None:
            with js.slot():
                with lock:
                    now[0] += 1
                    now[1] = max(now)
                time.sleep(0.05)
                with lock:
                    now[0] -= 1

        pool = [threading.Thread(target=job) for _ in range(threads)]
        for t in pool:
            t.start()
        for t in pool:
            t.join()
        return now[1]

    r, w = os.pipe()
    os.write(w, b"++")
    js = Jobserver(f" -j3 --jobserver-auth={r},{w}")
    assert js.fds == (r, w), js.fds
    assert most_at_once(js, 8) == 3
    os.set_blocking(r, False)
    assert os.read(r, 8) == b"++", "the tokens are given back"
    os.set_blocking(r, True)
    assert js.free, "and the script's own"
    os.close(r)
    os.close(w)
    assert Jobserver(f"--jobserver-auth={r},{w}").fds is None, "closed descriptors"
    with tempfile.TemporaryFile() as f:
        assert Jobserver(f"--jobserver-auth={f.fileno()},{f.fileno()}").fds is None, "not a pipe"
    assert Jobserver(" -j4").fds is None
    r, w = os.pipe()
    assert Jobserver(f" -j3 --jobserver-fds={r},{w}").fds == (r, w), "the name before make 4.2"
    os.close(r)
    os.close(w)
    assert most_at_once(Jobserver(""), 4) == 4, "without a jobserver, the threads are the bound"
    with tempfile.TemporaryDirectory() as d:
        fifo = os.path.join(d, "fifo")
        os.mkfifo(fifo)
        js = Jobserver(f"-j2 --jobserver-auth=fifo:{fifo}")
        assert js.fds is not None
        os.write(js.fds[1], b"+")
        assert most_at_once(js, 5) == 2
        assert Jobserver(f"--jobserver-auth=fifo:{fifo}x").fds is None, "no such pipe"

    # Make itself gives the jobserver to a recipe with hdl/Makefile's
    # $(JOBSERVER) in front, and does not run that recipe under -n or -q.
    def probe(*options: str) -> tuple[str, int]:
        run = subprocess.run([make, "--no-print-directory", "-j3", *options, "jobserver-probe"],
                             cwd=os.path.join(HERE, ".."), capture_output=True, text=True)
        return run.stdout, run.returncode

    assert probe() == ("True\n", 0), probe()
    out, status = probe("-n")
    assert out.endswith("test/core_runs.py --probe\n") and out.count("\n") == 1 and status == 0, out
    assert probe("-q") == ("", 1), probe("-q")
    print("PASS core_runs.py --test")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Tests the client of make's jobserver.")
    parser.add_argument("--make", default="make", help="the make to test with (default make)")
    parser.add_argument("--probe", action="store_true",
                        help="print whether this process has make's jobserver, and do no more")
    main_args = parser.parse_args()
    if main_args.probe:
        print(JOBSERVER.fds is not None)
    else:
        self_test(main_args.make)
