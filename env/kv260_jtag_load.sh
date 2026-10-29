#!/bin/bash
# Load a .bit into the KV260's PL over JTAG, then lift PS->PL isolation.
#
# Two things here are not optional, and both cost a day to find:
#
#  * The target is the K26's "PS TAP", not "PL". xsdb's `fpga` refuses with
#    "Multiple FPGA devices found" while the PL target is selected, and the
#    same hw_server chain may also hold another board (the Blackboard's
#    xc7z007s was there). The TAP is therefore picked by cable serial.
#
#  * After every load the PMU has to be asked to power up / un-isolate the PL
#    (REQ_PWRUP bit 23, the request xilfpga's XFpga_IsolationRestore makes).
#    A board that stops in U-Boot never makes it, and a JTAG load re-masks it,
#    so without this PL_CLK0 and every other PS->PL signal reads as a constant
#    and nothing clocked by the PS runs -- Vivado's bitstreams included. The
#    REQ_ISO request (0xFFD80318/0xFFD80320) looks like the right register and
#    is not: its mask write does not land.
#
# Usage: env/kv260_jtag_load.sh <file.bit>
#   KV260_CABLE  cable serial glob   (default XFL11V5BMUH4*)
#   XSDB_BAT     Windows xsdb        (default the 2024.2 install)
#   KV260_ICAP=1 hand the configuration port to the PL's ICAP afterwards:
#                CSU pcap_ctrl.PCAP_PR (0xFFCA3008 bit 0) resets to 1, the
#                PCAP, and while it is set an ICAPE3 gets no answer.
set -euo pipefail
BIT="${1:?usage: env/kv260_jtag_load.sh <file.bit>}"
[ -f "$BIT" ] || { echo "no such file: $BIT" >&2; exit 1; }
CABLE="${KV260_CABLE:-XFL11V5BMUH4*}"
XSDB="${XSDB_BAT:-E:\\Xilinx\\Vivado\\2024.2\\bin\\xsdb.bat}"

# xsdb runs on Windows, so both the script and the bitstream need Windows
# paths; the Tcl side wants forward slashes.
WBIT="$(wslpath -m "$(readlink -f "$BIT")")"
TCL="$(mktemp --suffix=.tcl)"
trap 'rm -f "$TCL"' EXIT
cat > "$TCL" <<EOF
connect
after 1500
# Linux on the board idles cores by powering them down, and hw_server
# holds a core that comes back out of reset ("Reset Catch"): Linux then
# waits on it forever (soft lockup). Let any such core go, and say so.
foreach t [split [targets] \n] {
    if {[regexp {^\s*(\d+)\*?\s+(Cortex-A53 #\d) \(Reset Catch} \$t -> id name]} {
        targets \$id; catch {con}
        puts "warning: released \$name from Reset Catch (on the board: disable cpuidle state1)"
    }
}
targets -set -nocase -filter {name =~ "PS TAP" && jtag_cable_serial =~ "$CABLE"}
fpga -file {$WBIT}
set st [fpga -config-status]
puts [lindex [split \$st \n] 0]
foreach l [split \$st \n] { if {[string match "*DONE PIN*" \$l] || [string match "*CRC ERROR*" \$l] || [string match "*IDCODE ERROR*" \$l]} { puts "  [string trim \$l]" } }
targets -set -nocase -filter {name =~ "PSU" && jtag_cable_serial =~ "$CABLE"}
mwr -force 0xFFD80118 0x00800000
if {([mrd -force -value 0xFFD80114] & 0x00800000) != 0} { error "REQ_PWRUP_INT_EN write did not land" }
mwr -force 0xFFD80120 0x00800000
for {set i 0} {\$i < 100} {incr i} { if {([mrd -force -value 0xFFD80110] & 0x00800000) == 0} break; after 10 }
if {\$i == 100} { error "PMU did not service the PL power-up request" }
puts "PL power-up request serviced (polls=\$i)"
EOF
if [ "${KV260_ICAP:-0}" = 1 ]; then cat >> "$TCL" <<EOF
puts [format "pcap_ctrl was 0x%08x" [mrd -force -value 0xFFCA3008]]
mwr -force 0xFFCA3008 0
puts [format "pcap_ctrl now 0x%08x (ICAP selected)" [mrd -force -value 0xFFCA3008]]
EOF
fi
cd /mnt/c && cmd.exe /c "$XSDB $(wslpath -w "$TCL")" 2>&1 | tr -d '\r' \
    | grep -vE '^\s*$|hw_server|Copyright|Build date|Ctrl-C|url: TCP|cygwin'
