`default_nettype none
`timescale 1ns / 1ps

// 16x4 multiplier used for master volume
module mdac16x4(
    input                CLK,
    input  signed [15:0] VOICE,
    input         [ 3:0] VOL,
    output signed [15:0] OUTPUT
    );

  wire signed [31:0] product;  // 16x16 product
  SB_MAC16 mac(
    .A(VOICE),
    .B({12'b0, VOL}),
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
    out <= product[19:4];
  end
endmodule

// 12x8 multiplier used for voice envelopes
module mdac12x8(
    input                CLK,
    input  signed [11:0] VOICE,
    input         [ 7:0] ENV,
    output signed [15:0] OUTPUT
    );

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

module sid(
    input                CLK,     // Master clock
    input                CLKen,   // 1Mhz enable
    input                WR,      // write data to sid addr
    input         [ 4:0] ADDR,    // sid address
    input         [ 7:0] DATAW,   // C64 to SID
    output        [ 7:0] DATAR,   // SID to C64
    output signed [15:0] OUTPUT
    );

  initial begin
    reg_volume     = 4'hf;
    reg_filt       = 0;
    reg_mode       = 0;
    reg_last_write = 0;
    reg_3off       = 0;
  end

  // voice 0
  wire msb0;
  wire [11:0] voice0_out;
  sid_voice #(.BASE_ADDR('h0)) voice0(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATAW),
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
    .DATA(DATAW),
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
    .DATA(DATAW),
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
    .DATA(DATAW),
    .OUTPUT(env0_out));

  // envelope 1
  wire [7:0] env1_out;
  sid_env #(.BASE_ADDR('h7)) env1(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATAW),
    .OUTPUT(env1_out));

  // envelope 2
  wire [7:0] env2_out;
  sid_env #(.BASE_ADDR('he)) env2(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATAW),
    .OUTPUT(env2_out));

  // convert to signed format
  wire signed [11:0] voice0_signed = { ~voice0_out[11], voice0_out[10:0] };
  wire signed [11:0] voice1_signed = { ~voice1_out[11], voice1_out[10:0] };
  wire signed [11:0] voice2_signed = { ~voice2_out[11], voice2_out[10:0] };

  // simulate multiplying dac (12bit-signed * 8bit-unsigned)
  reg signed [15:0] voice0_amp;
  reg signed [15:0] voice1_amp;
  reg signed [15:0] voice2_amp;
  mdac12x8 mdac0(CLK, voice0_signed, env0_out, voice0_amp);
  mdac12x8 mdac1(CLK, voice1_signed, env1_out, voice1_amp);
  mdac12x8 mdac2(CLK, voice2_signed, env2_out, voice2_amp);

  wire signed [15:0] sid_filter_lp;
  wire signed [15:0] sid_filter_bp;
  wire signed [15:0] sid_filter_hp;
  filter sid_filter(
    CLK,
    CLKen,
    pre_filter,
    WR,
    ADDR,
    DATAW,
    sid_filter_lp,
    sid_filter_bp,
    sid_filter_hp);

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
      ( reg_filt[0]             ? 8'b0 : (voice0_amp >>> 3)) +
      ( reg_filt[1]             ? 8'b0 : (voice1_amp >>> 3)) +
      ((reg_filt[2] | reg_3off) ? 8'b0 : (voice2_amp >>> 3));
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

  // master volume stage
  reg signed [15:0] post_master_vol;
  mdac16x4 master_vol(
    CLK,
    post_filter,
    reg_volume,
    post_master_vol);

  // SID output
  assign OUTPUT = post_master_vol;

  // handle data reads
  // note: the real sid returns the last value writen to ANY
  //       register during a register read of write only reg.
  always @(*) begin
    case (ADDR)
    'h19:    DATAR <= 8'h00;              // potx
    'h1a:    DATAR <= 8'h00;              // poty
    'h1b:    DATAR <= voice2_out[11:4];   // osc3 MSB
    'h1c:    DATAR <= env2_out;           // env3
    default: DATAR <= reg_last_write;     // potx/poty
    endcase
  end

  // address/data decoder
  reg [2:0] reg_filt;       // voice routing
  reg [2:0] reg_mode;       // filter mode
  reg [3:0] reg_volume;     // master volume
  reg [7:0] reg_last_write; // last writen value
  reg       reg_3off;       // osc3 off
  always @(posedge CLK) begin
    if (WR) begin
      // kee track of the last write for read purposes
      reg_last_write <= DATAW;
      case (ADDR)
      'h17: reg_filt <= DATAW[2:0];
      'h18: begin
        reg_mode     <= DATAW[6:4];
        reg_volume   <= DATAW[3:0];
//        reg_3off     <= DATAW[7];
      end
      endcase
    end
  end
endmodule
