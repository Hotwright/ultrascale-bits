#!/bin/bash
# Timing test: PL_CLK0 slowed from 100 MHz (IOPLL/10) to ${MHZ:-25} MHz by
# rewriting CRL_APB.PL0_REF_CTRL's first divisor over JTAG, then the rebuilt
# block test (current bridge) and the browser BPE build with the step test.
R="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIV=$((1000 / ${MHZ:-25}))
echo "== PL_CLK0 -> IOPLL/$DIV"
printf 'set v [mrd -force -value 0xFF5E00C0]\nputs [format "before 0x%%08x" $v]\nmwr -force 0xFF5E00C0 [expr {($v & ~0x3F00) | (%d << 8)}]\nputs [format "after  0x%%08x" [mrd -force -value 0xFF5E00C0]]\n' $DIV | "$R/env/kv260_xsdb.sh" | tr -cd '\11\12\15\40-\176'
echo "== block test v2 (current bridge)"
"$R/env/kv260_jtag_load.sh" "$R/designs/kv260_ps8_block_test_v2/top.bit" 2>&1 | tail -1
"$R/designs/kv260_ps8_block_test/test.sh" 2>&1 | tail -3
echo "== browser BPE (noirq)"
"$R/env/kv260_jtag_load.sh" "$R/designs/kv260_bpe_web/noirq/kv260_bpe_noirq_top.bit" 2>&1 | tail -1
"$R/designs/kv260_bpe_web/step.sh" 2>&1 | tail -27
