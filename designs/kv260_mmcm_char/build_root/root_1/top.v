module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    (* DONT_TOUCH = "TRUE" *) reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;
    wire [63:0] msb;
    wire mfb0; wire [6:0] mo0;
    (* DONT_TOUCH = "TRUE" *) MMCME4_ADV #(.BANDWIDTH("LOW"), .CLKFBOUT_MULT_F(126), .CLKFBOUT_PHASE(160.000), .CLKIN1_PERIOD(21.459), .CLKIN2_PERIOD(21.459), .CLKOUT0_DIVIDE_F(100), .CLKOUT0_DUTY_CYCLE(0.720), .CLKOUT0_PHASE(133.200), .CLKOUT1_DIVIDE(121), .CLKOUT1_DUTY_CYCLE(0.3182), .CLKOUT1_PHASE(70.661), .CLKOUT2_DIVIDE(18), .CLKOUT2_DUTY_CYCLE(0.3889), .CLKOUT2_PHASE(320.000), .CLKOUT3_DIVIDE(41), .CLKOUT3_DUTY_CYCLE(0.7927), .CLKOUT3_PHASE(0.000), .CLKOUT4_CASCADE("FALSE"), .CLKOUT4_DIVIDE(111), .CLKOUT4_DUTY_CYCLE(0.500), .CLKOUT4_PHASE(162.973), .CLKOUT5_DIVIDE(34), .CLKOUT5_DUTY_CYCLE(0.500), .CLKOUT5_PHASE(272.647), .CLKOUT6_DIVIDE(96), .CLKOUT6_DUTY_CYCLE(0.151), .CLKOUT6_PHASE(0.000), .COMPENSATION("AUTO"), .DIVCLK_DIVIDE(4), .IS_CLKINSEL_INVERTED(0), .IS_PSEN_INVERTED(1), .IS_PSINCDEC_INVERTED(1), .IS_PWRDWN_INVERTED(1), .IS_RST_INVERTED(0), .STARTUP_WAIT("TRUE")) mmcm0 (
        .CLKIN1(clk), .CLKIN2(clk), .CLKINSEL(ctr[1]), .CLKFBIN(mfb0), .CLKFBOUT(mfb0),
        .CLKOUT0(mo0[0]), .CLKOUT1(mo0[1]), .CLKOUT2(mo0[2]), .CLKOUT3(mo0[3]), .CLKOUT4(mo0[4]), .CLKOUT5(mo0[5]), .CLKOUT6(mo0[6]),
        .LOCKED(msb[48]), .RST(ctr[2]), .PWRDWN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .CDDCREQ(1'b0));
    wire pfb0; wire [1:0] po0;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(.CLKFBOUT_MULT(16), .CLKFBOUT_PHASE(270.000), .CLKIN_PERIOD(1.372), .CLKOUT0_DIVIDE(66), .CLKOUT0_DUTY_CYCLE(0.500), .CLKOUT0_PHASE(0.000), .CLKOUT1_DIVIDE(27), .CLKOUT1_DUTY_CYCLE(0.500), .CLKOUT1_PHASE(226.667), .COMPENSATION("AUTO"), .DIVCLK_DIVIDE(10), .IS_PWRDWN_INVERTED(1), .IS_RST_INVERTED(1), .STARTUP_WAIT("FALSE")) pll0 (
        .CLKIN(clk), .CLKFBIN(pfb0), .CLKFBOUT(pfb0), .CLKOUT0(po0[0]), .CLKOUT1(po0[1]),
        .LOCKED(msb[52]), .RST(ctr[3]), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire pfb1; wire [1:0] po1;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(.CLKFBOUT_MULT(18), .CLKFBOUT_PHASE(320.000), .CLKIN_PERIOD(12.784), .CLKOUT0_DIVIDE(57), .CLKOUT0_DUTY_CYCLE(0.6491), .CLKOUT0_PHASE(189.474), .CLKOUT1_DIVIDE(73), .CLKOUT1_DUTY_CYCLE(0.863), .CLKOUT1_PHASE(0.000), .COMPENSATION("AUTO"), .DIVCLK_DIVIDE(1), .IS_PWRDWN_INVERTED(1), .IS_RST_INVERTED(1), .STARTUP_WAIT("FALSE")) pll1 (
        .CLKIN(clk), .CLKFBIN(pfb1), .CLKFBOUT(pfb1), .CLKOUT0(po1[0]), .CLKOUT1(po1[1]),
        .LOCKED(msb[53]), .RST(ctr[4]), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire b0;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b0_i (.I(mo0[0]), .CE(1'b1), .O(b0));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q0 = 8'd0;
    always @(posedge b0) q0 <= q0 + 1'b1;
    assign msb[0] = q0[7];
    wire b1;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b1_i (.I(mo0[1]), .CE(1'b1), .O(b1));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q1 = 8'd0;
    always @(posedge b1) q1 <= q1 + 1'b1;
    assign msb[1] = q1[7];
    wire b2;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b2_i (.I(mo0[2]), .CE(1'b1), .O(b2));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q2 = 8'd0;
    always @(posedge b2) q2 <= q2 + 1'b1;
    assign msb[2] = q2[7];
    wire b3;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b3_i (.I(mo0[3]), .CE(1'b1), .O(b3));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q3 = 8'd0;
    always @(posedge b3) q3 <= q3 + 1'b1;
    assign msb[3] = q3[7];
    wire b4;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b4_i (.I(mo0[4]), .CE(1'b1), .O(b4));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q4 = 8'd0;
    always @(posedge b4) q4 <= q4 + 1'b1;
    assign msb[4] = q4[7];
    wire b5;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b5_i (.I(mo0[5]), .CE(1'b1), .O(b5));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q5 = 8'd0;
    always @(posedge b5) q5 <= q5 + 1'b1;
    assign msb[5] = q5[7];
    wire b6;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b6_i (.I(po0[0]), .CE(1'b1), .O(b6));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q6 = 8'd0;
    always @(posedge b6) q6 <= q6 + 1'b1;
    assign msb[6] = q6[7];
    wire b7;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b7_i (.I(po0[1]), .CE(1'b1), .O(b7));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q7 = 8'd0;
    always @(posedge b7) q7 <= q7 + 1'b1;
    assign msb[7] = q7[7];
    wire b8;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b8_i (.I(po1[0]), .CE(1'b1), .O(b8));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q8 = 8'd0;
    always @(posedge b8) q8 <= q8 + 1'b1;
    assign msb[8] = q8[7];
    wire b9;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b9_i (.I(po1[1]), .CE(1'b1), .O(b9));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q9 = 8'd0;
    always @(posedge b9) q9 <= q9 + 1'b1;
    assign msb[9] = q9[7];
    wire mfb1; wire [6:0] mo1;
    (* DONT_TOUCH = "TRUE" *) MMCME4_ADV #(.BANDWIDTH("OPTIMIZED"), .CLKFBOUT_MULT_F(84), .CLKFBOUT_PHASE(272.143), .CLKIN1_PERIOD(2.013), .CLKIN2_PERIOD(2.013), .CLKOUT0_DIVIDE_F(27), .CLKOUT0_DUTY_CYCLE(0.500), .CLKOUT0_PHASE(0.000), .CLKOUT1_DIVIDE(96), .CLKOUT1_DUTY_CYCLE(0.0365), .CLKOUT1_PHASE(100.312), .CLKOUT2_DIVIDE(31), .CLKOUT2_DUTY_CYCLE(0.500), .CLKOUT2_PHASE(0.000), .CLKOUT3_DIVIDE(95), .CLKOUT3_DUTY_CYCLE(0.7421), .CLKOUT3_PHASE(216.000), .CLKOUT4_CASCADE("FALSE"), .CLKOUT4_DIVIDE(109), .CLKOUT4_DUTY_CYCLE(0.945), .CLKOUT4_PHASE(0.000), .CLKOUT5_DIVIDE(91), .CLKOUT5_DUTY_CYCLE(0.500), .CLKOUT5_PHASE(112.747), .CLKOUT6_DIVIDE(83), .CLKOUT6_DUTY_CYCLE(0.500), .CLKOUT6_PHASE(-123.614), .COMPENSATION("INTERNAL"), .DIVCLK_DIVIDE(30), .IS_CLKINSEL_INVERTED(0), .IS_PSEN_INVERTED(1), .IS_PSINCDEC_INVERTED(0), .IS_PWRDWN_INVERTED(0), .IS_RST_INVERTED(0), .STARTUP_WAIT("TRUE")) mmcm1 (
        .CLKIN1(clk), .CLKIN2(clk), .CLKINSEL(ctr[5]), .CLKFBIN(mfb1), .CLKFBOUT(mfb1),
        .CLKOUT0(mo1[0]), .CLKOUT1(mo1[1]), .CLKOUT2(mo1[2]), .CLKOUT3(mo1[3]), .CLKOUT4(mo1[4]), .CLKOUT5(mo1[5]), .CLKOUT6(mo1[6]),
        .LOCKED(msb[49]), .RST(ctr[6]), .PWRDWN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .CDDCREQ(1'b0));
    wire pfb2; wire [1:0] po2;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(.CLKFBOUT_MULT(10), .CLKFBOUT_PHASE(216.000), .CLKIN_PERIOD(2.347), .CLKOUT0_DIVIDE(4), .CLKOUT0_DUTY_CYCLE(0.375), .CLKOUT0_PHASE(0.000), .CLKOUT1_DIVIDE(126), .CLKOUT1_DUTY_CYCLE(0.500), .CLKOUT1_PHASE(165.714), .COMPENSATION("INTERNAL"), .DIVCLK_DIVIDE(3), .IS_PWRDWN_INVERTED(1), .IS_RST_INVERTED(0), .STARTUP_WAIT("FALSE")) pll2 (
        .CLKIN(clk), .CLKFBIN(pfb2), .CLKFBOUT(pfb2), .CLKOUT0(po2[0]), .CLKOUT1(po2[1]),
        .LOCKED(msb[54]), .RST(ctr[7]), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire pfb3; wire [1:0] po3;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(.CLKFBOUT_MULT(19), .CLKFBOUT_PHASE(284.211), .CLKIN_PERIOD(1.880), .CLKOUT0_DIVIDE(40), .CLKOUT0_DUTY_CYCLE(0.500), .CLKOUT0_PHASE(9.000), .CLKOUT1_DIVIDE(114), .CLKOUT1_DUTY_CYCLE(0.500), .CLKOUT1_PHASE(113.684), .COMPENSATION("AUTO"), .DIVCLK_DIVIDE(7), .IS_PWRDWN_INVERTED(1), .IS_RST_INVERTED(0), .STARTUP_WAIT("TRUE")) pll3 (
        .CLKIN(clk), .CLKFBIN(pfb3), .CLKFBOUT(pfb3), .CLKOUT0(po3[0]), .CLKOUT1(po3[1]),
        .LOCKED(msb[55]), .RST(ctr[8]), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire b10;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b10_i (.I(mo1[0]), .CE(1'b1), .O(b10));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q10 = 8'd0;
    always @(posedge b10) q10 <= q10 + 1'b1;
    assign msb[10] = q10[7];
    wire b11;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b11_i (.I(mo1[1]), .CE(1'b1), .O(b11));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q11 = 8'd0;
    always @(posedge b11) q11 <= q11 + 1'b1;
    assign msb[11] = q11[7];
    wire b12;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b12_i (.I(mo1[2]), .CE(1'b1), .O(b12));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q12 = 8'd0;
    always @(posedge b12) q12 <= q12 + 1'b1;
    assign msb[12] = q12[7];
    wire b13;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b13_i (.I(mo1[3]), .CE(1'b1), .O(b13));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q13 = 8'd0;
    always @(posedge b13) q13 <= q13 + 1'b1;
    assign msb[13] = q13[7];
    wire b14;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b14_i (.I(mo1[4]), .CE(1'b1), .O(b14));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q14 = 8'd0;
    always @(posedge b14) q14 <= q14 + 1'b1;
    assign msb[14] = q14[7];
    wire b15;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b15_i (.I(mo1[5]), .CE(1'b1), .O(b15));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q15 = 8'd0;
    always @(posedge b15) q15 <= q15 + 1'b1;
    assign msb[15] = q15[7];
    wire b16;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b16_i (.I(po2[0]), .CE(1'b1), .O(b16));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q16 = 8'd0;
    always @(posedge b16) q16 <= q16 + 1'b1;
    assign msb[16] = q16[7];
    wire b17;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b17_i (.I(po2[1]), .CE(1'b1), .O(b17));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q17 = 8'd0;
    always @(posedge b17) q17 <= q17 + 1'b1;
    assign msb[17] = q17[7];
    wire b18;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b18_i (.I(po3[0]), .CE(1'b1), .O(b18));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q18 = 8'd0;
    always @(posedge b18) q18 <= q18 + 1'b1;
    assign msb[18] = q18[7];
    wire b19;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b19_i (.I(po3[1]), .CE(1'b1), .O(b19));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q19 = 8'd0;
    always @(posedge b19) q19 <= q19 + 1'b1;
    assign msb[19] = q19[7];
    wire mfb2; wire [6:0] mo2;
    (* DONT_TOUCH = "TRUE" *) MMCME4_ADV #(.BANDWIDTH("HIGH"), .CLKFBOUT_MULT_F(113.625), .CLKIN1_PERIOD(1.639), .CLKIN2_PERIOD(1.639), .CLKOUT0_DIVIDE_F(19.500), .CLKOUT1_DIVIDE(113), .CLKOUT1_DUTY_CYCLE(0.500), .CLKOUT1_PHASE(59.735), .CLKOUT2_DIVIDE(81), .CLKOUT2_DUTY_CYCLE(0.9012), .CLKOUT2_PHASE(-145.000), .CLKOUT3_DIVIDE(13), .CLKOUT3_DUTY_CYCLE(0.1923), .CLKOUT3_PHASE(159.231), .CLKOUT4_CASCADE("FALSE"), .CLKOUT4_DIVIDE(118), .CLKOUT4_DUTY_CYCLE(0.0212), .CLKOUT4_PHASE(41.949), .CLKOUT5_DIVIDE(81), .CLKOUT6_DIVIDE(88), .COMPENSATION("AUTO"), .DIVCLK_DIVIDE(46), .IS_CLKINSEL_INVERTED(0), .IS_PSEN_INVERTED(1), .IS_PSINCDEC_INVERTED(0), .IS_PWRDWN_INVERTED(0), .IS_RST_INVERTED(0), .STARTUP_WAIT("FALSE")) mmcm2 (
        .CLKIN1(clk), .CLKIN2(clk), .CLKINSEL(ctr[9]), .CLKFBIN(mfb2), .CLKFBOUT(mfb2),
        .CLKOUT0(mo2[0]), .CLKOUT1(mo2[1]), .CLKOUT2(mo2[2]), .CLKOUT3(mo2[3]), .CLKOUT4(mo2[4]), .CLKOUT5(mo2[5]), .CLKOUT6(mo2[6]),
        .LOCKED(msb[50]), .RST(ctr[10]), .PWRDWN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .CDDCREQ(1'b0));
    wire pfb4; wire [1:0] po4;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(.CLKFBOUT_MULT(7), .CLKFBOUT_PHASE(0.000), .CLKIN_PERIOD(1.501), .CLKOUT0_DIVIDE(89), .CLKOUT0_DUTY_CYCLE(0.1573), .CLKOUT0_PHASE(0.000), .CLKOUT1_DIVIDE(57), .CLKOUT1_DUTY_CYCLE(0.6228), .CLKOUT1_PHASE(151.579), .COMPENSATION("INTERNAL"), .DIVCLK_DIVIDE(5), .IS_PWRDWN_INVERTED(1), .IS_RST_INVERTED(1), .STARTUP_WAIT("FALSE")) pll4 (
        .CLKIN(clk), .CLKFBIN(pfb4), .CLKFBOUT(pfb4), .CLKOUT0(po4[0]), .CLKOUT1(po4[1]),
        .LOCKED(msb[56]), .RST(ctr[11]), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire pfb5; wire [1:0] po5;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(.CLKFBOUT_MULT(7), .CLKFBOUT_PHASE(0.000), .CLKIN_PERIOD(5.693), .CLKOUT0_DIVIDE(60), .CLKOUT0_DUTY_CYCLE(0.500), .CLKOUT0_PHASE(150.000), .CLKOUT1_DIVIDE(119), .CLKOUT1_DUTY_CYCLE(0.500), .CLKOUT1_PHASE(175.462), .COMPENSATION("INTERNAL"), .DIVCLK_DIVIDE(1), .IS_PWRDWN_INVERTED(1), .IS_RST_INVERTED(0), .STARTUP_WAIT("TRUE")) pll5 (
        .CLKIN(clk), .CLKFBIN(pfb5), .CLKFBOUT(pfb5), .CLKOUT0(po5[0]), .CLKOUT1(po5[1]),
        .LOCKED(msb[57]), .RST(ctr[12]), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire b20;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b20_i (.I(mo2[1]), .CE(1'b1), .O(b20));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q20 = 8'd0;
    always @(posedge b20) q20 <= q20 + 1'b1;
    assign msb[20] = q20[7];
    wire b21;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b21_i (.I(mo2[2]), .CE(1'b1), .O(b21));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q21 = 8'd0;
    always @(posedge b21) q21 <= q21 + 1'b1;
    assign msb[21] = q21[7];
    wire b22;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b22_i (.I(mo2[3]), .CE(1'b1), .O(b22));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q22 = 8'd0;
    always @(posedge b22) q22 <= q22 + 1'b1;
    assign msb[22] = q22[7];
    wire b23;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b23_i (.I(mo2[5]), .CE(1'b1), .O(b23));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q23 = 8'd0;
    always @(posedge b23) q23 <= q23 + 1'b1;
    assign msb[23] = q23[7];
    wire b24;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b24_i (.I(mo2[6]), .CE(1'b1), .O(b24));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q24 = 8'd0;
    always @(posedge b24) q24 <= q24 + 1'b1;
    assign msb[24] = q24[7];
    wire b25;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b25_i (.I(po4[0]), .CE(1'b1), .O(b25));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q25 = 8'd0;
    always @(posedge b25) q25 <= q25 + 1'b1;
    assign msb[25] = q25[7];
    wire b26;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b26_i (.I(po4[1]), .CE(1'b1), .O(b26));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q26 = 8'd0;
    always @(posedge b26) q26 <= q26 + 1'b1;
    assign msb[26] = q26[7];
    wire b27;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b27_i (.I(po5[0]), .CE(1'b1), .O(b27));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q27 = 8'd0;
    always @(posedge b27) q27 <= q27 + 1'b1;
    assign msb[27] = q27[7];
    wire b28;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b28_i (.I(po5[1]), .CE(1'b1), .O(b28));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q28 = 8'd0;
    always @(posedge b28) q28 <= q28 + 1'b1;
    assign msb[28] = q28[7];
    wire mfb3; wire [6:0] mo3;
    (* DONT_TOUCH = "TRUE" *) MMCME4_ADV #(.BANDWIDTH("OPTIMIZED"), .CLKFBOUT_MULT_F(30.125), .CLKIN1_PERIOD(1.616), .CLKIN2_PERIOD(1.616), .CLKOUT0_DIVIDE_F(84.125), .CLKOUT1_DIVIDE(40), .CLKOUT1_DUTY_CYCLE(0.2625), .CLKOUT1_PHASE(205.875), .CLKOUT2_DIVIDE(26), .CLKOUT2_DUTY_CYCLE(0.8462), .CLKOUT2_PHASE(351.346), .CLKOUT3_DIVIDE(25), .CLKOUT3_DUTY_CYCLE(0.500), .CLKOUT3_PHASE(0.000), .CLKOUT4_CASCADE("TRUE"), .CLKOUT4_DIVIDE(21), .CLKOUT4_DUTY_CYCLE(0.9524), .CLKOUT4_PHASE(173.571), .CLKOUT5_DIVIDE(40), .CLKOUT6_DIVIDE(33), .COMPENSATION("INTERNAL"), .DIVCLK_DIVIDE(13), .IS_CLKINSEL_INVERTED(0), .IS_PSEN_INVERTED(0), .IS_PSINCDEC_INVERTED(1), .IS_PWRDWN_INVERTED(0), .IS_RST_INVERTED(0), .STARTUP_WAIT("FALSE")) mmcm3 (
        .CLKIN1(clk), .CLKIN2(clk), .CLKINSEL(ctr[13]), .CLKFBIN(mfb3), .CLKFBOUT(mfb3),
        .CLKOUT0(mo3[0]), .CLKOUT1(mo3[1]), .CLKOUT2(mo3[2]), .CLKOUT3(mo3[3]), .CLKOUT4(mo3[4]), .CLKOUT5(mo3[5]), .CLKOUT6(mo3[6]),
        .LOCKED(msb[51]), .RST(ctr[14]), .PWRDWN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .CDDCREQ(1'b0));
    wire pfb6; wire [1:0] po6;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(.CLKFBOUT_MULT(6), .CLKFBOUT_PHASE(0.000), .CLKIN_PERIOD(3.076), .CLKOUT0_DIVIDE(101), .CLKOUT0_DUTY_CYCLE(0.5545), .CLKOUT0_PHASE(0.000), .CLKOUT1_DIVIDE(72), .CLKOUT1_DUTY_CYCLE(0.9653), .CLKOUT1_PHASE(0.000), .COMPENSATION("AUTO"), .DIVCLK_DIVIDE(2), .IS_PWRDWN_INVERTED(0), .IS_RST_INVERTED(1), .STARTUP_WAIT("TRUE")) pll6 (
        .CLKIN(clk), .CLKFBIN(pfb6), .CLKFBOUT(pfb6), .CLKOUT0(po6[0]), .CLKOUT1(po6[1]),
        .LOCKED(msb[58]), .RST(ctr[15]), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire pfb7; wire [1:0] po7;
    (* DONT_TOUCH = "TRUE" *) PLLE4_ADV #(.CLKFBOUT_MULT(9), .CLKFBOUT_PHASE(0.000), .CLKIN_PERIOD(1.352), .CLKOUT0_DIVIDE(76), .CLKOUT0_DUTY_CYCLE(0.500), .CLKOUT0_PHASE(0.000), .CLKOUT1_DIVIDE(35), .CLKOUT1_DUTY_CYCLE(0.500), .CLKOUT1_PHASE(174.857), .COMPENSATION("AUTO"), .DIVCLK_DIVIDE(6), .IS_PWRDWN_INVERTED(0), .IS_RST_INVERTED(1), .STARTUP_WAIT("TRUE")) pll7 (
        .CLKIN(clk), .CLKFBIN(pfb7), .CLKFBOUT(pfb7), .CLKOUT0(po7[0]), .CLKOUT1(po7[1]),
        .LOCKED(msb[59]), .RST(ctr[16]), .PWRDWN(1'b0), .CLKOUTPHYEN(1'b0),
        .DCLK(1'b0), .DEN(1'b0), .DWE(1'b0), .DADDR(7'd0), .DI(16'd0));
    wire b29;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b29_i (.I(mo3[0]), .CE(1'b1), .O(b29));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q29 = 8'd0;
    always @(posedge b29) q29 <= q29 + 1'b1;
    assign msb[29] = q29[7];
    wire b30;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b30_i (.I(mo3[1]), .CE(1'b1), .O(b30));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q30 = 8'd0;
    always @(posedge b30) q30 <= q30 + 1'b1;
    assign msb[30] = q30[7];
    wire b31;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b31_i (.I(mo3[3]), .CE(1'b1), .O(b31));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q31 = 8'd0;
    always @(posedge b31) q31 <= q31 + 1'b1;
    assign msb[31] = q31[7];
    wire b32;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b32_i (.I(mo3[4]), .CE(1'b1), .O(b32));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q32 = 8'd0;
    always @(posedge b32) q32 <= q32 + 1'b1;
    assign msb[32] = q32[7];
    wire b33;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b33_i (.I(mo3[5]), .CE(1'b1), .O(b33));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q33 = 8'd0;
    always @(posedge b33) q33 <= q33 + 1'b1;
    assign msb[33] = q33[7];
    wire b34;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b34_i (.I(po6[0]), .CE(1'b1), .O(b34));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q34 = 8'd0;
    always @(posedge b34) q34 <= q34 + 1'b1;
    assign msb[34] = q34[7];
    wire b35;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b35_i (.I(po6[1]), .CE(1'b1), .O(b35));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q35 = 8'd0;
    always @(posedge b35) q35 <= q35 + 1'b1;
    assign msb[35] = q35[7];
    wire b36;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b36_i (.I(po7[0]), .CE(1'b1), .O(b36));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q36 = 8'd0;
    always @(posedge b36) q36 <= q36 + 1'b1;
    assign msb[36] = q36[7];
    wire b37;
    (* DONT_TOUCH = "TRUE" *) BUFGCE b37_i (.I(po7[1]), .CE(1'b1), .O(b37));
    (* DONT_TOUCH = "TRUE" *) reg [7:0] q37 = 8'd0;
    always @(posedge b37) q37 <= q37 + 1'b1;
    assign msb[37] = q37[7];
    assign msb[47:38] = 0;
    assign msb[63:60] = 0;
    assign pmod = {^msb, ctr[31:25]};
endmodule
