// KV260 PS-PL AXI board test: an AXI4 slave on M_AXI_HPM0_FPD (PS address
// 0xA000_0000, 128-bit data as the KV260 boot firmware configures it).
//
//   0xA000_0000..0C  r0..r3, read/write, byte strobes honoured
//   0xA000_0010      0xC0DE0A51, read only
//   0xA000_0014      free-running cycle counter
//   0xA000_0018      number of write beats accepted
//   0xA000_001C      number of read beats returned
//
// Reads return the four 32-bit words of the addressed 16-byte line in their
// own lanes, so any narrow read finds its data. Bursts (INCR) are honoured:
// each beat moves on by 1 << AxSIZE. One transaction at a time per direction;
// IDs are echoed. The Pmod LEDs show r0[7:0] (LEDs are active-low: a 1 bit
// is a dark LED).
//
// r1[7:0] drives PL_PS_IRQ0[7:0] (GIC SPI 121-128) and r1[15:8] drives
// PL_PS_IRQ1[7:0] (SPI 136-143), so the PS can raise its own interrupts
// through the PL and watch them in the GIC distributor.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    wire clk;

    wire [39:0] awaddr, araddr;
    wire [15:0] awid, arid;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire awvalid, arvalid, wvalid, wlast, bready, rready;
    wire [127:0] wdata;
    wire [15:0] wstrb;

    reg awready = 1'b0, wready = 1'b0, bvalid = 1'b0;
    reg arready = 1'b0, rvalid = 1'b0, rlast = 1'b0;
    reg [15:0] bid = 16'd0, rid = 16'd0;
    reg [127:0] rdata = 128'd0;

    reg [31:0] r0 = 32'h000000ff, r1 = 32'd0, r2 = 32'd0, r3 = 32'd0;

    PS8 ps8_i (
        .PLCLK(plclk),
        .PLPSIRQ0(r1[7:0]), .PLPSIRQ1(r1[15:8]),
        .MAXIGP0ACLK(clk),
        .MAXIGP0AWID(awid), .MAXIGP0AWADDR(awaddr), .MAXIGP0AWLEN(awlen),
        .MAXIGP0AWSIZE(awsize), .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready),
        .MAXIGP0WDATA(wdata), .MAXIGP0WSTRB(wstrb), .MAXIGP0WLAST(wlast),
        .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready),
        .MAXIGP0BID(bid), .MAXIGP0BRESP(2'b00), .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready),
        .MAXIGP0ARID(arid), .MAXIGP0ARADDR(araddr), .MAXIGP0ARLEN(arlen),
        .MAXIGP0ARSIZE(arsize), .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready),
        .MAXIGP0RID(rid), .MAXIGP0RDATA(rdata), .MAXIGP0RRESP(2'b00), .MAXIGP0RLAST(rlast),
        .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready));
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    reg [31:0] cyc = 32'd0, nwr = 32'd0, nrd = 32'd0;
    always @(posedge clk) cyc <= cyc + 1'b1;

    // Write channel: take AW, then W beats until WLAST, then B.
    reg wbusy = 1'b0;
    reg [11:0] wa = 12'd0;
    reg [2:0] wsz = 3'd0;
    function [31:0] merge(input [31:0] old, input [31:0] d, input [3:0] s);
        merge = {s[3] ? d[31:24] : old[31:24], s[2] ? d[23:16] : old[23:16],
                 s[1] ? d[15:8] : old[15:8], s[0] ? d[7:0] : old[7:0]};
    endfunction
    always @(posedge clk) begin
        awready <= 1'b0;
        if (!wbusy && !bvalid && awvalid && !awready) begin
            awready <= 1'b1;
            wbusy <= 1'b1;
            wready <= 1'b1;
            wa <= awaddr[11:0];
            wsz <= awsize;
            bid <= awid;
        end
        if (wready && wvalid) begin
            nwr <= nwr + 1'b1;
            if (wa[11:4] == 8'd0) begin
                r0 <= merge(r0, wdata[31:0], wstrb[3:0]);
                r1 <= merge(r1, wdata[63:32], wstrb[7:4]);
                r2 <= merge(r2, wdata[95:64], wstrb[11:8]);
                r3 <= merge(r3, wdata[127:96], wstrb[15:12]);
            end
            wa <= wa + (12'd1 << wsz);
            if (wlast) begin
                wready <= 1'b0;
                wbusy <= 1'b0;
                bvalid <= 1'b1;
            end
        end
        if (bvalid && bready)
            bvalid <= 1'b0;
    end

    // Read channel: take AR, then ARLEN+1 beats.
    reg rbusy = 1'b0;
    reg [11:0] ra = 12'd0;
    reg [2:0] rsz = 3'd0;
    reg [7:0] rleft = 8'd0;
    function [127:0] line(input [11:0] a);
        case (a[11:4])
            8'd0: line = {r3, r2, r1, r0};
            8'd1: line = {nrd, nwr, cyc, 32'hC0DE0A51};
            default: line = {4{20'hDEAD0, a}};
        endcase
    endfunction
    always @(posedge clk) begin
        arready <= 1'b0;
        if (!rbusy && arvalid && !arready) begin
            arready <= 1'b1;
            rbusy <= 1'b1;
            ra <= araddr[11:0];
            rsz <= arsize;
            rleft <= arlen;
            rid <= arid;
        end
        if (rvalid && rready) begin
            nrd <= nrd + 1'b1;
            if (rlast) begin
                rvalid <= 1'b0;
                rlast <= 1'b0;
                rbusy <= 1'b0;
            end else begin
                ra <= ra + (12'd1 << rsz);
                rleft <= rleft - 1'b1;
                rdata <= line(ra + (12'd1 << rsz));
                rlast <= rleft == 8'd1;
            end
        end else if (rbusy && !rvalid) begin
            rdata <= line(ra);
            rlast <= rleft == 8'd0;
            rvalid <= 1'b1;
        end
    end

    assign pmod = r0[7:0];
endmodule
