#!/usr/bin/env python3
"""Test niceemu --wav (doc/DEVICES.md §12.3) against the model.

A program writes the registers of DEVICES.md §12.5, one write in a
step, waits with TIME_SKIP while the note sounds, writes the key off,
and waits again. With --step-time, a write in the step whose
microseconds are m lands before the sample floor(m * 3579545 /
64000000), or after the write before it, if that is later; the run
computes the samples up to the microseconds of its halt. The model,
given those writes, must give every sample of the WAV file, and its
header must say so. Then the usage errors of --wav.

--pcm-wav (DEVICES.md §12.7): a program writes PCM_COUNT samples into
the sample player's FIFO, a step each, sets the rate, and waits with
TIME_SKIP. A sample is played at each microsecond m at which
(m - s) * rate reaches another million, for the s of the rate's write,
up to the microseconds of the halt: the FIFO's samples, then the 0s of
the underrun. The header states the rate. A second program changes the
rate, which the header does not follow, and niceemu says so.

Without --wav and a window, nobody takes the samples, and the emulator
computes none (emulator/README.md, Sound). The last check plays the
note and skips 9.5 hours of microseconds, which would be 1.9 billion
samples and minutes of the host's time: the run must end within
QUIET_TIMEOUT seconds, with the status of an empty FIFO.
"""

from __future__ import annotations

import os
import struct
import subprocess
import sys
import tempfile
from typing import List, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import opm_model  # noqa: E402

NICEEMU = os.environ.get("NICEEMU", os.path.join(HERE, "..", "zig-out", "bin", "niceemu"))
NICEASM = os.path.join(HERE, "..", "..", "assembler", "niceasm.py")

WRITES = [0x20C7, 0x284A, 0x607F, 0x687F, 0x707F, 0x5801, 0x981F, 0xF80F, 0x0878]
SKIP_ON = 50000
SKIP_OFF = 20000
QUIET_SKIPS = 8
QUIET_TIMEOUT = 30
PCM_COUNT = 100
PCM_RATE = 8000
PCM_SKIP = 20000

failures: List[str] = []


def program() -> str:
    lines = ["OPM_WRITE       .EQU    0xFFFFFF08", "TIME_SKIP       .EQU    0xFFFFFF5F"]
    for w in WRITES:
        lines.append(f"                MOVE    @OPM_WRITE, 0x{w:04X}")
    lines.append(f"                MOVE    @TIME_SKIP, {SKIP_ON}")
    lines.append("                MOVE    @OPM_WRITE, 0x0800")
    lines.append(f"                MOVE    @TIME_SKIP, {SKIP_OFF}")
    lines.append("                HALT")
    return "\n".join(lines) + "\n"


def quiet_program() -> str:
    """The note, QUIET_SKIPS skips of 2^32 - 1 microseconds, and the status at 0x200."""
    lines = [
        "OPM_WRITE       .EQU    0xFFFFFF08",
        "OPM_STATUS      .EQU    0xFFFFFF09",
        "TIME_SKIP       .EQU    0xFFFFFF5F",
    ]
    for w in WRITES:
        lines.append(f"                MOVE    @OPM_WRITE, 0x{w:04X}")
    for _ in range(QUIET_SKIPS):
        lines.append("                MOVE    @TIME_SKIP, 0xFFFFFFFF")
    lines.append("                MOVE    @0x200, @OPM_STATUS")
    lines.append("                HALT")
    return "\n".join(lines) + "\n"


def pcm_sample(i: int) -> Tuple[int, int]:
    """The i-th sample of the player's program, left and right."""
    left = (i * 331 + 7) % 65536 - 32768
    return left, -1 - left


def pcm_program(change: bool) -> str:
    lines = [
        "PCM_DATA        .EQU    0xFFFFFF0A",
        "PCM_RATE        .EQU    0xFFFFFF0B",
        "TIME_SKIP       .EQU    0xFFFFFF5F",
    ]
    for i in range(PCM_COUNT):
        left, right = pcm_sample(i)
        lines.append(f"                MOVE    @PCM_DATA, 0x{(left & 0xFFFF) << 16 | (right & 0xFFFF):08X}")
    lines.append(f"                MOVE    @PCM_RATE, {PCM_RATE}")
    lines.append(f"                MOVE    @TIME_SKIP, {PCM_SKIP}")
    if change:
        lines.append(f"                MOVE    @PCM_RATE, {2 * PCM_RATE}")
        lines.append("                MOVE    @TIME_SKIP, 1000")
    lines.append("                HALT")
    return "\n".join(lines) + "\n"


def pcm_expected() -> List[Tuple[int, int]]:
    start = PCM_COUNT  # the step of the rate's write
    end = start + 1 + 1 + PCM_SKIP + 1  # after the skip's step, its waits, and the HALT
    played = (end - start) * PCM_RATE // 1000000
    fifo = [pcm_sample(i) for i in range(PCM_COUNT)]
    return (fifo + [(0, 0)] * played)[:played]


def check_pcm(tmp: str) -> None:
    for change in (False, True):
        src = os.path.join(tmp, f"pcm{int(change)}.nasm")
        with open(src, "w") as f:
            f.write(pcm_program(change))
        subprocess.run([sys.executable, NICEASM, src], check=True)
        wav = os.path.join(tmp, "pcm.wav")
        r = run(["--step-time", "--pcm-wav", wav, src[:-5] + ".bin"])
        warned = "the rate changed after the first sample, and the file states 8000 Hz" in r.stderr
        if r.returncode != 0 or warned != change:
            failures.append(f"--pcm-wav, rate changed {change}: exit {r.returncode}, {r.stderr.strip()!r}")
            continue
        if change:
            continue
        header, got = read_wav(wav)
        want = pcm_expected()
        check_header(header, len(want), PCM_RATE)
        if len(want) <= PCM_COUNT:
            failures.append(f"the player's test has no underrun: {len(want)} samples")
        if len(got) != len(want):
            failures.append(f"--pcm-wav: {len(got)} samples, not {len(want)}")
        for n, (g, w) in enumerate(zip(got, want)):
            if g != w:
                failures.append(f"--pcm-wav: sample {n} is {g}, not {w}")
                break
    bin_path = os.path.join(tmp, "pcm0.bin")
    for args, msg in (
        (["--pcm-wav", "x.wav", "--no-sound", bin_path], "--pcm-wav cannot be given with --no-sound"),
        (["--pcm-wav", "x.wav", "--link", "0", bin_path], "--pcm-wav cannot be given with --link or --window"),
    ):
        r = run(args)
        if r.returncode != 1 or msg not in r.stderr:
            failures.append(f"{' '.join(args[:3])}: exit {r.returncode}, {r.stderr.strip()!r}")


def due(us: int) -> int:
    """The samples computed by the microsecond us."""
    return us * 3579545 // 64000000


def expected() -> List[Tuple[int, int]]:
    # The steps, a microsecond each, and their writes.
    times: List[Tuple[int, int]] = [(m, w) for m, w in enumerate(WRITES)]
    m = len(WRITES)  # the TIME_SKIP of SKIP_ON
    m += 1 + SKIP_ON
    times.append((m, 0x0800))
    m += 1  # the TIME_SKIP of SKIP_OFF
    m += 1 + SKIP_OFF
    end = m + 1  # the HALT
    log: List[opm_model.Write] = []
    for t, w in times:
        n = due(t)
        if log and log[-1][0] >= n:
            n = log[-1][0] + 1
        log.append((n, w >> 8, w & 0xFF))
    return opm_model.run(log, due(end))


def read_wav(path: str) -> Tuple[bytes, List[Tuple[int, int]]]:
    with open(path, "rb") as f:
        data = f.read()
    header = data[:44]
    body = data[44:]
    samples = [struct.unpack_from("<hh", body, i) for i in range(0, len(body), 4)]
    return header, samples


def check_header(header: bytes, count: int, rate: int = 55930) -> None:
    riff, size, wave, fmt, fmt_len, pcm, chans, rate, byte_rate, align, bits, data, data_len = struct.unpack(
        "<4sI4s4sIHHIIHH4sI", header
    )
    want = (b"RIFF", 36 + 4 * count, b"WAVE", b"fmt ", 16, 1, 2, rate, 4 * rate, 4, 16, b"data", 4 * count)
    got = (riff, size, wave, fmt, fmt_len, pcm, chans, rate, byte_rate, align, bits, data, data_len)
    if got != want:
        failures.append(f"the header is {got}, not {want}")


def run(args: List[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([NICEEMU] + args, capture_output=True, text=True, stdin=subprocess.DEVNULL)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "play.nasm")
        with open(src, "w") as f:
            f.write(program())
        subprocess.run([sys.executable, NICEASM, src], check=True)
        wav = os.path.join(tmp, "play.wav")
        r = run(["--step-time", "--wav", wav, os.path.join(tmp, "play.bin")])
        if r.returncode != 0:
            failures.append(f"the run exits {r.returncode}: {r.stderr}")
        else:
            header, got = read_wav(wav)
            want = expected()
            check_header(header, len(want))
            if len(got) != len(want):
                failures.append(f"{len(got)} samples, not {len(want)}")
            for n, (g, w) in enumerate(zip(got, want)):
                if g != w:
                    failures.append(f"sample {n} is {g}, not {w}")
                    break
            if max(left for left, _ in got) != 8160:
                failures.append("the note does not sound at its full level")
            if any(s != (0, 0) for s in got[-500:]):
                failures.append("the note does not end after the key off")
        bin_path = os.path.join(tmp, "play.bin")
        for args, msg in (
            (["--wav", wav, "--no-sound", bin_path], "--wav cannot be given with --no-sound"),
            (["--wav", wav, "--link", "0", bin_path], "--wav cannot be given with --link or --window"),
            (["--wav", os.path.join(tmp, "no", "such.wav"), bin_path], "cannot write"),
        ):
            r = run(args)
            if r.returncode != 1 or msg not in r.stderr:
                failures.append(f"{' '.join(args[:3])}: exit {r.returncode}, {r.stderr.strip()!r}")
        check_pcm(tmp)
        src = os.path.join(tmp, "quiet.nasm")
        with open(src, "w") as f:
            f.write(quiet_program())
        subprocess.run([sys.executable, NICEASM, src], check=True)
        # With --no-sound the words are memory, and 0xFFFFFF09 reads 0.
        for opts, status in (([], "21510000"), (["--no-sound"], "00000000")):
            args = ["--step-time", *opts, "-d", "0x200:1", os.path.join(tmp, "quiet.bin")]
            what = " ".join(args[:-1])
            try:
                r = subprocess.run(
                    [NICEEMU] + args, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=QUIET_TIMEOUT
                )
            except subprocess.TimeoutExpired:
                failures.append(f"{what}: the skips take more than {QUIET_TIMEOUT} s without --wav")
                continue
            if r.returncode != 0 or f"00000200: {status}" not in r.stdout:
                failures.append(f"{what}: exit {r.returncode}, {r.stdout.strip()!r} {r.stderr.strip()!r}")
    for failure in failures:
        print("FAIL wav:", failure)
    if failures:
        return 1
    print("PASS wav")
    return 0


if __name__ == "__main__":
    sys.exit(main())
