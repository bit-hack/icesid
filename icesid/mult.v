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
  reg signed [31:0] product;
  assign oOut = product[31:16];
  always @(posedge clk) begin
    product <= $signed(iSignal) * $unsigned(iCoef);
  end
endmodule

// 16x4 multiplier used for master volume
module mdac16x4 (
    input                clk,
    input  signed [15:0] iVoice,
    input         [ 3:0] iVol,
    output signed [15:0] oOut
);
  reg signed [31:0] product;  // 16x16 product
  assign oOut = product[19:4];
  always @(posedge clk) begin
    product <= $signed(iVoice) * $unsigned({12'b0, iVol});
  end
endmodule

// 12x8 multiplier used for voice envelopes
module mdac12x8 (
    input                clk,
    input  signed [11:0] iVoice,
    input         [ 7:0] iEnv,
    output signed [15:0] oOut
);
  reg signed [31:0] product;  // 16x16 product
  assign oOut = product[23:8];
  always @(posedge clk) begin
    product <= $signed({iVoice, 4'b0}) * $unsigned({8'b0, iEnv});
  end
endmodule
