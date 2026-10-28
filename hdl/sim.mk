# The simulator of the runs on the cores, for hdl/Makefile and
# bench/Makefile: SIM is ghdl, or nvc, which is several times faster on
# the long runs. SIM_BUILD, the absolute path of hdl/build, holds the
# analyzed VHDL: GHDL's library, and nvc's in $(NVCWORK). nvc elaborates
# each run in memory, with --no-save, so that runs with different generics
# can go in parallel. Its heap, -H, holds the memory model's pages of
# 128 KB each, one per byte of std_logic, and a run may write a new page in
# every step. sim_run runs the testbench $(1) with the generics
# $(2), and SIM_ARGS passes the same choice to hdl/test/core_runs.py.
SIM ?= ghdl
GHDL ?= ghdl
NVC ?= nvc
NVCWORK = $(SIM_BUILD)/nvc
NVCOPTS = --std=2008 --work=work:$(NVCWORK)
sim_run_ghdl = $(GHDL) --elab-run --std=08 --workdir=$(SIM_BUILD) $(1) $(2)
sim_run_nvc = $(NVC) $(NVCOPTS) -H 1g -e --jit --no-save $(2) $(1) -r
sim_run = $(sim_run_$(SIM))
SIM_ARGS = --sim $(SIM) --ghdl $(GHDL) --nvc $(NVC)
