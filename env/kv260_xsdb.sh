#!/bin/bash
# Run xsdb Tcl against the KV260's PSU target (the PS memory map through the
# DAP), as env/kv260_jtag_load.sh connects. The Tcl comes from stdin.
#
#   echo 'puts [format 0x%08x [mrd -force -value 0xA0000010]]' | env/kv260_xsdb.sh
#
# The Blackboard (xc7z007s) on the same chain is never targeted: the filter
# pins the K26's cable serial.
set -euo pipefail
CABLE="${KV260_CABLE:-XFL11V5BMUH4*}"
XSDB="${XSDB_BAT:-E:\\Xilinx\\Vivado\\2024.2\\bin\\xsdb.bat}"
TCL="$(mktemp --suffix=.tcl)"
trap 'rm -f "$TCL"' EXIT
{
    echo 'connect'
    echo 'after 1500'
    echo "targets -set -nocase -filter {name =~ \"PSU\" && jtag_cable_serial =~ \"$CABLE\"}"
    cat
} > "$TCL"
cd /mnt/c && cmd.exe /c "$XSDB $(wslpath -w "$TCL")" 2>&1 | tr -d '\r' \
    | grep -vE '^\s*$|hw_server|Copyright|Build date|Ctrl-C|url: TCP|cygwin'
