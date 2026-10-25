# Hooks for env/reference_build.sh (Vivado reference, diagnosis only).
# Leave the ICAPE3 where Vivado wants it; the point is to learn which ICAP
# port it picks and which non-INT routing its pins take.
proc ref_post_route {} {
    set f [open [file join $::env(REF_OUT) icap_route.txt] w]
    foreach c [get_cells -hierarchical -filter {PRIMITIVE_GROUP == CONFIGURATION}] {
        puts $f "CELL $c [get_property REF_NAME $c] [get_property LOC $c] [get_property BEL $c]"
        foreach n [get_nets -of_objects $c] {
            foreach p [get_pips -of_objects $n] {
                set t [get_tiles -of_objects $p]
                if {![string match INT_X* $t]} { puts $f "PIP $n $t $p" }
            }
        }
    }
    close $f
}
