# For a few DSPs of one specimen: every input pin tied to a constant, and
# whether Vivado routed it (characterisation: which tied pins nextpnr must
# route and which it must leave to the DSP's own tie/inversion bits).
#   vivado -mode batch -source pins.tcl -tclargs <specimen dir> [cells...]
set d [lindex $argv 0]
open_checkpoint $d/design.dcp
set cells [lrange $argv 1 end]
if {$cells eq ""} { set cells {d0 d1 d2 d3 d4 d5 d6 d7} }
set routed_nodes [dict create]
foreach n [get_nets -hierarchical -filter {TYPE == GROUND || TYPE == POWER}] {
    foreach nd [get_nodes -quiet -of $n] { dict set routed_nodes $nd $n }
}
set f [open $d/pins.txt w]
foreach c $cells {
    foreach p [get_pins -of [get_cells $c] -filter {DIRECTION == IN}] {
        set n [get_nets -quiet -of $p]
        if {$n eq ""} continue
        set t [get_property TYPE $n]
        if {$t ne "GROUND" && $t ne "POWER"} continue
        set sp [get_site_pins -quiet -of $p]
        set routed 0
        foreach s $sp {
            foreach nd [get_nodes -quiet -of $s] { if {[dict exists $routed_nodes $nd]} { set routed 1 } }
        }
        puts $f "$c [get_property REF_PIN_NAME $p] $t routed=$routed sitepin=$sp"
    }
}
close $f
