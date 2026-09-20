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
# The strongest check available without hardware. Every feature we asked for
# should come back; anything missing means the assembler and disassembler
# disagree about it, which no amount of checking against the db would show.
python3 "$R/prjuray/utils/bit2fasm.py" \
    --db-root "$URAY_FAMILY_DIR" --part "$URAY_PART" \
    --architecture "$URAY_ARCH" --bitread "$URAY_TOOLS_DIR/bitread" \
    "$BIT" > "$D/$NAME.roundtrip.fasm" || exit 1
python3 - "$FASM" "$D/$NAME.roundtrip.fasm" <<'PY' || exit 1
import sys
def feats(p):
    out = set()
    for line in open(p):
        line = line.split("#")[0].strip()
        if line and not line.startswith("{"):
            out.add(line.split()[0].rstrip("=").strip())
    return out
want, got = feats(sys.argv[1]), feats(sys.argv[2])
missing, extra = want - got, got - want
print(f"  asked for {len(want)}, got back {len(got)}")
print(f"  missing {len(missing)}, unexpected {len(extra)}")
for f in sorted(missing)[:10]:
    print(f"    MISSING {f}")
for f in sorted(extra)[:5]:
    print(f"    EXTRA   {f}")
if missing:
    sys.exit("  FAIL: features we set did not survive the round trip")
print("  OK: every feature survived")
PY

echo "=== .bit -> .bit.bin ==="
python3 "$R/tools/bit2binfile.py" "$BIT" "$D/$NAME.bit.bin" || exit 1
echo "  $(stat -c%s "$D/$NAME.bit.bin") bytes"
echo
echo "load with:  sudo fpgautil -b $NAME.bit.bin -f Full"
echo "check the PL clock first:  grep -A2 pl0 /sys/kernel/debug/clk/clk_summary"
