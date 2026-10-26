#!/usr/bin/env python3
"""Random specimens for the CMT_L characterisation: clock buffers, MMCM, PLL.

Each specimen places a random set of BUFGCE, BUFGCE_DIV and BUFGCTRL on
random sites of the four CMT_L tiles (loc.txt), with random attributes and
inputs (a fabric signal, the PS clock, or an MMCM/PLL output). Sometimes it adds
an MMCME4 and PLLE4s. Every buffer clocks its own small counter, kept in a
random clock region (pblock), so its clock has to be distributed there.
char.tcl dumps the features Vivado used; solve.py (kv260_clk_char) solves them.

    gen.py <outdir> <count> [seed [first index]]
"""
import os
import random
import sys

REGIONS = ["X%dY%d" % (x, y) for x in range(3) for y in range(4)]
BOOL = ("1'b0", "1'b1")


class Spec:
    def __init__(self, rng):
        self.rng = rng
        self.v = []
        self.locs = []
        self.regions = []   # (counter cell prefix, region)
        self.n = 0          # counters
        self.sig = 0        # fabric control bits drawn from ctr

    def fab(self):
        # A fabric signal: a bit of the PS-clocked counter.
        self.sig = (self.sig + 1) % 24
        return "ctr[%d]" % self.sig

    def load(self, clk):
        i = self.n
        self.n += 1
        self.v += ["    (* DONT_TOUCH = \"TRUE\" *) reg [7:0] q%d = 8'd0;" % i,
                   "    always @(posedge %s) q%d <= q%d + 1'b1;" % (clk, i, i),
                   "    assign msb[%d] = q%d[7];" % (i, i)]
        self.regions.append(("q%d_reg" % i, self.rng.choice(REGIONS)))

    def inv(self, *pins):
        return ["IS_%s_INVERTED(1'b%d)" % (p, self.rng.randrange(2)) for p in pins]


def specimen(rng, path):
    s = Spec(rng)
    # Site rules Vivado enforces (2026-10-26 trial specimens):
    #  - BUFGCE_X0Y<24r+t> drives only HROUTE/HDISTR track t, and two clocks
    #    on one track contend wherever their loads meet: every BUFGCE gets
    #    its own track, die-wide. Track 0 is the BUFG_PS's (BUFG_PS_X0Y72).
    #  - a BUFGCTRL or BUFGCE_DIV shares a site pair with a BUFGCE of its CMT
    #    (BUFGCTRL_X0Y2 against BUFGCE_X0Y7): BUFGCTRL k blocks BUFGCE
    #    3k..3k+2 and BUFGCE_DIV j blocks 6j..6j+5 of its CMT (conservative).
    #    They reach every track through the CMT_MUX_16_ENC muxes.
    tracks = list(range(1, 24))
    rng.shuffle(tracks)
    blocked = set()  # (cmt, BUFGCE index)
    ctrl = [(r, k) for r in range(4) for k in range(8)]
    div = [(r, j) for r in range(4) for j in range(4)]
    rng.shuffle(ctrl)
    rng.shuffle(div)

    def take(kind, r=None):
        if kind == "BUFGCTRL":
            r, k = ctrl.pop()
            blocked.update((r, i) for i in range(3 * k, 3 * k + 3))
            return "BUFGCTRL_X0Y%d" % (8 * r + k)
        if kind == "BUFGCE_DIV":
            r, j = div.pop()
            blocked.update((r, i) for i in range(6 * j, 6 * j + 6))
            return "BUFGCE_DIV_X0Y%d" % (4 * r + j)
        for t in tracks:
            cands = [c for c in range(4) if (r is None or c == r) and (c, t) not in blocked]
            if cands:
                tracks.remove(t)
                c = rng.choice(cands)
                return "BUFGCE_X0Y%d" % (24 * c + t)
        raise RuntimeError("no BUFGCE track left")

    nctrl, ndiv = rng.randint(0, 2), rng.randint(0, 2)
    sites_ctrl = [take("BUFGCTRL") for _ in range(nctrl)]
    sites_div = [take("BUFGCE_DIV") for _ in range(ndiv)]
    srcs = ["fab", "fab", "ps"]
    b = 0

    def src(kind):
        return s.fab() if kind == "fab" else "clk"

    # MMCM / PLL: one CMT each at most, outputs into BUFGCEs.
    pll_outs = []
    if rng.random() < 0.5:
        r = rng.randrange(4)
        outs = sorted(rng.sample(range(7), rng.randint(1, 3)))
        s.v += ["    wire mfb; wire [6:0] mo;",
                "    (* DONT_TOUCH = \"TRUE\" *) MMCME4_ADV #(.CLKIN1_PERIOD(10.0), .CLKFBOUT_MULT_F(10.0)%s) mmcm_i (" %
                "".join(", .CLKOUT%d_DIVIDE%s(%d)" % (o, "_F" if o == 0 else "", 10 + o) for o in outs),
                "        .CLKIN1(clk), .CLKIN2(1'b0), .CLKINSEL(1'b1), .CLKFBIN(mfb), .CLKFBOUT(mfb),",
                "        .CLKOUT0(mo[0]), .CLKOUT1(mo[1]), .CLKOUT2(mo[2]), .CLKOUT3(mo[3]), .CLKOUT4(mo[4]),",
                "        .CLKOUT5(mo[5]), .CLKOUT6(mo[6]), .LOCKED(msb[63]), .RST(%s), .PWRDWN(1'b0)," % s.fab(),
                "        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0),",
                "        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .CDDCREQ(1'b0));"]
        s.locs.append(("mmcm_i", "MMCM_X0Y%d" % r))
        pll_outs += [("mo[%d]" % o, r) for o in outs]
    pll_sites = ["PLL_X0Y%d" % i for i in range(8)]
    rng.shuffle(pll_sites)
    for p in range(2):
        if rng.random() < 0.3:
            site = pll_sites.pop()
            r = int(site[-1]) // 2
            outs = sorted(rng.sample(range(2), rng.randint(1, 2)))
            s.v += ["    wire pfb%d; wire [1:0] po%d;" % (p, p),
                    "    (* DONT_TOUCH = \"TRUE\" *) PLLE4_ADV #(.CLKIN_PERIOD(10.0), .CLKFBOUT_MULT(8)%s) pll%d (" %
                    ("".join(", .CLKOUT%d_DIVIDE(%d)" % (o, 8 + o) for o in outs), p),
                    "        .CLKIN(clk), .CLKFBIN(pfb%d), .CLKFBOUT(pfb%d), .CLKOUT0(po%d[0]), .CLKOUT1(po%d[1])," % (p, p, p, p),
                    "        .LOCKED(msb[%d]), .RST(%s), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0)," % (62 - p, s.fab()),
                    "        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));"]
            s.locs.append(("pll%d" % p, site))
            pll_outs += [("po%d[%d]" % (p, o), r) for o in outs]
    # PLL outputs: a BUFGCE in the same CMT.
    for net, r in pll_outs:
        site = take("BUFGCE", r)
        s.v += ["    wire b%d;" % b,
                "    (* DONT_TOUCH = \"TRUE\" *) BUFGCE b%d_i (.I(%s), .CE(1'b1), .O(b%d));" % (b, net, b)]
        s.locs.append(("b%d_i" % b, site))
        s.load("b%d" % b)
        b += 1
    for _ in range(rng.randint(3, 8)):
        site = take("BUFGCE")
        ce = s.fab() if rng.random() < 0.7 else "1'b1"
        params = ["CE_TYPE(\"%s\")" % rng.choice(["SYNC", "ASYNC"])] + s.inv("I", "CE")
        s.v += ["    wire b%d;" % b,
                "    (* DONT_TOUCH = \"TRUE\" *) BUFGCE #(%s) b%d_i (.I(%s), .CE(%s), .O(b%d));" %
                (", ".join("." + p for p in params), b, src(rng.choice(srcs)), ce, b)]
        s.locs.append(("b%d_i" % b, site))
        s.load("b%d" % b)
        b += 1
    for site in sites_div:
        params = ["BUFGCE_DIVIDE(%d)" % rng.randint(1, 8)] + s.inv("I", "CE", "CLR")
        s.v += ["    wire b%d;" % b,
                "    (* DONT_TOUCH = \"TRUE\" *) BUFGCE_DIV #(%s) b%d_i (.I(%s), .CE(%s), .CLR(%s), .O(b%d));" %
                (", ".join("." + p for p in params), b, src(rng.choice(srcs)), s.fab(), s.fab(), b)]
        s.locs.append(("b%d_i" % b, site))
        s.load("b%d" % b)
        b += 1
    for site in sites_ctrl:
        pre = rng.choice([(0, 0), (1, 0), (0, 1)])
        params = ["INIT_OUT(%d)" % rng.randrange(2), "PRESELECT_I0(\"%s\")" % ("TRUE" if pre[0] else "FALSE"),
                  "PRESELECT_I1(\"%s\")" % ("TRUE" if pre[1] else "FALSE"),
                  "CE_TYPE_CE0(\"SYNC\")",
                  "CE_TYPE_CE1(\"SYNC\")"] + \
            s.inv("I0", "I1", "CE0", "CE1", "S0", "S1", "IGNORE0", "IGNORE1")
        s.v += ["    wire b%d;" % b,
                "    (* DONT_TOUCH = \"TRUE\" *) BUFGCTRL #(%s) b%d_i (.I0(%s), .I1(%s), .S0(%s), .S1(%s), .CE0(%s), .CE1(%s), .IGNORE0(%s), .IGNORE1(%s), .O(b%d));" %
                (", ".join("." + p for p in params), b, src(rng.choice(srcs)), src(rng.choice(srcs)),
                 s.fab(), s.fab(), s.fab(), s.fab(), s.fab(), s.fab(), b)]
        s.locs.append(("b%d_i" % b, site))
        s.load("b%d" % b)
        b += 1
    head = ["module top (output wire [7:0] pmod);",
            "    wire [3:0] plclk;",
            "    PS8 ps8_i (.PLCLK(plclk));",
            "    wire clk;",
            "    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));",
            "    (* DONT_TOUCH = \"TRUE\" *) reg [31:0] ctr = 32'd0;",
            "    always @(posedge clk) ctr <= ctr + 1'b1;",
            "    wire [63:0] msb;"]
    tail = ["    assign msb[60:%d] = 0;" % s.n if s.n <= 60 else "",
            "    assign pmod = {^msb, ctr[31:25]};", "endmodule", ""]
    v = head + s.v + tail
    if not any("msb[63]" in l for l in s.v):
        v.insert(-3, "    assign msb[63] = 1'b0;")
    for p in range(2):
        if not any("msb[%d]" % (62 - p) in l for l in s.v):
            v.insert(-3, "    assign msb[%d] = 1'b0;" % (62 - p))
    s.locs.append(("bufg_i", "BUFG_PS_X0Y72"))
    os.makedirs(path, exist_ok=True)
    open(os.path.join(path, "top.v"), "w").write("\n".join(v))
    with open(os.path.join(path, "loc.txt"), "w") as f:
        for c, site in s.locs:
            f.write("%s %s\n" % (c, site))
    with open(os.path.join(path, "regions.txt"), "w") as f:
        for c, reg in s.regions:
            f.write("%s %s\n" % (c, reg))


def main():
    out, count = sys.argv[1], int(sys.argv[2])
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    first = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    rng = random.Random(seed)
    for i in range(first, first + count):
        specimen(rng, os.path.join(out, "specimen_%03d" % i))


if __name__ == "__main__":
    main()
