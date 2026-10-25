# One CONFIG_SITE specimen: build it, then dump where each config primitive
# landed (site/BEL) and every pip of their nets in non-INT tiles.
#
#   vivado -mode batch -source char.tcl -tclargs <specimen dir>
set dir [lindex $::argv 0]
create_project -in_memory -part xck26-sfvc784-2LV-c
read_verilog [file join $dir top.v]
synth_design -top top -flatten_hierarchy rebuilt
foreach {p pin} {0 H12 1 E10 2 D10 3 C11 4 B10 5 E12 6 D11 7 B11} {
    set_property PACKAGE_PIN $pin [get_ports "pmod\[$p\]"]
    set_property IOSTANDARD LVCMOS33 [get_ports "pmod\[$p\]"]
}
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
# bel.txt (optional): "<BEL>" for the one config primitive, e.g.
# CONFIG_SITE.ICAP_BOT -- a (* BEL *) attribute in the Verilog is ignored.
if {[file exists [file join $dir bel.txt]]} {
    set bel [string trim [read [open [file join $dir bel.txt]]]]
    set c [get_cells -hierarchical -filter {PRIMITIVE_GROUP == CONFIGURATION}]
    set_property BEL $bel $c
    set_property LOC CONFIG_SITE_X0Y0 $c
}
place_design
route_design
write_bitstream -force [file join $dir design.bit]
write_checkpoint -force [file join $dir design.dcp]
set f [open [file join $dir design.cells] w]
foreach c [get_cells -hierarchical -filter {PRIMITIVE_GROUP == CONFIGURATION}] {
    puts $f "CELL $c [get_property REF_NAME $c] [get_property LOC $c] [get_property BEL $c]"
    foreach n [get_nets -of_objects $c] {
        foreach p [get_pips -of_objects $n] {
            set t [get_tiles -of_objects $p]
            if {![string match INT_X* $t]} { puts $f "PIP $p" }
        }
    }
    foreach pin [get_pins -of_objects $c] {
        set n [get_nets -quiet -of_objects $pin]
        puts $f "PIN [get_property REF_PIN_NAME $pin] [expr {$n eq "" ? "-" : $n}]"
    }
}
close $f
