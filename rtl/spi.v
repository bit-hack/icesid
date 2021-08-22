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

  reg [2:0] sclk;
  reg [2:0] smosi;
  reg [2:0] scs;

  reg [7:0] sr;           // internal shift register
  reg [2:0] count;        // bit count
  reg avail;              // data available

  assign RECV = avail;
  assign DATA = sr;

  //                old        new
  wire sclk_up   = !sclk[2] &  sclk[1];
  wire sclk_down =  sclk[2] & !sclk[1];

  wire selected  = !scs[2];

  always @(posedge CLK) begin
    sclk  <= {  sclk[1:0], SPI_CLK  };
    smosi <= { smosi[1:0], SPI_MOSI };
    scs   <= {   scs[1:0], SPI_CS   };
  end

  always @(posedge CLK) begin
    if (sclk_up) begin                 // spi clock goes high
      sr <= { sr[6:0], smosi[2] };     // shift data in
    end
  end

  always @(posedge CLK) begin
    avail <= 0;
    if (sclk_down) begin               // spi clock goes low
      if (count == 0) begin            // if 8 bits shifted in
        avail <= 1;
      end
    end
  end

  always @(posedge CLK) begin
    if (selected) begin                // cs is low
      if (sclk_up) begin               // spi clock goes high
        count <= count + 'd1;
      end
    end else begin
      count <= 0;                      // reset counter
    end
  end
endmodule
