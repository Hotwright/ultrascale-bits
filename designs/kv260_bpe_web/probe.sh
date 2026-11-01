#!/bin/bash
# Read the zynq-ps8 bridge's status window (0xAFFF_FFF0-FFFC), try one write
# and one read of the BPE slave, and read the status again.
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat <<'TCL' | timeout 200 "$HERE/../../env/kv260_xsdb.sh" | tr -cd '\11\12\15\40-\176'
proc rd {a} { if {[catch {mrd -force -value $a} v]} { return "ERR" }; return [format 0x%08x $v] }
proc wr {a d} { if {[catch {mwr -force $a $d} e]} { return "ERR" }; return ok }
proc st {tag} { puts "$tag: S0=[rd 0xAFFFFFF0] W=[rd 0xAFFFFFF4] R=[rd 0xAFFFFFF8] S3=[rd 0xAFFFFFFC]" }
st before
puts "read LEN: [rd 0xA000000C]"
st after-read
puts "write RD_IDX<=2: [wr 0xA0000000 2]  readback [rd 0xA0000000]"
st after-write
TCL
