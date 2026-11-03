#!/bin/bash
# Reads kv260_bram_hold_test's counters from the PS debug port (no Linux needed):
#   ./build.sh && ../make_bitstream.sh . && ../../env/kv260_jtag_load.sh top.bit && ./test.sh
# PASS when both RAMs read the address their flip-flops held before the edge on
# every clock checked. Before nextpnr inverted the RAMB clock pins, every clock
# read address + 1 (the RAM ran on the other edge).
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
printf '%s\n' \
  'proc r {o} { return [mrd -force -value [expr {0xA0001000 + $o}]] }' \
  'after 500' \
  'puts [format "id %08x cycles %u ram0 bad %u (+1: %u) ram1 bad %u (+1: %u)" [r 0] [r 4] [r 8] [r 12] [r 24] [r 28]]' \
  | "$ROOT/env/kv260_xsdb.sh" | tr -cd '\11\12\15\40-\176' | tee "$HERE/test.out"
awk '/^id 5d9b0002/ { ok = ($4 > 1000000 && $7 == 0 && $12 == 0) } END { print ok ? "BRAM-HOLD PASS" : "BRAM-HOLD FAIL"; exit !ok }' "$HERE/test.out"
