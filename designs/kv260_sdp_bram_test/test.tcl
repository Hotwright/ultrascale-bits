proc w {a d} { mwr -force $a $d }
proc r {a} { return [mrd -force -value $a] }
set B 0xA0000000
puts [format "id 0x%08x  writes %d" [r [expr {$B + 0x1000}]] [r [expr {$B + 0x1004}]]]
proc pat {i} { return [expr {(($i * 0x9E3779B1) ^ ($i << 7) ^ 0x5A00F00F) & 0xffffffff}] }
proc pat2 {i} { return [expr {~[pat $i] & 0xffffffff}] }
set allbad 0
foreach {name off} {"mem (L half)" 0x0000 "mem1 (U half)" 0x0800} {
    puts "=== $name"
    set base [expr {$B + $off}]
    set bad0 0; set or0 0; set shown 0
    for {set i 0} {$i < 512} {incr i} {
        set g [r [expr {$base + 4*$i}]]; set e [pat $i]
        if {$g != $e} { incr bad0; set or0 [expr {$or0 | ($g ^ $e)}]
            if {$shown < 4} { puts [format "  init addr %3d want 0x%08x got 0x%08x" $i $e $g]; incr shown } }
    }
    puts [format "  init (read only): %d of 512 words wrong, bits 0x%08x" $bad0 $or0]
    for {set i 0} {$i < 512} {incr i} { w [expr {$base + 4*$i}] [pat2 $i] }
    set bad 0; set orx 0; set shown 0
    for {set i 0} {$i < 512} {incr i} {
        set g [r [expr {$base + 4*$i}]]; set e [pat2 $i]
        if {$g != $e} { incr bad; set orx [expr {$orx | ($g ^ $e)}]
            if {$shown < 4} { puts [format "  addr %3d wrote 0x%08x got 0x%08x xor 0x%08x" $i $e $g [expr {$g ^ $e}]]; incr shown } }
    }
    puts [format "  fill: %d of 512 words wrong, bits 0x%08x" $bad $orx]
    incr allbad [expr {$bad0 + $bad}]
}
puts [expr {$allbad == 0 ? "SDP-BRAM PASS" : "SDP-BRAM FAIL"}]
