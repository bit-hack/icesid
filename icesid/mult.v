// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

// 16x16 multiplier for the filters
module mult16x16 (
    input                clk,
    input  signed [16:0] iSignal,
    input         [15:0] iCoef,
    output signed [15:0] oOut
);

`ifdef VERILATOR
  reg signed [31:0] product;  // 16x16 product
  assign oOut = product[31:16];
  always @(clk) begin
    product = iSignal * iCoef;
  end

`else

  wire signed [15:0] clipped;
  clipper clip (
      iSignal,
      clipped
  );

  wire signed [31:0] product;  // 16x16 product
  assign oOut = product[31:16];
  SB_MAC16 mac (
      .A  (clipped),
      .B  (iCoef),
      .O  (product),
      .CLK(clk)
  );

  defparam mac.A_SIGNED = 1'b1;  // input is signed
  defparam mac.B_SIGNED = 1'b0;  // coefficient is unsigned
  defparam mac.TOPOUTPUT_SELECT = 2'b11;  // Mult16x16 data output
  defparam mac.BOTOUTPUT_SELECT = 2'b11;  // Mult16x16 data output
`endif  // VERILATOR
endmodule

// 16x4 multiplier used for master volume
module mdac16x4 (
    input                clk,
    input  signed [15:0] iVoice,
    input         [ 3:0] iVol,
    output signed [15:0] oOut
);

`ifdef VERILATOR
  reg signed [19:0] product;  // 16x4 product
  assign oOut = product[19:4];
  always @(clk) begin
    product = iVoice * iVol;
  end

`else

  wire signed [31:0] product;  // 16x16 product
  SB_MAC16 mac (
      .A  (iVoice),
      .B  ({12'b0, iVol}),
      .O  (product),
      .CLK(clk),
  );

  defparam mac.A_SIGNED = 1'b1;  // voice is signed
  defparam mac.B_SIGNED = 1'b0;  // env is unsigned
  defparam mac.TOPOUTPUT_SELECT = 2'b11;  // Mult16x16 data output
  defparam mac.BOTOUTPUT_SELECT = 2'b11;  // Mult16x16 data output

  reg [15:0] out;
  assign oOut = out;
  always @(posedge clk) begin
    out <= product[19:4];
  end
`endif // VERILATOR
endmodule

// 12x8 multiplier used for voice envelopes
module mdac12x8 (
    input                clk,
    input  signed [11:0] iVoice,
    input         [ 7:0] iEnv,
    output signed [15:0] oOut
);

`ifdef VERILATOR
  reg signed [19:0] product;  // 16x4 product
  assign oOut = product[19:4];
  always @(clk) begin
    product = iVoice * iEnv;
  end

`else
  wire signed [31:0] product;  // 16x16 product
  SB_MAC16 mac (
      .A  ({iVoice, 4'b0}),
      .B  ({8'b0, iEnv}),
      .O  (product),
      .CLK(clk),
  );

  defparam mac.A_SIGNED = 1'b1;  // voice is signed
  defparam mac.B_SIGNED = 1'b0;  // env is unsigned
  defparam mac.TOPOUTPUT_SELECT = 2'b11;  // Mult16x16 data output
  defparam mac.BOTOUTPUT_SELECT = 2'b11;  // Mult16x16 data output

  reg [15:0] out;
  assign oOut = out;
  always @(posedge clk) begin
    out <= product[23:8];
  end
`endif  // VERILATOR
endmodule
