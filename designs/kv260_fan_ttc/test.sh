#!/bin/bash
# Board test of top.v: run TTC0 counter 3 (whose wave output is
# EMIOTTC0WAVEO[2] -> A12 fan_en_b, mirrored on pmod[7]) as a 1 Hz, 50% PWM
# for SECONDS, then put it back to the idle state it was found in.
# Watch the board: the fan and the J2 LED pmod[7] pulse together.
# PASSED 2026-11-03 (fan and LED pulsed at 1 Hz).
#   ./build.sh && ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh top.bit && ./test.sh
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECONDS_ON="${1:-15}"
cat <<TCL | timeout 300 "$HERE/../../env/kv260_xsdb.sh"
set B 0xFF110000
set saved {}
foreach off {0x08 0x14 0x2C 0x38} { lappend saved \$off [mrd -force -value [expr {\$B + \$off}]] }
puts "TTC0 counter 3 before: \$saved"
# 100 MHz / 2^16 (prescale N=15) = 1526 Hz; interval 1526 -> 1 Hz; match 763 -> 50%.
mwr -force [expr {\$B + 0x14}] 0x00000001
mwr -force [expr {\$B + 0x08}] [expr {(15 << 1) | 1}]
mwr -force [expr {\$B + 0x2C}] 1526
mwr -force [expr {\$B + 0x38}] 763
mwr -force [expr {\$B + 0x14}] 0x0000001A
puts "1 Hz PWM on for ${SECONDS_ON} s"
after [expr {${SECONDS_ON} * 1000}]
mwr -force [expr {\$B + 0x14}] 0x00000001
foreach {off v} \$saved { if {\$off != 0x14} { mwr -force [expr {\$B + \$off}] \$v } }
mwr -force [expr {\$B + 0x14}] [dict get \$saved 0x14]
puts [format "restored: Counter_Control_3 0x%08x" [mrd -force -value [expr {\$B + 0x14}]]]
TCL
