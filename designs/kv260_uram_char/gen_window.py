#!/usr/bin/env python3
"""Specimens that locate the URAM tile's frame window.

A PS-clocked counter on the Pmod (base, base2), and the same design plus one
URAM288 with default attributes at a known site. Diffing each against base
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
    wire [71:0] q;
"""
URAM = """    (* DONT_TOUCH = "TRUE", LOC = "%s" *)
    URAM288 u (.CLK(clk), .ADDR_A({11'd0, ctr[11:0]}), .DIN_A({ctr[63:0], ctr[7:0]}),
               .EN_A(1'b1), .RDB_WR_A(ctr[12]), .BWE_A(9'h1ff), .DOUT_A(q),
               .ADDR_B(23'd0), .DIN_B(72'd0), .EN_B(1'b0), .RDB_WR_B(1'b0), .BWE_B(9'h000),
               .RST_A(1'b0), .RST_B(1'b0), .SLEEP(1'b0),
               .INJECT_SBITERR_A(1'b0), .INJECT_DBITERR_A(1'b0),
               .INJECT_SBITERR_B(1'b0), .INJECT_DBITERR_B(1'b0),
               .OREG_CE_A(1'b1), .OREG_CE_B(1'b1), .OREG_ECC_CE_A(1'b1), .OREG_ECC_CE_B(1'b1));
"""
TAIL_U = "    assign pmod = {^q, ctr[31:25]};\nendmodule\n"
TAIL = "    assign q = 72'd0;\n    assign pmod = {^q, ctr[31:25]};\nendmodule\n"

VARIANTS = {
    "base": None, "base2": None,
    "y0": "URAM288_X0Y0",       # URAM_URAM_FT_X30Y0, the four sites
    "y1": "URAM288_X0Y1",
    "y2": "URAM288_X0Y2",
    "y3": "URAM288_X0Y3",
    "y4": "URAM288_X0Y4",       # URAM_URAM_FT_X30Y15
    "y12": "URAM288_X0Y12",     # URAM_URAM_DELAY_FT_X30Y45, the other tile type
    "y34": "URAM288_X0Y34",     # URAM_URAM_FT_X30Y120, another clock region row
}

out = sys.argv[1]
for name, site in VARIANTS.items():
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "top.v"), "w") as f:
        f.write(HEAD + (URAM % site + TAIL_U if site else TAIL))
