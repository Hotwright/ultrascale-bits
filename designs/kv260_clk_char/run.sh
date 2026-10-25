#!/bin/bash
# Build every specimen under build/ that has no design.features yet, JOBS at
# a time, on the Windows Vivado (the Linux install is unlicensed). Vivado is
# used here to characterise, never in the design flow.
#
#   python3 gen.py build 40 1 && ./run.sh
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-4}"
VIVADO="${VIVADO:-$HERE/../../../0-xilinx-bits/rw-fuzzers/env/vivado.sh}"
export XRAY_VIVADO_LINUX="${XRAY_VIVADO_LINUX-}"
one () {
    cd "$1" || return 1
    [ -s design.features ] && return 0
    "$VIVADO" -mode batch -nojournal -source ../../char.tcl -tclargs . > viv.out 2>&1
    if [ -s design.features ]; then echo "ok   $1"; else echo "FAIL $1"; fi
}
export -f one; export VIVADO
ls -d "$HERE"/build/specimen_* | xargs -P "$JOBS" -I{} bash -c 'one {}'
