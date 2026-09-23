#!/bin/bash
# Export a device's routing graph from RapidWright as a nextpnr .bba.
#
# Run the class directly rather than from a jar: family.cmake builds a jar
# whose manifest carries the whole RapidWright classpath, and a JAR manifest
# line cannot exceed 72 bytes, so that path fails here.
#
# bbaexport.java is ported to the RapidWright 2026.1.0 API (6 call sites; see
# bbaexport.java.orig for the original). Heap has to be large - the exporter
# holds the full node graph, and XCK26 has 9.1M nodes.
set -e
cd "$(dirname "$0")"
DEV="${1:?usage: run_bbaexport.sh <device> <out.bba> [heap]}"
OUT="${2:?}"
HEAP="${3:-24g}"
# RapidWright lives in the sibling 7-series checkout (xilinx-bits, or
# 0-xilinx-bits). RAPIDWRIGHT_PATH overrides the search.
if [ -z "${RAPIDWRIGHT_PATH:-}" ]; then
    for d in ../xilinx-bits ../0-xilinx-bits; do
        [ -d "$d/RapidWright" ] && { RAPIDWRIGHT_PATH="$(cd "$d/RapidWright" && pwd -P)"; break; }
    done
fi
: "${RAPIDWRIGHT_PATH:?no RapidWright - set RAPIDWRIGHT_PATH, or check out xilinx-bits next to this repo}"
export RAPIDWRIGHT_PATH
exec java -Xmx"$HEAP" -cp "$(cat build-jar/classpath.txt)" \
    dev.fpga.rapidwright.bbaexport "$DEV" xilinx/constids.inc "$OUT"
