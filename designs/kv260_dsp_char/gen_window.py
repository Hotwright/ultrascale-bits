#!/usr/bin/env python3
"""Specimens that locate the DSP tile's frame window.

A PS-clocked counter on the Pmod (base, base2), and the same design plus one
DSP48E2 with default attributes at a known site. Diffing each against base
(tools/find_frame_window.py) gives the frame column, minors and words.

    gen_window.py <outdir>
"""
import os
import sys

HEAD = """module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    (* DONT_TOUCH = "TRUE" *) reg [63:0] ctr = 64'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;
    wire [47:0] p;
"""
DSP = """    (* DONT_TOUCH = "TRUE", LOC = "%s" *)
    DSP48E2 u (.CLK(clk), .A(ctr[29:0]), .B(ctr[47:30]), .C(ctr[63:16]), .D(ctr[26:0]),
               .ALUMODE(4'b0000), .INMODE(5'b00000), .OPMODE(9'b000110101), .CARRYIN(1'b0),
               .CARRYINSEL(3'b000), .CEA1(1'b1), .CEA2(1'b1), .CEAD(1'b1), .CEALUMODE(1'b1),
               .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b1), .CECARRYIN(1'b1), .CECTRL(1'b1), .CED(1'b1),
               .CEINMODE(1'b1), .CEM(1'b1), .CEP(1'b1), .RSTA(1'b0), .RSTALLCARRYIN(1'b0),
               .RSTALUMODE(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTCTRL(1'b0), .RSTD(1'b0),
               .RSTINMODE(1'b0), .RSTM(1'b0), .RSTP(1'b0), .P(p));
"""
TAIL_DSP = "    assign pmod = {^p, ctr[31:25]};\nendmodule\n"
TAIL = "    assign p = 48'd0;\n    assign pmod = {^p, ctr[31:25]};\nendmodule\n"

VARIANTS = {
    "base": None, "base2": None,
    "x4y0": "DSP48E2_X4Y0",     # DSP_X12Y0, the lower site
    "x4y1": "DSP48E2_X4Y1",     # DSP_X12Y0, the upper site
    "x4y2": "DSP48E2_X4Y2",     # DSP_X12Y5
    "x4y60": "DSP48E2_X4Y60",   # DSP_X12Y150, another clock region row
    "x0y0": "DSP48E2_X0Y0",     # DSP_X1Y0, another column
}

out = sys.argv[1]
for name, site in VARIANTS.items():
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "top.v"), "w") as f:
        f.write(HEAD + (DSP % site + TAIL_DSP if site else TAIL))
