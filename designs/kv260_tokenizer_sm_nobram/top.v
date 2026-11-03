// kv260_tokenizer_sm -- the KV260 board test of hotc's tokenizer-sm block
// (blocks/ai/tokenizer-sm) behind the zynq-ps8 block's HPM0 bridge, at
// 0xA000_0000. The same two blocks Agent-Hotwright's canvas wires together.
module top;
    wire [3:0] ps_plclk;
    wire       clk;
    PS8     ps8_board_clk     (.PLCLK(ps_plclk));
    BUFG_PS bufg_ps_board_clk (.I(ps_plclk[0]), .O(clk));

    reg [3:0] por_count = 4'd0;
    wire      rst_n = por_count[3];
    always @(posedge clk) if (!rst_n) por_count <= por_count + 4'd1;

    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [3:0]  wstrb;
    wire [1:0]  bresp, rresp;
    wire        awvalid, awready, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rvalid, rready, irq;

    ps8_axil #(.TIMEOUT_BITS(10)) u_ps (
        .m_axi_aclk(clk), .m_axi_aresetn(rst_n),
        .m_axi_awaddr(awaddr), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .irq({15'b0, irq})
    );

    tokenizer_sm_axil #(.IN_AW(4)) u_tok (
        .s_axi_aclk(clk), .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr[17:0]), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bvalid(bvalid), .s_axi_bresp(bresp), .s_axi_bready(bready),
        .s_axi_araddr(araddr[17:0]), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .irq_out(irq)
    );
endmodule
