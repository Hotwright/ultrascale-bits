// KV260 DNA_PORTE2 test: read the 96-bit device DNA, fold it to a byte (bit
// i of the byte is the XOR of DNA bits i, i+8, i+16, ...) and show it on the
// Pmod LEDs (active low), steady. The DNA is unknown up front, so the check
// is that this build and Vivado's build of the same file light the same
// LEDs. All off means every bit shifted out was zero.
//
// UG570: a READ pulse loads the DNA into the shift register, then each SHIFT
// clock moves it out on DOUT, bit 0 first. Re-read about 12 times a second.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    reg [22:0] ctr = 23'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    reg [6:0] n = 7'd0;
    reg read = 1'b0, shift = 1'b0, busy = 1'b0;
    reg [7:0] fold = 8'd0, shown = 8'd0;
    wire dout;
    always @(posedge clk) begin
        read <= 1'b0;
        if (!busy && ctr == 23'd0) begin
            read <= 1'b1;
            busy <= 1'b1;
            n <= 7'd0;
            fold <= 8'd0;
        end else if (busy && !read) begin
            // DOUT shows bit n while SHIFT is low, then SHIFT advances it
            shift <= 1'b1;
            fold[n[2:0]] <= fold[n[2:0]] ^ dout;
            n <= n + 1'b1;
            if (n == 7'd95) begin
                busy <= 1'b0;
                shift <= 1'b0;
            end
        end
        if (!busy && !read && n == 7'd96)
            shown <= fold;
    end

    DNA_PORTE2 dna_i (.CLK(clk), .DIN(1'b0), .READ(read), .SHIFT(shift), .DOUT(dout));

    assign pmod = ~shown;
endmodule
