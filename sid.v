`default_nettype none
`timescale 1ns / 1ps

module sid(input CLK,     // Master clock
           input CLKen,   // 1Mhz enable
           input WR,
           input [4:0] ADDR,
           input [7:0] DATA,
           output signed [15:0] OUTPUT);

  // instanciate voice 0
  wire [11:0] voice0_out;
  sid_voice #(.BASE_ADDR('h0)) voice0(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(voice0_out));

  // instanciate voice 1
  wire [11:0] voice1_out;
  sid_voice #(.BASE_ADDR('h7)) voice1(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(voice1_out));

  // instanciate voice 2
  wire [11:0] voice2_out;
  sid_voice #(.BASE_ADDR('he)) voice2(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(voice2_out));

  // instanciate envelope 0
  wire [7:0] env0_out;
  sid_env #(.BASE_ADDR('h0)) env0(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(env0_out));

  // instanciate envelope 1
  wire [7:0] env1_out;
  sid_env #(.BASE_ADDR('h7)) env1(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(env1_out));

  // instanciate envelope 2
  wire [7:0] env2_out;
  sid_env #(.BASE_ADDR('he)) env2(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(env2_out));

//`define OLD
`ifdef OLD
  wire signed [15:0] voice0_signed = { ~voice0_out[11], voice0_out[10:0], 4'h0 };
  reg signed [15:0] sid_out;
  assign OUTPUT = sid_out;
  always @(posedge CLK) begin
    sid_out <= voice0_signed;
  end
`else
  // convert to signed format
  wire signed [11:0] voice0_signed = { ~voice0_out[11], voice0_out[10:0] };
  wire signed [11:0] voice1_signed = { ~voice1_out[11], voice1_out[10:0] };
  wire signed [11:0] voice2_signed = { ~voice2_out[11], voice2_out[10:0] };

  // simulate multiplying dac (16bit-signed * 8bit-unsigned)
  wire signed [20:0] voice0_muldac =
    voice0_signed * $signed({ 1'b0, env0_out });
  wire signed [20:0] voice1_muldac =
    voice1_signed * $signed({ 1'b0, env1_out });
  wire signed [20:0] voice2_muldac =
    voice2_signed * $signed({ 1'b0, env2_out });

  reg signed [15:0] sid_out;
  assign OUTPUT = sid_out;
  always @(posedge CLK) begin
    sid_out <= voice0_muldac[20:5] +
               voice1_muldac[20:5] +
               voice2_muldac[20:5];
  end
`endif
endmodule
