PYTHON ?= python3
CLANG ?= clang
ZIG ?= zig
RUSTC ?= rustc

# The modules compiled from test/*.c, test/*.zig, and test/*.rs. Their .wasm files are
# checked in, so make test needs no compiler; make wasm rebuilds them. The
# options keep the linear memory to one page. ZIG_SAFE_TESTS are built with
# ReleaseSafe and a 16 KB stack, because Zig's panic handler puts a 4 KB
# buffer on the stack.
C_TESTS = sum5 control memory data shifts intops floats
ZIG_TESTS = answer datazig bulk hello
ZIG_SAFE_TESTS = safe safetrap
RUST_TESTS = rust rusttrap hellors

# Translate, assemble, and run each module in test/run.py, then check the
# error messages in test/errors.py.
test: emulator
	@$(PYTHON) test/run.py
	@$(PYTHON) test/errors.py

emulator:
	$(MAKE) -C ../emulator build

# Needs mypy (pip install mypy).
typecheck:
	cd test && MYPYPATH=../../assembler $(PYTHON) -m mypy --strict ../nicewasm.py run.py errors.py \
	  wasm.py

wasm:
	@for t in $(C_TESTS); do \
	  $(CLANG) --target=wasm32 -O2 -nostdlib -Wl,--no-entry -Wl,--export=main \
	    -Wl,--allow-undefined -Wl,-z,stack-size=4096 -Wl,--initial-memory=65536 \
	    -o test/$$t.wasm test/$$t.c || exit 1; \
	done
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

.PHONY: test emulator typecheck wasm
