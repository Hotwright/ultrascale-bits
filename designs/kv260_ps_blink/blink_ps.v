// KV260 PMOD blinky clocked from the PS.
//
// The PMOD LED module is output only and supplies no clock, and no pin on the
// carrier is driven with one, so an external clock is not an option on this
// board. PS8's PLCLK[0] is. Everything else is identical to
// ../kv260_pmod_blink/blink.v.
//
// Only PLCLK is connected. nextpnr-xilinx expects that: pins.cc excludes PS8
// from its pin list "due to the large number of tied-zero pins".
module top (output wire [7:0] pmod);
    wire [3:0] plclk;

    PS8 ps8_i (.PLCLK(plclk));

    // Instantiate the PS global buffer explicitly. Left to itself, yosys's
    // clkbufmap inserts a plain BUFG (which nextpnr upgrades to BUFGCE), the
    // placer puts it on a general BUFGCE site, and the route fails:
    //   ERROR: Failed to route arc 0.0 of net '...', from SITEWIRE/PS8_X0Y0/PL_CLK0
    //   to SITEWIRE/BUFGCE_X0Y40/IINV_I.
    // PL_CLK reaches the fabric over dedicated CLK_BUFG_PS_* wires, so the
    // buffer has to be a BUFG_PS. nextpnr maps BUFG_PS -> BUFCE_BUFG_PS.
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    reg [26:0] ctr = 27'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;
    assign pmod = ctr[26:19];
endmodule
