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
    input                iRst,    // sync. reset
    input                iWE,     // write enable
    input         [ 4:0] iAddr,   // sid address
    input         [ 7:0] iDataW,  // C64 to SID
    output reg    [ 7:0] oDataR,  // SID to C64
    output signed [15:0] oOut     // sid output
`ifndef VERILATOR
    ,
    inout                ioPotX,  // pot x pad
    inout                ioPotY   // pot y pad
`endif  // VERILATOR
);

  initial begin

`ifdef VERILATOR
//    $dumpfile("trace.vcd");
//    $dumpvars;
`endif  // VERILATOR
    regIs6581    = 1;
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
      .clk     (clk),
      .clkEn   (clkEn),
      .iRst    (iRst),
      .iWE     (iWE),
      .iAddr   (iAddr),
      .iDataW  (iDataW),
      .oVoice0 (voiceOut0),
      .oVoice1 (voiceOut1),
      .oVoice2 (voiceOut2)
  );

  // envelope 0
  wire [7:0] envOut0;
  sid_env #(
      .BASE_ADDR('h0)
  ) env0 (
      .clk   (clk),
      .clkEn (clkEn),
      .iRst  (iRst),
      .iWE   (iWE),
      .iAddr (iAddr),
      .iData (iDataW),
      .oOut  (envOut0)
  );

  // envelope 1
  wire [7:0] envOut1;
  sid_env #(
      .BASE_ADDR('h7)
  ) env1 (
      .clk   (clk),
      .clkEn (clkEn),
      .iRst  (iRst),
      .iWE   (iWE),
      .iAddr (iAddr),
      .iData (iDataW),
      .oOut  (envOut1)
  );

  // envelope 2
  wire [7:0] envOut2;
  sid_env #(
      .BASE_ADDR('he)
  ) env2 (
      .clk   (clk),
      .clkEn (clkEn),
      .iRst  (iRst),
      .iWE   (iWE),
      .iAddr (iAddr),
      .iData (iDataW),
      .oOut  (envOut2)
  );

`ifndef VERILATOR

  wire [7:0] potX;
  wire [7:0] potY;

  sid_pot potx (
      .clk      (clk),
      .clkEn    (clkEn),
      .ioPotPad (ioPotX),
      .oPotVal  (potX)
  );

  sid_pot poty (
      .clk      (clk),
      .clkEn    (clkEn),
      .ioPotPad (ioPotY),
      .oPotVal  (potY)
  );
`endif  // VERILATOR

  // convert to signed format
  wire signed [11:0] voiceSigned0 = {~voiceOut0[11], voiceOut0[10:0]};
  wire signed [11:0] voiceSigned1 = {~voiceOut1[11], voiceOut1[10:0]};
  wire signed [11:0] voiceSigned2 = {~voiceOut2[11], voiceOut2[10:0]};

  // simulate multiplying dac (12bit-signed * 8bit-unsigned)
  reg signed [15:0] voiceAmp0;
  reg signed [15:0] voiceAmp1;
  reg signed [15:0] voiceAmp2;
  mdac12x8 mdac0 (
      .clk     (clk),
      .iVoice  (voiceSigned0),
      .iEnv    (envOut0),
      .oOut    (voiceAmp0)
  );
  mdac12x8 mdac1 (
      .clk     (clk),
      .iVoice  (voiceSigned1),
      .iEnv    (envOut1),
      .oOut    (voiceAmp1)
  );
  mdac12x8 mdac2 (
      .clk     (clk),
      .iVoice  (voiceSigned2),
      .iEnv    (envOut2),
      .oOut    (voiceAmp2)
  );

  // pre-filter mixer
  reg signed [15:0] preFilter;
  always @(posedge clk) begin
    // note: shifts are here to create some headroom
    /* verilog_format: off */
    preFilter <=
      (regFilt[0] ? (voiceAmp0 >>> 3) : 16'sd0) +
      (regFilt[1] ? (voiceAmp1 >>> 3) : 16'sd0) +
      (regFilt[2] ? (voiceAmp2 >>> 3) : 16'sd0);
    /* verilog_format: on */
  end

  // filter bypass mixer
  reg signed [15:0] bypass;
  always @(posedge clk) begin
    // note: shifts are here to create some headroom
    /* verilog_format: off */
    bypass <=
      ( regFilt[0]            ? 16'sd0 : (voiceAmp0 >>> 3)) +
      ( regFilt[1]            ? 16'sd0 : (voiceAmp1 >>> 3)) +
      ((regFilt[2] | reg3Off) ? 16'sd0 : (voiceAmp2 >>> 3));
    /* verilog_format: on */
  end

  // SID filter
  wire signed [15:0] sidFilterLP;
  wire signed [15:0] sidFilterBP;
  wire signed [15:0] sidFilterHP;
  filter sid_filter (
      .clk   (clk),
      .clkEn (clkEn),
      .iIn   (preFilter),
      .iWE   (iWE),
      .iAddr (iAddr),
      .iData (iDataW),
      .i6581 (regIs6581),
      .oLP   (sidFilterLP),
      .oBP   (sidFilterBP),
      .oHP   (sidFilterHP)
  );

  // DC offset for digital sample volume
  // Quote from resid:
  //     The mixer has a small input DC offset. This is found as follows:
  //
  //     The "zero" output level of the mixer measured on the SID audio
  //     output pin is 5.50V at zero volume, and 5.44 at full
  //     volume. This yields a DC offset of (5.44V - 5.50V) = -0.06V.
  //
  //     The DC offset is thus -0.06V/1.05V ~ -1/18 of the dynamic range
  //     of one voice.
  //
  // The DC offset is thus -0.06V/1.05V ~ -1/18 of the dynamic range
  // of one voice. See voice.cc for measurement of the dynamic
  // range.
  wire signed [16:0] mixer_DC = ~17'd3745;  // 65535 * (0.06 / 1.05)

  // post-filter mixer
  reg signed [16:0] postFilter;
  always @(posedge clk) begin
    /* verilog_format: off */
    postFilter <=
      bypass +
      mixer_DC +
      (regMode[0] ? 17'(sidFilterLP) : 17'sd0) +
      (regMode[1] ? 17'(sidFilterBP) : 17'sd0) +
      (regMode[2] ? 17'(sidFilterHP) : 17'sd0);
    /* verilog_format: on */
  end

  // clip after summing filter and bypass
  wire signed [15:0] preMasterVol;
  clipper post_filter_clip (
      .iIn  (postFilter),
      .oOut (preMasterVol)
  );

  // master volume stage
  reg signed [15:0] postMasterVol;
  mdac16x4 master_vol (
      .clk  (clk),
      .iMix (preMasterVol),
      .iVol (regVolume),
      .oOut (postMasterVol)
  );

  // output state
  wire signed [15:0] postOutStage;
  filter15khz outState (
      .clk   (clk),
      .clkEn (clkEn),
      .iIn   (postMasterVol),
      .oOut  (postOutStage)
  );

  // SID output
  assign oOut = postOutStage;

  // handle data reads
  // note: the real sid returns the last value writen to ANY
  //       register during a register read of write only reg.
  always @(*) begin
    case (iAddr)
`ifndef VERILATOR
      'h19:    oDataR = potX;
      'h1a:    oDataR = potY;
`endif  // VERILATOR
      'h1b:    oDataR = voiceOut2[11:4];  // osc3 MSB
      'h1c:    oDataR = envOut2;          // env3
      default: oDataR = regLastWrite;     // last written value
    endcase
  end

  // address/data decoder
  reg [2:0] regFilt;       // voice routing
  reg [2:0] regMode;       // filter mode
  reg [3:0] regVolume;     // master volume
  reg [7:0] regLastWrite;  // last writen value
  reg       reg3Off;       // Oscillator 3 disconnect
  reg       regIs6581;     // (non standard) select 6581 behaviour
  always @(posedge clk) begin
    if (iWE) begin
      // keep track of the last write for read purposes
      regLastWrite <= iDataW;
      case (iAddr)
        'h17: regFilt <= iDataW[2:0];
        'h18: { reg3Off, regMode, regVolume } <= iDataW;
      endcase
    end
  end
endmodule
