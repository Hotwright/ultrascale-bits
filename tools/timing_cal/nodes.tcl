open_checkpoint [lindex $argv 0]/yosys.dcp
set f [open nodes1.txt w]
foreach n [get_nets -hier -filter {TYPE == SIGNAL && ROUTE_STATUS == ROUTED}] {
    set loads [get_pins -quiet -of $n -filter {DIRECTION == IN && IS_LEAF}]
    if {[llength $loads] != 1} continue
    set d [get_net_delays -quiet -of $n -to $loads]
    if {$d eq ""} continue
    set drv [get_pins -quiet -of $n -filter {DIRECTION == OUT && IS_LEAF}]
    puts $f "[get_property SLOW_MAX $d]\t[get_property REF_NAME [get_cells -of $drv]].[get_property REF_PIN_NAME $drv]\t[get_property REF_NAME [get_cells -of $loads]].[get_property REF_PIN_NAME $loads]\t[join [get_nodes -of $n] { }]"
}
close $f
puts DONE
