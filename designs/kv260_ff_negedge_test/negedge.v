// KV260 board test for falling-edge flip-flops (CLKINV in the CLE). Each
// group of four FDRE_1s captures LFSR bits on the falling edge and passes
// them to rising-edge FDREs pinned to the other half of the same slice,
// which must then hold them one cycle late, as a plain rising-edge pipeline
// stage would. A CLKINV that does not take effect, or that reaches the other
// half, makes them two cycles late. Any mismatch sets a sticky fail bit.
//
//   g0  CLEM ABCD falling, EFGH reads    g1  CLEM EFGH falling, ABCD reads
//   g2  CLEL ABCD falling, EFGH reads    g3  CLEL EFGH falling, ABCD reads
//
// Readout as kv260_ff_sr_test, on every Pmod LED: {pass[3:0], 4'b1001, 8'hA5},
// first bit first; pass[3] is g0. Board result 0xF9A5, at 100 MHz.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    reg [63:0] lf = 64'h0123456789abcdef;
    always @(posedge clk) lf <= {lf[62:0], lf[63] ^ lf[62] ^ lf[60] ^ lf[59]};
    reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;
    wire run = ctr[31:4] != 28'd0;

    // Falling-edge FFs and the rising-edge FFs that read them, pinned to the
    // two halves of one slice (X186 is CLEM_X6, X188 CLEL_R_X6):
    //   g0  CLEM ABCD falling, EFGH reads    g1  CLEM EFGH falling, ABCD reads
    //   g2  CLEL ABCD falling, EFGH reads    g3  CLEL EFGH falling, ABCD reads
    // A CLKINV bit that reaches the other half makes its readers sample on
    // the same edge as the FFs they read: one cycle late.
    wire [3:0] q0, q1, q2, q3, p0, p1, p2, p3;
    (* BEL = "X186Y60/SLICE_X0Y0.AFF" *) FDRE_1 n0_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[0]), .Q(q0[0]));
    (* BEL = "X186Y60/SLICE_X0Y0.EFF" *) FDRE p0_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(q0[0]), .Q(p0[0]));
    (* BEL = "X186Y60/SLICE_X0Y0.BFF" *) FDRE_1 n0_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[1]), .Q(q0[1]));
    (* BEL = "X186Y60/SLICE_X0Y0.FFF" *) FDRE p0_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(q0[1]), .Q(p0[1]));
    (* BEL = "X186Y60/SLICE_X0Y0.CFF" *) FDRE_1 n0_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[2]), .Q(q0[2]));
    (* BEL = "X186Y60/SLICE_X0Y0.GFF" *) FDRE p0_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(q0[2]), .Q(p0[2]));
    (* BEL = "X186Y60/SLICE_X0Y0.DFF" *) FDRE_1 n0_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[3]), .Q(q0[3]));
    (* BEL = "X186Y60/SLICE_X0Y0.HFF" *) FDRE p0_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(q0[3]), .Q(p0[3]));
    (* BEL = "X186Y61/SLICE_X0Y0.EFF" *) FDRE_1 n1_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[4]), .Q(q1[0]));
    (* BEL = "X186Y61/SLICE_X0Y0.AFF" *) FDRE p1_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(q1[0]), .Q(p1[0]));
    (* BEL = "X186Y61/SLICE_X0Y0.FFF" *) FDRE_1 n1_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[5]), .Q(q1[1]));
    (* BEL = "X186Y61/SLICE_X0Y0.BFF" *) FDRE p1_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(q1[1]), .Q(p1[1]));
    (* BEL = "X186Y61/SLICE_X0Y0.GFF" *) FDRE_1 n1_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[6]), .Q(q1[2]));
    (* BEL = "X186Y61/SLICE_X0Y0.CFF" *) FDRE p1_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(q1[2]), .Q(p1[2]));
    (* BEL = "X186Y61/SLICE_X0Y0.HFF" *) FDRE_1 n1_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[7]), .Q(q1[3]));
    (* BEL = "X186Y61/SLICE_X0Y0.DFF" *) FDRE p1_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(q1[3]), .Q(p1[3]));
    (* BEL = "X188Y60/SLICE_X0Y0.AFF" *) FDRE_1 n2_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[8]), .Q(q2[0]));
    (* BEL = "X188Y60/SLICE_X0Y0.EFF" *) FDRE p2_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(q2[0]), .Q(p2[0]));
    (* BEL = "X188Y60/SLICE_X0Y0.BFF" *) FDRE_1 n2_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[9]), .Q(q2[1]));
    (* BEL = "X188Y60/SLICE_X0Y0.FFF" *) FDRE p2_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(q2[1]), .Q(p2[1]));
    (* BEL = "X188Y60/SLICE_X0Y0.CFF" *) FDRE_1 n2_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[10]), .Q(q2[2]));
    (* BEL = "X188Y60/SLICE_X0Y0.GFF" *) FDRE p2_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(q2[2]), .Q(p2[2]));
    (* BEL = "X188Y60/SLICE_X0Y0.DFF" *) FDRE_1 n2_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[11]), .Q(q2[3]));
    (* BEL = "X188Y60/SLICE_X0Y0.HFF" *) FDRE p2_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(q2[3]), .Q(p2[3]));
    (* BEL = "X188Y61/SLICE_X0Y0.EFF" *) FDRE_1 n3_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[12]), .Q(q3[0]));
    (* BEL = "X188Y61/SLICE_X0Y0.AFF" *) FDRE p3_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(q3[0]), .Q(p3[0]));
    (* BEL = "X188Y61/SLICE_X0Y0.FFF" *) FDRE_1 n3_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[13]), .Q(q3[1]));
    (* BEL = "X188Y61/SLICE_X0Y0.BFF" *) FDRE p3_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(q3[1]), .Q(p3[1]));
    (* BEL = "X188Y61/SLICE_X0Y0.GFF" *) FDRE_1 n3_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[14]), .Q(q3[2]));
    (* BEL = "X188Y61/SLICE_X0Y0.CFF" *) FDRE p3_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(q3[2]), .Q(p3[2]));
    (* BEL = "X188Y61/SLICE_X0Y0.HFF" *) FDRE_1 n3_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(lf[15]), .Q(q3[3]));
    (* BEL = "X188Y61/SLICE_X0Y0.DFF" *) FDRE p3_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(q3[3]), .Q(p3[3]));
    reg [3:0] e0 = 0, e1 = 0, e2 = 0, e3 = 0;
    always @(posedge clk) begin
        e0 <= lf[3:0]; e1 <= lf[7:4]; e2 <= lf[11:8]; e3 <= lf[15:12];
    end

    reg [3:0] f = 0;
    always @(posedge clk) if (run) begin
        if (p0 != e0) f[3] <= 1'b1;
        if (p1 != e1) f[2] <= 1'b1;
        if (p2 != e2) f[1] <= 1'b1;
        if (p3 != e3) f[0] <= 1'b1;
    end
    wire [3:0] pass = run ? ~f : 4'd0;

    reg [4:0] sl = 0;
    reg [15:0] word = 0;
    reg on = 0;
    always @(posedge clk) begin
        if (ctr[25:0] == 26'h3ffffff) begin
            sl <= sl == 5'd19 ? 5'd0 : sl + 1'b1;
            if (sl == 5'd19)
                word <= {pass, 4'b1001, 8'ha5};
        end
        on <= sl < 5'd16 && (ctr[25:24] == 2'd0 || (word[15 - sl[3:0]] && ctr[25:24] != 2'd3));
    end
    assign pmod = {8{on}};
endmodule
