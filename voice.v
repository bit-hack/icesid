`default_nettype none
`timescale 1ns / 1ps

module sid_voice(input CLK,         // master clock
                 input CLKen,       // asserted at 1Mhz
                 input WR,          // data write
                 input [4:0] ADDR,  // address bus
                 input [7:0] DATA,  // data bus
                 // sync in
                 // sync out
                 // mix out
                 output [11:0] OUTPUT
                 );

  // note: if we capture all the SID waveforms we could put them in a blockram
  //       and play them back via a lookup table. this would require
  //       (2^3 * 2^12) 12bit samples (32768). it seems like reSID does this
  //       but it only has 8bit samples? perhaps they were captured from osc3.
  //       this would be way more than the available 80Kbit block ram we have
  //       on the ice40up5k device however.

  // register base address
  parameter BASE_ADDR = 0;

  // voice related internal registers
  reg [15:0] reg_freq;      // frequency
  reg [11:0] reg_pw;        // pulse width
  reg reg_noise;            // wave-select noise enable
  reg reg_pulse;            // wave-select pulse enable
  reg reg_saw;              // wave-select saw enable
  reg reg_tri;              // wave-select triangle enable
  reg reg_test;             // test register
  reg reg_ringmod;          // ring modulate
  reg reg_sync;             // oscillator sync

  // initial conditions
  initial begin
    reg_freq    = 'h4495;  // 1Khz
    reg_pw      = 'h400;   // 25% duty
    reg_noise   = 0;       // mute noise
    reg_pulse   = 0;       // mute pulse
    reg_saw     = 0;       // mute sawtooth
    reg_tri     = 1;       // mute triangle
    reg_test    = 0;
    reg_ringmod = 0;
    reg_sync    = 0;
  end

  // phase accumulator
  // the oscillator frequency can be calculated as:
  //   Freq = (Mclk * reg_freq) / (16777215)
  reg [23:0] phase;
  reg phase_msb_lag;
  always @(posedge CLK) begin
    if (CLKen) begin
      phase <= phase + { 8'd0, reg_freq };
      phase_msb_lag <= phase[23];  // delayed MSB
    end
  end

  initial begin
    // lfsr must be non zero to produce noise
    lfsr = 1;
  end

  // noise generator (23bit LFSR)
  // todo: pass in the test bit
  // todo: noise lockup
  reg [22:0] lfsr;
  always @(posedge CLK) begin
    if (CLKen) begin
      // update noise when phase accumulator wraps
      if (phase[23] != phase_msb_lag) begin
        lfsr <= { lfsr[21:0], lfsr[22] ^ lfsr[21] };
      end
    end
  end

  // waveform generators
  // note: at this stage all waveforms are unsigned with center point at 'h800
  reg [11:0] wav_saw;
  reg [11:0] wav_pulse;
  reg [11:0] wav_tri;
  reg [11:0] wav_noise;
  always @(posedge CLK) begin
    wav_saw   <=  phase[23:12];
    wav_pulse <= (phase[23:12] >= reg_pw) ? 12'h000 : 12'hfff;
    wav_tri   <= (phase[23] ? phase[22:11] : ~phase[22:11]);
    wav_noise <=  lfsr[22:11];
  end

  // waveform mixer
  // todo: the data sheet says the waveforms are "ANDed" together but that is
  //       not what happens. its much more complex than that, but for now lets
  //       do this and revise it later.
  reg [11:0] wav_mix;
  assign OUTPUT = wav_mix;
  always @(posedge CLK) begin
    wav_mix <= (reg_saw   ? wav_saw   : 12'hfff) &
               (reg_pulse ? wav_pulse : 12'hfff) &
               (reg_tri   ? wav_tri   : 12'hfff) &
               (reg_noise ? wav_noise : 12'hfff);
  end

  // address/data decoder
  always @(posedge CLK) begin
    if (WR) begin
      case (ADDR)
      (BASE_ADDR+'h0): begin reg_freq <= { reg_freq[15:8], DATA[7:0] }; end
      (BASE_ADDR+'h1): begin reg_freq <= { DATA[7:0], reg_freq[7:0] };  end
      (BASE_ADDR+'h2): begin reg_pw   <= { reg_pw[11:8], DATA[7:0] };   end
      (BASE_ADDR+'h3): begin reg_pw   <= { DATA[3:0], reg_pw[7:0] };    end
      (BASE_ADDR+'h4): begin
          reg_noise   <= DATA[7];
          reg_pulse   <= DATA[6];
          reg_saw     <= DATA[5];
          reg_tri     <= DATA[4];
          reg_test    <= DATA[3];
          reg_ringmod <= DATA[2];
          reg_sync    <= DATA[1];
      end
      endcase
    end
  end
endmodule
