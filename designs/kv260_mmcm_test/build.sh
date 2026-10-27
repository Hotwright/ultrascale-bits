#!/bin/bash
# KV260 MMCM/PLL spec and board test (mmcm.v): two MMCMs and two PLLs,
# each output on its own LED.
#
# Built with nextpnr-himbaechel (branch usp-himbaechel in eda-tools/nextpnr).
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh mmcm.bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"

yosys -q -p "read_verilog mmcm.v
             synth_xilinx -family xcup -flatten -top top
             write_json mmcm.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json mmcm.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=mmcm.fasm \
    --write mmcm_routed.json

# The features this drops are the documented bitless ones (SCOPE-K26.md):
# INT_INTF_R_PCIE4 IMUX pass-throughs, INT_INTF_L LOGIC_OUTS crossings (the
# tile type has no frames) and the clock-spine enables kv260_ps_blink also
# drops and works with.
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" mmcm.fasm --filter mmcm.filtered.fasm
