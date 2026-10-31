# Toolchain

There are six tools. Five run on the host, and one is NICE assembly that
is joined into every program. Each follows one part of
[ISA.md](ISA.md).

| Tool | Where | Written in | Reads | Writes | Follows |
|---|---|---|---|---|---|
| `niceasm`, the assembler | [assembler/niceasm.py](../assembler/niceasm.py) | Python 3, standard library only | `.nasm` | `.bin` | ISA.md §10 |
| `nicedis`, the disassembler | [assembler/nicedis.py](../assembler/nicedis.py) | Python 3, standard library only | `.bin` and `.sym` | `.nasm` | ISA.md §10 |
| `niceemu`, the emulator | [emulator/](../emulator/) | Zig 0.17 | `.bin` | Console output, the registers, memory dumps, and a trace | ISA.md §1–8, SYSTEM.md, DEBUG.md |
| The runtime library | [runtime/](../runtime/) | NICE assembly | | | ABI.md and WASM.md |
| `nicewasm`, the wasm translator | [translator/nicewasm.py](../translator/nicewasm.py) | Python 3, standard library only | `.wasm` | `.nasm` | WASM.md |
| `nicebuild`, the build script | [translator/nicebuild.py](../translator/nicebuild.py) | Python 3, standard library only | `.c`, `.zig`, or `.rs` | `.bin` | translator README |

A program is built in these steps. There is no linker. The pieces are
assembly files, joined with `cat` in the order ABI.md gives, and the
whole program is assembled at once.

    prog.c, prog.zig, or prog.rs
        |  clang, zig, or rustc, with a wasm32 target
        v
    prog.wasm
        |  translator/nicewasm.py
        v
    prog.nasm
        |
        |  cat, in this order: runtime/start_wasm.nasm (or start.nasm for a
        |  program with no wasm module, or their _mon versions for a program
        |  that a monitor in ROM runs), hand-written .nasm files, prog.nasm,
        |  runtime/lib.nasm, runtime/muldiv_mpu.nasm (or muldiv_soft.nasm
        |  without the math unit), and runtime/float.nasm if prog uses floats
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
[quick start](../README.md#quick-start). The
[translator README](../translator/README.md) gives the exact clang, Zig, and Rust
command lines for the first step, and the [runtime README](../runtime/README.md)
the join.

`translator/nicebuild.py` runs all of these steps for a C, Zig, or Rust
source file, and writes the `.bin` file:

    translator/nicebuild.py -o prog.bin prog.c

**How the tools use each other.**

- `niceemu` runs the `.bin` files that `niceasm` writes. Its probe programs
  are assembled with `niceasm` (`make bins`), and its tests also run the
  assembler's example programs.
- The runtime library's start-up code calls `_main`, and `start_wasm.nasm`
  first calls the `___wasm_start` that `nicewasm` emits. Translated code
  uses the math unit through the labels in `muldiv_mpu.nasm` for `i32.mul`
  and the divisions, or calls `__mul`, `__div`, and the like with
  `--no-mpu`, and traps through `___wasm_trap_vector`. A C compiler for
  NICE would call the same routines.
- The float routines are themselves translated by `nicewasm`: `runtime/
  float.zig` and parts of Zig's compiler_rt are compiled to
  `runtime/float.wasm`, and `nicewasm --library float` turns that into
  `runtime/float.nasm` (`make -C runtime float.nasm`).
- The tests of the runtime use `niceasm` and `niceemu`. The tests of
  `nicewasm` use all three other tools: they translate each module, join it
  with the runtime, assemble it, and run it.
- `nicedis` reads the `.bin` files of `niceasm` and the symbols files of
  `niceasm --symbols` and `nicebuild.py --symbols`. `niceasm` assembles
  its output back to the same words. Host tools import its
  `disassemble()`.
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
functions, `malloc`, and a few more. It is compiled to wasm with the
program, so it is not one of the joined files.

**Host tools.** Python 3 runs `niceasm`, `nicedis`, `nicewasm`, and the test scripts.
Nothing beyond the standard library is needed, and `make typecheck` checks
the Python with `mypy --strict` if mypy is installed. Zig 0.17 builds
`niceemu` and compiles the Zig test modules. clang with the wasm32 target,
`wasm-ld`, and `llvm-ar`, and rustc with the `wasm32-unknown-unknown` target, are
needed only for `make wasm` in `translator/`, which rebuilds the compiled
test modules. Their `.wasm` files are checked in, so `make test` needs no
C or Rust compiler. The same holds for the C library's tests in
`runtime/libc/`, which `make -C runtime/libc wasm` rebuilds. If `llvm-ar` has
another name, set `AR`. The tests use
`make`, `cat`, `cmp`, `diff`, `sed`, `grep`, `cut`, and `nproc`. GitHub Actions runs every `make test` and
`make typecheck`, the document checks, `make programs` on both cores, `make lint`,
`make formal`, and `make pdfcheck` on each push.
