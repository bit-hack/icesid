`default_nettype none

//`define NO_MUACM

// 24Mhz to 1Mhz clock enable generator
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
      counter <= 5'd23;
    end else begin
      counter <= counter - 5'd1;
    end
  end
endmodule

module tx_decode(
    input        clk,
    input  [7:0] iTxData,
    input        iTxValid,
    output [7:0] oData,
    output [4:0] oAddr,
    output       oWE
);

  assign oData = busDataW;
  assign oAddr = busAddr;
  assign oWE   = busWE;

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
    if (iTxValid) begin
      if (iTxData[7] == 'b1) begin
        busWE <= 0;
        busAddr <= iTxData[6:2];
        busDataW <= {iTxData[1:0], busDataW[5:0]};
      end else begin
        busWE <= 1;
        busDataW <= {busDataW[7:6], iTxData[5:0]};
      end
    end else begin
      busWE <= 0;
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
    //
    inout  wire phi2,
    // sid chip select
    inout  wire cs_n,
    // sid read/write
    inout  wire rw,
    inout  wire pot_x,
    inout  wire pot_y
);

`ifdef TX_IFACE
  wire [4:0] bus_addr;
  wire [7:0] bus_wdata;
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

  // SID
  wire signed [15:0] sidOut;
  wire [7:0] bus_rdata;
  sid the_sid (
      .clk   (sys_clk),  // Master clock
      .clkEn (clk_en),  // 1Mhz enable
      .iWE   (bus_we),  // write data to sid addr
      .iAddr (bus_addr),  // SID address bus
      .iDataW(bus_wdata),  // C64 to SID
      .oDataR(bus_rdata),  // SID to C64
      .oOut  (sidOut),  // SID output
      .ioPotX(pot_x),
      .ioPotY(pot_y)
  );

  // I2S encoder
  wire i2sSampled;
  i2s i2s_tx (
      sys_clk,
      sidOut,
      i2s_sclk,
      i2s_lrclk,
      i2s_din,
      i2sSampled
  );

  // I2C setup
  i2c_state_machine ism (
      .scl_led(scl_led),
      .sda_btn(sda_btn),
      .btn    (),
      .led    (bus_we),
      .done   (),
      .clk    (sys_clk),
      .rst    (rst)
  );

  wire clk_en;
  sid_clk sidClkDiv(sys_clk, clk_en);

  wire [7:0] tx_data;
  wire       tx_valid;
  wire [7:0] bus_wdata;
  wire [4:0] bus_addr;
  wire       bus_we;
  tx_decode decode(sys_clk, tx_data, tx_valid, bus_wdata, bus_addr, bus_we);

`ifndef NO_MUACM
  // Local signals
  wire bootloader;
  reg  boot = 1'b0;
  // Instance
  muacm acm_I (
      .usb_dp       (usb_dp),
      .usb_dn       (usb_dn),
      .usb_pu       (usb_pu),
      .in_data      (8'h00),
      .in_last      (),
      .in_valid     (1'b0),
      .in_ready     (),
      .in_flush_now (1'b0),
      .in_flush_time(1'b1),
      .out_data     (tx_data),
      .out_last     (),
      .out_valid    (tx_valid),
      .out_ready    (1'b1),
      .bootloader   (bootloader),
      .clk          (clk_usb),
      .rst          (rst_usb)
  );

  // Warmboot
  always @(posedge clk_usb) begin
    boot <= boot | bootloader;
  end

  SB_WARMBOOT warmboot (
      .BOOT(boot),
      .S0  (1'b1),
      .S1  (1'b0)
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
  SB_GB rst_gbuf_I (
      .USER_SIGNAL_TO_GLOBAL_BUFFER(rst_i),
      .GLOBAL_BUFFER_OUTPUT(rst)
  );

  // Use HF OSC to generate USB clock
  wire clk_usb;
  wire rst_usb;
  sysmgr_hfosc sysmgr_I (
      .rst_in (rst),
      .clk_out(clk_usb),
      .rst_out(rst_usb)
  );
endmodule
