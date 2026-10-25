# One clock-crossing specimen: build it, then dump every pip and used wire of
# every clock net in the tile types under study, spelled as nextpnr spells
# FASM features (TILE.PIP.<dst>.<src>[.FWD|.REV], TILE.WIRE.<wire>.USED).
#
#   vivado -mode batch -source char.tcl -tclargs <specimen dir>
set dir [lindex $::argv 0]
set types {CMT_L RCLK_CLEM_CLKBUF_L}

create_project -in_memory -part xck26-sfvc784-2LV-c
read_verilog [file join $dir top.v]
synth_design -top top -flatten_hierarchy rebuilt
set_property PACKAGE_PIN H12 [get_ports {pmod[0]}]
foreach p [get_ports pmod*] { set_property IOSTANDARD LVCMOS33 $p }
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

set fp [open [file join $dir clocks.txt] r]; set spec [read $fp]; close $fp
set i 0
foreach {row k region} $spec {
    set tile [get_tiles RCLK_INTF_LEFT_TERM_ALTO_X0Y$row]
    set site ""
    foreach s [get_sites -of_objects $tile] {
        set node [get_nodes -of_objects [get_site_pins $s/CLK_OUT]]
        if {[string match "*/CLK_BUFG_PS_${k}_CLK_OUT" $node]} { set site $s }
    }
    if {$site eq ""} { error "no BUFG_PS_$k in $tile" }
    set_property LOC $site [get_cells bufg$i]
    set pb [create_pblock pb$i]
    resize_pblock $pb -add CLOCKREGION_$region
    add_cells_to_pblock $pb [get_cells ctr${i}_reg*]
    incr i
}
place_design
route_design
write_bitstream -force [file join $dir design.bit]
write_checkpoint -force [file join $dir design.dcp]

set f [open [file join $dir design.features] w]
foreach net [get_nets -hierarchical -filter {TYPE == GLOBAL_CLOCK}] {
    foreach p [get_pips -of_objects $net] {
        set t [get_tiles -of_objects $p]
        if {[lsearch $types [get_property TYPE $t]] < 0} continue
        # TILE/TYPE.SRC->>DST, or TILE/TYPE.A<<->>B for a bidirectional pip
        regexp {^[^/]+/[^.]+\.(.*)$} $p - body
        if {[regexp {^(.*)<<->>(.*)$} $body - a b]} {
            # Every clock here enters from the west edge, so a bidirectional
            # CLK_HROUTE_L<<->>CLK_HROUTE_R is always used L to R: FWD.
            puts $f "$t.PIP.$b.$a.FWD"
        } elseif {[regexp {^(.*)->>?(.*)$} $body - a b]} {
            puts $f "$t.PIP.$b.$a"
        }
    }
    foreach n [get_nodes -of_objects $net] {
        foreach w [get_wires -of_objects $n] {
            set t [get_tiles -of_objects $w]
            if {[lsearch $types [get_property TYPE $t]] < 0} continue
            puts $f "$t.WIRE.[lindex [split $w /] 1].USED"
        }
    }
}
close $f
