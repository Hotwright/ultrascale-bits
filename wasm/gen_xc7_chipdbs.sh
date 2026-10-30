#!/bin/bash
# Regenerate the Series-7 chipdbs hotc ships (web/nextpnr-xilinx-wasm, 15
# fabrics) from the usp-himbaechel nextpnr tree. A chipdb embeds the tree's
# constids.inc string table, which the UltraScale+ work extended, so chipdbs
# from the old tree fail to load in the new binary (idstring.cc assertion).
# Same sources as hotc's README: the four "local" fabrics from
# 0-xilinx-bits/xray-db-local, the rest from openXC7's prjxray-db.
#   wasm/gen_xc7_chipdbs.sh [fabric...]     -> work/chipdb7/chipdb-<fabric>.bin
# Two at a time: the large Kintex dies take up to 13.6 GB each.
set -e
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$(dirname "$HERE")/work/chipdb7}"
NEXTPNR_SRC="${NEXTPNR_SRC:-/mnt/i/Hotwright/eda-tools/nextpnr}"
GEN="$NEXTPNR_SRC/himbaechel/uarch/xilinx/gen/xilinx_gen.py"
BBASM="${BBASM:-$NEXTPNR_SRC/build-xilinx/bba/bbasm}"
LOCAL_DB="${LOCAL_DB:-/mnt/i/Hotwright/0-xilinx-bits/xray-db-local}"
OXC7_DB="${OXC7_DB:-/home/sc/openxc7/prjxray-db}"
LOCAL="xc7s25 xc7s50 xc7z010 xc7a50t"
ALL="$LOCAL xc7a100t xc7a200t xc7k70t xc7k160t xc7k325t xc7k480t xc7s100 xc7z020 xc7z030 xc7z045 xc7z100"
mkdir -p "$OUT"
family() { case $1 in xc7a*) echo artix7;; xc7k*) echo kintex7;; xc7s*) echo spartan7;; *) echo zynq7;; esac; }
one() {
    local f=$1 db=$OXC7_DB
    case " $LOCAL " in *" $f "*) db=$LOCAL_DB;; esac
    python3 "$GEN" --xray "$db/$(family "$f")" --device "$f" --bba "$OUT/chipdb-$f.bba" > "$OUT/$f.log" 2>&1 &&
    "$BBASM" --l "$OUT/chipdb-$f.bba" "$OUT/chipdb-$f.bin" >> "$OUT/$f.log" 2>&1 &&
    rm -f "$OUT/chipdb-$f.bba" && echo "ok $f $(stat -c%s "$OUT/chipdb-$f.bin")" || echo "FAIL $f (see $OUT/$f.log)"
}
export -f one family; export GEN BBASM LOCAL_DB OXC7_DB OUT LOCAL
printf '%s\n' ${@:-$ALL} | xargs -P 2 -I{} bash -c 'one {}'
