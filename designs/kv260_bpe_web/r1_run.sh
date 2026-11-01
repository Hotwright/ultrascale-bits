#!/bin/bash
# The seed-1 native build whose routed netlist is kept (native_r1/routed_s1.json):
# load it and run the step test, so a failure can be traced inside the netlist.
R="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"$R/env/kv260_jtag_load.sh" "$R/designs/kv260_bpe_web/native_r1/r1.bit" 2>&1 | tail -1
"$R/designs/kv260_bpe_web/step.sh" 2>&1 | tail -27
