proc w {a d} { mwr -force $a $d }
proc r {a} { return [mrd -force -value $a] }
set B 0xA0000000
foreach {name off} {"L" 0x0000 "U" 0x0800} {
  set bad 0; set nob 0
  for {set i 0} {$i < 64} {incr i} {
    set a [expr {$B + $off + 4*$i}]
    set v [expr {(0x13579BDF * ($i + 1) + 0x2468ACE0) & 0xffffffff}]
    r $a                ;# read port now sits on this address
    w $a $v             ;# write the same address: a collision
    set g [r $a]
    if {$g != $v} { incr bad; if {$bad <= 4} { puts [format "  %s coll addr %2d wrote 0x%08x got 0x%08x" $name $i $v $g] } }
    # control: write while the read port sits elsewhere
    set a2 [expr {$B + $off + 4*($i + 256)}]
    r [expr {$B + $off + 4*($i + 100)}]
    w $a2 $v
    if {[r $a2] != $v} { incr nob }
  }
  puts "$name half: collision writes wrong $bad / 64, control writes wrong $nob / 64"
}
