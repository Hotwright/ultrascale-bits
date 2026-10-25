#!/bin/bash
# Build every specimen under build/ that has no design.bit yet, on the
# Windows Vivado (characterisation only, never in the design flow).
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-3}"
export VIVADO="${VIVADO:-$HERE/../../../0-xilinx-bits/rw-fuzzers/env/vivado.sh}"
export XRAY_VIVADO_LINUX="${XRAY_VIVADO_LINUX-}"
one () {
    cd "$1" || return 1
    [ -s design.bit ] && return 0
    "$VIVADO" -mode batch -nojournal -source ../../char.tcl -tclargs . > viv.out 2>&1
    [ -s design.bit ] && echo "ok   $1" || echo "FAIL $1"
}
export -f one; export VIVADO
ls -d ${ONLY:-"$HERE"/build/*} | xargs -P "$JOBS" -I{} bash -c 'one {}'
