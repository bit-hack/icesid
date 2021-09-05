`default_nettype none

// 12Mhz to 1Mhz clock enable generator
module sid_clk (
    input  clk,
    output clkEn
);

  reg [4:0] counter;
  wire clkEn = (counter == 0);

  initial begin
    counter <= 0;
  end

  always @(posedge clk) begin
    if (clkEn) begin
      counter <= 5'd11;
    end else begin
      counter <= counter - 5'd1;
    end
  end
endmodule

module top (
    input        clk,  // 12Mhz
    output [3:0] PM3,  // I2S BUS
    input  [2:0] PM4   // SPI BUS
);

  // SPI slave
  reg [7:0] spiData;
  reg spiRecv;
  spi_slave spi (
      clk,  // system clock
      PM4[0],  // spi clock
      PM4[1],  // spi mosi
      PM4[2],  // spi chip select
      spiData,  // data out
      spiRecv
  );  // data received

  // input data decoder
  //
  // receive format:
  //    1AAA AADD   - address, data MSB
  //    0?DD DDDD   -          data LSB
  //
  reg [4:0] busAddr;  // latched address
  reg [7:0] busDataW;  // latched data
  reg       busWE;  // write signal
  always @(posedge clk) begin
    if (spiRecv) begin
      if (spiData[7] == 'b1) begin
        busWE <= 0;
        busAddr <= spiData[6:2];
        busDataW <= {spiData[1:0], busDataW[5:0]};
      end else begin
        busWE <= 1;
        busDataW <= {busDataW[7:6], spiData[5:0]};
      end
    end else begin
      busWE <= 0;
    end
  end

  // SID 1Mhz clock
  wire clkEn;
  sid_clk sid_clk_en (
      clk,
      clkEn
  );

  // CIC resampling filter
  wire signed [15:0] fltOut;
  cic_filter cicFilter (
      clk,
      clkEn,
      i2sSampled,
      sidOut,
      fltOut
  );

  // SID
  wire signed [15:0] sidOut;
  wire [7:0] busDataR;
  sid the_sid (
      .clk   (clk),  // Master clock
      .clkEn (clkEn),  // 1Mhz enable
      .iWE   (busWE),  // write data to sid addr
      .iAddr (busAddr),  // SID address bus
      .iDataW(busDataW),  // C64 to SID
      .oDataR(busDataR),  // SID to C64
      .oOut  (sidOut),  // SID output
      .ioPotX(),
      .ioPotY()
  );

  reg SCK;
  reg LRCLK;
  reg DATA;
  reg BCLK;
  assign PM3[0] = SCK;
  assign PM3[1] = BCLK;
  assign PM3[2] = DATA;
  assign PM3[3] = LRCLK;

  // instanciate the I2S encoder
  wire i2sSampled;
  i2s_master_t i2s (
      .CLK(clk),
      .SMP(sidOut),
      .SCK(SCK),
      .BCK(BCLK),
      .DIN(DATA),
      .LCK(LRCLK),
      .SAMPLED(i2sSampled)
  );

endmodule
