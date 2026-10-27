#!/bin/bash
# KV260 PS-PL AXI board test (axi.v).
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh axi.bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"


yosys -q -p "read_verilog axi.v
             synth_xilinx -family xcup -flatten -nosrl -nodsp -top top
             write_json axi.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json axi.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=axi.fasm

python3 "$ROOT/tools/check_fasm_vs_uraydb.py" axi.fasm --filter axi.filtered.fasm
