// KV260 PMOD blinker, PL-only.
//
// Drives all eight PMOD pins on J2 (bank 45, HDIO) from a free-running
// counter, so a PMOD LED module shows a visible binary count. Bank 45 is the
// only PL-driven IO on this carrier that prjuray's ZU3EG-derived data fully
// covers - see SCOPE-K26.md.
//
// Output-only by design: the pad-to-fabric direction through
// INT_INTF_R_PCIE4 depends on an OUTPUTS_ENABLED analogue that has never been
// fuzzed, so nothing here reads a pin.
module top (
    input  wire       clk,
    output wire [7:0] pmod
);
    // At 100 MHz, bit 23 toggles at ~6 Hz and bit 26 at ~0.75 Hz, so the top
    // eight bits of a 27-bit counter are all visible by eye.
    reg [26:0] ctr = 27'd0;
    always @(posedge clk)
        ctr <= ctr + 1'b1;

    assign pmod = ctr[26:19];
endmodule
