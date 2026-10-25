#!/bin/bash
# KV260 block RAM board test: a 4096 x 8 ROM (one RAMB36E2, read width 9)
# played out to the Pmod LEDs. See rom.v for what the LEDs should show.
#
# Built with nextpnr-himbaechel (the UltraScale+ port, branch usp-himbaechel
# in eda-tools/nextpnr), not the legacy nextpnr-xilinx: only the former writes
# US+ BRAM FASM. Override NEXTPNR to point elsewhere.
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh rom.bit
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"

python3 gen_chase.py
yosys -q -p "read_verilog rom.v
             synth_xilinx -family xcup -flatten -top top
             write_json rom.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json rom.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=rom.fasm \
    --write rom_routed.json

# The features this drops are the documented bitless ones (SCOPE-K26.md):
# INT_INTF_R_PCIE4 IMUX pass-throughs, INT_INTF_L LOGIC_OUTS crossings (the
# tile type has no frames) and the clock-spine enables kv260_ps_blink also
# drops and works with.
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" rom.fasm --filter rom.filtered.fasm
