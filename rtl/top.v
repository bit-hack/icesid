`default_nettype none
`define NO_MUACM
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

module sid_biu(
        input        clk,
        input        d0,    // data lsb
        input        d1,
        input        d2,
        input        d3,
        input        d4,
        input        d5,
        input        d6,
        input        d7,    // data msb
        input        a0,    // addr lsb
        input        a1,
        input        a2,
        input        a3,
        input        a4,    // addr msb
        input        cs,    // chip seect
        input        rw,    // read / write
        input        phi2,
        output       oCLKen,
        output [7:0] oData,
        output [4:0] oAddr,
        output       oWR    // write strobe
    );

    initial begin
        bRW      <= 0;
        bCS      <= 0;
        bAddr[0] <= 0;
        bAddr[1] <= 0;
        bData[0] <= 0;
        bData[1] <= 0;
        bPHI2    <= 0;
    end

    // WR signal
    wire sidWrite = !bRW[1];    // r/w low
    wire sidRead  =  bRW[1];    // r/w high
    reg [1:0] bRW;
    always @(posedge clk) begin
        bRW <= { bRW[0], rw };
    end

    // chip select signal
    reg [1:0] bCS;              // cs active low
    always @(posedge clk) begin
        bCS <= { bCS[0], cs };
    end

    // register address
    reg [4:0] bAddr[2];
    always @(posedge clk) begin
        bAddr[0] <= { a4, a3, a2, a1, a0 };
        bAddr[1] <= bAddr[0];
    end

    // register data
    reg [7:0] bData[2];
    always @(posedge clk) begin
        bData[0] <= { d7, d6, d5, d4, d3, d2, d1, d0 };
        bData[1] <= bData[0];
    end

    // register phi2
    reg [2:0] bPHI2;
    always @(posedge clk) begin
        bPHI2 <= { bPHI2[1:0], phi2 };
    end

    assign oData  = bData[1];
    assign oAddr  = bAddr[1];
    // rising edge of phi2
    assign oCLKen =  bPHI2[1] & !bPHI2[2];
    // falling edge of phi2, WR low, CS low
    assign oWR    = !bPHI2[1] &  bPHI2[2] & sidWrite & !bCS[1];
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
    input wire d0,
    input wire d1,
    input wire d2,
    input wire d3,
    input wire d4,
    input wire d5,
    input wire d6,
    input wire d7,
    input wire a0,
    input wire a1,
    input wire a2,
    input wire a3,
    input wire a4,
    input wire phi2,
    input wire cs_n,
    input wire rw
`endif
);

`ifdef SPI_DRIVEN
    // SPI slave
    wire [7:0] spi_data;
    wire spi_recv;
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
    reg [4:0] laddr;  // latched address
    reg [7:0] ldata;  // latched data
    reg wr;           // write signal
    always @(posedge sys_clk) begin
        if (spi_recv) begin
            if (spi_data[7] == 'b1) begin
                wr <= 0;
                laddr <= spi_data[6:2];
                ldata <= { spi_data[1:0], ldata[5:0] };
            end else begin
                wr <= 1;
                ldata <= { ldata[7:6], spi_data[5:0] };
            end
        end else begin
            wr <= 0;
        end
    end

    // SID 1Mhz clock
    wire CLKen;
    sid_clk sid_clk_en(sys_clk, CLKen);
`endif
`ifdef BUS_DRIVEN
    wire CLKen;
    wire [4:0] laddr;  // latched address
    wire [7:0] ldata;  // latched data
    wire wr;           // write signal
    sid_biu bui(
        sys_clk,
        d0, d1, d2, d3, d4, d5, d6, d7,     // data pins
        a0, a1, a2, a3, a4,                 // addr pins
        cs_n,                               // cs
        rw,                                 // r/w
        phi2,                               // phi2
        CLKen,                              // sid clken out
        ldata,                              // data out
        laddr,                              // addr out
        wr                                  // write strobe
    );
`endif

    // SID
    sid the_sid(
           sys_clk,             // Master clock
           CLKen,               // 1Mhz enable
           wr,                  // write data to sid addr
           laddr,
           ldata,
           i2s_in);

    // I2S encoder
    wire signed [15:0] i2s_in;
    wire i2s_sampled;
    i2s i2s_tx(
        sys_clk,
        i2s_in,
        i2s_sclk,
        i2s_lrclk,
        i2s_din,
        i2s_sampled
    );

    // Little blinky
    wire led = CLKen;

    // I2C setup
    i2c_state_machine ism(
        .scl_led(scl_led),
        .sda_btn(sda_btn),
        .btn    (),
        .led    (led),
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
