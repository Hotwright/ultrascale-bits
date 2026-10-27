// KV260 DSP48E2 board test: seven DSPs, each checked against a LUT-only
// reference (built with yosys -nodsp) every 8 cycles. Inputs come from an
// LFSR and are held for 8 cycles, so the DSP pipelines (up to 4 deep) have
// settled when the check is made.
//
//   t0  P = A*B + C                  A/B/C/M/P registered
//   t1  P = (D + A)*B + C            pre-adder; INMODE tied 0 with
//                                    IS_INMODE_INVERTED[2] set: D enabled
//   t2  four 12-bit lanes  A:B + C   USE_SIMD FOUR12, USE_MULT NONE
//   t3  PATTERNDETECT on C           MASK ignores all but C[7:0], PATTERN 5A
//   t4  P = C - A:B                  ALUMODE tied 0 with IS_ALUMODE_INVERTED
//                                    4'b0011: subtract
//   t5  P = C + RND                  W = RND
//   t6  P = (D + A)*B + C            D tied to a constant (the DSP's own
//                                    D_TIE0/TIE1 bits, not routed), C[47:32]
//                                    tied (routed), INMODE tied 5'b00100
//
// Control pins are tied (OPMODE, CE*, RST*), some through their inversion
// bits (RSTP tied 1 with IS_RSTP_INVERTED: inactive). The result goes out
// on every Pmod LED together as a pulse train (see kv260_mmcm_phase):
// 16 slots of 0.67 s, MSB first, then 4 dark; a slot lit for a quarter is
// 0, for three quarters 1. The word is
//   {pass[6:0], t3_saw_match, 8'hA5}
// where pass[i] = checks were made and none failed.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    reg [127:0] lfsr = 128'h0123456789abcdef_fedcba9876543210;
    always @(posedge clk)
        if (ctr[2:0] == 3'd0)
            lfsr <= {lfsr[126:0], lfsr[127] ^ lfsr[125] ^ lfsr[100] ^ lfsr[98]};
    wire [29:0] a = lfsr[29:0];
    wire [17:0] b = lfsr[47:30];
    wire [47:0] c = lfsr[95:48];
    wire [26:0] d = lfsr[122:96];
    wire check = ctr[2:0] == 3'd7;

    localparam [47:0] RND = 48'h5a5a_1234_c3c3;
    localparam [26:0] DC = 27'h4b5e3e9;  // D[3], D[13], D[23] set: no TIE1 bits
    wire [47:0] c6 = {16'h1234, c[31:0]};
    wire [47:0] p0, p1, p2, p3, p4, p5, p6;
    wire pd3;

    (* LOC = "DSP48E2_X2Y10" *)
    DSP48E2 #(.AREG(1), .BREG(1), .CREG(1), .MREG(1), .PREG(1), .IS_RSTP_INVERTED(1'b1))
        t0 (.CLK(clk), .A(a), .B(b), .C(c), .OPMODE(9'b00_011_01_01), .ALUMODE(4'b0000),
            .INMODE(5'b00000), .CARRYINSEL(3'b000), .CARRYIN(1'b0),
            .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b1), .CEM(1'b1), .CEP(1'b1),
            .CECTRL(1'b1), .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECARRYIN(1'b1), .CED(1'b0), .CEAD(1'b0),
            .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTM(1'b0), .RSTP(1'b1), .RSTCTRL(1'b0),
            .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTALLCARRYIN(1'b0), .RSTD(1'b0), .P(p0));

    (* LOC = "DSP48E2_X2Y11" *)
    DSP48E2 #(.AMULTSEL("AD"), .ADREG(1), .DREG(1), .AREG(1), .BREG(1), .CREG(1), .MREG(1), .PREG(1),
              .INMODEREG(1), .IS_INMODE_INVERTED(5'b00100))
        t1 (.CLK(clk), .A(a), .B(b), .C(c), .D(d), .OPMODE(9'b00_011_01_01), .ALUMODE(4'b0000),
            .INMODE(5'b00000), .CARRYINSEL(3'b000), .CARRYIN(1'b0),
            .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b1), .CEM(1'b1), .CEP(1'b1),
            .CECTRL(1'b1), .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECARRYIN(1'b1), .CED(1'b1), .CEAD(1'b1),
            .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTM(1'b0), .RSTP(1'b0), .RSTCTRL(1'b0),
            .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTALLCARRYIN(1'b0), .RSTD(1'b0), .P(p1));

    (* LOC = "DSP48E2_X2Y12" *)
    DSP48E2 #(.USE_MULT("NONE"), .USE_SIMD("FOUR12"), .MREG(0), .AREG(1), .BREG(1), .CREG(1), .PREG(1))
        t2 (.CLK(clk), .A(a), .B(b), .C(c), .OPMODE(9'b00_011_00_11), .ALUMODE(4'b0000),
            .INMODE(5'b00000), .CARRYINSEL(3'b000), .CARRYIN(1'b0),
            .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b1), .CEM(1'b0), .CEP(1'b1),
            .CECTRL(1'b1), .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECARRYIN(1'b1), .CED(1'b0), .CEAD(1'b0),
            .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTM(1'b0), .RSTP(1'b0), .RSTCTRL(1'b0),
            .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTALLCARRYIN(1'b0), .RSTD(1'b0), .P(p2));

    (* LOC = "DSP48E2_X2Y13" *)
    DSP48E2 #(.USE_MULT("NONE"), .MREG(0), .CREG(1), .PREG(1), .USE_PATTERN_DETECT("PATDET"),
              .MASK(48'hffff_ffff_ff00), .PATTERN(48'h0000_0000_005a), .SEL_MASK("MASK"))
        t3 (.CLK(clk), .A(a), .B(b), .C(c), .OPMODE(9'b00_011_00_00), .ALUMODE(4'b0000),
            .INMODE(5'b00000), .CARRYINSEL(3'b000), .CARRYIN(1'b0),
            .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b1), .CEM(1'b0), .CEP(1'b1),
            .CECTRL(1'b1), .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECARRYIN(1'b1), .CED(1'b0), .CEAD(1'b0),
            .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTM(1'b0), .RSTP(1'b0), .RSTCTRL(1'b0),
            .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTALLCARRYIN(1'b0), .RSTD(1'b0),
            .P(p3), .PATTERNDETECT(pd3));

    (* LOC = "DSP48E2_X2Y14" *)
    DSP48E2 #(.USE_MULT("NONE"), .MREG(0), .AREG(1), .BREG(1), .CREG(1), .PREG(1),
              .IS_ALUMODE_INVERTED(4'b0011))
        t4 (.CLK(clk), .A(a), .B(b), .C(c), .OPMODE(9'b00_011_00_11), .ALUMODE(4'b0000),
            .INMODE(5'b00000), .CARRYINSEL(3'b000), .CARRYIN(1'b0),
            .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b1), .CEM(1'b0), .CEP(1'b1),
            .CECTRL(1'b1), .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECARRYIN(1'b1), .CED(1'b0), .CEAD(1'b0),
            .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTM(1'b0), .RSTP(1'b0), .RSTCTRL(1'b0),
            .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTALLCARRYIN(1'b0), .RSTD(1'b0), .P(p4));

    (* LOC = "DSP48E2_X2Y15" *)
    DSP48E2 #(.USE_MULT("NONE"), .MREG(0), .CREG(1), .PREG(1), .RND(RND))
        t5 (.CLK(clk), .A(a), .B(b), .C(c), .OPMODE(9'b10_011_00_00), .ALUMODE(4'b0000),
            .INMODE(5'b00000), .CARRYINSEL(3'b000), .CARRYIN(1'b0),
            .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b1), .CEM(1'b0), .CEP(1'b1),
            .CECTRL(1'b1), .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECARRYIN(1'b1), .CED(1'b0), .CEAD(1'b0),
            .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTM(1'b0), .RSTP(1'b0), .RSTCTRL(1'b0),
            .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTALLCARRYIN(1'b0), .RSTD(1'b0), .P(p5));

    (* LOC = "DSP48E2_X2Y16" *)
    DSP48E2 #(.AMULTSEL("AD"), .ADREG(1), .DREG(1), .AREG(1), .BREG(1), .CREG(1), .MREG(1), .PREG(1),
              .INMODEREG(1))
        t6 (.CLK(clk), .A(a), .B(b), .C(c6), .D(DC), .OPMODE(9'b00_011_01_01), .ALUMODE(4'b0000),
            .INMODE(5'b00100), .CARRYINSEL(3'b000), .CARRYIN(1'b0),
            .CEA1(1'b1), .CEA2(1'b1), .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b1), .CEM(1'b1), .CEP(1'b1),
            .CECTRL(1'b1), .CEALUMODE(1'b1), .CEINMODE(1'b1), .CECARRYIN(1'b1), .CED(1'b1), .CEAD(1'b1),
            .RSTA(1'b0), .RSTB(1'b0), .RSTC(1'b0), .RSTM(1'b0), .RSTP(1'b0), .RSTCTRL(1'b0),
            .RSTALUMODE(1'b0), .RSTINMODE(1'b0), .RSTALLCARRYIN(1'b0), .RSTD(1'b0), .P(p6));

    // The LUT references.
    wire signed [26:0] sa = a[26:0];
    wire signed [17:0] sb = b;
    wire signed [26:0] sad = $signed(d) + sa;
    // The products are formed signed at 48 bits before C is added: mixing
    // in the unsigned C would make Verilog multiply unsigned.
    // use_dsp "no": the Vivado reference must not turn these into DSPs either.
    (* use_dsp = "no" *) wire signed [47:0] m0 = sa * sb;
    (* use_dsp = "no" *) wire signed [47:0] m1 = sad * sb;
    wire signed [26:0] sdc = $signed(DC) + sa;
    (* use_dsp = "no" *) wire signed [47:0] m6 = sdc * sb;
    wire [47:0] e6 = m6 + c6;
    wire [47:0] e0 = m0 + c;
    wire [47:0] e1 = m1 + c;
    wire [47:0] ab = {a, b};
    wire [47:0] e2 = {ab[47:36] + c[47:36], ab[35:24] + c[35:24], ab[23:12] + c[23:12], ab[11:0] + c[11:0]};
    wire e3 = c[7:0] == 8'h5a;
    wire [47:0] e4 = c - ab;
    wire [47:0] e5 = c + RND;

    reg [6:0] fail = 0;
    reg checked = 0, saw = 0;
    always @(posedge clk)
        if (check) begin
            checked <= 1'b1;
            if (p0 != e0) fail[0] <= 1'b1;
            if (p1 != e1) fail[1] <= 1'b1;
            if (p2 != e2) fail[2] <= 1'b1;
            if (pd3 != e3 || p3 != c) fail[3] <= 1'b1;
            if (p4 != e4) fail[4] <= 1'b1;
            if (p5 != e5) fail[5] <= 1'b1;
            if (p6 != e6) fail[6] <= 1'b1;
            if (e3) saw <= 1'b1;
        end
    wire [6:0] pass = checked ? ~fail : 7'd0;

    // Readout (as kv260_mmcm_phase).
    reg [4:0] sl = 0;
    reg [15:0] word = 0;
    reg on = 0;
    always @(posedge clk) begin
        if (ctr[25:0] == 26'h3ffffff) begin
            sl <= sl == 5'd19 ? 5'd0 : sl + 1'b1;
            if (sl == 5'd19)
                word <= {pass, saw, 8'ha5};
        end
        on <= sl < 5'd16 && (ctr[25:24] == 2'd0 || (word[15 - sl[3:0]] && ctr[25:24] != 2'd3));
    end
    assign pmod = {8{on}};
endmodule
