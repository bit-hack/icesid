`default_nettype none

// I2S (inter-IC Sound bus) master
//
// tested with PCM5102A
//
// note: this is very rough and ready.  currently it will sample SMP twice,
//       at different phases for the left and right channels. this creates
//       a stereo effect and should be fixed.
//
module i2s_master_t(
    input               CLK,   // 12Mhz input clock
    input signed [15:0] SMP,   // input sample data (twos-compliment format)
    output              SCK,
    output              BCK,
    output              DIN,
    output              LCK    // ~48Khz
    );

  reg [ 8:0] counter;
  reg [15:0] shift;
  reg out;

  assign SCK = CLK;           // (sck)           12 Mhz
  assign BCK = counter[1];    // (sck / 4)        3 Mhz
  assign LCK = counter[7];    // (sck / 256)  46875 Hz
  assign DIN = shift[15];     // (sck / 4)        3 Mhz

  initial begin
    counter <= 'd0;
    shift <= 'd0;
  end

  always @(posedge CLK) begin
    // on the falling edge of BCK
    if (counter[1:0] == 0) begin
      if (counter[6:2] == 1) begin
        // re-sample at on BCK after LRCK edge
        shift <= SMP;
      end else begin
        // shift out data
        shift <= { shift[14:0], 1'b0 };
      end
    end
    counter <= counter + 'd1;
  end
endmodule
