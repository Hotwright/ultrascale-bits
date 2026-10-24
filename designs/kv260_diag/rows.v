// KV260 PMOD diagnostic (Vivado-built, not part of the open flow).
//   pmod[3:0] = PL_CLK0 counter (top row, pins 1-4)
//   pmod[7:4] = CFGMCLK counter  internal config oscillator, needs no PS
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire pclk;
    BUFG_PS bufg_ps (.I(plclk[0]), .O(pclk));

    wire cfgmclk, mclk;
    STARTUPE3 startup_i (.CFGMCLK(cfgmclk), .GSR(1'b0), .GTS(1'b0),
                         .KEYCLEARB(1'b1), .PACK(1'b0), .USRCCLKO(1'b0),
                         .USRCCLKTS(1'b0), .USRDONEO(1'b1), .USRDONETS(1'b1));
    BUFGCE bufg_m (.I(cfgmclk), .CE(1'b1), .O(mclk));

    reg [26:0] pc = 0;  always @(posedge pclk) pc <= pc + 1'b1;
    reg [25:0] mc = 0;  always @(posedge mclk) mc <= mc + 1'b1;

    assign pmod = {mc[25:22], pc[26:23]};
endmodule
