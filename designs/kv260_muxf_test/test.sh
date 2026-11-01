#!/bin/bash
# Board test of the wide-mux trees (muxlab.v) over JTAG: write each of the 512
# input values to r2 (0xA0000008), read the registered F9/F8/F7 words
# (0xA0000020/24/28) and compare with expected.tcl (gen.py, checked against
# iverilog). Prints per-word bit-error masks and PASS/FAIL. Run the block
# test's checks first so a bridge fault shows up as such.
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
{ cat "$HERE/expected.tcl"; cat <<'TCL'; } | timeout 900 "$HERE/../../env/kv260_xsdb.sh" | tr -cd '\11\12\15\40-\176'
proc rd {a} { return [mrd -force -value $a] }
puts [format "ID 0x%08x" [rd 0xA0000010]]
set bad9 0; set bad8 0; set bad7 0; set nbad 0
for {set x 0} {$x < 512} {incr x} {
    mwr -force 0xA0000008 $x
    set g [list [rd 0xA0000020] [rd 0xA0000024] [rd 0xA0000028]]
    set e [lindex $EXP $x]
    set d9 [expr {[lindex $g 0] ^ [lindex $e 0]}]
    set d8 [expr {[lindex $g 1] ^ [lindex $e 1]}]
    set d7 [expr {[lindex $g 2] ^ [lindex $e 2]}]
    set bad9 [expr {$bad9 | $d9}]; set bad8 [expr {$bad8 | $d8}]; set bad7 [expr {$bad7 | $d7}]
    if {$d9 || $d8 || $d7} {
        incr nbad
        if {$nbad <= 12} { puts [format "x=%3d  F9 xor 0x%08x  F8 xor 0x%08x  F7 xor 0x%08x" $x $d9 $d8 $d7] }
    }
}
puts [format "inputs wrong: %d/512   trees wrong: F9 0x%08x  F8 0x%08x  F7 0x%08x" $nbad $bad9 $bad8 $bad7]
puts [expr {$nbad == 0 ? "PASS" : "FAIL"}]
TCL
