# One random MMCM/PLL specimen (gen.py): place the clocking cells where
# loc.txt says and each counter in the clock region of the CMT whose MMCM
# regions.txt names, build, then write
#   cells.txt       every property of every MMCME4_ADV/PLLE4_ADV, as Vivado
#                   finally holds it ("<site> <property> <value>"): drp.py
#                   computes the register fields from these, not from the
#                   generator's intent
#   design.features the pips, wires and site attributes (kv260_cmt_char/dump.tcl)
#
#   vivado -mode batch -source char.tcl -tclargs <specimen dir>
set dir [lindex $::argv 0]
set types {CMT_L INT_INTF_L_CMT INT_INTF_L_IO RCLK_RCLK_XIPHY_INNER_FT RCLK_CLEM_CLKBUF_L}

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
set pbs [dict create]
foreach line [split [read [open [file join $dir regions.txt]]] "\n"] {
    if {[llength $line] != 2} continue
    set site [lindex $line 1]
    if {![dict exists $pbs $site]} {
        set pb [create_pblock pb_$site]
        resize_pblock $pb -add CLOCKREGION_[get_clock_regions -of [get_sites $site]]
        dict set pbs $site $pb
    }
    add_cells_to_pblock [dict get $pbs $site] [get_cells [lindex $line 0]*]
}
place_design
route_design
write_bitstream -force [file join $dir design.bit]
write_checkpoint -force [file join $dir design.dcp]

set fp [open [file join $dir cells.txt] w]
foreach c [get_cells -hier -filter {REF_NAME == MMCME4_ADV || REF_NAME == PLLE4_ADV}] {
    set site [get_sites -of $c]
    foreach prop [list_property $c] {
        set v [get_property $prop $c]
        if {[string first " " $v] >= 0 || $v eq ""} continue
        puts $fp "$site $prop $v"
    }
    foreach pin [get_pins -of $c -filter {DIRECTION == OUT}] {
        set n [get_nets -quiet -of $pin]
        set conn [expr {$n ne "" && [llength [get_pins -quiet -of $n -filter {DIRECTION == IN}]] > 0}]
        puts $fp "$site PIN.[get_property REF_PIN_NAME $pin] $conn"
    }
}
close $fp

source [file join [file dirname [file normalize [info script]]] .. kv260_cmt_char dump.tcl]
