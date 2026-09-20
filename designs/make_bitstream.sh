#!/bin/bash
# The last leg: filtered FASM -> .bit -> .bit.bin, with no vendor tool.
#
# Kept out of each design's build.sh because it needs tilegrid.json, which
# build.sh does not: a design can be placed, routed and checked against
# prjuray-db long before the die is fully characterised, and it is useful to
# keep that fast path working on its own.
#
# Usage: ./designs/make_bitstream.sh [<design-dir>]   (default kv260_ps_blink)
set -u
R="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
D="${1:-$R/designs/kv260_ps_blink}"
D="$( cd "$D" && pwd )"
source "$R/env/uray_env.sh" zynq_usp_5ev || exit 1
. "$R/prjuray/env/bin/activate"
export PYTHONPATH="$R/prjuray:${PYTHONPATH:-}"

TG="$URAY_FAMILY_DIR/$URAY_PART/tilegrid.json"
[ -f "$TG" ] || { echo "no tilegrid.json -- run env/run_uray_fuzzers.sh 002 then env/finish_tilegrid.sh" >&2; exit 1; }
FASM="$( ls "$D"/*.filtered.fasm 2>/dev/null | head -1 )"
[ -f "$FASM" ] || { echo "no *.filtered.fasm in $D -- run its build.sh first" >&2; exit 1; }
NAME="$( basename "${FASM%.filtered.fasm}" )"
BIT="$D/$NAME.bit"

echo "=== fasm2bit ==="
python3 "$R/prjuray/utils/fasm2bit.py" \
    --db-root "$URAY_FAMILY_DIR" --part "$URAY_PART" \
    --architecture "$URAY_ARCH" \
    --xcframes2bit "$URAY_TOOLS_DIR/xcframes2bit" \
    --frames-file "$D/$NAME.frames" \
    "$FASM" "$BIT" || exit 1
# fasm2bit exiting 0 is not enough. Handed a frames file with nothing in it,
# xcframes2bit pads the die out to a full all-zero bitstream and reports a
# perfectly normal frame count -- that is how a failed 7-series run once got
# mistaken for a good one.
nf=$( grep -c . "$D/$NAME.frames" 2>/dev/null || echo 0 )
[ "$nf" -gt 0 ] || { echo "  fasm2bit produced an empty frames file" >&2; exit 1; }
echo "  $nf frames written, $(stat -c%s "$BIT") bytes of .bit"

echo "=== round trip: decode our own bitstream back to FASM ==="
# The strongest check available without hardware: every feature we asked for
# that CAN be observed should come back. Anything missing means the assembler
# and the disassembler disagree, which no amount of checking against the db
# would reveal.
#
# "that can be observed" is the whole subtlety. A prjuray feature whose segbits
# are all !-prefixed CLEARS bits rather than setting them, so a bitstream
# containing it is identical to one without it and no decode can ever report it
# back. 180 of this design's 9011 features are like that -- every .V0 of a
# .V0/.V1 pair -- and requiring them would fail the build on features that are
# working exactly as intended.
python3 - "$FASM" "$D/$NAME.roundtrip.fasm" "$URAY_FAMILY_DIR" <<'PY' || exit 1
import collections, glob, os, re, sys

fasm_in, fasm_out, db = sys.argv[1], sys.argv[2], sys.argv[3]

# feature key -> does it set at least one bit
sets_a_bit = {}
for path in glob.glob(os.path.join(db, "segbits_*.db")):
    if "origin_info" in path:
        continue
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                sets_a_bit[parts[0]] = any(not b.startswith("!")
                                           for b in parts[1:])

TILE_INST = re.compile(r"_X-?\d+Y-?\d+$")


def feats(path):
    out = set()
    with open(path) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if line and not line.startswith("{"):
                out.add(line.split()[0].rstrip("=").strip())
    return out


want, got = feats(fasm_in), feats(fasm_out)
required, clear_only, unknown = set(), set(), set()
for f in want:
    tile, feature = f.split(".", 1)
    key = "%s.%s" % (TILE_INST.sub("", tile), feature)
    if key not in sets_a_bit:
        unknown.add(f)          # multi-bit keys like LUT.INIT[43] land here
        required.add(f)         # conservatively require them
    elif sets_a_bit[key]:
        required.add(f)
    else:
        clear_only.add(f)

missing, extra = required - got, got - want
print("  asked for %d, of which %d observable (%d clear only)"
      % (len(want), len(required), len(clear_only)))
print("  got back %d; missing %d, unexpected %d"
      % (len(got), len(missing), len(extra)))
if unknown:
    print("  (%d feature(s) had no exact segbits key and were required anyway)"
          % len(unknown))
for f in sorted(missing)[:10]:
    print("    MISSING %s" % f)
for f in sorted(extra)[:5]:
    print("    EXTRA   %s" % f)
if missing:
    sys.exit("  FAIL: observable features we set did not survive the round trip")
print("  OK: every observable feature survived")
PY

echo "=== .bit -> .bit.bin ==="
python3 "$R/tools/bit2binfile.py" "$BIT" "$D/$NAME.bit.bin" || exit 1
echo "  $(stat -c%s "$D/$NAME.bit.bin") bytes"
echo
echo "load with:  sudo fpgautil -b $NAME.bit.bin -f Full"
echo "check the PL clock first:  grep -A2 pl0 /sys/kernel/debug/clk/clk_summary"
