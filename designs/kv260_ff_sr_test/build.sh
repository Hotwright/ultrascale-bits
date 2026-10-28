#!/bin/bash
# KV260 flip-flop SR/CE board test (ffsr.v).
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh ffsr.bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"


yosys -q -p "read_verilog ffsr.v
             synth_xilinx -family xcup -flatten -nosrl -nodsp -top top
             write_json ffsr.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json ffsr.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=ffsr.fasm

python3 "$ROOT/tools/check_fasm_vs_uraydb.py" ffsr.fasm --filter ffsr.filtered.fasm
