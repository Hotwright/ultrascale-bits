# Context for solve.py's unexplained CMT_L bits: per clock net, its clock
# root and every pip it uses in any RCLK/CMT tile (all types, not just the
# two studied), from a specimen's saved checkpoint.
#
#   vivado -mode batch -source roots.tcl -tclargs <specimen dir>
set dir [lindex $::argv 0]
open_checkpoint [file join $dir design.dcp]
set f [open [file join $dir roots.txt] w]
foreach net [get_nets -hierarchical -filter {TYPE == GLOBAL_CLOCK}] {
    puts $f "NET $net ROOT [get_property CLOCK_ROOT $net]"
    foreach p [get_pips -of_objects $net] {
        set t [get_tiles -of_objects $p]
        if {[string match RCLK_* $t] || [string match CMT_* $t]} { puts $f "PIP $p" }
    }
}
close $f
