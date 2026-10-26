#!/bin/bash
# KV260 BUFGCE board test (bufgce.v): two CMT_L BUFGCEs with a shared
# fabric clock enable, one inverted; their counters take turns on the LEDs.
#
# Built with nextpnr-himbaechel (branch usp-himbaechel in eda-tools/nextpnr).
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh bufgce.bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"

yosys -q -p "read_verilog bufgce.v
             synth_xilinx -family xcup -flatten -top top
             write_json bufgce.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json bufgce.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=bufgce.fasm \
    --write bufgce_routed.json

# The features this drops are the documented bitless ones (SCOPE-K26.md):
# INT_INTF_R_PCIE4 IMUX pass-throughs, INT_INTF_L LOGIC_OUTS crossings (the
# tile type has no frames) and the clock-spine enables kv260_ps_blink also
# drops and works with.
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" bufgce.fasm --filter bufgce.filtered.fasm
