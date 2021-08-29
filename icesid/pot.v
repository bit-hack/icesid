`default_nettype none

module sid_pot(
	inout  wire       pot_pad,
	output reg  [7:0] pot_val,
	input  wire       clk_en,
	input  wire       clk
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
	reg        ctrl_discharging = 1'b0;	// Init for SIM only
	wire       ctrl_charging;

	// Counting
	reg  [7:0] cnt;


	// IOB
	// ---

	SB_IO #(
		.PIN_TYPE    (6'b1101_00),
		.PULLUP      (1'b0),
		.IO_STANDARD ("SB_LVCMOS")
	) pot_iob_I (
		.PACKAGE_PIN   (pot_pad),
		.INPUT_CLK     (clk),
		.OUTPUT_CLK    (clk),
		.OUTPUT_ENABLE (iob_oe),
		.D_OUT_0       (1'b0),
		.D_IN_0        (iob_i)
	);


	// Control
	// -------

	// Timer
	always @(posedge clk)
		if (clk_en)
			cyc_cnt <= {1'b0, cyc_cnt[7:0]} + 1;

	assign cyc_stb = cyc_cnt[8];

	// State tracking
	always @(posedge clk)
		if (clk_en)
			ctrl_discharging <= ctrl_discharging ^ cyc_stb;

	assign ctrl_charging = ~ctrl_discharging;

	// IO
	assign iob_oe = ctrl_discharging;


	// Counting
	// --------

	// Count all cycles input is 0 while charging
	always @(posedge clk)
		if (clk_en)
			cnt <= (cnt + {7'd0, ~iob_i}) & {8{ctrl_charging}};

	// Final value register
	always @(posedge clk)
		if (clk_en & ctrl_charging & cyc_stb)
			pot_val <= cnt;

endmodule // sid_pot
