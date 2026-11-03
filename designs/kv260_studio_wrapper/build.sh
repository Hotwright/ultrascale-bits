#!/bin/bash
# Studio's KV260 board wrapper, built natively: does its fan tap work?
#   ./build.sh && ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh top.bit && ../kv260_fan_ttc/test.sh
# YoWASP yosys (0.68) by default: the browser runs 0.67, not the distro 0.33.
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
YOSYS="${YOSYS:-yowasp-yosys}"
cd "$HERE"
"$YOSYS" -q -l yosys.log -p "read_verilog blinky.v blinky_board.v
             synth_xilinx -family xcup -flatten -nosrl -nodsp -nocarry -top blinky_board
             write_json top.json"
"$NEXTPNR" --device xck26-sfvc784-2LV-c --json top.json -o xdc=blinky_board.xdc -o fasm=top.fasm 2>&1 | tee nextpnr.log | grep -E "PS8|Max frequency|ERROR|Warning|fan_en_b"
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" top.fasm --filter top.filtered.fasm | grep -v "^   " | tail -3
