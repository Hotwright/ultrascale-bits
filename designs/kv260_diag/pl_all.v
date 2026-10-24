// All 8 LEDs follow PL_CLK0 counter bit 26: blink in unison iff PL_CLK0 runs.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire pclk;
    BUFG_PS bufg_ps (.I(plclk[0]), .O(pclk));
    reg [26:0] pc = 0;  always @(posedge pclk) pc <= pc + 1'b1;
    assign pmod = {8{pc[26]}};
endmodule
