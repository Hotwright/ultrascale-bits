#!/bin/bash
# KV260 MMCM ROW_MID phase test (phase.v). One route, two bitstreams that
# differ only in MMCM_X0Y1's ROW_MID[0]: set/phase.bit and clr/phase.bit.
#
# Then: ../../env/kv260_jtag_load.sh set/phase.bit (or clr/)
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"

yosys -q -p "read_verilog ${DEFS:-} phase.v
             synth_xilinx -family xcup -flatten -nosrl -top top
             write_json phase.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json phase.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=phase.fasm

python3 "$ROOT/tools/check_fasm_vs_uraydb.py" phase.fasm --filter phase.filtered.fasm

# MMCM_X0Y1 is the MMCM site of CMT row 1, tile CMT_L_X16Y60.
BIT=CMT_L_X16Y60.MMCM_X0Y0.ROW_MID[0]
mkdir -p set clr
{ grep -vxF "$BIT" phase.filtered.fasm; echo "$BIT"; } > set/phase.filtered.fasm
grep -vxF "$BIT" phase.filtered.fasm > clr/phase.filtered.fasm
for v in set clr; do "$ROOT/designs/make_bitstream.sh" "$HERE/$v"; done
