#!/bin/bash
# Synthesise and place-and-route the KV260 PMOD blinky for the XCK26, with no
# vendor tool anywhere in the flow.
#
# CARRY=0 (the default) asks yosys for a LUT-only ripple counter. That is not a
# style preference: prjuray-db has no entry for CARRY8.CI.CIN -- the fuzzer
# emits the tag, the solved database carries only CARRY8.CI.{AX,V0,V1} -- so a
# chained CARRY8 would assemble with both carry-in bits clear, which reads as
# constant zero and silently cuts the chain. Everything the -nocarry build uses
# is at 100% in tools/check_fasm_vs_uraydb.py. Set CARRY=1 to build the carry
# version anyway; nextpnr will warn once per chained CARRY8.
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CARRY="${CARRY:-0}"
SUFFIX=""; NOCARRY="-nocarry"
if [ "$CARRY" = "1" ]; then SUFFIX="_carry"; NOCARRY=""; fi

cd "$HERE"
yosys -q -p "read_verilog blink.v
             synth_xilinx -family xcup -flatten $NOCARRY -top top
             write_json blink${SUFFIX}.json"

"$ROOT/nextpnr-xilinx/build/nextpnr-xilinx" \
    --chipdb "$ROOT/nextpnr-xilinx/xilinx/xck26.bin" \
    --json blink${SUFFIX}.json \
    --xdc kv260_pmod.xdc \
    --write blink${SUFFIX}_routed.json \
    --fasm blink${SUFFIX}.fasm

# prjuray's assembler does not ignore a feature it has never heard of --
# fasm_assembler.py collects every one and raises FasmLookupError, so a single
# stray name makes fasm2bit.py refuse the whole file. --filter writes a copy
# with the unknowns removed and names each one.
#
# Dropping them is NOT known to be safe. Two of the eleven -- the HDISTR
# enables in RCLK_CLEM_CLKBUF_L and RCLK_RCLK_XIPHY_INNER_FT -- are on the
# clock spine in tile types the ZU3EG does not have, so prjuray-db has nothing
# for them and every characterised sibling does carry the enable. See
# SCOPE-K26.md; tools/explain_missing_feature.py gives the verdict per
# feature, and env/reference_build.sh is what settles it.
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" blink${SUFFIX}.fasm --filter blink${SUFFIX}.filtered.fasm
