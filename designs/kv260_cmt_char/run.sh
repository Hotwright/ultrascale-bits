#!/bin/bash
# Build every specimen under build/ that has no design.features yet, JOBS at
# a time, on the Windows Vivado (characterisation only, never in the design
# flow). Keep JOBS=1 while Windows commit is tight.
#
#   python3 gen.py build 8 1 && JOBS=1 ./run.sh
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-1}"
export VIVADO="${VIVADO:-$HERE/../../../0-xilinx-bits/rw-fuzzers/env/vivado.sh}"
export XRAY_VIVADO_LINUX="${XRAY_VIVADO_LINUX-}"
one () {
    cd "$1" || return 1
    [ -s design.features ] && return 0
    "$VIVADO" -mode batch -nojournal -source ../../char.tcl -tclargs . > viv.out 2>&1
    if [ -s design.features ]; then echo "ok   $1"; else echo "FAIL $1"; fi
}
export -f one
ls -d ${ONLY:-"$HERE"/build/specimen_*} | xargs -P "$JOBS" -I{} bash -c 'one {}'
