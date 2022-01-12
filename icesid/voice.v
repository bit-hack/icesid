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
  reg [15:0] regFreq;  // frequency
  reg [11:0] regPW;  // pulse width
  reg        regNoise;  // wave-select noise enable
  reg        regPulse;  // wave-select pulse enable
  reg        regSaw;  // wave-select saw enable
  reg        regTri;  // wave-select triangle enable
  reg        regTest;  // test register
  reg        regRingMod;  // ring modulate
  reg        regSync;  // oscillator sync

  // initial conditions
  initial begin
    regFreq     = 0;
    regPW       = 0;
    regNoise    = 0;  // mute noise
    regPulse    = 0;  // mute pulse
    regSaw      = 0;  // mute sawtooth
    regTri      = 0;  // mute triangle
    regTest     = 0;
    regRingMod  = 0;
    regSync     = 0;
    noiseClkLag = 0;
    extMSBLag   = 0;
    // accumulator's even bits are high on powerup
    phase       = 24'h555555;
  end

  // phase accumulator
  // the oscillator frequency can be calculated as:
  //   Freq = (Mclk * reg_freq) / (16777215)
  assign oMSB = phase[23];
  reg extMSBLag;
  reg [23:0] phase;
  reg noiseClkLag;
  always @(posedge clk) begin
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

  initial begin
    // lfsr must be non zero to produce noise
    lfsr = 23'h7ffff8;
  end

  // noise generator (23bit LFSR)
  // todo: noise lockup
  reg [22:0] lfsr;
  always @(posedge clk) begin
    if (clkEn) begin
      // update noise when bit 19 goes high
      if (phase[noiseClkBit] && !noiseClkLag) begin
        lfsr <= {lfsr[21:0], (lfsr[22] ^ lfsr[21]) | regTest};
      end
    end
  end

  // waveform generators
  // note: at this stage all waveforms are unsigned with center point at 'h800
  reg [11:0] wavSaw;
  reg [11:0] wavPulse;
  reg [11:0] wavTri;
  reg [11:0] wavNoise;
  always @(posedge clk) begin
    wavSaw   <= phase[23:12];
    wavPulse <= (phase[23:12] >= regPW) ? 12'h000 : 12'hfff;
    wavTri   <= ((phase[23] ^ (regRingMod & iExtMSB)) ? phase[22:11] : ~phase[22:11]);
    wavNoise <= {lfsr[20], lfsr[18], lfsr[14], lfsr[11], lfsr[9], lfsr[5], lfsr[2], lfsr[0], 4'b0};
  end

  // waveform mixer
  // todo: the data sheet says the waveforms are "ANDed" together but that is
  //       not what happens. its much more complex than that, but for now lets
  //       do this and revise it later.
  // note: we invert here so that when all channels are off a zero is produced.
  reg [11:0] wavMix;
  assign oOut = ~wavMix;
  always @(posedge clk) begin
    wavMix <= (regSaw   ? wavSaw   : 12'hfff) &
              (regPulse ? wavPulse : 12'hfff) &
              (regTri   ? wavTri   : 12'hfff) &
              (regNoise ? wavNoise : 12'hfff);
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
      .clk(clk),
      .clkEn(clkEn),
      .iWE(iWE),
      .iAddr(iAddr),
      .iData(iDataW),
      .iExtMSB(msb2),
      .oMSB(msb0),
      .oOut(oVoice0)
  );

  // voice 1
  wire msb1;
  sid_voice #(
      .BASE_ADDR('h7)
  ) voice1 (
      .clk(clk),
      .clkEn(clkEn),
      .iWE(iWE),
      .iAddr(iAddr),
      .iData(iDataW),
      .iExtMSB(msb0),
      .oMSB(msb1),
      .oOut(oVoice1)
  );

  // voice 2
  wire msb2;
  sid_voice #(
      .BASE_ADDR('he)
  ) voice2 (
      .clk(clk),
      .clkEn(clkEn),
      .iWE(iWE),
      .iAddr(iAddr),
      .iData(iDataW),
      .iExtMSB(msb1),
      .oMSB(msb2),
      .oOut(oVoice2)
  );
endmodule
