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

module filter15khz (
    input                clk,
    input                clkEn,
    input  signed [15:0] iIn,
    output signed [15:0] oOut
);

  reg signed [15:0] s0;
  reg signed [15:0] s1;
  reg signed [15:0] s2;
  assign oOut = s2;

  initial begin
    s0 <= 0;
    s1 <= 0;
    s2 <= 0;
  end

  wire signed [15:0] c0 = $signed(16'h099b);  // 15Khz
  wire signed [15:0] c1 = $signed(16'h0a86);  // 17.5Khz
  wire signed [15:0] c2 = $signed(16'h0b6e);  // 20Khz

  wire signed [31:0] t0 = c0 * (iIn - s0);
  wire signed [31:0] t1 = c1 * (s0  - s1);
  wire signed [31:0] t2 = c2 * (s1  - s2);

  always @(posedge clk) begin
    if (clkEn) begin
      s0 <= s0 + t0[30:15];
      s1 <= s1 + t1[30:15];
      s2 <= s2 + t2[30:15];
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

  wire signed [15:0] fltOut;
  filter15khz flt (
      .clk  (clk),
      .clkEn(clkEn),
      .iIn  (sidOut),
      .oOut (fltOut)
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
      .SMP(fltOut),
      .SCK(SCK),
      .BCK(BCLK),
      .DIN(DATA),
      .LCK(LRCLK),
      .SAMPLED(i2sSampled)
  );

endmodule
