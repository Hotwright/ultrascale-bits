// Clock-vs-logic discriminator for the open flow: no LUTs on the LED path.
// pmod[3:0]: FDRE with D=1, INIT=0, clocked by PL_CLK0 -> goes high (LED off,
//            the Pmod is active-low) on the first edge iff the clock arrives.
// pmod[7:4]: constant 1 (LED off) as the reference.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    genvar i;
    generate for (i = 0; i < 4; i = i + 1) begin : g
        (* keep *) FDRE #(.INIT(1'b0)) ff (.C(clk), .CE(1'b1), .R(1'b0), .D(1'b1), .Q(pmod[i]));
    end endgenerate
    assign pmod[7:4] = 4'b1111;
endmodule
