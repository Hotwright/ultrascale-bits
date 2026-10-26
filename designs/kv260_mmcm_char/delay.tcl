# Diagnosis of the MMCM/PLL ROW_MID bit: for each checkpoint, the routed delay
# of the input clock to every MMCM/PLL CLKIN pin, and every pip of that net.
#   vivado -mode batch -source delay.tcl -tclargs <dcp> <out> [<dcp> <out> ...]
foreach {dcp out} $argv {
    open_checkpoint $dcp
    set f [open $out w]
    foreach c [get_cells -hierarchical -filter {REF_NAME =~ MMCM* || REF_NAME =~ PLL*}] {
        foreach pn {CLKIN1 CLKIN} {
            set p [get_pins -quiet $c/$pn]
            if {$p eq ""} continue
            set n [get_nets -of $p]
            set d [get_net_delays -quiet -of $n -to $p]
            set v ""
            foreach k {SLOW_MAX SLOW_MIN FAST_MAX FAST_MIN} { lappend v $k=[get_property -quiet $k $d] }
            puts $f "PIN [get_property LOC $c] $pn net=$n $v"
        }
    }
    foreach n [lsort -unique [get_nets -of [get_pins -hierarchical -filter {NAME =~ */CLKIN1 || NAME =~ */CLKIN}]]] {
        foreach pp [get_pips -of $n] { puts $f "PIP $n $pp" }
    }
    close $f
    close_design
}
