#!/bin/bash
# Board test of top.v over JTAG (env/kv260_xsdb.sh): 32-, 16- and 8-bit
# accesses through the zynq-ps8 block's AXI4-Lite bridge, the 16 PL->PS
# interrupts in the LPD GIC proxy (as kv260_ps_axi_test/test.sh), and that
# nothing was refused. Prints "PASS n/n".
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat <<'TCL' | timeout 300 "$HERE/../../env/kv260_xsdb.sh"
proc rd {a} { return [mrd -force -value $a] }
set n 0; set ok 0
proc check {what got exp} {
    global n ok
    incr n
    if {$got == $exp} { incr ok } else { puts [format "FAIL %s: 0x%08x, expected 0x%08x" $what $got $exp] }
}
check "ID" [rd 0xA0000010] 0xC0DE0B58
set c0 [rd 0xA0000014]
check "counter runs" [expr {[rd 0xA0000014] != $c0}] 1
set w {0x12345678 0x9abcdef0 0x0badf00d 0xcafef00d}
for {set i 0} {$i < 4} {incr i} { mwr -force [expr 0xA0000000 + 4*$i] [lindex $w $i] }
for {set i 0} {$i < 4} {incr i} { check "r$i" [rd [expr 0xA0000000 + 4*$i]] [lindex $w $i] }
mwr -force -size b 0xA0000001 0xaa
mwr -force -size h 0xA000000A 0x5555
mwr -force -size b 0xA000000F 0x77
check "byte write" [rd 0xA0000000] 0x1234aa78
check "halfword write" [rd 0xA0000008] 0x5555f00d
check "byte write lane 3" [rd 0xA000000C] 0x77fef00d
check "unmapped" [rd 0xA0000100] 0xdead0100
set G2 0xFF418028; set G3 0xFF41803C
for {set i 0} {$i < 16} {incr i} {
    mwr -force 0xA0000004 0; mwr -force $G2 0xFE000000; mwr -force $G3 0x0000FF01
    mwr -force 0xA0000004 [expr 1 << $i]
    set id [expr {$i < 8 ? 121 + $i : 136 + $i - 8}]
    set e2 [expr {$id < 128 ? 1 << ($id - 96) : 0}]
    set e3 [expr {$id < 128 ? 0 : 1 << ($id - 128)}]
    check "IRQ line $i (SPI $id) GICP2" [expr {[rd $G2] & 0xFE000000}] $e2
    check "IRQ line $i (SPI $id) GICP3" [expr {[rd $G3] & 0x0000FF01}] $e3
}
mwr -force 0xA0000004 0; mwr -force $G2 0xFE000000; mwr -force $G3 0x0000FF01
check "no bad_access" [expr {[rd 0xA0000018] >> 31}] 0
mwr -force 0xA0000000 0x000000a5
puts [expr {$ok == $n ? "PASS $ok/$n" : "FAIL $ok/$n"}]
TCL
