// .___               _________.___________
// |   | ____  ____  /   _____/|   \______ \
// |   |/ ___\/ __ \ \_____  \ |   ||    |  \
// |   \  \__\  ___/ /        \|   ||    `   \
// |___|\___  >___  >_______  /|___/_______  /
//          \/    \/        \/             \/
`default_nettype none

`ifndef VERILATOR

module sid_pot (
    input  wire       clk,
    input  wire       clkEn,
    inout  wire       ioPotPad,
    output reg  [7:0] oPotVal
);

  // Signals
  // -------

  // IOB control
  wire       iob_oe;
  wire       iob_i;

  // Cycle timer (1:256 pulses)
  reg  [8:0] cyc_cnt;
  wire       cyc_stb;

  // Control
  reg        ctrl_discharging = 1'b0;  // Init for SIM only
  wire       ctrl_charging;

  // Counting
  reg  [7:0] cnt;

  // IOB
  // ---

  SB_IO #(
      .PIN_TYPE   (6'b1101_00),
      .PULLUP     (1'b0),
      .IO_STANDARD("SB_LVCMOS")
  ) pot_iob_I (
      .PACKAGE_PIN  (ioPotPad),
      .INPUT_CLK    (clk),
      .OUTPUT_CLK   (clk),
      .OUTPUT_ENABLE(iob_oe),
      .D_OUT_0      (1'b0),
      .D_IN_0       (iob_i)
  );

  // Control
  // -------

  // Timer
  always @(posedge clk) begin
    if (clkEn) begin
      cyc_cnt <= {1'b0, cyc_cnt[7:0]} + 1;
    end
  end

  assign cyc_stb = cyc_cnt[8];

  // State tracking
  always @(posedge clk) begin
    if (clkEn) begin
      ctrl_discharging <= ctrl_discharging ^ cyc_stb;
    end
  end

  assign ctrl_charging = ~ctrl_discharging;

  // IO
  assign iob_oe = ctrl_discharging;

  // Counting
  // --------

  // Count all cycles input is 0 while charging
  always @(posedge clk) begin
    if (clkEn) begin
      cnt <= (cnt + {7'd0, ~iob_i}) & {8{ctrl_charging}};
    end
  end

  // Final value register
  always @(posedge clk) begin
    if (clkEn & ctrl_charging & cyc_stb) begin
      oPotVal <= cnt;
    end
  end

endmodule  // sid_pot

`endif  // ifndef VERILATOR
