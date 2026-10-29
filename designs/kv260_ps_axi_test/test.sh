#!/bin/bash
# Board test for axi.v, run from the PS side over JTAG (env/kv260_xsdb.sh):
# AXI reads and writes through M_AXI_HPM0_FPD, then each of the 16 PL->PS
# interrupt lines, seen in the LPD GIC proxy (LPD_SLCR GICP2/GICP3 status:
# the APU and RPU GICs are not reachable from the DAP). Prints "PASS n/n".
#
#   ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh axi.bit && ./test.sh
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat <<'TCL' | timeout 300 "$HERE/../../env/kv260_xsdb.sh"
proc rd {a} { return [mrd -force -value $a] }
set n 0; set ok 0
proc check {what got exp} {
    global n ok
    incr n
    if {$got == $exp} { incr ok } else { puts [format "FAIL %s: 0x%08x, expected 0x%08x" $what $got $exp] }
}
check "ID" [rd 0xA0000010] 0xC0DE0A51
set c0 [rd 0xA0000014]
check "counter runs" [expr {[rd 0xA0000014] != $c0}] 1
set w {0x12345678 0x9abcdef0 0x0badf00d 0xcafef00d}
for {set i 0} {$i < 4} {incr i} { mwr -force [expr 0xA0000000 + 4*$i] [lindex $w $i] }
for {set i 0} {$i < 4} {incr i} { check "r$i" [rd [expr 0xA0000000 + 4*$i]] [lindex $w $i] }
mwr -force -size b 0xA0000001 0xaa
mwr -force -size h 0xA000000A 0x5555
check "byte write" [rd 0xA0000000] 0x1234aa78
check "halfword write" [rd 0xA0000008] 0x5555f00d
check "unmapped" [rd 0xA0000100] 0xdead0100
set G2 0xFF418028; set G3 0xFF41803C
for {set i 0} {$i < 16} {incr i} {
    mwr -force 0xA0000004 0; mwr -force $G2 0xFE000000; mwr -force $G3 0x0000FF01
    mwr -force 0xA0000004 [expr 1 << $i]
    set id [expr {$i < 8 ? 121 + $i : 136 + $i - 8}]
    set e2 [expr {$id < 128 ? 1 << ($id - 96) : 0}]
    set e3 [expr {$id < 128 ? 0 : 1 << ($id - 128)}]
    # Only the PL lines (SPI 121-128, 136-143): under Linux other PS
    # peripherals (SPI 151, 154) can be pending too.
    check "IRQ line $i (SPI $id) GICP2" [expr {[rd $G2] & 0xFE000000}] $e2
    check "IRQ line $i (SPI $id) GICP3" [expr {[rd $G3] & 0x0000FF01}] $e3
}
mwr -force 0xA0000004 0; mwr -force $G2 0xFE000000; mwr -force $G3 0x0000FF01
mwr -force 0xA0000000 0x000000ff
puts [expr {$ok == $n ? "PASS $ok/$n" : "FAIL $ok/$n"}]
TCL
