#!/bin/bash
# test.sh one access at a time. First the PS registers that decide whether the
# PL can answer HPM0 at all (read through the LPD/FPD, never HPM0), then each
# access of the BPE sequence with the bridge's status window after it, so a
# wedge names the access that caused it. FAST=1 drops the 50 ms gaps.
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAP=50; [ "${FAST:-0}" = 1 ] && GAP=0
{ echo "set GAP $GAP"; cat <<'TCL'; } | timeout 300 "$HERE/../../env/kv260_xsdb.sh" | tr -cd '\11\12\15\40-\176'
proc rd {a} { if {[catch {mrd -force -value $a} v]} { return ERR }; return [format 0x%08x $v] }
proc wr {a d} { if {[catch {mwr -force $a $d} e]} { return ERR }; return ok }
proc st {} { return "S0=[rd 0xAFFFFFF0] W=[rd 0xAFFFFFF4] R=[rd 0xAFFFFFF8] S3=[rd 0xAFFFFFFC]" }
puts "PL0_REF_CTRL [rd 0xFF5E00C0]  (bit24 = PL_CLK0 running; divisors in [21:16],[13:8])"
puts "AFI_FS       [rd 0xFD615000]  (HPM0 width [9:8]: 2 = 128-bit)"
puts "PCAP_STATUS  [rd 0xFFCA3010]  (PL done etc.)"
puts "status       [st]"
set B 0xA0000000
proc step {what r} { global GAP; puts "$what -> $r   [st]"; after $GAP; return $r }
step "wr STATUS<=1" [wr [expr $B+4] 1]
step "rd OUT_LEN"   [rd [expr $B+0xC]]
set toks {}
for {set i 0} {$i < 5} {incr i} {
    step "wr RD_IDX<=$i" [wr $B $i]
    step "wr STATUS<=1"  [wr [expr $B+4] 1]
    step "rd STATUS"     [rd [expr $B+4]]
    lappend toks [step "rd TOKEN" [rd [expr $B+8]]]
}
puts "tokens $toks"
TCL
