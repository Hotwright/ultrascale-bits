# For one placed MMCM and PLL: every input pin, its net, and whether Vivado
# routed it (characterisation: which tied pins nextpnr must route).
#   vivado -mode batch -source pins.tcl -tclargs <specimen dir>
set d [lindex $argv 0]
open_checkpoint $d/design.dcp
set f [open $d/pins.txt w]
foreach c [list mmcm1 pll2] {
    foreach p [get_pins -of [get_cells $c] -filter {DIRECTION == IN}] {
        set n [get_nets -of $p]
        if {$n eq ""} { puts $f "$p - unconnected"; continue }
        set t [get_property TYPE $n]
        set s [get_property ROUTE_STATUS $n]
        set sp [get_site_pins -of $p -quiet]
        set pn [get_nodes -of $sp -quiet]
        set routed [expr {$pn ne "" && [lsearch -exact [get_nodes -of $n -quiet] $pn] >= 0}]
        set up [get_pips -uphill -of $pn -quiet]
        set used ""
        foreach u $up { if {[lsearch -exact [get_pips -of $n -quiet] $u] >= 0} { lappend used $u } }
        puts $f "$p $n $t $s pin_routed=$routed via=$used"
    }
}
close $f
