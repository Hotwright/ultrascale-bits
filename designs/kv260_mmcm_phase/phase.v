// KV260 MMCM ROW_MID phase test: does ROW_MID[0] (DRP 0x00 bit 0) move the
// CLKIN -> CLKOUT phase of an MMCM?
//
// MMCM T (MMCM_X0Y1) makes 100 MHz from the 100 MHz PS clock (M 10, O 10).
// MMCM S (MMCM_X0Y3) makes the 49.741 MHz sampling clock (M 12, O 24.125).
// A DDMTD compares them: ta and tb toggle at 50 MHz on the PS clock and on
// T's CLKOUT0. Sampled at 49.741 MHz, each becomes a beat about 192 samples
// long, so one sample of beat delay is 20 ns / 192 = 104 ps of clock delay.
// d = (beat edge of tb) - (beat edge of ta) in samples, averaged over 65536
// beats. Because ta and tb are divide-by-2s, d is only meaningful mod 96
// (10 ns).
//
// build.sh writes two bitstreams from one route that differ only in T's
// ROW_MID[0]: set/ and clr/.
//
// The LEDs show the result as a pulse train (see Readout below).
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    wire fbt, fbs, t0, s0, lt, ls, cb, cs;
    (* LOC = "MMCM_X0Y1" *)
    MMCME4_ADV #(.CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(10.0), .CLKOUT0_DIVIDE_F(10.0))
        mmcm_t (.CLKIN1(clk), .CLKFBIN(fbt), .CLKFBOUT(fbt), .CLKOUT0(t0), .LOCKED(lt),
                .RST(1'b0), .PWRDWN(1'b0), .CLKINSEL(1'b1));
    (* LOC = "MMCM_X0Y3" *)
    MMCME4_ADV #(.CLKIN1_PERIOD(10.0), .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT_F(12.0), .CLKOUT0_DIVIDE_F(24.125))
        mmcm_s (.CLKIN1(clk), .CLKFBIN(fbs), .CLKFBOUT(fbs), .CLKOUT0(s0), .LOCKED(ls),
                .RST(1'b0), .PWRDWN(1'b0), .CLKINSEL(1'b1));
    BUFGCE bgt (.I(t0), .CE(1'b1), .O(cb));
    BUFGCE bgs (.I(s0), .CE(1'b1), .O(cs));

    reg ta = 1'b0, tb = 1'b0;
    always @(posedge clk) ta <= ~ta;
    always @(posedge cb) tb <= ~tb;

    // Sampling domain.
    reg [2:0] sa = 0, sb = 0;
    reg [5:0] za = 0, zb = 0;           // samples since the last 1, saturating
    reg [15:0] c = 0, ca = 0;
    reg [15:0] n = 0;
    reg [31:0] sum = 0, res = 0;
    reg sea = 0, seb = 0, sacc = 0, sdone = 0, tgl = 0;   // diagnosis
    wire ea = sa[2] & (za >= 6'd32);    // first 1 after a long low: a beat edge
    wire eb = sb[2] & (zb >= 6'd32);
    wire [15:0] d = c - ca;
    always @(posedge cs) begin
        sa <= {sa[1:0], ta};
        sb <= {sb[1:0], tb};
        za <= sa[2] ? 6'd0 : (za == 6'd63 ? za : za + 1'b1);
        zb <= sb[2] ? 6'd0 : (zb == 6'd63 ? zb : zb + 1'b1);
        c <= c + 1'b1;
        tgl <= ~tgl;
        if (ea) sea <= 1'b1;
        if (eb) seb <= 1'b1;
        if (eb && !ea && d < 16'd256) sacc <= 1'b1;
        if (n == 16'hffff) sdone <= 1'b1;
        if (ea)
            ca <= c;
        if (eb && !ea && d < 16'd256) begin
            if (n == 16'hffff) begin
                res <= sum + d;
                sum <= 0;
            end else
                sum <= sum + d;
            n <= n + 1'b1;
        end
    end

    // Readout: every LED shows the same pulse train, so the webcam need not
    // tell them apart. A word is 16 slots of 0.67 s, MSB first, then 4 dark
    // slots; a slot is lit for its first quarter (0) or first three
    // quarters (1). The word is {integer, fraction} of the average d.
`ifndef WORD
`define WORD res[23:8]
`endif
    reg [2:0] tg = 0;
    reg alive = 0;
    always @(posedge clk) begin tg <= {tg[1:0], tgl}; if (tg[2] != tg[1]) alive <= 1'b1; end
    reg [4:0] sl = 0;
    reg [15:0] word = 0;
    reg on = 0;
    always @(posedge clk) begin
        if (ctr[25:0] == 26'h3ffffff) begin
            sl <= sl == 5'd19 ? 5'd0 : sl + 1'b1;
            if (sl == 5'd19)
                word <= `WORD;
        end
        on <= sl < 5'd16 && (ctr[25:24] == 2'd0 || (word[15 - sl[3:0]] && ctr[25:24] != 2'd3));
    end
    assign pmod = {8{on}};
endmodule
