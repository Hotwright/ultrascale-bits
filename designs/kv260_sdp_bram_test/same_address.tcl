proc w {a d} { mwr -force $a $d }
proc r {a} { return [mrd -force -value $a] }
foreach base {0xa0000000 0xa0000800} {
  foreach off {0x0 0x40 0x100} {
    set a [expr {$base + $off}]
    set b [expr {$a + 4}]
    # same address: read, write, read
    set r0 [r $a]; w $a 0x11111111; set r1 [r $a]; w $a 0x22222222; set r2 [r $a]
    # different address in between
    set r3 [r $b]; set r4 [r $a]
    puts [format "%08x: before %08x  after-write1 %08x  after-write2 %08x | via other %08x then %08x" $a $r0 $r1 $r2 $r3 $r4]
  }
}
