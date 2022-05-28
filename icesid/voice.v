// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

module sid_voice (
    input         clk,      // master clock
    input         clkEn,    // asserted at 1Mhz
    input         iRst,     // reset
    input         iWE,      // data write
    input  [ 4:0] iAddr,    // address bus
    input  [ 7:0] iData,    // data bus
    input         iExtMSB,  // external msb input
    output        oMSB,     // msb out for ringmod and sync
    output [11:0] oOut      // voice output
);

  // tap from the phase acumulator to clock the noise LFSR
  localparam noiseClkBit = 19;

  // register base address
  parameter BASE_ADDR = 0;

  // voice related internal registers
  reg [15:0] regFreq    = 0;  // frequency
  reg [11:0] regPW      = 0;  // pulse width
  reg        regNoise   = 0;  // wave-select noise enable
  reg        regPulse   = 0;  // wave-select pulse enable
  reg        regSaw     = 0;  // wave-select saw enable
  reg        regTri     = 0;  // wave-select triangle enable
  reg        regTest    = 0;  // test register
  reg        regRingMod = 0;  // ring modulate
  reg        regSync    = 0;  // oscillator sync

  // phase accumulator
  // the oscillator frequency can be calculated as:
  //   Freq = (Mclk * reg_freq) / (16777215)
  assign oMSB = phase[23];
  reg extMSBLag = 0;
  reg [23:0] phase = 24'h555555;
  always @(posedge clk) begin
    if (iRst) begin
      phase <= 0;
    end else begin
      if (clkEn) begin
        if (regTest || regSync && !iExtMSB && extMSBLag) begin
          // reset due to sync or test bit being high
          phase <= 0;
        end else begin
          phase <= phase + {8'd0, regFreq};
        end
        noiseClkLag <= phase[noiseClkBit];
        extMSBLag   <= iExtMSB;
      end
    end
  end

  // noise generator (23bit LFSR)
  // todo: noise lockup, handle reset
  reg [22:0] lfsr = 23'h7fffff;
  reg noiseClkLag = 0;
  always @(posedge clk) begin
    if (clkEn) begin
      // update noise when bit 19 goes high
      noiseClkLag <= phase[noiseClkBit];
      if (phase[noiseClkBit] && !noiseClkLag) begin
        lfsr <= {lfsr[21:0], (regTest | lfsr[22]) ^ lfsr[17]};
      end
    end
  end

  // waveform generators
  // note: at this stage all waveforms are unsigned with center point at 'h800
  reg [11:0] wavSaw   = 12'd0;
  reg [11:0] wavPulse = 12'd0;
  reg [11:0] wavTri   = 12'd0;
  reg [11:0] wavNoise = 12'd0;
  always @(posedge clk) begin
    wavSaw   <= phase[23:12];
    wavPulse <= (phase[23:12] <= regPW) ? 12'h000 : 12'hfff;
    wavTri   <= ((phase[23] ^ (regRingMod & iExtMSB)) ? ~phase[22:11] : phase[22:11]);
    wavNoise <= {lfsr[20], lfsr[18], lfsr[14], lfsr[11], lfsr[9], lfsr[5], lfsr[2], lfsr[0], 4'b0};
  end

  // waveform mixer
  // todo: the data sheet says the waveforms are "ANDed" together but that is
  //       not what happens. its much more complex than that, but for now lets
  //       do this and revise it later.
  reg [11:0] wavMix = 12'd0;
  assign oOut = wavMix;
  always @(posedge clk) begin
    wavMix <= (regSaw   ? wavSaw   : 12'h000) ^
              (regPulse ? wavPulse : 12'h000) ^
              (regTri   ? wavTri   : 12'h000) ^
              (regNoise ? wavNoise : 12'h000);
  end

  // address/data decoder
  always @(posedge clk) begin
    if (iWE) begin
      case (iAddr)
        (BASE_ADDR + 'h0): begin
          regFreq <= {regFreq[15:8], iData[7:0]};
        end
        (BASE_ADDR + 'h1): begin
          regFreq <= {iData[7:0], regFreq[7:0]};
        end
        (BASE_ADDR + 'h2): begin
          regPW <= {regPW[11:8], iData[7:0]};
        end
        (BASE_ADDR + 'h3): begin
          regPW <= {iData[3:0], regPW[7:0]};
        end
        (BASE_ADDR + 'h4): begin
          regNoise   <= iData[7];
          regPulse   <= iData[6];
          regSaw     <= iData[5];
          regTri     <= iData[4];
          regTest    <= iData[3];
          regRingMod <= iData[2];
          regSync    <= iData[1];
        end
      endcase
    end
  end
endmodule

module sid_voices (
    input         clk,      // master clock
    input         clkEn,    // asserted at 1Mhz
    input         iRst,     // reset
    input         iWE,      // data write
    input  [ 4:0] iAddr,    // address bus
    input  [ 7:0] iDataW,   // data bus
    output [11:0] oVoice0,  // voice 0 output
    output [11:0] oVoice1,  // voice 1 output
    output [11:0] oVoice2   // voice 2 output
);
  // voice 0
  wire msb0;
  sid_voice #(
      .BASE_ADDR('h0)
  ) voice0 (
      .clk    (clk),
      .clkEn  (clkEn),
      .iRst   (iRst),
      .iWE    (iWE),
      .iAddr  (iAddr),
      .iData  (iDataW),
      .iExtMSB(msb2),
      .oMSB   (msb0),
      .oOut   (oVoice0)
  );

  // voice 1
  wire msb1;
  sid_voice #(
      .BASE_ADDR('h7)
  ) voice1 (
      .clk    (clk),
      .clkEn  (clkEn),
      .iRst   (iRst),
      .iWE    (iWE),
      .iAddr  (iAddr),
      .iData  (iDataW),
      .iExtMSB(msb0),
      .oMSB   (msb1),
      .oOut   (oVoice1)
  );

  // voice 2
  wire msb2;
  sid_voice #(
      .BASE_ADDR('he)
  ) voice2 (
      .clk    (clk),
      .clkEn  (clkEn),
      .iRst   (iRst),
      .iWE    (iWE),
      .iAddr  (iAddr),
      .iData  (iDataW),
      .iExtMSB(msb1),
      .oMSB   (msb2),
      .oOut   (oVoice2)
  );
endmodule
