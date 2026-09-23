#!/bin/bash
# Build a Vivado reference for one of the designs and diff its FASM against
# ours by feature class. See env/reference_build.tcl for why this is not Vivado
# in the design loop.
#
# Usage: ./env/reference_build.sh [<design-dir>]
#
# The default is kv260_ps_blink, and it has to be. The whole reason for
# spending a Vivado run is to see whether Vivado sets bits in
# RCLK_INTF_LEFT_TERM_ALTO, RCLK_CLEM_CLKBUF_L_X15Y149 and
# RCLK_RCLK_XIPHY_INNER_FT at Y149 -- and those sit on the PS-side clock
# route. kv260_pmod_blink takes its clock from an HDIO pin in bank 45 and
# never crosses them, so a reference built from it cannot answer the question
# however clean it comes out.
#
# A bare PS8 with only PLCLK connected does synthesize: it is a UNISIM
# primitive, and the PLCLK frequency is set by PS firmware rather than by the
# bitstream. Expect unconnected-pin warnings.
set -u
R="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
D="${1:-$R/designs/kv260_ps_blink}"
D="$( cd "$D" && pwd )"
source "$R/env/uray_env.sh" zynq_usp_5ev || exit 1
. "$R/prjuray/env/bin/activate"
export PYTHONPATH="$R/prjuray:${PYTHONPATH:-}"

SRC="${REF_SRC:-$( ls "$D"/*.v | head -1 )}"
# Prefer a Vivado-spelled XDC if the design ships one. The nextpnr file is not
# valid Tcl -- `[get_ports pmod[0]]` runs a command named `0` -- and it uses
# LOC where Vivado wants PACKAGE_PIN. Constraining the two tools differently
# would make the whole comparison meaningless, so this is not cosmetic.
XDC="${REF_XDC:-$( ls "$D"/*_vivado.xdc 2>/dev/null | head -1 )}"
if [ -z "$XDC" ]; then
    XDC="$( ls "$D"/*.xdc | grep -v _vivado | head -1 )"
    echo "WARNING: $(basename "$D") has no *_vivado.xdc, falling back to" >&2
    echo "         $(basename "$XDC"), which Vivado will almost certainly" >&2
    echo "         reject: an unbraced [get_ports foo[0]] is a Tcl command" >&2
    echo "         substitution, and LOC is not PACKAGE_PIN." >&2
fi
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
# --verbose is required, not cosmetic. A tile whose type has no segbits file is
# skipped in silence without it, so bits Vivado set in exactly the tiles this
# run is meant to investigate would never be reported at all.
python3 "$R/prjuray/utils/bit2fasm.py" --verbose \
    --db-root "$URAY_FAMILY_DIR" --part "$URAY_PART" \
    --architecture "$URAY_ARCH" --bitread "$URAY_TOOLS_DIR/bitread" \
    "$OUT/ref.bit" > "$OUT/ref.fasm" || exit 1
echo "  $(grep -c . "$OUT/ref.fasm") lines"

echo "=== does Vivado set bits in the three clock-spine tiles? ==="
# The question the whole run exists to answer. bit2fasm reports an undecoded
# bit by frame and word with no tile name, so locate_unknown_bits maps it back
# through the tilegrid's frame windows -- which is why finish_tilegrid.sh has
# to have filled the base addresses first.
python3 "$R/tools/locate_unknown_bits.py" "$OUT/ref.fasm" \
    --tilegrid "$URAY_FAMILY_DIR/$URAY_PART/tilegrid.json" \
    --tile RCLK_INTF_LEFT_TERM_ALTO_X0Y149 \
    --tile RCLK_CLEM_CLKBUF_L_X15Y149 \
    --tile RCLK_RCLK_XIPHY_INNER_FT_X16Y149
echo "  (bits present  => the enable we emit is real and must not be dropped)"
echo "  (no bits       => we are over-emitting and --filter is correct)"

echo "=== IO tiles, bit for bit ==="
# The only check in this tree that has ever found a MISSING feature. The FASM
# checker proves emitted subset of known and the round trip is closed loop, so
# neither can see something we never write -- that is how nextpnr shipping no
# OQ_MUX feature at all went unnoticed until this ran.
#
# Restricted to IO tiles on purpose. The two tools place logic differently, so
# a CLE diff is noise, but the XDC LOCs every pad to a package pin, so the same
# IO tile holds the same outputs in both bitstreams and a difference there is
# real.
"$URAY_TOOLS_DIR/bitread" --architecture "$URAY_ARCH" \
    --part_file "$URAY_FAMILY_DIR/$URAY_PART/part.yaml" \
    -o "$OUT/ref.frames" "$OUT/ref.bit" >/dev/null || exit 1
OURFRAMES="${OURS%.fasm}.frames"
if [ -f "$OURFRAMES" ]; then
    # HDIO and HPIO both: an HPIO design would otherwise silently diff nothing.
    IOTILES=$(grep -ohE '^H[DP]IO[A-Z_]*_X[0-9]+Y[0-9]+' "$OURS" | sort -u | sed 's/^/--tile /')
    python3 "$R/tools/diff_tile_bits.py" "$OUT/ref.frames" "$OURFRAMES" \
        --tilegrid "$URAY_FAMILY_DIR/$URAY_PART/tilegrid.json" \
        --segbits "$URAY_FAMILY_DIR/segbits_hdio_top_right.db" \
        $IOTILES || echo "  (differences above are real; see SCOPE-K26.md)"
else
    echo "  skipped: no $OURFRAMES -- run designs/make_bitstream.sh first"
fi

echo "=== feature classes: Vivado vs ours ==="
python3 "$R/tools/diff_fasm_classes.py" "$OUT/ref.fasm" "$OURS" \
    --tilegrid "$URAY_FAMILY_DIR/$URAY_PART/tilegrid.json" \
    | tee "$OUT/classes.diff"
