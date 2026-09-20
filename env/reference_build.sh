#!/bin/bash
# Build a Vivado reference for one of the designs and diff its FASM against
# ours by feature class. See env/reference_build.tcl for why this is not Vivado
# in the design loop.
#
# Usage: ./env/reference_build.sh [<design-dir>]
#   default designs/kv260_pmod_blink -- the pin-clocked variant. Prefer it as
#   the reference target: kv260_ps_blink instantiates a bare PS8 with only
#   PLCLK connected, which nextpnr accepts but Vivado will want configured.
set -u
R="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
D="${1:-$R/designs/kv260_pmod_blink}"
D="$( cd "$D" && pwd )"
source "$R/env/uray_env.sh" zynq_usp_5ev || exit 1
. "$R/prjuray/env/bin/activate"
export PYTHONPATH="$R/prjuray:${PYTHONPATH:-}"

SRC="${REF_SRC:-$( ls "$D"/*.v | head -1 )}"
XDC="${REF_XDC:-$( ls "$D"/*.xdc | head -1 )}"
OURS="${REF_OURS:-$( ls "$D"/*.fasm | grep -v filtered | head -1 )}"
OUT="$D/reference"

if [ ! -f "$URAY_FAMILY_DIR/$URAY_PART/tilegrid.json" ]; then
    echo "reference_build.sh: no tilegrid.json for $URAY_PART yet." >&2
    echo "  bit2fasm cannot run without it. Finish ./env/run_uray_fuzzers.sh 002 first." >&2
    exit 1
fi
for f in "$SRC" "$XDC" "$OURS"; do
    [ -f "$f" ] || { echo "reference_build.sh: missing $f" >&2; exit 1; }
done

mkdir -p "$OUT"
export REF_SRC="$SRC" REF_XDC="$XDC" REF_OUT="$OUT"
echo "reference: $(basename "$SRC") + $(basename "$XDC") -> $OUT/ref.bit"
"$URAY_VIVADO" -mode batch -nojournal -log "$OUT/vivado.log" \
    -source "$R/env/reference_build.tcl" || exit 1

echo "=== bit2fasm on the Vivado bitstream ==="
python3 "$R/prjuray/utils/bit2fasm.py" \
    --db-root "$URAY_FAMILY_DIR" --part "$URAY_PART" \
    --architecture "$URAY_ARCH" --bitread "$URAY_TOOLS_DIR/bitread" \
    "$OUT/ref.bit" > "$OUT/ref.fasm" || exit 1
echo "  $(grep -c . "$OUT/ref.fasm") features"

echo "=== feature classes: Vivado vs ours ==="
python3 "$R/tools/diff_fasm_classes.py" "$OUT/ref.fasm" "$OURS" \
    --tilegrid "$URAY_FAMILY_DIR/$URAY_PART/tilegrid.json" \
    | tee "$OUT/classes.diff"
