# The out-of-context timing of the pipelined core, as
# doc/review/pipeline-timing.md measures it: synthesis, placement, and
# routing of pipeline alone, for the part of the MEGA65, with a 10 ns
# clock, and the worst register-to-register paths. Run it with
# "make timing" in hdl/, which leaves build/timing.rpt and prints the
# worst path.
#
# The input and output delays are 0, so the slack of a path from an input
# or to an output is the time left to the system around the core: for the
# data bus, its address decode, its block RAMs, and its read mux. Those
# paths go to build/timing_in.rpt and build/timing_out.rpt. They leave out
# retire_o and stats_o, which only the trace and the statistics read. A run takes about 10 minutes, and runs differ by a few
# tenths of a nanosecond from placement alone.
set src [file normalize [file join [file dirname [info script]] src]]
set out [file normalize [file join [file dirname [info script]] build]]
read_vhdl -vhdl2008 [list $src/nice_pkg.vhd $src/trace_pkg.vhd $src/pipe_pkg.vhd \
  $src/pipe_fetch.vhd $src/pipe_decode.vhd $src/pipe_prepare.vhd $src/pipe_dbus.vhd \
  $src/pipe_write.vhd $src/pipeline.vhd]
synth_design -top pipeline -part xc7a200tfbg484-2 -mode out_of_context
create_clock -period 10.000 -name clk [get_ports clk_i]
set_input_delay -clock clk 0 [get_ports -filter {DIRECTION == IN && NAME != clk_i}]
set_output_delay -clock clk 0 [all_outputs]
opt_design
place_design
phys_opt_design
route_design
report_utilization -file $out/timing_util.rpt
report_timing -from [all_registers] -to [all_registers] -max_paths 50 -nworst 1 \
  -file $out/timing.rpt
report_timing -from [all_inputs] -to [all_registers] -max_paths 50 -nworst 1 \
  -file $out/timing_in.rpt
report_timing -from [all_registers] \
  -to [get_ports -filter {DIRECTION == OUT && NAME !~ retire_o* && NAME !~ stats_o*}] \
  -max_paths 50 -nworst 1 -file $out/timing_out.rpt
