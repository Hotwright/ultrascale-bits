#!/bin/bash
# Run roots.tcl on every specimen checkpoint that has no roots.txt yet.
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-3}"
export VIVADO="${VIVADO:-$HERE/../../../0-xilinx-bits/rw-fuzzers/env/vivado.sh}"
export XRAY_VIVADO_LINUX="${XRAY_VIVADO_LINUX-}"
one () {
    cd "$1" || return 1
    [ -s roots.txt ] && return 0
    "$VIVADO" -mode batch -nojournal -source ../../roots.tcl -tclargs . > roots.out 2>&1
    [ -s roots.txt ] && echo "ok   $1" || echo "FAIL $1"
}
export -f one
ls -d "$HERE"/build/specimen_* | xargs -P "$JOBS" -I{} bash -c 'one {}'
