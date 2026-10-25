// KV260 block RAM test: a 4096 x 8 ROM in one RAMB36E2, read out to the Pmod
// LEDs. Clocked from PS PL_CLK0 (~100 MHz) like ../kv260_ps_blink.
//
// chase.hex (written by gen_chase.py) holds two patterns a counter cannot
// produce: the first 2048 words bounce one lit LED end to end, the second 2048
// fill a bar of LEDs left to right. One word per 2^23 cycles (~84 ms), so the
// whole ROM plays in ~5.7 minutes and the switch is at ~2.9 minutes. A wrong
// INIT interleave between the RAMB36's two halves scrambles both patterns.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    reg [34:0] ctr = 35'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    (* rom_style = "block" *) reg [7:0] rom [0:4095];
    initial $readmemh("chase.hex", rom);
    reg [7:0] q;
    always @(posedge clk) q <= rom[ctr[34:23]];
    assign pmod = q;
endmodule
