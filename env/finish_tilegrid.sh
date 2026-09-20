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
# being able to diff against the original is how a wrong span gets caught.
# Refresh .orig whenever the pushed tilegrid is newer, so re-running 002 does
# not leave us filling from a stale snapshot.
if [ ! -f "$TG.orig" ] || [ "$TG" -nt "$TG.orig" ]; then cp -p "$TG" "$TG.orig"; fi
python3 "$R/tools/fill_rclk_baseaddr.py" --cross-validate "$TG.orig" || {
    echo "cross-validation reported a WRONG prediction -- not filling" >&2; exit 1; }
python3 "$R/tools/fill_rclk_baseaddr.py" "$TG.orig" "$TG" || exit 1

echo
echo "=== 2. round-trip smoke test ==="
# Decode a bitstream we did NOT build, and check the result against what the
# fuzzer is known to have put in it. The subject is 002's own cle/specimen_003
# rather than 001-part-yaml's: 001's specimen exists to produce per-frame
# CRCs and may be near-trivial, so a feature count there proves little, while
# this one ships a params.csv naming all 13920 tiles it configured. That makes
# the check a round trip -- did the features come back in the right tiles --
# instead of a threshold.
SP="$R/prjuray/fuzzers/002-tilegrid/cle/build_$URAY_PART/specimen_003"
[ -f "$SP/design.bit" ] && [ -f "$SP/params.csv" ] || {
    echo "  no $SP/{design.bit,params.csv} -- skipping" >&2; exit 1; }
OUT="$R/work/smoke"; mkdir -p "$OUT"
# --verbose matters: without it a tile whose type has no segbits file is
# skipped in silence, so undecoded bits vanish rather than being reported.
python3 "$R/prjuray/utils/bit2fasm.py" --verbose \
    --db-root "$URAY_FAMILY_DIR" --part "$URAY_PART" \
    --architecture "$URAY_ARCH" --bitread "$URAY_TOOLS_DIR/bitread" \
    "$SP/design.bit" > "$OUT/specimen.fasm" 2> "$OUT/bit2fasm.err" || {
        echo "  bit2fasm FAILED:"; tail -20 "$OUT/bit2fasm.err"; exit 1; }

python3 - "$OUT/specimen.fasm" "$SP/params.csv" <<'PY' || exit 1
import csv, re, sys, collections
fasm, params = sys.argv[1], sys.argv[2]
want = set()
with open(params) as f:
    for row in csv.DictReader(f):
        want.add(row["tile"])
got = collections.Counter()
feats = 0
for line in open(fasm):
    line = line.split("#")[0].strip()
    if not line or line.startswith("{"):
        continue
    feats += 1
    got[line.split(".")[0]] += 1
hit = want & set(got)
print(f"  {feats} features over {len(got)} tiles;"
      f" params.csv names {len(want)}")
print(f"  tiles in both: {len(hit)}"
      f" ({100.0 * len(hit) / max(len(want), 1):.1f}% of the fuzzer's)")
if not feats:
    sys.exit("  FAIL: decoded nothing")
if len(hit) < 0.5 * len(want):
    sys.exit("  FAIL: most of the tiles the fuzzer configured came back with"
             " no features -- the tilegrid does not line up with the bitstream")
print("  OK: the decode lands in the tiles the fuzzer configured")
PY

echo
echo "=== 3. where the undecoded bits are ==="
# A regex or window-arithmetic bug in the locator reports zero bits, and zero
# reads as "Vivado set nothing there" -- the opposite conclusion. Check the
# tool before believing it.
python3 "$R/tools/locate_unknown_bits.py" --self-test --tilegrid "$TG" \
    | tail -3 || exit 1
python3 "$R/tools/locate_unknown_bits.py" "$OUT/specimen.fasm" \
    --tilegrid "$TG" | head -30

echo
echo "OK: tilegrid usable. Next: env/reference_build.sh"
