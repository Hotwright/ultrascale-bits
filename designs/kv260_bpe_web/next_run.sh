#!/bin/bash
# After a power cycle (board settled, console idle): known-good block test
# first, then the native BPE build with the step test.
R="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "== block test"; "$R/env/kv260_jtag_load.sh" "$R/designs/kv260_ps8_block_test/top.bit" 2>&1 | tail -1
"$R/designs/kv260_ps8_block_test/test.sh" 2>&1 | tail -3
echo "== native_s1 BPE"; "$R/env/kv260_jtag_load.sh" "$R/designs/kv260_bpe_web/native_s1/n.bit" 2>&1 | tail -1
"$R/designs/kv260_bpe_web/step.sh" 2>&1 | tail -26
