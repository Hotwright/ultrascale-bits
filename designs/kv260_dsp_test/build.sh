#!/bin/bash
# KV260 DSP48E2 board test (dsp.v). DSP48E2 is behind -o unverified_dsp
# until its spec design matches Vivado.
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh dsp.bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"

# -nodsp: the references must be LUTs, not more DSPs.
yosys -q -p "read_verilog dsp.v
             synth_xilinx -family xcup -flatten -nosrl -nodsp -top top
             write_json dsp.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json dsp.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=dsp.fasm -o unverified_dsp=1

python3 "$ROOT/tools/check_fasm_vs_uraydb.py" dsp.fasm --filter dsp.filtered.fasm
