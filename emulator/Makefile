ZIG ?= zig
EMU = zig-out/bin/niceemu
BIN = ../assembler/test

# The 2004 example programs, each run with its options and its output
# compared with test/X.expected.
TESTS = count replicate print
OPTS_count     =
OPTS_replicate = -d 0x10:10
OPTS_print     = -s

define check
	@$(EMU) $(OPTS_$(1)) $(BIN)/$(1).bin > test/$(1).out
	@if cmp -s test/$(1).out test/$(1).expected; then echo "PASS $(1)"; \
	else echo "FAIL $(1)"; diff test/$(1).expected test/$(1).out; exit 1; fi

endef

test: build
	$(ZIG) build test --summary all
	$(foreach t,$(TESTS),$(call check,$(t)))
	@rm -f test/*.out

build:
	$(ZIG) build -Doptimize=ReleaseSafe

clean:
	rm -rf zig-out .zig-cache test/*.out

.PHONY: test build clean
