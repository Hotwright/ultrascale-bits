#!/bin/bash
# The used-vs-unused window specimens (gen_window.py) into build_window/.
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VIVADO="${VIVADO:-$HERE/../../../0-xilinx-bits/rw-fuzzers/env/vivado.sh}"
export XRAY_VIVADO_LINUX="${XRAY_VIVADO_LINUX-}"
for d in "$HERE"/build_window/*; do
    (cd "$d" && [ -s design.bit ] || "$VIVADO" -mode batch -nojournal -source ../../char_window.tcl -tclargs . > viv.out 2>&1)
    [ -s "$d/design.bit" ] && echo "ok   $d" || echo "FAIL $d"
done
