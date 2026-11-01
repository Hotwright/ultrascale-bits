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
                default: rdata <= {20'hDEAD0, araddr[11:0]};
            endcase
        end
        if (rvalid && rready) rvalid <= 1'b0;
    end

    assign pmod = r0[7:0];
endmodule
