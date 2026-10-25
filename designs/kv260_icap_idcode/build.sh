#!/bin/bash
# KV260 ICAPE3 board test: read the IDCODE back through the ICAP and show
# the verdict on the Pmod LEDs. See icap.v for what the LEDs should show.
#
# Built with nextpnr-himbaechel (branch usp-himbaechel in eda-tools/nextpnr).
# Override NEXTPNR to point elsewhere.
#
# Then: ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh icap.bit
# The ICAP answers only once the CSU gives it the configuration port; if the
# LEDs stay off, clear pcap_ctrl.PCAP_PR (bit 0 of CSU 0xFFCA3008), e.g. from
# Linux on the board: devmem 0xFFCA3008 32 0, or load with KV260_ICAP=1
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
cd "$HERE"

yosys -q -p "read_verilog icap.v
             synth_xilinx -family xcup -flatten -top top
             write_json icap.json"

"$NEXTPNR" --device xck26-sfvc784-2LV-c \
    --json icap.json \
    -o xdc=kv260_ps.xdc \
    -o fasm=icap.fasm \
    --write icap_routed.json

# The features this drops are the documented bitless ones (SCOPE-K26.md):
# INT_INTF_R_PCIE4 IMUX pass-throughs, INT_INTF_L LOGIC_OUTS crossings (the
# tile type has no frames) and the clock-spine enables kv260_ps_blink also
# drops and works with.
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" icap.fasm --filter icap.filtered.fasm
