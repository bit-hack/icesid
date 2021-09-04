// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

module cic_filter (
    input                clk,     // system clock
    input                clkEnA,  // input sample rate
    input                clkEnB,  // output sample rate
    input  signed [15:0] iIn,     // input sample
    output signed [15:0] oOut     // filtered sample
);

  // D             = 1000000 / ~44100   = ~23
  // bits required = log2(2^16 * 23)    = ~21

  reg signed [21:0] inAcc;
  reg signed [21:0] outLag;

  reg signed [21:0] out;
  assign oOut = out[21:6];

  initial begin
    inAcc  <= 0;
    outLag <= 0;
    out    <= 0;
  end

  // integration stage
  always @(posedge clk) begin
    if (clkEnA) begin
      inAcc <= inAcc + iIn;
    end
  end

  // comb stage
  always @(posedge clk) begin
    if (clkEnB) begin
      out    <= inAcc - outLag;
      outLag <= inAcc;
    end
  end
endmodule
