// KV260 board test for flip-flop set/reset and clock enable (SRUSED, SRINV,
// SYNC, SRVAL and SR-over-CE priority), which kv260_ps_axi_test's AXI slave
// was the first design to use. Every DUT is a primitive driven by LFSR bits
// and runs in lockstep with a reference FDRE that uses neither SR nor CE: its
// next state is a LUT6 of {q, d, ce, r}. Any mismatch sets a sticky fail bit.
//
//   t0  FDRE  R, CE                     q <= r ? 0 : ce ? d : q
//   t1  FDRE  R, CE, D tied 1 (as the AXI slave's bvalid)
//   t2  FDSE  S, CE                     q <= s ? 1 : ce ? d : q
//   t3  FDRE  R inverted (IS_R_INVERTED) q <= !r ? 0 : ce ? d : q
//   t4  FDRE  R only, CE tied 1
//   t5  FDCE  CLR (async), CE           not checked while CLR is high
//   t6  FDRE  R, CE, eight of them sharing one R and one CE (a full half)
//
// Readout as kv260_dsp_test, on every Pmod LED: {pass[6:0], 1, 8'hA5}.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    reg [63:0] lf = 64'h0123456789abcdef;
    always @(posedge clk) lf <= {lf[62:0], lf[63] ^ lf[62] ^ lf[60] ^ lf[59]};
    reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;
    wire run = ctr[31:4] != 28'd0;      // let the LFSR settle first

    // Reference: q' = LUT6(q, d, ce, r, mode). Both FDREs have R=0, CE=1.
    // mode 0: R clear wins, 1: S set wins, 2: R active low
    function next(input q, input d, input ce, input r, input [1:0] mode);
        case (mode)
            2'd0: next = r ? 1'b0 : ce ? d : q;
            2'd1: next = r ? 1'b1 : ce ? d : q;
            default: next = !r ? 1'b0 : ce ? d : q;
        endcase
    endfunction

    wire [6:0] bad;
    genvar k;
    generate
        for (k = 0; k < 6; k = k + 1) begin : t
            wire d = (k == 1) ? 1'b1 : lf[8 * k];
            wire ce = (k == 4) ? 1'b1 : lf[8 * k + 1];
            wire r = lf[8 * k + 2] & lf[8 * k + 3];     // rarer resets
            wire [1:0] mode = (k == 2) ? 2'd1 : (k == 3) ? 2'd2 : 2'd0;
            wire q, qr, nx;
            if (k == 2)
                FDSE dut (.C(clk), .CE(ce), .S(r), .D(d), .Q(q));
            else if (k == 3)
                FDRE #(.IS_R_INVERTED(1'b1)) dut (.C(clk), .CE(ce), .R(r), .D(d), .Q(q));
            else if (k == 5)
                FDCE dut (.C(clk), .CE(ce), .CLR(r), .D(d), .Q(q));
            else
                FDRE dut (.C(clk), .CE(ce), .R(r), .D(d), .Q(q));
            FDRE rf (.C(clk), .CE(1'b1), .R(1'b0), .D(nx), .Q(qr));
            assign nx = next(qr, d, ce, r, mode);
            reg f = 1'b0;
            // t5: the clear acts at once, the reference's at the next edge.
            always @(posedge clk) if (run && q != qr && !(k == 5 && r)) f <= 1'b1;
            assign bad[k] = f;
        end
    endgenerate

    // t6: eight FDREs sharing R and CE, each with its own D.
    wire r6 = lf[50] & lf[51], ce6 = lf[52];
    wire [7:0] q6, qr6;
    reg f6 = 1'b0;
    generate
        for (k = 0; k < 8; k = k + 1) begin : h
            FDRE dut (.C(clk), .CE(ce6), .R(r6), .D(lf[k]), .Q(q6[k]));
            FDRE rf (.C(clk), .CE(1'b1), .R(1'b0), .D(next(qr6[k], lf[k], ce6, r6, 2'd0)), .Q(qr6[k]));
        end
    endgenerate
    always @(posedge clk) if (run && q6 != qr6) f6 <= 1'b1;
    assign bad[6] = f6;

    wire [6:0] pass = run ? ~bad : 7'd0;

    reg [4:0] sl = 0;
    reg [15:0] word = 0;
    reg on = 0;
    always @(posedge clk) begin
        if (ctr[25:0] == 26'h3ffffff) begin
            sl <= sl == 5'd19 ? 5'd0 : sl + 1'b1;
            if (sl == 5'd19)
                word <= {pass, 1'b1, 8'ha5};
        end
        on <= sl < 5'd16 && (ctr[25:24] == 2'd0 || (word[15 - sl[3:0]] && ctr[25:24] != 2'd3));
    end
    assign pmod = {8{on}};
endmodule
