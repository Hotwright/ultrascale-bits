# Print the clock root of the PS clock (bufg_i/O) and of every net into an
# MMCM/PLL CLKIN, for each checkpoint named in the list file (argv 0).
foreach d [split [string trim [read [open [lindex $::argv 0]]]] "\n"] {
    open_checkpoint [file join $d design.dcp]
    set n [get_nets -of [get_pins bufg_i/O]]
    puts "ROOT $d [get_property CLOCK_ROOT $n] [get_property USER_CLOCK_ROOT $n]"
    foreach c [get_cells -hier -filter {REF_NAME == MMCME4_ADV || REF_NAME == PLLE4_ADV}] {
        puts "SITE $d [get_sites -of $c]"
    }
    close_design
}
