// KV260 PS-PL AXI board test: an AXI4 slave on M_AXI_HPM0_FPD (PS address
// 0xA000_0000, 128-bit data as the KV260 boot firmware configures it).
//
//   0xA000_0000..0C  r0..r3, read/write, byte strobes honoured
//   0xA000_0010      0xC0DE0A51, read only
//   0xA000_0014      free-running cycle counter
//   0xA000_0018      number of write beats accepted
//   0xA000_001C      number of read beats returned
//   0xA000_0020      number of write transactions (AW handshakes)
//   0xA000_0024      number of read transactions (AR handshakes)
//   0xA000_0028      {AWSIZE, AWLEN} of the longest write burst: [10:8], [7:0]
//   0xA000_002C      {ARSIZE, ARLEN} of the longest read burst
// Writing anything to 0x20-0x2F clears the four.
//
// Reads return the four 32-bit words of the addressed 16-byte line in their
// own lanes, so any narrow read finds its data. Bursts (INCR) are honoured:
// each beat moves on by 1 << AxSIZE. One transaction at a time per direction;
// IDs are echoed. The Pmod LEDs show both channels' state (dbg, below).
//
// r1[7:0] drives PL_PS_IRQ0[7:0] (GIC SPI 121-128) and r1[15:8] drives
// PL_PS_IRQ1[7:0] (SPI 136-143), so the PS can raise its own interrupts
// through the PL and watch them in the GIC distributor.
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    wire clk;

    // The PS8's outputs as they leave it (_p); the logic sees them through
    // the falling-edge stage below.
    wire [39:0] awaddr_p, araddr_p;
    wire [15:0] awid_p, arid_p;
    wire [7:0] awlen_p, arlen_p;
    wire [2:0] awsize_p, arsize_p;
    wire awvalid_p, arvalid_p, wvalid_p, wlast_p, bready_p, rready_p;
    wire [127:0] wdata_p;
    wire [15:0] wstrb_p;

    reg awready = 1'b0, wready = 1'b0, bvalid = 1'b0;
    reg arready = 1'b0, rvalid = 1'b0, rlast = 1'b0;
    reg [15:0] bid = 16'd0, rid = 16'd0;
    reg [127:0] rdata = 128'd0;

    reg [31:0] r0 = 32'h000000ff, r1 = 32'd0, r2 = 32'd0, r3 = 32'd0;

    // Every M_AXI_HPM0_FPD signal crosses between the PS8 and the logic
    // through a falling-edge register: the copies of our outputs (_n), and
    // the captures of the PS's. The PS works on the rising edge, so each pin
    // changes half a cycle away from the edge it is sampled on, and what each
    // side sees at a rising edge is what it would see without the stage.
    // nextpnr (place_ps_boundary) puts these registers beside the INT rows
    // where their PS8 pins cross into the fabric. Without both, the routes
    // ran up to 74 pips (there is no UltraScale+ timing model) and the PS and
    // the logic each caught bits of the other's next value: a 2-beat read's
    // first beat had bits of the second, writes stored wrong bits, ARSIZE 4
    // was read as 5.
    reg awready_n = 1'b0, wready_n = 1'b0, bvalid_n = 1'b0, arready_n = 1'b0, rvalid_n = 1'b0, rlast_n = 1'b0;
    reg [15:0] bid_n = 16'd0, rid_n = 16'd0;
    reg [127:0] rdata_n = 128'd0;
    always @(negedge clk) begin
        awready_n <= awready; wready_n <= wready; bvalid_n <= bvalid; bid_n <= bid;
        arready_n <= arready; rvalid_n <= rvalid; rlast_n <= rlast; rid_n <= rid; rdata_n <= rdata;
    end
    reg [11:0] awaddr = 12'd0, araddr = 12'd0;
    reg [15:0] awid = 16'd0, arid = 16'd0;
    reg [7:0] awlen = 8'd0, arlen = 8'd0;
    reg [2:0] awsize = 3'd0, arsize = 3'd0;
    reg awvalid = 1'b0, arvalid = 1'b0, wvalid = 1'b0, wlast = 1'b0, bready = 1'b0, rready = 1'b0;
    reg [127:0] wdata = 128'd0;
    reg [15:0] wstrb = 16'd0;
    always @(negedge clk) begin
        awaddr <= awaddr_p[11:0]; awid <= awid_p; awlen <= awlen_p; awsize <= awsize_p; awvalid <= awvalid_p;
        wdata <= wdata_p; wstrb <= wstrb_p; wlast <= wlast_p; wvalid <= wvalid_p; bready <= bready_p;
        araddr <= araddr_p[11:0]; arid <= arid_p; arlen <= arlen_p; arsize <= arsize_p; arvalid <= arvalid_p;
        rready <= rready_p;
    end

    PS8 ps8_i (
        .PLCLK(plclk),
        .PLPSIRQ0(r1[7:0]), .PLPSIRQ1(r1[15:8]),
        .MAXIGP0ACLK(clk),
        .MAXIGP0AWID(awid_p), .MAXIGP0AWADDR(awaddr_p), .MAXIGP0AWLEN(awlen_p),
        .MAXIGP0AWSIZE(awsize_p), .MAXIGP0AWVALID(awvalid_p), .MAXIGP0AWREADY(awready_n),
        .MAXIGP0WDATA(wdata_p), .MAXIGP0WSTRB(wstrb_p), .MAXIGP0WLAST(wlast_p),
        .MAXIGP0WVALID(wvalid_p), .MAXIGP0WREADY(wready_n),
        .MAXIGP0BID(bid_n), .MAXIGP0BRESP(2'b00), .MAXIGP0BVALID(bvalid_n), .MAXIGP0BREADY(bready_p),
        .MAXIGP0ARID(arid_p), .MAXIGP0ARADDR(araddr_p), .MAXIGP0ARLEN(arlen_p),
        .MAXIGP0ARSIZE(arsize_p), .MAXIGP0ARVALID(arvalid_p), .MAXIGP0ARREADY(arready_n),
        .MAXIGP0RID(rid_n), .MAXIGP0RDATA(rdata_n), .MAXIGP0RRESP(2'b00), .MAXIGP0RLAST(rlast_n),
        .MAXIGP0RVALID(rvalid_n), .MAXIGP0RREADY(rready_p));
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));

    reg [31:0] cyc = 32'd0, nwr = 32'd0, nrd = 32'd0, naw = 32'd0, nar = 32'd0;
    reg [10:0] maxaw = 11'd0, maxar = 11'd0;
    reg clr = 1'b0;
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
            naw <= naw + 1'b1;
            if (awlen >= maxaw[7:0]) maxaw <= {awsize, awlen};
        end
        if (wready && wvalid) begin
            nwr <= nwr + 1'b1;
            if (wa[11:4] == 8'd2) clr <= 1'b1;
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
        if (clr) begin
            clr <= 1'b0;
            naw <= 32'd0;
            maxaw <= 11'd0;
        end
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
            8'd2: line = {21'd0, maxar, 21'd0, maxaw, nar, naw};
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
            nar <= nar + 1'b1;
            if (arlen >= maxar[7:0]) maxar <= {arsize, arlen};
        end
        if (clr) begin
            nar <= 32'd0;
            maxar <= 11'd0;
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

    // Channel state on the LEDs (a pulse train as in kv260_dsp_test, first
    // bit first): {rbusy, rvalid, rlast, rready, arvalid, awvalid, wbusy,
    // bvalid, nar[3:0], nrd[3:0]}, as they are now, so a hung transfer shows
    // where it stopped.
    wire [15:0] dbg = {rbusy, rvalid, rlast, rready, arvalid, awvalid, wbusy, bvalid, nar[3:0], nrd[3:0]};
    reg [4:0] sl = 0;
    reg [15:0] word = 0;
    reg on = 0;
    always @(posedge clk) begin
        if (cyc[25:0] == 26'h3ffffff) begin
            sl <= sl == 5'd19 ? 5'd0 : sl + 1'b1;
            if (sl == 5'd19)
                word <= dbg;
        end
        on <= sl < 5'd16 && (cyc[25:24] == 2'd0 || (word[15 - sl[3:0]] && cyc[25:24] != 2'd3));
    end
    assign pmod = {8{on}};
endmodule
