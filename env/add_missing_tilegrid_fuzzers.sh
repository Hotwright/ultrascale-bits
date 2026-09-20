#!/bin/bash
# Re-enable the four 002 sub-fuzzers that were dropped on the wrong criterion.
#
# They were removed because the tile types they are NAMED after have zero
# instances on the XCK26. That reasoning does not apply to them: each one
# scans for a SITE type and configures whatever tile happens to hold it, and
# nothing in any of them mentions its namesake tile type. The XCK26 simply has
# the left-hand variants where the ZU3EG had the right-hand ones:
#
#   rclk_pss_alto   BUFG_PS         96 sites in RCLK_INTF_LEFT_TERM_ALTO (4)
#   cmt_right       BUFCE_ROW       96 sites in CMT_L                    (4)
#   bitslice_tiles  BITSLICE_RX_TX 208 sites in XIPHY_BYTE_L            (16)
#   hpio_right      HPIOB_M/S      164 sites in HPIO_L                   (8)
#
# rclk_pss_alto is not optional. RCLK_INTF_LEFT_TERM_ALTO is where PL_CLK
# enters the fabric -- our FASM's PIP.CLK_BUFG_PS_0_CLK_IN.PS_TO_PL_CLK0 lives
# there -- and without a base address fasm2bit cannot place a single bit in it.
# The design would assemble into a bitstream whose clock is never connected.
#
# Run AFTER env/run_uray_fuzzers.sh 002 has finished. Each sub-fuzzer is built
# on its own first and only added to tilegrid.json's dependency list once its
# .tdb exists, because tilegrid.json depends on EVERY listed .tdb: adding one
# that cannot succeed means make never reaches the final target, however it
# fails.
set -u
R="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
JOBS="${URAY_JOBS:-4}"
source "$R/env/uray_env.sh" zynq_usp_5ev || exit 1
. "$R/prjuray/env/bin/activate"
export PYTHONPATH="$R/prjuray:${PYTHONPATH:-}"
F="$R/prjuray/fuzzers/002-tilegrid"
MK="$F/Makefile"
BF="build_$URAY_PART"

cd "$F" || exit 1
ok=()
for s in rclk_pss_alto cmt_right bitslice_tiles hpio_right; do
    if [ -f "$s/$BF/segbits_tilegrid.tdb" ]; then
        echo "=== $s: already built ==="; ok+=("$s"); continue
    fi
    echo "=== $s: building $(date -Is) ==="
    if make -j"$JOBS" "$s/$BF/segbits_tilegrid.tdb"; then
        echo "=== $s: OK ==="; ok+=("$s")
    else
        echo "=== $s: FAILED -- left out of the dependency list ==="
    fi
done

[ ${#ok[@]} -gt 0 ] || { echo "nothing built; tilegrid unchanged" >&2; exit 1; }

echo
echo "=== adding to TILEGRID_TDB_DEPENDENCIES: ${ok[*]} ==="
cp -n "$MK" "$MK.orig" 2>/dev/null || true
for s in "${ok[@]}"; do
    grep -q "^ *$s/\$(BUILD_FOLDER)/segbits_tilegrid.tdb" "$MK" && continue
    # Append to the last entry of the list, which has no trailing backslash.
    python3 - "$MK" "$s" <<'PY'
import re, sys
mk, sub = sys.argv[1], sys.argv[2]
s = open(mk).read()
m = re.search(r"(TILEGRID_TDB_DEPENDENCIES \+= .*?segbits_tilegrid\.tdb)(?!\s*\\)",
              s, re.S)
if not m:
    sys.exit(f"could not find the end of TILEGRID_TDB_DEPENDENCIES in {mk}")
s = (s[:m.end()] + " \\\n                             "
     + f"{sub}/$(BUILD_FOLDER)/segbits_tilegrid.tdb" + s[m.end():])
open(mk, "w").write(s)
print(f"  added {sub}")
PY
done

echo
echo "=== regenerating tilegrid.json with the new .tdb files ==="
rm -f "$BF/tilegrid.json"
make -j"$JOBS" database || exit 1
make pushdb || exit 1

echo
echo "=== did RCLK_INTF_LEFT_TERM_ALTO get a base address? ==="
python3 - "$URAY_FAMILY_DIR/$URAY_PART/tilegrid.json" <<'PY'
import json, sys, collections
g = json.load(open(sys.argv[1]))
for want in ("RCLK_INTF_LEFT_TERM_ALTO", "CMT_L", "XIPHY_BYTE_L", "HPIO_L"):
    inst = [v for v in g.values() if v["type"] == want]
    have = sum(1 for v in inst if (v.get("bits") or {}).get("CLB_IO_CLK"))
    print(f"  {want:28s} {len(inst):3d} instances, {have:3d} addressed")
PY
echo
echo "now re-run ./env/finish_tilegrid.sh"
