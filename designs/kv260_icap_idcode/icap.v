// KV260 ICAPE3 test: read the device IDCODE back through the ICAP, ~12 times
// a second, and show the verdict on the Pmod LEDs (active low):
//
//   all eight LEDs blink together (~3 Hz) - the last read returned the K26
//                                           IDCODE (x4A49093, revision ignored)
//   one LED blinking, the rest steady     - the reads returned something
//                                           else: the steady seven show the
//                                           low 7 bits of the last nonzero
//                                           word (none lit: every word was
//                                           zero, i.e. the ICAP outputs never
//                                           reached the fabric)
//   all off                               - the state machine never finished
//
// Sequence (UG570, "Reading configuration registers via ICAP"): dummy, sync,
// NOOP, a type-1 read of IDCODE (register 0x0C), two NOOPs; switch to read
// and capture; switch back and DESYNC. ICAP data is bit-swapped within each
// byte. On Zynq UltraScale+ the ICAP only answers once the CSU hands the
// configuration port over from the PCAP (pcap_ctrl.PCAP_PR = 0); see build.sh.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    function [31:0] swap(input [31:0] w);
        integer i;
        for (i = 0; i < 32; i = i + 1)
            swap[(i / 8) * 8 + 7 - (i % 8)] = w[i];
    endfunction

    reg [26:0] ctr = 27'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    reg [5:0] st = 6'd0;
    reg csib = 1'b1, rdwrb = 1'b0;
    reg [31:0] wr = 32'hFFFFFFFF;
    wire [31:0] rd;
    reg seen = 1'b0, pass = 1'b0, got = 1'b0;
    reg [7:0] last = 8'd0;

    always @(posedge clk) begin
        case (st)
            // write: dummy, sync, NOOP, read IDCODE x1, NOOP, NOOP
            6'd1: begin csib <= 1'b0; rdwrb <= 1'b0; wr <= swap(32'hFFFFFFFF); end
            6'd2: wr <= swap(32'hAA995566);
            6'd3: wr <= swap(32'h20000000);
            6'd4: wr <= swap(32'h28018001);
            6'd5: wr <= swap(32'h20000000);
            6'd6: wr <= swap(32'h20000000);
            6'd7: csib <= 1'b1;
            6'd8: rdwrb <= 1'b1;
            6'd9: begin csib <= 1'b0; got <= 1'b0; end
            // 10-41: capture; the word arrives a few cycles in
            6'd42: csib <= 1'b1;
            6'd43: rdwrb <= 1'b0;
            // DESYNC: write CMD, DESYNC, NOOP, NOOP
            6'd44: begin csib <= 1'b0; wr <= swap(32'h30008001); end
            6'd45: wr <= swap(32'h0000000D);
            6'd46: wr <= swap(32'h20000000);
            6'd47: wr <= swap(32'h20000000);
            6'd48: begin
                csib <= 1'b1;
                seen <= 1'b1;
                pass <= got;
            end
            default: ;
        endcase
        if (st >= 6'd10 && st <= 6'd41 && (swap(rd) & 32'h0FFFFFFF) == 32'h04A49093)
            got <= 1'b1;
        if (st >= 6'd10 && st <= 6'd41 && rd != 32'd0 && !got)
            last <= swap(rd);
        if (st == 6'd0)
            st <= (ctr[22:0] == 23'd0) ? 6'd1 : 6'd0;
        else
            st <= (st == 6'd48) ? 6'd0 : st + 1'b1;
    end

    ICAPE3 icap_i (.CLK(clk), .CSIB(csib), .RDWRB(rdwrb), .I(wr), .O(rd));

    // Active-low LEDs
    assign pmod = !seen ? 8'hFF : pass ? {8{ctr[24]}} : ~{ctr[24], last[6:0]};
endmodule
