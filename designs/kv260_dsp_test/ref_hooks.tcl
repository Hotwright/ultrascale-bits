# Hooks for env/reference_build.sh (Vivado reference, diagnosis only). The
# DSPs are LOC'd in dsp.v. After routing: every DSP site input fed straight
# from a constant net, with the pip that feeds it. A DSP48E2 is a macro, so
# its own pins have no site pins: the query goes through the site.
proc ref_post_route {} {
    set const_pips [dict create]
    foreach n [get_nets -hierarchical -filter {TYPE == GROUND || TYPE == POWER}] {
        foreach u [get_pips -quiet -of $n] { dict set const_pips $u [get_property TYPE $n] }
    }
    set f [open [file join $::env(REF_OUT) pins.txt] w]
    foreach c [get_cells -hierarchical -filter {REF_NAME == DSP48E2}] {
        puts $f "CELL $c [get_property LOC $c]"
        foreach sp [get_site_pins -of [get_sites [get_property LOC $c]]] {
            if {[get_property DIRECTION $sp] ne "IN"} continue
            foreach u [get_pips -quiet -uphill -of [get_nodes -quiet -of $sp]] {
                if {[dict exists $const_pips $u]} { puts $f "PIN $c $sp [dict get $const_pips $u] $u" }
            }
        }
    }
    close $f
}
