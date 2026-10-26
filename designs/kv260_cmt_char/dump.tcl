# Dump the features of a routed CMT_L specimen (sourced by char.tcl after
# route_design, or on its own over a checkpoint):
#   vivado -mode batch -source dump.tcl -tclargs <specimen dir>   (redump)
if {![info exists dir]} {
    set dir [lindex $::argv 0]
    open_checkpoint [file join $dir design.dcp]
}
set types {CMT_L INT_INTF_L_CMT INT_INTF_L_IO RCLK_RCLK_XIPHY_INNER_FT}

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
foreach net [get_nets -hierarchical] {
    foreach p [get_pips -quiet -of_objects $net] {
        if {![regexp {^([^/]+)/([^.]+)\.(.*)$} $p - t tt body]} continue
        if {[lsearch $types $tt] < 0} continue
        if {[regexp {^(.*)<<->>(.*)$} $body - a b]} {
            puts $f "$t.PIP.$b.$a.FWD"
        } elseif {[regexp {^(.*)->>?(.*)$} $body - a b]} {
            puts $f "$t.PIP.$b.$a"
        }
    }
}
foreach net [get_nets -hierarchical -filter {TYPE == GLOBAL_CLOCK}] {
    foreach n [get_nodes -of_objects $net] {
        foreach w [get_wires -of_objects $n] {
            set t [get_tiles -of_objects $w]
            if {[lsearch {CMT_L RCLK_RCLK_XIPHY_INNER_FT} [get_property TYPE $t]] < 0} continue
            puts $f "$t.WIRE.[lindex [split $w /] 1].USED"
        }
    }
}
close $f
