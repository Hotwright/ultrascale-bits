// KV260 URAM288 board test: six LOC'd URAMs, each written with a pattern
// and read back. A shared sequencer runs a write pass over 256 addresses,
// then a read pass; every address is held for 8 cycles, written two cycles
// in and checked on the last, so no URAM's read latency matters. The pattern changes every round.
//
//   u0  X0Y0   A writes, B reads; every attribute default
//   u1  X0Y5   OREG_A, IREG_PRE_A, USE_EXT_CE_A (OREG_CE_A tied 1),
//              RST_MODE_A ASYNC (RST_A tied 0), AUTO_SLEEP_LATENCY 11
//   u2  X0Y10  byte writes: BWE_MODE_A PARITY_INDEPENDENT; a second write
//              of each address with BWE 9'h00f replaces bytes 0-3 only
//   u3  X0Y13  ECC (EN_ECC_WR_A, EN_ECC_RD_A): odd addresses are written
//              with INJECT_SBITERR_A; the read must be corrected, with
//              SBITERR_A set exactly there and DBITERR_A never
//   u4  X0Y34  inversions: EN_A, RDB_WR_A, RST_A (tied 1) inverted on A,
//              which writes; B reads with EN_B tied 0 and IS_EN_B_INVERTED
//   u5  X0Y63  SELF_ADDR_A 11'h001, SELF_MASK_A 11'h7fe: the URAM answers
//              only when ADDR_A[12] is 1, so a second write of each address
//              with ADDR_A[12] 0 and other data must leave it alone
//
// u3 sits in a URAM_URAM_DELAY_FT tile, the rest in URAM_URAM_FT; between
// them every site position (0-3) is used. The result goes out on every Pmod
// LED together as a pulse train (see kv260_dsp_test):
//   {pass[5:0], u3_saw_sbiterr, 1'b1, 8'hA5}
module top (output wire [7:0] pmod);
    wire [3:0] plclk;
    PS8 ps8_i (.PLCLK(plclk));
    wire clk;
    BUFG_PS bufg_i (.I(plclk[0]), .O(clk));
    reg [31:0] ctr = 32'd0;
    always @(posedge clk) ctr <= ctr + 1'b1;

    // ctr[2:0]: step within an address, ctr[10:3]: address, ctr[11]: read
    // pass, ctr[19:12]: round (the pattern seed).
    wire [2:0] step = ctr[2:0];
    wire [7:0] a = ctr[10:3];
    wire rd = ctr[11];
    wire [7:0] s = ctr[19:12];
    // The writes come two steps after the address and data change: nextpnr
    // has no UltraScale+ timing model, and d0/d1 go through a multiplier and
    // across the whole URAM column.
    wire wr0 = !rd && step == 3'd2;     // first write of an address
    wire wr1 = !rd && step == 3'd5;     // second write (u2, u5)
    wire check = rd && step == 3'd7;

    function [71:0] f(input [7:0] a, input [7:0] s);
        f = {a ^ s, {8'h12, a} * {8'h00, s | 8'h01}, {a, s} ^ 16'ha5c3,
             {a, 3'd0} + {8'h00, s}, ~{a, a} + {s, s}};
    endfunction
    wire [71:0] d0 = f(a, s);
    wire [71:0] d1 = f(~a, s ^ 8'h5a);
    wire [22:0] addr = {15'd0, a};

    wire [71:0] q0, q1, q2, q3, q4, q5;
    wire sbit3, dbit3;

    (* LOC = "URAM288_X0Y0" *)
    URAM288 u0 (.CLK(clk),
        .ADDR_A(addr), .DIN_A(d0), .EN_A(wr0), .RDB_WR_A(1'b1), .BWE_A(9'h1ff),
        .ADDR_B(addr), .DIN_B(72'd0), .EN_B(rd), .RDB_WR_B(1'b0), .BWE_B(9'h1ff), .DOUT_B(q0),
        .RST_A(1'b0), .RST_B(1'b0), .SLEEP(1'b0), .OREG_CE_A(1'b1), .OREG_CE_B(1'b1),
        .OREG_ECC_CE_A(1'b1), .OREG_ECC_CE_B(1'b1), .INJECT_SBITERR_A(1'b0), .INJECT_DBITERR_A(1'b0),
        .INJECT_SBITERR_B(1'b0), .INJECT_DBITERR_B(1'b0));

    (* LOC = "URAM288_X0Y5" *)
    URAM288 #(.OREG_A("TRUE"), .IREG_PRE_A("TRUE"), .USE_EXT_CE_A("TRUE"), .RST_MODE_A("ASYNC"),
              .AUTO_SLEEP_LATENCY(11))
        u1 (.CLK(clk),
        .ADDR_A(addr), .DIN_A(d0), .EN_A(wr0 | rd), .RDB_WR_A(!rd), .BWE_A(9'h1ff), .DOUT_A(q1),
        .ADDR_B(23'd0), .DIN_B(72'd0), .EN_B(1'b0), .RDB_WR_B(1'b0), .BWE_B(9'h1ff),
        .RST_A(1'b0), .RST_B(1'b0), .SLEEP(1'b0), .OREG_CE_A(1'b1), .OREG_CE_B(1'b1),
        .OREG_ECC_CE_A(1'b1), .OREG_ECC_CE_B(1'b1), .INJECT_SBITERR_A(1'b0), .INJECT_DBITERR_A(1'b0),
        .INJECT_SBITERR_B(1'b0), .INJECT_DBITERR_B(1'b0));

    (* LOC = "URAM288_X0Y10" *)
    URAM288 #(.BWE_MODE_A("PARITY_INDEPENDENT"))
        u2 (.CLK(clk),
        .ADDR_A(addr), .DIN_A(wr1 ? d1 : d0), .EN_A(wr0 | wr1 | rd), .RDB_WR_A(!rd),
        .BWE_A(wr1 ? 9'h00f : 9'h1ff), .DOUT_A(q2),
        .ADDR_B(23'd0), .DIN_B(72'd0), .EN_B(1'b0), .RDB_WR_B(1'b0), .BWE_B(9'h1ff),
        .RST_A(1'b0), .RST_B(1'b0), .SLEEP(1'b0), .OREG_CE_A(1'b1), .OREG_CE_B(1'b1),
        .OREG_ECC_CE_A(1'b1), .OREG_ECC_CE_B(1'b1), .INJECT_SBITERR_A(1'b0), .INJECT_DBITERR_A(1'b0),
        .INJECT_SBITERR_B(1'b0), .INJECT_DBITERR_B(1'b0));

    (* LOC = "URAM288_X0Y13" *)
    URAM288 #(.EN_ECC_WR_A("TRUE"), .EN_ECC_RD_A("TRUE"))
        u3 (.CLK(clk),
        .ADDR_A(addr), .DIN_A(d0), .EN_A(wr0 | rd), .RDB_WR_A(!rd), .BWE_A(9'h1ff), .DOUT_A(q3),
        .SBITERR_A(sbit3), .DBITERR_A(dbit3), .INJECT_SBITERR_A(wr0 & a[0]), .INJECT_DBITERR_A(1'b0),
        .ADDR_B(23'd0), .DIN_B(72'd0), .EN_B(1'b0), .RDB_WR_B(1'b0), .BWE_B(9'h1ff),
        .RST_A(1'b0), .RST_B(1'b0), .SLEEP(1'b0), .OREG_CE_A(1'b1), .OREG_CE_B(1'b1),
        .OREG_ECC_CE_A(1'b1), .OREG_ECC_CE_B(1'b1), .INJECT_SBITERR_B(1'b0), .INJECT_DBITERR_B(1'b0));

    (* LOC = "URAM288_X0Y34" *)
    URAM288 #(.IS_EN_A_INVERTED(1'b1), .IS_RDB_WR_A_INVERTED(1'b1), .IS_RST_A_INVERTED(1'b1),
              .IS_EN_B_INVERTED(1'b1))
        u4 (.CLK(clk),
        .ADDR_A(addr), .DIN_A(d0), .EN_A(!wr0), .RDB_WR_A(1'b0), .BWE_A(9'h1ff),
        .ADDR_B(addr), .DIN_B(72'd0), .EN_B(1'b0), .RDB_WR_B(1'b0), .BWE_B(9'h1ff), .DOUT_B(q4),
        .RST_A(1'b1), .RST_B(1'b0), .SLEEP(1'b0), .OREG_CE_A(1'b1), .OREG_CE_B(1'b1),
        .OREG_ECC_CE_A(1'b1), .OREG_ECC_CE_B(1'b1), .INJECT_SBITERR_A(1'b0), .INJECT_DBITERR_A(1'b0),
        .INJECT_SBITERR_B(1'b0), .INJECT_DBITERR_B(1'b0));

    (* LOC = "URAM288_X0Y63" *)
    URAM288 #(.SELF_ADDR_A(11'h001), .SELF_MASK_A(11'h7fe))
        u5 (.CLK(clk),
        .ADDR_A({10'd0, !wr1, 4'd0, a}), .DIN_A(wr1 ? d1 : d0), .EN_A(wr0 | wr1 | rd), .RDB_WR_A(!rd),
        .BWE_A(9'h1ff), .DOUT_A(q5),
        .ADDR_B(23'd0), .DIN_B(72'd0), .EN_B(1'b0), .RDB_WR_B(1'b0), .BWE_B(9'h1ff),
        .RST_A(1'b0), .RST_B(1'b0), .SLEEP(1'b0), .OREG_CE_A(1'b1), .OREG_CE_B(1'b1),
        .OREG_ECC_CE_A(1'b1), .OREG_ECC_CE_B(1'b1), .INJECT_SBITERR_A(1'b0), .INJECT_DBITERR_A(1'b0),
        .INJECT_SBITERR_B(1'b0), .INJECT_DBITERR_B(1'b0));

    wire [71:0] e2 = {d0[71:64], d0[63:32], d1[31:0]};

    reg [5:0] fail = 0;
    reg checked = 0, saw = 0;
    always @(posedge clk)
        if (check) begin
            checked <= 1'b1;
            if (q0 != d0) fail[0] <= 1'b1;
            if (q1 != d0) fail[1] <= 1'b1;
            if (q2 != e2) fail[2] <= 1'b1;
            if (q3[63:0] != d0[63:0] || sbit3 != a[0] || dbit3) fail[3] <= 1'b1;
            if (q4 != d0) fail[4] <= 1'b1;
            if (q5 != d0) fail[5] <= 1'b1;
            if (sbit3) saw <= 1'b1;
        end
    wire [5:0] pass = checked ? ~fail : 6'd0;

    // Readout (as kv260_dsp_test).
    reg [4:0] sl = 0;
    reg [15:0] word = 0;
    reg on = 0;
    always @(posedge clk) begin
        if (ctr[25:0] == 26'h3ffffff) begin
            sl <= sl == 5'd19 ? 5'd0 : sl + 1'b1;
            if (sl == 5'd19)
                word <= {pass, saw, 1'b1, 8'ha5};
        end
        on <= sl < 5'd16 && (ctr[25:24] == 2'd0 || (word[15 - sl[3:0]] && ctr[25:24] != 2'd3));
    end
    assign pmod = {8{on}};
endmodule
