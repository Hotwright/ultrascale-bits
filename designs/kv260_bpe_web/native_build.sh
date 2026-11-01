#!/bin/bash
# Native place-and-route of the BPE netlist that Agent-Hotwright's browser flow
# synthesizes (noirq.json, the tokenizer behind the hotc zynq-ps8 bridge).
#   ./native_build.sh <noirq.json> [seed] [outdir]   then: env/kv260_jtag_load.sh <outdir>/n.bit && ./test.sh
# native_fix/ (seed 1) is the build that wedged the PS before nextpnr b177a652
# (per-region BUFCE_LEAF IINV) and passes test.sh after it.
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
NEXTPNR="${NEXTPNR:-$ROOT/../eda-tools/nextpnr/build-xilinx/nextpnr-himbaechel}"
JSON="$(realpath "$1")"; SEED="${2:-1}"; OUT="$(realpath -m "${3:-$HERE/native_fix}")"
mkdir -p "$OUT"
"$NEXTPNR" --device xck26-sfvc784-2LV-c --json "$JSON" --seed "$SEED" -o fasm="$OUT/n.fasm" > "$OUT/npr.log" 2>&1
grep "Max frequency" "$OUT/npr.log" | tail -1
python3 "$ROOT/tools/check_fasm_vs_uraydb.py" "$OUT/n.fasm" --filter "$OUT/n.filtered.fasm" > /dev/null
rm "$OUT/n.fasm"
bash "$ROOT/designs/make_bitstream.sh" "$OUT" > "$OUT/mk.log" 2>&1
echo "wrote $OUT/n.bit"
