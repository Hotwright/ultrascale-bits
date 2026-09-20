#!/bin/bash
# Characterise the XCK26 with prjuray's per-part fuzzers.
#
# This is the ONE place Vivado is used: building the database, once per die,
# exactly as prjxray and prjuray themselves do. It is not in the path from
# Verilog to .bit -- designs/kv260_pmod_blink/build.sh has no vendor tool in it
# at all.
#
#   001-part-yaml  one Vivado run; gen_part_base_yaml derives the frame
#                  addressing from a per-frame-CRC bitstream.
#   002-tilegrid   one Vivado run to dump the tile list, then ~200 specimens
#                  across 20 sub-fuzzers to solve each tile's base frame
#                  address. This is the long pole -- expect hours.
#
# Both pushdb into prjuray/database/zynqusp/<part>/, which is the WRITABLE
# overlay (see mk_uray_overlay.sh). prjuray-db is the reference and is never
# written.
set -u
STAGE="${1:-all}"
R="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
source "$R/env/uray_env.sh" zynq_usp_5ev || exit 1
. "$R/prjuray/env/bin/activate"
export PYTHONPATH="$R/prjuray:${PYTHONPATH:-}"
echo "part=$URAY_PART  db=$URAY_FAMILY_DIR"

run_stage () {
    local dir="$1"
    echo "=== $dir : starting $(date -Is) ==="
    cd "$R/prjuray/fuzzers/$dir" || return 1
    if ! make database; then echo "=== $dir : DATABASE FAILED ==="; return 1; fi
    if ! make pushdb;   then echo "=== $dir : PUSHDB FAILED ==="; return 1; fi
    echo "=== $dir : done $(date -Is) ==="
}

case "$STAGE" in
  001) run_stage 001-part-yaml ;;
  002) run_stage 002-tilegrid ;;
  all) run_stage 001-part-yaml && run_stage 002-tilegrid ;;
  *)   echo "usage: $0 [001|002|all]" >&2; exit 2 ;;
esac
rc=$?
echo "=== part dir now holds: ==="
ls -la "$URAY_FAMILY_DIR/$URAY_PART" 2>/dev/null
exit $rc
