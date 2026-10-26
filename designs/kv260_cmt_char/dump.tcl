# Dump the features of a routed CMT_L specimen (sourced by char.tcl after
# route_design, or on its own over a checkpoint):
#   vivado -mode batch -source dump.tcl -tclargs <specimen dir>   (redump)
if {![info exists dir]} {
    set dir [lindex $::argv 0]
    open_checkpoint [file join $dir design.dcp]
}
set types {CMT_L INT_INTF_L_CMT INT_INTF_L_IO RCLK_RCLK_XIPHY_INNER_FT RCLK_CLEM_CLKBUF_L}

# The site's name inside its tile, as prjuray and nextpnr spell it: its X/Y
# less the smallest X/Y among the tile's sites of the same prefix.
proc relname {site} {
    regexp {^(.*)_X(\d+)Y(\d+)$} $site - pfx x y
    set mx 1000000; set my 1000000
    foreach s [get_sites -of_objects [get_tiles -of_objects $site]] {
        if {[regexp {^(.*)_X(\d+)Y(\d+)$} $s - p2 x2 y2] && $p2 eq $pfx} {
            if {$x2 < $mx} { set mx $x2 }
            if {$y2 < $my} { set my $y2 }
        }
    }
    return "${pfx}_X[expr {$x - $mx}]Y[expr {$y - $my}]"
}

set f [open [file join $dir design.features] w]
set params {CE_TYPE IS_I_INVERTED IS_CE_INVERTED BUFGCE_DIVIDE IS_CLR_INVERTED INIT_OUT PRESELECT_I0
    PRESELECT_I1 CE_TYPE_CE0 CE_TYPE_CE1 IS_I0_INVERTED IS_I1_INVERTED IS_CE0_INVERTED IS_CE1_INVERTED
    IS_S0_INVERTED IS_S1_INVERTED IS_IGNORE0_INVERTED IS_IGNORE1_INVERTED}
foreach c [get_cells -hierarchical -filter {PRIMITIVE_GROUP == CLOCK}] {
    set site [get_property LOC $c]
    set t [get_tiles -of_objects [get_sites $site]]
    if {[get_property TYPE $t] ne "CMT_L"} continue
    set rel [relname $site]
    puts $f "$t.$rel.IN_USE"
    foreach p $params {
        set v [get_property -quiet $p $c]
        if {$v ne ""} { puts $f "$t.$rel.$p.$v" }
    }
}
# A bidirectional pip A<<->>B (A the west side: CLK_HROUTE_L, CLK_HDISTR_ZERO)
# is FWD when the clock runs west to east, i.e. when the net's driver sits in
# a tile column west of the pip's tile. Clocks from a CMT cross the X15
# HROUTE buffers east to west (REV), PS clocks west to east. (The net's ROUTE
# string names nodes by a bare wire name that does not match get_nodes, so it
# cannot order them.)
proc driver_column {net} {
    set pin [get_pins -quiet -of_objects $net -filter {DIRECTION == OUT}]
    if {$pin eq ""} { return -1 }
    set site [get_sites -quiet -of_objects [get_cells -of_objects $pin]]
    if {$site eq ""} { return -1 }
    return [get_property COLUMN [get_tiles -of_objects $site]]
}
foreach net [get_nets -hierarchical] {
    set route ""
    foreach p [get_pips -quiet -of_objects $net] {
        if {![regexp {^([^/]+)/([^.]+)\.(.*)$} $p - t tt body]} continue
        if {[lsearch $types $tt] < 0} continue
        if {[regexp {^(.*)<<->>(.*)$} $body - a b]} {
            if {$route eq ""} { set route [driver_column $net] }
            set col [get_property COLUMN [get_tiles $t]]
            puts $f "$t.PIP.$b.$a.[expr {$route > $col ? "REV" : "FWD"}]"
        } elseif {[regexp {^(.*)->>?(.*)$} $body - a b]} {
            puts $f "$t.PIP.$b.$a"
        }
    }
}
foreach net [get_nets -hierarchical -filter {TYPE == GLOBAL_CLOCK}] {
    foreach n [get_nodes -of_objects $net] {
        foreach w [get_wires -of_objects $n] {
            set t [get_tiles -of_objects $w]
            if {[lsearch {CMT_L RCLK_RCLK_XIPHY_INNER_FT RCLK_CLEM_CLKBUF_L} [get_property TYPE $t]] < 0} continue
            puts $f "$t.WIRE.[lindex [split $w /] 1].USED"
        }
    }
}
close $f
