// KV260 board test of a simple-dual-port RAMB18E2 as the open flow builds it.
// Behind the zynq-ps8 bridge at 0xA000_0000:
//   0x0000..0x07FC  a 512 x 32 RAM, preloaded from init.hex (test.tcl's pat): write port <- AXI writes, read port <- AXI
//                   reads (address in, data the clock after). Yosys maps it to one
//                   RAMB18E2 in SDP mode (READ_WIDTH_A = WRITE_WIDTH_B = 36).
//   0x0800..0x0FFC  a second such RAM (mem1), same preload; build.sh pins mem
//                   to the tile's lower RAMB18 (L) and mem1 to its upper one (U)
//   0x1000          0x5D9B0001, read only (the design is the one you think)
//   0x1004          writes seen
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
    reg  [15:0] nwr = 16'd0;

    ps8_axil ps (
        .m_axi_aclk(clk), .m_axi_aresetn(rstn),
        .m_axi_awaddr(awaddr), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(2'b00), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(2'b00), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .irq(16'd0), .bad_access(bad_access));

    reg [31:0] mem [0:511];
    reg [31:0] mem1 [0:511];
    initial $readmemh("init.hex", mem);   // the pattern test.tcl checks before writing
    initial $readmemh("init.hex", mem1);
    reg [31:0] rd_q, rd_q1;
    reg        rsel = 1'b0;
    integer    k;
    reg  [8:0] ra = 9'd0;
    reg  [1:0] rph = 2'd0;        // 0 idle, 1 address in, 2 data out
    reg        rmem = 1'b0;
    reg [31:0] rreg = 32'd0;

    always @(posedge clk) begin
        awready <= 1'b0; wready <= 1'b0;
        if (awvalid && wvalid && !awready && !bvalid) begin
            awready <= 1'b1; wready <= 1'b1; bvalid <= 1'b1;
            nwr <= nwr + 1'b1;
            // byte strobes honoured: yosys maps wstrb to WEBWE[3:0]
            for (k = 0; k < 4; k = k + 1) begin
                if (awaddr[12] == 1'b0 && !awaddr[11] && wstrb[k]) mem[awaddr[10:2]][8*k +: 8] <= wdata[8*k +: 8];
                if (awaddr[12] == 1'b0 &&  awaddr[11] && wstrb[k]) mem1[awaddr[10:2]][8*k +: 8] <= wdata[8*k +: 8];
            end
        end
        if (bvalid && bready) bvalid <= 1'b0;
    end

    always @(posedge clk) rd_q <= mem[ra];
    always @(posedge clk) rd_q1 <= mem1[ra];

    always @(posedge clk) begin
        arready <= 1'b0;
        case (rph)
            2'd0: if (arvalid && !arready && !rvalid) begin
                      arready <= 1'b1;
                      ra   <= araddr[10:2];
                      rmem <= (araddr[12] == 1'b0);
                      rsel <= araddr[11];
                      rreg <= araddr[2] ? {16'd0, nwr} : 32'h5D9B0001;
                      rph  <= 2'd1;
                  end
            2'd1: rph <= 2'd2;                        // RAM reads ra this clock
            2'd2: begin rdata <= rmem ? (rsel ? rd_q1 : rd_q) : rreg; rvalid <= 1'b1; rph <= 2'd3; end
            2'd3: if (rvalid && rready) begin rvalid <= 1'b0; rph <= 2'd0; end
        endcase
    end

    assign pmod = nwr[7:0];
endmodule
