#!/bin/bash
# KV260 board test of hotc's tokenizer-sm block behind the zynq-ps8 bridge.
#   ./build.sh && ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh top.bit && ./test.sh
# yowasp-yosys, not the system yosys: the Hotstate engine's packed arrays need a
# newer front end. The block's generated files come from `make generate` there.
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
HOTC="${HOTC:-$ROOT/../hotc}"
BLK="$HOTC/blocks/ai/tokenizer-sm"
cd "$HERE"
make -s -C "$BLK" generate > /dev/null
cp "$BLK"/tokenizer_*.mem .
IP="$HOTC/IP"
yowasp-yosys -q -l yosys.log -p "read_verilog -sv top.v $HOTC/blocks/processors/zynq-ps8/ps8_axil.v \
    $BLK/tokenizer_sm_axil.v $BLK/tokenizer_template.v \
    $IP/hotstate.sv $IP/microcode.sv $IP/control.sv $IP/next_address.sv $IP/stack.sv $IP/switch.sv $IP/timer.sv $IP/variable.sv
  synth_xilinx -family xcup -flatten -nosrl -nolutram -nodsp -top top
  tee -o utilization.txt stat
  write_json top.json"
"$NEXTPNR" --device xck26-sfvc784-2LV-c --json top.json -o xdc=kv260_ps.xdc -o fasm=top.fasm --write top.routed.json 2>&1 | tee nextpnr.log | grep -E "Max frequency|ERROR"
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" top.fasm --filter top.filtered.fasm | grep -v "^   " | tail -2
