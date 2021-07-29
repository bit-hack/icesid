`default_nettype none
`timescale 1ns / 1ps

module sid_env(input CLK,           // master clock
               input TICK,          // asserted at 1Mhz
               input WR,            // data write
               input [4:0] ADDR,    // address bus
               input [7:0] DATA,    // data bus
               output [7:0] OUTPUT
               );

  // register base address
  parameter BASE_ADDR = 0;

  reg reg_gate;             // envelope gate
  reg [3:0] reg_att;        // envelope attack
  reg [3:0] reg_dec;        // envelope decay
  reg [3:0] reg_sus;        // envelope systain
  reg [3:0] reg_rel;        // envelope release

  initial begin
    reg_gate    = 0;
    reg_att     = 0;
    reg_dec     = 0;
    reg_sus     = 'hf;     // 100% sustain
    reg_rel     = 0;
  end
  
  // address/data decoder
  always @(posedge CLK) begin
    if (WR) begin
      case (ADDR)
      (BASE_ADDR+'h4): begin
          reg_gate    <= DATA[0];
      end
      (BASE_ADDR+'h5): begin reg_att <= DATA[7:4]; reg_dec <= DATA[3:0]; end
      (BASE_ADDR+'h6): begin reg_sus <= DATA[7:4]; reg_rel <= DATA[3:0]; end
      endcase
    end
  end
endmodule

module sid_voice(input CLK,         // master clock
                 input TICK,        // asserted at 1Mhz
                 input WR,          // data write
                 input [4:0] ADDR,  // address bus
                 input [7:0] DATA,  // data bus
                 // sync in
                 // sync out
                 // mix out
                 output [15:0] OUTPUT
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
    reg_freq    = 'h4495;  // 440Hz
    reg_pw      = 'h800;   // 50% duty
    reg_noise   = 0;       // mute noise
    reg_pulse   = 0;       // mute pulse
    reg_saw     = 1;       // mute sawtooth
    reg_tri     = 0;       // mute triangle
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
    if (TICK) begin
      phase <= phase + { 8'd0, reg_freq };
      phase_msb_lag <= phase[23];  // delayed MSB
    end
  end

  // noise generator (23bit LFSR)
  // todo: pass in the test bit
  // todo: noise lockup
  reg [22:0] lfsr;
  always @(posedge CLK) begin
    if (TICK) begin
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
    // todo: why is the saw not interpreted as a signed value?
    wav_saw   <=  phase[23:12];
    // todo: the pulse is clearly also being interpreted as a signed number
    wav_pulse <= (phase[23:12] >= reg_pw) ? 12'h800 : 12'h7ff;
    // todo: why do I have to flip the MSB for the triangle wave?
    wav_tri   <= (phase[23] ? phase[22:11] : ~phase[22:11]) ^ 12'b100000000000;
    // todo: why doesnt the noise channel work
    wav_noise <=  lfsr[22:11];
  end

  // waveform mixer
  // todo: the data sheet says the waveforms are "ANDed" together but that is
  //       not what happens. its much more complex than that, but for now lets
  //       do this and revise it later.
  reg [11:0] wav_mix;
  reg [15:0] voice_out;
  assign OUTPUT = voice_out;
  always @(posedge CLK) begin
    wav_mix <= (reg_saw   ? wav_saw   : 12'hfff) &
               (reg_pulse ? wav_pulse : 12'hfff) &
               (reg_tri   ? wav_tri   : 12'hfff) &
               (reg_noise ? wav_noise : 12'hfff);
    // for now just stuff the 12bit output into the upper bits
    voice_out <= { wav_mix, 4'd0 };
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

module sid(input CLK,     // Master clock
           input TICK,    // 1Mhz enable
           input WR,
           input [4:0] ADDR,
           input [7:0] DATA,
           output signed [15:0] OUTPUT);

  // instanciate voice 0
  wire [15:0] voice0_out;
  sid_voice #(.BASE_ADDR(0)) voice0(
    .CLK(CLK),
    .TICK(TICK),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(voice0_out));

  // instanciate envelope 0
  wire [7:0] env0_out;
  sid_env #(.BASE_ADDR(0)) env0(
    .CLK(CLK),
    .TICK(TICK),
    .WR(WR),
    .ADDR(ADDR),
    .DATA(DATA),
    .OUTPUT(env0_out));

  assign OUTPUT = voice0_out;

endmodule
