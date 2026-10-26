# Hooks for env/reference_build.sh (Vivado reference, diagnosis only).

# The MMCM/PLL LOCs of mmcm.v, and each BUFGCE where nextpnr put it
# (USPacker::place_cmt: the first free track of the CMT, track 0 kept clear),
# so that the CMT_L tiles can be compared whole.
proc ref_pre_place {} {
    foreach {cell site} {
        mmcm_a MMCM_X0Y1   mmcm_b MMCM_X0Y3   pll_c PLL_X0Y2   pll_d PLL_X0Y7
        bga0 BUFGCE_X0Y27  bga1 BUFGCE_X0Y28  bgc0 BUFGCE_X0Y30
        bgb0 BUFGCE_X0Y73  bgb3 BUFGCE_X0Y74  bgd1 BUFGCE_X0Y77
    } {
        set c [get_cells -hierarchical -filter "NAME =~ *$cell"]
        puts "ref_hooks: $c -> $site"
        set_property LOC $site $c
    }
}

# Where everything went, and every input pin of the MMCMs/PLLs with the pip
# that drives it (pins Vivado leaves unrouted show none).
proc ref_post_route {} {
    set f [open [file join $::env(REF_OUT) placement.txt] w]
    foreach c [get_cells -hierarchical -filter {REF_NAME =~ MMCM* || REF_NAME =~ PLL* || REF_NAME =~ BUFG*}] {
        puts $f "$c [get_property LOC $c]"
    }
    foreach c [get_cells -hierarchical -filter {REF_NAME =~ MMCM* || REF_NAME =~ PLL*}] {
        foreach p [get_pins -of $c -filter {DIRECTION == IN}] {
            set n [get_nets -of $p -quiet]
            set sp [get_site_pins -of $p -quiet]
            set pn [get_nodes -of $sp -quiet]
            set via ""
            if {$n ne "" && $pn ne ""} {
                foreach u [get_pips -uphill -of $pn -quiet] {
                    if {[lsearch -exact [get_pips -of $n -quiet] $u] >= 0} { lappend via $u }
                }
            }
            puts $f "PIN $p net=$n via=$via"
        }
    }
    close $f
}
