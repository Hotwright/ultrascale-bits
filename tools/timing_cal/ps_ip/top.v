module top(output [3:0] led);
  wire clk;
  ps_wrapper ps_i(.pl_clk0(clk));
  (* DONT_TOUCH = "yes" *) reg [15:0] c = 0;
  (* DONT_TOUCH = "yes" *) reg [15:0] n = 0;
  always @(posedge clk) c <= c + 1'b1 + n[3];
  always @(negedge clk) n <= n ^ c;
  assign led = c[15:12] ^ n[15:12];
endmodule
