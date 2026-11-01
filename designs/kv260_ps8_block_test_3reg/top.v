// KV260 board test for hotc blocks/processors/zynq-ps8 (ps8_axil.v), laid out
// the way Agent-Hotwright's KV260 board wrapper builds a design: the wrapper's
// own PS8 gives PL_CLK0 through BUFG_PS, and the block instantiates a second
// PS8 for M_AXI_HPM0_FPD -- nextpnr merges the two (merge_ps8).
//
// Behind the bridge, a 32-bit AXI4-Lite slave at 0xA000_0000:
//   0x00..0C  r0..r3, read/write, byte strobes honoured
//   0x10      0xC0DE0B58, read only
//   0x14      free-running cycle counter
//   0x18      {bad_access, 15'd0, writes[15:0]}
//   others    0xDEAD0000 | addr[11:0]
// r1[15:0] drives the block's irq[15:0]; r0[7:0] is on the Pmod LEDs.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    wire clk;
    PS8     ps8_board_clk     (.PLCLK(plclk));
    BUFG_PS bufg_ps_board_clk (.I(plclk[0]), .O(clk));

    reg [3:0] por = 4'd0;
    always @(posedge clk) if (!por[3]) por <= por + 4'd1;
    wire rstn = por[3];

    wire [31:0] awaddr, wdata, araddr;
    wire [3:0]  wstrb;
    wire        awvalid, wvalid, bready, arvalid, rready, bad_access;
    reg         awready = 1'b0, wready = 1'b0, bvalid = 1'b0, arready = 1'b0, rvalid = 1'b0;
    reg  [31:0] rdata = 32'd0;
    reg  [31:0] r0 = 32'h000000ff, r1 = 32'd0, r2 = 32'd0, r3 = 32'd0;
    reg  [31:0] cyc = 32'd0;
    reg  [15:0] nwr = 16'd0;

    ps8_axil ps (
        .m_axi_aclk(clk), .m_axi_aresetn(rstn),
        .m_axi_awaddr(awaddr), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(2'b00), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(2'b00), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .irq(r1[15:0]), .bad_access(bad_access));

    // kv260_ps8_block_test_3reg: the clock tree spans three clock regions, as the
    // BPE builds' do. cyc[7:0] crosses from the bridge's region (X0Y1) into X0Y2
    // (f2_*, X161Y90) and X0Y0 (f0_*, X161Y215) and back every cycle; word 7
    // snapshots {cyc, back via X0Y2, back via X0Y0, 0}. Correct: back == cyc - 2.
    // (The X0Y0 path carries ~cyc so yosys cannot merge it with the X0Y2 one.)
    wire [7:0] f2, f0;
    reg  [7:0] ncyc = 8'hFF;   // ~cyc, registered: a LUT in front would pack with f0_* and lose their BEL
    (* BEL = "X161Y90/SLICE_X0Y0.AFF" *) FDRE #(.INIT(1'b0)) f2_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(cyc[0]), .Q(f2[0]));
    (* BEL = "X161Y90/SLICE_X0Y0.BFF" *) FDRE #(.INIT(1'b0)) f2_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(cyc[1]), .Q(f2[1]));
    (* BEL = "X161Y90/SLICE_X0Y0.CFF" *) FDRE #(.INIT(1'b0)) f2_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(cyc[2]), .Q(f2[2]));
    (* BEL = "X161Y90/SLICE_X0Y0.DFF" *) FDRE #(.INIT(1'b0)) f2_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(cyc[3]), .Q(f2[3]));
    (* BEL = "X161Y90/SLICE_X0Y0.EFF" *) FDRE #(.INIT(1'b0)) f2_4 (.C(clk), .CE(1'b1), .R(1'b0), .D(cyc[4]), .Q(f2[4]));
    (* BEL = "X161Y90/SLICE_X0Y0.FFF" *) FDRE #(.INIT(1'b0)) f2_5 (.C(clk), .CE(1'b1), .R(1'b0), .D(cyc[5]), .Q(f2[5]));
    (* BEL = "X161Y90/SLICE_X0Y0.GFF" *) FDRE #(.INIT(1'b0)) f2_6 (.C(clk), .CE(1'b1), .R(1'b0), .D(cyc[6]), .Q(f2[6]));
    (* BEL = "X161Y90/SLICE_X0Y0.HFF" *) FDRE #(.INIT(1'b0)) f2_7 (.C(clk), .CE(1'b1), .R(1'b0), .D(cyc[7]), .Q(f2[7]));
    (* BEL = "X161Y215/SLICE_X0Y0.AFF" *) FDRE #(.INIT(1'b0)) f0_0 (.C(clk), .CE(1'b1), .R(1'b0), .D(ncyc[0]), .Q(f0[0]));
    (* BEL = "X161Y215/SLICE_X0Y0.BFF" *) FDRE #(.INIT(1'b0)) f0_1 (.C(clk), .CE(1'b1), .R(1'b0), .D(ncyc[1]), .Q(f0[1]));
    (* BEL = "X161Y215/SLICE_X0Y0.CFF" *) FDRE #(.INIT(1'b0)) f0_2 (.C(clk), .CE(1'b1), .R(1'b0), .D(ncyc[2]), .Q(f0[2]));
    (* BEL = "X161Y215/SLICE_X0Y0.DFF" *) FDRE #(.INIT(1'b0)) f0_3 (.C(clk), .CE(1'b1), .R(1'b0), .D(ncyc[3]), .Q(f0[3]));
    (* BEL = "X161Y215/SLICE_X0Y0.EFF" *) FDRE #(.INIT(1'b0)) f0_4 (.C(clk), .CE(1'b1), .R(1'b0), .D(ncyc[4]), .Q(f0[4]));
    (* BEL = "X161Y215/SLICE_X0Y0.FFF" *) FDRE #(.INIT(1'b0)) f0_5 (.C(clk), .CE(1'b1), .R(1'b0), .D(ncyc[5]), .Q(f0[5]));
    (* BEL = "X161Y215/SLICE_X0Y0.GFF" *) FDRE #(.INIT(1'b0)) f0_6 (.C(clk), .CE(1'b1), .R(1'b0), .D(ncyc[6]), .Q(f0[6]));
    (* BEL = "X161Y215/SLICE_X0Y0.HFF" *) FDRE #(.INIT(1'b0)) f0_7 (.C(clk), .CE(1'b1), .R(1'b0), .D(ncyc[7]), .Q(f0[7]));
    reg [7:0] b2 = 8'd0, b0 = 8'd0;
    reg [31:0] snap = 32'd0;
    always @(posedge clk) begin
        ncyc <= ~(cyc[7:0] + 8'd1);
        b2 <= f2; b0 <= ~f0;
        snap <= {cyc[7:0], b2, b0, 8'd0};
    end

    function [31:0] merge(input [31:0] old, input [31:0] d, input [3:0] s);
        merge = {s[3] ? d[31:24] : old[31:24], s[2] ? d[23:16] : old[23:16],
                 s[1] ? d[15:8] : old[15:8], s[0] ? d[7:0] : old[7:0]};
    endfunction

    always @(posedge clk) begin
        cyc <= cyc + 1'b1;
        // Write: AW and W together (the bridge offers both at once), then B.
        awready <= 1'b0; wready <= 1'b0;
        if (awvalid && wvalid && !awready && !bvalid) begin
            awready <= 1'b1; wready <= 1'b1; bvalid <= 1'b1;
            nwr <= nwr + 1'b1;
            case (awaddr[11:2])
                10'd0: r0 <= merge(r0, wdata, wstrb);
                10'd1: r1 <= merge(r1, wdata, wstrb);
                10'd2: r2 <= merge(r2, wdata, wstrb);
                10'd3: r3 <= merge(r3, wdata, wstrb);
                default: ;
            endcase
        end
        if (bvalid && bready) bvalid <= 1'b0;
        // Read: AR, then R the clock after.
        arready <= 1'b0;
        if (arvalid && !arready && !rvalid) begin
            arready <= 1'b1;
            rvalid  <= 1'b1;
            case (araddr[11:2])
                10'd0: rdata <= r0;
                10'd1: rdata <= r1;
                10'd2: rdata <= r2;
                10'd3: rdata <= r3;
                10'd4: rdata <= 32'hC0DE0B58;
                10'd5: rdata <= cyc;
                10'd6: rdata <= {bad_access, 15'd0, nwr};
                10'd7: rdata <= snap;
                default: rdata <= {20'hDEAD0, araddr[11:0]};
            endcase
        end
        if (rvalid && rready) rvalid <= 1'b0;
    end

    assign pmod = r0[7:0];
endmodule
