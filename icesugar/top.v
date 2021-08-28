`default_nettype none

// 12Mhz to 1Mhz clock enable generator
module sid_clk(
    input  CLK,
    output CLKen
    );

  reg [4:0] counter;
  wire CLKen = (counter == 0);

  initial begin
    counter <= 0;
  end

  always @(posedge CLK) begin
    if (CLKen) begin
      counter <= 5'd11;
    end else begin
      counter <= counter - 5'd1;
    end
  end
endmodule

// A very crappy filter
// y(n) = y(n-1) * 7/8 + x(n)
module simple_filter(
    input                CLK,
    input                CLKen,
    input  signed [15:0] in,
    output signed [15:0] out
    );

  reg signed [21:0] accum;
  assign out = accum[20:5];

  initial begin
    accum <= 0;
  end

  always @(posedge CLK) begin
    if (CLKen) begin
      accum <= (accum - (accum >>> 3)) + in;
    end
  end
endmodule

module top (
    input        CLK,       // 12Mhz
    output [3:0] PM3,       // I2S BUS
    input  [2:0] PM4        // SPI BUS
);

  // SPI slave
  reg [7:0] spi_data;
  reg spi_recv;
  spi_slave spi(
      CLK,                // system clock
      PM4[0],             // spi clock
      PM4[1],             // spi mosi
      PM4[2],             // spi chip select
      spi_data,           // data out
      spi_recv);          // data received

  // input data decoder
  //
  // receive format:
  //    1AAA AADD   - address, data MSB
  //    0?DD DDDD   -          data LSB
  //
  reg [4:0] bus_addr;     // latched address
  reg [7:0] bus_wdata;    // latched data
  reg bus_we;           // write signal
  always @(posedge CLK) begin
    if (spi_recv) begin
      if (spi_data[7] == 'b1) begin
        bus_we <= 0;
        bus_addr <= spi_data[6:2];
        bus_wdata <= { spi_data[1:0], bus_wdata[5:0] };
      end else begin
        bus_we <= 1;
        bus_wdata <= { bus_wdata[7:6], spi_data[5:0] };
      end
    end else begin
      bus_we <= 0;
    end
  end

  // SID 1Mhz clock
  wire clk_en;
  sid_clk sid_clk_en(CLK, clk_en);

  // very poor resampling filter
  wire signed [15:0] flt_out;
  simple_filter flt(CLK, clk_en, sid_out, flt_out);

  // SID
  wire signed [15:0] sid_out;
  wire [7:0] bus_rdata;
  sid the_sid(
    .CLK(CLK),               // Master clock
    .CLKen(clk_en),          // 1Mhz enable
    .WR(bus_we),             // write data to sid addr
    .ADDR(bus_addr),         // SID address bus
    .DATAW(bus_wdata),       // C64 to SID
    .DATAR(bus_rdata),       // SID to C64
    .OUTPUT(sid_out));       // SID output

  reg SCK;
  reg LRCLK;
  reg DATA;
  reg BCLK;
  assign PM3[0] = SCK;
  assign PM3[1] = BCLK;
  assign PM3[2] = DATA;
  assign PM3[3] = LRCLK;

  // note: shift signal down a bit so its not too loud (~2vac)
  wire signed [15:0] VAL = flt_out;

  // instanciate the I2S encoder
  i2s_master_t i2s(
    .CLK(CLK),
    .SMP(VAL),
    .SCK(SCK),
    .BCK(BCLK),
    .DIN(DATA),
    .LCK(LRCLK));

endmodule
