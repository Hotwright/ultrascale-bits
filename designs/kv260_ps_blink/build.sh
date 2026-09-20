#!/bin/bash
# The KV260 blinky as it has to be on hardware: clocked from the PS.
#
# The PMOD LED module is output only and no carrier pin is driven with a clock,
# so there is no external clock to use. PS8's PLCLK[0] is the one that exists.
# See ../kv260_pmod_blink/build.sh for the pin-clocked variant, which exercises
# the same writers through an HDIO input instead.
#
# -nocarry for the same reason as the other design: prjuray-db has no entry for
# CARRY8.CI.CIN, so a chained CARRY8 would assemble as constant zero.
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$HERE"

yosys -q -p "read_verilog blink_ps.v
             synth_xilinx -family xcup -flatten -nocarry -top top
             write_json blink_ps.json"

"$ROOT/nextpnr-xilinx/build/nextpnr-xilinx" \
    --chipdb "$ROOT/nextpnr-xilinx/xilinx/xck26.bin" \
    --json blink_ps.json \
    --xdc kv260_ps.xdc \
    --write blink_ps_routed.json \
    --fasm blink_ps.fasm

# prjuray's assembler does not ignore a feature it has never heard of --
# fasm_assembler.py collects every one and raises FasmLookupError, so a single
# stray name makes fasm2bit.py refuse the whole file. --filter writes a copy
# with the unknowns removed and names each one. SCOPE-K26.md says which tile
# types those are and why dropping them is safe.
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" blink_ps.fasm --filter blink_ps.filtered.fasm
