#!/bin/bash
# Re-run dump.tcl over the checkpoints of the given specimens (a feature the
# dump learned after they were built).   redump.sh build/specimen_000 ...
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VIVADO="${VIVADO:-$HERE/../../../0-xilinx-bits/rw-fuzzers/env/vivado.sh}"
export XRAY_VIVADO_LINUX="${XRAY_VIVADO_LINUX-}"
one () {
    cd "$1" || return 1
    "$VIVADO" -mode batch -nojournal -source ../../dump.tcl -tclargs . > redump.out 2>&1
    grep -q "XIPHY_INNER_FT.*WIRE" design.features && echo "ok   $1" || echo "FAIL $1"
}
export -f one
printf '%s\n' "$@" | xargs -P "${JOBS:-2}" -I{} bash -c 'one {}'
