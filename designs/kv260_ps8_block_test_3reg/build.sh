#!/bin/bash
# KV260 board test of the hotc zynq-ps8 block (top.v).
#   ./build.sh && ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh top.bit && ./test.sh
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
BLOCK="${BLOCK:-$ROOT/../hotc/blocks/processors/zynq-ps8}"
cd "$HERE"
yosys -q -l yosys.log -p "read_verilog top.v $BLOCK/ps8_axil.v
             synth_xilinx -family xcup -flatten -nosrl -nodsp -top top
             write_json top.json"
"$NEXTPNR" --device xck26-sfvc784-2LV-c --json top.json -o xdc=kv260_ps.xdc -o fasm=top.fasm --write top.routed.json 2>&1 | tee nextpnr.log | grep -E "PS8|Max frequency|ERROR|Warning"
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" top.fasm --filter top.filtered.fasm | grep -v "^   " | tail -3
