#!/usr/bin/env python3
"""The CLK_BUFGCE_<n>_CLK_IN selects of the MMCM/PLL outputs: one code
table, 24 bit placements.

mux.py over kv260_cmt_char + this build (--min-frame 4) shows each BUFGCE
input mux selecting an MMCM/PLL output with a code of five bits (a..e) whose
letters do not depend on the mux, only where they sit. So, as enc.py does
for CLK_CMT_MUX_16_ENC:

  1. CODES: the letters of each of the 11 outputs, read off BUFGCE_13;
  2. per mux, the bit of each letter: set in every observed selection whose
     code has the letter, clear in every one whose code does not;
  3. every observed selection (singletons included) must equal its code
     under that placement.

BUFGCE_3 (BUFGCE_X0Y0) is never sampled: the PS clock always takes track 0.
Groups of six muxes share a frame pair, and the 04/05 and 06/07 groups agree
position by position (BUFGCE_27 and BUFGCE_6, ...), so BUFGCE_3 gets
BUFGCE_24's placement two frames up. Marked inferred.

    bufg_enc.py mux_solution.json > bufg_enc.corrections
"""
import json
import re
import sys

MMCM, PLL0, PLL1 = "CMT_MMCM_WITH_MEM_1_", "CMT_TXPLL_WITH_MEM_86_", "CMT_TXPLL_WITH_MEM_87_"
CODES = {MMCM + "CLKOUT0": "ac", MMCM + "CLKOUT1": "ace", MMCM + "CLKOUT2": "de", MMCM + "CLKOUT3": "cd",
         MMCM + "CLKOUT4": "cde", MMCM + "CLKOUT5": "abd", MMCM + "CLKOUT6": "ade",
         PLL0 + "CLKOUT0": "ce", PLL0 + "CLKOUT1": "ae", PLL1 + "CLKOUT0": "e", PLL1 + "CLKOUT1": "c"}


def bits_of(code, place):
    return sorted(place[c] for c in code)


def main():
    mux = json.load(open(sys.argv[1]))
    dsts = sorted((d for d in mux if re.match(r"CLK_BUFGCE_\d+_CLK_IN$", d)), key=lambda d: int(d.split("_")[2]))
    places, bad = {}, 0
    for d in dsts:
        obs = {l: set(v["bits"]) for l, v in mux[d].items() if l in CODES}
        if not obs:
            continue
        place = {}
        for c in "abcde":
            on = [b for l, b in obs.items() if c in CODES[l]]
            off = [b for l, b in obs.items() if c not in CODES[l]]
            cand = set.intersection(*on) - set().union(*off) if on else set()
            assert len(cand) == 1, (d, c, cand)
            place[c] = cand.pop()
        for l, b in obs.items():
            if set(bits_of(CODES[l], place)) != b:
                bad += 1
                print("# MISMATCH %s <- %s: %s vs %s" % (d, l, sorted(b), bits_of(CODES[l], place)), file=sys.stderr)
        places[d] = place
    # BUFGCE_3: BUFGCE_24's placement on frames 06/07 instead of 04/05
    up = {"04": "06", "05": "07"}
    places["CLK_BUFGCE_3_CLK_IN"] = {c: up[b[:2]] + b[2:] for c, b in places["CLK_BUFGCE_24_CLK_IN"].items()}
    print("# CLK_BUFGCE_<n>_CLK_IN <- MMCM/PLL CLKOUTn (designs/kv260_mmcm_char/bufg_enc.py):")
    print("# one code table, per-mux placement; %d muxes x %d sources, every observed" % (len(places), len(CODES)))
    print("# selection agrees (%d disagreements). BUFGCE_3 inferred (see bufg_enc.py)." % bad)
    for d in sorted(places, key=lambda d: int(d.split("_")[2])):
        for src in CODES:
            tail = "  # inferred" if d == "CLK_BUFGCE_3_CLK_IN" else ""
            print("CMT_L.PIP.%s.%s add-feature %s%s" % (d, src, " ".join(bits_of(CODES[src], places[d])), tail))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
