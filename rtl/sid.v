`default_nettype none
`timescale 1ns / 1ps

module mdac(input CLK,
            input signed [11:0] VOICE,
            input [7:0] ENV,
            output signed [15:0] OUTPUT);

  wire signed [31:0] product;  // 16x16 product
  SB_MAC16 mac(
    .A({VOICE, 4'b0}),
    .B({8'b0, ENV}),
    .O(product),
    .CLK(CLK),
  );

  defparam mac.A_SIGNED = 1'b1;           // voice is signed
  defparam mac.B_SIGNED = 1'b0;           // env is unsigned
  defparam mac.TOPOUTPUT_SELECT = 2'b11;  // Mult16x16 data output
  defparam mac.BOTOUTPUT_SELECT = 2'b11;  // Mult16x16 data output

  reg [15:0] out;
  assign OUTPUT = out;
  always @(posedge CLK) begin
    out <= product[23:8];
  end
endmodule

module sid(input CLK,         // Master clock
           input CLKen,       // 1Mhz enable
           input WR,          // write data to sid addr
           input [4:0] ADDR,
           input [7:0] DATA,
           output signed [15:0] OUTPUT);

  // voice 0
  wire msb0;
  wire [11:0] voice0_out;
  sid_voice #(.BASE_ADDR('h0)) voice0(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .EXTMSB(msb2),
    .MSBOUT(msb0),
    .OUTPUT(voice0_out));

  // voice 1
  wire msb1;
  wire [11:0] voice1_out;
  sid_voice #(.BASE_ADDR('h7)) voice1(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .EXTMSB(msb0),
    .MSBOUT(msb1),
    .OUTPUT(voice1_out));

  // voice 2
  wire msb2;
  wire [11:0] voice2_out;
  sid_voice #(.BASE_ADDR('he)) voice2(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .EXTMSB(msb1),
    .MSBOUT(msb2),
    .OUTPUT(voice2_out));

  // envelope 0
  wire [7:0] env0_out;
  sid_env #(.BASE_ADDR('h0)) env0(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(env0_out));

  // envelope 1
  wire [7:0] env1_out;
  sid_env #(.BASE_ADDR('h7)) env1(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(env1_out));

  // envelope 2
  wire [7:0] env2_out;
  sid_env #(.BASE_ADDR('he)) env2(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(env2_out));

  // convert to signed format
  wire signed [11:0] voice0_signed = { ~voice0_out[11], voice0_out[10:0] };
  wire signed [11:0] voice1_signed = { ~voice1_out[11], voice1_out[10:0] };
  wire signed [11:0] voice2_signed = { ~voice2_out[11], voice2_out[10:0] };

  // simulate multiplying dac (12bit-signed * 8bit-unsigned)
  reg signed [15:0] voice0_amp;
  reg signed [15:0] voice1_amp;
  reg signed [15:0] voice2_amp;
  mdac mdac0(CLK, voice0_signed, env0_out, voice0_amp);
  mdac mdac1(CLK, voice1_signed, env1_out, voice1_amp);
  mdac mdac2(CLK, voice2_signed, env2_out, voice2_amp);

  wire signed [15:0] sid_filter_lp;
  wire signed [15:0] sid_filter_bp;
  wire signed [15:0] sid_filter_hp;
  filter sid_filter(
    CLK,
    CLKen,
    pre_filter,
    WR,
    ADDR,
    DATA,
    sid_filter_lp,
    sid_filter_bp,
    sid_filter_hp
    );

  // pre-filter mixer
  reg signed [15:0] pre_filter;
  always @(posedge CLK) begin
    pre_filter <=
      (reg_filt[0] ? (voice0_amp >>> 3) : 0) +
      (reg_filt[1] ? (voice1_amp >>> 3) : 0) +
      (reg_filt[2] ? (voice2_amp >>> 3) : 0);
  end

  // filter bypass mixer
  reg signed [15:0] bypass;
  always @(posedge CLK) begin
    bypass <=
      (reg_filt[0] ? 0 : (voice0_amp >>> 3)) +
      (reg_filt[1] ? 0 : (voice1_amp >>> 3)) +
      (reg_filt[2] ? 0 : (voice2_amp >>> 3));
  end

  // post_filter mixer
  reg signed [15:0] post_filter;
  always @(posedge CLK) begin
    post_filter <=
      bypass +
      (reg_mode[0] ? sid_filter_lp : 0) +
      (reg_mode[1] ? sid_filter_bp : 0) +
      (reg_mode[2] ? sid_filter_hp : 0);
  end

  // SID output
  // XXX: still do do is the final volume stage
  assign OUTPUT = post_filter;

  // address/data decoder
  reg [2:0] reg_filt;   // voice routing
  reg [2:0] reg_mode;   // filter mode
  reg [3:0] reg_volume; // master volume
  always @(posedge CLK) begin
    if (WR) begin
      case (ADDR)
      'h17: begin
        reg_filt <= DATA[2:0];
      end
      'h18: begin
        reg_mode   <= DATA[6:4];
        reg_volume <= DATA[3:0];
      end
      endcase
    end
  end
endmodule
