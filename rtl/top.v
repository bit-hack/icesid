`default_nettype none

//`define NO_MUACM
//`define SPI_DRIVEN
`define BUS_DRIVEN

module sid_clk(
    input CLK,
    output CLKen
    );

  reg [4:0] counter;
  wire CLKen = (counter == 0);

  initial begin
      counter <= 0;
  end

  always @(posedge CLK) begin
      if (CLKen) begin
          counter <= 5'd23;
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
    output signed [15:0] out,
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
    // I2S
    output wire i2s_din,
    input  wire i2s_dout,
    input  wire i2s_sclk,
    input  wire i2s_lrclk,
    // I2C (shared)
    inout  wire scl_led,
    inout  wire sda_btn,
    // USB
    inout  wire usb_dp,
    inout  wire usb_dn,
    output wire usb_pu,
    // Clock
    input  wire sys_clk,
`ifdef SPI_DRIVEN
    // SPI bus
    input wire d0,  // SCLK
    input wire d1,  // MOSI
    input wire d2   // CS
`endif
`ifdef BUS_DRIVEN
    // data bus
    inout  wire d0,
    inout  wire d1,
    inout  wire d2,
    inout  wire d3,
    inout  wire d4,
    inout  wire d5,
    inout  wire d6,
    inout  wire d7,
    // address bus
    inout  wire a0,
    inout  wire a1,
    inout  wire a2,
    inout  wire a3,
    inout  wire a4,
    // sid clock
    inout  wire phi2,
    // sid chip select
    inout  wire cs_n,
    // sid read/write
    inout  wire rw
`endif
);

`ifdef SPI_DRIVEN
    // SPI slave
    reg [7:0] spi_data;
    reg spi_recv;
    spi_slave spi(
        sys_clk,            // system clock
        d0,                 // spi clock
        d1,                 // spi mosi
        d2,                 // spi chip select
        spi_data,           // data out
        spi_recv            // data received
    );

    // input data decoder
    //
    // receive format:
    //    1AAA AADD   - address, data MSB
    //    0?DD DDDD   -          data LSB
    //
    reg [4:0] bus_addr;     // latched address
    reg [7:0] bus_wdata;    // latched data
    reg bus_we;           // write signal
    always @(posedge sys_clk) begin
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
    sid_clk sid_clk_en(sys_clk, clk_en);
`endif
`ifdef BUS_DRIVEN

    wire [4:0] bus_addr;
    wire [7:0] bus_wdata;
    reg  [7:0] bus_rdata;
    wire       bus_we;
    wire       clk_en;
    reg        bus_re;

    sid_bus_if bus (
        // Pads
        .pad_a({a4, a3, a2, a1, a0}),
        .pad_d({d7, d6, d5, d4, d3, d2, d1, d0}),
        .pad_r_wn(rw),
        .pad_csn(cs_n),
        .pad_phi2(phi2),
        // Internal bus
        .bus_addr(bus_addr),
        .bus_rdata(bus_rdata),  // sid to c64
        .bus_wdata(bus_wdata),  // c64 to sid
        .bus_we(bus_we),
        .clk_en(clk_en),
        // Clock
        .clk(sys_clk),
        .rst(rst)
    );
`endif

    wire signed [15:0] flt_out;
    simple_filter flt(sys_clk, clk_en, sid_out, flt_out);

    // SID
    wire signed [15:0] sid_out;
    sid the_sid(
           sys_clk,             // Master clock
           clk_en,              // 1Mhz enable
           bus_we,              // write data to sid addr
           bus_addr,
           bus_wdata,
           sid_out);

    // I2S encoder
    wire i2s_sampled;
    i2s i2s_tx(
        sys_clk,
        flt_out,
        i2s_sclk,
        i2s_lrclk,
        i2s_din,
        i2s_sampled
    );

    // I2C setup
    i2c_state_machine ism(
        .scl_led(scl_led),
        .sda_btn(sda_btn),
        .btn    (),
        .led    (bus_we),
        .done   (),
        .clk    (sys_clk),
        .rst    (rst)
    );

`ifndef NO_MUACM
    // Local signals
    wire bootloader;
    reg boot = 1'b0;

    // Instance
    muacm acm_I(
        .usb_dp       (usb_dp),
        .usb_dn       (usb_dn),
        .usb_pu       (usb_pu),
        .in_data      (8'h00),
        .in_last      (),
        .in_valid     (1'b0),
        .in_ready     (),
        .in_flush_now (1'b0),
        .in_flush_time(1'b1),
        .out_data     (),
        .out_last     (),
        .out_valid    (),
        .out_ready    (1'b1),
        .bootloader   (bootloader),
        .clk          (clk_usb),
        .rst          (rst_usb)
    );

    // Warmboot
    always @(posedge clk_usb) begin
        boot <= boot | bootloader;
    end

    SB_WARMBOOT warmboot(
        .BOOT (boot),
        .S0   (1'b1),
        .S1   (1'b0)
    );
`endif

    // Local reset
    reg [15:0] rst_cnt = 0;
    wire rst_i = ~rst_cnt[15];
    always @(posedge sys_clk) begin
        if (~rst_cnt[15]) begin
            rst_cnt <= rst_cnt + 1;
        end
    end

    // Promote reset signal to global buffer
    wire rst;
    SB_GB rst_gbuf_I(
        .USER_SIGNAL_TO_GLOBAL_BUFFER(rst_i),
        .GLOBAL_BUFFER_OUTPUT(rst)
    );

    // Use HF OSC to generate USB clock
    wire clk_usb;
    wire rst_usb;
    sysmgr_hfosc sysmgr_I(
        .rst_in (rst),
        .clk_out(clk_usb),
        .rst_out(rst_usb)
    );
endmodule
