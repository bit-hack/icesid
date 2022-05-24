// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

module sid_dac8(
  input            clk,
  input            iRst,
  input      [7:0] iIn,
  input            iStart,
  output reg [7:0] oOut);

  reg [ 2:0] count = 0;
  reg [ 7:0] data  = 0;
  reg [11:0] accum = 0;
  reg [11:0] coef  = 0;
  wire valid = ~|data;

  initial oOut = 8'd0;

  always @(*) begin
    case (count)
    3'd0: coef = 12'h01d;
    3'd1: coef = 12'h02a;
    3'd2: coef = 12'h04b;
    3'd3: coef = 12'h08d;
    3'd4: coef = 12'h110;
    3'd5: coef = 12'h20e;
    3'd6: coef = 12'h3fb;
    3'd7: coef = 12'h7b8;
    endcase
  end

  always @(posedge clk) begin
    data  <= iStart ? iIn   : (data >> 1);
    count <= iStart ? 3'd0  : count + 3'd1;
    accum <= iStart ? 12'd8 : accum + (data[0] ? coef : 12'd0);
    oOut  <= valid  ? accum[11:4] : oOut;
  end
endmodule
