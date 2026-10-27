#!/bin/bash
# KV260 URAM288 board test (uram.v). URAM288 is behind -o unverified_uram
# until its spec design matches Vivado.
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh uram.bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"

# -nodsp: no DSPs in the checkers.
yosys -q -p "read_verilog uram.v
             synth_xilinx -family xcup -flatten -nosrl -nodsp -top top
             write_json uram.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json uram.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=uram.fasm -o unverified_uram=1

python3 "$ROOT/tools/check_fasm_vs_uraydb.py" uram.fasm --filter uram.filtered.fasm
