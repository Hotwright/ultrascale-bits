// KV260 STARTUPE3 test. CFGMCLK, the configuration logic's own ~50 MHz
// oscillator, is synchronised into the PS clock domain and its rising edges
// counted. Pmod LEDs (active low):
//
//   pmod[7]    EOS (end of startup): steadily lit
//   pmod[6:0]  edge count bits 25..19: counting, so lit LEDs keep changing
//              (all frozen: CFGMCLK never reaches the fabric)
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    wire cfgmclk, eos;
    STARTUPE3 startup_i (.CFGMCLK(cfgmclk), .EOS(eos), .GSR(1'b0), .GTS(1'b0), .KEYCLEARB(1'b1),
                         .PACK(1'b0), .USRCCLKO(1'b0), .USRCCLKTS(1'b1), .USRDONEO(1'b1),
                         .USRDONETS(1'b1), .DTS(4'b1111), .FCSBO(1'b1), .FCSBTS(1'b1));

    reg [2:0] sync = 3'd0;
    reg [25:0] edges = 26'd0;
    reg eos_q = 1'b0;
    always @(posedge clk) begin
        sync <= {sync[1:0], cfgmclk};
        if (sync[1] && !sync[2])
            edges <= edges + 1'b1;
        eos_q <= eos;
    end

    assign pmod = ~{eos_q, edges[25:19]};
endmodule
