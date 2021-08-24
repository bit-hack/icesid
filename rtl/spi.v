`default_nettype none

// a SPI slave device
module spi_slave(
    input CLK,            // system clock
    input SPI_CLK,        // spi clock
    input SPI_MOSI,       // spi mosi
    input SPI_CS,         // spi chip select
    output [7:0] DATA,    // data out
    output RECV           // data received
    );

  localparam NBITS = 4;

  reg [NBITS:0] sclk;
  reg [NBITS:0] smosi;
  reg [NBITS:0] scs;

  reg [7:0] sr;           // internal shift register
  reg [2:0] count;        // bit count
  reg avail;              // data available

  assign RECV = avail;
  assign DATA = sr;

  wire selected  = !scs[2];

  always @(posedge CLK) begin
    sclk  <= {  sclk[NBITS-1:0], SPI_CLK  };
    smosi <= { smosi[NBITS-1:0], SPI_MOSI };
    scs   <= {   scs[NBITS-1:0], SPI_CS   };
  end

  // clock filter
  reg clk_state;
  reg clk_rise;
  reg clk_fall;
  always @(posedge CLK) begin
    clk_rise <= 0;
    clk_fall <= 0;
    if (clk_state) begin
      if (~|sclk[NBITS:1]) begin
        clk_state <= 0;
        clk_fall  <= 1;
      end
    end else begin
      if (&sclk[NBITS:1]) begin
        clk_state <= 1;
        clk_rise  <= 1;
      end
    end
  end

  always @(posedge CLK) begin
    if (clk_rise) begin                // spi clock goes high
      sr <= { sr[6:0], smosi[2] };     // shift data in
    end
  end

  always @(posedge CLK) begin
    avail <= 0;
    if (clk_fall) begin                // spi clock goes low
      if (count == 0) begin            // if 8 bits shifted in
        avail <= 1;
      end
    end
  end

  always @(posedge CLK) begin
    if (selected) begin                // cs is low
      if (clk_rise) begin              // spi clock goes high
        count <= count + 'd1;
      end
    end else begin
      count <= 0;                      // reset counter
    end
  end
endmodule
