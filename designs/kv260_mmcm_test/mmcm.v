// KV260 MMCM/PLL spec and board test.
//
// Two MMCME4_ADVs and two PLLE4_ADVs on the 100 MHz PS clock (PL_CLK0), one
// of each in a middle CMT row and one in an outer row (the ROW_MID bits
// differ). MMCM A has a fractional multiplier and a fractional CLKOUT0, a
// phase and a duty cycle; MMCM B is integer with BANDWIDTH LOW. Feedback is
// internal; RST/PWRDWN/CLKINSEL are tied. Each used output clocks a counter
// through a BUFGCE, and bit 24 of each is on an LED (f / 2^25):
//
//   pmod[7]  all four LOCKED
//   pmod[6]  PS clock counter, bit 25          100 MHz   1.49 Hz (reference)
//   pmod[5]  MMCM A CLKOUT0  1250/12.5         100 MHz   2.98 Hz
//   pmod[4]  MMCM A CLKOUT1  1250/25, 90 deg    50 MHz   1.49 Hz
//   pmod[3]  MMCM B CLKOUT0  1000/8            125 MHz   3.73 Hz
//   pmod[2]  MMCM B CLKOUT3  1000/40, 60 %      25 MHz   0.75 Hz
//   pmod[1]  PLL A  CLKOUT0   800/10            80 MHz   2.38 Hz
//   pmod[0]  PLL B  CLKOUT1   900/12            75 MHz   2.24 Hz
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    wire fba, fbb, fbc, fbd, la, lb, lc, ld;
    wire a0, a1, b0, b3, c0, d1;

    (* LOC = "MMCM_X0Y1" *)
    MMCME4_ADV #(.CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(12.5),
                 .CLKOUT0_DIVIDE_F(12.5), .CLKOUT1_DIVIDE(25), .CLKOUT1_PHASE(90.0),
                 .CLKOUT2_DIVIDE(50), .CLKOUT2_DUTY_CYCLE(0.4))
        mmcm_a (.CLKIN1(clk), .CLKFBIN(fba), .CLKFBOUT(fba), .CLKOUT0(a0), .CLKOUT1(a1),
                .LOCKED(la), .RST(1'b0), .PWRDWN(1'b0), .CLKINSEL(1'b1));

    (* LOC = "MMCM_X0Y3" *)
    MMCME4_ADV #(.CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(10.0), .BANDWIDTH("LOW"),
                 .CLKOUT0_DIVIDE_F(8.0), .CLKOUT3_DIVIDE(40), .CLKOUT3_DUTY_CYCLE(0.6))
        mmcm_b (.CLKIN1(clk), .CLKFBIN(fbb), .CLKFBOUT(fbb), .CLKOUT0(b0), .CLKOUT3(b3),
                .LOCKED(lb), .RST(1'b0), .PWRDWN(1'b0), .CLKINSEL(1'b1));

    (* LOC = "PLL_X0Y2" *)
    PLLE4_ADV #(.CLKIN_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT(8), .CLKOUT0_DIVIDE(10))
        pll_c (.CLKIN(clk), .CLKFBIN(fbc), .CLKFBOUT(fbc), .CLKOUT0(c0), .LOCKED(lc),
               .RST(1'b0), .PWRDWN(1'b0));

    (* LOC = "PLL_X0Y7" *)
    PLLE4_ADV #(.CLKIN_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT(9), .CLKOUT1_DIVIDE(12))
        pll_d (.CLKIN(clk), .CLKFBIN(fbd), .CLKFBOUT(fbd), .CLKOUT1(d1), .LOCKED(ld),
               .RST(1'b0), .PWRDWN(1'b0));

    wire ga0, ga1, gb0, gb3, gc0, gd1;
    BUFGCE bga0 (.I(a0), .CE(1'b1), .O(ga0));
    BUFGCE bga1 (.I(a1), .CE(1'b1), .O(ga1));
    BUFGCE bgb0 (.I(b0), .CE(1'b1), .O(gb0));
    BUFGCE bgb3 (.I(b3), .CE(1'b1), .O(gb3));
    BUFGCE bgc0 (.I(c0), .CE(1'b1), .O(gc0));
    BUFGCE bgd1 (.I(d1), .CE(1'b1), .O(gd1));

    reg [24:0] qa0 = 0, qa1 = 0, qb0 = 0, qb3 = 0, qc0 = 0, qd1 = 0;
    always @(posedge ga0) qa0 <= qa0 + 1'b1;
    always @(posedge ga1) qa1 <= qa1 + 1'b1;
    always @(posedge gb0) qb0 <= qb0 + 1'b1;
    always @(posedge gb3) qb3 <= qb3 + 1'b1;
    always @(posedge gc0) qc0 <= qc0 + 1'b1;
    always @(posedge gd1) qd1 <= qd1 + 1'b1;

    assign pmod = {la & lb & lc & ld, ctr[25], qa0[24], qa1[24], qb0[24], qb3[24], qc0[24], qd1[24]};
endmodule
