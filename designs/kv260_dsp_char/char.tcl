# One DSP48E2 specimen: build it, then dump where each DSP landed and its
# cell properties. Vivado is for characterisation only.
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
place_design
route_design
write_bitstream -force [file join $dir design.bit]
write_checkpoint -force [file join $dir design.dcp]
set f [open [file join $dir cells.txt] w]
foreach c [get_cells -hierarchical -filter {REF_NAME =~ DSP*}] {
    puts $f "CELL $c [get_property REF_NAME $c] [get_property LOC $c] [get_property BEL $c]"
    foreach k [list_property $c] { puts $f "PROP $c $k [get_property $k $c]" }
}
close $f
