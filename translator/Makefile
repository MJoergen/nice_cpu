PYTHON ?= python3
CLANG ?= clang
ZIG ?= zig
RUSTC ?= rustc

# The modules compiled from test/*.c, test/*.zig, and test/*.rs. Their .wasm files are
# checked in, so make test needs no compiler; make wasm rebuilds them. The
# options keep the linear memory to one page. -mbulk-memory makes clang
# emit memory.copy and memory.fill, not imports of memcpy and memset that
# nothing defines, and --stack-first makes a stack overflow trap instead
# of overwriting the data (see README.md). ZIG_SAFE_TESTS are built with
# ReleaseSafe and a 16 KB stack, because Zig's panic handler puts a 4 KB
# buffer on the stack.
C_TESTS = sum5 control memory data shifts intops floats primes
ZIG_TESTS = answer datazig bulk hello
ZIG_SAFE_TESTS = safe safetrap
RUST_TESTS = rust rusttrap hellors

# Translate, assemble, and run each module in test/run.py, then random
# modules with test/fuzz.py: 40 with the math unit, 40 without, and 20 each
# without bounds checks and with a memory that can grow. Then the passes on
# code built by hand in test/passes.py, then check the error messages in
# test/errors.py, and run nicebuild.py in test/build.py, for each language
# whose compiler is installed.
test: emulator
	@$(PYTHON) test/run.py
	@$(PYTHON) test/fuzz.py 1 40
	@$(PYTHON) test/fuzz.py --no-mpu 1 40
	@$(PYTHON) test/fuzz.py --unchecked 1 20
	@$(PYTHON) test/fuzz.py --grow 1 20
	@$(PYTHON) test/passes.py
	@$(PYTHON) test/errors.py
	@$(PYTHON) test/build.py

emulator:
	$(MAKE) -C ../emulator build

# Compares the translator with an older version of itself, OLD, a git
# revision, on random modules: fuzz.py's, and modules with accesses,
# divisions, and indirect calls that may trap, in each mode (README.md,
# Test). Not part of make test: it takes minutes and needs git.
OLD ?= main
diff: emulator
	@$(PYTHON) test/diff_fuzz.py --old $(OLD) 1 60
	@$(PYTHON) test/diff_fuzz.py --old $(OLD) --trap 1 150
	@$(PYTHON) test/diff_fuzz.py --old $(OLD) --trap --grow 1 40
	@$(PYTHON) test/diff_fuzz.py --old $(OLD) --trap --no-mpu 1 40
	@$(PYTHON) test/diff_fuzz.py --old $(OLD) --trap --library 1 40
	@$(PYTHON) test/diff_fuzz.py --old $(OLD) --unchecked 1 30

# Needs mypy (pip install mypy).
typecheck:
	cd test && MYPYPATH=../../assembler:.. $(PYTHON) -m mypy --strict ../nicewasm.py ../nicebuild.py run.py errors.py \
	  wasm.py fuzz.py passes.py diff_fuzz.py build.py

wasm:
	@for t in $(C_TESTS); do \
	  $(CLANG) --target=wasm32 -mbulk-memory -O2 -nostdlib -Wl,--no-entry -Wl,--export=main \
	    -Wl,--allow-undefined -Wl,--stack-first -Wl,-z,stack-size=4096 -Wl,--initial-memory=65536 \
	    -o test/$$t.wasm test/$$t.c || exit 1; \
	done
	@chmod -x test/*.wasm
	@for t in $(ZIG_TESTS); do \
	  $(ZIG) build-exe -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSmall -fstrip \
	    --stack 4096 --initial-memory=65536 -femit-bin=test/$$t.wasm test/$$t.zig || exit 1; \
	done
	@for t in $(ZIG_SAFE_TESTS); do \
	  $(ZIG) build-exe -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSafe -fstrip \
	    --stack 16384 --initial-memory=65536 -femit-bin=test/$$t.wasm test/$$t.zig || exit 1; \
	done
	@for t in $(RUST_TESTS); do \
	  $(RUSTC) --target wasm32-unknown-unknown --crate-type cdylib -C opt-level=s -C panic=abort \
	    -C strip=debuginfo -C link-arg=-zstack-size=4096 -C link-arg=--initial-memory=65536 \
	    -o test/$$t.wasm test/$$t.rs || exit 1; \
	done
	@rm -f test/*.wasm.o

.PHONY: test emulator typecheck wasm diff
