# Toolchain

There are eight tools. Seven run on the host, and one is NICE assembly that
is joined into every program. Each follows one part of
[ISA.md](ISA.md).

| Tool | Where | Written in | Reads | Writes | Follows |
|---|---|---|---|---|---|
| `niceasm`, the assembler | [assembler/niceasm.py](../assembler/niceasm.py) | Python 3, standard library only | `.nasm` | `.bin` | ISA.md §10 |
| `nicedis`, the disassembler | [assembler/nicedis.py](../assembler/nicedis.py) | Python 3, standard library only | `.bin` and `.sym` | `.nasm` | ISA.md §10 |
| `niceemu`, the emulator | [emulator/](../emulator/) | Zig 0.17 | `.bin` | Console output, the registers, memory dumps, and a trace | ISA.md §1–8, DEVICES.md, DEBUG.md |
| `nicetap`, the TAP bridge | [emulator/tools/nicetap.py](../emulator/tools/nicetap.py) | Python 3, standard library only | Frames from a TAP device and niceemu's UDP socket | The same frames, the other way | DEVICES.md §7 |
| `nicedbg`, the debugger | [debugger/nicedbg.py](../debugger/nicedbg.py) | Python 3, standard library only | `.bin` and `.sym` | Commands to a system on the debug link | DEBUG.md |
| The runtime library | [runtime/](../runtime/) | NICE assembly | | | ABI.md and WASM.md |
| `nicewasm`, the wasm translator | [translator/nicewasm.py](../translator/nicewasm.py) | Python 3, standard library only | `.wasm` | `.nasm` | WASM.md |
| `nicebuild`, the build script | [translator/nicebuild.py](../translator/nicebuild.py) | Python 3, standard library only | `.c`, `.zig`, or `.rs` | `.bin` | translator README |

A program is built in these steps. There is no linker. The pieces are
assembly files, joined with `cat` in the order the runtime README gives
([Joining a program](../runtime/README.md#joining-a-program)), and the
whole program is assembled at once.

    prog.c, prog.zig, or prog.rs
        |  clang, zig, or rustc, with a wasm32 target
        v
    prog.wasm
        |  translator/nicewasm.py
        v
    prog.nasm
        |
        |  cat, in the order of the runtime README (Joining a program):
        |  a start-up file, hand-written .nasm files, prog.nasm, and
        |  the runtime library
        v
    full.nasm
        |  assembler/niceasm.py
        v
    full.bin
        |  emulator/zig-out/bin/niceemu, or the FPGA core
        v
    console output, the registers, and an exit status

A hand-written program that does not use the runtime library needs only
the last two steps, as in the
[worked example](../README.md#worked-example). The
[translator README](../translator/README.md) gives the exact clang, Zig, and Rust
command lines for the first step, and the [runtime README](../runtime/README.md#joining-a-program)
the join.

`translator/nicebuild.py` runs all of these steps for a C, Zig, or Rust
source file, and writes the `.bin` file:

    translator/nicebuild.py -o prog.bin prog.c

A monitor is a program in a ROM at address 0 that loads a program at
`0x8000` and calls it, as NiceMonMEGA65's does. `nicebuild.py --monitor`
builds a program for one: it picks the `_mon` start-up file
([ABI.md](../runtime/ABI.md), Programs under a monitor).

**How the tools use each other.**

- `niceemu` runs the `.bin` files that `niceasm` writes. Its probe programs
  are assembled with `niceasm` (`make bins`), and its tests also run the
  assembler's example programs.
- The runtime library's start-up code calls `_main` (a C name `f` is the
  label `_f`, ABI.md), and `start_wasm.nasm`
  first calls the `___wasm_start` that `nicewasm` emits. Translated code
  uses the math unit through the labels in `muldiv_mpu.nasm` for `i32.mul`
  and the divisions, or calls `__mul`, `__div`, and the like with
  `--no-mpu`, and traps through `___wasm_trap_vector`. A C compiler for
  NICE would call the same routines.
- Translated code calls the float library for its float operations.
  There are two, with the same labels. `runtime/float_fpu.nasm`, written
  by hand, uses the FPU (DEVICES.md §11), and `nicebuild.py` joins it.
  `runtime/float.nasm` computes in software, for a system without the
  FPU, and `nicebuild.py --no-fpu` joins it instead. It is itself
  translated by `nicewasm`: `runtime/float.zig` and parts of Zig's
  compiler_rt are compiled to `runtime/float.wasm`, and
  `nicewasm --library float` turns that into `runtime/float.nasm`
  (`make -C runtime float.nasm`).
- With `--inline-fpu`, `nicewasm` writes the FPU's accesses inline, in
  place of most calls of `float_fpu.nasm`, which is still joined.
  `nicebuild.py --inline-fpu` passes the option on.
- The tests of the runtime and the benchmarks join `float_fpu.nasm`, and
  with `NO_FPU=1` `float.nasm`: `make -C runtime test NO_FPU=1`. The
  float benchmark runs both ways, and its build with `float.nasm` goes
  to `bench/build/nofpu/`.
- The tests of the runtime use `niceasm` and `niceemu`. The tests of
  `nicewasm` use all three other tools: they translate each module, join it
  with the runtime, assemble it, and run it.
- `nicedis` reads the `.bin` files of `niceasm` and the symbols files of
  `niceasm --symbols` and `nicebuild.py --symbols`. `niceasm` assembles
  its output back to the same words. Host tools import its
  `disassemble()`.
- `nicedbg` loads the `.bin` files of `niceasm` into `niceemu --link`, or
  a board, over the debug link, and disassembles with `nicedis`, with the
  labels of the symbols files. Its tests use `niceasm` and `niceemu`.
- `nicetap` joins the UDP socket of `niceemu --eth-udp` to a TAP device on
  Linux, so that a program in the emulator is on a real network. Its test
  uses `niceasm`, `niceemu`, `unshare`, and `ip`.
- The `.bin` format is the text format of the 2004 `NICE.pm` assembler, so
  its example binaries can be compared directly.
- The FPGA cores take the place of `niceemu` at the end of the pipeline.
  `hdl/` runs the same programs on them in simulation, in GHDL or nvc, and
  compares their traces with the emulator's: `emulator/test/cputest.nasm`
  and the `--trace` format are there for that, and `make -C hdl programs`
  simulates a core running the runtime's and the translator's test
  programs. No test runs on an FPGA board.

**Compilers.** No compiler targets NICE directly
[yet](https://github.com/MJoergen/nice_cpu/issues/66). ABI.md defines the C ABI for one, with a
one-word `char` and `CHAR_BIT` = 32. Until there is one, compiled code
reaches NICE through WebAssembly: clang (with `wasm-ld`), Zig, and Rust
all have a wasm32 target, and `nicewasm` translates the compiler's
`.wasm` output into NICE assembly. That gives C code the 8-bit bytes of
wasm linear memory, which Rust and Zig need anyway. GCC has no wasm32
target and no NICE target, so it is not used. All three are tested. C
programs can use the small C library in
[runtime/libc/](../runtime/README.md#c-library): `printf`, the `string.h`
functions, `malloc`, the `math.h` functions, and a few more. It is compiled to wasm with the
program, so it is not one of the joined files.

**Host tools.** Python 3 runs `niceasm`, `nicedis`, `nicedbg`, `nicetap`, `nicewasm`, and the test scripts.
Nothing beyond the standard library is needed, and `make typecheck` checks
the Python with `mypy --strict` if mypy is installed. Zig 0.17 builds
`niceemu` and compiles the Zig test modules. clang with the wasm32 target,
`wasm-ld`, and `llvm-ar`, and rustc with the `wasm32-unknown-unknown` target, are
needed only for `make wasm` in `translator/`, which rebuilds the compiled
test modules. Their `.wasm` files are checked in, so `make test` needs no
C or Rust compiler. The same holds for the C library's tests in
`runtime/libc/`, which `make -C runtime/libc wasm` rebuilds. If `llvm-ar` has
another name, set `AR`. The tests use
`make`, `cat`, `cmp`, `diff`, `sed`, `grep`, `cut`, and `nproc`.

The cores need more. GHDL runs their tests, and nvc the long simulations;
vsg checks the VHDL style, SymbiYosys with Yosys and its solvers runs the
formal checks, and Vivado 2025.1 the timing run
([hdl/README.md](../hdl/README.md#running-the-tests) gives the versions).
A build of `niceemu` with `-Dwindow` compiles SDL 3 from source, which
Zig fetches, so it needs no system package
([emulator/README.md](../emulator/README.md#window)). The slides and the
diagrams of `doc/` need pdflatex, and the diagrams pdftoppm. GitHub
Actions runs every `make test` and `make typecheck`, `make window-test`,
the document checks, `make programs` on both cores, `make lint`,
`make formal`, and `make pdfcheck` on each push. On a tag, it runs
`make -C emulator dist` and attaches the two builds of niceemu to the
release ([emulator/README.md](../emulator/README.md#download)).
