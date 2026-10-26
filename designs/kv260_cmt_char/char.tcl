# One random CMT_L specimen (gen.py): place the clocking cells where loc.txt
# says and the counters where regions.txt says, build, then dump the features
# Vivado used, spelled as nextpnr spells FASM features:
#   <tile>.PIP.<dst>.<src>              pips in the tile types studied
#   <tile>.WIRE.<wire>.USED             clock wires in CMT_L
#   <tile>.<SITE_XnYm>.IN_USE           a clocking cell (site named tile-relative)
#   <tile>.<SITE_XnYm>.<PARAM>.<value>  its attributes
#
#   vivado -mode batch -source char.tcl -tclargs <specimen dir>
set dir [lindex $::argv 0]
set types {CMT_L INT_INTF_L_CMT INT_INTF_L_IO RCLK_RCLK_XIPHY_INNER_FT}

create_project -in_memory -part xck26-sfvc784-2LV-c
read_verilog [file join $dir top.v]
synth_design -top top -flatten_hierarchy rebuilt
foreach {p pin} {0 H12 1 E10 2 D10 3 C11 4 B10 5 E12 6 D11 7 B11} {
    set_property PACKAGE_PIN $pin [get_ports "pmod\[$p\]"]
    set_property IOSTANDARD LVCMOS33 [get_ports "pmod\[$p\]"]
}
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
foreach line [split [read [open [file join $dir loc.txt]]] "\n"] {
    if {[llength $line] == 2} { set_property LOC [lindex $line 1] [get_cells [lindex $line 0]] }
}
set i 0
foreach line [split [read [open [file join $dir regions.txt]]] "\n"] {
    if {[llength $line] != 2} continue
    set pb [create_pblock pb$i]
    resize_pblock $pb -add CLOCKREGION_[lindex $line 1]
    add_cells_to_pblock $pb [get_cells [lindex $line 0]*]
    incr i
}
place_design
route_design
write_bitstream -force [file join $dir design.bit]
write_checkpoint -force [file join $dir design.dcp]

source [file join [file dirname [info script]] dump.tcl]
