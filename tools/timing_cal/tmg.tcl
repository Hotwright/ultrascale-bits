# Vivado timing of kv260_ps_axi_test for comparison with nextpnr's model.
# argv: mode (rtl | yosys), work dir
set mode [lindex $argv 0]
set w [lindex $argv 1]
cd $w
set part xck26-sfvc784-2LV-c
if {$mode eq "rtl"} {
    read_verilog axi.v
    read_xdc kv260_ps_vivado.xdc
    synth_design -top top -part $part
} else {
    read_edif top.edf
    read_xdc kv260_ps_vivado.xdc
    link_design -top top -part $part
}
set ps [get_cells -hier -filter {REF_NAME == PS8}]
create_clock -name clk -period 10.000 [get_pins $ps/PLCLK[0]]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force $mode.dcp
report_timing_summary -max_paths 10 -file $mode.summary.rpt
report_timing -max_paths 300 -nworst 1 -input_pins -file $mode.paths.rpt
# One line per path: start edge, end edge, requirement, data path delay, logic levels, slack
set f [open $mode.pathlist.txt w]
foreach p [get_timing_paths -max_paths 3000 -nworst 1] {
    puts $f [join [list [get_property STARTPOINT_CLOCK_EDGE $p] [get_property ENDPOINT_CLOCK_EDGE $p] \
        [get_property REQUIREMENT $p] [get_property DATAPATH_DELAY $p] [get_property LOGIC_LEVELS $p] \
        [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]] "\t"]
}
close $f
# Every routed connection: driver/sink tile grid points, cells, pins, slow-max delay (ps)
set f [open $mode.arcs.txt w]
foreach n [get_nets -hier -filter {TYPE == SIGNAL && ROUTE_STATUS == ROUTED}] {
    set drv [get_pins -quiet -of $n -filter {DIRECTION == OUT && IS_LEAF}]
    if {[llength $drv] != 1} continue
    set loads [get_pins -quiet -of $n -filter {DIRECTION == IN && IS_LEAF}]
    if {[llength $loads] > 200 || [llength $loads] == 0} continue
    set ds [get_sites -quiet -of [get_cells -of $drv]]
    if {$ds eq ""} continue
    set dt [get_tiles -of $ds]
    foreach l $loads {
        set ls [get_sites -quiet -of [get_cells -of $l]]
        if {$ls eq ""} continue
        set lt [get_tiles -of $ls]
        set d [get_net_delays -quiet -of $n -to $l]
        if {$d eq ""} continue
        puts $f [join [list [get_property GRID_POINT_X $dt] [get_property GRID_POINT_Y $dt] \
            [get_property GRID_POINT_X $lt] [get_property GRID_POINT_Y $lt] \
            [get_property REF_PIN_NAME $drv] [get_property REF_PIN_NAME $l] \
            [get_property SLOW_MAX $d] [get_property REF_NAME [get_cells -of $drv]] \
            [get_property REF_NAME [get_cells -of $l]] $dt $lt] "\t"]
    }
}
close $f
# Grid check against nextpnr's X/Y (RapidWright column/row)
puts "GRID INT_X0Y100 [get_property GRID_POINT_X [get_tiles INT_X0Y100]] [get_property GRID_POINT_Y [get_tiles INT_X0Y100]]"
puts "DONE $mode"
