#!/usr/bin/env bash
# Run a bare-metal ELF (sw/build.sh baremetal) on the KV260's A53 #0 over
# JTAG, then print what it wrote to its log and its exit code.
#
#   env/kv260_run_bm.sh <prog.elf> [seconds]     (default 2)
#
# This resets A53 #0 out from under whatever runs there: Linux or U-Boot
# stops. Power-cycle the board to get Linux back (a PS `rst -srst` does
# boot it, but leaves the USB hub dead).
set -euo pipefail
ELF="${1:?usage: env/kv260_run_bm.sh <prog.elf> [seconds]}"
SECS="${2:-2}"
CABLE="${KV260_CABLE:-XFL11V5BMUH4*}"
XSDB="${XSDB_BAT:-E:\\Xilinx\\Vivado\\2024.2\\bin\\xsdb.bat}"
NM="${NM:-$(command -v llvm-nm || command -v llvm-nm-18 || command -v nm)}"

sym() { "$NM" "$ELF" | awk -v s="$1" '$3 == s { print "0x" $1 }'; }
LOG=$(sym bm_log); LEN=$(sym bm_log_len); EXIT=$(sym bm_exit)
[ -n "$LOG" ] && [ -n "$LEN" ] && [ -n "$EXIT" ] || { echo "$ELF: no bm_log/bm_exit (not a sw/build.sh baremetal ELF?)" >&2; exit 1; }

WELF="$(wslpath -m "$(readlink -f "$ELF")")"
TCL="$(mktemp --suffix=.tcl)"
trap 'rm -f "$TCL"' EXIT
cat > "$TCL" <<TCL
connect
after 1500
targets -set -nocase -filter {name =~ "Cortex-A53 #0" && jtag_cable_serial =~ "$CABLE"}
catch {stop}
rst -processor
after 200
dow {$WELF}
con
after [expr {int($SECS * 1000)}]
catch {stop}
set n [mrd -force -value $LEN]
if {\$n > 8192} { set n 8192 }
set s ""
if {\$n > 0} {
    foreach w [mrd -force -value $LOG [expr {(\$n + 3) / 4}]] {
        for {set b 0} {\$b < 4} {incr b} { append s [format %c [expr {(\$w >> (8 * \$b)) & 0xff}]] }
    }
}
puts "---- log ----"
puts -nonewline [string range \$s 0 [expr {\$n - 1}]]
set e [mrd -force -value $EXIT]
puts [format "---- exit 0x%x  pc %s ----" \$e [lindex [rrd pc] 1]]
TCL
cd /mnt/c && cmd.exe /c "$XSDB $(wslpath -w "$TCL")" 2>&1 | tr -d '\r' \
    | grep -vE '^\s*$|hw_server|Copyright|Build date|Ctrl-C|url: TCP|cygwin|Downloading|Setting PC|Successfully|100%|Info: Cortex|reset is being triggered|bootloop at reset|-clear-registers option|Further warnings'
