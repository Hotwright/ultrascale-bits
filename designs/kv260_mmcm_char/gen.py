#!/usr/bin/env python3
"""Random specimens for the MMCM/PLL configuration registers.

Every specimen uses all four MMCME4_ADVs and all eight PLLE4_ADVs, each with
random multiply, divides, phases, duty cycles and bandwidth, so that the
dynamic-reconfiguration (DRP) register fields the bitstream holds (XAPP888:
counter high/low times, edge, no-count, phase mux, delay time, fractional
settings, lock and filter tables) vary from instance to instance. drp.py
computes those fields from the parameters Vivado reports; solve_drp.py
locates each field bit in the frames.

The bitstream only encodes ratios, so the input period is a lie chosen to
keep the VCO and phase-detector frequencies legal (CLKIN1_PERIOD =
DIVCLK * MULT / Fvco). Every connected output drives a BUFGCE in its own CMT
and a small counter in that CMT's clock region (regions.txt names
the CMT's MMCM site; char.tcl turns it into the clock region); each BUFGCE in a row has its
own clock track.

    gen.py <outdir> <count> [seed [first index]]
"""
import json
import math
import os
import random
import sys

# Kria K26 (-2LV) limits, MHz. Vivado's DRC quotes the ones it enforces.
MMCM_VCO = (820.0, 1580.0)
MMCM_PFD = (11.0, 480.0)
PLL_VCO = (760.0, 1480.0)
PLL_PFD = (72.0, 640.0)
FIN_MAX = 780.0
FOUT_MAX = 600.0      # a connected output into a BUFGCE


def pick_phase(rng, divide, pll=False):
    """A phase Vivado accepts (DRC AVAL-168/169 on the K26).

    MMCM: a multiple of 45 / divide degrees (an eighth of a VCO cycle), at
    most 63.875 * 360 / divide (the 6-bit delay counter). Sometimes spelled
    negative (Vivado adds 360). PLL: a multiple of 360 / divide only.
    """
    if rng.random() < 0.3:
        return 0.0
    if pll:
        k = rng.randint(0, min(divide - 1, 63))
        return round(k * 360.0 / divide, 3)
    k = rng.randint(0, min(8 * divide - 1, 511))
    ph = k * 45.0 / divide
    if ph > 0 and rng.random() < 0.2:
        ph -= 360.0
    return round(ph, 3)


def pick_duty(rng, divide):
    # Achievable duty cycles are k / (2 * divide).
    if divide == 1 or rng.random() < 0.4:
        return 0.5
    k = rng.randint(2, 2 * divide - 2)
    return round(k / (2.0 * divide), 4)


def mmcm(rng, r, used_out):
    p = {}
    frac_m = rng.random() < 0.4
    while True:
        m = rng.randint(2, 127) + (rng.randint(1, 7) / 8.0 if frac_m else 0)
        vco = rng.uniform(max(MMCM_VCO[0], m * MMCM_PFD[0]), min(MMCM_VCO[1], m * MMCM_PFD[1]))
        if vco < MMCM_VCO[0] or vco > MMCM_VCO[1]:
            continue
        pfd = vco / m
        dmax = min(106, int(FIN_MAX / pfd))
        if dmax >= 1:
            break
    d = rng.randint(1, dmax)
    fin = pfd * d
    p["CLKFBOUT_MULT_F"] = m
    p["DIVCLK_DIVIDE"] = d
    p["CLKIN1_PERIOD"] = p["CLKIN2_PERIOD"] = round(1000.0 / fin, 3)
    if not frac_m:
        p["CLKFBOUT_PHASE"] = pick_phase(rng, int(m))
    p["BANDWIDTH"] = rng.choice(["OPTIMIZED", "HIGH", "LOW"])
    p["COMPENSATION"] = rng.choice(["AUTO", "INTERNAL"])
    p["STARTUP_WAIT"] = rng.choice(["FALSE", "TRUE"])
    p["CLKOUT4_CASCADE"] = rng.choice(["FALSE", "FALSE", "TRUE"])
    omin = int(math.ceil(vco / FOUT_MAX))
    frac_o0 = rng.random() < 0.4
    for o in range(7):
        conn = o in used_out
        lo = max(omin, 2 if (o == 0 and frac_o0) else 1) if conn else 1
        div = rng.randint(lo, 128)
        if o == 0:
            if frac_o0 and div < 128:
                div = div + rng.randint(1, 7) / 8.0
            p["CLKOUT0_DIVIDE_F"] = div
        else:
            p["CLKOUT%d_DIVIDE" % o] = div
        fractional = div != int(div)
        # A fractional CLKOUT0 takes CLKOUT5's phase/duty logic, a
        # fractional CLKFBOUT takes CLKOUT6's: leave those at their defaults.
        shared = (o == 5 and frac_o0) or (o == 6 and frac_m)
        if not fractional and not shared:
            p["CLKOUT%d_PHASE" % o] = pick_phase(rng, int(div))
            p["CLKOUT%d_DUTY_CYCLE" % o] = pick_duty(rng, int(div))
    for pin in ("RST", "PWRDWN", "PSEN", "PSINCDEC", "CLKINSEL"):
        p["IS_%s_INVERTED" % pin] = rng.randrange(2)
    return p


def pll(rng):
    p = {}
    while True:
        m = rng.randint(1, 19)
        lo, hi = max(PLL_VCO[0], m * PLL_PFD[0]), min(PLL_VCO[1], m * PLL_PFD[1])
        if lo < hi:
            break
    vco = rng.uniform(lo, hi)
    pfd = vco / m
    dmax = min(15, int(FIN_MAX / pfd))
    d = rng.randint(1, max(1, dmax))
    p["CLKFBOUT_MULT"] = m
    p["DIVCLK_DIVIDE"] = d
    p["CLKIN_PERIOD"] = round(1000.0 / (pfd * d), 3)
    p["CLKFBOUT_PHASE"] = pick_phase(rng, m, pll=True)
    p["COMPENSATION"] = rng.choice(["AUTO", "INTERNAL"])
    p["STARTUP_WAIT"] = rng.choice(["FALSE", "TRUE"])
    omin = int(math.ceil(vco / FOUT_MAX))
    for o in range(2):
        div = rng.randint(omin, 128)
        p["CLKOUT%d_DIVIDE" % o] = div
        p["CLKOUT%d_PHASE" % o] = pick_phase(rng, div, pll=True)
        p["CLKOUT%d_DUTY_CYCLE" % o] = pick_duty(rng, div)
    for pin in ("RST", "PWRDWN"):
        p["IS_%s_INVERTED" % pin] = rng.randrange(2)
    return p


def fmt(v):
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, float):
        return "%.3f" % v if abs(v * 1000 - round(v * 1000)) < 1e-9 else repr(v)
    return str(v)


def params(p):
    return ", ".join(".%s(%s)" % (k, fmt(v)) for k, v in sorted(p.items()))


def specimen(rng, path):
    v = ["module top (output wire [7:0] pmod);",
         "    wire [3:0] plclk;",
         "    PS8 ps8_i (.PLCLK(plclk));",
         "    wire clk;",
         "    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));",
         "    (* DONT_TOUCH = \"TRUE\" *) reg [31:0] ctr = 32'd0;",
         "    always @(posedge clk) ctr <= ctr + 1'b1;",
         "    wire [63:0] msb;"]
    locs, regions, intent = [("bufg_i", "BUFG_PS_X0Y72")], [], {}
    n = 0       # counters
    sig = [0]

    def fab():
        sig[0] = (sig[0] + 1) % 24
        return "ctr[%d]" % sig[0]

    for r in range(4):
        tracks = list(range(1, 24))
        rng.shuffle(tracks)
        outs = []
        # MMCM: each output connected with probability 0.8.
        used = [o for o in range(7) if rng.random() < 0.8]
        mp = mmcm(rng, r, used)
        intent["mmcm%d" % r] = mp
        v += ["    wire mfb%d; wire [6:0] mo%d;" % (r, r),
              "    (* DONT_TOUCH = \"TRUE\" *) MMCME4_ADV #(%s) mmcm%d (" % (params(mp), r),
              # Both inputs carry the same clock and CLKINSEL comes from the
              # fabric: Vivado's DRC (REQP-122) reads a tied CLKINSEL
              # literally, ignoring IS_CLKINSEL_INVERTED.
              "        .CLKIN1(clk), .CLKIN2(clk), .CLKINSEL(%s), .CLKFBIN(mfb%d), .CLKFBOUT(mfb%d)," %
              (fab(), r, r),
              "        " + ", ".join(".CLKOUT%d(mo%d[%d])" % (o, r, o) for o in range(7)) + ",",
              "        .LOCKED(msb[%d]), .RST(%s), .PWRDWN(1'b0)," % (48 + r, fab()),
              "        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0),",
              "        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .CDDCREQ(1'b0));"]
        locs.append(("mmcm%d" % r, "MMCM_X0Y%d" % r))
        outs += ["mo%d[%d]" % (r, o) for o in used]
        for k in range(2):
            q = 2 * r + k
            pp = pll(rng)
            intent["pll%d" % q] = pp
            pused = [o for o in range(2) if rng.random() < 0.85]
            v += ["    wire pfb%d; wire [1:0] po%d;" % (q, q),
                  "    (* DONT_TOUCH = \"TRUE\" *) PLLE4_ADV #(%s) pll%d (" % (params(pp), q),
                  "        .CLKIN(clk), .CLKFBIN(pfb%d), .CLKFBOUT(pfb%d), .CLKOUT0(po%d[0]), .CLKOUT1(po%d[1])," %
                  (q, q, q, q),
                  "        .LOCKED(msb[%d]), .RST(%s), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0)," % (52 + q, fab()),
                  "        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));"]
            locs.append(("pll%d" % q, "PLL_X0Y%d" % q))
            outs += ["po%d[%d]" % (q, o) for o in pused]
        for net in outs:
            t = tracks.pop()
            v += ["    wire b%d;" % n,
                  "    (* DONT_TOUCH = \"TRUE\" *) BUFGCE b%d_i (.I(%s), .CE(1'b1), .O(b%d));" % (n, net, n),
                  "    (* DONT_TOUCH = \"TRUE\" *) reg [7:0] q%d = 8'd0;" % n,
                  "    always @(posedge b%d) q%d <= q%d + 1'b1;" % (n, n, n),
                  "    assign msb[%d] = q%d[7];" % (n, n)]
            locs.append(("b%d_i" % n, "BUFGCE_X0Y%d" % (24 * r + t)))
            regions.append(("q%d_reg" % n, "MMCM_X0Y%d" % r))
            n += 1
    assert n <= 44
    v += ["    assign msb[47:%d] = 0;" % n,
          "    assign msb[63:60] = 0;",
          "    assign pmod = {^msb, ctr[31:25]};", "endmodule", ""]
    os.makedirs(path, exist_ok=True)
    open(os.path.join(path, "top.v"), "w").write("\n".join(v))
    with open(os.path.join(path, "loc.txt"), "w") as f:
        f.writelines("%s %s\n" % l for l in locs)
    with open(os.path.join(path, "regions.txt"), "w") as f:
        f.writelines("%s %s\n" % l for l in regions)
    json.dump(intent, open(os.path.join(path, "intent.json"), "w"), indent=1, sort_keys=True)


def main():
    out, count = sys.argv[1], int(sys.argv[2])
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    first = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    rng = random.Random(seed)
    for i in range(first, first + count):
        specimen(rng, os.path.join(out, "specimen_%03d" % i))


if __name__ == "__main__":
    main()
