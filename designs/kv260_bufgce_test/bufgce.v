// KV260 BUFGCE board test. Two CMT_L BUFGCEs share one fabric clock (the
// PS counter's bit 3) and one slow fabric clock enable (ctr[29], ~5 s at
// 100 MHz); the second has IS_CE_INVERTED. Each clocks its own counter.
//
//   pmod[7]    the enable (on for ~5 s, off for ~5 s)
//   pmod[6:4]  counter behind BUFGCE a: counts while the enable is on
//   pmod[3:1]  counter behind BUFGCE b: counts while the enable is off
//   pmod[0]    PS-clock heartbeat
//
// So the two groups of three take turns: one group runs while the other
// holds still. (The Pmod LEDs are active-low; "on" and "off" swap, the
// turn-taking does not.)
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    wire ca, cb;
    BUFGCE #(.CE_TYPE("ASYNC")) a_i (.I(ctr[3]), .CE(ctr[29]), .O(ca));
    BUFGCE #(.IS_CE_INVERTED(1'b1)) b_i (.I(ctr[3]), .CE(ctr[29]), .O(cb));
    reg [23:0] qa = 24'd0, qb = 24'd0;
    always @(posedge ca) qa <= qa + 1'b1;
    always @(posedge cb) qb <= qb + 1'b1;

    assign pmod = {ctr[29], qa[22:20], qb[22:20], ctr[25]};
endmodule
