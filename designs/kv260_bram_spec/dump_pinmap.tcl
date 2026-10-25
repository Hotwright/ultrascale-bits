# For each BRAM in the reference checkpoint: its post-opt parameters, every
# cell pin, the bel pin(s) it lands on, and the net on it (with the net TYPE,
# so GND/VCC ties show). Run on reference/ref.dcp:
#   REF_OUT=<dir> vivado -mode batch -source dump_pinmap.tcl
open_checkpoint $::env(REF_OUT)/ref.dcp
set f [open $::env(REF_OUT)/pinmap.txt w]
foreach c [get_cells -hier -filter {REF_NAME =~ RAMB*}] {
    puts $f "CELL [get_property NAME $c] [get_property REF_NAME $c] [get_property LOC $c] [get_property BEL $c]"
    foreach p {READ_WIDTH_A READ_WIDTH_B WRITE_WIDTH_A WRITE_WIDTH_B CLOCK_DOMAINS DOA_REG DOB_REG WRITE_MODE_A WRITE_MODE_B
               IS_CLKARDCLK_INVERTED IS_CLKBWRCLK_INVERTED IS_ENARDEN_INVERTED IS_ENBWREN_INVERTED
               IS_RSTRAMARSTRAM_INVERTED IS_RSTRAMB_INVERTED IS_RSTREGARSTREG_INVERTED IS_RSTREGB_INVERTED
               INIT_A INIT_B SRVAL_A SRVAL_B} {
        puts $f "  PARAM $p [get_property -quiet $p $c]"
    }
    foreach p [get_pins -of $c] {
        set bp [get_bel_pins -quiet -of $p]
        set n [get_nets -quiet -of $p]
        set nn ""
        set nt ""
        if {[llength $n]} { set nn [get_property NAME $n]; set nt [get_property TYPE $n] }
        set bps {}
        foreach b $bp { lappend bps [lindex [split $b /] end] }
        puts $f "  PIN [get_property REF_PIN_NAME $p] [get_property DIRECTION $p] -> [join $bps ,] net=$nn $nt"
    }
}
close $f
