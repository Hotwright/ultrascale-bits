// The design inside blinky_board.v: a counter on the J2 LEDs, so the board
// shows the bitstream is running. blinky_board.v and blinky_board.xdc are
// Studio's own output (Agent-Hotwright app.js designBoardWrapperV /
// designBoardConstraint, as deployed 2026-11-03 at ?v=723) for boards/kv260.json,
// whose fixed_outputs drive A12 fan_en_b from the PS8's EMIOTTC0WAVEO[2].
module blinky (input wire clk, input wire clk_rst_n, output wire [7:0] led);
    reg [26:0] ctr = 27'd0;
    always @(posedge clk) if (!clk_rst_n) ctr <= 27'd0; else ctr <= ctr + 1'b1;
    assign led = ctr[26:19];
endmodule
