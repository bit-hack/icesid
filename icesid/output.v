// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

module filter15khz (
    input                clk,
    input                clkEn,
    input  signed [15:0] iIn,
    output signed [15:0] oOut
);

`ifdef DISABLED
  reg signed [15:0] s0;
  reg signed [15:0] s1;
  reg signed [15:0] s2;
  assign oOut = s2;

  initial begin
    s0 = 0;
    s1 = 0;
    s2 = 0;
  end

  wire signed [15:0] c0 = $signed(16'h099b);  // 15Khz
  wire signed [15:0] c1 = $signed(16'h0a86);  // 17.5Khz
  wire signed [15:0] c2 = $signed(16'h0b6e);  // 20Khz

  wire signed [31:0] t0 = c0 * (iIn - s0);
  wire signed [31:0] t1 = c1 * (s0  - s1);
  wire signed [31:0] t2 = c2 * (s1  - s2);

  always @(posedge clk) begin
    if (clkEn) begin
      s0 <= s0 + t0[30:15];
      s1 <= s1 + t1[30:15];
      s2 <= s2 + t2[30:15];
    end
  end
`else
  reg signed [15:0] t;
  always @(posedge clk) begin
    t <= iIn;
  end
  assign oOut = t;
`endif
endmodule
