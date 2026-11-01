#!/bin/bash
# KV260 board test of the Agent-Hotwright build of zynq-ps8 + byte-pair-encoding
# (built in the browser: kv260_bpe_top.bit; or native/bpe.bit). Over JTAG from
# the PS debug port: clear DONE, then for each output slot select it, wait for
# the next settled pass, read the token. reg_map.h: the demo corpus
# "aaabdaaabac" settles to 5 tokens [258 100 258 97 99]. Prints PASS/FAIL.
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat <<'TCL' | timeout 300 "$HERE/../../env/kv260_xsdb.sh" | tr -cd '\11\12\15\40-\176'
proc rd {a} { if {[catch {mrd -force -value $a} v]} { puts "read $a: $v"; return -1 }; return $v }
proc wr {a d} { if {[catch {mwr -force $a $d} e]} { puts "write $a: $e" } }
set B 0xA0000000
wr [expr $B + 4] 1
after 20
set len [expr {[rd [expr $B + 0xC]] & 0x1f}]
set toks {}
for {set i 0} {$i < 5} {incr i} {
    wr $B $i
    wr [expr $B + 4] 1
    set n 0
    while {!([rd [expr $B + 4]] & 1) && $n < 200} { incr n }
    lappend toks [expr {[rd [expr $B + 8]] & 0x1ff}]
}
puts "OUT_LEN $len tokens $toks"
puts [expr {$len == 5 && $toks eq {258 100 258 97 99} ? "PASS" : "FAIL"}]
TCL
