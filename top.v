`default_nettype none
`timescale 1ns / 1ps

// I2S (inter-IC Sound bus) master
//
// tested with PCM5102A
//
// note: this is very rough and ready.  currently it will sample SMP twice,
//       at different phases for the left and right channels. this creates
//       a stereo effect and should be fixed.
//
module i2s_master_t(
      input CLK,          // 12Mhz input clock
      input [15:0] SMP,   // input sample data (twos-compliment format)
      output SCK,
      output BCK,
      output DIN,
      output LCK          // ~48Khz
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


module uart_rx(input clk,
               input rx,
               output reg [7:0] data,
               output reg recv);

  // baud rate 19200 @ 12Mhz
  // 12000000 / 19200 = 625

  // @1   = 1     - start
  // @312 = 137   - half cycle
  // @625 = 838
  // @626 = 652   - full cycle
  reg [9:0] lfsr;
  wire [9:0] lfsr_next = { lfsr[8:0], lfsr[9] ^ lfsr[6] };

  reg [3:0] count;  // remaining bits
  reg rx_;          // lag RX for edge detector

  initial begin
    lfsr      <= 1;
    data      <= 0; // idle state
    count     <= 0;
    rx_       <= 1;
    recv      <= 0;
    start     <= 0;
    sample    <= 0;
  end

  reg start;        // start bit has been received
  reg sample;       // sample rx line

  // update the lfsr counter
  always @(posedge clk) begin
    sample <= 0;
    if (start && count != 0) begin
      lfsr <= 'd137;    // start at CLK/2
    end else begin
      if (lfsr_next == 'd652) begin
        sample <= 1;
        lfsr <= 'd1;    // start at CLK/1
      end else begin
        lfsr <= lfsr_next;
      end
    end
  end

  // sample the data
  always @(posedge clk) begin
    start <= 0;
    // if we are idle
    if (count == 0) begin
      // if start bit has been detected
      if (rx_ == 1 && rx == 0) begin
        start <= 1;
        // 8 bits + start bit
        count <= 9;
      end
    end else begin
      // time to sample the data
      if (sample) begin
        // shift the data in
        data <= { rx, data[7:1] };
        // reduce count by one
        count <= count - 1;
      end
    end
    // update the edge detector
    rx_ <= rx;
  end

  always @(posedge clk) begin
    // if we have just sampled our last bit
    recv <= count == 1 && sample;
  end
endmodule

// 12Mhz to 1Mhz gate generator
module sid_clock(input CLK, output CLK1);
  reg [11:0] shift;
  assign CLK1 = shift[0];
  initial begin
    shift = 'h001;
  end
  always @(posedge CLK) begin
    // rotate left
    shift <= { shift[10:0], shift[11] };
  end
endmodule

module top(input CLK, input RX, output [7:0] PM3);

  // note: currently the SID outputs at 1Mhz but is being sampled at around
  //       44Khz this it will alias a lot. on the todo list is a low-pass
  //       filter to remove frequencies > 22Khz. This should be done prior to
  //       I2S conversion.

  // instanciate the uart receiver
  reg [7:0] data;
  reg recv;
  uart_rx uart(
    .clk(CLK),
    .rx(RX),
    .data(data),
    .recv(recv));

  // instanciate sid clock gate generator
  reg CLKen;
  sid_clock sid_clk(
    .CLK(CLK),
    .CLK1(CLKen));

  // instanciate the SID
  reg signed [15:0] sid_out;
  sid psg(
    .CLK(CLK),
    .CLKen(CLKen),
    .WR(wr),
    .ADDR(laddr),
    .DATA(ldata),
    .OUTPUT(sid_out));

  reg SCK;
  reg LRCLK;
  reg DATA;
  reg BCLK;
  assign PM3[0] = SCK;
  assign PM3[1] = BCLK;
  assign PM3[2] = DATA;
  assign PM3[3] = LRCLK;
  assign PM3[4:7] = 0;

  // note: shift signal down a bit so its not too loud (~2vac)
  wire [15:0] VAL = { {3{sid_out[15]}}, sid_out[14:2] };

  // instanciate the I2S encoder
  i2s_master_t i2s(
    .CLK(CLK),
    .SMP(VAL),
    .SCK(SCK),
    .BCK(BCLK),
    .DIN(DATA),
    .LCK(LRCLK));

  reg [4:0] laddr;  // latched address
  reg [7:0] ldata;  // latched data
  reg wr;           // write signal

  // input data decoder
  //
  // receive format:
  //    1AAA AADD   - address, data MSB
  //    0?DD DDDD   -          data LSB
  //
  always @(posedge CLK) begin
    if (recv) begin
      if (data[7] == 'b1) begin
        wr <= 0;
        laddr <= data[6:2];
        ldata <= { data[1:0], ldata[5:0] };
      end else begin
        wr <= 1;
        ldata <= { ldata[7:6], data[5:0] };
      end
    end else begin
      wr <= 0;
    end
  end
endmodule
