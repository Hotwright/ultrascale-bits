# Hooks for env/reference_build.sh (Vivado reference, diagnosis only).

# rom.v reads chase.hex with $readmemh.
proc ref_pre_synth {} {
    add_files -norecurse [file join [file dirname $::env(REF_SRC)] chase.hex]
}

# Put the ROM where nextpnr put it (BRAM_X19Y130), so the clock has to make
# the same trip east across the CMT_L/XIPHY column at X16.
proc ref_pre_place {} {
    set ram [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]
    puts "ref_hooks: BRAM cells: $ram"
    set_property LOC RAMB36_X0Y26 $ram
}

# Every pip and node of every clock net, one per line, with its tile.
proc ref_post_route {} {
    set f [open [file join $::env(REF_OUT) clock_route.txt] w]
    foreach net [get_nets -hierarchical -filter {TYPE == GLOBAL_CLOCK}] {
        puts $f "NET $net"
        foreach p [get_pips -of_objects $net] { puts $f "PIP [get_tiles -of_objects $p] $p" }
        foreach n [get_nodes -of_objects $net] { puts $f "NODE $n" }
    }
    close $f
}
