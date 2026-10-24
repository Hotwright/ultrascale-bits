// LED identification (Vivado-built, trusted): pmod[1] and pmod[7] low (lit,
// the Pmod is active-low), the rest high. Registered from PL_CLK0 so the pads
// are driven by FFs exactly as in out_plall.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire pclk;
    BUFG_PS bufg_ps (.I(plclk[0]), .O(pclk));
    reg [7:0] r = 8'hFF;
    always @(posedge pclk) r <= 8'b0111_1101;
    assign pmod = r;
endmodule
