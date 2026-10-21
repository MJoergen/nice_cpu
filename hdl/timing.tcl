# The out-of-context timing of the pipelined core, as
# doc/review/pipeline-timing.md measures it: synthesis, placement, and
# routing of pipeline alone, for the part of a board, with a 10 ns clock,
# and the worst register-to-register paths. Run it with "make timing" in
# hdl/, which runs it in the directory of the reports and prints the worst
# path of each and the groups.
#
# The arguments, all optional, are the part, the flow, and the period in ns:
#   default  the directives of Vivado's defaults
#   timing   the directives that NiceMonMEGA65 builds with: synthesis
#            PerformanceOptimized with retiming, Explore, ExtraTimingOpt,
#            AggressiveExplore, and phys_opt_design again after routing
#
# The input and output delays are 0, so the slack of a path from an input
# or to an output is the time left to the system around the core: for the
# data bus, its address decode, its block RAMs, and its read mux. Those
# paths go to timing_in.rpt and timing_out.rpt. They leave out retire_o
# and stats_o, which only the trace and the statistics read.
#
# timing_groups.rpt counts the endpoints with less than 1 ns of slack, by
# the register or port they start from and the register or port they end
# at, with the worst slack of each group. A run takes about 10 minutes
# with the default flow, and runs differ by a few tenths of a nanosecond
# from placement alone.
set part   [expr {$argc > 0 ? [lindex $argv 0] : "xc7a200tfbg484-2"}]
set flow   [expr {$argc > 1 ? [lindex $argv 1] : "default"}]
set period [expr {$argc > 2 ? [lindex $argv 2] : 10.0}]
set margin 1.0

if {$flow eq "default"} {
  set d_synth {}
  set d_opt   {}
  set d_place {}
  set d_phys  {}
  set d_route {}
} elseif {$flow eq "timing"} {
  set d_synth {-directive PerformanceOptimized -retiming}
  set d_opt   {-directive Explore}
  set d_place {-directive ExtraTimingOpt}
  set d_phys  {-directive AggressiveExplore}
  set d_route {-directive AggressiveExplore}
} else {
  error "unknown flow $flow, not default or timing"
}

set src [file normalize [file join [file dirname [info script]] src]]
read_vhdl -vhdl2008 [list $src/nice_pkg.vhd $src/trace_pkg.vhd $src/pipe_pkg.vhd \
  $src/pipe_fetch.vhd $src/pipe_decode.vhd $src/pipe_prepare.vhd $src/pipe_dbus.vhd \
  $src/pipe_write.vhd $src/pipeline.vhd]
synth_design -top pipeline -part $part -mode out_of_context {*}$d_synth
create_clock -period $period -name clk [get_ports clk_i]
set_input_delay -clock clk 0 [get_ports -filter {DIRECTION == IN && NAME != clk_i}]
set_output_delay -clock clk 0 [all_outputs]
opt_design {*}$d_opt
place_design {*}$d_place
phys_opt_design {*}$d_phys
route_design {*}$d_route
if {$flow eq "timing"} {
  phys_opt_design {*}$d_phys
}

set outputs [get_ports -filter {DIRECTION == OUT && NAME !~ retire_o* && NAME !~ stats_o*}]
report_utilization -file timing_util.rpt
report_timing -from [all_registers] -to [all_registers] -max_paths 50 -nworst 1 \
  -file timing.rpt
report_timing -from [all_inputs] -to [all_registers] -max_paths 50 -nworst 1 \
  -file timing_in.rpt
report_timing -from [all_registers] -to $outputs -max_paths 50 -nworst 1 \
  -file timing_out.rpt

# The name of a group: a port without its index, or a register as stage
# and name, such as "write w_r.uop" for i_pipe_write/w_r_reg[uop][src][0][0].
# The first field of a record stays only for a start, since the fields of
# an end are many and seldom differ in their paths.
proc group_name {pin field} {
  if {[string first / $pin] < 0} {
    return [regsub {\[.*$} $pin {}]
  }
  set cell [file dirname $pin]
  set stage [regsub {^i_pipe_} [lindex [split $cell /] 0] {}]
  set reg [join [lrange [split $cell /] 1 end] /]
  if {[regexp {^(.*?)_reg} $reg -> name]} {
    if {$field && [regexp {_reg\[([a-z_][a-z0-9_]*)\]} $reg -> first]} {
      set name "$name.$first"
    }
  } else {
    set name [regsub -all {\[[0-9]+\]} $reg {}]
  }
  return "$stage $name"
}

set paths [concat \
  [get_timing_paths -from [all_registers] -to [all_registers] -max_paths 100000 -nworst 1 \
    -slack_lesser_than $margin] \
  [get_timing_paths -from [all_inputs] -to [all_registers] -max_paths 100000 -nworst 1 \
    -slack_lesser_than $margin] \
  [get_timing_paths -from [all_registers] -to $outputs -max_paths 100000 -nworst 1 \
    -slack_lesser_than $margin]]
set groups [dict create]
set failing 0
set wns {}
foreach p $paths {
  set slack [get_property SLACK $p]
  set end_pin [get_property ENDPOINT_PIN $p]
  set key [list [group_name [get_property STARTPOINT_PIN $p] 1] \
    "[group_name $end_pin 0] [regsub {^.*/} $end_pin {}]"]
  if {$slack < 0} { incr failing }
  if {$wns eq "" || $slack < $wns} { set wns $slack }
  if {[dict exists $groups $key]} {
    lassign [dict get $groups $key] n worst
    dict set groups $key [list [expr {$n + 1}] [expr {min($worst, $slack)}]]
  } else {
    dict set groups $key [list 1 $slack]
  }
}
set rows {}
dict for {key value} $groups {
  lappend rows [concat $value $key]
}
set f [open timing_groups.rpt w]
puts $f "Part $part, flow $flow, period $period ns"
puts $f "Endpoints with less than $margin ns of slack: [llength $paths],\
  failing: $failing, worst slack: [expr {$wns eq "" ? "none" : "$wns ns"}]"
puts $f ""
puts $f [format "%9s  %9s  %-28s  %s" Endpoints "Worst ns" From To]
foreach row [lsort -real -index 1 $rows] {
  lassign $row n worst from to
  puts $f [format "%9d  %9.3f  %-28s  %s" $n $worst $from $to]
}
close $f
