// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

module sid (
    input                clk,     // Master clock
    input                clkEn,   // 1Mhz enable
    input                iWE,     // write enable
    input         [ 4:0] iAddr,   // sid address
    input         [ 7:0] iDataW,  // C64 to SID
    output        [ 7:0] oDataR,  // SID to C64
    output signed [15:0] oOut,    // sid output
    inout                ioPotX,  // pot x pad
    inout                ioPotY   // pot y pad
);

  initial begin
    regVolume    = 4'hf;
    regFilt      = 0;
    regMode      = 0;
    regLastWrite = 0;
    reg3Off      = 0;
  end

  // oscillators
  wire [11:0] voiceOut0;
  wire [11:0] voiceOut1;
  wire [11:0] voiceOut2;
  sid_voices voices (
      .clk(clk),
      .clkEn(clkEn),
      .iWE(iWE),
      .iAddr(iAddr),
      .iDataW(iDataW),
      .oVoice0(voiceOut0),
      .oVoice1(voiceOut1),
      .oVoice2(voiceOut2)
  );

  // envelope 0
  wire [7:0] envOut0;
  sid_env #(
      .BASE_ADDR('h0)
  ) env0 (
      .clk  (clk),
      .clkEn(clkEn),
      .iWE  (iWE),
      .iAddr(iAddr),
      .iData(iDataW),
      .oOut (envOut0)
  );

  // envelope 1
  wire [7:0] envOut1;
  sid_env #(
      .BASE_ADDR('h7)
  ) env1 (
      .clk  (clk),
      .clkEn(clkEn),
      .iWE  (iWE),
      .iAddr(iAddr),
      .iData(iDataW),
      .oOut (envOut1)
  );

  // envelope 2
  wire [7:0] envOut2;
  sid_env #(
      .BASE_ADDR('he)
  ) env2 (
      .clk  (clk),
      .clkEn(clkEn),
      .iWE  (iWE),
      .iAddr(iAddr),
      .iData(iDataW),
      .oOut (envOut2)
  );

  wire [7:0] potX;
  sid_pot potx (
      .clk(clk),
      .clkEn(clkEn),
      .ioPotPad(ioPotX),
      .oPotVal(potX)
  );

  wire [7:0] potY;
  sid_pot poty (
      .clk(clk),
      .clkEn(clkEn),
      .ioPotPad(ioPotY),
      .oPotVal(potY)
  );

  // convert to signed format
  wire signed [11:0] voiceSigned0 = {~voiceOut0[11], voiceOut0[10:0]};
  wire signed [11:0] voiceSigned1 = {~voiceOut1[11], voiceOut1[10:0]};
  wire signed [11:0] voiceSigned2 = {~voiceOut2[11], voiceOut2[10:0]};

  // simulate multiplying dac (12bit-signed * 8bit-unsigned)
  reg signed [15:0] voiceAmp0;
  reg signed [15:0] voiceAmp1;
  reg signed [15:0] voiceAmp2;
  mdac12x8 mdac0 (
      clk,
      voiceSigned0,
      envOut0,
      voiceAmp0
  );
  mdac12x8 mdac1 (
      clk,
      voiceSigned1,
      envOut1,
      voiceAmp1
  );
  mdac12x8 mdac2 (
      clk,
      voiceSigned2,
      envOut2,
      voiceAmp2
  );

  // pre-filter mixer
  reg signed [15:0] preFilter;
  always @(posedge clk) begin
    // note: shifts are here to create some headroom
    preFilter <=
      (regFilt[0] ? (voiceAmp0 >>> 3) : 0) +
      (regFilt[1] ? (voiceAmp1 >>> 3) : 0) +
      (regFilt[2] ? (voiceAmp2 >>> 3) : 0);
  end

  // filter bypass mixer
  reg signed [15:0] bypass;
  always @(posedge clk) begin
    // note: shifts are here to create some headroom
    /* verilog_format: off */
    bypass <=
      ( regFilt[0]            ? 0 : (voiceAmp0 >>> 3)) +
      ( regFilt[1]            ? 0 : (voiceAmp1 >>> 3)) +
      ((regFilt[2] | reg3Off) ? 0 : (voiceAmp2 >>> 3));
    /* verilog_format: on */
  end

  // SID filter
  wire signed [15:0] sidFilterLP;
  wire signed [15:0] sidFilterBP;
  wire signed [15:0] sidFilterHP;
  filter sid_filter (
      clk,
      clkEn,
      preFilter,
      iWE,
      iAddr,
      iDataW,
      sidFilterLP,
      sidFilterBP,
      sidFilterHP
  );

  // post-filter mixer
  reg signed [16:0] postFilter;
  always @(posedge clk) begin
    postFilter <=
      bypass +
      (regMode[0] ? sidFilterLP : 0) +
      (regMode[1] ? sidFilterBP : 0) +
      (regMode[2] ? sidFilterHP : 0);
  end

  // clip after summing filter and bypass
  wire signed [15:0] preMasterVol;
  clipper post_filter_clip (
      postFilter,
      preMasterVol
  );

  // master volume stage
  reg signed [15:0] postMasterVol;
  mdac16x4 master_vol (
      clk,
      preMasterVol,
      regVolume,
      postMasterVol
  );

  // output state
  wire signed [15:0] postOutStage;
  filter15khz outState (
      .clk(clk),
      .clkEn(clkEn),
      .iIn(postMasterVol),
      .oOut(postOutStage)
  );

  // SID output
  assign oOut = postOutStage;

  // handle data reads
  // note: the real sid returns the last value writen to ANY
  //       register during a register read of write only reg.
  always @(*) begin
    case (iAddr)
      'h19:    oDataR <= potX;
      'h1a:    oDataR <= potY;
      'h1b:    oDataR <= voiceOut2[11:4];  // osc3 MSB
      'h1c:    oDataR <= envOut2;  // env3
      default: oDataR <= regLastWrite;  // potx/poty
    endcase
  end

  // address/data decoder
  reg [2:0] regFilt;  // voice routing
  reg [2:0] regMode;  // filter mode
  reg [3:0] regVolume;  // master volume
  reg [7:0] regLastWrite;  // last writen value
  reg       reg3Off;  // Oscillator 3 disconnect
  always @(posedge clk) begin
    if (iWE) begin
      // kee track of the last write for read purposes
      regLastWrite <= iDataW;
      case (iAddr)
        'h17: regFilt <= iDataW[2:0];
        'h18: begin
          regMode   <= iDataW[6:4];
          regVolume <= iDataW[3:0];
          reg3Off   <= iDataW[7];
        end
      endcase
    end
  end
endmodule
