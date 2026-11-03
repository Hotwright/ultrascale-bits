proc r {a} { return [mrd -force -value $a] }
set B 0xA0000000
foreach {name off} {"L" 0x0000 "U" 0x0800} {
  foreach k {0 1 2 3} {
    set a [expr {$B + $off + 4*(20 + $k)}]
    mwr -force $a 0x00000000
    mwr -force -size b [expr {$a + $k}] [expr {0xA0 + $k}]
    set g [r $a]
    puts [format "%s lane %d: wrote byte %d = 0x%02x, word now 0x%08x (want 0x%08x)" $name $k $k [expr {0xA0 + $k}] $g [expr {(0xA0 + $k) << (8*$k)}]]
  }
  mwr -force [expr {$B + $off + 4*30}] 0x11223344
  mwr -force -size h [expr {$B + $off + 4*30 + 2}] 0xBEEF
  puts [format "%s halfword upper: 0x%08x (want 0xbeef3344)" $name [r [expr {$B + $off + 4*30}]]]
}
