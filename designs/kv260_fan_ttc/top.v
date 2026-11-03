// KV260: the heat-sink fan handed back to the PS from an open-flow bitstream.
//
// The fan is a PS peripheral. TTC0's waveform output 2 leaves the PS over EMIO
// (PS8 EMIOTTC0WAVEO[2]) and the PL passes it straight to fan_en_b on A12,
// as AMD's platforms and hotc's examples/tokenizer do (kria_fan.v:
// assign fout = fin[2]). Linux's pwm-fan then runs the fan from TTC0.
//
// pmod[7] mirrors the same wave, so the J2 LED module shows what the fan
// sees. pmod[6:0] count on PL_CLK0, to show the bitstream is running.
module top (output wire fan_en_b, output wire [7:0] pmod);
    wire [3:0] plclk;
    wire [2:0] ttc0_wave;
    PS8 ps8_i (.PLCLK(plclk), .EMIOTTC0WAVEO(ttc0_wave));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    reg [26:0] ctr = 27'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;
    assign pmod[6:0] = ctr[26:20];
    assign pmod[7]   = ttc0_wave[2];
    assign fan_en_b  = ttc0_wave[2];
endmodule
