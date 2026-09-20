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
# --verbose is not cosmetic: without it bit2fasm skips a tile whose type has no
# segbits file in silence, so bits we set there would vanish from the decode and
# the comparison below would call that a pass.
python3 "$R/prjuray/utils/bit2fasm.py" --verbose \
    --db-root "$URAY_FAMILY_DIR" --part "$URAY_PART" \
    --architecture "$URAY_ARCH" --bitread "$URAY_TOOLS_DIR/bitread" \
    "$BIT" > "$D/$NAME.roundtrip.fasm" || exit 1
echo "  decoded $(grep -c . "$D/$NAME.roundtrip.fasm") line(s)"

python3 - "$FASM" "$D/$NAME.roundtrip.fasm" "$URAY_FAMILY_DIR" "$TG" <<'PY' || exit 1
import glob, json, os, re, sys

fasm_in, fasm_out, db, tgpath = sys.argv[1:5]

# segbits key -> does it set at least one bit (as opposed to only clearing)
sets_a_bit = {}
for path in glob.glob(os.path.join(db, "segbits_*.db")):
    if "origin_info" in path:
        continue
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) >= 2:
                sets_a_bit[p[0]] = any(not b.startswith("!") for b in p[1:])

tg = json.load(open(tgpath))
TILE_INST = re.compile(r"_X-?\d+Y-?\d+$")
RANGE = re.compile(r"^(.*)\[(\d+):(\d+)\]$")
INDEX = re.compile(r"^(.*)\[(\d+)\]$")
VALUE = re.compile(r"^(\d+)'([hbdo])([0-9a-fA-F]+)$")


def load(path):
    """FASM -> {base feature: integer mask}, plus the set that was indexed.

    The assembler and the disassembler are each free to spell an indexed
    feature any way that is FASM-equivalent. We write
    `CLEL_R_X6Y151.ALUT.INIT[63:0] = 64'h8000000000000000`; bit2fasm writes
    `CLEL_R_X6Y151.ALUT.INIT[63]`. Comparing the text calls that a mismatch --
    and, far worse, calls two identical spellings carrying DIFFERENT values a
    match. So fold every indexed feature down to a number and compare numbers.
    """
    vals, indexed = {}, set()
    with open(path) as f:
        for line in f:
            line = line.split("#")[0].strip()
            if not line or line.startswith("{"):
                continue
            lhs, _, rhs = (x.strip() for x in line.partition("="))
            v = 1
            if rhs:
                m = VALUE.match(rhs.replace("_", ""))
                v = (int(m.group(3), {"b": 2, "o": 8, "d": 10, "h": 16}[m.group(2)])
                     if m else int(rhs, 0))
            m = RANGE.match(lhs) or INDEX.match(lhs)
            if m:
                base, lo = m.group(1), int(m.group(m.lastindex))
                indexed.add(base)
                vals[base] = vals.get(base, 0) | (v << lo)
            else:
                vals[lhs] = vals.get(lhs, 0) | v
    return vals, indexed


def seg_key(tile, feat, bit=None):
    ttype = tg[tile]["type"] if tile in tg else TILE_INST.sub("", tile)
    return "%s.%s%s" % (ttype, feat, "" if bit is None else "[%d]" % bit)


want, want_ix = load(fasm_in)
got, _ = load(fasm_out)

# A feature whose segbits are all "!"-prefixed CLEARS bits rather than setting
# them, so a bitstream containing it is identical to one without it and no
# decode can ever report it back. Requiring those would fail the build on
# features that are working exactly as intended.
required, clear_only, unknown = {}, 0, set()
for f, v in want.items():
    tile, _, feat = f.partition(".")
    if f in want_ix:
        mask = 0
        for i in range(v.bit_length()):
            if not (v >> i) & 1:
                continue
            obs = sets_a_bit.get(seg_key(tile, feat, i))
            if obs is None:
                unknown.add("%s[%d]" % (f, i))
            if obs is not False:          # unknown is required conservatively
                mask |= 1 << i
        clear_only += bin(v & ~mask).count("1")
        if mask:
            required[f] = mask
    else:
        obs = sets_a_bit.get(seg_key(tile, feat))
        if obs is None:
            unknown.add(f)
        if obs is not False:
            required[f] = v
        else:
            clear_only += 1

missing = {f: (m, got.get(f, 0)) for f, m in required.items()
           if (got.get(f, 0) & m) != m}
want_tiles = {f.partition(".")[0] for f in want}
extra = [f for f in got if f not in want and f.partition(".")[0] in want_tiles]

print("  asked for %d feature(s) over %d tile(s)" % (len(want), len(want_tiles)))
print("  %d observable, %d bit(s) clear-only and unobservable by construction"
      % (len(required), clear_only))
print("  decode returned %d feature(s); %d missing, %d unexpected in our tiles"
      % (len(got), len(missing), len(extra)))
if unknown:
    print("  (%d had no segbits key of their own and were required anyway)"
          % len(unknown))
for f in sorted(missing)[:10]:
    m, g = missing[f]
    print("    MISSING %s: wanted 0x%x, decoded 0x%x (short by 0x%x)"
          % (f, m, g, m & ~g))
for f in sorted(extra)[:5]:
    print("    EXTRA   %s = 0x%x" % (f, got[f]))
if missing:
    sys.exit("  FAIL: observable features we set did not survive the round trip")
print("  OK: every observable feature came back with the value we asked for")
PY

echo "=== .bit -> .bit.bin ==="
python3 "$R/tools/bit2binfile.py" "$BIT" "$D/$NAME.bit.bin" || exit 1
echo "  $(stat -c%s "$D/$NAME.bit.bin") bytes"
echo
echo "load with:  sudo fpgautil -b $NAME.bit.bin -f Full"
echo "check the PL clock first:  grep -A2 pl0 /sys/kernel/debug/clk/clk_summary"
