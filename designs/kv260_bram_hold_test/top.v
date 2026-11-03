// KV260 board test: does a block RAM read the address its flip-flops held
// before the clock edge (right), or the one they take on at it (a hold race)?
//
// A free-running 9-bit counter drives the read address of two 512 x 32 RAMs
// (each one RAMB18E2 in SDP mode) holding mem[a] = a. Every clock the address
// changes on the very edge that reads it -- the FIFO and program-counter
// pattern -- and the word read must equal the address before that edge.
// Behind the zynq-ps8 bridge at 0xA000_0000 (read only):
//   0x1000  0x5D9B0002 (the design is the one you think)
//   0x1004  cycles checked
//   0x1008  RAM 0 mismatches     0x100C  RAM 0 mismatches that read address + 1
//   0x1010  RAM 0 last bad word  0x1014  RAM 0 its expected word
//   0x1018  RAM 1 mismatches     0x101C  RAM 1 mismatches that read address + 1
//   0x1020  RAM 1 last bad word  0x1024  RAM 1 its expected word
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

    ps8_axil ps (
        .m_axi_aclk(clk), .m_axi_aresetn(rstn),
        .m_axi_awaddr(awaddr), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(2'b00), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(2'b00), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .irq(16'd0), .bad_access(bad_access));

    // ---- the race ----------------------------------------------------------------
    reg [31:0] ram0 [0:511];
    reg [31:0] ram1 [0:511];
    initial $readmemh("addr.hex", ram0);
    initial $readmemh("addr.hex", ram1);
    // A write port each (never enabled) so yosys keeps them RAMs, not ROMs.
    always @(posedge clk) if (awvalid && wvalid && awaddr[13]) ram0[awaddr[10:2]] <= wdata;
    always @(posedge clk) if (awvalid && wvalid && awaddr[14]) ram1[awaddr[10:2]] <= wdata;

    reg  [8:0]  c = 9'd0, cp = 9'd0;
    reg  [31:0] q0, q1;
    reg  [2:0]  warm = 3'd0;
    always @(posedge clk) begin
        c  <= c + 1'b1;
        cp <= c;
        q0 <= ram0[c];
        q1 <= ram1[c];
        if (!warm[2]) warm <= warm + 1'b1;
    end

    reg [31:0] n = 0, bad0 = 0, plus0 = 0, w0 = 0, e0 = 0, bad1 = 0, plus1 = 0, w1 = 0, e1 = 0;
    wire [31:0] want = {23'd0, cp};
    wire [31:0] next = {23'd0, cp + 9'd1};
    always @(posedge clk) if (warm[2]) begin
        n <= n + 1;
        if (q0 != want) begin bad0 <= bad0 + 1; w0 <= q0; e0 <= want; if (q0 == next) plus0 <= plus0 + 1; end
        if (q1 != want) begin bad1 <= bad1 + 1; w1 <= q1; e1 <= want; if (q1 == next) plus1 <= plus1 + 1; end
    end

    // ---- AXI: writes acknowledged, reads of the counters ---------------------------
    always @(posedge clk) begin
        awready <= 1'b0; wready <= 1'b0;
        if (awvalid && wvalid && !awready && !bvalid) begin awready <= 1'b1; wready <= 1'b1; bvalid <= 1'b1; end
        if (bvalid && bready) bvalid <= 1'b0;
    end
    always @(posedge clk) begin
        arready <= 1'b0;
        if (arvalid && !arready && !rvalid) begin
            arready <= 1'b1; rvalid <= 1'b1;
            case (araddr[5:2])
                4'd0: rdata <= 32'h5D9B0002;
                4'd1: rdata <= n;
                4'd2: rdata <= bad0;  4'd3: rdata <= plus0;
                4'd4: rdata <= w0;    4'd5: rdata <= e0;
                4'd6: rdata <= bad1;  4'd7: rdata <= plus1;
                4'd8: rdata <= w1;    4'd9: rdata <= e1;
                default: rdata <= 32'hdeadbeef;
            endcase
        end
        if (rvalid && rready) rvalid <= 1'b0;
    end

    assign pmod = bad0[7:0];
endmodule
