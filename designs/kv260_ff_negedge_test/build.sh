#!/bin/bash
# KV260 falling-edge flip-flop board test (negedge.v).
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh negedge.bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"


yosys -q -p "read_verilog negedge.v
             synth_xilinx -family xcup -flatten -nosrl -nodsp -top top
             write_json negedge.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json negedge.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=negedge.fasm

python3 "$ROOT/tools/check_fasm_vs_uraydb.py" negedge.fasm --filter negedge.filtered.fasm
