#!/usr/bin/env python3
"""The CLK_CMT_MUX_16_ENC_<k> selects: one code table, 24 bit placements.

mux.py showed that a source's select code does not depend on which of the 24
MUX_16_ENC muxes it drives: in every mux BUFGCE_<own> is one bit, BUFGCTRL
63 is three, and so on. With five select bits per mux (a..e), this fits:

  1. the code of every source, by letters (CODES below, read off mux.py for
     ENC_5 and ENC_13 and checked against the rest here);
  2. per mux, the bit carrying each letter: set in every instance whose
     selected source's code has the letter, clear in every one whose code
     does not (instances where the mux is unused say nothing);

then writes every <mux> <- <source> pip, observed or not, and checks each
mux's placement against every instance (none may disagree).

    enc.py [build] > enc.corrections
"""
import collections, glob, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "kv260_clk_char"))
import solve  # noqa: E402

CODES = {"BUFGCE": "c",
         "CLK_BUFGCTRL_WITH_OPTINVS_11_CLK_OUT": "e", "CLK_BUFGCTRL_WITH_OPTINVS_21_CLK_OUT": "ce",
         "CLK_BUFGCTRL_WITH_OPTINVS_32_CLK_OUT": "d", "CLK_BUFGCTRL_WITH_OPTINVS_42_CLK_OUT": "bc",
         "CLK_BUFGCTRL_WITH_OPTINVS_53_CLK_OUT": "be", "CLK_BUFGCTRL_WITH_OPTINVS_63_CLK_OUT": "bce",
         "CLK_BUFGCTRL_WITH_OPTINVS_74_CLK_OUT": "bd", "CLK_BUFGCTRL_WITH_OPTINVS_84_CLK_OUT": "ac",
         "CLK_BUFGCE_DIV_WITH_OPTINVS_22_CLK_OUT": "ae", "CLK_BUFGCE_DIV_WITH_OPTINVS_43_CLK_OUT": "ace",
         "CLK_BUFGCE_DIV_WITH_OPTINVS_64_CLK_OUT": "ad", "CLK_BUFGCE_DIV_WITH_OPTINVS_85_CLK_OUT": "abc"}


def code(src):
    return CODES["BUFGCE"] if re.match(r"CLK_BUFGCE_\d+_CLK_OUT$", src) else CODES.get(src)


# The placement, regular over all 24 (derived from the 21 muxes the data
# pins down completely, and checked against every instance below): muxes go
# in groups of six on a frame pair (A, B); in group position j, a and b sit at
# 1569+j on A and B, and c, d, e in a three-bit slot at 1575+3*(j//2) that
# alternates between the frames with j's parity.
PAIRS = [(6, 7), (4, 5), (9, 8), (11, 10)]


def formula(k):
    A, B = PAIRS[k // 6]
    j = k % 6
    s = 1575 + 3 * (j // 2) + (j % 2)
    if j % 2:
        c, d, e = (A, s), (A, s + 1), (B, s + 1)
    else:
        c, d, e = (B, s), (B, s + 1), (A, s)
    return {"a": (A, 1569 + j), "b": (B, 1569 + j), "c": c, "d": d, "e": e}


build = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "build")
grid = json.load(open(os.path.join(solve.PART_DIR, "tilegrid.json")))
cmts = sorted(t for t, v in grid.items() if v["type"] == "CMT_L")
inst = []
for spec in sorted(glob.glob(os.path.join(build, "specimen_*"))):
    f = os.path.join(spec, "design.nfeatures")
    if not os.path.exists(f):
        continue
    pips = collections.defaultdict(dict)
    for l in open(f):
        m = re.match(r"^(CMT_L_\w+)\.PIP\.(CLK_CMT_MUX_16_ENC_\d+_CLK_OUT)\.(\S+)$", l.strip())
        if m:
            pips[m.group(1)][m.group(2)] = m.group(3)
    frames = solve.frames_of(spec)
    for t in cmts:
        e = grid[t]["bits"]["CLB_IO_CLK"]
        inst.append((pips.get(t, {}), solve.config_bits(solve.tile_bits(frames, e), e)))

srcs_of = collections.defaultdict(set)  # mux -> BUFGCE source seen
ok = True
lines = []
for k in range(24):
    mux = "CLK_CMT_MUX_16_ENC_%d_CLK_OUT" % k
    used = [(p[mux], b) for p, b in inst if mux in p]
    unknown = {s for s, _ in used if code(s) is None}
    if unknown:
        print("# ENC_%d: sources with no code: %s" % (k, " ".join(sorted(unknown))), file=sys.stderr)
    used = [(s, b) for s, b in used if code(s) is not None]
    place = {}
    for L in "abcde":
        yes = [b for s, b in used if L in code(s)]
        no = [b for s, b in used if L not in code(s)]
        if not yes:
            continue
        cand = set.intersection(*yes) - (set().union(*no) if no else set())
        # the mux's own region (frames 4-11, bits 1560-1590) -- not other muxes
        cand = {c for c in cand if 1560 <= c[1] <= 1590}
        if len(cand) == 1:
            place[L] = cand.pop()
        else:
            print("# ENC_%d letter %s: %d candidates %s" % (k, L, len(cand),
                  " ".join(map(solve.bitname, sorted(cand)))), file=sys.stderr)
    f = formula(k)
    for L, b in place.items():
        if f[L] != b:
            print("# ENC_%d letter %s: data %s, formula %s" % (k, L, solve.bitname(b), solve.bitname(f[L])),
                  file=sys.stderr)
            ok = False
    place = f
    # every instance must agree with the placement
    bad = 0
    for s, b in used:
        want = {place[L] for L in code(s) if L in place}
        have = b & set(place.values())
        bad += want != have
    ok &= bad == 0
    bufgce = sorted({s for s, _ in used if code(s) == "c" and s.startswith("CLK_BUFGCE_")})
    print("# ENC_%d: %d instances, letters %s, %d disagree" % (
        k, len(used), " ".join("%s=%s" % (L, solve.bitname(place[L])) for L in "abcde" if L in place), bad),
        file=sys.stderr)
    for src, c in CODES.items():
        names = bufgce if src == "BUFGCE" else [src]
        for n in names:
            lines.append("CMT_L.PIP.%s.%s add-feature %s" % (mux, n, " ".join(solve.bitname(place[L]) for L in c)))
print("\n".join(lines))
sys.exit(0 if ok else 1)
