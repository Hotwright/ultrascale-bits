#!/usr/bin/env python3
"""Check a candidate INIT/SRVAL encoding against every characterisation tile."""
import json, re, sys
sys.path.insert(0, "../../tools")
from diff_tile_bits import load, tile_bits
R = "../.."
grid = json.load(open(R + "/prjuray/database/zynqusp/xck26-sfvc784-2LV-c/tilegrid.json"))
variants = json.load(open("variants.json")); frames = load(sys.argv[1] + "/ref.frames")
pos = {}
for line in open(R + "/prjuray-db/zynqusp/segbits_bram.db"):
    f, *bits = line.split()
    m = re.match(r"BRAM\.RAMB18E2_([LU])\.(INIT_A|INIT_B|SRVAL_A|SRVAL_B)\[(\d+)\]$", f)
    if m:
        fo, bo = bits[0].split("_"); pos[(m.group(1), m.group(2), int(m.group(3)))] = (int(fo), int(bo))
pval = lambda s: int(s.split("'h")[1], 16)


def enc18(v, rw):
    """18K: stored {P1,P0,D15..D0}; a 9-bit-wide port's value is {P1,D15..8,P0,D7..0}."""
    if rw == 9:
        b = lambda i: (v >> i) & 1
        return (b(17) << 17) | (b(8) << 16) | (((v >> 9) & 0xFF) << 8) | (v & 0xFF)
    return v


def enc36(v, rw):
    """36K -> (L, U). Normalise to {P3..P0, D31..D0}, then data bit d goes to
    half d%2 bit d//2 and parity bit k to half k%2 bit 16 + k//2."""
    b = lambda i: (v >> i) & 1
    if rw == 9:   # {P3,D31..24,P2,D23..16,P1,D15..8,P0,D7..0}
        d = sum(((v >> (9 * u)) & 0xFF) << (8 * u) for u in range(4))
        p = sum(b(9 * u + 8) << u for u in range(4))
    elif rw == 18:  # {P3,P2,D31..16,P1,P0,D15..0}? try natural 18-unit order
        d = (v & 0xFFFF) | (((v >> 18) & 0xFFFF) << 16)
        p = ((v >> 16) & 3) | (((v >> 34) & 3) << 2)
    else:
        d, p = v & 0xFFFFFFFF, v >> 32
    L = U = 0
    for i in range(32):
        if (d >> i) & 1:
            if i % 2: U |= 1 << (i // 2)
            else: L |= 1 << (i // 2)
    for k in range(4):
        if (p >> k) & 1:
            if k % 2: U |= 1 << (16 + k // 2)
            else: L |= 1 << (16 + k // 2)
    return L, U


bad = 0
for v in variants:
    tb = tile_bits(frames, grid[v["tile"]]["bits"]["CLB_IO_CLK"])
    st = lambda h, p: sum(1 << i for i in range(18) if pos[(h, p, i)] in tb)
    for p in ("INIT_A", "INIT_B", "SRVAL_A", "SRVAL_B"):
        rw = v["params"].get("READ_WIDTH_" + p[-1])
        pv = pval(v["params"][p])
        if v["half"] == "36":
            exp, got = enc36(pv, rw), (st("L", p), st("U", p))
        else:
            exp, got = enc18(pv, rw), st(v["half"], p)
        if exp != got:
            bad += 1
            print("MISMATCH", v["half"], v["label"], p, "RW", rw, f"param={pv:036b}", "exp", exp, "got", got)
print("mismatches:", bad)
