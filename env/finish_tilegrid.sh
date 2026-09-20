#!/bin/bash
# What has to happen after 002-tilegrid's `make pushdb`, before anything
# downstream can be trusted.
#
# Two steps, in this order:
#
#  1. Fill the base addresses 002 structurally cannot produce. A tile type with
#     no sites can never be fuzzed, and prjuray's hand-written fallbacks in
#     generate_full.py cover only the site-less types the ZU3EG has. On the
#     XCK26 that leaves RCLK_CLEM_CLKBUF_L (8) and RCLK_RCLK_XIPHY_INNER_FT (4)
#     with bits:{} -- invisible to fasm2bit, bit2fasm and every later fuzzer
#     alike. tools/fill_rclk_baseaddr.py derives them; see its header for why
#     prjuray's dx*0x100 rule does not hold and what the cross-validation says.
#
#  2. Smoke-test the round trip on a bitstream we did not build: 001's own
#     design.bit, through bit2fasm.py. If part.yaml plus tilegrid plus segbits
#     cannot decode a Vivado bitstream on this die, nothing downstream is worth
#     running, and it is much cheaper to learn that here than after a
#     place-and-route.
#
# The part directory under prjuray/database is a real directory; only the
# segbits_*.db beside it are symlinks into the READ-ONLY prjuray-db. Nothing
# here writes through those.
set -u
R="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
source "$R/env/uray_env.sh" zynq_usp_5ev || exit 1
. "$R/prjuray/env/bin/activate"
export PYTHONPATH="$R/prjuray:${PYTHONPATH:-}"

TG="$URAY_FAMILY_DIR/$URAY_PART/tilegrid.json"
[ -f "$TG" ] || { echo "no $TG -- run ./env/run_uray_fuzzers.sh 002 first" >&2; exit 1; }

echo "=== 1. base addresses ==="
python3 - "$TG" <<'PY'
import json, sys, collections
g = json.load(open(sys.argv[1]))
miss = collections.Counter(
    v["type"] for v in g.values()
    if v["type"].startswith("RCLK_") and not (v.get("bits") or {}).get("CLB_IO_CLK"))
print(f"  {len(g)} tiles; RCLK tiles with no base address, by type:")
for t, n in miss.most_common():
    print(f"    {n:4d}  {t}")
if not miss:
    print("    (none)")
PY

# Keep the pushed file recoverable: the filler is derived, not measured, and
# being able to diff against the original is how a wrong width gets caught.
[ -f "$TG.orig" ] || cp -p "$TG" "$TG.orig"
python3 "$R/tools/fill_rclk_baseaddr.py" --cross-validate "$TG.orig" || {
    echo "cross-validation reported a WRONG prediction -- not filling" >&2; exit 1; }
python3 "$R/tools/fill_rclk_baseaddr.py" "$TG.orig" "$TG" || exit 1

echo
echo "=== 2. round-trip smoke test: bit2fasm on 001's own bitstream ==="
BIT="$R/prjuray/fuzzers/001-part-yaml/build_$URAY_PART/specimen_001/design.bit"
[ -f "$BIT" ] || { echo "  no $BIT -- skipping" >&2; exit 1; }
OUT="$R/work/smoke"; mkdir -p "$OUT"
python3 "$R/prjuray/utils/bit2fasm.py" \
    --db-root "$URAY_FAMILY_DIR" --part "$URAY_PART" \
    --architecture "$URAY_ARCH" --bitread "$URAY_TOOLS_DIR/bitread" \
    "$BIT" > "$OUT/design.fasm" 2> "$OUT/bit2fasm.err" || {
        echo "  bit2fasm FAILED:"; tail -20 "$OUT/bit2fasm.err"; exit 1; }
n=$(grep -c . "$OUT/design.fasm")
echo "  decoded $n features -> $OUT/design.fasm"
# A decode that produces almost nothing is the failure mode to watch for: it
# exits 0 and looks like a clean result. 001's specimen is a real placed design.
[ "$n" -lt 100 ] && { echo "  only $n features -- that is not a decoded design" >&2; exit 1; }
echo "  top tile types:"
sed 's/_X[0-9]*Y[0-9]*\..*//' "$OUT/design.fasm" | sort | uniq -c | sort -rn | head -8 | sed 's/^/    /'
echo
echo "OK: tilegrid usable. Next: env/reference_build.sh"
