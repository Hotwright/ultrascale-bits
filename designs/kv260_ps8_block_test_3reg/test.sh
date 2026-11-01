#!/bin/bash
# The block test's 43 checks, then 200 snapshots of word 7: {cyc, back via
# X0Y2, back via X0Y0, 0}. With a sound multi-region clock both back values are
# cyc - 2 every time.
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$HERE/../kv260_ps8_block_test/test.sh" 2>&1 | tail -1
cat <<'TCL' | timeout 300 "$HERE/../../env/kv260_xsdb.sh" | tr -cd '\11\12\15\40-\176'
set bad2 0; set bad0 0; set shown 0
for {set i 0} {$i < 200} {incr i} {
    set v [mrd -force -value 0xA000001C]
    set c [expr {($v >> 24) & 0xff}]; set b2 [expr {($v >> 16) & 0xff}]; set b0 [expr {($v >> 8) & 0xff}]
    set e [expr {($c - 2) & 0xff}]
    if {$b2 != $e} { incr bad2 }
    if {$b0 != $e} { incr bad0 }
    if {($b2 != $e || $b0 != $e) && $shown < 8} { incr shown; puts [format "cyc %3d  via X0Y2 %3d  via X0Y0 %3d  (expect %3d)" $c $b2 $b0 $e] }
}
puts "snapshots 200: wrong via X0Y2 $bad2, via X0Y0 $bad0"
puts [expr {$bad2 == 0 && $bad0 == 0 ? "3-REGION PASS" : "3-REGION FAIL"}]
TCL
