// KV260 BUFGCE_DIV and BUFGCTRL board test.
//
// Three BUFGCE_DIVs divide one fabric clock (the PS counter's bit 3) by 1, 2
// and 4; each clocks a counter, and the same two bits of each are on the
// LEDs, so the three pairs blink at rates 4:2:1. A BUFGCTRL switches every
// ~10 s between that fabric clock and one four times slower (bit 5); its
// counter's LED blinks fast, then slow, then fast again.
//
//   pmod[7]    the BUFGCTRL select (S1 = sel, S0 = ~sel: on = I1, the slow one)
//   pmod[6]    counter behind the BUFGCTRL
//   pmod[5:4]  counter behind BUFGCE_DIV /1
//   pmod[3:2]  counter behind BUFGCE_DIV /2
//   pmod[1:0]  counter behind BUFGCE_DIV /4
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    wire d1, d2, d4, cx;
    BUFGCE_DIV #(.BUFGCE_DIVIDE(1)) div1_i (.I(ctr[3]), .CE(1'b1), .CLR(1'b0), .O(d1));
    BUFGCE_DIV #(.BUFGCE_DIVIDE(2)) div2_i (.I(ctr[3]), .CE(1'b1), .CLR(1'b0), .O(d2));
    BUFGCE_DIV #(.BUFGCE_DIVIDE(4)) div4_i (.I(ctr[3]), .CE(1'b1), .CLR(1'b0), .O(d4));
    wire sel = ctr[30];
    BUFGCTRL ctrl_i (.I0(ctr[3]), .I1(ctr[5]), .S0(~sel), .S1(sel), .CE0(1'b1), .CE1(1'b1),
                     .IGNORE0(1'b0), .IGNORE1(1'b0), .O(cx));

    reg [23:0] q1 = 0, q2 = 0, q4 = 0, qx = 0;
    always @(posedge d1) q1 <= q1 + 1'b1;
    always @(posedge d2) q2 <= q2 + 1'b1;
    always @(posedge d4) q4 <= q4 + 1'b1;
    always @(posedge cx) qx <= qx + 1'b1;

    assign pmod = {sel, qx[21], q1[21:20], q2[21:20], q4[21:20]};
endmodule
